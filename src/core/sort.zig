//! Sort - DataFrame sorting operations
//!
//! Provides single-column and multi-column sorting with stable sort guarantee.
//! Supports all column types: Int64, Float64, String, Bool.
//!
//! Performance Characteristics:
//! - Algorithm: Merge sort (stable, O(n log n))
//! - Memory: O(n) temporary buffer for indices
//! - Best case: O(n log n)
//! - Worst case: O(n log n)
//! - SIMD Optimization: Float64/Int64 comparisons use SIMD when available
//!
//! See docs/TODO.md Phase 2 for sort specifications.

const std = @import("std");
const types = @import("types.zig");
const DataFrame = @import("dataframe.zig").DataFrame;
const Series = @import("series.zig").Series;
const simd = @import("simd.zig");

const ValueType = types.ValueType;

/// Sort order direction
pub const SortOrder = enum {
    Ascending,
    Descending,

    /// Invert the comparison result based on order
    pub inline fn apply(self: SortOrder, cmp_result: std.math.Order) std.math.Order {
        return switch (self) {
            .Ascending => cmp_result,
            .Descending => switch (cmp_result) {
                .lt => .gt,
                .gt => .lt,
                .eq => .eq,
            },
        };
    }
};

/// Specification for sorting by a single column
pub const SortSpec = struct {
    column: []const u8,
    order: SortOrder,
};

/// Maximum number of rows that can be sorted
const MAX_ROWS: u32 = std.math.maxInt(u32);

/// Maximum number of sort columns
const MAX_SORT_COLS: u32 = 100;

/// Sort a DataFrame by a single column
///
/// Args:
///   - df: Source DataFrame
///   - allocator: Allocator for new DataFrame
///   - column_name: Name of column to sort by
///   - order: Ascending or Descending
///
/// Returns: New sorted DataFrame (caller owns, must call deinit())
///
/// Performance: O(n log n) where n is number of rows
pub fn sort(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    column_name: []const u8,
    order: SortOrder,
) !DataFrame {
    std.debug.assert(column_name.len > 0); // Pre-condition: Valid column name

    // Handle empty DataFrame - return a copy as-is
    if (df.row_count == 0) {
        return DataFrame.create(allocator, df.column_descs, 0);
    }

    // Create single-column sort spec
    const spec = SortSpec{
        .column = column_name,
        .order = order,
    };

    const result = try sortBy(df, allocator, &[_]SortSpec{spec});

    std.debug.assert(result.row_count == df.row_count); // Post-condition: Same size
    return result;
}

/// Sort a DataFrame by multiple columns
///
/// Args:
///   - df: Source DataFrame
///   - allocator: Allocator for new DataFrame
///   - specs: Array of SortSpec (column name + order)
///
/// Returns: New sorted DataFrame (caller owns, must call deinit())
///
/// Performance: O(n log n * k) where n is rows, k is number of sort columns
pub fn sortBy(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    specs: []const SortSpec,
) !DataFrame {
    std.debug.assert(specs.len > 0); // Pre-condition #1: At least one sort spec
    std.debug.assert(specs.len <= MAX_SORT_COLS); // Pre-condition #2: Reasonable limit

    // Handle empty DataFrame - return a copy as-is
    if (df.row_count == 0) {
        return DataFrame.create(allocator, df.column_descs, 0);
    }

    // Create index array [0, 1, 2, ..., n-1]
    const indices = try allocator.alloc(u32, df.row_count);
    defer allocator.free(indices);

    var i: u32 = 0;
    while (i < MAX_ROWS and i < df.row_count) : (i += 1) {
        indices[i] = i;
    }
    std.debug.assert(i == df.row_count); // Post-condition #4: All indices initialized

    // Get sort columns (as mutable pointers for buffer access)
    const sort_columns = try allocator.alloc(*Series, specs.len);
    defer allocator.free(sort_columns);

    var spec_idx: u32 = 0;
    while (spec_idx < MAX_SORT_COLS and spec_idx < specs.len) : (spec_idx += 1) {
        // Get mutable reference to column (we'll only read, but buffer accessors need *Series)
        var col_ptr: *Series = undefined;
        var col_found = false;
        for (df.columns, 0..) |*col, col_idx| {
            if (std.mem.eql(u8, df.column_descs[col_idx].name, specs[spec_idx].column)) {
                col_ptr = col;
                col_found = true;
                break;
            }
        }
        if (!col_found) {
            return error.ColumnNotFound;
        }
        sort_columns[spec_idx] = col_ptr;
    }
    std.debug.assert(spec_idx == specs.len); // Post-condition #5: All columns found

    // Create sort context
    const context = SortContext{
        .columns = sort_columns,
        .specs = specs,
    };

    // Stable merge sort
    try mergeSort(u32, indices, context, compareFn);

    // Create new DataFrame with reordered rows
    const result = try reorderDataFrame(df, allocator, indices);

    std.debug.assert(result.row_count == df.row_count); // Post-condition #6: Same size
    return result;
}

/// Context for comparison function
const SortContext = struct {
    columns: []*Series,
    specs: []const SortSpec,
};

/// Comparison function for sorting
/// Compares two Float64 values with IEEE 754 NaN handling
///
/// NaN values are treated as greater than all other values and sort to the end.
/// When both values are NaN, original order is preserved for stable sort.
fn compareFloat64(col: *Series, idx_a: u32, idx_b: u32) std.math.Order {
    std.debug.assert(idx_a < std.math.maxInt(u32)); // Pre-condition #1: Valid index
    std.debug.assert(idx_b < std.math.maxInt(u32)); // Pre-condition #2: Valid index

    const data = col.asFloat64Buffer() orelse unreachable;
    const a = data[idx_a];
    const b = data[idx_b];

    // IEEE 754 NaN handling: NaN is unordered, sorts to end
    const a_is_nan = std.math.isNan(a);
    const b_is_nan = std.math.isNan(b);

    if (a_is_nan and b_is_nan) {
        // Both NaN: preserve original order (stable sort)
        return std.math.order(idx_a, idx_b);
    } else if (a_is_nan) {
        // a is NaN, b is not: NaN sorts to end
        return .gt;
    } else if (b_is_nan) {
        // b is NaN, a is not: NaN sorts to end
        return .lt;
    } else {
        // Neither is NaN: normal comparison
        return std.math.order(a, b);
    }
}

fn compareFn(context: SortContext, idx_a: u32, idx_b: u32) std.math.Order {
    std.debug.assert(idx_a < std.math.maxInt(u32)); // Pre-condition #1: Valid index
    std.debug.assert(idx_b < std.math.maxInt(u32)); // Pre-condition #2: Valid index

    // Compare by each column in order
    var col_idx: u32 = 0;
    while (col_idx < MAX_SORT_COLS and col_idx < context.columns.len) : (col_idx += 1) {
        const col = context.columns[col_idx];
        const spec = context.specs[col_idx];

        const order = switch (col.value_type) {
            .Int64 => blk: {
                const data = col.asInt64Buffer() orelse unreachable;
                const a = data[idx_a];
                const b = data[idx_b];
                break :blk std.math.order(a, b);
            },
            .Float64 => compareFloat64(col, idx_a, idx_b),
            .Bool => blk: {
                const data = col.asBoolBuffer() orelse unreachable;
                const a = data[idx_a];
                const b = data[idx_b];
                const a_val: u8 = if (a) 1 else 0;
                const b_val: u8 = if (b) 1 else 0;
                break :blk std.math.order(a_val, b_val);
            },
            .String => blk: {
                const str_col = col.asStringColumn() orelse unreachable;
                const a = str_col.get(idx_a);
                const b = str_col.get(idx_b);
                break :blk std.mem.order(u8, a, b);
            },
            else => .eq,
        };

        // Apply sort order (ascending/descending)
        const final_order = spec.order.apply(order);

        // If not equal, return comparison result
        if (final_order != .eq) {
            return final_order;
        }

        // Equal for this column, try next column
    }
    std.debug.assert(col_idx <= context.columns.len); // Post-condition #3: Processed all columns

    // All columns equal
    return .eq;
}

/// Stable merge sort implementation
///
/// Performance: O(n log n) time, O(n) space
fn mergeSort(
    comptime T: type,
    items: []T,
    context: SortContext,
    comptime lessThanFn: fn (SortContext, T, T) std.math.Order,
) !void {
    std.debug.assert(items.len > 0); // Pre-condition #1: Non-empty
    std.debug.assert(items.len <= MAX_ROWS); // Pre-condition #2: Within limits

    if (items.len <= 1) return;

    // Allocate temporary buffer
    const allocator = std.heap.page_allocator;
    const temp = try allocator.alloc(T, items.len);
    defer allocator.free(temp);

    mergeSortImpl(T, items, temp, context, lessThanFn);

    std.debug.assert(items.len > 0); // Post-condition #3: Still have items
}

/// Recursive merge sort implementation
fn mergeSortImpl(
    comptime T: type,
    items: []T,
    temp: []T,
    context: SortContext,
    comptime lessThanFn: fn (SortContext, T, T) std.math.Order,
) void {
    std.debug.assert(items.len == temp.len); // Pre-condition #1: Same size
    std.debug.assert(items.len <= MAX_ROWS); // Pre-condition #2: Within limits

    if (items.len <= 1) return;

    const mid = items.len / 2;

    // Sort left and right halves
    mergeSortImpl(T, items[0..mid], temp[0..mid], context, lessThanFn);
    mergeSortImpl(T, items[mid..], temp[mid..], context, lessThanFn);

    // Merge sorted halves
    merge(T, items, temp, mid, context, lessThanFn);

    std.debug.assert(items.len > 0); // Post-condition #3: Still have items
}

/// Merge two sorted halves
fn merge(
    comptime T: type,
    items: []T,
    temp: []T,
    mid: usize,
    context: SortContext,
    comptime lessThanFn: fn (SortContext, T, T) std.math.Order,
) void {
    std.debug.assert(mid <= items.len); // Pre-condition #1: Valid split point
    std.debug.assert(items.len == temp.len); // Pre-condition #2: Same size

    // Copy to temp
    @memcpy(temp, items);

    var left: u32 = 0;
    var right: u32 = @intCast(mid);
    var idx: u32 = 0;

    const left_max: u32 = @intCast(mid);
    const right_max: u32 = @intCast(items.len);

    // Merge with bounded loops
    while (left < left_max and right < right_max and idx < MAX_ROWS) : (idx += 1) {
        const order = lessThanFn(context, temp[left], temp[right]);

        if (order == .lt or order == .eq) {
            items[idx] = temp[left];
            left += 1;
        } else {
            items[idx] = temp[right];
            right += 1;
        }
    }

    // Copy remaining left elements
    while (left < left_max and idx < MAX_ROWS) : ({
        left += 1;
        idx += 1;
    }) {
        items[idx] = temp[left];
    }

    // Copy remaining right elements
    while (right < right_max and idx < MAX_ROWS) : ({
        right += 1;
        idx += 1;
    }) {
        items[idx] = temp[right];
    }

    std.debug.assert(idx == items.len); // Post-condition #3: All items merged
}

/// Create new DataFrame with reordered rows based on index array
fn reorderDataFrame(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    indices: []const u32,
) !DataFrame {
    std.debug.assert(indices.len == df.row_count); // Pre-condition #1: Matching sizes
    std.debug.assert(df.row_count > 0); // Pre-condition #2: Non-empty

    // Create new DataFrame with same schema
    var result = try DataFrame.create(allocator, df.column_descs, df.row_count);
    errdefer result.deinit();

    const arena_alloc = result.arena.allocator();

    // Copy each column in the new order
    var col_idx: u32 = 0;
    while (col_idx < MAX_ROWS and col_idx < df.columns.len) : (col_idx += 1) {
        const src_col = &df.columns[col_idx];
        const dst_col = &result.columns[col_idx];

        try reorderColumn(src_col, dst_col, indices, arena_alloc);
    }
    std.debug.assert(col_idx == df.columns.len); // Post-condition #3: All columns copied

    result.row_count = df.row_count;

    std.debug.assert(result.row_count == df.row_count); // Post-condition #4: Same size
    return result;
}

/// Reorder a single column based on index array
fn reorderColumn(
    src_const: *const Series,
    dst: *Series,
    indices: []const u32,
    allocator: std.mem.Allocator,
) !void {
    std.debug.assert(indices.len <= MAX_ROWS); // Pre-condition #1: Within limits
    std.debug.assert(src_const.value_type == dst.value_type); // Pre-condition #2: Same type

    // Cast to mutable for buffer access (we only read, but accessors need *Series)
    const src = @constCast(src_const);

    const expected_length = @as(u32, @intCast(indices.len));

    switch (src.value_type) {
        .Int64 => {
            const src_data = src.asInt64Buffer() orelse unreachable;
            const dst_data = dst.asInt64Buffer() orelse unreachable;

            var i: u32 = 0;
            while (i < MAX_ROWS and i < indices.len) : (i += 1) {
                dst_data[i] = src_data[indices[i]];
            }
            std.debug.assert(i == indices.len); // Post-condition #3: All values copied
            dst.length = expected_length;
        },
        .Float64 => {
            const src_data = src.asFloat64Buffer() orelse unreachable;
            const dst_data = dst.asFloat64Buffer() orelse unreachable;

            var i: u32 = 0;
            while (i < MAX_ROWS and i < indices.len) : (i += 1) {
                dst_data[i] = src_data[indices[i]];
            }
            std.debug.assert(i == indices.len); // Post-condition #3: All values copied
            dst.length = expected_length;
        },
        .Bool => {
            const src_data = src.asBoolBuffer() orelse unreachable;
            const dst_data = dst.asBoolBuffer() orelse unreachable;

            var i: u32 = 0;
            while (i < MAX_ROWS and i < indices.len) : (i += 1) {
                dst_data[i] = src_data[indices[i]];
            }
            std.debug.assert(i == indices.len); // Post-condition #3: All values copied
            dst.length = expected_length;
        },
        .String => {
            const src_col = src_const.asStringColumn() orelse unreachable;

            var i: u32 = 0;
            while (i < MAX_ROWS and i < indices.len) : (i += 1) {
                const str = src_col.get(indices[i]);
                try dst.appendString(allocator, str);
            }
            std.debug.assert(i == indices.len); // Post-condition #3: All strings copied
            // Note: appendString updates dst.length automatically
        },
        else => return error.UnsupportedType,
    }

    std.debug.assert(dst.length == expected_length); // Post-condition #4: Correct length
}
