//! DataFrame Operations - Column selection, filtering, and aggregations
//!
//! This module provides operations on DataFrames including:
//! - Column selection (select, drop)
//! - Row filtering (filter)
//! - Aggregations (sum, mean, min, max)
//!
//! See docs/RFC.md Section 6 for DataFrame operations specification.
//!
//! Example:
//! ```
//! const selected = try select(&df, &[_][]const u8{"age", "score"});
//! const filtered = try filter(&df, myFilterFn);
//! const total = try sum(&df, "age");
//! ```

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const DataFrame = @import("dataframe.zig").DataFrame;
const Series = @import("series.zig").Series;
const StringColumn = @import("series.zig").StringColumn;
const ColumnDesc = types.ColumnDesc;
const ValueType = types.ValueType;
const RowRef = @import("dataframe.zig").RowRef;

/// Log error only when not in test mode (suppresses error output during tests)
fn logError(comptime fmt: []const u8, args: anytype) void {
    if (!builtin.is_test) {
        std.log.err(fmt, args);
    }
}

/// Maximum number of columns for operations
const MAX_COLS: u32 = 10_000;

/// Maximum number of rows for operations
const MAX_ROWS: u32 = 4_000_000_000;

/// Selects a subset of columns from a DataFrame
///
/// Args:
///   - df: Source DataFrame
///   - column_names: Array of column names to select
///
/// Returns: New DataFrame with selected columns
///
/// Note: Currently creates a copy. Zero-copy view pattern deferred to 0.3.0
pub fn select(
    df: *const DataFrame,
    column_names: []const []const u8,
) !DataFrame {
    // Check for empty column list
    if (column_names.len == 0) {
        return error.EmptyColumnList;
    }
    std.debug.assert(column_names.len > 0); // Should never trigger after check above
    std.debug.assert(column_names.len <= MAX_COLS); // Reasonable limit

    // Validate all column names exist
    var name_idx: u32 = 0;
    while (name_idx < MAX_COLS and name_idx < column_names.len) : (name_idx += 1) {
        if (!df.hasColumn(column_names[name_idx])) {
            // Return error without logging - let caller decide to log
            return error.ColumnNotFound;
        }
    }
    std.debug.assert(name_idx == column_names.len); // Checked all names

    // Create column descriptors for selected columns
    const allocator = df.getAllocator();
    var col_descs = try allocator.alloc(ColumnDesc, column_names.len);

    var col_idx: u32 = 0;
    while (col_idx < MAX_COLS and col_idx < column_names.len) : (col_idx += 1) {
        const src_col = df.column(column_names[col_idx]).?;
        col_descs[col_idx] = ColumnDesc.init(
            column_names[col_idx],
            src_col.value_type,
            @intCast(col_idx),
        );
    }

    std.debug.assert(col_idx == column_names.len); // Processed all columns

    // Create new DataFrame with selected columns
    var new_df = try DataFrame.create(df.arena.child_allocator, col_descs, df.len());
    errdefer new_df.deinit();

    // Copy data from source columns
    col_idx = 0;
    while (col_idx < MAX_COLS and col_idx < column_names.len) : (col_idx += 1) {
        const src_col = df.column(column_names[col_idx]).?;
        const dst_col = &new_df.columns[col_idx];

        // Copy data based on type
        switch (src_col.value_type) {
            .Int64 => {
                const src_data = src_col.asInt64().?;
                const dst_data = dst_col.asInt64Buffer().?;
                @memcpy(dst_data[0..src_data.len], src_data);
            },
            .Float64 => {
                const src_data = src_col.asFloat64().?;
                const dst_data = dst_col.asFloat64Buffer().?;
                @memcpy(dst_data[0..src_data.len], src_data);
            },
            .Bool => {
                const src_data = src_col.asBool().?;
                const dst_data = dst_col.asBoolBuffer().?;
                @memcpy(dst_data[0..src_data.len], src_data);
            },
            .String => {
                const src_string_col = src_col.asStringColumn().?;
                var dst_string_col = dst_col.asStringColumnMut().?;

                // Copy each string from source to destination
                const new_df_allocator = new_df.getAllocator();

                var str_idx: u32 = 0;
                while (str_idx < MAX_ROWS and str_idx < src_string_col.count) : (str_idx += 1) {
                    const str = src_string_col.get(str_idx);
                    try dst_string_col.append(new_df_allocator, str);
                }

                std.debug.assert(str_idx == src_string_col.count); // Copied all strings
            },
            .Categorical => {
                const src_cat_col = src_col.asCategoricalColumn().?;

                // Create deep copy with all rows (independent dictionary)
                const new_df_allocator = new_df.getAllocator();

                // Extract all row indices
                var all_indices = try new_df_allocator.alloc(u32, src_cat_col.count);
                defer new_df_allocator.free(all_indices);

                var i: u32 = 0;
                while (i < MAX_ROWS and i < src_cat_col.count) : (i += 1) {
                    all_indices[i] = i;
                }
                std.debug.assert(i == src_cat_col.count); // Generated all indices

                // Deep copy creates independent dictionary
                const new_cat_col = try src_cat_col.deepCopyRows(
                    new_df_allocator,
                    all_indices,
                );

                // Store the deep copy
                dst_col.data = .{ .Categorical = try new_df_allocator.create(@TypeOf(new_cat_col)) };
                dst_col.data.Categorical.* = new_cat_col;
            },
            .Null => {}, // No data to copy
        }
    }

    std.debug.assert(col_idx == column_names.len); // Copied all columns

    try new_df.setRowCount(df.len());
    return new_df;
}

/// Drops specified columns from a DataFrame
///
/// Args:
///   - df: Source DataFrame
///   - column_names: Array of column names to drop
///
/// Returns: New DataFrame without dropped columns
pub fn drop(
    df: *const DataFrame,
    column_names: []const []const u8,
) !DataFrame {
    std.debug.assert(column_names.len > 0); // Need at least one column to drop
    std.debug.assert(df.columnCount() > 0); // DataFrame must have columns

    // Check if trying to drop all columns (return error instead of asserting)
    if (column_names.len >= df.columnCount()) {
        return error.CannotDropAllColumns;
    }

    // Build list of columns to keep
    const allocator = df.getAllocator();
    var keep_names = try allocator.alloc([]const u8, df.columnCount());
    var keep_count: usize = 0;

    // Check each column in DataFrame
    var col_idx: u32 = 0;
    while (col_idx < MAX_COLS and col_idx < df.columnCount()) : (col_idx += 1) {
        const col_name = df.column_descs[col_idx].name;

        // Check if this column should be dropped
        var should_drop = false;
        var drop_idx: u32 = 0;
        while (drop_idx < MAX_COLS and drop_idx < column_names.len) : (drop_idx += 1) {
            if (std.mem.eql(u8, col_name, column_names[drop_idx])) {
                should_drop = true;
                break;
            }
        }

        // Keep if not in drop list
        if (!should_drop) {
            keep_names[keep_count] = col_name;
            keep_count += 1;
        }
    }

    std.debug.assert(col_idx == df.columnCount()); // Checked all columns
    std.debug.assert(keep_count > 0); // Must keep at least one column

    // Use select() to create DataFrame with remaining columns
    return select(df, keep_names[0..keep_count]);
}

/// Filter predicate function type
pub const FilterFn = *const fn (row: RowRef) bool;

/// Filters rows based on a predicate function
///
/// Args:
///   - df: Source DataFrame
///   - predicate: Function that returns true for rows to keep
///
/// Returns: New DataFrame with filtered rows
pub fn filter(
    df: *const DataFrame,
    predicate: FilterFn,
) !DataFrame {
    std.debug.assert(df.len() > 0); // Need data to filter
    std.debug.assert(df.columnCount() > 0); // Need columns

    // First pass: count matching rows and collect their indices
    var match_count: u32 = 0;
    var row_idx: u32 = 0;

    // Allocate array to store matching row indices (needed for categorical deep copy)
    const allocator = df.getAllocator();
    var matching_indices = try allocator.alloc(u32, df.len());
    defer allocator.free(matching_indices);

    while (row_idx < df.len()) : (row_idx += 1) {
        const row = try df.row(row_idx);
        if (predicate(row)) {
            matching_indices[match_count] = row_idx;
            match_count += 1;
        }
    }

    std.debug.assert(row_idx == df.len()); // Checked all rows

    // Create new DataFrame with same columns, capacity = match_count
    const capacity = if (match_count > 0) match_count else 1;
    var new_df = try DataFrame.create(df.arena.child_allocator, df.column_descs, capacity);
    errdefer new_df.deinit();

    // Second pass: copy matching rows
    var dst_idx: u32 = 0;

    while (dst_idx < MAX_ROWS and dst_idx < match_count) : (dst_idx += 1) {
        const src_row_idx = matching_indices[dst_idx];

        // Copy row data
        var col_idx: u32 = 0;
        while (col_idx < MAX_COLS and col_idx < df.columnCount()) : (col_idx += 1) {
            const src_col = &df.columns[col_idx];
            const dst_col = &new_df.columns[col_idx];

            switch (src_col.value_type) {
                .Int64 => {
                    const src_data = src_col.asInt64().?;
                    const dst_data = dst_col.asInt64Buffer().?;
                    dst_data[dst_idx] = src_data[src_row_idx];
                },
                .Float64 => {
                    const src_data = src_col.asFloat64().?;
                    const dst_data = dst_col.asFloat64Buffer().?;
                    dst_data[dst_idx] = src_data[src_row_idx];
                },
                .Bool => {
                    const src_data = src_col.asBool().?;
                    const dst_data = dst_col.asBoolBuffer().?;
                    dst_data[dst_idx] = src_data[src_row_idx];
                },
                .String => {
                    const src_string_col = src_col.asStringColumn().?;
                    var dst_string_col = dst_col.asStringColumnMut().?;

                    const str = src_string_col.get(src_row_idx);
                    const new_df_allocator = new_df.getAllocator();
                    try dst_string_col.append(new_df_allocator, str);
                },
                .Categorical => {
                    // Categorical columns are handled in the deep copy pass below
                    // We'll rebuild the dictionary after collecting all matching rows
                },
                .Null => {}, // No data to copy
            }
        }

        std.debug.assert(col_idx == df.columnCount()); // Copied all columns
    }

    std.debug.assert(dst_idx == match_count); // Copied all matching rows

    // Third pass: Deep copy categorical columns with new dictionaries
    // This ensures the filtered DataFrame has independent categorical data
    var col_idx: u32 = 0;
    while (col_idx < MAX_COLS and col_idx < df.columnCount()) : (col_idx += 1) {
        const src_col = &df.columns[col_idx];
        if (src_col.value_type == .Categorical) {
            const src_cat_col = src_col.asCategoricalColumn().?;

            // Create deep copy with only matching rows
            const new_df_allocator = new_df.getAllocator();
            const new_cat_col = try src_cat_col.deepCopyRows(
                new_df_allocator,
                matching_indices[0..match_count],
            );

            // Replace the categorical column in the new DataFrame
            // First, free the old pointer (shallow copy from create())
            const dst_col = &new_df.columns[col_idx];
            dst_col.data = .{ .Categorical = try new_df_allocator.create(@TypeOf(new_cat_col)) };
            dst_col.data.Categorical.* = new_cat_col;
        }
    }

    std.debug.assert(col_idx == df.columnCount()); // Processed all columns

    try new_df.setRowCount(match_count);
    return new_df;
}

/// Computes the sum of a numeric column
///
/// Args:
///   - df: Source DataFrame
///   - column_name: Name of column to sum
///
/// Returns: Sum as f64, or null if column is empty
pub fn sum(
    df: *const DataFrame,
    column_name: []const u8,
) !?f64 {
    std.debug.assert(column_name.len > 0); // Name required
    std.debug.assert(df.columnCount() > 0); // Need columns

    const col = df.column(column_name) orelse return error.ColumnNotFound;

    if (df.len() == 0) return null;

    return switch (col.value_type) {
        .Int64 => blk: {
            const data = col.asInt64() orelse return error.TypeMismatch;
            var total: i64 = 0;

            var idx: u32 = 0;
            while (idx < data.len) : (idx += 1) {
                total += data[idx];
            }

            std.debug.assert(idx == data.len); // Processed all values
            break :blk @as(f64, @floatFromInt(total));
        },
        .Float64 => blk: {
            const data = col.asFloat64() orelse return error.TypeMismatch;
            var total: f64 = 0.0;

            var idx: u32 = 0;
            while (idx < data.len) : (idx += 1) {
                total += data[idx];
            }

            std.debug.assert(idx == data.len); // Processed all values
            break :blk total;
        },
        else => error.TypeMismatch,
    };
}

/// Computes the mean (average) of a numeric column
///
/// Args:
///   - df: Source DataFrame
///   - column_name: Name of column to average
///
/// Returns: Mean as f64, or null if column is empty
pub fn mean(
    df: *const DataFrame,
    column_name: []const u8,
) !?f64 {
    std.debug.assert(column_name.len > 0); // Name required
    std.debug.assert(df.columnCount() > 0); // Need columns

    if (df.len() == 0) return null;

    const total = try sum(df, column_name) orelse return null;
    const count = @as(f64, @floatFromInt(df.len()));

    std.debug.assert(count > 0); // Division by zero check

    return total / count;
}

// Tests
test "select creates DataFrame with subset of columns" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("a", .Int64, 0),
        ColumnDesc.init("b", .Int64, 1),
        ColumnDesc.init("c", .Int64, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    try df.setRowCount(5);

    // Select 2 columns
    var selected = try select(&df, &[_][]const u8{ "a", "c" });
    defer selected.deinit();

    try testing.expectEqual(@as(usize, 2), selected.columnCount());
    try testing.expectEqual(@as(u32, 5), selected.len());
    try testing.expect(selected.hasColumn("a"));
    try testing.expect(selected.hasColumn("c"));
    try testing.expect(!selected.hasColumn("b"));
}

test "select returns error for non-existent column" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("a", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    try testing.expectError(error.ColumnNotFound, select(&df, &[_][]const u8{"nonexistent"}));
}

test "drop removes specified columns" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("a", .Int64, 0),
        ColumnDesc.init("b", .Int64, 1),
        ColumnDesc.init("c", .Int64, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    try df.setRowCount(5);

    // Drop 1 column
    var dropped = try drop(&df, &[_][]const u8{"b"});
    defer dropped.deinit();

    try testing.expectEqual(@as(usize, 2), dropped.columnCount());
    try testing.expect(dropped.hasColumn("a"));
    try testing.expect(!dropped.hasColumn("b"));
    try testing.expect(dropped.hasColumn("c"));
}

test "drop returns error when dropping all columns" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("a", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    try testing.expectError(error.CannotDropAllColumns, drop(&df, &[_][]const u8{"a"}));
}

test "filter keeps only matching rows" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
        ColumnDesc.init("score", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    // Set data
    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    ages[0] = 30;
    ages[1] = 25;
    ages[2] = 35;

    try df.setRowCount(3);

    // Filter: age > 28
    var filtered = try filter(&df, struct {
        fn pred(row: RowRef) bool {
            const age = row.getInt64("age") orelse return false;
            return age > 28;
        }
    }.pred);
    defer filtered.deinit();

    // Should have 2 rows (30 and 35)
    try testing.expectEqual(@as(u32, 2), filtered.len());

    const filtered_ages = filtered.column("age").?.asInt64().?;
    try testing.expectEqual(@as(i64, 30), filtered_ages[0]);
    try testing.expectEqual(@as(i64, 35), filtered_ages[1]);
}

test "sum computes total for Int64 column" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const col = df.columnMut("value").?;
    const data = col.asInt64Buffer().?;
    data[0] = 10;
    data[1] = 20;
    data[2] = 30;

    try df.setRowCount(3);

    const total = try sum(&df, "value");
    try testing.expectEqual(@as(?f64, 60.0), total);
}

test "sum computes total for Float64 column" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Float64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const col = df.columnMut("value").?;
    const data = col.asFloat64Buffer().?;
    data[0] = 10.5;
    data[1] = 20.3;
    data[2] = 30.2;

    try df.setRowCount(3);

    const total = try sum(&df, "value");
    try testing.expect(total != null);
    try testing.expectApproxEqRel(@as(f64, 61.0), total.?, 0.01);
}

test "mean computes average" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const col = df.columnMut("value").?;
    const data = col.asInt64Buffer().?;
    data[0] = 10;
    data[1] = 20;
    data[2] = 30;

    try df.setRowCount(3);

    const avg = try mean(&df, "value");
    try testing.expectEqual(@as(?f64, 20.0), avg);
}

test "sum returns null for empty DataFrame" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    try df.setRowCount(0);

    const total = try sum(&df, "value");
    try testing.expectEqual(@as(?f64, null), total);
}

test "mean returns null for empty DataFrame" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    try df.setRowCount(0);

    const avg = try mean(&df, "value");
    try testing.expectEqual(@as(?f64, null), avg);
}

// Integration Tests for String DataFrame Operations

test "Integration: select DataFrame with string column" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
        ColumnDesc.init("city", .String, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    // Populate data
    const name_col = df.columnMut("name").?;
    try name_col.appendString(allocator, "Alice");
    try name_col.appendString(allocator, "Bob");

    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    ages[0] = 30;
    ages[1] = 25;

    const city_col = df.columnMut("city").?;
    try city_col.appendString(allocator, "NYC");
    try city_col.appendString(allocator, "LA");

    try df.setRowCount(2);

    // Select only string columns
    var selected = try select(&df, &[_][]const u8{ "name", "city" });
    defer selected.deinit();

    try testing.expectEqual(@as(usize, 2), selected.columnCount());
    try testing.expectEqual(@as(u32, 2), selected.len());

    // Verify string data was copied correctly
    const sel_name = selected.column("name").?;
    try testing.expectEqualStrings("Alice", sel_name.getString(0).?);
    try testing.expectEqualStrings("Bob", sel_name.getString(1).?);

    const sel_city = selected.column("city").?;
    try testing.expectEqualStrings("NYC", sel_city.getString(0).?);
    try testing.expectEqualStrings("LA", sel_city.getString(1).?);
}

test "Integration: filter DataFrame with string column" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    // Populate data
    const name_col = df.columnMut("name").?;
    try name_col.appendString(allocator, "Alice");
    try name_col.appendString(allocator, "Bob");
    try name_col.appendString(allocator, "Charlie");

    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    ages[0] = 30;
    ages[1] = 25;
    ages[2] = 35;

    try df.setRowCount(3);

    // Filter: age > 28
    var filtered = try filter(&df, struct {
        fn pred(row: RowRef) bool {
            const age = row.getInt64("age") orelse return false;
            return age > 28;
        }
    }.pred);
    defer filtered.deinit();

    // Should have 2 rows (Alice=30, Charlie=35)
    try testing.expectEqual(@as(u32, 2), filtered.len());

    // Verify string data was copied correctly
    const filt_names = filtered.column("name").?;
    try testing.expectEqualStrings("Alice", filt_names.getString(0).?);
    try testing.expectEqualStrings("Charlie", filt_names.getString(1).?);

    const filt_ages = filtered.column("age").?;
    const filt_ages_data = filt_ages.asInt64().?;
    try testing.expectEqual(@as(i64, 30), filt_ages_data[0]);
    try testing.expectEqual(@as(i64, 35), filt_ages_data[1]);
}

/// Creates a deep copy of a DataFrame
///
/// Args:
///   - df: Source DataFrame to clone
///
/// Returns: New DataFrame with copied data
///
/// **Complexity**: O(n*m) where n=rows, m=columns
/// **Memory**: Allocates full copy of all data
///
/// Example:
/// ```zig
/// var cloned = try df.clone();
/// defer cloned.deinit();
/// // cloned is independent of df
/// ```
pub fn clone(df: *const DataFrame) !DataFrame {
    std.debug.assert(df.columnCount() > 0); // Must have columns
    std.debug.assert(df.len() <= MAX_ROWS); // Within row limit

    // Get all column names
    const allocator = df.getAllocator();
    var column_names = try allocator.alloc([]const u8, df.columnCount());
    defer allocator.free(column_names);

    var col_idx: u32 = 0;
    while (col_idx < MAX_COLS and col_idx < df.columnCount()) : (col_idx += 1) {
        column_names[col_idx] = df.column_descs[col_idx].name;
    }
    std.debug.assert(col_idx == df.columnCount()); // Got all column names

    // Use select() to create a full copy
    return select(df, column_names);
}

/// Replaces a column in a DataFrame with a new Series
///
/// Args:
///   - df: Source DataFrame
///   - column_name: Name of column to replace
///   - new_series: New Series data to replace with
///
/// Returns: New DataFrame with replaced column
///
/// **Requirements**:
///   - Column must exist in DataFrame
///   - new_series.length must equal df.len()
///   - new_series name is ignored (column_name is used)
///
/// **Complexity**: O(n*m) where n=rows, m=columns (full copy)
///
/// Example:
/// ```zig
/// const lower_names = try string_ops.lower(df.column("name").?, allocator);
/// var updated = try df.replaceColumn("name", lower_names);
/// defer updated.deinit();
/// ```
pub fn replaceColumn(
    df: *const DataFrame,
    column_name: []const u8,
    new_series: Series,
) !DataFrame {
    std.debug.assert(column_name.len > 0); // Valid column name
    std.debug.assert(new_series.length == df.len()); // Matching row count
    std.debug.assert(df.columnCount() > 0); // Must have columns

    // Verify column exists
    if (!df.hasColumn(column_name)) {
        return error.ColumnNotFound;
    }

    // Verify row count matches
    if (new_series.length != df.len()) {
        logError("replaceColumn: Series length ({}) != DataFrame length ({})", .{ new_series.length, df.len() });
        return error.LengthMismatch;
    }

    // Create new DataFrame by cloning
    var new_df = try clone(df);
    errdefer new_df.deinit();

    // Find the column index
    const col_index = df.columnIndex(column_name).?;

    // Get the destination column
    const dst_col = &new_df.columns[col_index];
    const new_df_allocator = new_df.getAllocator();

    // If types don't match, we need to free old data and allocate new data
    const types_match = dst_col.value_type == new_series.value_type;

    if (!types_match) {
        // Free old column data
        switch (dst_col.value_type) {
            .Int64 => new_df_allocator.free(dst_col.data.Int64),
            .Float64 => new_df_allocator.free(dst_col.data.Float64),
            .Bool => new_df_allocator.free(dst_col.data.Bool),
            .String => dst_col.data.String.deinit(new_df_allocator),
            .Categorical => dst_col.data.Categorical.deinit(new_df_allocator),
            .Null => {},
        }

        // Update the column's value type
        dst_col.value_type = new_series.value_type;
    }

    // Replace the data based on type
    switch (new_series.value_type) {
        .Int64 => {
            const src_data = new_series.asInt64().?;
            if (types_match) {
                const dst_data = dst_col.asInt64Buffer().?;
                @memcpy(dst_data[0..src_data.len], src_data);
            } else {
                const new_data = try new_df_allocator.alloc(i64, new_series.length);
                @memcpy(new_data, src_data);
                dst_col.data = .{ .Int64 = new_data };
            }
        },
        .Float64 => {
            const src_data = new_series.asFloat64().?;
            if (types_match) {
                const dst_data = dst_col.asFloat64Buffer().?;
                @memcpy(dst_data[0..src_data.len], src_data);
            } else {
                const new_data = try new_df_allocator.alloc(f64, new_series.length);
                @memcpy(new_data, src_data);
                dst_col.data = .{ .Float64 = new_data };
            }
        },
        .Bool => {
            const src_data = new_series.asBool().?;
            if (types_match) {
                const dst_data = dst_col.asBoolBuffer().?;
                @memcpy(dst_data[0..src_data.len], src_data);
            } else {
                const new_data = try new_df_allocator.alloc(bool, new_series.length);
                @memcpy(new_data, src_data);
                dst_col.data = .{ .Bool = new_data };
            }
        },
        .String => {
            const src_string_col = new_series.asStringColumn().?;

            // Create a new StringColumn and copy all strings
            var new_string_col = StringColumn.init(new_df_allocator, src_string_col.count, @intCast(src_string_col.buffer.len)) catch |err| {
                return err;
            };

            // Copy each string from new_series
            var str_idx: u32 = 0;
            while (str_idx < MAX_ROWS and str_idx < src_string_col.count) : (str_idx += 1) {
                const str = src_string_col.get(str_idx);
                try new_string_col.append(new_df_allocator, str);
            }
            std.debug.assert(str_idx == src_string_col.count); // Copied all strings

            // Free old string column and replace with new one
            dst_col.data.String.deinit(new_df_allocator);
            dst_col.data = .{ .String = new_string_col };
        },
        .Categorical => {
            const src_cat_col = new_series.asCategoricalColumn().?;

            // Extract all row indices
            var all_indices = try new_df_allocator.alloc(u32, src_cat_col.count);
            defer new_df_allocator.free(all_indices);

            var i: u32 = 0;
            while (i < MAX_ROWS and i < src_cat_col.count) : (i += 1) {
                all_indices[i] = i;
            }
            std.debug.assert(i == src_cat_col.count); // Generated all indices

            // Deep copy creates independent dictionary
            const new_cat_col = try src_cat_col.deepCopyRows(
                new_df_allocator,
                all_indices,
            );

            // Store the deep copy
            dst_col.data = .{ .Categorical = try new_df_allocator.create(@TypeOf(new_cat_col)) };
            dst_col.data.Categorical.* = new_cat_col;
        },
        .Null => {}, // No data to copy
    }

    // Update column descriptor type if it changed
    new_df.column_descs[col_index].value_type = new_series.value_type;
    dst_col.value_type = new_series.value_type;

    return new_df;
}

// ============================================================================
// Tests for clone() and replaceColumn()
// ============================================================================

test "clone() creates independent copy" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create test DataFrame
    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 3);
    defer df.deinit();

    // Add data
    const name_col = df.columnMut("name").?;
    try name_col.appendString(allocator, "Alice");
    try name_col.appendString(allocator, "Bob");
    try name_col.appendString(allocator, "Charlie");

    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    ages[0] = 30;
    ages[1] = 25;
    ages[2] = 35;

    try df.setRowCount(3);

    // Clone the DataFrame
    var cloned = try clone(&df);
    defer cloned.deinit();

    // Verify cloned has same data
    try testing.expectEqual(@as(u32, 3), cloned.len());
    try testing.expectEqual(@as(usize, 2), cloned.columnCount());

    const cloned_names = cloned.column("name").?;
    try testing.expectEqualStrings("Alice", cloned_names.getString(0).?);
    try testing.expectEqualStrings("Bob", cloned_names.getString(1).?);
    try testing.expectEqualStrings("Charlie", cloned_names.getString(2).?);

    const cloned_ages = cloned.column("age").?;
    const ages_data = cloned_ages.asInt64().?;
    try testing.expectEqual(@as(i64, 30), ages_data[0]);
    try testing.expectEqual(@as(i64, 25), ages_data[1]);
    try testing.expectEqual(@as(i64, 35), ages_data[2]);
}

test "replaceColumn() replaces column data" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create test DataFrame
    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 3);
    defer df.deinit();

    // Add data
    const name_col = df.columnMut("name").?;
    try name_col.appendString(allocator, "Alice");
    try name_col.appendString(allocator, "Bob");
    try name_col.appendString(allocator, "Charlie");

    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    ages[0] = 30;
    ages[1] = 25;
    ages[2] = 35;

    try df.setRowCount(3);

    // Create new Series with different ages
    var new_ages = try Series.init(allocator, "age", .Int64, 3);
    defer new_ages.deinit(allocator);

    const new_ages_buf = new_ages.asInt64Buffer().?;
    new_ages_buf[0] = 40;
    new_ages_buf[1] = 35;
    new_ages_buf[2] = 45;
    new_ages.length = 3;

    // Replace the age column
    var updated = try replaceColumn(&df, "age", new_ages);
    defer updated.deinit();

    // Verify updated has new ages
    const updated_ages = updated.column("age").?;
    const updated_ages_data = updated_ages.asInt64().?;
    try testing.expectEqual(@as(i64, 40), updated_ages_data[0]);
    try testing.expectEqual(@as(i64, 35), updated_ages_data[1]);
    try testing.expectEqual(@as(i64, 45), updated_ages_data[2]);

    // Verify original is unchanged
    const orig_ages = df.column("age").?;
    const orig_ages_data = orig_ages.asInt64().?;
    try testing.expectEqual(@as(i64, 30), orig_ages_data[0]);
    try testing.expectEqual(@as(i64, 25), orig_ages_data[1]);
    try testing.expectEqual(@as(i64, 35), orig_ages_data[2]);
}
