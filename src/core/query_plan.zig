// Query Plan - Lazy evaluation and optimization for DataFrame operations
// Tiger Style: 2+ assertions, ≤70 lines per function, bounded loops

const std = @import("std");
const DataFrame = @import("dataframe.zig").DataFrame;
const Allocator = std.mem.Allocator;

/// Maximum query plan depth (prevent unbounded recursion)
const MAX_PLAN_DEPTH: u32 = 64;

/// Maximum number of operations in a query plan
const MAX_OPERATIONS: u32 = 1000;

/// Operation types in query plan DAG
pub const OperationType = enum {
    Filter, // Row filtering with predicate
    Select, // Column selection (projection)
    GroupBy, // Group by columns with aggregation
    Join, // Join with another DataFrame
    Sort, // Sort by columns
    Limit, // Limit number of rows
    Map, // Element-wise transformation
};

/// Filter predicate function signature
pub const FilterFn = *const fn (row_idx: u32, df: *const DataFrame) bool;

/// Map function signature
pub const MapFn = *const fn (value: f64) f64;

/// Query operation node
pub const Operation = struct {
    op_type: OperationType,

    // Filter operation
    filter_fn: ?FilterFn = null,

    // Select operation
    column_names: ?[]const []const u8 = null,

    // GroupBy operation
    group_columns: ?[]const []const u8 = null,
    agg_column: ?[]const u8 = null,

    // Sort operation
    sort_columns: ?[]const []const u8 = null,
    sort_ascending: bool = true,

    // Limit operation
    limit_count: ?u32 = null,

    // Map operation
    map_fn: ?MapFn = null,
    map_column: ?[]const u8 = null,
};

/// Query plan - DAG of operations
pub const QueryPlan = struct {
    allocator: Allocator,
    operations: std.ArrayList(Operation),
    source_df: ?*const DataFrame,

    pub fn init(allocator: Allocator) QueryPlan {
        return .{
            .allocator = allocator,
            .operations = std.ArrayList(Operation).init(allocator),
            .source_df = null,
        };
    }

    pub fn deinit(self: *QueryPlan) void {
        self.operations.deinit();
    }

    /// Add filter operation to plan
    pub fn addFilter(self: *QueryPlan, filter_fn: FilterFn) !void {
        std.debug.assert(self.operations.items.len < MAX_OPERATIONS);

        const op = Operation{
            .op_type = .Filter,
            .filter_fn = filter_fn,
        };
        try self.operations.append(op);
    }

    /// Add select (projection) operation to plan
    pub fn addSelect(self: *QueryPlan, columns: []const []const u8) !void {
        std.debug.assert(self.operations.items.len < MAX_OPERATIONS);
        std.debug.assert(columns.len > 0);

        const op = Operation{
            .op_type = .Select,
            .column_names = columns,
        };
        try self.operations.append(op);
    }

    /// Add limit operation to plan
    pub fn addLimit(self: *QueryPlan, count: u32) !void {
        std.debug.assert(self.operations.items.len < MAX_OPERATIONS);
        std.debug.assert(count > 0);

        const op = Operation{
            .op_type = .Limit,
            .limit_count = count,
        };
        try self.operations.append(op);
    }

    /// Get operation count
    pub fn operationCount(self: *const QueryPlan) u32 {
        return @intCast(self.operations.items.len);
    }
};

/// Query optimizer - applies optimization rules
pub const QueryOptimizer = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) QueryOptimizer {
        return .{ .allocator = allocator };
    }

    /// Optimize query plan (apply transformation rules)
    pub fn optimize(self: *QueryOptimizer, plan: *QueryPlan) !void {
        std.debug.assert(plan.operations.items.len <= MAX_OPERATIONS);

        // Apply optimization passes
        try self.fuseFilters(plan);
        try self.pushDownPredicates(plan);
        try self.pushDownProjections(plan);
    }

    /// Fuse consecutive filter operations into single pass
    fn fuseFilters(self: *QueryOptimizer, plan: *QueryPlan) !void {
        _ = self;
        std.debug.assert(plan.operations.items.len <= MAX_OPERATIONS);

        // Scan for consecutive filters and mark for fusion
        var i: u32 = 0;
        while (i + 1 < plan.operations.items.len and i < MAX_OPERATIONS) : (i += 1) {
            const op1 = plan.operations.items[i];
            const op2 = plan.operations.items[i + 1];

            // If both are filters, we could fuse them
            // For MVP, we skip fusion (complex predicate composition)
            // Defer to future: combine filter_fn1 AND filter_fn2
            if (op1.op_type == .Filter and op2.op_type == .Filter) {
                // TODO: Implement filter fusion in future version
                continue;
            }
        }
        std.debug.assert(i <= MAX_OPERATIONS);
    }

    /// Push predicates (filters) earlier in plan
    fn pushDownPredicates(self: *QueryOptimizer, plan: *QueryPlan) !void {
        _ = self;
        std.debug.assert(plan.operations.items.len <= MAX_OPERATIONS);

        // Move filters before selects (reduce data volume early)
        var i: u32 = 0;
        while (i + 1 < plan.operations.items.len and i < MAX_OPERATIONS) : (i += 1) {
            const current = plan.operations.items[i];
            const next = plan.operations.items[i + 1];

            // If select followed by filter, swap them
            if (current.op_type == .Select and next.op_type == .Filter) {
                // Swap operations
                plan.operations.items[i] = next;
                plan.operations.items[i + 1] = current;
            }
        }
        std.debug.assert(i <= MAX_OPERATIONS);
    }

    /// Push projections (selects) earlier in plan
    fn pushDownProjections(self: *QueryOptimizer, plan: *QueryPlan) !void {
        _ = self;
        std.debug.assert(plan.operations.items.len <= MAX_OPERATIONS);

        // Move selects before expensive operations (reduce column count)
        var i: u32 = 0;
        while (i + 1 < plan.operations.items.len and i < MAX_OPERATIONS) : (i += 1) {
            const current = plan.operations.items[i];
            const next = plan.operations.items[i + 1];

            // If groupBy/join followed by select, swap if possible
            if ((current.op_type == .GroupBy or current.op_type == .Join) and
                next.op_type == .Select)
            {
                // Only swap if select doesn't depend on groupBy result
                // For MVP, skip this optimization (complex dependency analysis)
                continue;
            }
        }
        std.debug.assert(i <= MAX_OPERATIONS);
    }
};

/// Lazy DataFrame - defers execution until collect()
pub const LazyDataFrame = struct {
    allocator: Allocator,
    plan: QueryPlan,
    source_df: *const DataFrame,

    pub fn init(allocator: Allocator, source: *const DataFrame) LazyDataFrame {
        var plan = QueryPlan.init(allocator);
        plan.source_df = source;

        return .{
            .allocator = allocator,
            .plan = plan,
            .source_df = source,
        };
    }

    pub fn deinit(self: *LazyDataFrame) void {
        self.plan.deinit();
    }

    /// Add filter operation (lazy)
    pub fn filter(self: *LazyDataFrame, filter_fn: FilterFn) !void {
        try self.plan.addFilter(filter_fn);
    }

    /// Add select operation (lazy)
    pub fn select(self: *LazyDataFrame, columns: []const []const u8) !void {
        try self.plan.addSelect(columns);
    }

    /// Add limit operation (lazy)
    pub fn limit(self: *LazyDataFrame, count: u32) !void {
        try self.plan.addLimit(count);
    }

    /// Execute plan and return result DataFrame
    pub fn collect(self: *LazyDataFrame) !DataFrame {
        std.debug.assert(self.plan.operations.items.len > 0);
        std.debug.assert(self.plan.operations.items.len <= MAX_OPERATIONS);

        // Optimize plan before execution
        var optimizer = QueryOptimizer.init(self.allocator);
        try optimizer.optimize(&self.plan);

        // Execute operations in order
        var current_df = self.source_df.*;

        for (self.plan.operations.items) |op| {
            switch (op.op_type) {
                .Filter => {
                    if (op.filter_fn) |filter_fn| {
                        current_df = try executeFilter(&current_df, filter_fn);
                    }
                },
                .Select => {
                    if (op.column_names) |cols| {
                        current_df = try executeSelect(&current_df, cols);
                    }
                },
                .Limit => {
                    if (op.limit_count) |count| {
                        current_df = try executeLimit(&current_df, count);
                    }
                },
                else => return error.UnsupportedOperation,
            }
        }

        return current_df;
    }
};

// Execution functions - delegate to operations module
fn executeFilter(df: *const DataFrame, filter_fn: FilterFn) !DataFrame {
    std.debug.assert(df.row_count > 0);
    std.debug.assert(df.columns.len > 0);

    const ops = @import("operations.zig");
    return ops.filter(df, filter_fn);
}

fn executeSelect(df: *const DataFrame, columns: []const []const u8) !DataFrame {
    std.debug.assert(df.columns.len > 0);
    std.debug.assert(columns.len > 0);

    const ops = @import("operations.zig");
    return ops.select(df, columns);
}

fn executeLimit(df: *const DataFrame, count: u32) !DataFrame {
    std.debug.assert(df.row_count > 0);
    std.debug.assert(count > 0);

    // Create new DataFrame with limited rows
    var result = try DataFrame.create(
        df.arena.child_allocator,
        df.column_descs,
        @min(count, df.row_count),
    );

    // Copy data for limited rows
    const limit_rows = @min(count, df.row_count);
    var col_idx: u32 = 0;
    while (col_idx < result.columns.len and col_idx < MAX_OPERATIONS) : (col_idx += 1) {
        const src_series = &df.columns[col_idx];
        const dst_series = &result.columns[col_idx];

        switch (src_series.value_type) {
            .Int64 => {
                const src_data = src_series.data.Int64;
                const dst_data = dst_series.data.Int64;
                @memcpy(dst_data[0..limit_rows], src_data[0..limit_rows]);
            },
            .Float64 => {
                const src_data = src_series.data.Float64;
                const dst_data = dst_series.data.Float64;
                @memcpy(dst_data[0..limit_rows], src_data[0..limit_rows]);
            },
            .Bool => {
                const src_data = src_series.data.Bool;
                const dst_data = dst_series.data.Bool;
                @memcpy(dst_data[0..limit_rows], src_data[0..limit_rows]);
            },
            else => return error.UnsupportedType,
        }
    }
    std.debug.assert(col_idx == result.columns.len);

    result.row_count = limit_rows;
    return result;
}
