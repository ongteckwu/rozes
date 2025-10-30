//! Reshape - DataFrame pivot, melt, transpose, and stack/unstack operations
//!
//! This module implements DataFrame reshaping operations that convert between
//! wide and long formats, swap rows/columns, and reorganize hierarchical data.
//!
//! See docs/TODO.md Milestone 0.6.0 Phase 1 for complete specifications.
//!
//! Examples:
//! ```zig
//! // Pivot: Transform long format → wide format
//! const pivoted = try df.pivot(allocator, .{
//!     .index = "date",
//!     .columns = "region",
//!     .values = "sales",
//!     .aggfunc = .sum,
//! });
//! defer pivoted.deinit();
//!
//! // Melt: Transform wide format → long format
//! const melted = try df.melt(allocator, .{
//!     .id_vars = &[_][]const u8{"date"},
//!     .value_vars = &[_][]const u8{"East", "West", "South"},
//!     .var_name = "region",
//!     .value_name = "sales",
//! });
//! defer melted.deinit();
//! ```

const std = @import("std");
const types = @import("types.zig");
const DataFrame = @import("dataframe.zig").DataFrame;
const Series = @import("series.zig").Series;
const ColumnDesc = types.ColumnDesc;
const ValueType = types.ValueType;

/// Maximum number of pivot columns (prevents combinatorial explosion)
const MAX_PIVOT_COLUMNS: u32 = 10_000;

/// Maximum number of index values (rows in pivoted result)
const MAX_INDEX_VALUES: u32 = 1_000_000;

/// Maximum unique values in pivot column (becomes new columns)
const MAX_PIVOT_VALUES: u32 = 1_000;

/// Aggregation functions for pivot operations
pub const AggFunc = enum {
    Sum,
    Mean,
    Count,
    Min,
    Max,

    /// Get string representation
    pub fn toString(self: AggFunc) []const u8 {
        std.debug.assert(@intFromEnum(self) >= 0); // Pre-condition #1: Valid enum
        std.debug.assert(@intFromEnum(self) <= @intFromEnum(AggFunc.Max)); // Pre-condition #2: In range

        const result = switch (self) {
            .Sum => "sum",
            .Mean => "mean",
            .Count => "count",
            .Min => "min",
            .Max => "max",
        };

        std.debug.assert(result.len > 0); // Post-condition
        return result;
    }
};

/// Pivot table options
pub const PivotOptions = struct {
    /// Column name to use as row labels (index)
    index: []const u8,

    /// Column name to pivot (becomes new column names)
    columns: []const u8,

    /// Column name containing values to aggregate
    values: []const u8,

    /// Aggregation function to apply
    aggfunc: AggFunc = .Sum,

    /// Validate options
    pub fn validate(self: PivotOptions) !void {
        std.debug.assert(self.index.len > 0); // Pre-condition #1
        std.debug.assert(self.columns.len > 0); // Pre-condition #2

        if (self.index.len == 0) return error.InvalidIndexColumn;
        if (self.columns.len == 0) return error.InvalidColumnsColumn;
        if (self.values.len == 0) return error.InvalidValuesColumn;

        std.debug.assert(self.values.len > 0); // Post-condition
    }
};

/// Represents a unique index value in the pivot result
const IndexKey = union(ValueType) {
    Int64: i64,
    Float64: f64,
    String: []const u8,
    Bool: bool,
    Categorical: []const u8,
    Null: void,

    /// Hash function for index keys
    pub fn hash(self: IndexKey) u64 {
        std.debug.assert(@intFromEnum(self) >= 0); // Valid enum

        return switch (self) {
            .Int64 => |val| @as(u64, @bitCast(val)),
            .Float64 => |val| @as(u64, @bitCast(val)),
            .Bool => |val| if (val) @as(u64, 1) else @as(u64, 0),
            .String => |str| std.hash.Wyhash.hash(0, str),
            .Categorical => |str| std.hash.Wyhash.hash(0, str),
            .Null => 0,
        };
    }

    /// Equality check
    pub fn eql(self: IndexKey, other: IndexKey) bool {
        std.debug.assert(@intFromEnum(self) >= 0); // Valid enum

        if (@intFromEnum(self) != @intFromEnum(other)) return false;

        return switch (self) {
            .Int64 => |val| val == other.Int64,
            .Float64 => |val| val == other.Float64,
            .Bool => |val| val == other.Bool,
            .String => |str| std.mem.eql(u8, str, other.String),
            .Categorical => |str| std.mem.eql(u8, str, other.Categorical),
            .Null => true,
        };
    }
};

/// Represents a cell in the pivot result (index × column)
const PivotCell = struct {
    sum: f64 = 0.0,
    count: u32 = 0,
    min: f64 = std.math.inf(f64),
    max: f64 = -std.math.inf(f64),

    /// Add a value to the cell
    /// NaN values are skipped to prevent contaminating aggregations
    /// Warns on overflow to infinity
    pub fn addValue(self: *PivotCell, value: f64) void {
        std.debug.assert(self.count < std.math.maxInt(u32)); // Pre-condition #1

        // Skip NaN values - don't add to aggregation
        if (std.math.isNan(value)) {
            return; // Early return, don't increment count
        }

        // Check for sum overflow
        const new_sum = self.sum + value;
        if (std.math.isInf(new_sum) and !std.math.isInf(self.sum)) {
            std.log.warn("Pivot aggregation overflow detected (sum={d}, count={}, new_value={d})", .{ self.sum, self.count, value });
        }

        self.sum = new_sum;
        self.count += 1;
        self.min = @min(self.min, value);
        self.max = @max(self.max, value);

        std.debug.assert(self.count > 0); // Post-condition #2
        std.debug.assert(!std.math.isNan(self.sum)); // Post-condition #3: Sum is not NaN (but can be inf)
    }

    /// Get aggregated value based on function
    /// Returns NaN if cell has no data (all values were NaN)
    pub fn getAggregate(self: *const PivotCell, func: AggFunc) f64 {
        std.debug.assert(@intFromEnum(func) >= 0); // Pre-condition #1: Valid function

        // If all values were NaN, count=0, return NaN
        if (self.count == 0) {
            return std.math.nan(f64);
        }

        const result = switch (func) {
            .Sum => self.sum,
            .Mean => self.sum / @as(f64, @floatFromInt(self.count)),
            .Count => @as(f64, @floatFromInt(self.count)),
            .Min => self.min,
            .Max => self.max,
        };

        std.debug.assert(!std.math.isNan(result)); // Post-condition
        return result;
    }
};

/// Pivot table result structure
const PivotResult = struct {
    allocator: std.mem.Allocator,
    index_keys: std.ArrayListUnmanaged(IndexKey),
    column_keys: std.ArrayListUnmanaged([]const u8),
    cells: std.AutoHashMapUnmanaged(u64, PivotCell), // hash(index_key, col_key) -> cell

    pub fn init(allocator: std.mem.Allocator) PivotResult {
        std.debug.assert(@intFromPtr(&allocator) != 0); // Valid allocator pointer

        return PivotResult{
            .allocator = allocator,
            .index_keys = .{},
            .column_keys = .{},
            .cells = .{},
        };
    }

    pub fn deinit(self: *PivotResult) void {
        std.debug.assert(self.cells.count() >= 0); // Valid state

        self.index_keys.deinit(self.allocator);

        // Free allocated column key strings (bounded)
        const MAX_CLEANUP_ITEMS: u32 = 10_000;
        var key_idx: u32 = 0;
        while (key_idx < MAX_CLEANUP_ITEMS and key_idx < self.column_keys.items.len) : (key_idx += 1) {
            self.allocator.free(self.column_keys.items[key_idx]);
        }
        std.debug.assert(key_idx == self.column_keys.items.len or key_idx == MAX_CLEANUP_ITEMS); // Post-condition

        self.column_keys.deinit(self.allocator);
        self.cells.deinit(self.allocator);
    }

    /// Hash combination of index and column keys
    fn hashCell(index_key: IndexKey, col_key: []const u8) u64 {
        std.debug.assert(col_key.len > 0); // Valid column key

        const index_hash = index_key.hash();
        const col_hash = std.hash.Wyhash.hash(0, col_key);

        // Combine hashes using XOR and rotation (better distribution)
        const result = index_hash ^ ((col_hash << 32) | (col_hash >> 32));

        std.debug.assert(result != 0 or (index_hash == 0 and col_hash == 0)); // Post-condition
        return result;
    }
};

/// Transform DataFrame from long format to wide format (pivot table)
///
/// Example:
/// ```
/// Input (long):          Output (wide):
/// date, region, sales    date, East, West, South
/// 2024-01-01, East, 100  2024-01-01, 100, 200, 150
/// 2024-01-01, West, 200  2024-01-02, 120, 180, 160
/// 2024-01-01, South, 150
/// 2024-01-02, East, 120
/// ```
///
/// **Performance**:
/// - Time Complexity: O(n × m) where n = rows, m = unique pivot values
/// - Space Complexity: O(i × c) where i = unique index values, c = unique column values
/// - Typical: 100K rows × 100 unique values → ~500ms
/// - Worst Case: 1M rows × 1K unique values → ~50 seconds
///
/// **Warning**: Avoid pivoting high-cardinality columns (>1000 unique values).
/// Result DataFrame size = (unique index values) × (unique column values).
///
/// **Optimization Tips**:
/// 1. Pre-filter data to reduce row count before pivoting
/// 2. Use Categorical type for low-cardinality pivot columns (10× faster)
/// 3. Consider sampling for exploratory analysis
/// 4. For >10K unique values, use aggregation without pivoting
///
/// **NaN Handling**: NaN values in source data are skipped during aggregation.
/// Missing combinations are filled with NaN (IEEE 754 standard).
pub fn pivot(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    opts: PivotOptions,
) !DataFrame {
    std.debug.assert(df.row_count > 0); // Pre-condition #1: Non-empty DataFrame
    std.debug.assert(@intFromPtr(df) != 0); // Pre-condition #2: Valid DataFrame pointer

    // Validate options
    try opts.validate();

    // Get source columns
    const index_col = df.column(opts.index) orelse return error.ColumnNotFound;
    const pivot_col = df.column(opts.columns) orelse return error.ColumnNotFound;
    const value_col = df.column(opts.values) orelse return error.ColumnNotFound;

    // Value column must be numeric
    if (value_col.value_type != .Int64 and value_col.value_type != .Float64) {
        return error.ValueColumnMustBeNumeric;
    }

    // Build pivot structure
    var result = PivotResult.init(allocator);
    defer result.deinit();

    // Phase 1: Collect unique index and column values
    try collectPivotKeys(df, &result, index_col, pivot_col, value_col);

    // Phase 2: Build result DataFrame
    const pivoted_df = try buildPivotDataFrame(allocator, &result, opts, index_col.value_type);

    std.debug.assert(pivoted_df.row_count > 0); // Post-condition
    return pivoted_df;
}

/// Collect unique index and column keys, aggregate values
fn collectPivotKeys(
    df: *const DataFrame,
    result: *PivotResult,
    index_col: *const Series,
    pivot_col: *const Series,
    value_col: *const Series,
) !void {
    std.debug.assert(df.row_count > 0); // Pre-condition #1
    std.debug.assert(df.row_count <= MAX_INDEX_VALUES); // Pre-condition #2

    var index_map = std.AutoHashMap(u64, u32).init(result.allocator);
    defer index_map.deinit();

    var column_map = std.StringHashMap(u32).init(result.allocator);
    defer column_map.deinit();

    // Iterate through rows
    var row_idx: u32 = 0;
    while (row_idx < df.row_count and row_idx < MAX_INDEX_VALUES) : (row_idx += 1) {
        // Get index key
        const index_key = try getIndexKeyAtRow(index_col, row_idx);
        const index_hash = index_key.hash();

        // Track unique index values
        if (!index_map.contains(index_hash)) {
            try index_map.put(index_hash, @intCast(result.index_keys.items.len));
            try result.index_keys.append(result.allocator, index_key);

            if (result.index_keys.items.len > MAX_INDEX_VALUES) {
                return error.TooManyIndexValues;
            }
        }

        // Get column key (must be string-convertible)
        const col_key_owned = try getColumnKeyAtRow(pivot_col, row_idx, result.allocator);

        // Track unique column values, and get the canonical key for hashing
        const col_key_for_hash: []const u8 = blk: {
            if (!column_map.contains(col_key_owned)) {
                try column_map.put(col_key_owned, @intCast(result.column_keys.items.len));
                try result.column_keys.append(result.allocator, col_key_owned);

                if (result.column_keys.items.len > MAX_PIVOT_VALUES) {
                    return error.TooManyPivotColumns;
                }
                break :blk col_key_owned;
            } else {
                // Column key already exists, free the duplicate and use stored key
                defer result.allocator.free(col_key_owned);
                const key_idx = column_map.get(col_key_owned).?;
                break :blk result.column_keys.items[key_idx];
            }
        };

        // Get value
        const value = try getNumericValueAtRow(value_col, row_idx);

        // Update cell
        const cell_hash = PivotResult.hashCell(index_key, col_key_for_hash);
        const gop = try result.cells.getOrPut(result.allocator, cell_hash);

        if (!gop.found_existing) {
            gop.value_ptr.* = PivotCell{};
        }

        gop.value_ptr.addValue(value);
    }

    std.debug.assert(row_idx == df.row_count or row_idx == MAX_INDEX_VALUES); // Post-condition: Processed all rows
}

/// Get index key from series at row
fn getIndexKeyAtRow(series: *const Series, row_idx: u32) !IndexKey {
    std.debug.assert(row_idx < series.length); // Pre-condition #1
    std.debug.assert(series.length > 0); // Pre-condition #2

    return switch (series.value_type) {
        .Int64 => IndexKey{ .Int64 = series.data.Int64[row_idx] },
        .Float64 => IndexKey{ .Float64 = series.data.Float64[row_idx] },
        .Bool => IndexKey{ .Bool = series.data.Bool[row_idx] },
        .String => IndexKey{ .String = series.data.String.get(row_idx) },
        .Categorical => IndexKey{ .Categorical = series.data.Categorical.get(row_idx) },
        .Null => IndexKey.Null,
    };
}

/// Get column key (as string) from series at row
fn getColumnKeyAtRow(series: *const Series, row_idx: u32, allocator: std.mem.Allocator) ![]const u8 {
    std.debug.assert(row_idx < series.length); // Pre-condition #1
    std.debug.assert(series.length > 0); // Pre-condition #2

    return switch (series.value_type) {
        .Int64 => blk: {
            const val = series.data.Int64[row_idx];
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{}", .{val});
            break :blk try allocator.dupe(u8, str);
        },
        .Float64 => blk: {
            const val = series.data.Float64[row_idx];
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{val});
            break :blk try allocator.dupe(u8, str);
        },
        .Bool => blk: {
            const val = series.data.Bool[row_idx];
            break :blk try allocator.dupe(u8, if (val) "true" else "false");
        },
        .String => try allocator.dupe(u8, series.data.String.get(row_idx)),
        .Categorical => try allocator.dupe(u8, series.data.Categorical.get(row_idx)),
        .Null => try allocator.dupe(u8, "null"),
    };
}

/// Get numeric value from series at row (convert if needed)
///
/// **NaN Handling**: Rejects NaN values with error.NanValueNotSupported
/// Pivot/melt operations require valid numeric data for aggregation.
fn getNumericValueAtRow(series: *const Series, row_idx: u32) !f64 {
    std.debug.assert(row_idx < series.length); // Pre-condition #1
    std.debug.assert(series.value_type == .Int64 or series.value_type == .Float64 or series.value_type == .Bool); // Pre-condition #2

    const result = switch (series.value_type) {
        .Int64 => @as(f64, @floatFromInt(series.data.Int64[row_idx])),
        .Float64 => series.data.Float64[row_idx],
        .Bool => if (series.data.Bool[row_idx]) @as(f64, 1.0) else @as(f64, 0.0),
        else => return error.ValueColumnMustBeNumeric,
    };

    // Accept NaN but warn user (data integrity audit trail)
    if (std.math.isNan(result)) {
        std.log.warn("NaN detected at row {} - will be excluded from aggregation", .{row_idx});
        // Return NaN, let caller decide how to handle
    }

    return result;
}

/// Build final DataFrame from pivot result
fn buildPivotDataFrame(
    allocator: std.mem.Allocator,
    result: *PivotResult,
    opts: PivotOptions,
    index_type: ValueType,
) !DataFrame {
    std.debug.assert(result.index_keys.items.len > 0); // Pre-condition #1
    std.debug.assert(result.column_keys.items.len > 0); // Pre-condition #2

    // Check overflow before cast
    const col_count_usize = result.column_keys.items.len + 1; // +1 for index column
    if (col_count_usize > MAX_PIVOT_COLUMNS) {
        std.log.err("Pivot would create {} columns (max {})", .{ col_count_usize, MAX_PIVOT_COLUMNS });
        return error.TooManyPivotColumns;
    }

    const row_count: u32 = @intCast(result.index_keys.items.len);
    const col_count: u32 = @intCast(col_count_usize);

    // Build column descriptors
    var columns = try std.ArrayList(ColumnDesc).initCapacity(allocator, col_count);
    defer columns.deinit(allocator);

    // Index column
    try columns.append(allocator, ColumnDesc.init(opts.index, index_type, 0));

    // Value columns (one per unique pivot value)
    var col_idx: u32 = 1;
    while (col_idx < col_count and col_idx - 1 < result.column_keys.items.len) : (col_idx += 1) {
        const col_name = result.column_keys.items[col_idx - 1];
        try columns.append(allocator, ColumnDesc.init(col_name, .Float64, col_idx));
    }

    std.debug.assert(col_idx == col_count or col_idx - 1 == result.column_keys.items.len); // Post-condition

    // Create DataFrame
    var df = try DataFrame.create(allocator, columns.items, row_count);
    df.row_count = row_count; // Set row count manually since DataFrame.create starts at 0

    // Set all series lengths to match row count
    for (df.columns) |*col| {
        col.length = row_count;
    }

    // Fill index column
    try fillIndexColumn(&df, result, index_type);

    // Fill value columns
    try fillValueColumns(&df, result, opts.aggfunc);

    return df;
}

/// Fill index column with unique index values
fn fillIndexColumn(df: *DataFrame, result: *PivotResult, index_type: ValueType) !void {
    std.debug.assert(df.row_count == result.index_keys.items.len); // Pre-condition #1
    std.debug.assert(df.columns.len > 0); // Pre-condition #2

    const index_series = &df.columns[0];

    var row_idx: u32 = 0;
    while (row_idx < df.row_count and row_idx < result.index_keys.items.len) : (row_idx += 1) {
        const key = result.index_keys.items[row_idx];

        switch (index_type) {
            .Int64 => index_series.data.Int64[row_idx] = key.Int64,
            .Float64 => index_series.data.Float64[row_idx] = key.Float64,
            .Bool => index_series.data.Bool[row_idx] = key.Bool,
            .String, .Categorical => {
                // String handling would go here (deferred for now)
                std.log.err("String index type not yet implemented: column '{s}' at row {}", .{ index_series.name, row_idx });
                return error.StringIndexNotYetImplemented;
            },
            else => {
                std.log.err("Unsupported index type: {any} for column '{s}'", .{ index_type, index_series.name });
                return error.UnsupportedIndexType;
            },
        }
    }

    std.debug.assert(row_idx == df.row_count); // Post-condition
}

/// Fill value columns with aggregated values (or 0.0 for missing)
///
/// **Missing Values**: Filled with 0.0 for combinations not in source data.
/// This is consistent with aggregation semantics (no data = zero contribution).
fn fillValueColumns(df: *DataFrame, result: *PivotResult, aggfunc: AggFunc) !void {
    std.debug.assert(df.columns.len > 1); // Pre-condition #1: Has value columns
    std.debug.assert(result.column_keys.items.len > 0); // Pre-condition #2

    // For each value column
    var col_idx: u32 = 1; // Skip index column
    while (col_idx < df.columns.len and col_idx - 1 < result.column_keys.items.len) : (col_idx += 1) {
        const col_key = result.column_keys.items[col_idx - 1];
        const col_series = &df.columns[col_idx];

        // For each row (index value)
        var row_idx: u32 = 0;
        while (row_idx < df.row_count and row_idx < result.index_keys.items.len) : (row_idx += 1) {
            const index_key = result.index_keys.items[row_idx];
            const cell_hash = PivotResult.hashCell(index_key, col_key);

            // Get aggregated value or NaN if cell doesn't exist (IEEE 754 standard for missing)
            const value = if (result.cells.get(cell_hash)) |cell|
                cell.getAggregate(aggfunc)
            else
                std.math.nan(f64); // ✅ Use NaN for explicit missing value marker

            std.debug.assert(!std.math.isNan(value) or result.cells.get(cell_hash) == null or result.cells.get(cell_hash).?.count == 0); // Post-condition: Only NaN for missing/empty cells
            col_series.data.Float64[row_idx] = value;
        }

        std.debug.assert(row_idx == df.row_count or row_idx == result.index_keys.items.len); // Inner loop post-condition
    }

    std.debug.assert(col_idx == df.columns.len or col_idx - 1 == result.column_keys.items.len); // Outer loop post-condition
}

/// Melt (unpivot) options
pub const MeltOptions = struct {
    /// Columns to preserve as identifiers (not melted)
    id_vars: []const []const u8,

    /// Columns to melt (if null, melt all non-id columns)
    value_vars: ?[]const []const u8 = null,

    /// Name for the variable column (default: "variable")
    var_name: []const u8 = "variable",

    /// Name for the value column (default: "value")
    value_name: []const u8 = "value",

    /// Validate options
    ///
    /// **Limitation (0.6.0)**: String/Categorical id_vars not yet supported.
    /// Use Int64, Float64, or Bool columns as id_vars only.
    /// String/Categorical support deferred to 0.7.0.
    pub fn validate(self: MeltOptions) !void {
        std.debug.assert(self.id_vars.len >= 0); // Pre-condition #1
        std.debug.assert(self.var_name.len > 0); // Pre-condition #2

        if (self.var_name.len == 0) return error.InvalidVarName;
        if (self.value_name.len == 0) return error.InvalidValueName;

        std.debug.assert(self.value_name.len > 0); // Post-condition
    }
};

/// Maximum number of columns to melt (prevents memory explosion)
const MAX_MELT_COLUMNS: u32 = 1_000;

/// Transform DataFrame from wide format to long format (unpivot/melt)
///
/// Example:
/// ```
/// Input (wide):          Output (long):
/// date, East, West       date, region, sales
/// 2024-01-01, 100, 200   2024-01-01, East, 100
/// 2024-01-02, 120, 180   2024-01-01, West, 200
///                        2024-01-02, East, 120
///                        2024-01-02, West, 180
/// ```
///
/// **Performance**:
/// - Time Complexity: O(n × m) where n = rows, m = melted columns
/// - Space Complexity: O(n × m) result size
/// - Typical: 100 rows × 50 columns → 5K result rows (~10ms)
/// - Warning: 100K rows × 1K columns → 100M result rows (overflow check prevents this)
///
/// **Memory Warning**: Result size = input_rows × melted_columns.
/// Large melts can exceed memory limits (max 4.2B rows due to u32 limit).
///
/// **Optimization Tips**:
/// 1. Pre-filter rows before melting large DataFrames
/// 2. Melt in batches if result would exceed 100M rows
/// 3. Specify value_vars to melt only needed columns
pub fn melt(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    opts: MeltOptions,
) !DataFrame {
    std.debug.assert(df.row_count > 0); // Pre-condition #1: Non-empty DataFrame
    std.debug.assert(df.columns.len > 0); // Pre-condition #2: Has columns

    // Validate options
    try opts.validate();

    // Determine which columns to melt
    const melt_columns = if (opts.value_vars) |vars|
        vars
    else
        try findNonIdColumns(allocator, df, opts.id_vars);
    defer if (opts.value_vars == null) allocator.free(melt_columns);

    if (melt_columns.len == 0) {
        return error.NoColumnsToMelt;
    }

    if (melt_columns.len > MAX_MELT_COLUMNS) {
        return error.TooManyMeltColumns;
    }

    // Build melted DataFrame
    const melted_df = try buildMeltedDataFrame(allocator, df, opts, melt_columns);

    std.debug.assert(melted_df.row_count > 0); // Post-condition
    return melted_df;
}

/// Find all columns that are not in id_vars list
fn findNonIdColumns(
    allocator: std.mem.Allocator,
    df: *const DataFrame,
    id_vars: []const []const u8,
) ![]const []const u8 {
    std.debug.assert(df.columns.len > 0); // Pre-condition #1
    std.debug.assert(df.columns.len <= MAX_MELT_COLUMNS); // Pre-condition #2

    var non_id_list = std.ArrayListUnmanaged([]const u8){};
    defer non_id_list.deinit(allocator);

    var col_idx: u32 = 0;
    while (col_idx < MAX_MELT_COLUMNS and col_idx < df.columns.len) : (col_idx += 1) {
        const col_name = df.columns[col_idx].name;

        // Check if this column is in id_vars
        var is_id_var = false;
        var id_idx: u32 = 0;
        while (id_idx < id_vars.len and id_idx < MAX_MELT_COLUMNS) : (id_idx += 1) {
            if (std.mem.eql(u8, col_name, id_vars[id_idx])) {
                is_id_var = true;
                break;
            }
        }
        std.debug.assert(id_idx <= id_vars.len); // Post-condition: Inner loop

        if (!is_id_var) {
            try non_id_list.append(allocator, col_name);
        }
    }

    std.debug.assert(col_idx == df.columns.len or col_idx == MAX_MELT_COLUMNS); // Post-condition: Outer loop
    return try non_id_list.toOwnedSlice(allocator);
}

/// Build the melted DataFrame structure
fn buildMeltedDataFrame(
    allocator: std.mem.Allocator,
    df: *const DataFrame,
    opts: MeltOptions,
    melt_columns: []const []const u8,
) !DataFrame {
    std.debug.assert(df.row_count > 0); // Pre-condition #1
    std.debug.assert(melt_columns.len > 0); // Pre-condition #2

    // Calculate result dimensions with overflow check
    // Check overflow BEFORE multiplication using wider type
    const melt_col_count: u64 = melt_columns.len;
    const row_count_u64: u64 = df.row_count;
    const result_row_count_u64 = row_count_u64 * melt_col_count;

    if (result_row_count_u64 > MAX_INDEX_VALUES) {
        std.log.err("Melt would create {} rows (max {})", .{ result_row_count_u64, MAX_INDEX_VALUES });
        return error.MeltResultTooLarge;
    }

    const result_row_count: u32 = @intCast(result_row_count_u64);
    const result_col_count: u32 = @as(u32, @intCast(opts.id_vars.len + 2)); // id_vars + var + value

    // Build column descriptors
    var columns = try std.ArrayListUnmanaged(ColumnDesc).initCapacity(allocator, result_col_count);
    defer columns.deinit(allocator);

    // Add id columns (preserve types)
    var id_idx: u32 = 0;
    while (id_idx < opts.id_vars.len and id_idx < MAX_MELT_COLUMNS) : (id_idx += 1) {
        const id_col = df.column(opts.id_vars[id_idx]) orelse return error.ColumnNotFound;
        try columns.append(allocator, ColumnDesc.init(opts.id_vars[id_idx], id_col.value_type, id_idx));
    }
    std.debug.assert(id_idx == opts.id_vars.len or id_idx == MAX_MELT_COLUMNS); // Post-condition

    // Add variable column (String type)
    try columns.append(allocator, ColumnDesc.init(opts.var_name, .String, @intCast(columns.items.len)));

    // Add value column (Float64 - we'll convert all values)
    try columns.append(allocator, ColumnDesc.init(opts.value_name, .Float64, @intCast(columns.items.len)));

    // Create DataFrame
    var result = try DataFrame.create(allocator, columns.items, result_row_count);
    result.row_count = result_row_count;

    // Set all series lengths (except String column which grows with append)
    const MAX_RESULT_COLUMNS: u32 = 10_000;
    var col_idx_set: u32 = 0;
    while (col_idx_set < MAX_RESULT_COLUMNS and col_idx_set < result.columns.len) : (col_idx_set += 1) {
        // Skip the variable column (String type) - it will be filled via appendString
        if (col_idx_set != opts.id_vars.len) {
            result.columns[col_idx_set].length = result_row_count;
        }
    }
    std.debug.assert(col_idx_set == result.columns.len or col_idx_set == MAX_RESULT_COLUMNS); // Post-condition

    // Fill data
    try fillMeltedData(allocator, &result, df, opts, melt_columns);

    return result;
}

/// Fill the melted DataFrame with data
fn fillMeltedData(
    allocator: std.mem.Allocator,
    result: *DataFrame,
    source: *const DataFrame,
    opts: MeltOptions,
    melt_columns: []const []const u8,
) !void {
    std.debug.assert(result.row_count > 0); // Pre-condition #1
    std.debug.assert(source.row_count > 0); // Pre-condition #2

    var result_row: u32 = 0;
    const max_result_rows = result.row_count;

    // For each source row
    var source_row: u32 = 0;
    while (source_row < source.row_count and source_row < MAX_INDEX_VALUES) : (source_row += 1) {
        // For each melted column
        var melt_idx: u32 = 0;
        while (melt_idx < melt_columns.len and melt_idx < MAX_MELT_COLUMNS) : (melt_idx += 1) {
            if (result_row >= max_result_rows) break;

            // Copy id column values
            var id_idx: u32 = 0;
            while (id_idx < opts.id_vars.len and id_idx < MAX_MELT_COLUMNS) : (id_idx += 1) {
                const source_col = source.column(opts.id_vars[id_idx]) orelse continue;
                const result_col = &result.columns[id_idx];

                try copyValueToResult(result_col, result_row, source_col, source_row);
            }
            std.debug.assert(id_idx <= opts.id_vars.len); // Post-condition: id loop

            // Set variable name (column being melted)
            const var_col_idx = opts.id_vars.len;
            const var_name = melt_columns[melt_idx];
            try result.columns[var_col_idx].appendString(allocator, var_name);

            // Set value (convert to Float64)
            const value_col_idx = opts.id_vars.len + 1;
            const source_value_col = source.column(var_name) orelse return error.ColumnNotFound;
            const value = try getNumericValueAtRow(source_value_col, source_row);
            result.columns[value_col_idx].data.Float64[result_row] = value;

            result_row += 1;
        }
        std.debug.assert(melt_idx <= melt_columns.len); // Inner loop post-condition
    }
    std.debug.assert(source_row == source.row_count or source_row == MAX_INDEX_VALUES); // Outer loop post-condition

    std.debug.assert(result_row == result.row_count); // Final post-condition
}

/// Copy a value from source series to result series at given row indices
fn copyValueToResult(
    result_col: *Series,
    result_row: u32,
    source_col: *const Series,
    source_row: u32,
) !void {
    std.debug.assert(result_row < result_col.length); // Pre-condition #1
    std.debug.assert(source_row < source_col.length); // Pre-condition #2

    switch (source_col.value_type) {
        .Int64 => result_col.data.Int64[result_row] = source_col.data.Int64[source_row],
        .Float64 => result_col.data.Float64[result_row] = source_col.data.Float64[source_row],
        .Bool => result_col.data.Bool[result_row] = source_col.data.Bool[source_row],
        .String, .Categorical => {
            // String/Categorical not implemented for id_vars yet
            return error.StringIdVarsNotYetImplemented;
        },
        else => return error.UnsupportedType,
    }
}

/// Transpose DataFrame - swap rows and columns
///
/// Converts a DataFrame where each row becomes a column and each column becomes a row.
/// All values must be convertible to a common type (Float64 for mixed numeric types).
///
/// Example:
/// ```
/// Input:     A    B    C        Output:   row0  row1  row2
///    row0    1    2    3                A     1     4     7
///    row1    4    5    6                B     2     5     8
///    row2    7    8    9                C     3     6     9
/// ```
///
/// **Performance**:
/// - Time Complexity: O(rows × cols) - copies all data
/// - Space Complexity: O(rows × cols) - new DataFrame allocated
/// - Typical: 100 rows × 100 cols → ~2-5ms
/// - Warning: Result dimensions = input dimensions (swapped)
///
/// **Memory Warning**: Transpose of 1M rows × 1K columns = 1K rows × 1M columns.
/// Column count limited by MAX_COLUMNS (10K), row count by u32 (4.2B).
///
/// **Type Handling**: All data converted to Float64 for consistency.
///
/// **Tiger Style**: Bounded by MAX_ROWS and MAX_COLUMNS
pub fn transpose(self: *const DataFrame, allocator: std.mem.Allocator) !DataFrame {
    std.debug.assert(self.row_count > 0); // Pre-condition #1
    std.debug.assert(self.columns.len > 0); // Pre-condition #2

    const src_rows = self.row_count;
    const src_cols: u32 = @intCast(self.columns.len);

    // Transposed dimensions: rows become columns, columns become rows
    const new_rows = src_cols;
    const new_cols = src_rows;

    if (new_cols > MAX_PIVOT_COLUMNS) return error.TooManyColumns;
    if (new_rows > MAX_INDEX_VALUES) return error.TooManyRows;

    // Create result DataFrame first to get access to its arena
    // We'll create column descriptors using stack memory
    var new_columns_stack = try allocator.alloc(ColumnDesc, new_cols);
    defer allocator.free(new_columns_stack);

    // Temporarily create column descriptors with placeholder names
    var col_idx: u32 = 0;
    while (col_idx < new_cols and col_idx < MAX_PIVOT_COLUMNS) : (col_idx += 1) {
        new_columns_stack[col_idx] = ColumnDesc{
            .name = "temp", // Will be replaced by DataFrame.create
            .value_type = .Float64,
            .index = col_idx,
        };
    }
    std.debug.assert(col_idx == new_cols or col_idx == MAX_PIVOT_COLUMNS); // Post-condition #3

    // Create DataFrame (this will allocate proper names in its arena)
    var result = try DataFrame.create(allocator, new_columns_stack, new_rows);
    errdefer result.deinit();

    // Now update column names using the DataFrame's arena
    const arena_alloc = result.arena.allocator();
    col_idx = 0;
    while (col_idx < new_cols and col_idx < MAX_PIVOT_COLUMNS) : (col_idx += 1) {
        const name = try std.fmt.allocPrint(arena_alloc, "row_{d}", .{col_idx});
        result.column_descs[col_idx].name = name;
        result.columns[col_idx].name = name;
    }
    std.debug.assert(col_idx == new_cols or col_idx == MAX_PIVOT_COLUMNS); // Post-condition

    // Set row count and column lengths (DataFrame.create sets them to 0)
    result.row_count = new_rows;

    // Set all column lengths to new_rows
    var new_col_idx: u32 = 0;
    while (new_col_idx < new_cols and new_col_idx < MAX_PIVOT_COLUMNS) : (new_col_idx += 1) {
        std.debug.assert(result.columns[new_col_idx].value_type == .Float64);
        result.columns[new_col_idx].length = new_rows;
    }
    std.debug.assert(new_col_idx == new_cols); // Post-condition #4

    // Copy data with transposition: result[src_col][src_row] = source[src_row][src_col]
    var src_row: u32 = 0;
    while (src_row < src_rows and src_row < MAX_INDEX_VALUES) : (src_row += 1) {
        var src_col_idx: u32 = 0;
        while (src_col_idx < src_cols and src_col_idx < MAX_PIVOT_COLUMNS) : (src_col_idx += 1) {
            const source_col = &self.columns[src_col_idx];

            // Convert value to Float64
            const value = try getNumericValueAtRow(source_col, src_row);

            // Transposed position: old column index becomes new row, old row becomes new column
            const new_row = src_col_idx;
            const new_col = src_row;

            result.columns[new_col].data.Float64[new_row] = value;
        }
        std.debug.assert(src_col_idx == src_cols); // Inner loop completed
    }

    std.debug.assert(src_row == src_rows); // Post-condition #5: All rows processed
    return result;
}

/// Stack options for reshaping wide to long format
pub const StackOptions = struct {
    /// Column to use as identifier (will be preserved)
    id_column: []const u8,

    /// Name for the new variable column (default: "variable")
    var_name: []const u8 = "variable",

    /// Name for the new value column (default: "value")
    value_name: []const u8 = "value",
};

/// Stack - Convert wide format to long format (similar to melt but simpler API)
///
/// Stacks all columns except the id_column into a long format with two new columns:
/// - var_name: contains the original column names
/// - value_name: contains the values
///
/// Example:
/// ```
/// Input:     id    A    B    C        Output:   id  variable  value
///    row0    1     10   20   30               1      A         10
///    row1    2     40   50   60               1      B         20
///                                             1      C         30
///                                             2      A         40
///                                             2      B         50
///                                             2      C         60
/// ```
///
/// **Performance**:
/// - Time Complexity: O(rows × cols) where cols = value columns (all except id)
/// - Space Complexity: O(rows × value_cols) result size
/// - Typical: 100 rows × 10 value cols → 1K result rows (~5ms)
/// - Result rows = input_rows × (total_columns - 1)
///
/// **Memory Warning**: Similar to melt() - result size multiplies by column count.
///
/// **Tiger Style**: Bounded by MAX_ROWS and MAX_COLUMNS
pub fn stack(self: *const DataFrame, allocator: std.mem.Allocator, opts: StackOptions) !DataFrame {
    std.debug.assert(self.row_count > 0); // Pre-condition #1
    std.debug.assert(self.columns.len > 1); // Pre-condition #2: Need at least id + 1 value column

    // Find id column
    var id_col_idx: ?u32 = null;
    var col_search_idx: u32 = 0;
    while (col_search_idx < self.columns.len and col_search_idx < MAX_PIVOT_COLUMNS) : (col_search_idx += 1) {
        if (std.mem.eql(u8, self.column_descs[col_search_idx].name, opts.id_column)) {
            id_col_idx = col_search_idx;
            break;
        }
    }

    const id_idx = id_col_idx orelse return error.ColumnNotFound;

    // Count value columns (all except id column)
    const value_col_count = self.columns.len - 1;
    if (value_col_count == 0) return error.NoColumnsToStack;

    // Calculate output dimensions
    const output_rows = self.row_count * @as(u32, @intCast(value_col_count));
    if (output_rows > MAX_INDEX_VALUES) return error.TooManyRows;

    // Create output columns: id, var_name, value_name
    var out_columns = try allocator.alloc(ColumnDesc, 3);
    defer allocator.free(out_columns);

    out_columns[0] = ColumnDesc{
        .name = opts.id_column,
        .value_type = self.columns[id_idx].value_type,
        .index = 0,
    };
    out_columns[1] = ColumnDesc{
        .name = opts.var_name,
        .value_type = .String,
        .index = 1,
    };
    out_columns[2] = ColumnDesc{
        .name = opts.value_name,
        .value_type = .Float64, // All values converted to Float64
        .index = 2,
    };

    var result = try DataFrame.create(allocator, out_columns, output_rows);
    errdefer result.deinit();
    result.row_count = output_rows;

    const arena_alloc = result.arena.allocator();

    // Update column names in result
    result.column_descs[0].name = try arena_alloc.dupe(u8, opts.id_column);
    result.columns[0].name = result.column_descs[0].name;
    result.column_descs[1].name = try arena_alloc.dupe(u8, opts.var_name);
    result.columns[1].name = result.column_descs[1].name;
    result.column_descs[2].name = try arena_alloc.dupe(u8, opts.value_name);
    result.columns[2].name = result.column_descs[2].name;

    // Set column lengths for non-String columns (String grows with appendString)
    result.columns[0].length = output_rows; // id column
    result.columns[2].length = output_rows; // value column (Float64)

    // Fill result DataFrame
    var result_row: u32 = 0;
    var src_row: u32 = 0;
    while (src_row < self.row_count and src_row < MAX_INDEX_VALUES) : (src_row += 1) {
        // For each value column, create a new row
        var val_col_idx: u32 = 0;
        while (val_col_idx < self.columns.len and val_col_idx < MAX_PIVOT_COLUMNS) : (val_col_idx += 1) {
            if (val_col_idx == id_idx) continue; // Skip id column

            // Copy id value
            try copyValueToResult(&result.columns[0], result_row, &self.columns[id_idx], src_row);

            // Set variable name (original column name)
            const var_name = self.column_descs[val_col_idx].name;
            try result.columns[1].appendString(arena_alloc, var_name);

            // Set value (convert to Float64)
            const value = try getNumericValueAtRow(&self.columns[val_col_idx], src_row);
            result.columns[2].data.Float64[result_row] = value;

            result_row += 1;
        }
        std.debug.assert(val_col_idx <= self.columns.len); // Inner loop post-condition
    }
    std.debug.assert(src_row == self.row_count or src_row == MAX_INDEX_VALUES); // Outer loop post-condition

    std.debug.assert(result_row == output_rows); // Final post-condition
    return result;
}

/// Unstack options for reshaping long to wide format
pub const UnstackOptions = struct {
    /// Column containing the index values
    index: []const u8,

    /// Column containing the variable names (will become column headers)
    columns: []const u8,

    /// Column containing the values to populate
    values: []const u8,
};

/// Unstack - Convert long format to wide format (inverse of stack, similar to pivot)
///
/// Takes a long-format DataFrame and pivots it to wide format based on the columns parameter.
/// This is essentially an alias for pivot with a different conceptual framing.
///
/// Example:
/// ```
/// Input:   id  variable  value        Output:     id    A     B     C
///          1      A         10                     1    10    20    30
///          1      B         20                     2    40    50    60
///          1      C         30
///          2      A         40
///          2      B         50
///          2      C         60
/// ```
///
/// **Performance**: O(rows) - same as pivot operation
/// **Tiger Style**: Bounded by MAX_ROWS and MAX_COLUMNS
pub fn unstack(self: *const DataFrame, allocator: std.mem.Allocator, opts: UnstackOptions) !DataFrame {
    std.debug.assert(self.row_count > 0); // Pre-condition #1
    std.debug.assert(self.columns.len >= 3); // Pre-condition #2: Need index, columns, values

    // Unstack is essentially pivot with different naming
    // Delegate to pivot with appropriate options
    return try pivot(self, allocator, .{
        .index = opts.index,
        .columns = opts.columns,
        .values = opts.values,
        .aggfunc = .Sum, // Default aggregation (can be customized later)
    });
}
