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
    _,

    pub fn fromError(err: anyerror) ErrorCode {
        return switch (err) {
            error.OutOfMemory => .OutOfMemory,
            error.InvalidFormat => .InvalidFormat,
            error.ColumnNotFound => .ColumnNotFound,
            error.TypeMismatch => .TypeMismatch,
            error.IndexOutOfBounds => .IndexOutOfBounds,
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

// NOTE: String column export deferred to 0.2.0
// Browser tests use Int64/Float64/Bool columns only for MVP

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
            std.mem.indexOf(u8, json, "\"has_headers\": true") != null) {
            opts.has_headers = true;
        } else if (std.mem.indexOf(u8, json, "\"has_headers\":false") != null or
                   std.mem.indexOf(u8, json, "\"has_headers\": false") != null) {
            opts.has_headers = false;
        }
    }

    // Check for "skip_blank_lines":true or "skip_blank_lines":false
    if (std.mem.indexOf(u8, json, "\"skip_blank_lines\"") != null) {
        if (std.mem.indexOf(u8, json, "\"skip_blank_lines\":true") != null or
            std.mem.indexOf(u8, json, "\"skip_blank_lines\": true") != null) {
            opts.skip_blank_lines = true;
        } else if (std.mem.indexOf(u8, json, "\"skip_blank_lines\":false") != null or
                   std.mem.indexOf(u8, json, "\"skip_blank_lines\": false") != null) {
            opts.skip_blank_lines = false;
        }
    }

    // Check for "trim_whitespace":true or "trim_whitespace":false
    if (std.mem.indexOf(u8, json, "\"trim_whitespace\"") != null) {
        if (std.mem.indexOf(u8, json, "\"trim_whitespace\":true") != null or
            std.mem.indexOf(u8, json, "\"trim_whitespace\": true") != null) {
            opts.trim_whitespace = true;
        } else if (std.mem.indexOf(u8, json, "\"trim_whitespace\":false") != null or
                   std.mem.indexOf(u8, json, "\"trim_whitespace\": false") != null) {
            opts.trim_whitespace = false;
        }
    }

    // Check for "delimiter":"," or "delimiter":"\t"
    if (std.mem.indexOf(u8, json, "\"delimiter\"") != null) {
        if (std.mem.indexOf(u8, json, "\"delimiter\":\",\"") != null or
            std.mem.indexOf(u8, json, "\"delimiter\": \",\"") != null) {
            opts.delimiter = ',';
        } else if (std.mem.indexOf(u8, json, "\"delimiter\":\"\\t\"") != null or
                   std.mem.indexOf(u8, json, "\"delimiter\": \"\\t\"") != null) {
            opts.delimiter = '\t';
        } else if (std.mem.indexOf(u8, json, "\"delimiter\":\";\"") != null or
                   std.mem.indexOf(u8, json, "\"delimiter\": \";\"") != null) {
            opts.delimiter = ';';
        }
    }

    std.debug.assert(opts.delimiter != 0); // Post-condition: Valid delimiter
    std.debug.assert(opts.delimiter == ',' or opts.delimiter == '\t' or opts.delimiter == ';'); // Post-condition: Known delimiters

    return opts;
}
