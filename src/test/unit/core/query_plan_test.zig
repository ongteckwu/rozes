// Unit tests for query plan and lazy evaluation
const std = @import("std");
const testing = std.testing;
const QueryPlan = @import("../../../core/query_plan.zig").QueryPlan;
const QueryOptimizer = @import("../../../core/query_plan.zig").QueryOptimizer;
const LazyDataFrame = @import("../../../core/query_plan.zig").LazyDataFrame;
const Operation = @import("../../../core/query_plan.zig").Operation;
const OperationType = @import("../../../core/query_plan.zig").OperationType;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const ColumnDesc = @import("../../../core/types.zig").ColumnDesc;
const ValueType = @import("../../../core/types.zig").ValueType;

// Helper: Create test DataFrame
fn createTestDataFrame(allocator: std.mem.Allocator) !DataFrame {
    const col_descs = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
        ColumnDesc.init("score", .Float64, 0),
        ColumnDesc.init("active", .Bool, 0),
    };

    var df = try DataFrame.create(allocator, &col_descs, 10);

    // Fill with test data
    const age_data = df.columns[0].data.Int64;
    const score_data = df.columns[1].data.Float64;
    const active_data = df.columns[2].data.Bool;

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        age_data[i] = @as(i64, @intCast(20 + i * 5));
        score_data[i] = @as(f64, @floatFromInt(50 + i * 10));
        active_data[i] = (i % 2 == 0);
    }

    df.row_count = 10;
    return df;
}

// Test filter predicate: age > 30
fn filterAgeOver30(row_idx: u32, df: *const DataFrame) bool {
    std.debug.assert(row_idx < df.row_count);
    std.debug.assert(df.columns.len > 0);

    const age_col = &df.columns[0];
    const age = age_col.data.Int64[row_idx];
    return age > 30;
}

test "QueryPlan.init creates empty plan" {
    const allocator = testing.allocator;

    var plan = QueryPlan.init(allocator);
    defer plan.deinit();

    try testing.expectEqual(@as(u32, 0), plan.operationCount());
}

test "QueryPlan.addFilter adds filter operation" {
    const allocator = testing.allocator;

    var plan = QueryPlan.init(allocator);
    defer plan.deinit();

    try plan.addFilter(filterAgeOver30);

    try testing.expectEqual(@as(u32, 1), plan.operationCount());
    try testing.expectEqual(OperationType.Filter, plan.operations.items[0].op_type);
}

test "QueryPlan.addSelect adds select operation" {
    const allocator = testing.allocator;

    var plan = QueryPlan.init(allocator);
    defer plan.deinit();

    const columns = [_][]const u8{ "age", "score" };
    try plan.addSelect(&columns);

    try testing.expectEqual(@as(u32, 1), plan.operationCount());
    try testing.expectEqual(OperationType.Select, plan.operations.items[0].op_type);
}

test "QueryPlan.addLimit adds limit operation" {
    const allocator = testing.allocator;

    var plan = QueryPlan.init(allocator);
    defer plan.deinit();

    try plan.addLimit(5);

    try testing.expectEqual(@as(u32, 1), plan.operationCount());
    try testing.expectEqual(OperationType.Limit, plan.operations.items[0].op_type);
    try testing.expectEqual(@as(u32, 5), plan.operations.items[0].limit_count.?);
}

test "QueryOptimizer.pushDownPredicates moves filter before select" {
    const allocator = testing.allocator;

    var plan = QueryPlan.init(allocator);
    defer plan.deinit();

    // Add select then filter (suboptimal order)
    const columns = [_][]const u8{ "age", "score" };
    try plan.addSelect(&columns);
    try plan.addFilter(filterAgeOver30);

    // Verify initial order
    try testing.expectEqual(OperationType.Select, plan.operations.items[0].op_type);
    try testing.expectEqual(OperationType.Filter, plan.operations.items[1].op_type);

    // Optimize
    var optimizer = QueryOptimizer.init(allocator);
    try optimizer.optimize(&plan);

    // Verify optimized order (filter pushed before select)
    try testing.expectEqual(OperationType.Filter, plan.operations.items[0].op_type);
    try testing.expectEqual(OperationType.Select, plan.operations.items[1].op_type);
}

test "LazyDataFrame.init creates lazy DataFrame wrapper" {
    const allocator = testing.allocator;

    var df = try createTestDataFrame(allocator);
    defer df.deinit();

    var lazy = LazyDataFrame.init(allocator, &df);
    defer lazy.deinit();

    try testing.expectEqual(@as(u32, 0), lazy.plan.operationCount());
}

test "LazyDataFrame.filter adds operation without executing" {
    const allocator = testing.allocator;

    var df = try createTestDataFrame(allocator);
    defer df.deinit();

    var lazy = LazyDataFrame.init(allocator, &df);
    defer lazy.deinit();

    // Add filter (lazy - doesn't execute yet)
    try lazy.filter(filterAgeOver30);

    // Verify operation added but not executed
    try testing.expectEqual(@as(u32, 1), lazy.plan.operationCount());
    try testing.expectEqual(@as(u32, 10), df.row_count); // Source unchanged
}

test "LazyDataFrame.select adds operation without executing" {
    const allocator = testing.allocator;

    var df = try createTestDataFrame(allocator);
    defer df.deinit();

    var lazy = LazyDataFrame.init(allocator, &df);
    defer lazy.deinit();

    const columns = [_][]const u8{ "age", "score" };
    try lazy.select(&columns);

    try testing.expectEqual(@as(u32, 1), lazy.plan.operationCount());
    try testing.expectEqual(@as(usize, 3), df.columns.len); // Source unchanged
}

test "LazyDataFrame.limit adds operation without executing" {
    const allocator = testing.allocator;

    var df = try createTestDataFrame(allocator);
    defer df.deinit();

    var lazy = LazyDataFrame.init(allocator, &df);
    defer lazy.deinit();

    try lazy.limit(5);

    try testing.expectEqual(@as(u32, 1), lazy.plan.operationCount());
    try testing.expectEqual(@as(u32, 10), df.row_count); // Source unchanged
}

test "LazyDataFrame.collect executes filter operation" {
    const allocator = testing.allocator;

    var df = try createTestDataFrame(allocator);
    defer df.deinit();

    var lazy = LazyDataFrame.init(allocator, &df);
    defer lazy.deinit();

    try lazy.filter(filterAgeOver30);

    // Execute plan
    var result = try lazy.collect();
    defer result.deinit();

    // Verify filtered rows (age > 30: ages are 20,25,30,35,40,45,50,55,60,65)
    // Expected: 35,40,45,50,55,60,65 (7 rows)
    try testing.expectEqual(@as(u32, 7), result.row_count);
}

test "LazyDataFrame.collect executes select operation" {
    const allocator = testing.allocator;

    var df = try createTestDataFrame(allocator);
    defer df.deinit();

    var lazy = LazyDataFrame.init(allocator, &df);
    defer lazy.deinit();

    const columns = [_][]const u8{ "age", "score" };
    try lazy.select(&columns);

    var result = try lazy.collect();
    defer result.deinit();

    // Verify selected columns (2 out of 3)
    try testing.expectEqual(@as(usize, 2), result.columns.len);
    try testing.expectEqual(@as(u32, 10), result.row_count);
}

test "LazyDataFrame.collect executes limit operation" {
    const allocator = testing.allocator;

    var df = try createTestDataFrame(allocator);
    defer df.deinit();

    var lazy = LazyDataFrame.init(allocator, &df);
    defer lazy.deinit();

    try lazy.limit(5);

    var result = try lazy.collect();
    defer result.deinit();

    // Verify limited rows
    try testing.expectEqual(@as(u32, 5), result.row_count);
    try testing.expectEqual(@as(usize, 3), result.columns.len);
}

test "LazyDataFrame.collect executes chained operations with optimization" {
    const allocator = testing.allocator;

    var df = try createTestDataFrame(allocator);
    defer df.deinit();

    var lazy = LazyDataFrame.init(allocator, &df);
    defer lazy.deinit();

    // Add operations in suboptimal order
    const columns = [_][]const u8{ "age", "score" };
    try lazy.select(&columns); // Select first (suboptimal)
    try lazy.filter(filterAgeOver30); // Then filter
    try lazy.limit(3); // Then limit

    // Execute with optimization
    var result = try lazy.collect();
    defer result.deinit();

    // Verify result: optimized plan should execute filter → select → limit
    // Expected: 3 rows with age > 30, only age and score columns
    try testing.expectEqual(@as(u32, 3), result.row_count);
    try testing.expectEqual(@as(usize, 2), result.columns.len);

    // Verify column names
    const col_names = [_][]const u8{ "age", "score" };
    for (result.column_descs, 0..) |desc, i| {
        try testing.expectEqualStrings(col_names[i], desc.name);
    }
}

test "QueryOptimizer handles empty plan" {
    const allocator = testing.allocator;

    var plan = QueryPlan.init(allocator);
    defer plan.deinit();

    var optimizer = QueryOptimizer.init(allocator);
    try optimizer.optimize(&plan);

    try testing.expectEqual(@as(u32, 0), plan.operationCount());
}

test "QueryOptimizer handles single operation" {
    const allocator = testing.allocator;

    var plan = QueryPlan.init(allocator);
    defer plan.deinit();

    try plan.addFilter(filterAgeOver30);

    var optimizer = QueryOptimizer.init(allocator);
    try optimizer.optimize(&plan);

    try testing.expectEqual(@as(u32, 1), plan.operationCount());
    try testing.expectEqual(OperationType.Filter, plan.operations.items[0].op_type);
}

test "Memory leak test: 100 lazy DataFrame cycles" {
    const allocator = testing.allocator;

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        var df = try createTestDataFrame(allocator);
        defer df.deinit();

        var lazy = LazyDataFrame.init(allocator, &df);
        defer lazy.deinit();

        try lazy.filter(filterAgeOver30);
        const columns = [_][]const u8{ "age", "score" };
        try lazy.select(&columns);

        var result = try lazy.collect();
        result.deinit();
    }

    // testing.allocator will report leaks automatically
}
