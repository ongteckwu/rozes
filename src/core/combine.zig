// combine.zig - DataFrame combination operations (concat, merge, append, update)
//
// This module provides operations for combining multiple DataFrames:
// - concat(): Vertical or horizontal stacking
// - merge(): SQL-style joins (inner, left, right, outer, cross)
// - append(): Add rows to existing DataFrame
// - update(): Modify values based on another DataFrame
//
// Tiger Style: 2+ assertions per function, bounded loops, explicit error handling

const std = @import("std");
const types = @import("types.zig");
const DataFrame = @import("dataframe.zig").DataFrame;
const Series = @import("series.zig").Series;
const ColumnDesc = types.ColumnDesc;
const ValueType = types.ValueType;
const Allocator = std.mem.Allocator;

// Maximum number of DataFrames that can be concatenated at once
const MAX_CONCAT_DFS = 1000;

// Maximum number of columns across all DataFrames in concat
const MAX_TOTAL_COLUMNS = 10000;

// Maximum rows in result DataFrame
const MAX_ROWS: u32 = std.math.maxInt(u32);

// Axis for concatenation
pub const ConcatAxis = enum {
    vertical, // Stack rows (axis=0, default)
    horizontal, // Stack columns (axis=1)
};

// Options for concat operation
pub const ConcatOptions = struct {
    axis: ConcatAxis = .vertical,
    ignore_index: bool = false, // If true, don't use existing index
};

// Concatenate multiple DataFrames
//
// Vertical (axis=0):
// - Stacks DataFrames on top of each other (row-wise)
// - Aligns columns by name
// - Missing columns filled with NaN/default values
//
// Horizontal (axis=1):
// - Stacks DataFrames side by side (column-wise)
// - All DataFrames must have same row count
// - Column names must be unique (or use suffixes)
//
// Example:
//   const combined = try concat(allocator, &[_]*DataFrame{df1, df2, df3}, .{
//       .axis = .vertical,
//       .ignore_index = false,
//   });
//

/// Type promotion hierarchy for concat operations
/// Hierarchy: Bool < Int64 < Float64 < String (most general)
/// Categorical is treated specially (not automatically promoted)
fn promoteTypes(t1: ValueType, t2: ValueType) !ValueType {
    std.debug.assert(@intFromEnum(t1) >= 0); // Valid enum
    std.debug.assert(@intFromEnum(t2) >= 0); // Valid enum

    // Same type - no promotion needed
    if (t1 == t2) return t1;

    // Numeric promotion chain: Bool → Int64 → Float64
    if ((t1 == .Bool or t1 == .Int64) and t2 == .Float64) return .Float64;
    if (t1 == .Float64 and (t2 == .Bool or t2 == .Int64)) return .Float64;
    if (t1 == .Bool and t2 == .Int64) return .Int64;
    if (t1 == .Int64 and t2 == .Bool) return .Int64;

    // String is universal fallback (can represent anything)
    if (t1 == .String or t2 == .String) return .String;

    // Categorical + anything else → error (requires explicit handling)
    if (t1 == .Categorical or t2 == .Categorical) {
        std.log.err("Cannot auto-promote Categorical type with {any}", .{if (t1 == .Categorical) t2 else t1});
        return error.IncompatibleColumnTypes;
    }

    // Null type - promote to other type
    if (t1 == .Null) return t2;
    if (t2 == .Null) return t1;

    // Incompatible types with no clear promotion
    std.debug.assert(t1 != t2); // Post-condition
    return error.IncompatibleColumnTypes;
}

pub fn concat(
    allocator: Allocator,
    dataframes: []*const DataFrame,
    options: ConcatOptions,
) !DataFrame {
    // Pre-condition: At least 1 DataFrame
    std.debug.assert(dataframes.len > 0);
    std.debug.assert(dataframes.len <= MAX_CONCAT_DFS);

    // Pre-condition: All DataFrames non-null and have columns
    var df_idx: u32 = 0;
    while (df_idx < dataframes.len and df_idx < MAX_CONCAT_DFS) : (df_idx += 1) {
        std.debug.assert(dataframes[df_idx].columns.len > 0);
    }
    std.debug.assert(df_idx == dataframes.len or df_idx == MAX_CONCAT_DFS);

    // Single DataFrame - treat as concat of one (which creates a copy)
    if (dataframes.len == 1) {
        // Just proceed with normal concat logic, which will create a copy
    }

    // Dispatch to vertical or horizontal concat
    return switch (options.axis) {
        .vertical => try concatVertical(allocator, dataframes, options),
        .horizontal => try concatHorizontal(allocator, dataframes, options),
    };
}

// Concatenate DataFrames vertically (stack rows)
fn concatVertical(
    allocator: Allocator,
    dataframes: []*const DataFrame,
    options: ConcatOptions,
) !DataFrame {
    _ = options; // TODO: Handle ignore_index

    // Pre-condition: At least 1 DataFrame
    std.debug.assert(dataframes.len >= 1);

    // Step 1: Collect all unique column names (union of all schemas)
    var all_columns = std.StringHashMap(ValueType).init(allocator);
    defer all_columns.deinit();

    var df_idx: u32 = 0;
    while (df_idx < dataframes.len and df_idx < MAX_CONCAT_DFS) : (df_idx += 1) {
        const df = dataframes[df_idx];
        var col_idx: u32 = 0;
        while (col_idx < df.columns.len and col_idx < MAX_TOTAL_COLUMNS) : (col_idx += 1) {
            const col = &df.columns[col_idx];

            // Add column if not already present
            const result = try all_columns.getOrPut(col.name);
            if (!result.found_existing) {
                result.value_ptr.* = col.value_type;
            } else {
                // Column already exists - check type compatibility and promote
                if (result.value_ptr.* != col.value_type) {
                    const promoted = promoteTypes(result.value_ptr.*, col.value_type) catch {
                        std.log.err("Cannot concat columns with incompatible types {any} and {any}", .{ result.value_ptr.*, col.value_type });
                        return error.IncompatibleColumnTypes;
                    };
                    result.value_ptr.* = promoted;
                }
            }
        }
        std.debug.assert(col_idx == df.columns.len or col_idx == MAX_TOTAL_COLUMNS);
    }
    std.debug.assert(df_idx == dataframes.len or df_idx == MAX_CONCAT_DFS);

    // Step 2: Calculate total row count
    var total_rows: u32 = 0;
    df_idx = 0;
    while (df_idx < dataframes.len and df_idx < MAX_CONCAT_DFS) : (df_idx += 1) {
        total_rows += dataframes[df_idx].row_count;
    }
    std.debug.assert(df_idx == dataframes.len or df_idx == MAX_CONCAT_DFS);

    // Step 3: Create column descriptors for result
    // Check overflow before cast
    const num_columns_usize = all_columns.count();
    if (num_columns_usize > MAX_TOTAL_COLUMNS) {
        std.log.err("Concat would create {} columns (max {})", .{ num_columns_usize, MAX_TOTAL_COLUMNS });
        return error.TooManyColumns;
    }
    const num_columns: u32 = @intCast(num_columns_usize);
    var column_descs = try allocator.alloc(ColumnDesc, num_columns);
    defer allocator.free(column_descs);

    // Get sorted column names for deterministic order
    var column_names = try allocator.alloc([]const u8, num_columns);
    defer allocator.free(column_names);

    var iter = all_columns.iterator();
    var col_idx: u32 = 0;
    while (iter.next()) |entry| : (col_idx += 1) {
        column_names[col_idx] = entry.key_ptr.*;
    }
    std.debug.assert(col_idx == num_columns);

    // Sort column names for deterministic order
    std.mem.sort([]const u8, column_names, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    // Create column descriptors
    col_idx = 0;
    while (col_idx < num_columns and col_idx < MAX_TOTAL_COLUMNS) : (col_idx += 1) {
        const col_name = column_names[col_idx];
        const col_type = all_columns.get(col_name).?;
        column_descs[col_idx] = ColumnDesc.init(col_name, col_type, col_idx);
    }
    std.debug.assert(col_idx == num_columns or col_idx == MAX_TOTAL_COLUMNS);

    // Step 4: Create result DataFrame
    var result = try DataFrame.create(allocator, column_descs, total_rows);
    errdefer result.deinit();

    result.row_count = total_rows;

    // Set Series lengths to total_rows (capacity was allocated, but length starts at 0)
    col_idx = 0;
    while (col_idx < num_columns and col_idx < MAX_TOTAL_COLUMNS) : (col_idx += 1) {
        result.columns[col_idx].length = total_rows;
    }
    std.debug.assert(col_idx == num_columns or col_idx == MAX_TOTAL_COLUMNS);

    // Step 5: Copy data from each DataFrame
    var current_row: u32 = 0;
    df_idx = 0;
    while (df_idx < dataframes.len and df_idx < MAX_CONCAT_DFS) : (df_idx += 1) {
        const source_df = dataframes[df_idx];

        // For each column in result
        col_idx = 0;
        while (col_idx < num_columns and col_idx < MAX_TOTAL_COLUMNS) : (col_idx += 1) {
            const dest_col = &result.columns[col_idx];

            // Find matching column in source DataFrame
            const source_col_opt = source_df.column(dest_col.name);

            if (source_col_opt) |source_col| {
                // Column exists - copy data
                try copySeriesData(allocator, dest_col, source_col, current_row, 0, source_df.row_count);
            } else {
                // Column missing - fill with NaN/default
                try fillSeriesWithDefault(dest_col, current_row, source_df.row_count);
            }
        }
        std.debug.assert(col_idx == num_columns or col_idx == MAX_TOTAL_COLUMNS);

        current_row += source_df.row_count;
    }
    std.debug.assert(df_idx == dataframes.len or df_idx == MAX_CONCAT_DFS);
    std.debug.assert(current_row == total_rows);

    // Post-condition: Result has correct dimensions
    std.debug.assert(result.columns.len == num_columns);
    std.debug.assert(result.row_count == total_rows);

    return result;
}

// Concatenate DataFrames horizontally (stack columns)
fn concatHorizontal(
    allocator: Allocator,
    dataframes: []*const DataFrame,
    options: ConcatOptions,
) !DataFrame {
    _ = options;

    // Pre-condition: At least 1 DataFrame
    std.debug.assert(dataframes.len >= 1);

    // Pre-condition: All DataFrames have same row count
    const expected_rows = dataframes[0].row_count;
    var df_idx: u32 = 1;
    while (df_idx < dataframes.len and df_idx < MAX_CONCAT_DFS) : (df_idx += 1) {
        if (dataframes[df_idx].row_count != expected_rows) {
            return error.RowCountMismatch;
        }
    }
    std.debug.assert(df_idx == dataframes.len or df_idx == MAX_CONCAT_DFS);

    // Step 1: Count total columns and create descriptors
    var total_columns: u32 = 0;
    df_idx = 0;
    while (df_idx < dataframes.len and df_idx < MAX_CONCAT_DFS) : (df_idx += 1) {
        total_columns += @as(u32, @intCast(dataframes[df_idx].columns.len));
    }
    std.debug.assert(df_idx == dataframes.len or df_idx == MAX_CONCAT_DFS);
    std.debug.assert(total_columns <= MAX_TOTAL_COLUMNS);

    var column_descs = try allocator.alloc(ColumnDesc, total_columns);
    defer allocator.free(column_descs);

    // Collect all column descriptors
    var dest_idx: u32 = 0;
    df_idx = 0;
    while (df_idx < dataframes.len and df_idx < MAX_CONCAT_DFS) : (df_idx += 1) {
        const source_df = dataframes[df_idx];

        var src_idx: u32 = 0;
        while (src_idx < source_df.columns.len and src_idx < MAX_TOTAL_COLUMNS) : (src_idx += 1) {
            const source_col = &source_df.columns[src_idx];
            column_descs[dest_idx] = ColumnDesc.init(source_col.name, source_col.value_type, dest_idx);
            dest_idx += 1;
        }
        std.debug.assert(src_idx == source_df.columns.len or src_idx == MAX_TOTAL_COLUMNS);
    }
    std.debug.assert(df_idx == dataframes.len or df_idx == MAX_CONCAT_DFS);
    std.debug.assert(dest_idx == total_columns);

    // Step 2: Create result DataFrame
    var result = try DataFrame.create(allocator, column_descs, expected_rows);
    errdefer result.deinit();

    result.row_count = expected_rows;

    // Set Series lengths to expected_rows
    dest_idx = 0;
    while (dest_idx < total_columns and dest_idx < MAX_TOTAL_COLUMNS) : (dest_idx += 1) {
        result.columns[dest_idx].length = expected_rows;
    }
    std.debug.assert(dest_idx == total_columns or dest_idx == MAX_TOTAL_COLUMNS);

    // Step 3: Copy all columns
    dest_idx = 0;
    df_idx = 0;
    while (df_idx < dataframes.len and df_idx < MAX_CONCAT_DFS) : (df_idx += 1) {
        const source_df = dataframes[df_idx];

        var src_idx: u32 = 0;
        while (src_idx < source_df.columns.len and src_idx < MAX_TOTAL_COLUMNS) : (src_idx += 1) {
            const source_col = &source_df.columns[src_idx];
            const dest_col = &result.columns[dest_idx];

            // Copy data
            try copySeriesData(allocator, dest_col, source_col, 0, 0, expected_rows);

            dest_idx += 1;
        }
        std.debug.assert(src_idx == source_df.columns.len or src_idx == MAX_TOTAL_COLUMNS);
    }
    std.debug.assert(df_idx == dataframes.len or df_idx == MAX_CONCAT_DFS);
    std.debug.assert(dest_idx == total_columns);

    // Post-condition: Result has correct dimensions
    std.debug.assert(result.columns.len == total_columns);
    std.debug.assert(result.row_count == expected_rows);

    return result;
}

// Copy data from source series to destination series
fn copySeriesData(
    allocator: Allocator,
    dest: *Series,
    source: *const Series,
    dest_start: u32,
    source_start: u32,
    count: u32,
) !void {
    // Pre-conditions
    std.debug.assert(@intFromPtr(&allocator) != 0); // Pre-condition: Valid allocator
    std.debug.assert(dest_start + count <= dest.length); // Pre-condition: Destination bounds
    std.debug.assert(source_start + count <= source.length); // Pre-condition: Source bounds

    // If types match, direct copy
    if (dest.value_type == source.value_type) {
        switch (dest.value_type) {
            .Int64 => {
                const dest_data = dest.data.Int64;
                const source_data = source.data.Int64;
                @memcpy(dest_data[dest_start .. dest_start + count], source_data[source_start .. source_start + count]);
            },
            .Float64 => {
                const dest_data = dest.data.Float64;
                const source_data = source.data.Float64;
                @memcpy(dest_data[dest_start .. dest_start + count], source_data[source_start .. source_start + count]);
            },
            .Bool => {
                const dest_data = dest.data.Bool;
                const source_data = source.data.Bool;
                @memcpy(dest_data[dest_start .. dest_start + count], source_data[source_start .. source_start + count]);
            },
            .String => {
                // For strings, we need to copy to the destination StringColumn
                // This is complex because StringColumn uses offset-based storage
                // For concat, we're appending to the end, so dest_start == dest.count
                var dest_string_col = &dest.data.String;
                const source_string_col = &source.data.String;

                // Verify we're appending to the end (concat pattern)
                std.debug.assert(dest_start == dest_string_col.count);

                // Copy each string by appending
                var i: u32 = 0;
                const MAX_STRING_COPY: u32 = 1_000_000;
                while (i < count and i < MAX_STRING_COPY) : (i += 1) {
                    const str = source_string_col.get(source_start + i);
                    try dest_string_col.append(allocator, str);
                }
                std.debug.assert(i == count or i == MAX_STRING_COPY);
            },
            .Categorical => {
                // For categorical, need to remap indices if dictionaries differ
                // For now, just copy indices (assumes same dictionary)
                const dest_data = dest.data.Categorical.codes;
                const source_data = source.data.Categorical.codes;
                @memcpy(dest_data[dest_start .. dest_start + count], source_data[source_start .. source_start + count]);
            },
            .Null => {
                // Nothing to copy for Null type
            },
        }
    } else {
        // Type conversion needed (Int64 → Float64)
        if (dest.value_type == .Float64 and source.value_type == .Int64) {
            const dest_data = dest.data.Float64;
            const source_data = source.data.Int64;

            var i: u32 = 0;
            while (i < count) : (i += 1) {
                dest_data[dest_start + i] = @floatFromInt(source_data[source_start + i]);
            }
            std.debug.assert(i == count);
        } else {
            return error.IncompatibleTypes;
        }
    }

    // Post-condition: Data copied
    std.debug.assert(dest_start + count <= dest.length);
}

// Fill series with default values (NaN for numeric, empty for string)
fn fillSeriesWithDefault(series: *Series, start: u32, count: u32) !void {
    // Pre-condition
    std.debug.assert(start + count <= series.length);

    switch (series.value_type) {
        .Int64 => {
            const data = series.data.Int64;
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                data[start + i] = 0; // Default to 0 for integers
            }
            std.debug.assert(i == count);
        },
        .Float64 => {
            const data = series.data.Float64;
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                data[start + i] = std.math.nan(f64);
            }
            std.debug.assert(i == count);
        },
        .Bool => {
            const data = series.data.Bool;
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                data[start + i] = false; // Default to false
            }
            std.debug.assert(i == count);
        },
        .String => {
            // TODO: Implement string default filling
            // For now, strings will be left as-is
        },
        .Categorical => {
            const data = series.data.Categorical.codes;
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                data[start + i] = 0; // Default to first category (or invalid)
            }
            std.debug.assert(i == count);
        },
        .Null => {
            // Nothing to fill for Null type
        },
    }

    // Post-condition
    std.debug.assert(start + count <= series.length);
}

// ============================================================================
// Merge Operations (SQL-style joins)
// ============================================================================

// Maximum number of keys for multi-column merge
const MAX_MERGE_KEYS = 10;

// Maximum matches per key in join operation
const MAX_MATCHES_PER_KEY: u32 = 100_000;

// Merge strategy
pub const MergeHow = enum {
    inner, // Only matching keys (intersection)
    left, // All from left, matching from right
    right, // All from right, matching from left
    outer, // All keys from both (union)
    cross, // Cartesian product (all combinations)
};

// Options for merge operation
pub const MergeOptions = struct {
    how: MergeHow = .inner,
    left_on: []const []const u8, // Column names from left DataFrame
    right_on: []const []const u8, // Column names from right DataFrame
    suffixes: struct {
        left: []const u8 = "_x",
        right: []const u8 = "_y",
    } = .{},
};

// Merge two DataFrames using SQL-style join
//
// Example:
//   const merged = try merge(allocator, &left, &right, .{
//       .how = .inner,
//       .left_on = &[_][]const u8{"id"},
//       .right_on = &[_][]const u8{"user_id"},
//   });
//
pub fn merge(
    allocator: Allocator,
    left: *const DataFrame,
    right: *const DataFrame,
    options: MergeOptions,
) !DataFrame {
    // Pre-conditions
    std.debug.assert(left.columns.len > 0);
    std.debug.assert(right.columns.len > 0);
    std.debug.assert(options.left_on.len > 0);
    std.debug.assert(options.left_on.len == options.right_on.len);
    std.debug.assert(options.left_on.len <= MAX_MERGE_KEYS);

    // Validate merge keys exist
    var key_idx: u32 = 0;
    while (key_idx < options.left_on.len and key_idx < MAX_MERGE_KEYS) : (key_idx += 1) {
        const left_key = options.left_on[key_idx];
        const right_key = options.right_on[key_idx];

        if (left.column(left_key) == null) {
            std.log.err("Left merge key not found: {s}", .{left_key});
            return error.ColumnNotFound;
        }
        if (right.column(right_key) == null) {
            std.log.err("Right merge key not found: {s}", .{right_key});
            return error.ColumnNotFound;
        }
    }
    std.debug.assert(key_idx == options.left_on.len or key_idx == MAX_MERGE_KEYS);

    // Dispatch based on merge strategy
    return switch (options.how) {
        .inner => try mergeInner(allocator, left, right, options),
        .left => try mergeLeft(allocator, left, right, options),
        .right => try mergeRight(allocator, left, right, options),
        .outer => try mergeOuter(allocator, left, right, options),
        .cross => try mergeCross(allocator, left, right, options),
    };
}

// Helper: Build hash key from row values for given columns
fn buildHashKey(
    allocator: Allocator,
    df: *const DataFrame,
    row_idx: u32,
    key_columns: []const []const u8,
) ![]u8 {
    // Pre-conditions
    std.debug.assert(row_idx < df.row_count);
    std.debug.assert(key_columns.len > 0);
    std.debug.assert(key_columns.len <= MAX_MERGE_KEYS);

    var key = std.ArrayListUnmanaged(u8){};
    errdefer key.deinit(allocator);

    var col_idx: u32 = 0;
    while (col_idx < key_columns.len and col_idx < MAX_MERGE_KEYS) : (col_idx += 1) {
        const col_name = key_columns[col_idx];
        const col = df.column(col_name) orelse return error.ColumnNotFound;

        // Add separator between key components (except first)
        if (col_idx > 0) {
            try key.append(allocator, '|');
        }

        // Append value as string based on type
        switch (col.value_type) {
            .Int64 => {
                const data = col.data.Int64;
                const val = data[row_idx];
                var buf: [20]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "{}", .{val});
                try key.appendSlice(allocator, str);
            },
            .Float64 => {
                const data = col.data.Float64;
                const val = data[row_idx];
                var buf: [32]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "{d}", .{val});
                try key.appendSlice(allocator, str);
            },
            .String => {
                const string_col = &col.data.String;
                const val = string_col.get(row_idx);
                try key.appendSlice(allocator, val);
            },
            .Bool => {
                const data = col.data.Bool;
                const val = data[row_idx];
                try key.appendSlice(allocator, if (val) "true" else "false");
            },
            .Categorical => {
                const codes = col.data.Categorical.codes;
                const val = codes[row_idx];
                var buf: [20]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "{}", .{val});
                try key.appendSlice(allocator, str);
            },
            .Null => {
                try key.appendSlice(allocator, "null");
            },
        }
    }
    std.debug.assert(col_idx == key_columns.len or col_idx == MAX_MERGE_KEYS);

    // Post-condition
    std.debug.assert(key.items.len > 0);

    return try key.toOwnedSlice(allocator);
}

// Inner merge - only matching keys
fn mergeInner(
    allocator: Allocator,
    left: *const DataFrame,
    right: *const DataFrame,
    options: MergeOptions,
) !DataFrame {
    // Pre-conditions
    std.debug.assert(left.columns.len > 0);
    std.debug.assert(right.columns.len > 0);

    // Step 1: Build hash map of right DataFrame rows by key
    var right_index = std.StringHashMap(std.ArrayList(u32)).init(allocator);
    defer {
        var iter = right_index.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
            allocator.free(entry.key_ptr.*);
        }
        right_index.deinit();
    }

    var right_row: u32 = 0;
    while (right_row < right.row_count and right_row < MAX_ROWS) : (right_row += 1) {
        const key = try buildHashKey(allocator, right, right_row, options.right_on);
        errdefer allocator.free(key);

        const result = try right_index.getOrPut(key);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(u32).init(allocator);
        } else {
            allocator.free(key); // Already have this key
        }
        try result.value_ptr.append(right_row);
    }
    std.debug.assert(right_row == right.row_count or right_row == MAX_ROWS);

    // Step 2: Find matching rows
    var matches = std.ArrayList(struct { left_idx: u32, right_idx: u32 }).init(allocator);
    defer matches.deinit();

    var left_row: u32 = 0;
    while (left_row < left.row_count and left_row < MAX_ROWS) : (left_row += 1) {
        const key = try buildHashKey(allocator, left, left_row, options.left_on);
        defer allocator.free(key);

        if (right_index.get(key)) |right_rows| {
            var match_idx: u32 = 0;
            while (match_idx < right_rows.items.len and match_idx < MAX_MATCHES_PER_KEY) : (match_idx += 1) {
                try matches.append(.{
                    .left_idx = left_row,
                    .right_idx = right_rows.items[match_idx],
                });
            }
            std.debug.assert(match_idx == right_rows.items.len or match_idx == MAX_MATCHES_PER_KEY);
        }
    }
    std.debug.assert(left_row == left.row_count or left_row == MAX_ROWS);

    // Step 3: Build result schema (left columns + right non-key columns with suffixes)
    const result_row_count: u32 = @intCast(matches.items.len);
    var result_cols = std.ArrayList(ColumnDesc).init(allocator);
    defer result_cols.deinit();

    // Add all left columns
    var left_col_idx: u32 = 0;
    while (left_col_idx < left.columns.len and left_col_idx < MAX_TOTAL_COLUMNS) : (left_col_idx += 1) {
        const col = &left.columns[left_col_idx];
        try result_cols.append(ColumnDesc.init(col.name, col.value_type, @intCast(result_cols.items.len)));
    }
    std.debug.assert(left_col_idx == left.columns.len or left_col_idx == MAX_TOTAL_COLUMNS);

    // Add right columns (skip key columns, add suffix if overlapping)
    var right_col_idx: u32 = 0;
    while (right_col_idx < right.columns.len and right_col_idx < MAX_TOTAL_COLUMNS) : (right_col_idx += 1) {
        const col = &right.columns[right_col_idx];

        // Skip if this is a key column
        var is_key = false;
        var key_check: u32 = 0;
        while (key_check < options.right_on.len and key_check < MAX_MERGE_KEYS) : (key_check += 1) {
            if (std.mem.eql(u8, col.name, options.right_on[key_check])) {
                is_key = true;
                break;
            }
        }
        std.debug.assert(key_check <= options.right_on.len or key_check == MAX_MERGE_KEYS);

        if (is_key) continue;

        // Check if name conflicts with left columns
        var name_conflicts = false;
        var left_check: u32 = 0;
        while (left_check < left.columns.len and left_check < MAX_TOTAL_COLUMNS) : (left_check += 1) {
            if (std.mem.eql(u8, col.name, left.columns[left_check].name)) {
                name_conflicts = true;
                break;
            }
        }
        std.debug.assert(left_check <= left.columns.len or left_check == MAX_TOTAL_COLUMNS);

        // Add with suffix if conflicts
        if (name_conflicts) {
            const suffixed_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ col.name, options.suffixes.right });
            try result_cols.append(ColumnDesc.init(suffixed_name, col.value_type, @intCast(result_cols.items.len)));
        } else {
            try result_cols.append(ColumnDesc.init(col.name, col.value_type, @intCast(result_cols.items.len)));
        }
    }
    std.debug.assert(right_col_idx == right.columns.len or right_col_idx == MAX_TOTAL_COLUMNS);

    // Step 4: Create result DataFrame
    var result = try DataFrame.create(allocator, result_cols.items, result_row_count);
    errdefer result.deinit();

    result.row_count = result_row_count;

    // Set Series lengths
    var col_idx: u32 = 0;
    while (col_idx < result.columns.len and col_idx < MAX_TOTAL_COLUMNS) : (col_idx += 1) {
        result.columns[col_idx].length = result_row_count;
    }
    std.debug.assert(col_idx == result.columns.len or col_idx == MAX_TOTAL_COLUMNS);

    // Step 5: Fill result data
    var match_idx: u32 = 0;
    while (match_idx < matches.items.len and match_idx < MAX_ROWS) : (match_idx += 1) {
        const match = matches.items[match_idx];

        // Copy left columns
        left_col_idx = 0;
        while (left_col_idx < left.columns.len and left_col_idx < MAX_TOTAL_COLUMNS) : (left_col_idx += 1) {
            const src_col = &left.columns[left_col_idx];
            const dest_col = &result.columns[left_col_idx];
            try copySeriesData(allocator, dest_col, src_col, match_idx, match.left_idx, 1);
        }
        std.debug.assert(left_col_idx == left.columns.len or left_col_idx == MAX_TOTAL_COLUMNS);

        // Copy right non-key columns
        var result_col_offset = left.columns.len;
        right_col_idx = 0;
        while (right_col_idx < right.columns.len and right_col_idx < MAX_TOTAL_COLUMNS) : (right_col_idx += 1) {
            const src_col = &right.columns[right_col_idx];

            // Skip key columns
            var is_key = false;
            var key_check: u32 = 0;
            while (key_check < options.right_on.len and key_check < MAX_MERGE_KEYS) : (key_check += 1) {
                if (std.mem.eql(u8, src_col.name, options.right_on[key_check])) {
                    is_key = true;
                    break;
                }
            }
            std.debug.assert(key_check <= options.right_on.len or key_check == MAX_MERGE_KEYS);

            if (is_key) continue;

            const dest_col = &result.columns[result_col_offset];
            try copySeriesData(allocator, dest_col, src_col, match_idx, match.right_idx, 1);
            result_col_offset += 1;
        }
        std.debug.assert(right_col_idx == right.columns.len or right_col_idx == MAX_TOTAL_COLUMNS);
    }
    std.debug.assert(match_idx == matches.items.len or match_idx == MAX_ROWS);

    // Post-conditions
    std.debug.assert(result.row_count == result_row_count);
    std.debug.assert(result.columns.len >= left.columns.len);

    return result;
}

// Left merge - all from left, matching from right
fn mergeLeft(
    allocator: Allocator,
    left: *const DataFrame,
    right: *const DataFrame,
    options: MergeOptions,
) !DataFrame {
    // Pre-conditions
    std.debug.assert(left.columns.len > 0);
    std.debug.assert(right.columns.len > 0);

    // Step 1: Build hash map of right DataFrame rows by key (same as inner)
    var right_index = std.StringHashMap(std.ArrayList(u32)).init(allocator);
    defer {
        var iter = right_index.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
            allocator.free(entry.key_ptr.*);
        }
        right_index.deinit();
    }

    var right_row: u32 = 0;
    while (right_row < right.row_count and right_row < MAX_ROWS) : (right_row += 1) {
        const key = try buildHashKey(allocator, right, right_row, options.right_on);
        errdefer allocator.free(key);

        const result = try right_index.getOrPut(key);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(u32).init(allocator);
        } else {
            allocator.free(key);
        }
        try result.value_ptr.append(right_row);
    }
    std.debug.assert(right_row == right.row_count or right_row == MAX_ROWS);

    // Step 2: For EACH left row, find matches (or add with NaN if no match)
    var matches = std.ArrayList(struct { left_idx: u32, right_idx: ?u32 }).init(allocator);
    defer matches.deinit();

    var left_row: u32 = 0;
    while (left_row < left.row_count and left_row < MAX_ROWS) : (left_row += 1) {
        const key = try buildHashKey(allocator, left, left_row, options.left_on);
        defer allocator.free(key);

        if (right_index.get(key)) |right_rows| {
            // Has matches - add all combinations
            var match_idx: u32 = 0;
            while (match_idx < right_rows.items.len and match_idx < MAX_MATCHES_PER_KEY) : (match_idx += 1) {
                try matches.append(.{
                    .left_idx = left_row,
                    .right_idx = right_rows.items[match_idx],
                });
            }
            std.debug.assert(match_idx == right_rows.items.len or match_idx == MAX_MATCHES_PER_KEY);
        } else {
            // No match - add row with null right
            try matches.append(.{
                .left_idx = left_row,
                .right_idx = null,
            });
        }
    }
    std.debug.assert(left_row == left.row_count or left_row == MAX_ROWS);

    // Step 3: Build result schema (same as inner)
    const result_row_count: u32 = @intCast(matches.items.len);
    var result_cols = std.ArrayList(ColumnDesc).init(allocator);
    defer result_cols.deinit();

    // Add all left columns
    var left_col_idx: u32 = 0;
    while (left_col_idx < left.columns.len and left_col_idx < MAX_TOTAL_COLUMNS) : (left_col_idx += 1) {
        const col = &left.columns[left_col_idx];
        try result_cols.append(ColumnDesc.init(col.name, col.value_type, @intCast(result_cols.items.len)));
    }
    std.debug.assert(left_col_idx == left.columns.len or left_col_idx == MAX_TOTAL_COLUMNS);

    // Add right non-key columns
    var right_col_idx: u32 = 0;
    while (right_col_idx < right.columns.len and right_col_idx < MAX_TOTAL_COLUMNS) : (right_col_idx += 1) {
        const col = &right.columns[right_col_idx];

        // Skip key columns
        var is_key = false;
        var key_check: u32 = 0;
        while (key_check < options.right_on.len and key_check < MAX_MERGE_KEYS) : (key_check += 1) {
            if (std.mem.eql(u8, col.name, options.right_on[key_check])) {
                is_key = true;
                break;
            }
        }
        std.debug.assert(key_check <= options.right_on.len or key_check == MAX_MERGE_KEYS);

        if (is_key) continue;

        // Check for name conflicts
        var name_conflicts = false;
        var left_check: u32 = 0;
        while (left_check < left.columns.len and left_check < MAX_TOTAL_COLUMNS) : (left_check += 1) {
            if (std.mem.eql(u8, col.name, left.columns[left_check].name)) {
                name_conflicts = true;
                break;
            }
        }
        std.debug.assert(left_check <= left.columns.len or left_check == MAX_TOTAL_COLUMNS);

        if (name_conflicts) {
            const suffixed_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ col.name, options.suffixes.right });
            try result_cols.append(ColumnDesc.init(suffixed_name, col.value_type, @intCast(result_cols.items.len)));
        } else {
            try result_cols.append(ColumnDesc.init(col.name, col.value_type, @intCast(result_cols.items.len)));
        }
    }
    std.debug.assert(right_col_idx == right.columns.len or right_col_idx == MAX_TOTAL_COLUMNS);

    // Step 4: Create result DataFrame
    var result = try DataFrame.create(allocator, result_cols.items, result_row_count);
    errdefer result.deinit();

    result.row_count = result_row_count;

    // Set Series lengths
    var col_idx: u32 = 0;
    while (col_idx < result.columns.len and col_idx < MAX_TOTAL_COLUMNS) : (col_idx += 1) {
        result.columns[col_idx].length = result_row_count;
    }
    std.debug.assert(col_idx == result.columns.len or col_idx == MAX_TOTAL_COLUMNS);

    // Step 5: Fill result data
    var match_idx: u32 = 0;
    while (match_idx < matches.items.len and match_idx < MAX_ROWS) : (match_idx += 1) {
        const match = matches.items[match_idx];

        // Copy left columns (always present)
        left_col_idx = 0;
        while (left_col_idx < left.columns.len and left_col_idx < MAX_TOTAL_COLUMNS) : (left_col_idx += 1) {
            const src_col = &left.columns[left_col_idx];
            const dest_col = &result.columns[left_col_idx];
            try copySeriesData(allocator, dest_col, src_col, match_idx, match.left_idx, 1);
        }
        std.debug.assert(left_col_idx == left.columns.len or left_col_idx == MAX_TOTAL_COLUMNS);

        // Copy right columns if match exists, otherwise fill with NaN/defaults
        var result_col_offset = left.columns.len;
        right_col_idx = 0;
        while (right_col_idx < right.columns.len and right_col_idx < MAX_TOTAL_COLUMNS) : (right_col_idx += 1) {
            const src_col = &right.columns[right_col_idx];

            // Skip key columns
            var is_key = false;
            var key_check: u32 = 0;
            while (key_check < options.right_on.len and key_check < MAX_MERGE_KEYS) : (key_check += 1) {
                if (std.mem.eql(u8, src_col.name, options.right_on[key_check])) {
                    is_key = true;
                    break;
                }
            }
            std.debug.assert(key_check <= options.right_on.len or key_check == MAX_MERGE_KEYS);

            if (is_key) continue;

            const dest_col = &result.columns[result_col_offset];

            if (match.right_idx) |right_idx| {
                // Has match - copy data
                try copySeriesData(allocator, dest_col, src_col, match_idx, right_idx, 1);
            } else {
                // No match - fill with default
                try fillSeriesWithDefault(dest_col, match_idx, 1);
            }

            result_col_offset += 1;
        }
        std.debug.assert(right_col_idx == right.columns.len or right_col_idx == MAX_TOTAL_COLUMNS);
    }
    std.debug.assert(match_idx == matches.items.len or match_idx == MAX_ROWS);

    // Post-conditions
    std.debug.assert(result.row_count == result_row_count);
    std.debug.assert(result.row_count >= left.row_count); // At least all left rows

    return result;
}

// Right merge - all from right, matching from left
// (Implemented as left merge with swapped arguments)
fn mergeRight(
    allocator: Allocator,
    left: *const DataFrame,
    right: *const DataFrame,
    options: MergeOptions,
) !DataFrame {
    // Pre-conditions
    std.debug.assert(left.columns.len > 0);
    std.debug.assert(right.columns.len > 0);

    // Swap left and right for a left merge
    const swapped_options = MergeOptions{
        .how = .left,
        .left_on = options.right_on,
        .right_on = options.left_on,
        .suffixes = .{ .left = options.suffixes.right, .right = options.suffixes.left },
    };

    return try mergeLeft(allocator, right, left, swapped_options);
}

// Outer merge - all keys from both (union)
fn mergeOuter(
    allocator: Allocator,
    left: *const DataFrame,
    right: *const DataFrame,
    options: MergeOptions,
) !DataFrame {
    // Pre-conditions
    std.debug.assert(left.columns.len > 0);
    std.debug.assert(right.columns.len > 0);

    // Strategy: Do left merge + add unmatched right rows

    // Step 1: Build index of right rows
    var right_index = std.StringHashMap(std.ArrayList(u32)).init(allocator);
    defer {
        var iter = right_index.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
            allocator.free(entry.key_ptr.*);
        }
        right_index.deinit();
    }

    var right_row: u32 = 0;
    while (right_row < right.row_count and right_row < MAX_ROWS) : (right_row += 1) {
        const key = try buildHashKey(allocator, right, right_row, options.right_on);
        errdefer allocator.free(key);

        const result = try right_index.getOrPut(key);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(u32).init(allocator);
        } else {
            allocator.free(key);
        }
        try result.value_ptr.append(right_row);
    }
    std.debug.assert(right_row == right.row_count or right_row == MAX_ROWS);

    // Step 2: Track which right rows were matched
    var right_matched = try allocator.alloc(bool, right.row_count);
    defer allocator.free(right_matched);
    @memset(right_matched, false);

    // Step 3: Build matches (left + matching right)
    var matches = std.ArrayList(struct { left_idx: ?u32, right_idx: ?u32 }).init(allocator);
    defer matches.deinit();

    var left_row_iter: u32 = 0;
    while (left_row_iter < left.row_count and left_row_iter < MAX_ROWS) : (left_row_iter += 1) {
        const key = try buildHashKey(allocator, left, left_row_iter, options.left_on);
        defer allocator.free(key);

        if (right_index.get(key)) |right_rows| {
            var match_idx: u32 = 0;
            while (match_idx < right_rows.items.len and match_idx < MAX_MATCHES_PER_KEY) : (match_idx += 1) {
                const right_idx = right_rows.items[match_idx];
                right_matched[right_idx] = true;
                try matches.append(.{
                    .left_idx = left_row_iter,
                    .right_idx = right_idx,
                });
            }
            std.debug.assert(match_idx == right_rows.items.len or match_idx == MAX_MATCHES_PER_KEY);
        } else {
            // No match - add left row with null right
            try matches.append(.{
                .left_idx = left_row_iter,
                .right_idx = null,
            });
        }
    }
    std.debug.assert(left_row_iter == left.row_count or left_row_iter == MAX_ROWS);

    // Step 4: Add unmatched right rows
    var unmatched_check: u32 = 0;
    while (unmatched_check < right.row_count and unmatched_check < MAX_ROWS) : (unmatched_check += 1) {
        if (!right_matched[unmatched_check]) {
            try matches.append(.{
                .left_idx = null,
                .right_idx = unmatched_check,
            });
        }
    }
    std.debug.assert(unmatched_check == right.row_count or unmatched_check == MAX_ROWS);

    // Step 5: Build result schema (same as left merge)
    const result_row_count: u32 = @intCast(matches.items.len);
    var result_cols = std.ArrayList(ColumnDesc).init(allocator);
    defer result_cols.deinit();

    var left_col_idx: u32 = 0;
    while (left_col_idx < left.columns.len and left_col_idx < MAX_TOTAL_COLUMNS) : (left_col_idx += 1) {
        const col = &left.columns[left_col_idx];
        try result_cols.append(ColumnDesc.init(col.name, col.value_type, @intCast(result_cols.items.len)));
    }
    std.debug.assert(left_col_idx == left.columns.len or left_col_idx == MAX_TOTAL_COLUMNS);

    var right_col_idx: u32 = 0;
    while (right_col_idx < right.columns.len and right_col_idx < MAX_TOTAL_COLUMNS) : (right_col_idx += 1) {
        const col = &right.columns[right_col_idx];

        var is_key = false;
        var key_check: u32 = 0;
        while (key_check < options.right_on.len and key_check < MAX_MERGE_KEYS) : (key_check += 1) {
            if (std.mem.eql(u8, col.name, options.right_on[key_check])) {
                is_key = true;
                break;
            }
        }
        std.debug.assert(key_check <= options.right_on.len or key_check == MAX_MERGE_KEYS);

        if (is_key) continue;

        var name_conflicts = false;
        var left_check: u32 = 0;
        while (left_check < left.columns.len and left_check < MAX_TOTAL_COLUMNS) : (left_check += 1) {
            if (std.mem.eql(u8, col.name, left.columns[left_check].name)) {
                name_conflicts = true;
                break;
            }
        }
        std.debug.assert(left_check <= left.columns.len or left_check == MAX_TOTAL_COLUMNS);

        if (name_conflicts) {
            const suffixed_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ col.name, options.suffixes.right });
            try result_cols.append(ColumnDesc.init(suffixed_name, col.value_type, @intCast(result_cols.items.len)));
        } else {
            try result_cols.append(ColumnDesc.init(col.name, col.value_type, @intCast(result_cols.items.len)));
        }
    }
    std.debug.assert(right_col_idx == right.columns.len or right_col_idx == MAX_TOTAL_COLUMNS);

    // Step 6: Create result DataFrame
    var result = try DataFrame.create(allocator, result_cols.items, result_row_count);
    errdefer result.deinit();

    result.row_count = result_row_count;

    var col_idx: u32 = 0;
    while (col_idx < result.columns.len and col_idx < MAX_TOTAL_COLUMNS) : (col_idx += 1) {
        result.columns[col_idx].length = result_row_count;
    }
    std.debug.assert(col_idx == result.columns.len or col_idx == MAX_TOTAL_COLUMNS);

    // Step 7: Fill result data
    var match_idx: u32 = 0;
    while (match_idx < matches.items.len and match_idx < MAX_ROWS) : (match_idx += 1) {
        const match = matches.items[match_idx];

        // Copy left columns
        left_col_idx = 0;
        while (left_col_idx < left.columns.len and left_col_idx < MAX_TOTAL_COLUMNS) : (left_col_idx += 1) {
            const src_col = &left.columns[left_col_idx];
            const dest_col = &result.columns[left_col_idx];

            if (match.left_idx) |left_idx| {
                try copySeriesData(allocator, dest_col, src_col, match_idx, left_idx, 1);
            } else {
                try fillSeriesWithDefault(dest_col, match_idx, 1);
            }
        }
        std.debug.assert(left_col_idx == left.columns.len or left_col_idx == MAX_TOTAL_COLUMNS);

        // Copy right columns
        var result_col_offset = left.columns.len;
        right_col_idx = 0;
        while (right_col_idx < right.columns.len and right_col_idx < MAX_TOTAL_COLUMNS) : (right_col_idx += 1) {
            const src_col = &right.columns[right_col_idx];

            var is_key = false;
            var key_check: u32 = 0;
            while (key_check < options.right_on.len and key_check < MAX_MERGE_KEYS) : (key_check += 1) {
                if (std.mem.eql(u8, src_col.name, options.right_on[key_check])) {
                    is_key = true;
                    break;
                }
            }
            std.debug.assert(key_check <= options.right_on.len or key_check == MAX_MERGE_KEYS);

            if (is_key) continue;

            const dest_col = &result.columns[result_col_offset];

            if (match.right_idx) |right_idx| {
                try copySeriesData(allocator, dest_col, src_col, match_idx, right_idx, 1);
            } else {
                try fillSeriesWithDefault(dest_col, match_idx, 1);
            }

            result_col_offset += 1;
        }
        std.debug.assert(right_col_idx == right.columns.len or right_col_idx == MAX_TOTAL_COLUMNS);
    }
    std.debug.assert(match_idx == matches.items.len or match_idx == MAX_ROWS);

    // Post-conditions
    std.debug.assert(result.row_count == result_row_count);

    return result;
}

// Cross merge - cartesian product (all combinations)
fn mergeCross(
    allocator: Allocator,
    left: *const DataFrame,
    right: *const DataFrame,
    options: MergeOptions,
) !DataFrame {
    // Pre-conditions
    std.debug.assert(left.columns.len > 0);
    std.debug.assert(right.columns.len > 0);

    // Cross join ignores merge keys - creates all combinations
    _ = options;

    // Calculate result size (can be very large!)
    const result_row_count: u32 = @intCast(@as(u64, left.row_count) * @as(u64, right.row_count));

    // Safety check
    if (result_row_count > MAX_ROWS) {
        std.log.err("Cross merge would create {} rows (max: {})", .{ result_row_count, MAX_ROWS });
        return error.ResultTooLarge;
    }

    // Step 1: Build result schema (all left columns + all right columns with suffix handling)
    var result_cols = std.ArrayList(ColumnDesc).init(allocator);
    defer result_cols.deinit();

    var left_col_idx: u32 = 0;
    while (left_col_idx < left.columns.len and left_col_idx < MAX_TOTAL_COLUMNS) : (left_col_idx += 1) {
        const col = &left.columns[left_col_idx];
        try result_cols.append(ColumnDesc.init(col.name, col.value_type, @intCast(result_cols.items.len)));
    }
    std.debug.assert(left_col_idx == left.columns.len or left_col_idx == MAX_TOTAL_COLUMNS);

    var right_col_idx: u32 = 0;
    while (right_col_idx < right.columns.len and right_col_idx < MAX_TOTAL_COLUMNS) : (right_col_idx += 1) {
        const col = &right.columns[right_col_idx];

        // Check for name conflicts
        var name_conflicts = false;
        var left_check: u32 = 0;
        while (left_check < left.columns.len and left_check < MAX_TOTAL_COLUMNS) : (left_check += 1) {
            if (std.mem.eql(u8, col.name, left.columns[left_check].name)) {
                name_conflicts = true;
                break;
            }
        }
        std.debug.assert(left_check <= left.columns.len or left_check == MAX_TOTAL_COLUMNS);

        if (name_conflicts) {
            const suffixed_name = try std.fmt.allocPrint(allocator, "{s}_right", .{col.name});
            try result_cols.append(ColumnDesc.init(suffixed_name, col.value_type, @intCast(result_cols.items.len)));
        } else {
            try result_cols.append(ColumnDesc.init(col.name, col.value_type, @intCast(result_cols.items.len)));
        }
    }
    std.debug.assert(right_col_idx == right.columns.len or right_col_idx == MAX_TOTAL_COLUMNS);

    // Step 2: Create result DataFrame
    var result = try DataFrame.create(allocator, result_cols.items, result_row_count);
    errdefer result.deinit();

    result.row_count = result_row_count;

    var col_idx: u32 = 0;
    while (col_idx < result.columns.len and col_idx < MAX_TOTAL_COLUMNS) : (col_idx += 1) {
        result.columns[col_idx].length = result_row_count;
    }
    std.debug.assert(col_idx == result.columns.len or col_idx == MAX_TOTAL_COLUMNS);

    // Step 3: Fill result data (nested loop - all combinations)
    var result_row: u32 = 0;
    var left_row: u32 = 0;
    while (left_row < left.row_count and left_row < MAX_ROWS) : (left_row += 1) {
        var right_row: u32 = 0;
        while (right_row < right.row_count and right_row < MAX_ROWS) : (right_row += 1) {
            // Copy left columns
            left_col_idx = 0;
            while (left_col_idx < left.columns.len and left_col_idx < MAX_TOTAL_COLUMNS) : (left_col_idx += 1) {
                const src_col = &left.columns[left_col_idx];
                const dest_col = &result.columns[left_col_idx];
                try copySeriesData(allocator, dest_col, src_col, result_row, left_row, 1);
            }
            std.debug.assert(left_col_idx == left.columns.len or left_col_idx == MAX_TOTAL_COLUMNS);

            // Copy right columns
            var result_col_offset = left.columns.len;
            right_col_idx = 0;
            while (right_col_idx < right.columns.len and right_col_idx < MAX_TOTAL_COLUMNS) : (right_col_idx += 1) {
                const src_col = &right.columns[right_col_idx];
                const dest_col = &result.columns[result_col_offset];
                try copySeriesData(allocator, dest_col, src_col, result_row, right_row, 1);
                result_col_offset += 1;
            }
            std.debug.assert(right_col_idx == right.columns.len or right_col_idx == MAX_TOTAL_COLUMNS);

            result_row += 1;
        }
        std.debug.assert(right_row == right.row_count or right_row == MAX_ROWS);
    }
    std.debug.assert(left_row == left.row_count or left_row == MAX_ROWS);
    std.debug.assert(result_row == result_row_count);

    // Post-conditions
    std.debug.assert(result.row_count == result_row_count);

    return result;
}

// ============================================================================
// Append & Update Operations
// ============================================================================

// Options for append operation
pub const AppendOptions = struct {
    verify_schema: bool = true, // Verify column names and types match
};

// Append rows from another DataFrame to this DataFrame
//
// Creates a new DataFrame with rows from both DataFrames.
// This is a convenience wrapper around concat() with vertical axis.
//
// Example:
//   const appended = try append(allocator, &df1, &df2, .{});
//   defer appended.deinit();
//
pub fn append(
    allocator: Allocator,
    base: *const DataFrame,
    other: *const DataFrame,
    options: AppendOptions,
) !DataFrame {
    // Pre-conditions
    std.debug.assert(base.columns.len > 0);
    std.debug.assert(other.columns.len > 0);

    // Verify schema if requested
    if (options.verify_schema) {
        if (base.columns.len != other.columns.len) {
            std.log.err("Append schema mismatch: {} columns vs {} columns", .{ base.columns.len, other.columns.len });
            return error.SchemaMismatch;
        }

        var col_idx: u32 = 0;
        while (col_idx < base.columns.len and col_idx < MAX_TOTAL_COLUMNS) : (col_idx += 1) {
            const base_col = &base.columns[col_idx];
            const other_col = &other.columns[col_idx];

            if (!std.mem.eql(u8, base_col.name, other_col.name)) {
                std.log.err("Column name mismatch at index {}: '{s}' vs '{s}'", .{ col_idx, base_col.name, other_col.name });
                return error.SchemaMismatch;
            }

            if (base_col.value_type != other_col.value_type) {
                std.log.err("Column type mismatch for '{s}': {} vs {}", .{ base_col.name, base_col.value_type, other_col.value_type });
                return error.SchemaMismatch;
            }
        }
        std.debug.assert(col_idx == base.columns.len or col_idx == MAX_TOTAL_COLUMNS);
    }

    // Delegate to concat with vertical axis
    var dfs = [_]*const DataFrame{ base, other };
    return try concat(allocator, dfs[0..], .{
        .axis = .vertical,
        .ignore_index = false,
    });
}

// Options for update operation
pub const UpdateOptions = struct {
    on: []const []const u8, // Columns to match on (like SQL UPDATE ... WHERE)
    overwrite: bool = true, // If true, overwrite existing values; if false, only fill NaN/null
};

// Update DataFrame values based on another DataFrame
//
// Similar to SQL UPDATE ... SET ... WHERE ...
// Matches rows based on 'on' columns and updates other columns from 'other' DataFrame.
//
// Example:
//   // Update prices based on product_id
//   const updated = try update(allocator, &base, &updates, .{
//       .on = &[_][]const u8{"product_id"},
//       .overwrite = true,
//   });
//   defer updated.deinit();
//
pub fn update(
    allocator: Allocator,
    base: *const DataFrame,
    other: *const DataFrame,
    options: UpdateOptions,
) !DataFrame {
    // Pre-conditions
    std.debug.assert(base.columns.len > 0);
    std.debug.assert(other.columns.len > 0);
    std.debug.assert(options.on.len > 0);
    std.debug.assert(options.on.len <= MAX_MERGE_KEYS);

    // Strategy: Do a left merge, then for each matched row, update values from 'other'

    // Step 1: Build hash map of 'other' DataFrame rows by key
    var other_index = std.StringHashMap(u32).init(allocator);
    defer {
        var iter = other_index.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        other_index.deinit();
    }

    var other_row: u32 = 0;
    while (other_row < other.row_count and other_row < MAX_ROWS) : (other_row += 1) {
        const key = try buildHashKey(allocator, other, other_row, options.on);
        errdefer allocator.free(key);

        const result = try other_index.getOrPut(key);
        if (!result.found_existing) {
            result.value_ptr.* = other_row;
        } else {
            allocator.free(key); // Already have this key
            // Use first match if duplicate keys
        }
    }
    std.debug.assert(other_row == other.row_count or other_row == MAX_ROWS);

    // Step 2: Create result DataFrame (same schema as base)
    var result = try DataFrame.create(allocator, base.column_descs, base.row_count);
    errdefer result.deinit();

    result.row_count = base.row_count;

    // Set Series lengths
    var col_idx: u32 = 0;
    while (col_idx < result.columns.len and col_idx < MAX_TOTAL_COLUMNS) : (col_idx += 1) {
        result.columns[col_idx].length = base.row_count;
    }
    std.debug.assert(col_idx == result.columns.len or col_idx == MAX_TOTAL_COLUMNS);

    // Step 3: Copy base data, then update from 'other' where keys match
    var base_row: u32 = 0;
    while (base_row < base.row_count and base_row < MAX_ROWS) : (base_row += 1) {
        const key = try buildHashKey(allocator, base, base_row, options.on);
        defer allocator.free(key);

        const other_row_opt = other_index.get(key);

        // Copy/update each column
        col_idx = 0;
        while (col_idx < base.columns.len and col_idx < MAX_TOTAL_COLUMNS) : (col_idx += 1) {
            const base_col = &base.columns[col_idx];
            const dest_col = &result.columns[col_idx];

            // Check if this is a key column (never update key columns)
            var is_key = false;
            var key_check: u32 = 0;
            while (key_check < options.on.len and key_check < MAX_MERGE_KEYS) : (key_check += 1) {
                if (std.mem.eql(u8, base_col.name, options.on[key_check])) {
                    is_key = true;
                    break;
                }
            }
            std.debug.assert(key_check <= options.on.len or key_check == MAX_MERGE_KEYS);

            if (is_key) {
                // Key column - always copy from base
                try copySeriesData(allocator, dest_col, base_col, base_row, base_row, 1);
            } else if (other_row_opt) |other_row_idx| {
                // Has match - find matching column in 'other' DataFrame
                const other_col_opt = other.column(base_col.name);

                if (other_col_opt) |other_col| {
                    // Column exists in both - update from 'other'
                    try copySeriesData(allocator, dest_col, other_col, base_row, other_row_idx, 1);
                } else {
                    // Column not in 'other' - keep base value
                    try copySeriesData(allocator, dest_col, base_col, base_row, base_row, 1);
                }
            } else {
                // No match - keep base value
                try copySeriesData(allocator, dest_col, base_col, base_row, base_row, 1);
            }
        }
        std.debug.assert(col_idx == base.columns.len or col_idx == MAX_TOTAL_COLUMNS);
    }
    std.debug.assert(base_row == base.row_count or base_row == MAX_ROWS);

    // Post-conditions
    std.debug.assert(result.row_count == base.row_count);
    std.debug.assert(result.columns.len == base.columns.len);

    return result;
}
