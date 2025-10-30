//! Functional Programming Operations for DataFrame
//!
//! This module provides user-defined function operations:
//! - apply(): Apply function to each row or column
//! - map(): Element-wise transformations (type-specific)
//! - filter(): Custom filter predicates (extends existing filter)
//!
//! Features:
//! - Type-safe function signatures using comptime
//! - Row-wise and column-wise operations
//! - Efficient execution with bounded loops
//! - Tiger Style compliant (2+ assertions, bounded loops, <70 lines per function)
//!
//! **Design Decision: Why Type-Specific Map Functions?**
//!
//! Zig's comptime type system prevents generic dispatch with type-specific function pointers.
//! A generic `map()` that accepts `fn(T) T` cannot branch on Series type at runtime because
//! all branches are instantiated at compile time, causing type errors.
//!
//! **Alternative Considered** (rejected due to compiler limitations):
//! ```zig
//! pub fn map(comptime FuncType: type, func: FuncType, series: *const Series) !Series {
//!     switch (series.value_type) {
//!         .Float64 => mapFloat64To(FuncType, func, series), // func: fn(f64) f64
//!         .Int64 => mapInt64To(FuncType, func, series),     // ❌ Compiler error!
//!         // Compiler tries to compile BOTH branches regardless of runtime type,
//!         // causing type errors when func signature doesn't match.
//!     }
//! }
//! ```
//!
//! **Solution**: Type-specific functions (mapFloat64, mapInt64, mapBool) avoid comptime
//! conflicts and provide clear, explicit API with zero runtime overhead.
//!
//! **Benefits**:
//! - ✅ Explicit type safety at compile time
//! - ✅ No runtime type checking overhead
//! - ✅ Clear API - users know exactly what function signature is required
//! - ✅ No comptime complexity or edge cases
//!
//! See docs/TODO.md Milestone 0.6.0 Phase 3 for implementation details.

const std = @import("std");
const types = @import("types.zig");
const series_mod = @import("series.zig");
const dataframe_mod = @import("dataframe.zig");

const ValueType = types.ValueType;
const ColumnDesc = types.ColumnDesc;
const Series = series_mod.Series;
const DataFrame = dataframe_mod.DataFrame;
const RowRef = dataframe_mod.RowRef;

/// Maximum number of rows for apply operations (4 billion limit)
const MAX_ROWS: u32 = std.math.maxInt(u32);

/// Maximum number of columns
const MAX_COLS: u32 = 10_000;

/// Apply axis - determines whether function is applied row-wise or column-wise
pub const ApplyAxis = enum {
    /// Apply function to each row (RowRef → Value)
    rows,
    /// Apply function to each column (Series → Series)
    columns,
};

/// Options for apply operation
pub const ApplyOptions = struct {
    /// Axis to apply function along (default: rows)
    axis: ApplyAxis = .rows,
    /// Result type for row-wise operations (required for axis=rows)
    result_type: ?ValueType = null,
};

/// Apply a function to each row of the DataFrame, returning a new Series
///
/// **Usage**: Row-wise operations where result depends on multiple columns
///
/// **Performance**: O(n) where n = row_count
/// **Memory**: Allocates result series
///
/// Example:
/// ```zig
/// fn calculateDiscount(row: RowRef) f64 {
///     const price = row.getFloat64("price") orelse return 0;
///     const quantity = row.getInt64("quantity") orelse return 0;
///     return price * @as(f64, @floatFromInt(quantity)) * 0.1;
/// }
///
/// const discounts = try apply(allocator, &df, calculateDiscount, .{
///     .axis = .rows,
///     .result_type = .Float64,
/// });
/// defer discounts.deinit();
/// ```
pub fn apply(
    allocator: std.mem.Allocator,
    df: *const DataFrame,
    comptime FuncType: type,
    comptime func: FuncType,
    opts: ApplyOptions,
) !Series {
    std.debug.assert(df.row_count > 0); // DataFrame must have rows
    std.debug.assert(df.row_count <= MAX_ROWS); // Within limits

    switch (opts.axis) {
        .rows => {
            // Result type must be specified for row-wise operations
            const result_type = opts.result_type orelse return error.ResultTypeRequired;
            return try applyRows(allocator, df, FuncType, func, result_type);
        },
        .columns => {
            // Column-wise operations (to be implemented)
            return error.ColumnWiseNotYetImplemented;
        },
    }
}

/// Apply function to each row, returning Float64 series
fn applyRows(
    allocator: std.mem.Allocator,
    df: *const DataFrame,
    comptime FuncType: type,
    comptime func: FuncType,
    result_type: ValueType,
) !Series {
    std.debug.assert(df.row_count > 0); // DataFrame must have rows
    std.debug.assert(df.row_count <= MAX_ROWS); // Within limits

    // Infer return type from function
    const FuncReturnType = @TypeOf(func(RowRef{ .dataframe = df, .rowIndex = 0 }));

    // Create result series based on result_type
    var result = try Series.init(allocator, "apply_result", result_type, df.row_count);
    errdefer result.deinit(allocator);

    // Apply function to each row
    switch (result_type) {
        .Float64 => {
            const buffer = result.asFloat64Buffer() orelse return error.TypeMismatch;
            try fillFloat64Results(df, FuncType, func, FuncReturnType, buffer);
        },
        .Int64 => {
            const buffer = result.asInt64Buffer() orelse return error.TypeMismatch;
            try fillInt64Results(df, FuncType, func, FuncReturnType, buffer);
        },
        .Bool => {
            const buffer = result.asBoolBuffer() orelse return error.TypeMismatch;
            try fillBoolResults(df, FuncType, func, FuncReturnType, buffer);
        },
        else => {
            return error.UnsupportedResultType;
        },
    }

    result.length = df.row_count;
    return result;
}

/// Fill Float64 result buffer from function application
fn fillFloat64Results(
    df: *const DataFrame,
    comptime FuncType: type,
    comptime func: FuncType,
    comptime FuncReturnType: type,
    buffer: []f64,
) !void {
    std.debug.assert(df.row_count > 0); // DataFrame must have rows
    std.debug.assert(buffer.len >= df.row_count); // Buffer must be large enough

    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < df.row_count) : (row_idx += 1) {
        const row_ref = RowRef{ .dataframe = df, .rowIndex = row_idx };
        const result = func(row_ref);

        // Convert result to f64
        buffer[row_idx] = switch (FuncReturnType) {
            f64, f32 => @as(f64, result),
            i64, i32, i16, i8, u64, u32, u16, u8 => @as(f64, @floatFromInt(result)),
            else => return error.IncompatibleReturnType,
        };
    }

    std.debug.assert(row_idx == df.row_count); // All rows processed
}

/// Fill Int64 result buffer from function application
fn fillInt64Results(
    df: *const DataFrame,
    comptime FuncType: type,
    comptime func: FuncType,
    comptime FuncReturnType: type,
    buffer: []i64,
) !void {
    std.debug.assert(df.row_count > 0); // DataFrame must have rows
    std.debug.assert(buffer.len >= df.row_count); // Buffer must be large enough

    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < df.row_count) : (row_idx += 1) {
        const row_ref = RowRef{ .dataframe = df, .rowIndex = row_idx };
        const result = func(row_ref);

        // Convert result to i64
        buffer[row_idx] = switch (FuncReturnType) {
            i64, i32, i16, i8 => @as(i64, result),
            u64, u32, u16, u8 => @as(i64, @intCast(result)),
            f64, f32 => @as(i64, @intFromFloat(result)),
            else => return error.IncompatibleReturnType,
        };
    }

    std.debug.assert(row_idx == df.row_count); // All rows processed
}

/// Fill Bool result buffer from function application
fn fillBoolResults(
    df: *const DataFrame,
    comptime FuncType: type,
    comptime func: FuncType,
    comptime FuncReturnType: type,
    buffer: []bool,
) !void {
    std.debug.assert(df.row_count > 0); // DataFrame must have rows
    std.debug.assert(buffer.len >= df.row_count); // Buffer must be large enough

    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < df.row_count) : (row_idx += 1) {
        const row_ref = RowRef{ .dataframe = df, .rowIndex = row_idx };
        const result = func(row_ref);

        // Convert result to bool
        buffer[row_idx] = switch (FuncReturnType) {
            bool => result,
            i64, i32, i16, i8, u64, u32, u16, u8 => result != 0,
            f64, f32 => result != 0.0,
            else => return error.IncompatibleReturnType,
        };
    }

    std.debug.assert(row_idx == df.row_count); // All rows processed
}

/// Map a Float64 function element-wise to a Float64 column
///
/// **Usage**: Transform a Float64 column with a simple function
///
/// **Performance**: O(n) where n = column length
/// **Memory**: Allocates new series
///
/// Example:
/// ```zig
/// fn square(x: f64) f64 {
///     return x * x;
/// }
///
/// const squared = try mapFloat64(allocator, price_col, square);
/// defer squared.deinit(allocator);
/// ```
pub fn mapFloat64(
    allocator: std.mem.Allocator,
    series: *const Series,
    func: fn (f64) f64,
) !Series {
    std.debug.assert(series.length > 0); // Series must have data
    std.debug.assert(series.length <= MAX_ROWS); // Within limits
    std.debug.assert(series.value_type == .Float64); // Input type must match

    const input = series.asFloat64() orelse return error.TypeMismatch;
    var result = try Series.init(allocator, "map_result", .Float64, series.length);
    errdefer result.deinit(allocator);

    const buffer = result.asFloat64Buffer() orelse return error.TypeMismatch;

    var i: u32 = 0;
    while (i < MAX_ROWS and i < input.len) : (i += 1) {
        buffer[i] = func(input[i]);
    }

    std.debug.assert(i == input.len); // All elements processed
    result.length = series.length;
    return result;
}

/// Map an Int64 function element-wise to an Int64 column
///
/// **Usage**: Transform an Int64 column with a simple function
///
/// **Performance**: O(n) where n = column length
/// **Memory**: Allocates new series
///
/// Example:
/// ```zig
/// fn double(x: i64) i64 {
///     return x * 2;
/// }
///
/// const doubled = try mapInt64(allocator, count_col, double);
/// defer doubled.deinit(allocator);
/// ```
pub fn mapInt64(
    allocator: std.mem.Allocator,
    series: *const Series,
    func: fn (i64) i64,
) !Series {
    std.debug.assert(series.length > 0); // Series must have data
    std.debug.assert(series.length <= MAX_ROWS); // Within limits
    std.debug.assert(series.value_type == .Int64); // Input type must match

    const input = series.asInt64() orelse return error.TypeMismatch;
    var result = try Series.init(allocator, "map_result", .Int64, series.length);
    errdefer result.deinit(allocator);

    const buffer = result.asInt64Buffer() orelse return error.TypeMismatch;

    var i: u32 = 0;
    while (i < MAX_ROWS and i < input.len) : (i += 1) {
        buffer[i] = func(input[i]);
    }

    std.debug.assert(i == input.len); // All elements processed
    result.length = series.length;
    return result;
}

/// Map a Bool function element-wise to a Bool column
///
/// **Usage**: Transform a Bool column with a simple function
///
/// **Performance**: O(n) where n = column length
/// **Memory**: Allocates new series
///
/// Example:
/// ```zig
/// fn negate(x: bool) bool {
///     return !x;
/// }
///
/// const negated = try mapBool(allocator, active_col, negate);
/// defer negated.deinit(allocator);
/// ```
pub fn mapBool(
    allocator: std.mem.Allocator,
    series: *const Series,
    func: fn (bool) bool,
) !Series {
    std.debug.assert(series.length > 0); // Series must have data
    std.debug.assert(series.length <= MAX_ROWS); // Within limits
    std.debug.assert(series.value_type == .Bool); // Input type must match

    const input = series.asBool() orelse return error.TypeMismatch;
    var result = try Series.init(allocator, "map_result", .Bool, series.length);
    errdefer result.deinit(allocator);

    const buffer = result.asBoolBuffer() orelse return error.TypeMismatch;

    var i: u32 = 0;
    while (i < MAX_ROWS and i < input.len) : (i += 1) {
        buffer[i] = func(input[i]);
    }

    std.debug.assert(i == input.len); // All elements processed
    result.length = series.length;
    return result;
}
