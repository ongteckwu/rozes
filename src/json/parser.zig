//! JSON Parser - DataFrame from JSON
//!
//! Supports 3 formats:
//! 1. Line-delimited JSON (NDJSON): `{"name": "Alice", "age": 30}\n{"name": "Bob", "age": 25}\n`
//! 2. JSON Array: `[{"name": "Alice", "age": 30}, {"name": "Bob", "age": 25}]`
//! 3. Columnar JSON: `{"name": ["Alice", "Bob"], "age": [30, 25]}`
//!
//! See docs/TODO.md Phase 5 for specifications.

const std = @import("std");
const DataFrame = @import("../core/dataframe.zig").DataFrame;
const types = @import("../core/types.zig");
const series_mod = @import("../core/series.zig");
const ValueType = types.ValueType;
const ColumnDesc = types.ColumnDesc;
const Series = series_mod.Series;

const MAX_JSON_SIZE: u32 = 1_000_000_000; // 1GB max
const MAX_COLUMNS: u32 = 10_000;
const MAX_ROWS: u32 = 4_000_000_000; // u32 limit
const MAX_NESTING_DEPTH: u32 = 32; // Prevent stack overflow

/// JSON parsing format
pub const JSONFormat = enum {
    /// Line-delimited JSON (NDJSON)
    /// Example: {"name": "Alice", "age": 30}\n{"name": "Bob", "age": 25}\n
    LineDelimited,

    /// JSON array of objects
    /// Example: [{"name": "Alice", "age": 30}, {"name": "Bob", "age": 25}]
    Array,

    /// Columnar JSON (most efficient for DataFrames)
    /// Example: {"name": ["Alice", "Bob"], "age": [30, 25]}
    Columnar,
};

/// JSON parsing options
pub const JSONOptions = struct {
    /// JSON format to parse
    format: JSONFormat = .LineDelimited,

    /// Automatically infer column types (default: true)
    type_inference: bool = true,

    /// Schema specification (overrides type inference if provided)
    schema: ?[]ColumnDesc = null,

    /// Validates JSON options
    pub fn validate(self: JSONOptions) !void {
        std.debug.assert(@intFromEnum(self.format) >= 0); // Valid enum value
        std.debug.assert(self.type_inference or self.schema != null); // Must have types

        if (self.schema) |sch| {
            if (sch.len == 0) return error.EmptySchema;
            if (sch.len > MAX_COLUMNS) return error.TooManyColumns;
        }
    }
};

/// JSON Parser state machine
pub const JSONParser = struct {
    allocator: std.mem.Allocator,
    buffer: []const u8,
    opts: JSONOptions,

    /// Initialize JSON parser
    pub fn init(
        allocator: std.mem.Allocator,
        buffer: []const u8,
        opts: JSONOptions,
    ) !JSONParser {
        std.debug.assert(buffer.len > 0); // Non-empty buffer
        std.debug.assert(buffer.len <= MAX_JSON_SIZE); // Size check

        try opts.validate();

        return JSONParser{
            .allocator = allocator,
            .buffer = buffer,
            .opts = opts,
        };
    }

    /// Parse JSON to DataFrame
    pub fn toDataFrame(self: *JSONParser) !DataFrame {
        std.debug.assert(self.buffer.len > 0); // Valid buffer
        std.debug.assert(self.buffer.len <= MAX_JSON_SIZE); // Size limit

        return switch (self.opts.format) {
            .LineDelimited => try self.parseNDJSON(),
            .Array => try self.parseArray(),
            .Columnar => try self.parseColumnar(),
        };
    }

    /// Parse NDJSON format
    fn parseNDJSON(self: *JSONParser) !DataFrame {
        std.debug.assert(self.buffer.len > 0); // Non-empty input
        std.debug.assert(self.opts.format == .LineDelimited); // Correct format

        // Phase 1: Split buffer by newlines and collect all JSON objects
        var objects = try std.ArrayList(std.json.Parsed(std.json.Value)).initCapacity(self.allocator, 100);
        defer {
            for (objects.items) |obj| obj.deinit();
            objects.deinit(self.allocator);
        }

        var line_start: u32 = 0;
        var line_count: u32 = 0;

        while (line_start < self.buffer.len and line_count < MAX_ROWS) : (line_count += 1) {
            // Find end of line
            var line_end = line_start;
            while (line_end < self.buffer.len) : (line_end += 1) {
                const char = self.buffer[line_end];
                if (char == '\n' or char == '\r') break;
            }

            // Extract line (skip empty lines)
            const line = std.mem.trim(u8, self.buffer[line_start..line_end], " \t\r\n");
            if (line.len > 0) {
                // Parse JSON object
                const parsed = std.json.parseFromSlice(
                    std.json.Value,
                    self.allocator,
                    line,
                    .{},
                ) catch |err| {
                    std.log.err("JSON parse error at line {}: {}", .{ line_count + 1, err });
                    return error.InvalidJSON;
                };

                // Validate it's an object
                if (parsed.value != .object) {
                    parsed.deinit();
                    return error.ExpectedObject;
                }

                try objects.append(self.allocator, parsed);
            }

            // Move to next line
            line_start = line_end + 1;
            if (line_end < self.buffer.len and self.buffer[line_end] == '\r' and
                line_start < self.buffer.len and self.buffer[line_start] == '\n')
            {
                line_start += 1; // Skip LF in CRLF
            }
        }

        std.debug.assert(line_count <= MAX_ROWS); // Bounded loop check

        if (objects.items.len == 0) {
            return error.NoDataRows;
        }

        // Phase 2: Discover all unique keys across all objects
        var key_set = std.StringHashMap(void).init(self.allocator);
        defer key_set.deinit();

        var obj_idx: u32 = 0;
        while (obj_idx < MAX_ROWS and obj_idx < objects.items.len) : (obj_idx += 1) {
            const obj = objects.items[obj_idx];
            var it = obj.value.object.iterator();
            while (it.next()) |entry| {
                try key_set.put(entry.key_ptr.*, {});
            }
        }
        std.debug.assert(obj_idx == objects.items.len); // Processed all objects

        // Collect keys in stable order
        var keys = try std.ArrayList([]const u8).initCapacity(self.allocator, key_set.count());
        defer keys.deinit(self.allocator);

        var key_it = key_set.iterator();
        while (key_it.next()) |entry| {
            try keys.append(self.allocator, entry.key_ptr.*);
        }

        if (keys.items.len == 0) {
            return error.NoColumns;
        }
        if (keys.items.len > MAX_COLUMNS) {
            return error.TooManyColumns;
        }

        // Phase 3: Infer column types
        const column_types = try self.inferColumnTypes(objects.items, keys.items);
        defer self.allocator.free(column_types);

        // Phase 4: Build DataFrame
        return try self.buildDataFrameFromObjects(objects.items, keys.items, column_types);
    }

    /// Parse JSON array format
    fn parseArray(self: *JSONParser) !DataFrame {
        std.debug.assert(self.buffer.len > 0); // Non-empty input
        std.debug.assert(self.opts.format == .Array); // Correct format

        // Parse entire JSON array
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            self.buffer,
            .{},
        );
        defer parsed.deinit();

        // Validate it's an array
        if (parsed.value != .array) {
            return error.ExpectedArray;
        }

        const array = parsed.value.array;
        if (array.items.len == 0) {
            return error.NoDataRows;
        }
        if (array.items.len > MAX_ROWS) {
            return error.TooManyRows;
        }

        // Create Parsed wrappers for each object (reusing the same arena)
        var objects = try std.ArrayList(std.json.Parsed(std.json.Value)).initCapacity(
            self.allocator,
            array.items.len,
        );
        defer objects.deinit(self.allocator);

        // Validate all items are objects and wrap them
        var row_idx: u32 = 0;
        while (row_idx < array.items.len and row_idx < MAX_ROWS) : (row_idx += 1) {
            const item = array.items[row_idx];
            if (item != .object) {
                return error.ExpectedObject;
            }
            // Create a Parsed wrapper (shares the arena from parsed)
            const wrapped = std.json.Parsed(std.json.Value){
                .arena = parsed.arena,
                .value = item,
            };
            try objects.append(self.allocator, wrapped);
        }
        std.debug.assert(row_idx <= MAX_ROWS); // Bounded loop check

        // Phase 2: Discover all unique keys across all objects
        var key_set = std.StringHashMap(void).init(self.allocator);
        defer key_set.deinit();

        var obj_idx: u32 = 0;
        while (obj_idx < MAX_ROWS and obj_idx < objects.items.len) : (obj_idx += 1) {
            const obj = objects.items[obj_idx];
            var it = obj.value.object.iterator();
            while (it.next()) |entry| {
                try key_set.put(entry.key_ptr.*, {});
            }
        }
        std.debug.assert(obj_idx == objects.items.len); // Processed all objects

        // Collect keys in stable order
        var keys = try std.ArrayList([]const u8).initCapacity(self.allocator, key_set.count());
        defer keys.deinit(self.allocator);

        var key_it = key_set.iterator();
        while (key_it.next()) |entry| {
            try keys.append(self.allocator, entry.key_ptr.*);
        }

        if (keys.items.len == 0) {
            return error.NoColumns;
        }
        if (keys.items.len > MAX_COLUMNS) {
            return error.TooManyColumns;
        }

        // Phase 3: Infer column types
        const column_types = try self.inferColumnTypes(objects.items, keys.items);
        defer self.allocator.free(column_types);

        // Phase 4: Build DataFrame
        return try self.buildDataFrameFromObjects(objects.items, keys.items, column_types);
    }

    /// Parse columnar JSON format
    fn parseColumnar(self: *JSONParser) !DataFrame {
        std.debug.assert(self.buffer.len > 0); // Non-empty input
        std.debug.assert(self.opts.format == .Columnar); // Correct format

        // Parse JSON object
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            self.buffer,
            .{},
        );
        // NOTE: We defer deinit until AFTER DataFrame is created, because
        // the column names point to strings owned by the parsed object.
        // DataFrame.create will duplicate these strings in its arena.
        errdefer parsed.deinit();

        // Validate it's an object
        if (parsed.value != .object) {
            return error.ExpectedObject;
        }

        const obj = parsed.value.object;
        if (obj.count() == 0) {
            return error.NoColumns;
        }
        if (obj.count() > MAX_COLUMNS) {
            return error.TooManyColumns;
        }

        // Collect column names and validate all values are arrays
        var col_names = try std.ArrayList([]const u8).initCapacity(self.allocator, obj.count());
        defer col_names.deinit(self.allocator);

        var row_count: ?u32 = null;

        var it = obj.iterator();
        while (it.next()) |entry| {
            try col_names.append(self.allocator, entry.key_ptr.*);

            // Validate value is an array
            if (entry.value_ptr.* != .array) {
                return error.ExpectedArray;
            }

            const arr = entry.value_ptr.array;

            // Check row count consistency
            const this_len: u32 = @intCast(arr.items.len);
            if (row_count) |expected| {
                if (this_len != expected) {
                    return error.InconsistentColumnLengths;
                }
            } else {
                row_count = this_len;
            }

            if (this_len > MAX_ROWS) {
                return error.TooManyRows;
            }
        }

        const final_row_count = row_count orelse 0;
        if (final_row_count == 0) {
            return error.NoDataRows;
        }

        // Infer column types from array elements
        var column_types = try std.ArrayList(ValueType).initCapacity(self.allocator, col_names.items.len);
        defer column_types.deinit(self.allocator);

        var col_idx: u32 = 0;
        while (col_idx < col_names.items.len and col_idx < MAX_COLUMNS) : (col_idx += 1) {
            const col_name = col_names.items[col_idx];
            const col_array = obj.get(col_name).?.array;

            // Collect observed types for this column
            var has_int = false;
            var has_float = false;
            var has_bool = false;
            var has_string = false;
            var has_null = false;

            var val_idx: u32 = 0;
            while (val_idx < col_array.items.len and val_idx < MAX_ROWS) : (val_idx += 1) {
                const value = col_array.items[val_idx];
                switch (value) {
                    .integer => has_int = true,
                    .float => has_float = true,
                    .number_string => has_float = true,
                    .bool => has_bool = true,
                    .string => has_string = true,
                    .null => has_null = true,
                    else => has_string = true,
                }
            }

            std.debug.assert(val_idx <= MAX_ROWS); // Bounded loop check

            // Determine type (same logic as inferColumnTypes)
            const col_type = if (has_string)
                ValueType.String
            else if (has_float or (has_int and has_float))
                ValueType.Float64
            else if (has_int)
                ValueType.Int64
            else if (has_bool)
                ValueType.Bool
            else
                ValueType.Null;

            try column_types.append(self.allocator, col_type);
        }

        std.debug.assert(col_idx <= MAX_COLUMNS); // Bounded loop check

        // Build DataFrame directly from columnar data
        const df = try self.buildDataFrameFromColumnar(col_names.items, column_types.items, obj, final_row_count);

        // Now that DataFrame has duplicated all strings, we can free the parsed JSON
        parsed.deinit();

        return df;
    }

    /// Infer column type from JSON value
    fn inferTypeFromValue(value: std.json.Value) ValueType {
        // Pre-condition: Value enum should be in valid range (0-6 for std.json.Value)
        const value_tag = @intFromEnum(std.meta.activeTag(value));
        std.debug.assert(value_tag >= 0); // Pre-condition #1: Valid enum tag
        std.debug.assert(value_tag <= 6); // Pre-condition #2: Within std.json.Value range

        return switch (value) {
            .integer => .Int64,
            .float => .Float64,
            .number_string => .Float64, // Parse number strings as floats
            .bool => .Bool,
            .string => .String,
            .null => .Null,
            .array, .object => .String, // Serialize complex types as strings
        };
    }

    /// Infer column types from JSON objects
    fn inferColumnTypes(
        self: *JSONParser,
        objects: []std.json.Parsed(std.json.Value),
        keys: []const []const u8,
    ) ![]ValueType {
        std.debug.assert(objects.len > 0); // Need at least one object
        std.debug.assert(keys.len > 0); // Need at least one column
        std.debug.assert(keys.len <= MAX_COLUMNS); // Reasonable column count

        const column_types = try self.allocator.alloc(ValueType, keys.len);

        // For each column, scan values to determine type
        var col_idx: u32 = 0;
        while (col_idx < keys.len and col_idx < MAX_COLUMNS) : (col_idx += 1) {
            const key = keys[col_idx];

            // Collect observed types for this column
            var has_int = false;
            var has_float = false;
            var has_bool = false;
            var has_string = false;
            var has_null = false;

            var obj_idx: u32 = 0;
            while (obj_idx < objects.len and obj_idx < MAX_ROWS) : (obj_idx += 1) {
                const obj = objects[obj_idx].value.object;
                if (obj.get(key)) |value| {
                    switch (value) {
                        .integer => has_int = true,
                        .float => has_float = true,
                        .bool => has_bool = true,
                        .string => has_string = true,
                        .null => has_null = true,
                        else => has_string = true, // Treat complex types as string
                    }
                }
            }

            std.debug.assert(obj_idx <= MAX_ROWS); // Bounded loop check

            // Determine most specific type that fits all values
            if (has_string) {
                column_types[col_idx] = .String; // String supersedes all
            } else if (has_float or (has_int and has_float)) {
                column_types[col_idx] = .Float64; // Float can represent integers
            } else if (has_int) {
                column_types[col_idx] = .Int64;
            } else if (has_bool) {
                column_types[col_idx] = .Bool;
            } else {
                column_types[col_idx] = .Null; // All null column
            }
        }

        std.debug.assert(col_idx <= MAX_COLUMNS); // Bounded loop check
        return column_types;
    }

    /// Build DataFrame from JSON objects
    fn buildDataFrameFromObjects(
        self: *JSONParser,
        objects: []std.json.Parsed(std.json.Value),
        keys: []const []const u8,
        column_types: []const ValueType,
    ) !DataFrame {
        std.debug.assert(objects.len > 0); // Need data
        std.debug.assert(keys.len > 0); // Need columns
        std.debug.assert(keys.len == column_types.len); // Matching lengths

        // Create column descriptors
        var col_descs = try std.ArrayList(ColumnDesc).initCapacity(self.allocator, keys.len);
        defer col_descs.deinit(self.allocator);

        var col_idx: u32 = 0;
        while (col_idx < keys.len and col_idx < MAX_COLUMNS) : (col_idx += 1) {
            try col_descs.append(self.allocator, ColumnDesc.init(keys[col_idx], column_types[col_idx], col_idx));
        }

        std.debug.assert(col_idx <= MAX_COLUMNS); // Bounded loop check

        // Create DataFrame
        const row_count: u32 = @intCast(objects.len);
        var df = try DataFrame.create(self.allocator, col_descs.items, row_count);
        errdefer df.deinit();

        // Fill data row by row
        var row_idx: u32 = 0;
        while (row_idx < objects.len and row_idx < MAX_ROWS) : (row_idx += 1) {
            const obj = objects[row_idx].value.object;

            col_idx = 0;
            while (col_idx < keys.len and col_idx < MAX_COLUMNS) : (col_idx += 1) {
                const key = keys[col_idx];
                const col_type = column_types[col_idx];

                // Get value or use default
                const value = obj.get(key) orelse std.json.Value{ .null = {} };

                try self.appendValueToColumn(&df.columns[col_idx], value, col_type, row_idx);
            }
        }

        std.debug.assert(row_idx <= MAX_ROWS); // Bounded loop check
        df.row_count = row_count;

        return df;
    }

    /// Build DataFrame from columnar JSON data
    fn buildDataFrameFromColumnar(
        self: *JSONParser,
        col_names: []const []const u8,
        column_types: []const ValueType,
        obj: std.json.ObjectMap,
        row_count: u32,
    ) !DataFrame {
        std.debug.assert(col_names.len > 0); // Need columns
        std.debug.assert(col_names.len == column_types.len); // Matching lengths
        std.debug.assert(row_count > 0); // Need rows

        // Create column descriptors
        var col_descs = try std.ArrayList(ColumnDesc).initCapacity(self.allocator, col_names.len);
        defer col_descs.deinit(self.allocator);

        var col_idx: u32 = 0;
        while (col_idx < col_names.len and col_idx < MAX_COLUMNS) : (col_idx += 1) {
            try col_descs.append(self.allocator, ColumnDesc.init(col_names[col_idx], column_types[col_idx], col_idx));
        }

        std.debug.assert(col_idx <= MAX_COLUMNS); // Bounded loop check

        // Create DataFrame
        var df = try DataFrame.create(self.allocator, col_descs.items, row_count);
        errdefer df.deinit();

        // Fill data column by column (already in columnar format!)
        col_idx = 0;
        while (col_idx < col_names.len and col_idx < MAX_COLUMNS) : (col_idx += 1) {
            const col_name = col_names[col_idx];
            const col_type = column_types[col_idx];
            const col_array = obj.get(col_name).?.array;

            var row_idx: u32 = 0;
            while (row_idx < row_count and row_idx < MAX_ROWS) : (row_idx += 1) {
                const value = col_array.items[row_idx];
                try self.appendValueToColumn(&df.columns[col_idx], value, col_type, row_idx);
            }

            std.debug.assert(row_idx <= MAX_ROWS); // Bounded loop check
        }

        std.debug.assert(col_idx <= MAX_COLUMNS); // Bounded loop check
        df.row_count = row_count;

        return df;
    }

    /// Append JSON value to column
    fn appendValueToColumn(
        self: *JSONParser,
        column: *Series,
        value: std.json.Value,
        expected_type: ValueType,
        row_idx: u32,
    ) !void {
        std.debug.assert(row_idx < MAX_ROWS); // Valid row index
        _ = self;

        switch (expected_type) {
            .Int64 => {
                const data = column.data.Int64;
                data[row_idx] = switch (value) {
                    .integer => |v| v,
                    .float => |v| @intFromFloat(v),
                    .null => 0,
                    else => 0, // Default for incompatible types
                };
            },
            .Float64 => {
                const data = column.data.Float64;
                data[row_idx] = switch (value) {
                    .float => |v| v,
                    .integer => |v| @floatFromInt(v),
                    .null => std.math.nan(f64),
                    else => std.math.nan(f64), // NaN for incompatible types
                };
            },
            .Bool => {
                const data = column.data.Bool;
                data[row_idx] = switch (value) {
                    .bool => |v| v,
                    .null => false,
                    else => false, // Default for incompatible types
                };
            },
            .String => {
                // For String columns, we need to convert the value to string
                // This will be handled when String column support is complete
                // For now, skip (will be implemented in Day 2/3)
                std.debug.assert(column.value_type == .String);
            },
            .Null => {
                // Null columns don't store data
            },
            else => return error.UnsupportedType,
        }
    }

    /// Clean up parser resources
    pub fn deinit(self: *JSONParser) void {
        std.debug.assert(self.buffer.len <= MAX_JSON_SIZE); // Invariant check
        std.debug.assert(self.buffer.len > 0); // Buffer exists
        // Nothing to cleanup (buffer is owned by caller)
    }
};

// Tests
test "JSONOptions.validate accepts valid options" {
    const opts = JSONOptions{};
    try opts.validate();
}

test "JSONOptions.validate rejects empty schema" {
    const testing = std.testing;

    const opts = JSONOptions{
        .type_inference = false,
        .schema = &[_]ColumnDesc{}, // Empty schema
    };

    try testing.expectError(error.EmptySchema, opts.validate());
}

test "JSONParser.init accepts valid JSON" {
    const allocator = std.testing.allocator;
    const json = "{\"name\": \"Alice\", \"age\": 30}";

    var parser = try JSONParser.init(allocator, json, .{});
    defer parser.deinit();

    std.testing.expect(parser.buffer.len > 0) catch unreachable;
}

test "JSONParser.toDataFrame works for NDJSON" {
    const allocator = std.testing.allocator;
    const json = "{\"name\": \"Alice\", \"age\": 30}\n";

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    // Now NDJSON parser is implemented!
    var df = try parser.toDataFrame();
    defer df.deinit();

    try std.testing.expectEqual(@as(u32, 1), df.row_count);
}

test "JSONParser.toDataFrame works for Array" {
    const allocator = std.testing.allocator;
    const json = "[{\"name\": \"Alice\", \"age\": 30}]";

    var parser = try JSONParser.init(allocator, json, .{ .format = .Array });
    defer parser.deinit();

    // Now Array parser is implemented!
    var df = try parser.toDataFrame();
    defer df.deinit();

    try std.testing.expectEqual(@as(u32, 1), df.row_count);
}

test "JSONParser.toDataFrame works for Columnar" {
    const allocator = std.testing.allocator;
    const json = "{\"name\": [\"Alice\"], \"age\": [30]}";

    var parser = try JSONParser.init(allocator, json, .{ .format = .Columnar });
    defer parser.deinit();

    // Now Columnar parser is implemented!
    var df = try parser.toDataFrame();
    defer df.deinit();

    try std.testing.expectEqual(@as(u32, 1), df.row_count);
}

test "inferTypeFromValue detects types correctly" {
    const testing = std.testing;

    try testing.expectEqual(ValueType.Int64, JSONParser.inferTypeFromValue(.{ .integer = 42 }));
    try testing.expectEqual(ValueType.Float64, JSONParser.inferTypeFromValue(.{ .float = 3.14 }));
    try testing.expectEqual(ValueType.Bool, JSONParser.inferTypeFromValue(.{ .bool = true }));
    try testing.expectEqual(ValueType.String, JSONParser.inferTypeFromValue(.{ .string = "test" }));
    try testing.expectEqual(ValueType.Null, JSONParser.inferTypeFromValue(.null));
}
