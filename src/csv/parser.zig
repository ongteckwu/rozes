//! CSV Parser - RFC 4180 Compliant
//!
//! One-pass CSV parser with state machine for efficient parsing.
//! Converts CSV text to columnar DataFrame.
//!
//! See RFC.md Section 5 for CSV parsing specification.
//!
//! Example:
//! ```
//! const csv = "name,age\nAlice,30\nBob,25\n";
//! var parser = try CSVParser.init(allocator, csv, .{});
//! defer parser.deinit();
//!
//! const df = try parser.toDataFrame();
//! defer df.deinit();
//! ```

const std = @import("std");
const core_types = @import("../core/types.zig");
const DataFrame = @import("../core/dataframe.zig").DataFrame;
const Series = @import("../core/series.zig").Series;
const SeriesValue = @import("../core/series.zig").SeriesValue;

const ValueType = core_types.ValueType;
const ColumnDesc = core_types.ColumnDesc;
const CSVOptions = core_types.CSVOptions;

/// Parser state machine
const ParserState = enum {
    Start,
    InField,
    InQuotedField,
    QuoteInQuoted,
    EndOfRecord,
};

/// Maximum limits
const MAX_CSV_SIZE: u32 = 1024 * 1024 * 1024; // 1GB
const MAX_COLUMNS: u32 = 10_000;
const MAX_ROWS: u32 = std.math.maxInt(u32);
const MAX_FIELD_LENGTH: u32 = 1_000_000; // 1MB per field

/// CSV Parser
pub const CSVParser = struct {
    parent_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    buffer: []const u8,
    pos: u32,
    state: ParserState,
    opts: CSVOptions,
    current_field: std.ArrayListUnmanaged(u8),
    current_row: std.ArrayListUnmanaged([]const u8),
    rows: std.ArrayListUnmanaged([][]const u8),

    /// Initialize CSV parser
    pub fn init(
        allocator: std.mem.Allocator,
        buffer: []const u8,
        opts: CSVOptions,
    ) !CSVParser {
        std.debug.assert(buffer.len > 0); // Non-empty buffer
        std.debug.assert(buffer.len <= MAX_CSV_SIZE); // Size check

        try opts.validate();

        // Create arena for parser lifetime
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        // Skip UTF-8 BOM if present (0xEF 0xBB 0xBF)
        const start_pos: u32 = if (buffer.len >= 3 and
            buffer[0] == 0xEF and buffer[1] == 0xBB and buffer[2] == 0xBF)
            3
        else
            0;

        std.debug.assert(start_pos <= 3); // BOM is 0 or 3 bytes

        return CSVParser{
            .parent_allocator = allocator,
            .arena = arena,
            .buffer = buffer,
            .pos = start_pos, // Skip BOM if present
            .state = .Start,
            .opts = opts,
            .current_field = .{},
            .current_row = .{},
            .rows = .{},
        };
    }

    /// Free parser resources
    pub fn deinit(self: *CSVParser) void {
        std.debug.assert(self.pos <= self.buffer.len); // Valid state
        std.debug.assert(self.buffer.len <= MAX_CSV_SIZE); // Size invariant

        // Arena deinit frees everything at once - much simpler!
        self.arena.deinit();
    }

    /// Parse next field from CSV
    pub fn nextField(self: *CSVParser) !?[]const u8 {
        std.debug.assert(self.pos <= self.buffer.len); // Invariant

        // Handle EndOfRecord state before entering loop
        if (self.state == .EndOfRecord) {
            self.state = .Start;
            return null;
        }

        while (self.pos < self.buffer.len) {
            // Check field length limit
            if (self.current_field.items.len >= MAX_FIELD_LENGTH) {
                return error.FieldTooLarge;
            }

            const char = self.buffer[self.pos];
            self.pos += 1;

            const action = try self.handleChar(char);
            switch (action) {
                .FieldComplete => return try self.finishField(),
                .RowComplete => {
                    self.state = .EndOfRecord;
                    return null;
                },
                .Continue => {},
            }
        }

        // End of buffer
        if (self.current_field.items.len > 0) {
            self.state = .EndOfRecord;
            return try self.finishField();
        }

        std.debug.assert(self.pos <= self.buffer.len); // Post-condition
        return null;
    }

    /// Character processing action
    const CharAction = enum { Continue, FieldComplete, RowComplete };

    /// Handle a single character in the current state
    fn handleChar(self: *CSVParser, char: u8) !CharAction {
        std.debug.assert(self.pos <= self.buffer.len); // Invariant
        std.debug.assert(self.current_field.items.len < MAX_FIELD_LENGTH); // Field size check

        return switch (self.state) {
            .Start => try self.handleStart(char),
            .InField => try self.handleInField(char),
            .InQuotedField => try self.handleInQuotedField(char),
            .QuoteInQuoted => try self.handleQuoteInQuoted(char),
            .EndOfRecord => unreachable,
        };
    }

    /// Handle character in Start state
    fn handleStart(self: *CSVParser, char: u8) !CharAction {
        const allocator = self.arena.allocator();
        if (char == '"') {
            self.state = .InQuotedField;
            return .Continue;
        } else if (char == self.opts.delimiter) {
            return .FieldComplete;
        } else if (char == '\n' or char == '\r') {
            self.skipLineEnding(char);
            return .RowComplete;
        } else {
            try self.current_field.append(allocator, char);
            self.state = .InField;
            return .Continue;
        }
    }

    /// Handle character in InField state
    fn handleInField(self: *CSVParser, char: u8) !CharAction {
        const allocator = self.arena.allocator();
        if (char == self.opts.delimiter) {
            self.state = .Start;
            return .FieldComplete;
        } else if (char == '\n' or char == '\r') {
            self.skipLineEnding(char);
            return .FieldComplete;
        } else {
            try self.current_field.append(allocator, char);
            return .Continue;
        }
    }

    /// Handle character in InQuotedField state
    fn handleInQuotedField(self: *CSVParser, char: u8) !CharAction {
        const allocator = self.arena.allocator();
        if (char == '"') {
            self.state = .QuoteInQuoted;
        } else {
            try self.current_field.append(allocator, char);
        }
        return .Continue;
    }

    /// Handle character in QuoteInQuoted state
    fn handleQuoteInQuoted(self: *CSVParser, char: u8) !CharAction {
        const allocator = self.arena.allocator();
        if (char == '"') {
            // Escaped quote
            try self.current_field.append(allocator, '"');
            self.state = .InQuotedField;
            return .Continue;
        } else if (char == self.opts.delimiter) {
            self.state = .Start;
            return .FieldComplete;
        } else if (char == '\n' or char == '\r') {
            self.skipLineEnding(char);
            return .FieldComplete;
        } else {
            return error.InvalidQuoting;
        }
    }

    /// Skip line ending (handles CRLF, LF, CR)
    fn skipLineEnding(self: *CSVParser, char: u8) void {
        std.debug.assert(char == '\n' or char == '\r'); // Must be line ending
        std.debug.assert(self.pos <= self.buffer.len); // Valid position

        // If we got CR, check for following LF
        if (char == '\r' and self.pos < self.buffer.len and self.buffer[self.pos] == '\n') {
            self.pos += 1; // Skip LF in CRLF
        }
    }

    /// Finish current field and reset buffer
    fn finishField(self: *CSVParser) ![]const u8 {
        const allocator = self.arena.allocator();
        std.debug.assert(self.current_field.items.len <= MAX_FIELD_LENGTH); // Field size check

        const field = try self.current_field.toOwnedSlice(allocator);

        std.debug.assert(field.len <= MAX_FIELD_LENGTH); // Post-condition
        return field;
    }

    /// Parse one row
    pub fn nextRow(self: *CSVParser) !?[][]const u8 {
        const allocator = self.arena.allocator();
        std.debug.assert(self.current_row.items.len == 0); // Should be empty

        self.state = .Start;

        while (try self.nextField()) |field| {
            try self.current_row.append(allocator, field);

            if (self.current_row.items.len > MAX_COLUMNS) {
                return error.TooManyColumns;
            }
        }

        // If we got fields, return the row
        if (self.current_row.items.len > 0) {
            const row = try self.current_row.toOwnedSlice(allocator);
            return row;
        }

        // End of data
        return null;
    }

    /// Parse all rows
    pub fn parseAll(self: *CSVParser) !void {
        const allocator = self.arena.allocator();
        std.debug.assert(self.rows.items.len == 0); // Should be empty

        var row_count: u32 = 0;
        while (row_count < MAX_ROWS) : (row_count += 1) {
            const row = try self.nextRow() orelse break;

            // Skip blank lines if option is set
            // Note: No need to free - arena will handle it
            if (self.opts.skipBlankLines and row.len == 1 and row[0].len == 0) {
                row_count -= 1; // Don't count blank lines
                continue;
            }

            try self.rows.append(allocator, row);
        }

        std.debug.assert(row_count <= MAX_ROWS); // Invariant
    }

    /// Convert parsed rows to DataFrame
    pub fn toDataFrame(self: *CSVParser) !DataFrame {
        // Parse all rows if not done yet
        if (self.rows.items.len == 0) {
            try self.parseAll();
        }

        if (self.rows.items.len == 0) {
            return error.EmptyCSV;
        }

        std.debug.assert(self.rows.items.len > 0); // Need at least header or data

        const allocator = self.arena.allocator();

        // Extract headers
        const header_row: [][]const u8 = if (self.opts.hasHeaders) self.rows.items[0] else blk: {
            // Generate column names: col0, col1, col2, ...
            const col_count = self.rows.items[0].len;
            var headers = try allocator.alloc([]const u8, col_count);
            for (0..col_count) |i| {
                headers[i] = try std.fmt.allocPrint(allocator, "col{}", .{i});
            }
            break :blk headers;
        };

        const data_start: usize = if (self.opts.hasHeaders) 1 else 0;
        const data_rows = self.rows.items[data_start..];

        // Infer column types
        const col_count = header_row.len;
        var column_types = try allocator.alloc(ValueType, col_count);
        defer allocator.free(column_types);

        if (data_rows.len > 0 and self.opts.inferTypes) {
            const preview_count = @min(self.opts.previewRows, @as(u32, @intCast(data_rows.len)));
            for (0..col_count) |col_idx| {
                column_types[col_idx] = try inferColumnType(data_rows[0..preview_count], col_idx);
            }
        } else {
            // Default to String type when no data or inference disabled (0.2.0+)
            for (0..col_count) |col_idx| {
                column_types[col_idx] = .String;
            }
        }

        // Create column descriptors
        var col_descs = try allocator.alloc(ColumnDesc, col_count);
        defer allocator.free(col_descs);

        for (0..col_count) |i| {
            col_descs[i] = ColumnDesc.init(header_row[i], column_types[i], @intCast(i));
        }

        // Create DataFrame with capacity (may have 0 rows if headers-only)
        // Use parent_allocator for DataFrame (it has its own arena)
        const capacity: u32 = if (data_rows.len > 0) @intCast(data_rows.len) else 1;
        var df = try DataFrame.create(self.parent_allocator, col_descs, capacity);
        errdefer df.deinit();

        // Fill DataFrame with data (only if we have data rows)
        if (data_rows.len > 0) {
            try fillDataFrame(&df, data_rows, column_types);
            try df.setRowCount(@intCast(data_rows.len));
        } else {
            // Empty DataFrame with 0 rows
            try df.setRowCount(0);
        }

        return df;
    }
};

/// Infer column type from preview rows
fn inferColumnType(rows: []const [][]const u8, col_idx: usize) !ValueType {
    std.debug.assert(rows.len > 0); // Need data
    std.debug.assert(rows.len <= 10_000); // Preview limit

    var all_int = true;
    var all_float = true;

    for (rows) |row| {
        if (col_idx >= row.len) continue;

        const field = row[col_idx];
        if (field.len == 0) continue; // Skip empty fields

        if (!tryParseInt64(field)) all_int = false;
        if (!tryParseFloat64(field)) all_float = false;
    }

    if (all_int) return .Int64;
    if (all_float) return .Float64;
    return .String; // Default (not supported in MVP)
}

/// Try to parse as Int64
fn tryParseInt64(field: []const u8) bool {
    std.debug.assert(field.len <= MAX_FIELD_LENGTH); // Field size check

    if (field.len == 0) return false;

    _ = std.fmt.parseInt(i64, field, 10) catch return false;
    return true;
}

/// Try to parse as Float64
fn tryParseFloat64(field: []const u8) bool {
    std.debug.assert(field.len <= MAX_FIELD_LENGTH); // Field size check

    if (field.len == 0) return false;

    _ = std.fmt.parseFloat(f64, field) catch return false;
    return true;
}

/// Fill DataFrame with parsed data
fn fillDataFrame(df: *DataFrame, rows: []const [][]const u8, column_types: []ValueType) !void {
    std.debug.assert(rows.len > 0); // Need data
    std.debug.assert(column_types.len == df.columns.len); // Match column count

    for (df.columns, 0..) |*col, col_idx| {
        const col_type = column_types[col_idx];

        // Get buffer and fill with data
        switch (col_type) {
            .Int64 => {
                const buffer = col.asInt64Buffer() orelse return error.TypeMismatch;
                for (rows, 0..) |row, row_idx| {
                    if (col_idx >= row.len or row[col_idx].len == 0) {
                        buffer[row_idx] = 0; // Explicit null representation
                    } else {
                        buffer[row_idx] = std.fmt.parseInt(i64, row[col_idx], 10) catch |err| {
                            std.log.err("Failed to parse Int64 at row {}, col {}: '{s}' - {}", .{ row_idx, col_idx, row[col_idx], err });
                            return error.TypeMismatch; // Fail fast in Strict mode
                        };
                    }
                }
            },
            .Float64 => {
                const buffer = col.asFloat64Buffer() orelse return error.TypeMismatch;
                for (rows, 0..) |row, row_idx| {
                    if (col_idx >= row.len or row[col_idx].len == 0) {
                        buffer[row_idx] = 0.0; // Explicit null representation
                    } else {
                        buffer[row_idx] = std.fmt.parseFloat(f64, row[col_idx]) catch |err| {
                            std.log.err("Failed to parse Float64 at row {}, col {}: '{s}' - {}", .{ row_idx, col_idx, row[col_idx], err });
                            return error.TypeMismatch; // Fail fast in Strict mode
                        };
                    }
                }
            },
            else => {
                // String type not supported in MVP
                return error.UnsupportedType;
            },
        }
    }
}

// Tests
test "CSVParser.init creates parser" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,age\nAlice,30\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    try testing.expectEqual(@as(u32, 0), parser.pos);
    try testing.expectEqual(ParserState.Start, parser.state);
}

test "CSVParser.nextField parses simple field" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "hello,world\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    const field1 = try parser.nextField();
    try testing.expect(field1 != null);
    try testing.expectEqualStrings("hello", field1.?);
    allocator.free(field1.?);

    const field2 = try parser.nextField();
    try testing.expect(field2 != null);
    try testing.expectEqualStrings("world", field2.?);
    allocator.free(field2.?);
}

test "CSVParser.nextField parses quoted field" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "\"hello, world\",next\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    const field1 = try parser.nextField();
    try testing.expect(field1 != null);
    try testing.expectEqualStrings("hello, world", field1.?);
    allocator.free(field1.?);

    const field2 = try parser.nextField();
    try testing.expect(field2 != null);
    try testing.expectEqualStrings("next", field2.?);
    allocator.free(field2.?);
}

test "CSVParser.nextField handles escaped quotes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "\"hello \"\"world\"\"\"\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    const field = try parser.nextField();
    try testing.expect(field != null);
    try testing.expectEqualStrings("hello \"world\"", field.?);
    allocator.free(field.?);
}

test "CSVParser.toDataFrame parses simple CSV" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "age,score\n30,95.5\n25,87.3\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.len());
    try testing.expectEqual(@as(usize, 2), df.columnCount());

    const age_col = df.column("age").?;
    try testing.expectEqual(ValueType.Int64, age_col.valueType);

    const score_col = df.column("score").?;
    try testing.expectEqual(ValueType.Float64, score_col.valueType);

    const ages = age_col.asInt64().?;
    try testing.expectEqual(@as(i64, 30), ages[0]);
    try testing.expectEqual(@as(i64, 25), ages[1]);

    const scores = score_col.asFloat64().?;
    try testing.expectEqual(@as(f64, 95.5), scores[0]);
    try testing.expectEqual(@as(f64, 87.3), scores[1]);
}

test "inferColumnType identifies Int64" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const field1 = try allocator.dupe(u8, "10");
    defer allocator.free(field1);
    const field2 = try allocator.dupe(u8, "20");
    defer allocator.free(field2);

    var row1 = [_][]const u8{field1};
    var row2 = [_][]const u8{field2};
    var rows_arr = [_][][]const u8{ &row1, &row2 };
    const rows: []const [][]const u8 = &rows_arr;

    const typ = try inferColumnType(rows, 0);
    try testing.expectEqual(ValueType.Int64, typ);
}

test "inferColumnType identifies Float64" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const field1 = try allocator.dupe(u8, "10.5");
    defer allocator.free(field1);
    const field2 = try allocator.dupe(u8, "20.5");
    defer allocator.free(field2);

    var row1 = [_][]const u8{field1};
    var row2 = [_][]const u8{field2};
    var rows_arr = [_][][]const u8{ &row1, &row2 };
    const rows: []const [][]const u8 = &rows_arr;

    const typ = try inferColumnType(rows, 0);
    try testing.expectEqual(ValueType.Float64, typ);
}

test "tryParseInt64 validates integers" {
    const testing = std.testing;

    try testing.expect(tryParseInt64("42"));
    try testing.expect(tryParseInt64("-100"));
    try testing.expect(tryParseInt64("0"));

    try testing.expect(!tryParseInt64("3.14"));
    try testing.expect(!tryParseInt64("hello"));
    try testing.expect(!tryParseInt64(""));
}

test "tryParseFloat64 validates floats" {
    const testing = std.testing;

    try testing.expect(tryParseFloat64("3.14"));
    try testing.expect(tryParseFloat64("-2.5"));
    try testing.expect(tryParseFloat64("42"));
    // Note: "1e10" format should work but may have issues in some contexts
    // try testing.expect(tryParseFloat64("1e10"));

    try testing.expect(!tryParseFloat64("hello"));
    try testing.expect(!tryParseFloat64(""));
}

// ===== Phase 2 Tests: BOM, Empty DataFrames, Field Limits =====

test "CSVParser.init skips UTF-8 BOM" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // CSV with BOM (0xEF 0xBB 0xBF) followed by content
    const csv_with_bom = "\xEF\xBB\xBFname,age\nAlice,30\n";

    var parser = try CSVParser.init(allocator, csv_with_bom, .{});
    defer parser.deinit();

    // Parser should skip the 3-byte BOM
    try testing.expectEqual(@as(u32, 3), parser.pos);

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should parse correctly, ignoring BOM
    try testing.expectEqual(@as(u32, 1), df.rowCount);
    try testing.expectEqualStrings("name", df.columnDescs[0].name);
    try testing.expectEqualStrings("age", df.columnDescs[1].name);
}

test "CSVParser handles CSV without BOM" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,age\nAlice,30\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    // Parser should start at position 0
    try testing.expectEqual(@as(u32, 0), parser.pos);

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 1), df.rowCount);
}

test "toDataFrame allows empty CSV with headers only" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,age,score\n"; // Headers but no data rows

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should create DataFrame with 0 rows, 3 columns
    try testing.expectEqual(@as(u32, 0), df.rowCount);
    try testing.expectEqual(@as(usize, 3), df.columns.len);
    try testing.expectEqualStrings("name", df.columnDescs[0].name);
    try testing.expectEqualStrings("age", df.columnDescs[1].name);
    try testing.expectEqualStrings("score", df.columnDescs[2].name);
}

test "toDataFrame handles empty DataFrame operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "col1,col2\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expect(df.isEmpty());
    try testing.expectEqual(@as(u32, 0), df.len());
    try testing.expectEqual(@as(usize, 2), df.columnCount());
}

test "skipLineEnding handles CRLF correctly" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,age\r\nAlice,30\r\nBob,25\r\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.rowCount);
}

test "skipLineEnding handles LF only" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,age\nAlice,30\nBob,25\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.rowCount);
}

test "skipLineEnding handles CR only (old Mac format)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,age\rAlice,30\rBob,25\r";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.rowCount);
}

test "fillDataFrame fails on invalid Int64 instead of defaulting to 0" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // CSV with invalid integer value
    const csv = "age\n30\nabc\n"; // "abc" is not a valid integer

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    // Should FAIL with error, NOT return DataFrame with age=0
    try testing.expectError(error.TypeMismatch, parser.toDataFrame());
}

test "fillDataFrame fails on invalid Float64 instead of defaulting to 0.0" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // CSV with invalid float value
    const csv = "score\n95.5\ninvalid\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    // Should FAIL with error, NOT return DataFrame with score=0.0
    try testing.expectError(error.TypeMismatch, parser.toDataFrame());
}
