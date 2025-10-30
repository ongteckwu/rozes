//! Additional DataFrame Operations - Data exploration and manipulation utilities
//!
//! This module provides convenience operations for DataFrame manipulation:
//! - unique(): Get unique values from a column
//! - dropDuplicates(): Remove duplicate rows
//! - rename(): Rename columns
//! - head(n) / tail(n): Get first/last n rows
//! - describe(): Statistical summary
//!
//! See docs/TODO.md Phase 5 for specifications.

const std = @import("std");
const types = @import("types.zig");
const DataFrame = @import("dataframe.zig").DataFrame;
const Series = @import("series.zig").Series;
const ColumnDesc = types.ColumnDesc;

const MAX_ROWS: u32 = std.math.maxInt(u32);
const MAX_COLS: u32 = 10_000;

/// Returns unique values from a column
///
/// Args:
///   - df: Source DataFrame
///   - allocator: Allocator for result array
///   - column_name: Name of column to get unique values from
///
/// Returns: Array of unique values (caller must free each string and the array)
///
/// Performance: O(n) average case with hash map
///
/// Example:
/// ```zig
/// const unique_cities = try df.unique(allocator, "city");
/// defer {
///     for (unique_cities) |val| allocator.free(val);
///     allocator.free(unique_cities);
/// }
/// ```
pub fn unique(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    column_name: []const u8,
) ![]const []const u8 {
    std.debug.assert(column_name.len > 0); // Pre-condition #1
    std.debug.assert(df.row_count <= MAX_ROWS); // Pre-condition #2

    const col = df.column(column_name) orelse return error.ColumnNotFound;

    // Handle empty DataFrame
    if (df.row_count == 0) {
        return &[_][]const u8{};
    }

    // Use hash map to track unique values
    var seen = std.StringHashMap(void).init(allocator);
    defer {
        // Free all keys owned by hash map
        var it = seen.keyIterator();
        while (it.next()) |key| {
            allocator.free(key.*);
        }
        seen.deinit();
    }

    var result = std.ArrayListUnmanaged([]const u8){};
    defer result.deinit(allocator);

    switch (col.value_type) {
        .Int64 => {
            const data = col.asInt64() orelse return error.TypeMismatch;
            var i: u32 = 0;
            while (i < MAX_ROWS and i < df.row_count) : (i += 1) {
                const value = data[i];
                const key = try std.fmt.allocPrint(allocator, "{}", .{value});

                if (!seen.contains(key)) {
                    // Hash map takes ownership of key - don't free it
                    try seen.put(key, {});
                    try result.append(allocator, try std.fmt.allocPrint(allocator, "{}", .{value}));
                } else {
                    // Key already exists, free the duplicate
                    allocator.free(key);
                }
            }
            std.debug.assert(i == df.row_count); // Post-condition
        },
        .Float64 => {
            const data = col.asFloat64() orelse return error.TypeMismatch;
            var i: u32 = 0;
            while (i < MAX_ROWS and i < df.row_count) : (i += 1) {
                const value = data[i];
                const key = try std.fmt.allocPrint(allocator, "{d}", .{value});

                if (!seen.contains(key)) {
                    // Hash map takes ownership of key - don't free it
                    try seen.put(key, {});
                    try result.append(allocator, try std.fmt.allocPrint(allocator, "{d}", .{value}));
                } else {
                    // Key already exists, free the duplicate
                    allocator.free(key);
                }
            }
            std.debug.assert(i == df.row_count); // Post-condition
        },
        .String => {
            const string_col = col.asStringColumn() orelse return error.TypeMismatch;
            var i: u32 = 0;
            while (i < MAX_ROWS and i < df.row_count) : (i += 1) {
                const value = string_col.get(i);
                if (!seen.contains(value)) {
                    // Duplicate the string for hash map ownership
                    const key = try allocator.dupe(u8, value);
                    try seen.put(key, {});
                    try result.append(allocator, try allocator.dupe(u8, value));
                }
            }
            std.debug.assert(i == df.row_count); // Post-condition
        },
        .Categorical => {
            // Categorical behaves like String for unique values
            const cat_col = col.asCategoricalColumn() orelse return error.TypeMismatch;
            var i: u32 = 0;
            while (i < MAX_ROWS and i < df.row_count) : (i += 1) {
                const value = cat_col.get(i);
                if (!seen.contains(value)) {
                    const key = try allocator.dupe(u8, value);
                    try seen.put(key, {});
                    try result.append(allocator, try allocator.dupe(u8, value));
                }
            }
            std.debug.assert(i == df.row_count); // Post-condition
        },
        .Bool => {
            const data = col.asBool() orelse return error.TypeMismatch;
            var has_true = false;
            var has_false = false;

            var i: u32 = 0;
            while (i < MAX_ROWS and i < df.row_count) : (i += 1) {
                if (data[i]) {
                    has_true = true;
                } else {
                    has_false = true;
                }
                if (has_true and has_false) break;
            }
            std.debug.assert(i <= df.row_count); // Post-condition

            if (has_true) try result.append(allocator, try allocator.dupe(u8, "true"));
            if (has_false) try result.append(allocator, try allocator.dupe(u8, "false"));
        },
        .Null => {
            try result.append(allocator, try allocator.dupe(u8, "null"));
        },
    }

    return try result.toOwnedSlice(allocator);
}

/// Removes duplicate rows from DataFrame
///
/// Args:
///   - df: Source DataFrame
///   - allocator: Allocator for new DataFrame
///   - subset: Columns to consider for duplicates (all if null)
///
/// Returns: New DataFrame without duplicates (caller owns, must call deinit())
///
/// Performance: O(n * k) where n is rows, k is columns in subset
///
/// Example:
/// ```zig
/// const no_dupes = try df.dropDuplicates(allocator, &[_][]const u8{"name", "age"});
/// defer no_dupes.deinit();
/// ```
pub fn dropDuplicates(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    subset: ?[]const []const u8,
) !DataFrame {
    std.debug.assert(df.row_count <= MAX_ROWS); // Pre-condition #1
    std.debug.assert(df.columns.len <= MAX_COLS); // Pre-condition #2

    // Determine which columns to check
    const check_cols = subset orelse blk: {
        var all_cols = try allocator.alloc([]const u8, df.columns.len);
        var i: u32 = 0;
        while (i < MAX_COLS and i < df.column_descs.len) : (i += 1) {
            all_cols[i] = df.column_descs[i].name;
        }
        std.debug.assert(i == df.column_descs.len); // Post-condition
        break :blk all_cols;
    };
    defer if (subset == null) allocator.free(check_cols);

    // Use hash map to track seen rows
    var seen = std.StringHashMap(void).init(allocator);
    defer {
        // Free all keys in the hash map
        var it = seen.keyIterator();
        while (it.next()) |key_ptr| {
            allocator.free(key_ptr.*);
        }
        seen.deinit();
    }

    var keep_indices = std.ArrayListUnmanaged(u32){};
    defer keep_indices.deinit(allocator);

    // Iterate through rows and check for duplicates
    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < df.row_count) : (row_idx += 1) {
        // Build row key from subset columns
        var key_buf = std.ArrayListUnmanaged(u8){};
        defer key_buf.deinit(allocator);

        for (check_cols) |col_name| {
            const col = df.column(col_name) orelse return error.ColumnNotFound;
            switch (col.value_type) {
                .Int64 => {
                    const data = switch (col.data) {
                        .Int64 => |slice| slice[0..df.row_count],
                        else => unreachable,
                    };
                    try key_buf.writer(allocator).print("{}|", .{data[row_idx]});
                },
                .Float64 => {
                    const data = switch (col.data) {
                        .Float64 => |slice| slice[0..df.row_count],
                        else => unreachable,
                    };
                    try key_buf.writer(allocator).print("{d}|", .{data[row_idx]});
                },
                .String => {
                    const string_col = col.asStringColumn() orelse unreachable;
                    try key_buf.writer(allocator).print("{s}|", .{string_col.get(row_idx)});
                },
                .Categorical => {
                    const cat_col = col.asCategoricalColumn() orelse unreachable;
                    try key_buf.writer(allocator).print("{s}|", .{cat_col.get(row_idx)});
                },
                .Bool => {
                    const data = switch (col.data) {
                        .Bool => |slice| slice[0..df.row_count],
                        else => unreachable,
                    };
                    try key_buf.writer(allocator).print("{}|", .{data[row_idx]});
                },
                .Null => {
                    try key_buf.appendSlice(allocator, "null|");
                },
            }
        }

        const key = try key_buf.toOwnedSlice(allocator);
        defer allocator.free(key);

        if (!seen.contains(key)) {
            try seen.put(try allocator.dupe(u8, key), {});
            try keep_indices.append(allocator, row_idx);
        }
    }
    std.debug.assert(row_idx == df.row_count); // Post-condition #3

    // Handle edge case: no unique rows (all duplicates)
    if (keep_indices.items.len == 0) {
        // Create empty DataFrame with same columns but 0 rows
        const result = try DataFrame.create(allocator, df.column_descs, 0);
        return result;
    }

    // Create new DataFrame with unique rows
    var result = try DataFrame.create(allocator, df.column_descs, @intCast(keep_indices.items.len));
    errdefer result.deinit();

    // Copy data for kept rows
    for (df.columns, 0..) |*src_col, col_idx| {
        var dst_col = &result.columns[col_idx];

        switch (src_col.value_type) {
            .Int64 => {
                const src_data = src_col.asInt64() orelse unreachable;
                const dst_data = dst_col.asInt64Buffer() orelse unreachable;
                for (keep_indices.items, 0..) |src_idx, dst_idx| {
                    dst_data[dst_idx] = src_data[src_idx];
                }
            },
            .Float64 => {
                const src_data = src_col.asFloat64() orelse unreachable;
                const dst_data = dst_col.asFloat64Buffer() orelse unreachable;
                for (keep_indices.items, 0..) |src_idx, dst_idx| {
                    dst_data[dst_idx] = src_data[src_idx];
                }
            },
            .String => {
                const src_string_col = src_col.asStringColumn() orelse unreachable;
                for (keep_indices.items) |src_idx| {
                    const str = src_string_col.get(src_idx);
                    try dst_col.appendString(result.arena.allocator(), str);
                }
            },
            .Bool => {
                const src_data = src_col.asBool() orelse unreachable;
                const dst_data = dst_col.asBoolBuffer() orelse unreachable;
                for (keep_indices.items, 0..) |src_idx, dst_idx| {
                    dst_data[dst_idx] = src_data[src_idx];
                }
            },
            .Categorical => {
                // Deep copy categorical with independent dictionary
                const src_cat_col = src_col.asCategoricalColumn() orelse unreachable;
                const new_cat_col = try src_cat_col.deepCopyRows(
                    result.arena.allocator(),
                    keep_indices.items,
                );

                // Replace the categorical column in result DataFrame
                dst_col.data = .{ .Categorical = try result.arena.allocator().create(@TypeOf(new_cat_col)) };
                dst_col.data.Categorical.* = new_cat_col;
            },
            .Null => {},
        }
    }

    try result.setRowCount(@intCast(keep_indices.items.len));
    return result;
}

/// Renames columns in DataFrame
///
/// Args:
///   - df: Source DataFrame
///   - allocator: Allocator for new DataFrame
///   - rename_map: Map of old name -> new name
///
/// Returns: New DataFrame with renamed columns (caller owns, must call deinit())
///
/// Performance: O(n * m) where n is rows, m is columns
///
/// Example:
/// ```zig
/// var rename_map = std.StringHashMap([]const u8).init(allocator);
/// try rename_map.put("old_name", "new_name");
/// const renamed = try df.rename(allocator, &rename_map);
/// defer renamed.deinit();
/// ```
pub fn rename(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    rename_map: *const std.StringHashMap([]const u8),
) !DataFrame {
    std.debug.assert(df.row_count <= MAX_ROWS); // Pre-condition #1
    std.debug.assert(df.columns.len <= MAX_COLS); // Pre-condition #2

    // Create new column descriptors with renamed columns
    var new_descs = try allocator.alloc(ColumnDesc, df.column_descs.len);
    defer allocator.free(new_descs);

    var i: u32 = 0;
    while (i < MAX_COLS and i < df.column_descs.len) : (i += 1) {
        const old_name = df.column_descs[i].name;
        const new_name = rename_map.get(old_name) orelse old_name;
        new_descs[i] = ColumnDesc.init(new_name, df.column_descs[i].value_type, i);
    }
    std.debug.assert(i == df.column_descs.len); // Post-condition #3

    // Create new DataFrame with renamed columns
    var result = try DataFrame.create(allocator, new_descs, df.row_count);
    errdefer result.deinit();

    // Copy all data
    for (df.columns, 0..) |*src_col, col_idx| {
        var dst_col = &result.columns[col_idx];

        switch (src_col.value_type) {
            .Int64 => {
                const src_data = src_col.asInt64() orelse unreachable;
                const dst_data = dst_col.asInt64Buffer() orelse unreachable;
                @memcpy(dst_data[0..df.row_count], src_data[0..df.row_count]);
            },
            .Float64 => {
                const src_data = src_col.asFloat64() orelse unreachable;
                const dst_data = dst_col.asFloat64Buffer() orelse unreachable;
                @memcpy(dst_data[0..df.row_count], src_data[0..df.row_count]);
            },
            .String => {
                const src_string_col = src_col.asStringColumn() orelse unreachable;
                var row_idx: u32 = 0;
                while (row_idx < MAX_ROWS and row_idx < df.row_count) : (row_idx += 1) {
                    const str = src_string_col.get(row_idx);
                    try dst_col.appendString(result.arena.allocator(), str);
                }
                std.debug.assert(row_idx == df.row_count); // Loop verification
            },
            .Categorical => {
                // Shallow copy categorical pointer
                dst_col.data = src_col.data;
            },
            .Bool => {
                const src_data = src_col.asBool() orelse unreachable;
                const dst_data = dst_col.asBoolBuffer() orelse unreachable;
                @memcpy(dst_data[0..df.row_count], src_data[0..df.row_count]);
            },
            .Null => {},
        }
    }

    try result.setRowCount(df.row_count);
    return result;
}

/// Returns first n rows of DataFrame
///
/// Args:
///   - df: Source DataFrame
///   - allocator: Allocator for new DataFrame
///   - n: Number of rows to return
///
/// Returns: New DataFrame with first n rows (caller owns, must call deinit())
///
/// Performance: O(n * m) where n is rows, m is columns
///
/// Example:
/// ```zig
/// const preview = try df.head(allocator, 10);
/// defer preview.deinit();
/// ```
pub fn head(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    n: u32,
) !DataFrame {
    std.debug.assert(n > 0); // Pre-condition #1
    std.debug.assert(df.row_count <= MAX_ROWS); // Pre-condition #2

    const actual_n = @min(n, df.row_count);

    var result = try DataFrame.create(allocator, df.column_descs, actual_n);
    errdefer result.deinit();

    // Copy first n rows
    for (df.columns, 0..) |*src_col, col_idx| {
        var dst_col = &result.columns[col_idx];

        switch (src_col.value_type) {
            .Int64 => {
                const src_data = src_col.asInt64() orelse unreachable;
                const dst_data = dst_col.asInt64Buffer() orelse unreachable;
                @memcpy(dst_data[0..actual_n], src_data[0..actual_n]);
            },
            .Float64 => {
                const src_data = src_col.asFloat64() orelse unreachable;
                const dst_data = dst_col.asFloat64Buffer() orelse unreachable;
                @memcpy(dst_data[0..actual_n], src_data[0..actual_n]);
            },
            .String => {
                const src_string_col = src_col.asStringColumn() orelse unreachable;
                var i: u32 = 0;
                while (i < MAX_ROWS and i < actual_n) : (i += 1) {
                    const str = src_string_col.get(i);
                    try dst_col.appendString(result.arena.allocator(), str);
                }
                std.debug.assert(i == actual_n); // Post-condition
            },
            .Categorical => {
                // Shallow copy categorical pointer
                dst_col.data = src_col.data;
            },
            .Bool => {
                const src_data = src_col.asBool() orelse unreachable;
                const dst_data = dst_col.asBoolBuffer() orelse unreachable;
                @memcpy(dst_data[0..actual_n], src_data[0..actual_n]);
            },
            .Null => {},
        }
    }

    try result.setRowCount(actual_n);
    std.debug.assert(result.row_count == actual_n); // Post-condition #3
    return result;
}

/// Returns last n rows of DataFrame
///
/// Args:
///   - df: Source DataFrame
///   - allocator: Allocator for new DataFrame
///   - n: Number of rows to return
///
/// Returns: New DataFrame with last n rows (caller owns, must call deinit())
///
/// Performance: O(n * m) where n is rows, m is columns
///
/// Example:
/// ```zig
/// const last_rows = try df.tail(allocator, 10);
/// defer last_rows.deinit();
/// ```
pub fn tail(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    n: u32,
) !DataFrame {
    std.debug.assert(n > 0); // Pre-condition #1
    std.debug.assert(df.row_count <= MAX_ROWS); // Pre-condition #2

    const actual_n = @min(n, df.row_count);
    const start_idx = df.row_count - actual_n;

    var result = try DataFrame.create(allocator, df.column_descs, actual_n);
    errdefer result.deinit();

    // Copy last n rows
    for (df.columns, 0..) |*src_col, col_idx| {
        var dst_col = &result.columns[col_idx];

        switch (src_col.value_type) {
            .Int64 => {
                const src_data = src_col.asInt64() orelse unreachable;
                const dst_data = dst_col.asInt64Buffer() orelse unreachable;
                @memcpy(dst_data[0..actual_n], src_data[start_idx .. start_idx + actual_n]);
            },
            .Float64 => {
                const src_data = src_col.asFloat64() orelse unreachable;
                const dst_data = dst_col.asFloat64Buffer() orelse unreachable;
                @memcpy(dst_data[0..actual_n], src_data[start_idx .. start_idx + actual_n]);
            },
            .String => {
                const src_string_col = src_col.asStringColumn() orelse unreachable;
                var i: u32 = 0;
                while (i < MAX_ROWS and i < actual_n) : (i += 1) {
                    const str = src_string_col.get(start_idx + i);
                    try dst_col.appendString(result.arena.allocator(), str);
                }
                std.debug.assert(i == actual_n); // Post-condition
            },
            .Categorical => {
                // Shallow copy categorical pointer
                dst_col.data = src_col.data;
            },
            .Bool => {
                const src_data = src_col.asBool() orelse unreachable;
                const dst_data = dst_col.asBoolBuffer() orelse unreachable;
                @memcpy(dst_data[0..actual_n], src_data[start_idx .. start_idx + actual_n]);
            },
            .Null => {},
        }
    }

    try result.setRowCount(actual_n);
    std.debug.assert(result.row_count == actual_n); // Post-condition #3
    return result;
}

/// Statistical summary for numeric columns
pub const Summary = struct {
    count: u32,
    mean: ?f64,
    std: ?f64,
    min: ?f64,
    max: ?f64,
};

/// Returns statistical summary of DataFrame
///
/// Args:
///   - df: Source DataFrame
///   - allocator: Allocator for result map
///
/// Returns: Map of column name -> Summary (caller must deinit)
///
/// Performance: O(n * m) where n is rows, m is numeric columns
///
/// Example:
/// ```zig
/// const summary = try df.describe(allocator);
/// defer summary.deinit();
///
/// const age_summary = summary.get("age").?;
/// std.debug.print("Age - mean: {d}, std: {d}\n", .{age_summary.mean.?, age_summary.std.?});
/// ```
pub fn describe(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
) !std.StringHashMap(Summary) {
    std.debug.assert(df.row_count <= MAX_ROWS); // Pre-condition #1
    std.debug.assert(df.columns.len <= MAX_COLS); // Pre-condition #2

    var result = std.StringHashMap(Summary).init(allocator);
    errdefer result.deinit();

    for (df.columns) |*col| {
        switch (col.value_type) {
            .Int64 => {
                if (df.row_count == 0) {
                    // Empty DataFrame - return summary with count=0
                    try result.put(col.name, Summary{
                        .count = 0,
                        .mean = null,
                        .std = null,
                        .min = null,
                        .max = null,
                    });
                } else {
                    const data = col.asInt64() orelse continue;
                    const summary = try computeNumericSummary(i64, data[0..df.row_count]);
                    try result.put(col.name, summary);
                }
            },
            .Float64 => {
                if (df.row_count == 0) {
                    // Empty DataFrame - return summary with count=0
                    try result.put(col.name, Summary{
                        .count = 0,
                        .mean = null,
                        .std = null,
                        .min = null,
                        .max = null,
                    });
                } else {
                    const data = col.asFloat64() orelse continue;
                    const summary = try computeNumericSummary(f64, data[0..df.row_count]);
                    try result.put(col.name, summary);
                }
            },
            .String, .Bool, .Categorical, .Null => {
                // Non-numeric columns - only count
                try result.put(col.name, Summary{
                    .count = df.row_count,
                    .mean = null,
                    .std = null,
                    .min = null,
                    .max = null,
                });
            },
        }
    }

    std.debug.assert(result.count() == df.columns.len); // Post-condition #3
    return result;
}

fn computeNumericSummary(comptime T: type, data: []const T) !Summary {
    std.debug.assert(data.len > 0); // Pre-condition #1
    std.debug.assert(data.len <= MAX_ROWS); // Pre-condition #2

    const count: u32 = @intCast(data.len);

    // Calculate mean
    var sum: f64 = 0;
    var min_val: f64 = if (T == f64) data[0] else @floatFromInt(data[0]);
    var max_val: f64 = if (T == f64) data[0] else @floatFromInt(data[0]);

    var i: u32 = 0;
    while (i < MAX_ROWS and i < data.len) : (i += 1) {
        const val: f64 = if (T == f64) data[i] else @floatFromInt(data[i]);
        sum += val;
        min_val = @min(min_val, val);
        max_val = @max(max_val, val);
    }
    std.debug.assert(i == data.len); // Post-condition

    const mean = sum / @as(f64, @floatFromInt(count));

    // Calculate standard deviation
    var variance_sum: f64 = 0;
    i = 0;
    while (i < MAX_ROWS and i < data.len) : (i += 1) {
        const val: f64 = if (T == f64) data[i] else @floatFromInt(data[i]);
        const diff = val - mean;
        variance_sum += diff * diff;
    }
    std.debug.assert(i == data.len); // Post-condition

    const variance = variance_sum / @as(f64, @floatFromInt(count));
    const std_dev = @sqrt(variance);

    return Summary{
        .count = count,
        .mean = mean,
        .std = std_dev,
        .min = min_val,
        .max = max_val,
    };
}
