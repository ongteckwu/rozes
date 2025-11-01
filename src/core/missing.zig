//! Missing Value Operations - Data cleaning and imputation
//!
//! This module provides operations for handling missing/null values including:
//! - fillna(): Fill missing values with constant or method (ffill, bfill, interpolate)
//! - dropna(): Remove rows with missing values
//! - isna() / notna(): Boolean masks for missing values
//!
//! See docs/TODO.md Phase 4 (Day 15-16) for implementation details.
//!
//! Example:
//! ```
//! const filled = try fillna(&series, allocator, .Constant, 0.0);
//! const clean = try dropna(&df, allocator, .{});
//! const mask = try isna(&series, allocator);
//! ```

const std = @import("std");
const builtin = @import("builtin");
const DataFrame = @import("dataframe.zig").DataFrame;
const Series = @import("series.zig").Series;
const types = @import("types.zig");
const ValueType = types.ValueType;
const ColumnDesc = types.ColumnDesc;
const Allocator = std.mem.Allocator;

/// Log error only when not in test mode (suppresses error output during tests)
fn logError(comptime fmt: []const u8, args: anytype) void {
    if (!builtin.is_test) {
        std.log.err(fmt, args);
    }
}

/// Maximum number of rows for operations
const MAX_ROWS: u32 = 4_000_000_000;

/// Maximum number of columns
const MAX_COLUMNS: u32 = 10_000;

/// Fill method for missing values
pub const FillMethod = enum {
    Constant, // Fill with specific value
    ForwardFill, // Use previous value (ffill)
    BackwardFill, // Use next value (bfill)
    Interpolate, // Linear interpolation (numeric only)
};

/// Options for dropna operation
pub const DropNaOptions = struct {
    subset: ?[]const []const u8 = null, // Columns to check (null = check all)
    how: DropHow = .Any, // How to determine if row should be dropped
};

/// How to determine if row should be dropped
pub const DropHow = enum {
    Any, // Drop if ANY column has null
    All, // Drop only if ALL columns have null
};

/// Fill missing values in a Series
///
/// Args:
///   - series: Input Series
///   - allocator: Allocator for result Series
///   - method: Fill method to use
///   - value: Value to fill with (required for Constant method)
///
/// Returns: New Series with filled values
///
/// **Complexity**: O(n)
pub fn fillna(
    series: *const Series,
    allocator: Allocator,
    method: FillMethod,
    value: ?f64,
) !Series {
    std.debug.assert(series.length > 0); // Need data
    std.debug.assert(series.length <= MAX_ROWS); // Reasonable limit

    return switch (method) {
        .Constant => try fillConstant(series, allocator, value.?),
        .ForwardFill => try fillForward(series, allocator),
        .BackwardFill => try fillBackward(series, allocator),
        .Interpolate => try fillInterpolate(series, allocator),
    };
}

/// Fill with constant value
fn fillConstant(
    series: *const Series,
    allocator: Allocator,
    fill_value: f64,
) !Series {
    std.debug.assert(series.length > 0); // Need data
    std.debug.assert(!std.math.isNan(fill_value)); // Valid fill value

    return switch (series.value_type) {
        .Int64 => blk: {
            const src = series.asInt64() orelse return error.TypeMismatch;
            var dst = try allocator.alloc(i64, src.len);
            errdefer allocator.free(dst);

            const fill_int = @as(i64, @intFromFloat(fill_value));

            var idx: u32 = 0;
            while (idx < MAX_ROWS and idx < src.len) : (idx += 1) {
                // For Int64, we treat 0 as "missing" (simplified approach)
                dst[idx] = if (src[idx] == 0) fill_int else src[idx];
            }
            std.debug.assert(idx == src.len); // Processed all

            break :blk Series{
                .name = series.name,
                .value_type = .Int64,
                .data = .{ .Int64 = dst },
                .length = series.length,
            };
        },
        .Float64 => blk: {
            const src = series.asFloat64() orelse return error.TypeMismatch;
            var dst = try allocator.alloc(f64, src.len);
            errdefer allocator.free(dst);

            var idx: u32 = 0;
            while (idx < MAX_ROWS and idx < src.len) : (idx += 1) {
                // For Float64, treat NaN as missing
                dst[idx] = if (std.math.isNan(src[idx])) fill_value else src[idx];
            }
            std.debug.assert(idx == src.len); // Processed all

            break :blk Series{
                .name = series.name,
                .value_type = .Float64,
                .data = .{ .Float64 = dst },
                .length = series.length,
            };
        },
        else => error.TypeMismatch,
    };
}

/// Fill with previous value (forward fill)
fn fillForward(
    series: *const Series,
    allocator: Allocator,
) !Series {
    std.debug.assert(series.length > 0); // Need data

    return switch (series.value_type) {
        .Int64 => blk: {
            const src = series.asInt64() orelse return error.TypeMismatch;
            var dst = try allocator.alloc(i64, src.len);
            errdefer allocator.free(dst);

            var last_valid: i64 = 0;

            var idx: u32 = 0;
            while (idx < MAX_ROWS and idx < src.len) : (idx += 1) {
                if (src[idx] != 0) {
                    last_valid = src[idx];
                    dst[idx] = src[idx];
                } else {
                    dst[idx] = last_valid;
                }
            }
            std.debug.assert(idx == src.len); // Processed all

            break :blk Series{
                .name = series.name,
                .value_type = .Int64,
                .data = .{ .Int64 = dst },
                .length = series.length,
            };
        },
        .Float64 => blk: {
            const src = series.asFloat64() orelse return error.TypeMismatch;
            var dst = try allocator.alloc(f64, src.len);
            errdefer allocator.free(dst);

            var last_valid: f64 = 0.0;

            var idx: u32 = 0;
            while (idx < MAX_ROWS and idx < src.len) : (idx += 1) {
                if (!std.math.isNan(src[idx])) {
                    last_valid = src[idx];
                    dst[idx] = src[idx];
                } else {
                    dst[idx] = last_valid;
                }
            }
            std.debug.assert(idx == src.len); // Processed all

            break :blk Series{
                .name = series.name,
                .value_type = .Float64,
                .data = .{ .Float64 = dst },
                .length = series.length,
            };
        },
        else => error.TypeMismatch,
    };
}

/// Fill with next value (backward fill)
fn fillBackward(
    series: *const Series,
    allocator: Allocator,
) !Series {
    std.debug.assert(series.length > 0); // Need data

    return switch (series.value_type) {
        .Int64 => blk: {
            const src = series.asInt64() orelse return error.TypeMismatch;
            var dst = try allocator.alloc(i64, src.len);
            errdefer allocator.free(dst);

            var last_valid: i64 = 0;

            // Scan backward
            var idx: u32 = @intCast(src.len);
            while (idx > 0) {
                idx -= 1;
                if (src[idx] != 0) {
                    last_valid = src[idx];
                    dst[idx] = src[idx];
                } else {
                    dst[idx] = last_valid;
                }
            }
            std.debug.assert(idx == 0); // Processed all

            break :blk Series{
                .name = series.name,
                .value_type = .Int64,
                .data = .{ .Int64 = dst },
                .length = series.length,
            };
        },
        .Float64 => blk: {
            const src = series.asFloat64() orelse return error.TypeMismatch;
            var dst = try allocator.alloc(f64, src.len);
            errdefer allocator.free(dst);

            var last_valid: f64 = 0.0;

            // Scan backward
            var idx: u32 = @intCast(src.len);
            while (idx > 0) {
                idx -= 1;
                if (!std.math.isNan(src[idx])) {
                    last_valid = src[idx];
                    dst[idx] = src[idx];
                } else {
                    dst[idx] = last_valid;
                }
            }
            std.debug.assert(idx == 0); // Processed all

            break :blk Series{
                .name = series.name,
                .value_type = .Float64,
                .data = .{ .Float64 = dst },
                .length = series.length,
            };
        },
        else => error.TypeMismatch,
    };
}

/// Fill with linear interpolation
fn fillInterpolate(
    series: *const Series,
    allocator: Allocator,
) !Series {
    std.debug.assert(series.length > 0); // Need data

    // Only support Float64 for interpolation
    if (series.value_type != .Float64) {
        return error.TypeMismatch;
    }

    const src = series.asFloat64() orelse return error.TypeMismatch;
    var dst = try allocator.alloc(f64, src.len);
    errdefer allocator.free(dst);

    var idx: u32 = 0;
    while (idx < MAX_ROWS and idx < src.len) : (idx += 1) {
        if (!std.math.isNan(src[idx])) {
            dst[idx] = src[idx];
        } else {
            // Find previous and next valid values
            const prev_idx = findPrevValid(src, idx);
            const next_idx = findNextValid(src, idx);

            if (prev_idx != null and next_idx != null) {
                // Interpolate between prev and next
                const prev_val = src[prev_idx.?];
                const next_val = src[next_idx.?];

                // Cannot interpolate if either endpoint is NaN
                if (std.math.isNan(prev_val) or std.math.isNan(next_val)) {
                    dst[idx] = std.math.nan(f64);
                } else {
                    // Tiger Style: Invariant check for division by zero
                    const range_diff = next_idx.? - prev_idx.?;
                    std.debug.assert(range_diff > 0); // Invariant: next > prev

                    const t = @as(f64, @floatFromInt(idx - prev_idx.?)) / @as(f64, @floatFromInt(range_diff));
                    dst[idx] = prev_val + t * (next_val - prev_val);
                }
            } else if (prev_idx != null) {
                // Use prev value (no next available)
                dst[idx] = src[prev_idx.?];
            } else if (next_idx != null) {
                // Use next value (no prev available)
                dst[idx] = src[next_idx.?];
            } else {
                // No valid values found (all NaN)
                dst[idx] = 0.0;
            }
        }
    }
    std.debug.assert(idx == src.len); // Processed all

    return Series{
        .name = series.name,
        .value_type = .Float64,
        .data = .{ .Float64 = dst },
        .length = series.length,
    };
}

/// Helper to find previous valid value
fn findPrevValid(data: []const f64, start_idx: u32) ?u32 {
    // Tiger Style: 2+ assertions for helper functions
    std.debug.assert(data.len > 0); // Assertion 1: Valid data
    std.debug.assert(start_idx <= data.len); // Assertion 2: Bounds check

    if (start_idx == 0) return null;

    var idx = start_idx - 1;
    const MAX_SCAN: u32 = start_idx; // Max iterations = start_idx
    var i: u32 = 0;

    while (i < MAX_SCAN) : (i += 1) {
        if (!std.math.isNan(data[idx])) {
            std.debug.assert(idx < data.len); // Assertion 3: Found valid index
            return idx;
        }
        if (idx == 0) return null;
        idx -= 1;
    }

    std.debug.assert(i == MAX_SCAN); // Post-condition: Scanned all positions
    return null; // No valid value found
}

/// Helper to find next valid value
fn findNextValid(data: []const f64, start_idx: u32) ?u32 {
    // Tiger Style: 2+ assertions for helper functions
    std.debug.assert(data.len > 0); // Assertion 1: Valid data
    std.debug.assert(start_idx < data.len); // Assertion 2: Bounds check

    var idx = start_idx + 1;
    const MAX_SCAN: u32 = @intCast(data.len - start_idx - 1); // Max iterations

    var i: u32 = 0;
    while (i < MAX_SCAN and idx < data.len) : ({ i += 1; idx += 1; }) {
        if (!std.math.isNan(data[idx])) {
            std.debug.assert(idx < data.len); // Assertion 3: Found valid index
            return idx;
        }
    }

    std.debug.assert(i <= MAX_SCAN); // Post-condition: Scanned all positions
    return null; // No valid value found
}

/// Drop rows with missing values from DataFrame
///
/// Args:
///   - df: Input DataFrame
///   - allocator: Allocator for result DataFrame
///   - opts: Options for dropping (subset columns, how to determine)
///
/// Returns: New DataFrame with rows removed
///
/// **Complexity**: O(n * m) where n=rows, m=columns
pub fn dropna(
    df: *const DataFrame,
    allocator: Allocator,
    opts: DropNaOptions,
) !DataFrame {
    std.debug.assert(df.len() > 0); // Need data
    std.debug.assert(df.columnCount() > 0); // Need columns

    // First pass: count rows to keep
    var keep_count: u32 = 0;

    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < df.len()) : (row_idx += 1) {
        if (try shouldKeepRow(df, row_idx, opts)) {
            keep_count += 1;
        }
    }
    std.debug.assert(row_idx == df.len()); // Checked all rows

    // Create new DataFrame with same columns
    const capacity = if (keep_count > 0) keep_count else 1;
    var new_df = try DataFrame.create(allocator, df.column_descs, capacity);
    errdefer new_df.deinit();

    // Second pass: copy rows to keep
    row_idx = 0;
    var dst_idx: u32 = 0;

    while (row_idx < MAX_ROWS and row_idx < df.len()) : (row_idx += 1) {
        if (try shouldKeepRow(df, row_idx, opts)) {
            // Copy row data
            var col_idx: u32 = 0;
            while (col_idx < df.columnCount()) : (col_idx += 1) {
                const src_col = &df.columns[col_idx];
                const dst_col = &new_df.columns[col_idx];

                switch (src_col.value_type) {
                    .Int64 => {
                        const src_data = src_col.asInt64().?;
                        const dst_data = dst_col.asInt64Buffer().?;
                        dst_data[dst_idx] = src_data[row_idx];
                    },
                    .Float64 => {
                        const src_data = src_col.asFloat64().?;
                        const dst_data = dst_col.asFloat64Buffer().?;
                        dst_data[dst_idx] = src_data[row_idx];
                    },
                    .Bool => {
                        const src_data = src_col.asBool().?;
                        const dst_data = dst_col.asBoolBuffer().?;
                        dst_data[dst_idx] = src_data[row_idx];
                    },
                    else => {}, // Skip unsupported types
                }
            }

            dst_idx += 1;
        }
    }

    std.debug.assert(dst_idx == keep_count); // Copied all kept rows

    try new_df.setRowCount(keep_count);
    return new_df;
}

/// Helper to determine if row should be kept
fn shouldKeepRow(
    df: *const DataFrame,
    row_idx: u32,
    opts: DropNaOptions,
) !bool {
    const columns_to_check = opts.subset orelse blk: {
        // Check all columns
        var names = try std.ArrayList([]const u8).initCapacity(std.heap.page_allocator, df.columnCount());
        defer names.deinit(std.heap.page_allocator);

        var col_idx: u32 = 0;
        while (col_idx < df.columnCount()) : (col_idx += 1) {
            try names.append(std.heap.page_allocator, df.column_descs[col_idx].name);
        }

        break :blk try names.toOwnedSlice(std.heap.page_allocator);
    };

    var has_missing = false;
    var all_missing = true;

    std.debug.assert(columns_to_check.len <= MAX_COLUMNS); // Pre-condition

    // Bounded iteration over columns to check
    var col_idx: u32 = 0;
    while (col_idx < MAX_COLUMNS and col_idx < columns_to_check.len) : (col_idx += 1) {
        const col_name = columns_to_check[col_idx];
        const col = df.column(col_name) orelse {
            logError("dropna: Column '{s}' not found in DataFrame", .{col_name});
            continue;
        };

        const is_missing = switch (col.value_type) {
            .Int64 => blk: {
                const data = col.asInt64() orelse break :blk false;
                break :blk data[row_idx] == 0; // Treat 0 as missing
            },
            .Float64 => blk: {
                const data = col.asFloat64() orelse break :blk false;
                break :blk std.math.isNan(data[row_idx]);
            },
            else => false,
        };

        if (is_missing) {
            has_missing = true;
        } else {
            all_missing = false;
        }
    }
    std.debug.assert(col_idx == columns_to_check.len); // Post-condition

    return switch (opts.how) {
        .Any => !has_missing, // Keep if NO columns are missing
        .All => !all_missing, // Keep if NOT ALL columns are missing
    };
}

/// Create boolean mask for missing values in Series
///
/// Args:
///   - series: Input Series
///   - allocator: Allocator for result Series
///
/// Returns: Series of Bool type with true for missing values
///
/// **Complexity**: O(n)
pub fn isna(
    series: *const Series,
    allocator: Allocator,
) !Series {
    std.debug.assert(series.length > 0); // Need data
    std.debug.assert(series.length <= MAX_ROWS); // Reasonable limit

    var mask = try allocator.alloc(bool, series.length);
    errdefer allocator.free(mask);

    return switch (series.value_type) {
        .Int64 => blk: {
            const data = series.asInt64() orelse return error.TypeMismatch;

            var idx: u32 = 0;
            while (idx < MAX_ROWS and idx < data.len) : (idx += 1) {
                mask[idx] = (data[idx] == 0); // 0 is treated as missing
            }
            std.debug.assert(idx == data.len); // Processed all

            break :blk Series{
                .name = series.name,
                .value_type = .Bool,
                .data = .{ .Bool = mask },
                .length = series.length,
            };
        },
        .Float64 => blk: {
            const data = series.asFloat64() orelse return error.TypeMismatch;

            var idx: u32 = 0;
            while (idx < MAX_ROWS and idx < data.len) : (idx += 1) {
                mask[idx] = std.math.isNan(data[idx]);
            }
            std.debug.assert(idx == data.len); // Processed all

            break :blk Series{
                .name = series.name,
                .value_type = .Bool,
                .data = .{ .Bool = mask },
                .length = series.length,
            };
        },
        else => error.TypeMismatch,
    };
}

/// Create boolean mask for non-missing values in Series
///
/// Args:
///   - series: Input Series
///   - allocator: Allocator for result Series
///
/// Returns: Series of Bool type with true for non-missing values
///
/// **Complexity**: O(n)
pub fn notna(
    series: *const Series,
    allocator: Allocator,
) !Series {
    std.debug.assert(series.length > 0); // Need data
    std.debug.assert(series.length <= MAX_ROWS); // Reasonable limit

    const mask_series = try isna(series, allocator);
    defer allocator.free(mask_series.data.Bool);

    // Invert mask
    var inverted = try allocator.alloc(bool, series.length);
    errdefer allocator.free(inverted);

    const mask = mask_series.data.Bool;

    var idx: u32 = 0;
    while (idx < MAX_ROWS and idx < mask.len) : (idx += 1) {
        inverted[idx] = !mask[idx];
    }
    std.debug.assert(idx == mask.len); // Inverted all

    return Series{
        .name = series.name,
        .value_type = .Bool,
        .data = .{ .Bool = inverted },
        .length = series.length,
    };
}
