//! Rozes WebAssembly Entry Point
//!
//! This module serves as the root for the Wasm build, exposing
//! WebAssembly-specific export functions for JavaScript interaction.

const std = @import("std");
const builtin = @import("builtin");
const rozes = @import("rozes.zig");
const DataFrame = rozes.DataFrame;
const CSVParser = rozes.CSVParser;
const CSVOptions = rozes.CSVOptions;
const ValueType = rozes.ValueType;
const string_ops = @import("core/string_ops.zig");
const operations = @import("core/operations.zig");

// Conditional logging: only enabled in Debug mode
const enable_logging = builtin.mode == .Debug;

fn logError(comptime fmt: []const u8, args: anytype) void {
    if (enable_logging) {
        std.log.err(fmt, args);
    }
}

// ============================================================================
// Constants
// ============================================================================

const MAX_DATAFRAMES: u32 = 1000; // Maximum concurrent DataFrames
const INVALID_HANDLE: i32 = -1;

// String interning: Deduplicate error messages (saves ~1-2 KB)
const ErrorStrings = struct {
    pub const csv_parse_failed = "CSV parsing failed";
    pub const out_of_memory = "Out of memory";
    pub const invalid_format = "Invalid format";
    pub const invalid_handle = "Invalid handle";
    pub const column_not_found = "Column not found";
    pub const type_mismatch = "Type mismatch";
};

// ============================================================================
// Error Codes (returned to JavaScript)
// ============================================================================

pub const ErrorCode = enum(i32) {
    Success = 0,
    OutOfMemory = -1,
    InvalidFormat = -2,
    InvalidHandle = -3,
    ColumnNotFound = -4,
    TypeMismatch = -5,
    IndexOutOfBounds = -6,
    TooManyDataFrames = -7,
    InvalidOptions = -8,
    InvalidJson = -9,
    InvalidRange = -10,
    _,

    pub fn fromError(err: anyerror) ErrorCode {
        return switch (err) {
            error.OutOfMemory => .OutOfMemory,
            error.InvalidFormat => .InvalidFormat,
            error.ColumnNotFound => .ColumnNotFound,
            error.TypeMismatch => .TypeMismatch,
            error.InvalidType => .TypeMismatch, // Map InvalidType to TypeMismatch
            error.IndexOutOfBounds => .IndexOutOfBounds,
            error.InvalidSlice => .InvalidRange, // Map InvalidSlice to InvalidRange
            error.StringTooLong => .OutOfMemory, // String too long → out of memory
            error.InvalidUtf8 => .InvalidFormat, // Invalid UTF-8 → invalid format
            error.EmptyPattern => .InvalidFormat, // Empty pattern → invalid format
            error.EmptyDelimiter => .InvalidFormat, // Empty delimiter → invalid format
            error.LengthMismatch => .InvalidFormat, // Length mismatch → invalid format
            else => @enumFromInt(-100),
        };
    }
};

// ============================================================================
// DataFrame Handle Registry
// ============================================================================

const DataFrameRegistry = struct {
    frames: std.ArrayList(?*DataFrame),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) !DataFrameRegistry {
        const frames = try std.ArrayList(?*DataFrame).initCapacity(allocator, 4);

        return DataFrameRegistry{
            .frames = frames,
            .allocator = allocator,
        };
    }

    fn deinit(self: *DataFrameRegistry) void {
        self.frames.deinit();
    }

    fn register(self: *DataFrameRegistry, df: *DataFrame) !i32 {
        std.debug.assert(@intFromPtr(df) != 0); // Pre-condition: Non-null DataFrame
        std.debug.assert(self.frames.items.len < MAX_DATAFRAMES); // Pre-condition: Not at max

        // Look for empty slot (reuse freed handles)
        var i: u32 = 0;
        const max_search: u32 = @min(@as(u32, @intCast(self.frames.items.len)), MAX_DATAFRAMES);
        while (i < max_search) : (i += 1) {
            if (self.frames.items[i] == null) {
                self.frames.items[i] = df;
                return @intCast(i);
            }
        }

        // No empty slots, append new one
        if (self.frames.items.len >= MAX_DATAFRAMES) {
            return error.TooManyDataFrames;
        }

        try self.frames.append(self.allocator, df);
        const handle: i32 = @intCast(self.frames.items.len - 1);

        if (builtin.mode == .Debug) {
            std.debug.assert(handle >= 0);
            std.debug.assert(handle < MAX_DATAFRAMES);
        }

        return handle;
    }

    inline fn get(self: *DataFrameRegistry, handle: i32) ?*DataFrame {
        std.debug.assert(handle >= 0); // Pre-condition: Non-negative handle

        const idx: u32 = @intCast(handle);
        if (idx >= self.frames.items.len) {
            return null;
        }

        const result = self.frames.items[idx];

        if (builtin.mode == .Debug) {
            std.debug.assert(result == null or @intFromPtr(result.?) != 0); // Post-condition: Valid pointer if non-null
        }
        return result;
    }

    inline fn unregister(self: *DataFrameRegistry, handle: i32) void {
        std.debug.assert(handle >= 0); // Pre-condition: Non-negative handle

        const idx: u32 = @intCast(handle);
        if (idx < self.frames.items.len) {
            self.frames.items[idx] = null;

            if (builtin.mode == .Debug) {
                std.debug.assert(self.frames.items[idx] == null); // Post-condition: Slot is now null
            }
        }
    }
};

// ============================================================================
// Wasm Memory Management
// ============================================================================

// Use GeneralPurposeAllocator for Wasm
// Wasm linear memory is managed by the runtime, no need for manual @wasmMemoryGrow
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Global registry
var registry: DataFrameRegistry = undefined;
var registry_initialized = false;

fn ensureRegistryInitialized() void {
    if (!registry_initialized) {
        registry = DataFrameRegistry.init(gpa.allocator()) catch blk: {
            // If init fails, use a simpler fallback (shouldn't happen in practice)
            break :blk DataFrameRegistry{
                .frames = std.ArrayList(?*DataFrame).initCapacity(gpa.allocator(), 0) catch unreachable,
                .allocator = gpa.allocator(),
            };
        };
        registry_initialized = true;
    }

    std.debug.assert(registry_initialized == true); // Post-condition: Always initialized after call
}

fn getAllocator() std.mem.Allocator {
    std.debug.assert(registry_initialized); // Must call ensureRegistryInitialized first
    return gpa.allocator();
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Parse JSON array of strings: ["col1", "col2", ...]
/// Caller is responsible for freeing both the ArrayList and the individual strings
///
/// Tiger Style:
/// - 2+ assertions (input validation)
/// - Bounded loops with MAX constants
/// - Explicit error handling
/// - Post-loop assertions
///
/// Returns: ArrayList of allocated strings, or error
fn parseJSONStringArray(
    json: []const u8,
    allocator: std.mem.Allocator,
) !std.ArrayList([]const u8) {
    std.debug.assert(json.len > 0);
    std.debug.assert(json.len <= 10_000_000); // Max 10MB JSON input

    var result = std.ArrayList([]const u8).initCapacity(allocator, 4) catch {
        return error.OutOfMemory;
    };
    errdefer {
        for (result.items) |item| allocator.free(item);
        result.deinit(allocator);
    }

    // Tiger Style: Bounded parsing with explicit MAX constants
    const MAX_PARSE_ITERATIONS: u32 = 10_000; // Max fields in JSON array
    const MAX_FIELD_LENGTH: u32 = 1_000_000; // Max single field length

    var i: u32 = 0;
    var iterations: u32 = 0;

    while (i < json.len and iterations < MAX_PARSE_ITERATIONS) : (iterations += 1) {
        if (json[i] == '"') {
            // Find closing quote with bounded search
            i += 1;
            const start = i;
            var field_len: u32 = 0;

            while (i < json.len and
                json[i] != '"' and
                field_len < MAX_FIELD_LENGTH) : ({ i += 1; field_len += 1; })
            {}

            if (field_len >= MAX_FIELD_LENGTH) {
                return error.InvalidFormat;
            }

            if (i < json.len) {
                const name = try allocator.dupe(u8, json[start..i]);
                result.append(allocator, name) catch {
                    allocator.free(name);
                    return error.OutOfMemory;
                };
            }
        }
        i += 1;
    }

    // Post-condition: Loop completed within bounds
    std.debug.assert(iterations <= MAX_PARSE_ITERATIONS);

    return result;
}

// ============================================================================
// Wasm Exported Functions
// ============================================================================

/// Parse CSV buffer and return DataFrame handle
export fn rozes_parseCSV(
    csv_ptr: [*]const u8,
    csv_len: u32,
    opts_json_ptr: [*]const u8,
    opts_json_len: u32,
) i32 {
    ensureRegistryInitialized();

    std.debug.assert(csv_len > 0);
    std.debug.assert(csv_len <= 1_000_000_000);

    const csv_buffer = csv_ptr[0..csv_len];

    const opts: CSVOptions = if (opts_json_len > 0) blk: {
        const opts_json = opts_json_ptr[0..opts_json_len];
        break :blk parseCSVOptionsJSON(opts_json) catch {
            return @intFromEnum(ErrorCode.InvalidOptions);
        };
    } else CSVOptions{};

    const allocator = getAllocator();

    // Create CSV parser
    var parser = CSVParser.init(allocator, csv_buffer, opts) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };
    defer parser.deinit();

    // Parse to DataFrame
    const df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    df_ptr.* = parser.toDataFrame() catch |err| {
        // Log error context with row/column information (debug only)
        const field_preview = if (parser.current_field.items.len > 0)
            parser.current_field.items[0..@min(50, parser.current_field.items.len)]
        else
            "";

        logError("CSV parsing failed: {} at row {} col {} - field preview: '{s}'", .{
            err,
            parser.current_row_index,
            parser.current_col_index,
            field_preview,
        });

        allocator.destroy(df_ptr);
        return @intFromEnum(ErrorCode.fromError(err));
    };

    const handle = registry.register(df_ptr) catch {
        df_ptr.deinit();
        allocator.destroy(df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(handle >= 0); // Post-condition: Valid handle returned
    std.debug.assert(handle < MAX_DATAFRAMES); // Post-condition: Within bounds

    return handle;
}

/// Get DataFrame dimensions
export fn rozes_getDimensions(
    handle: i32,
    out_rows: *u32,
    out_cols: *u32,
) i32 {
    std.debug.assert(handle >= 0);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    out_rows.* = df.row_count;
    out_cols.* = @intCast(df.columns.len);

    return @intFromEnum(ErrorCode.Success);
}

/// Get Float64 column data (zero-copy access)
export fn rozes_getColumnF64(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    out_ptr: *u32,
    out_len: *u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);
    std.debug.assert(@intFromPtr(out_ptr) != 0); // Non-null output pointer
    std.debug.assert(@intFromPtr(out_len) != 0); // Non-null output pointer

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const series = df.column(col_name) orelse {
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    const data = series.asFloat64() orelse {
        return @intFromEnum(ErrorCode.TypeMismatch);
    };

    const ptr_val: u32 = @intCast(@intFromPtr(data.ptr));
    out_ptr.* = ptr_val;
    out_len.* = @intCast(data.len);

    std.debug.assert(ptr_val != 0); // Post-condition: Non-null pointer
    std.debug.assert(out_len.* == @as(u32, @intCast(data.len))); // Post-condition: Length matches

    return @intFromEnum(ErrorCode.Success);
}

/// Get Int64 column data (zero-copy access)
export fn rozes_getColumnI64(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    out_ptr: *u32,
    out_len: *u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);
    std.debug.assert(@intFromPtr(out_ptr) != 0); // Non-null output pointer
    std.debug.assert(@intFromPtr(out_len) != 0); // Non-null output pointer

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const series = df.column(col_name) orelse {
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    const data = series.asInt64() orelse {
        return @intFromEnum(ErrorCode.TypeMismatch);
    };

    const ptr_val: u32 = @intCast(@intFromPtr(data.ptr));
    out_ptr.* = ptr_val;
    out_len.* = @intCast(data.len);

    std.debug.assert(ptr_val != 0); // Post-condition: Non-null pointer
    std.debug.assert(out_len.* == @as(u32, @intCast(data.len))); // Post-condition: Length matches

    return @intFromEnum(ErrorCode.Success);
}

/// Get column names as JSON array
export fn rozes_getColumnNames(
    handle: i32,
    out_buffer: [*]u8,
    buffer_len: u32,
    out_written: *u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(buffer_len > 0);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    var buffer = out_buffer[0..buffer_len];
    var pos: usize = 0;

    buffer[pos] = '[';
    pos += 1;

    for (df.columns, 0..) |col, i| {
        if (i > 0) {
            buffer[pos] = ',';
            pos += 1;
        }

        buffer[pos] = '"';
        pos += 1;

        const name_bytes = std.mem.sliceTo(col.name, 0);
        if (pos + name_bytes.len + 1 >= buffer_len) {
            return @intFromEnum(ErrorCode.OutOfMemory);
        }

        @memcpy(buffer[pos .. pos + name_bytes.len], name_bytes);
        pos += name_bytes.len;

        buffer[pos] = '"';
        pos += 1;
    }

    buffer[pos] = ']';
    pos += 1;

    out_written.* = @intCast(pos);
    return @intFromEnum(ErrorCode.Success);
}

/// Free DataFrame and release memory
export fn rozes_free(handle: i32) void {
    std.debug.assert(handle >= 0);

    const df = registry.get(handle) orelse return;

    df.deinit();

    const allocator = getAllocator();
    allocator.destroy(df);

    registry.unregister(handle);
}

/// Allocate memory buffer for JavaScript
/// Returns pointer to allocated memory, or 0 on failure
export fn rozes_alloc(size: u32) u32 {
    std.debug.assert(size > 0); // Pre-condition: Non-zero size
    std.debug.assert(size <= 1_000_000_000); // Pre-condition: Reasonable limit (1GB)

    const allocator = getAllocator();
    const mem = allocator.alloc(u8, size) catch return 0;

    const ptr: u32 = @intCast(@intFromPtr(mem.ptr));

    std.debug.assert(ptr != 0); // Post-condition: Non-null pointer
    std.debug.assert(ptr % 8 == 0 or size < 8); // Post-condition: Aligned for most types
    return ptr;
}

/// Free memory buffer allocated by rozes_alloc
export fn rozes_free_buffer(ptr: u32, size: u32) void {
    std.debug.assert(ptr != 0); // Pre-condition: Non-null pointer
    std.debug.assert(size > 0); // Pre-condition: Non-zero size

    const allocator = getAllocator();
    const mem = @as([*]u8, @ptrFromInt(ptr))[0..size];
    allocator.free(mem);
}

/// Get Bool column data (zero-copy access)
export fn rozes_getColumnBool(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    out_ptr: *u32,
    out_len: *u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);
    std.debug.assert(@intFromPtr(out_ptr) != 0); // Non-null output pointer
    std.debug.assert(@intFromPtr(out_len) != 0); // Non-null output pointer

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const series = df.column(col_name) orelse {
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    const data = series.asBool() orelse {
        return @intFromEnum(ErrorCode.TypeMismatch);
    };

    const ptr_val: u32 = @intCast(@intFromPtr(data.ptr));
    out_ptr.* = ptr_val;
    out_len.* = @intCast(data.len);

    std.debug.assert(ptr_val != 0); // Post-condition: Non-null pointer
    std.debug.assert(out_len.* == @as(u32, @intCast(data.len))); // Post-condition: Length matches

    return @intFromEnum(ErrorCode.Success);
}

/// Get String column data
/// Returns two arrays: offsets array and buffer
/// offsets[i] = end position of string i in buffer
/// String i spans buffer[start..end] where start = offsets[i-1] (or 0 for i==0), end = offsets[i]
export fn rozes_getColumnString(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    out_offsets_ptr: *u32,
    out_offsets_len: *u32,
    out_buffer_ptr: *u32,
    out_buffer_len: *u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);
    std.debug.assert(@intFromPtr(out_offsets_ptr) != 0); // Non-null output pointer
    std.debug.assert(@intFromPtr(out_offsets_len) != 0); // Non-null output pointer
    std.debug.assert(@intFromPtr(out_buffer_ptr) != 0); // Non-null output pointer
    std.debug.assert(@intFromPtr(out_buffer_len) != 0); // Non-null output pointer

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const series = df.column(col_name) orelse {
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    if (series.value_type != .String) {
        return @intFromEnum(ErrorCode.TypeMismatch);
    }

    const str_col = &series.data.String;

    // Return offsets array
    const offsets_ptr_val: u32 = @intCast(@intFromPtr(str_col.offsets.ptr));
    out_offsets_ptr.* = offsets_ptr_val;
    out_offsets_len.* = str_col.count;

    // Return buffer
    const buffer_ptr_val: u32 = @intCast(@intFromPtr(str_col.buffer.ptr));
    out_buffer_ptr.* = buffer_ptr_val;
    out_buffer_len.* = if (str_col.count > 0) str_col.offsets[str_col.count - 1] else 0;

    std.debug.assert(offsets_ptr_val != 0); // Post-condition: Non-null pointer
    std.debug.assert(buffer_ptr_val != 0); // Post-condition: Non-null pointer
    std.debug.assert(out_offsets_len.* == str_col.count); // Post-condition: Length matches

    return @intFromEnum(ErrorCode.Success);
}

// ============================================================================
// DataFrame Operations (Priority 2 - Milestone 1.1.0)
// ============================================================================

/// Select specific columns from DataFrame
/// Returns handle to new DataFrame with selected columns only
export fn rozes_select(
    handle: i32,
    col_names_json_ptr: [*]const u8,
    col_names_json_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_names_json_len > 0);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    // Parse JSON array of column names: ["col1", "col2", ...]
    const col_names_json = col_names_json_ptr[0..col_names_json_len];
    const allocator = getAllocator();

    // Use helper function for JSON parsing
    var col_names = parseJSONStringArray(col_names_json, allocator) catch |err| {
        return @intFromEnum(ErrorCode.fromError(err));
    };
    defer {
        for (col_names.items) |name| {
            allocator.free(name);
        }
        col_names.deinit(allocator);
    }

    if (col_names.items.len == 0) {
        return @intFromEnum(ErrorCode.InvalidFormat);
    }

    // Call DataFrame.select()
    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = df.select(col_names.items) catch |err| {
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.fromError(err));
    };

    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Drop columns from DataFrame
/// Returns handle to new DataFrame without dropped columns
///
/// Args:
///   - handle: DataFrame handle
///   - col_names_json_ptr: Pointer to JSON array of column names to drop
///   - col_names_json_len: Length of JSON array
///
/// Returns: Handle to new DataFrame, or error code
export fn rozes_drop(
    handle: i32,
    col_names_json_ptr: [*]const u8,
    col_names_json_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_names_json_len > 0);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    // Parse JSON array of column names: ["col1", "col2", ...]
    const col_names_json = col_names_json_ptr[0..col_names_json_len];
    const allocator = getAllocator();

    // Use helper function for JSON parsing
    var col_names = parseJSONStringArray(col_names_json, allocator) catch |err| {
        return @intFromEnum(ErrorCode.fromError(err));
    };
    defer {
        for (col_names.items) |name| {
            allocator.free(name);
        }
        col_names.deinit(allocator);
    }

    if (col_names.items.len == 0) {
        return @intFromEnum(ErrorCode.InvalidFormat);
    }

    // Call DataFrame.drop()
    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = df.drop(col_names.items) catch |err| {
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.fromError(err));
    };

    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Rename column in DataFrame
/// JSON format: {"old_name": "new_name"}
export fn rozes_rename(
    handle: i32,
    old_name_ptr: [*]const u8,
    old_name_len: u32,
    new_name_ptr: [*]const u8,
    new_name_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(old_name_len > 0);
    std.debug.assert(new_name_len > 0);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();

    const old_name = old_name_ptr[0..old_name_len];
    const new_name = new_name_ptr[0..new_name_len];

    // Create rename map
    var rename_map = std.StringHashMap([]const u8).init(allocator);
    defer rename_map.deinit();

    rename_map.put(old_name, new_name) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    // Create result DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = df.rename(allocator, &rename_map) catch |err| {
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Get unique values from a column
/// Returns JSON array of unique values as strings
export fn rozes_unique(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    out_ptr: *u32,
    out_len: *u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];

    // Get unique values
    const unique_values = df.unique(allocator, col_name) catch |err| {
        return @intFromEnum(ErrorCode.fromError(err));
    };
    defer allocator.free(unique_values);

    // Convert to JSON array
    var json_array = std.ArrayList(u8).initCapacity(allocator, 256) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };
    defer json_array.deinit(allocator);

    json_array.append(allocator, '[') catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    for (unique_values, 0..) |value, i| {
        if (i > 0) {
            json_array.append(allocator, ',') catch {
                return @intFromEnum(ErrorCode.OutOfMemory);
            };
        }
        json_array.append(allocator, '"') catch {
            return @intFromEnum(ErrorCode.OutOfMemory);
        };
        json_array.appendSlice(allocator, value) catch {
            return @intFromEnum(ErrorCode.OutOfMemory);
        };
        json_array.append(allocator, '"') catch {
            return @intFromEnum(ErrorCode.OutOfMemory);
        };
    }

    json_array.append(allocator, ']') catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    // Allocate buffer for result
    const result = json_array.toOwnedSlice(allocator) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    const result_ptr = allocator.alloc(u8, result.len) catch {
        allocator.free(result);
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    @memcpy(result_ptr, result);
    allocator.free(result);

    out_ptr.* = @intCast(@intFromPtr(result_ptr.ptr));
    out_len.* = @intCast(result_ptr.len);

    return @intFromEnum(ErrorCode.Success);
}

/// Drop duplicate rows based on subset of columns
/// subset_json format: ["col1", "col2"] or null for all columns
export fn rozes_dropDuplicates(
    handle: i32,
    subset_json_ptr: [*]const u8,
    subset_json_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();

    // Parse subset from JSON
    var subset: ?[]const []const u8 = null;
    defer if (subset) |s| {
        for (s) |col_name| allocator.free(col_name);
        allocator.free(s);
    };

    if (subset_json_len > 0) {
        const subset_json = subset_json_ptr[0..subset_json_len];

        if (!std.mem.eql(u8, subset_json, "null")) {
            var parsed = std.json.parseFromSlice(
                std.json.Value,
                allocator,
                subset_json,
                .{},
            ) catch {
                return @intFromEnum(ErrorCode.InvalidJson);
            };
            defer parsed.deinit();

            const array = parsed.value.array;
            var col_names = allocator.alloc([]const u8, array.items.len) catch {
                return @intFromEnum(ErrorCode.OutOfMemory);
            };

            for (array.items, 0..) |item, i| {
                const str = item.string;
                col_names[i] = allocator.dupe(u8, str) catch {
                    for (col_names[0..i]) |name| allocator.free(name);
                    allocator.free(col_names);
                    return @intFromEnum(ErrorCode.OutOfMemory);
                };
            }

            subset = col_names;
        }
    }

    // Create result DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = df.dropDuplicates(allocator, subset) catch |err| {
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Get summary statistics for all columns
/// Returns JSON object: {"col1": {"count": 100, "mean": 50, ...}, ...}
export fn rozes_describe(
    handle: i32,
    out_ptr: *u32,
    out_len: *u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();

    // Get summary statistics
    var summary_map = df.describe(allocator) catch |err| {
        return @intFromEnum(ErrorCode.fromError(err));
    };
    defer {
        var it = summary_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        summary_map.deinit();
    }

    // Convert to JSON
    var json = std.ArrayList(u8).initCapacity(allocator, 512) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };
    defer json.deinit(allocator);

    json.append(allocator, '{') catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    var it = summary_map.iterator();
    var first = true;
    while (it.next()) |entry| {
        if (!first) {
            json.append(allocator, ',') catch {
                return @intFromEnum(ErrorCode.OutOfMemory);
            };
        }
        first = false;

        // Column name
        json.append(allocator, '"') catch {
            return @intFromEnum(ErrorCode.OutOfMemory);
        };
        json.appendSlice(allocator, entry.key_ptr.*) catch {
            return @intFromEnum(ErrorCode.OutOfMemory);
        };
        json.appendSlice(allocator, "\":{") catch {
            return @intFromEnum(ErrorCode.OutOfMemory);
        };

        // Summary stats
        const summary = entry.value_ptr.*;

        // Count is always present (not optional)
        json.writer(allocator).print("\"count\":{},", .{summary.count}) catch {
            return @intFromEnum(ErrorCode.OutOfMemory);
        };

        // Mean, std, min, max are optional
        if (summary.mean) |mean| {
            json.writer(allocator).print("\"mean\":{d},", .{mean}) catch {
                return @intFromEnum(ErrorCode.OutOfMemory);
            };
        }
        if (summary.std) |std_val| {
            json.writer(allocator).print("\"std\":{d},", .{std_val}) catch {
                return @intFromEnum(ErrorCode.OutOfMemory);
            };
        }
        if (summary.min) |min| {
            json.writer(allocator).print("\"min\":{d},", .{min}) catch {
                return @intFromEnum(ErrorCode.OutOfMemory);
            };
        }
        if (summary.max) |max| {
            json.writer(allocator).print("\"max\":{d}", .{max}) catch {
                return @intFromEnum(ErrorCode.OutOfMemory);
            };
        }

        json.append(allocator, '}') catch {
            return @intFromEnum(ErrorCode.OutOfMemory);
        };
    }

    json.append(allocator, '}') catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    // Allocate buffer for result
    const result = json.toOwnedSlice(allocator) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    const result_ptr = allocator.alloc(u8, result.len) catch {
        allocator.free(result);
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    @memcpy(result_ptr, result);
    allocator.free(result);

    out_ptr.* = @intCast(@intFromPtr(result_ptr.ptr));
    out_len.* = @intCast(result_ptr.len);

    return @intFromEnum(ErrorCode.Success);
}

/// Random sample of n rows (with replacement)
export fn rozes_sample(
    handle: i32,
    n: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(n > 0);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();

    // Create result DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = df.sample(allocator, n) catch |err| {
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Get first n rows of DataFrame
/// Returns handle to new DataFrame with first n rows
export fn rozes_head(
    handle: i32,
    n: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(n > 0);
    std.debug.assert(n <= std.math.maxInt(u32));

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();

    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = df.head(allocator, n) catch |err| {
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.fromError(err));
    };

    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Get last n rows of DataFrame
/// Returns handle to new DataFrame with last n rows
export fn rozes_tail(
    handle: i32,
    n: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(n > 0);
    std.debug.assert(n <= std.math.maxInt(u32));

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();

    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = df.tail(allocator, n) catch |err| {
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.fromError(err));
    };

    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Sort DataFrame by column
/// Returns handle to new sorted DataFrame
export fn rozes_sort(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    descending: bool,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const allocator = getAllocator();

    // Import sort module
    const sort_mod = @import("core/sort.zig");
    const SortOrder = rozes.SortOrder;

    const order: SortOrder = if (descending) .Descending else .Ascending;

    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = sort_mod.sort(df, allocator, col_name, order) catch |err| {
        allocator.destroy(new_df_ptr);
        logError("Sort failed on column '{s}': {}", .{ col_name, err });
        return @intFromEnum(ErrorCode.fromError(err));
    };

    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Filter DataFrame by simple numeric comparison
/// operator: 0 = equal, 1 = not equal, 2 = greater than, 3 = less than, 4 = greater or equal, 5 = less or equal
/// Returns handle to new filtered DataFrame
export fn rozes_filterNumeric(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    operator: u8,
    value: f64,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);
    std.debug.assert(operator <= 5);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const allocator = getAllocator();

    // Get column to filter on
    const series = df.column(col_name) orelse {
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Verify it's numeric
    if (series.value_type != .Float64 and series.value_type != .Int64) {
        return @intFromEnum(ErrorCode.TypeMismatch);
    }

    // Implement filter inline (can't use closures in Zig export functions)
    // First pass: count matching rows
    var match_count: u32 = 0;
    var row_idx: u32 = 0;

    const MAX_ROWS: u32 = df.row_count;

    // Get column data once
    const float_data = if (series.value_type == .Float64) series.asFloat64() else null;
    const int_data = if (series.value_type == .Int64) series.asInt64() else null;

    while (row_idx < MAX_ROWS) : (row_idx += 1) {
        const row_val: f64 = if (float_data) |fdata|
            fdata[row_idx]
        else if (int_data) |idata|
            @as(f64, @floatFromInt(idata[row_idx]))
        else
            continue;

        const matches = switch (operator) {
            0 => row_val == value, // equal
            1 => row_val != value, // not equal
            2 => row_val > value, // greater than
            3 => row_val < value, // less than
            4 => row_val >= value, // greater or equal
            5 => row_val <= value, // less or equal
            else => false,
        };

        if (matches) match_count += 1;
    }

    std.debug.assert(row_idx == MAX_ROWS);

    // Create new DataFrame
    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    const capacity = if (match_count > 0) match_count else 1;
    new_df_ptr.* = DataFrame.create(allocator, df.column_descs, capacity) catch |err| {
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Second pass: copy matching rows
    row_idx = 0;
    var dst_idx: u32 = 0;

    while (row_idx < MAX_ROWS) : (row_idx += 1) {
        const row_val: f64 = if (float_data) |fdata|
            fdata[row_idx]
        else if (int_data) |idata|
            @as(f64, @floatFromInt(idata[row_idx]))
        else
            continue;

        const matches = switch (operator) {
            0 => row_val == value,
            1 => row_val != value,
            2 => row_val > value,
            3 => row_val < value,
            4 => row_val >= value,
            5 => row_val <= value,
            else => false,
        };

        if (matches) {
            // Copy all column values for this row
            var col_idx: usize = 0;
            while (col_idx < df.columns.len) : (col_idx += 1) {
                const src_col = &df.columns[col_idx];
                const dst_col = &new_df_ptr.columns[col_idx];

                switch (src_col.value_type) {
                    .Int64 => {
                        const src = src_col.asInt64().?;
                        const dst = dst_col.asInt64Buffer().?;
                        dst[dst_idx] = src[row_idx];
                    },
                    .Float64 => {
                        const src = src_col.asFloat64().?;
                        const dst = dst_col.asFloat64Buffer().?;
                        dst[dst_idx] = src[row_idx];
                    },
                    .Bool => {
                        const src = src_col.asBool().?;
                        const dst = dst_col.asBoolBuffer().?;
                        dst[dst_idx] = src[row_idx];
                    },
                    else => {}, // String/Categorical handled separately if needed
                }
            }

            dst_idx += 1;
        }
    }

    std.debug.assert(dst_idx == match_count);

    // Set row count
    new_df_ptr.setRowCount(match_count) catch |err| {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.fromError(err));
    };

    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

// ============================================================================
// DataFrame Advanced Operations (Priority 3 - Milestone 1.1.0)
// ============================================================================

/// GroupBy with aggregation - groups DataFrame and applies aggregation function
/// Returns handle to new DataFrame with grouped and aggregated data
///
/// Args:
///   - handle: DataFrame handle
///   - group_col_ptr: Pointer to group column name
///   - group_col_len: Length of group column name
///   - value_col_ptr: Pointer to value column name (column to aggregate)
///   - value_col_len: Length of value column name
///   - agg_func: Aggregation function (0=sum, 1=mean, 2=count, 3=min, 4=max)
///
/// Returns: Handle to new DataFrame with [group_column, aggregated_value]
export fn rozes_groupByAgg(
    handle: i32,
    group_col_ptr: [*]const u8,
    group_col_len: u32,
    value_col_ptr: [*]const u8,
    value_col_len: u32,
    agg_func: u8,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(group_col_len > 0);
    std.debug.assert(value_col_len > 0);
    std.debug.assert(agg_func <= 4); // 0-4: sum, mean, count, min, max

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const group_col_name = group_col_ptr[0..group_col_len];
    const value_col_name = value_col_ptr[0..value_col_len];
    const allocator = getAllocator();

    // Import groupby module
    const groupby_mod = @import("core/groupby.zig");
    const GroupBy = groupby_mod.GroupBy;
    const AggFunc = groupby_mod.AggFunc;
    const AggSpec = groupby_mod.AggSpec;

    // Map agg_func number to enum
    const func = switch (agg_func) {
        0 => AggFunc.Sum,
        1 => AggFunc.Mean,
        2 => AggFunc.Count,
        3 => AggFunc.Min,
        4 => AggFunc.Max,
        else => return @intFromEnum(ErrorCode.InvalidOptions),
    };

    // Create GroupBy
    var gb = GroupBy.init(allocator, df, group_col_name) catch |err| {
        logError("GroupBy init failed on column '{s}': {}", .{ group_col_name, err });
        return @intFromEnum(ErrorCode.fromError(err));
    };
    defer gb.deinit();

    // Create aggregation spec
    const specs = [_]AggSpec{
        AggSpec{ .column = value_col_name, .func = func },
    };

    // Perform aggregation
    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = gb.agg(allocator, &specs) catch |err| {
        allocator.destroy(new_df_ptr);
        logError("GroupBy aggregation failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Join two DataFrames on specified columns
/// Returns handle to new DataFrame with joined data
///
/// Args:
///   - left_handle: Left DataFrame handle
///   - right_handle: Right DataFrame handle
///   - join_cols_json_ptr: Pointer to JSON array of column names: ["col1", "col2"]
///   - join_cols_json_len: Length of JSON string
///   - join_type: Join type (0=inner, 1=left)
///
/// Returns: Handle to new joined DataFrame
export fn rozes_join(
    left_handle: i32,
    right_handle: i32,
    join_cols_json_ptr: [*]const u8,
    join_cols_json_len: u32,
    join_type: u8,
) i32 {
    std.debug.assert(left_handle >= 0);
    std.debug.assert(right_handle >= 0);
    std.debug.assert(join_cols_json_len > 0);
    std.debug.assert(join_type <= 1); // 0=inner, 1=left

    const left_df = registry.get(left_handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const right_df = registry.get(right_handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const join_cols_json = join_cols_json_ptr[0..join_cols_json_len];
    const allocator = getAllocator();

    // Parse JSON array of column names: ["col1", "col2"]
    // Use helper function for JSON parsing
    var col_names = parseJSONStringArray(join_cols_json, allocator) catch |err| {
        return @intFromEnum(ErrorCode.fromError(err));
    };
    defer {
        for (col_names.items) |name| {
            allocator.free(name);
        }
        col_names.deinit(allocator);
    }

    if (col_names.items.len == 0) {
        return @intFromEnum(ErrorCode.InvalidFormat);
    }

    // Import join module
    const join_mod = @import("core/join.zig");

    // Perform join
    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = blk: {
        if (join_type == 0) {
            break :blk join_mod.innerJoin(left_df, right_df, allocator, col_names.items) catch |err| {
                allocator.destroy(new_df_ptr);
                logError("Join failed: {}", .{err});
                return @intFromEnum(ErrorCode.fromError(err));
            };
        } else {
            break :blk join_mod.leftJoin(left_df, right_df, allocator, col_names.items) catch |err| {
                allocator.destroy(new_df_ptr);
                logError("Join failed: {}", .{err});
                return @intFromEnum(ErrorCode.fromError(err));
            };
        }
    };

    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

// ============================================================================
// CSV Export (Priority 5 - Milestone 1.1.0)
// ============================================================================

/// Export DataFrame to CSV format
/// Returns pointer and length of allocated CSV string
/// Caller must free the buffer using rozes_free_buffer
export fn rozes_toCSV(
    handle: i32,
    opts_json_ptr: [*]const u8,
    opts_json_len: u32,
    out_csv_ptr: *u32,
    out_csv_len: *u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(@intFromPtr(out_csv_ptr) != 0); // Non-null output pointer
    std.debug.assert(@intFromPtr(out_csv_len) != 0); // Non-null output pointer

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const opts: CSVOptions = if (opts_json_len > 0) blk: {
        const opts_json = opts_json_ptr[0..opts_json_len];
        break :blk parseCSVOptionsJSON(opts_json) catch {
            return @intFromEnum(ErrorCode.InvalidOptions);
        };
    } else CSVOptions{};

    const allocator = getAllocator();

    // Export DataFrame to CSV
    const csv = df.toCSV(allocator, opts) catch |err| {
        logError("CSV export failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Return pointer and length
    const csv_ptr_val: u32 = @intCast(@intFromPtr(csv.ptr));
    out_csv_ptr.* = csv_ptr_val;
    out_csv_len.* = @intCast(csv.len);

    std.debug.assert(csv_ptr_val != 0); // Post-condition: Non-null pointer
    std.debug.assert(out_csv_len.* == @as(u32, @intCast(csv.len))); // Post-condition: Length matches

    return @intFromEnum(ErrorCode.Success);
}

// ============================================================================
// Helper Functions
// ============================================================================

fn parseCSVOptionsJSON(json: []const u8) !CSVOptions {
    std.debug.assert(json.len > 0);
    std.debug.assert(json.len < 10_000); // Reasonable limit

    var opts = CSVOptions{};

    // Simple manual JSON parser for CSV options only
    // This saves ~2-3 KB by not pulling in std.json

    // Check for "has_headers":true or "has_headers":false
    if (std.mem.indexOf(u8, json, "\"has_headers\"") != null) {
        if (std.mem.indexOf(u8, json, "\"has_headers\":true") != null or
            std.mem.indexOf(u8, json, "\"has_headers\": true") != null)
        {
            opts.has_headers = true;
        } else if (std.mem.indexOf(u8, json, "\"has_headers\":false") != null or
            std.mem.indexOf(u8, json, "\"has_headers\": false") != null)
        {
            opts.has_headers = false;
        }
    }

    // Check for "skip_blank_lines":true or "skip_blank_lines":false
    if (std.mem.indexOf(u8, json, "\"skip_blank_lines\"") != null) {
        if (std.mem.indexOf(u8, json, "\"skip_blank_lines\":true") != null or
            std.mem.indexOf(u8, json, "\"skip_blank_lines\": true") != null)
        {
            opts.skip_blank_lines = true;
        } else if (std.mem.indexOf(u8, json, "\"skip_blank_lines\":false") != null or
            std.mem.indexOf(u8, json, "\"skip_blank_lines\": false") != null)
        {
            opts.skip_blank_lines = false;
        }
    }

    // Check for "trim_whitespace":true or "trim_whitespace":false
    if (std.mem.indexOf(u8, json, "\"trim_whitespace\"") != null) {
        if (std.mem.indexOf(u8, json, "\"trim_whitespace\":true") != null or
            std.mem.indexOf(u8, json, "\"trim_whitespace\": true") != null)
        {
            opts.trim_whitespace = true;
        } else if (std.mem.indexOf(u8, json, "\"trim_whitespace\":false") != null or
            std.mem.indexOf(u8, json, "\"trim_whitespace\": false") != null)
        {
            opts.trim_whitespace = false;
        }
    }

    // Check for "delimiter":"," or "delimiter":"\t"
    if (std.mem.indexOf(u8, json, "\"delimiter\"") != null) {
        if (std.mem.indexOf(u8, json, "\"delimiter\":\",\"") != null or
            std.mem.indexOf(u8, json, "\"delimiter\": \",\"") != null)
        {
            opts.delimiter = ',';
        } else if (std.mem.indexOf(u8, json, "\"delimiter\":\"\\t\"") != null or
            std.mem.indexOf(u8, json, "\"delimiter\": \"\\t\"") != null)
        {
            opts.delimiter = '\t';
        } else if (std.mem.indexOf(u8, json, "\"delimiter\":\";\"") != null or
            std.mem.indexOf(u8, json, "\"delimiter\": \";\"") != null)
        {
            opts.delimiter = ';';
        }
    }

    std.debug.assert(opts.delimiter != 0); // Post-condition: Valid delimiter
    std.debug.assert(opts.delimiter == ',' or opts.delimiter == '\t' or opts.delimiter == ';'); // Post-condition: Known delimiters

    return opts;
}

// ============================================================================
// SIMD Aggregation Functions
// ============================================================================

/// Compute sum of a numeric column using SIMD acceleration
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///
/// Returns: Sum as f64, or NaN on error
export fn rozes_sum(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
) f64 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        return std.math.nan(f64);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const col = df.column(col_name) orelse {
        return std.math.nan(f64);
    };

    const simd_mod = @import("core/simd.zig");

    return switch (col.value_type) {
        .Int64 => blk: {
            const data = col.asInt64() orelse return std.math.nan(f64);
            const sum = simd_mod.sumInt64(data);
            break :blk @as(f64, @floatFromInt(sum));
        },
        .Float64 => blk: {
            const data = col.asFloat64() orelse return std.math.nan(f64);
            break :blk simd_mod.sumFloat64(data);
        },
        else => std.math.nan(f64),
    };
}

/// Compute mean of a numeric column using SIMD acceleration
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///
/// Returns: Mean as f64, or NaN on error
export fn rozes_mean(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
) f64 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        return std.math.nan(f64);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const col = df.column(col_name) orelse {
        return std.math.nan(f64);
    };

    const simd_mod = @import("core/simd.zig");

    return switch (col.value_type) {
        .Int64 => blk: {
            const data = col.asInt64() orelse return std.math.nan(f64);
            break :blk simd_mod.meanInt64(data) orelse std.math.nan(f64);
        },
        .Float64 => blk: {
            const data = col.asFloat64() orelse return std.math.nan(f64);
            break :blk simd_mod.meanFloat64(data) orelse std.math.nan(f64);
        },
        else => std.math.nan(f64),
    };
}

/// Compute minimum of a numeric column using SIMD acceleration
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///
/// Returns: Minimum as f64, or NaN on error
export fn rozes_min(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
) f64 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        return std.math.nan(f64);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const col = df.column(col_name) orelse {
        return std.math.nan(f64);
    };

    const simd_mod = @import("core/simd.zig");

    return switch (col.value_type) {
        .Float64 => blk: {
            const data = col.asFloat64() orelse return std.math.nan(f64);
            break :blk simd_mod.minFloat64(data) orelse std.math.nan(f64);
        },
        .Int64 => blk: {
            // For Int64, convert to Float64 for min
            const data = col.asInt64() orelse return std.math.nan(f64);
            if (data.len == 0) return std.math.nan(f64);

            var min_val = data[0];
            for (data[1..]) |val| {
                if (val < min_val) min_val = val;
            }
            break :blk @as(f64, @floatFromInt(min_val));
        },
        else => std.math.nan(f64),
    };
}

/// Compute maximum of a numeric column using SIMD acceleration
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///
/// Returns: Maximum as f64, or NaN on error
export fn rozes_max(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
) f64 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        return std.math.nan(f64);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const col = df.column(col_name) orelse {
        return std.math.nan(f64);
    };

    const simd_mod = @import("core/simd.zig");

    return switch (col.value_type) {
        .Float64 => blk: {
            const data = col.asFloat64() orelse return std.math.nan(f64);
            break :blk simd_mod.maxFloat64(data) orelse std.math.nan(f64);
        },
        .Int64 => blk: {
            // For Int64, convert to Float64 for max
            const data = col.asInt64() orelse return std.math.nan(f64);
            if (data.len == 0) return std.math.nan(f64);

            var max_val = data[0];
            for (data[1..]) |val| {
                if (val > max_val) max_val = val;
            }
            break :blk @as(f64, @floatFromInt(max_val));
        },
        else => std.math.nan(f64),
    };
}

/// Compute variance of a numeric column using SIMD acceleration
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///
/// Returns: Variance as f64, or NaN on error
export fn rozes_variance(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
) f64 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        return std.math.nan(f64);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const stats_mod = @import("core/stats.zig");

    const result = stats_mod.variance(df, col_name) catch {
        return std.math.nan(f64);
    };

    return result orelse std.math.nan(f64);
}

/// Compute standard deviation of a numeric column using SIMD acceleration
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///
/// Returns: Standard deviation as f64, or NaN on error
export fn rozes_stddev(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
) f64 {
    std.debug.assert(handle >= 0);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        return std.math.nan(f64);
    };

    const col_name = col_name_ptr[0..col_name_len];
    const stats_mod = @import("core/stats.zig");

    const result = stats_mod.stdDev(df, col_name) catch {
        return std.math.nan(f64);
    };

    return result orelse std.math.nan(f64);
}

// ============================================================================
// Missing Data Operations (Phase 2 - Milestone 1.3.0)
// ============================================================================

const missing = @import("core/missing.zig");

/// Fill missing values with a constant
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///   - fill_value: Value to fill missing entries with
///
/// Returns: New DataFrame handle, or error code on failure
export fn rozes_fillna(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    fill_value: f64,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];

    // Get the column
    const col = df.column(col_name) orelse {
        logError("fillna: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Fill missing values
    const filled_series = missing.fillna(col, allocator, .Constant, fill_value) catch |err| {
        logError("fillna failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // For now, just return the original DataFrame handle
    // TODO: Implement proper column replacement when DataFrame.clone() is available
    _ = filled_series;

    logError("fillna: Column replacement not yet implemented", .{});
    return @intFromEnum(ErrorCode.InvalidFormat);
}

/// Drop rows with missing values
///
/// Args:
///   - handle: DataFrame handle
///
/// Returns: New DataFrame handle, or error code on failure
export fn rozes_dropna(handle: i32) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();

    // Drop rows with any missing values
    const cleaned_df = missing.dropna(df, allocator, .{}) catch |err| {
        logError("dropna failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Create DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = cleaned_df;

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Check for missing values in a column
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///   - out_ptr: Output pointer for boolean array
///   - out_len: Output length
///
/// Returns: 0 on success, error code on failure
export fn rozes_isna(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    out_ptr: *u32,
    out_len: *u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];

    // Get the column
    const col = df.column(col_name) orelse {
        logError("isna: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Get missing value mask
    const mask_series = missing.isna(col, allocator) catch |err| {
        logError("isna failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };
    defer allocator.free(mask_series.data.Bool);

    const mask = mask_series.data.Bool;

    // Allocate buffer for result
    const result_buf = allocator.alloc(u8, mask.len) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    // Convert bool array to byte array
    var i: u32 = 0;
    while (i < mask.len) : (i += 1) {
        result_buf[i] = if (mask[i]) 1 else 0;
    }
    // Post-condition: Converted all bool values
    std.debug.assert(i == mask.len);

    out_ptr.* = @intFromPtr(result_buf.ptr);
    out_len.* = @intCast(result_buf.len);

    return @intFromEnum(ErrorCode.Success);
}

/// Check for non-missing values in a column
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///   - out_ptr: Output pointer for boolean array
///   - out_len: Output length
///
/// Returns: 0 on success, error code on failure
export fn rozes_notna(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    out_ptr: *u32,
    out_len: *u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];

    // Get the column
    const col = df.column(col_name) orelse {
        logError("notna: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Get non-missing value mask
    const mask_series = missing.notna(col, allocator) catch |err| {
        logError("notna failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };
    defer allocator.free(mask_series.data.Bool);

    const mask = mask_series.data.Bool;

    // Allocate buffer for result
    const result_buf = allocator.alloc(u8, mask.len) catch {
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    // Convert bool array to byte array
    var i: u32 = 0;
    while (i < mask.len) : (i += 1) {
        result_buf[i] = if (mask[i]) 1 else 0;
    }
    // Post-condition: Converted all bool values
    std.debug.assert(i == mask.len);

    out_ptr.* = @intFromPtr(result_buf.ptr);
    out_len.* = @intCast(result_buf.len);

    return @intFromEnum(ErrorCode.Success);
}

// ============================================================================
// String Operations - DataFrame column string manipulation
// ============================================================================

/// Convert string column to lowercase
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///
/// Returns: New DataFrame handle with lowercased strings, or error code
export fn rozes_str_lower(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        logError("str_lower: Invalid handle {}", .{handle});
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];

    // Get the column
    const col = df.column(col_name) orelse {
        logError("str_lower: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Apply lower operation
    const lower_series = string_ops.lower(col, allocator) catch |err| {
        logError("str_lower failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Replace column in cloned DataFrame
    var new_df = operations.replaceColumn(df, col_name, lower_series) catch |err| {
        // Clean up series on error
        allocator.free(lower_series.data.String.offsets);
        allocator.free(lower_series.data.String.buffer);
        if (lower_series.data.String.hash_cache) |cache| allocator.free(cache);
        logError("str_lower: replaceColumn failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Create DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        new_df.deinit();
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = new_df;

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Convert string column to uppercase
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///
/// Returns: New DataFrame handle with uppercased strings, or error code
export fn rozes_str_upper(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        logError("str_upper: Invalid handle {}", .{handle});
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];

    // Get the column
    const col = df.column(col_name) orelse {
        logError("str_upper: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Apply upper operation
    const upper_series = string_ops.upper(col, allocator) catch |err| {
        logError("str_upper failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Replace column in cloned DataFrame
    var new_df = operations.replaceColumn(df, col_name, upper_series) catch |err| {
        // Clean up series on error
        allocator.free(upper_series.data.String.offsets);
        allocator.free(upper_series.data.String.buffer);
        if (upper_series.data.String.hash_cache) |cache| allocator.free(cache);
        logError("str_upper: replaceColumn failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Create DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        new_df.deinit();
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = new_df;

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Trim leading and trailing whitespace from string column
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///
/// Returns: New DataFrame handle with trimmed strings, or error code
export fn rozes_str_trim(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        logError("str_trim: Invalid handle {}", .{handle});
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];

    // Get the column
    const col = df.column(col_name) orelse {
        logError("str_trim: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Apply trim operation
    const trim_series = string_ops.trim(col, allocator) catch |err| {
        logError("str_trim failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Replace column in cloned DataFrame
    var new_df = operations.replaceColumn(df, col_name, trim_series) catch |err| {
        // Clean up series on error
        allocator.free(trim_series.data.String.offsets);
        allocator.free(trim_series.data.String.buffer);
        if (trim_series.data.String.hash_cache) |cache| allocator.free(cache);
        logError("str_trim: replaceColumn failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Create DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        new_df.deinit();
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = new_df;

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Check if string column contains substring
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///   - pattern_ptr: Pointer to pattern string
///   - pattern_len: Length of pattern
///
/// Returns: New DataFrame handle with boolean column, or error code
export fn rozes_str_contains(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    pattern_ptr: [*]const u8,
    pattern_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        logError("str_contains: Invalid handle {}", .{handle});
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];
    // Handle empty pattern - pass empty slice (standard behavior: empty pattern matches everything)
    const pattern = if (pattern_len > 0) pattern_ptr[0..pattern_len] else "";

    // Get the column
    const col = df.column(col_name) orelse {
        logError("str_contains: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Apply contains operation
    const contains_series = string_ops.contains(col, allocator, pattern) catch |err| {
        logError("str_contains failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Replace column in cloned DataFrame
    var new_df = operations.replaceColumn(df, col_name, contains_series) catch |err| {
        // Clean up series on error
        allocator.free(contains_series.data.Bool);
        logError("str_contains: replaceColumn failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Create DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        new_df.deinit();
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = new_df;

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Replace substring in string column
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///   - from_ptr: Pointer to "from" string
///   - from_len: Length of "from"
///   - to_ptr: Pointer to "to" string
///   - to_len: Length of "to"
///
/// Returns: New DataFrame handle with replaced strings, or error code
export fn rozes_str_replace(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    from_ptr: [*]const u8,
    from_len: u32,
    to_ptr: [*]const u8,
    to_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        logError("str_replace: Invalid handle {}", .{handle});
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];
    const from = from_ptr[0..from_len];
    const to = to_ptr[0..to_len];

    // Get the column
    const col = df.column(col_name) orelse {
        logError("str_replace: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Apply replace operation
    const replace_series = string_ops.replace(col, allocator, from, to) catch |err| {
        logError("str_replace failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Replace column in cloned DataFrame
    var new_df = operations.replaceColumn(df, col_name, replace_series) catch |err| {
        // Clean up series on error
        allocator.free(replace_series.data.String.offsets);
        allocator.free(replace_series.data.String.buffer);
        if (replace_series.data.String.hash_cache) |cache| allocator.free(cache);
        logError("str_replace: replaceColumn failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Create DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        new_df.deinit();
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = new_df;

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Extract substring from string column
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///   - start: Start index (inclusive)
///   - end: End index (exclusive)
///
/// Returns: New DataFrame handle with sliced strings, or error code
export fn rozes_str_slice(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    start: u32,
    end: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        logError("str_slice: Invalid handle {}", .{handle});
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];

    // Get the column
    const col = df.column(col_name) orelse {
        logError("str_slice: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Apply slice operation
    const slice_series = string_ops.slice(col, allocator, start, end) catch |err| {
        logError("str_slice failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Replace column in cloned DataFrame
    var new_df = operations.replaceColumn(df, col_name, slice_series) catch |err| {
        // Clean up series on error
        allocator.free(slice_series.data.String.offsets);
        allocator.free(slice_series.data.String.buffer);
        if (slice_series.data.String.hash_cache) |cache| allocator.free(cache);
        logError("str_slice: replaceColumn failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Create DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        new_df.deinit();
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = new_df;

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Get string lengths from string column
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///
/// Returns: New DataFrame handle with integer column of lengths, or error code
export fn rozes_str_len(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        logError("str_len: Invalid handle {}", .{handle});
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];

    // Get the column
    const col = df.column(col_name) orelse {
        logError("str_len: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Apply len operation
    const len_series = string_ops.len(col, allocator) catch |err| {
        logError("str_len failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Replace column in cloned DataFrame
    var new_df = operations.replaceColumn(df, col_name, len_series) catch |err| {
        // Clean up series on error
        allocator.free(len_series.data.Int64);
        logError("str_len: replaceColumn failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Create DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        new_df.deinit();
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = new_df;

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Check if strings start with prefix
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///   - prefix_ptr: Pointer to prefix string
///   - prefix_len: Length of prefix
///
/// Returns: New DataFrame handle with boolean column, or error code
export fn rozes_str_startsWith(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    prefix_ptr: [*]const u8,
    prefix_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        logError("str_startsWith: Invalid handle {}", .{handle});
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];
    // Handle empty prefix - pass empty slice (standard behavior: empty prefix matches everything)
    const prefix = if (prefix_len > 0) prefix_ptr[0..prefix_len] else "";

    // Get the column
    const col = df.column(col_name) orelse {
        logError("str_startsWith: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Apply startsWith operation
    const starts_series = string_ops.startsWith(col, allocator, prefix) catch |err| {
        logError("str_startsWith failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Replace column in cloned DataFrame
    var new_df = operations.replaceColumn(df, col_name, starts_series) catch |err| {
        // Clean up series on error
        allocator.free(starts_series.data.Bool);
        logError("str_startsWith: replaceColumn failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Create DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        new_df.deinit();
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = new_df;

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}

/// Check if strings end with suffix
///
/// Args:
///   - handle: DataFrame handle
///   - col_name_ptr: Pointer to column name string
///   - col_name_len: Length of column name
///   - suffix_ptr: Pointer to suffix string
///   - suffix_len: Length of suffix
///
/// Returns: New DataFrame handle with boolean column, or error code
export fn rozes_str_endsWith(
    handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    suffix_ptr: [*]const u8,
    suffix_len: u32,
) i32 {
    std.debug.assert(handle >= 0);
    std.debug.assert(handle < MAX_DATAFRAMES);
    std.debug.assert(col_name_len > 0);

    const df = registry.get(handle) orelse {
        logError("str_endsWith: Invalid handle {}", .{handle});
        return @intFromEnum(ErrorCode.InvalidHandle);
    };

    const allocator = getAllocator();
    const col_name = col_name_ptr[0..col_name_len];
    // Handle empty suffix - pass empty slice (standard behavior: empty suffix matches everything)
    const suffix = if (suffix_len > 0) suffix_ptr[0..suffix_len] else "";

    // Get the column
    const col = df.column(col_name) orelse {
        logError("str_endsWith: Column '{s}' not found", .{col_name});
        return @intFromEnum(ErrorCode.ColumnNotFound);
    };

    // Apply endsWith operation
    const ends_series = string_ops.endsWith(col, allocator, suffix) catch |err| {
        logError("str_endsWith failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Replace column in cloned DataFrame
    var new_df = operations.replaceColumn(df, col_name, ends_series) catch |err| {
        // Clean up series on error
        allocator.free(ends_series.data.Bool);
        logError("str_endsWith: replaceColumn failed: {}", .{err});
        return @intFromEnum(ErrorCode.fromError(err));
    };

    // Create DataFrame on heap
    const new_df_ptr = allocator.create(DataFrame) catch {
        new_df.deinit();
        return @intFromEnum(ErrorCode.OutOfMemory);
    };

    new_df_ptr.* = new_df;

    // Register result
    const new_handle = registry.register(new_df_ptr) catch {
        new_df_ptr.deinit();
        allocator.destroy(new_df_ptr);
        return @intFromEnum(ErrorCode.TooManyDataFrames);
    };

    std.debug.assert(new_handle >= 0);
    std.debug.assert(new_handle < MAX_DATAFRAMES);

    return new_handle;
}
