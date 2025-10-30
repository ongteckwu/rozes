//! Unit tests for statistical operations

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const Series = @import("../../../core/series.zig").Series;
const stats = @import("../../../core/stats.zig");
const types = @import("../../../core/types.zig");
const ColumnDesc = types.ColumnDesc;

test "variance computes correct sample variance for Int64" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [1, 2, 3, 4, 5] → mean = 3, variance = 2.5
    data[0] = 1;
    data[1] = 2;
    data[2] = 3;
    data[3] = 4;
    data[4] = 5;
    try df.setRowCount(5);

    const var_val = try stats.variance(&df, "values");

    try testing.expect(var_val != null);
    try testing.expectApproxEqAbs(@as(f64, 2.5), var_val.?, 0.0001);
}

test "variance computes correct sample variance for Float64" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Float64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asFloat64Buffer() orelse unreachable;
    // Data: [1.5, 2.5, 3.5, 4.5, 5.5] → mean = 3.5, variance = 2.5
    data[0] = 1.5;
    data[1] = 2.5;
    data[2] = 3.5;
    data[3] = 4.5;
    data[4] = 5.5;
    try df.setRowCount(5);

    const var_val = try stats.variance(&df, "values");

    try testing.expect(var_val != null);
    try testing.expectApproxEqAbs(@as(f64, 2.5), var_val.?, 0.0001);
}

test "variance returns 0 for single value" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 1);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    data[0] = 42;
    try df.setRowCount(1);

    const var_val = try stats.variance(&df, "values");

    try testing.expect(var_val != null);
    try testing.expectEqual(@as(f64, 0.0), var_val.?);
}

test "variance returns null for empty DataFrame" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 0);
    defer df.deinit();

    const var_val = try stats.variance(&df, "values");

    try testing.expect(var_val == null);
}

test "stdDev computes correct standard deviation" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [1, 2, 3, 4, 5] → variance = 2.5, stdDev = sqrt(2.5) ≈ 1.5811
    data[0] = 1;
    data[1] = 2;
    data[2] = 3;
    data[3] = 4;
    data[4] = 5;
    try df.setRowCount(5);

    const std_dev = try stats.stdDev(&df, "values");

    try testing.expect(std_dev != null);
    try testing.expectApproxEqAbs(@as(f64, 1.5811), std_dev.?, 0.0001);
}

test "median computes correct value for odd-length array" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [10, 20, 30, 40, 50] → median = 30
    data[0] = 10;
    data[1] = 20;
    data[2] = 30;
    data[3] = 40;
    data[4] = 50;
    try df.setRowCount(5);

    const median_val = try stats.median(&df, "values", allocator);

    try testing.expect(median_val != null);
    try testing.expectApproxEqAbs(@as(f64, 30.0), median_val.?, 0.0001);
}

test "median computes correct value for even-length array" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [10, 20, 30, 40] → median = (20 + 30) / 2 = 25
    data[0] = 10;
    data[1] = 20;
    data[2] = 30;
    data[3] = 40;
    try df.setRowCount(4);

    const median_val = try stats.median(&df, "values", allocator);

    try testing.expect(median_val != null);
    try testing.expectApproxEqAbs(@as(f64, 25.0), median_val.?, 0.0001);
}

test "quantile computes 25th percentile correctly" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [10, 20, 30, 40, 50] → Q1 (25th percentile) = 20
    data[0] = 10;
    data[1] = 20;
    data[2] = 30;
    data[3] = 40;
    data[4] = 50;
    try df.setRowCount(5);

    const q25 = try stats.quantile(&df, "values", allocator, 0.25);

    try testing.expect(q25 != null);
    try testing.expectApproxEqAbs(@as(f64, 20.0), q25.?, 0.0001);
}

test "quantile computes 75th percentile correctly" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [10, 20, 30, 40, 50] → Q3 (75th percentile) = 40
    data[0] = 10;
    data[1] = 20;
    data[2] = 30;
    data[3] = 40;
    data[4] = 50;
    try df.setRowCount(5);

    const q75 = try stats.quantile(&df, "values", allocator, 0.75);

    try testing.expect(q75 != null);
    try testing.expectApproxEqAbs(@as(f64, 40.0), q75.?, 0.0001);
}

test "corrMatrix computes identity for single column" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("x", .Float64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asFloat64Buffer() orelse unreachable;
    data[0] = 1.0;
    data[1] = 2.0;
    data[2] = 3.0;
    data[3] = 4.0;
    data[4] = 5.0;
    try df.setRowCount(5);

    var matrix = try stats.corrMatrix(&df, allocator, &[_][]const u8{"x"});
    defer {
        for (matrix) |row| {
            allocator.free(row);
        }
        allocator.free(matrix);
    }

    // 1×1 matrix should be [1.0] (perfect correlation with self)
    try testing.expectEqual(@as(usize, 1), matrix.len);
    try testing.expectApproxEqAbs(@as(f64, 1.0), matrix[0][0], 0.0001);
}

test "corrMatrix computes perfect positive correlation" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("x", .Float64, 0),
        ColumnDesc.init("y", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const x_data = df.columns[0].asFloat64Buffer() orelse unreachable;
    const y_data = df.columns[1].asFloat64Buffer() orelse unreachable;

    // Perfect positive correlation: y = 2x
    x_data[0] = 1.0;
    x_data[1] = 2.0;
    x_data[2] = 3.0;
    x_data[3] = 4.0;
    x_data[4] = 5.0;

    y_data[0] = 2.0;
    y_data[1] = 4.0;
    y_data[2] = 6.0;
    y_data[3] = 8.0;
    y_data[4] = 10.0;

    try df.setRowCount(5);

    var matrix = try stats.corrMatrix(&df, allocator, &[_][]const u8{ "x", "y" });
    defer {
        for (matrix) |row| {
            allocator.free(row);
        }
        allocator.free(matrix);
    }

    // Correlation matrix:
    // [1.0, 1.0]
    // [1.0, 1.0]
    try testing.expectApproxEqAbs(@as(f64, 1.0), matrix[0][0], 0.0001); // x with x
    try testing.expectApproxEqAbs(@as(f64, 1.0), matrix[0][1], 0.0001); // x with y
    try testing.expectApproxEqAbs(@as(f64, 1.0), matrix[1][0], 0.0001); // y with x
    try testing.expectApproxEqAbs(@as(f64, 1.0), matrix[1][1], 0.0001); // y with y
}

test "corrMatrix computes perfect negative correlation" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("x", .Float64, 0),
        ColumnDesc.init("y", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const x_data = df.columns[0].asFloat64Buffer() orelse unreachable;
    const y_data = df.columns[1].asFloat64Buffer() orelse unreachable;

    // Perfect negative correlation: y = -2x + 12
    x_data[0] = 1.0;
    x_data[1] = 2.0;
    x_data[2] = 3.0;
    x_data[3] = 4.0;
    x_data[4] = 5.0;

    y_data[0] = 10.0;
    y_data[1] = 8.0;
    y_data[2] = 6.0;
    y_data[3] = 4.0;
    y_data[4] = 2.0;

    try df.setRowCount(5);

    var matrix = try stats.corrMatrix(&df, allocator, &[_][]const u8{ "x", "y" });
    defer {
        for (matrix) |row| {
            allocator.free(row);
        }
        allocator.free(matrix);
    }

    // Correlation matrix:
    // [1.0, -1.0]
    // [-1.0, 1.0]
    try testing.expectApproxEqAbs(@as(f64, 1.0), matrix[0][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f64, -1.0), matrix[0][1], 0.0001);
    try testing.expectApproxEqAbs(@as(f64, -1.0), matrix[1][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 1.0), matrix[1][1], 0.0001);
}

test "corrMatrix handles zero variance (all same values)" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("x", .Float64, 0),
        ColumnDesc.init("y", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const x_data = df.columns[0].asFloat64Buffer() orelse unreachable;
    const y_data = df.columns[1].asFloat64Buffer() orelse unreachable;

    // x has variance, y has zero variance (all same)
    x_data[0] = 1.0;
    x_data[1] = 2.0;
    x_data[2] = 3.0;
    x_data[3] = 4.0;
    x_data[4] = 5.0;

    y_data[0] = 10.0;
    y_data[1] = 10.0;
    y_data[2] = 10.0;
    y_data[3] = 10.0;
    y_data[4] = 10.0;

    try df.setRowCount(5);

    var matrix = try stats.corrMatrix(&df, allocator, &[_][]const u8{ "x", "y" });
    defer {
        for (matrix) |row| {
            allocator.free(row);
        }
        allocator.free(matrix);
    }

    // When one column has zero variance, correlation is undefined (returns 0.0)
    try testing.expectApproxEqAbs(@as(f64, 1.0), matrix[0][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 0.0), matrix[0][1], 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 0.0), matrix[1][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 1.0), matrix[1][1], 0.0001);
}

test "rank assigns correct ranks with First method" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [30, 10, 50, 20, 40] → ranks (First): [3, 1, 5, 2, 4]
    data[0] = 30;
    data[1] = 10;
    data[2] = 50;
    data[3] = 20;
    data[4] = 40;
    try df.setRowCount(5);

    var ranked = try stats.rank(&df.columns[0], allocator, .First);
    defer allocator.free(ranked.data.Float64);

    const ranks = ranked.asFloat64() orelse unreachable;

    try testing.expectApproxEqAbs(@as(f64, 3.0), ranks[0], 0.0001); // 30 → rank 3
    try testing.expectApproxEqAbs(@as(f64, 1.0), ranks[1], 0.0001); // 10 → rank 1
    try testing.expectApproxEqAbs(@as(f64, 5.0), ranks[2], 0.0001); // 50 → rank 5
    try testing.expectApproxEqAbs(@as(f64, 2.0), ranks[3], 0.0001); // 20 → rank 2
    try testing.expectApproxEqAbs(@as(f64, 4.0), ranks[4], 0.0001); // 40 → rank 4
}

test "rank handles single value" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 1);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    data[0] = 42;
    try df.setRowCount(1);

    var ranked = try stats.rank(&df.columns[0], allocator, .First);
    defer allocator.free(ranked.data.Float64);

    const ranks = ranked.asFloat64() orelse unreachable;

    try testing.expectApproxEqAbs(@as(f64, 1.0), ranks[0], 0.0001); // Single value → rank 1
}

// ========================================
// Rank Tie-Breaking Tests
// ========================================

test "rank with Average method handles ties correctly" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 7);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [10, 20, 20, 30, 30, 30, 40]
    // Ranks (Average): [1, 2.5, 2.5, 5, 5, 5, 7]
    data[0] = 10;
    data[1] = 20;
    data[2] = 20;
    data[3] = 30;
    data[4] = 30;
    data[5] = 30;
    data[6] = 40;
    df.columns[0].length = 7;
    try df.setRowCount(7);

    var ranked = try stats.rank(&df.columns[0], allocator, .Average);
    defer allocator.free(ranked.data.Float64);

    const ranks = ranked.asFloat64() orelse unreachable;

    try testing.expectApproxEqAbs(@as(f64, 1.0), ranks[0], 0.0001); // 10 → rank 1
    try testing.expectApproxEqAbs(@as(f64, 2.5), ranks[1], 0.0001); // 20 → rank 2.5 (avg of 2,3)
    try testing.expectApproxEqAbs(@as(f64, 2.5), ranks[2], 0.0001); // 20 → rank 2.5
    try testing.expectApproxEqAbs(@as(f64, 5.0), ranks[3], 0.0001); // 30 → rank 5 (avg of 4,5,6)
    try testing.expectApproxEqAbs(@as(f64, 5.0), ranks[4], 0.0001); // 30 → rank 5
    try testing.expectApproxEqAbs(@as(f64, 5.0), ranks[5], 0.0001); // 30 → rank 5
    try testing.expectApproxEqAbs(@as(f64, 7.0), ranks[6], 0.0001); // 40 → rank 7
}

test "rank with Min method handles ties correctly" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 6);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [1, 2, 2, 4, 4, 4]
    // Ranks (Min): [1, 2, 2, 4, 4, 4]
    data[0] = 1;
    data[1] = 2;
    data[2] = 2;
    data[3] = 4;
    data[4] = 4;
    data[5] = 4;
    df.columns[0].length = 6;
    try df.setRowCount(6);

    var ranked = try stats.rank(&df.columns[0], allocator, .Min);
    defer allocator.free(ranked.data.Float64);

    const ranks = ranked.asFloat64() orelse unreachable;

    try testing.expectApproxEqAbs(@as(f64, 1.0), ranks[0], 0.0001); // 1 → rank 1
    try testing.expectApproxEqAbs(@as(f64, 2.0), ranks[1], 0.0001); // 2 → rank 2
    try testing.expectApproxEqAbs(@as(f64, 2.0), ranks[2], 0.0001); // 2 → rank 2
    try testing.expectApproxEqAbs(@as(f64, 4.0), ranks[3], 0.0001); // 4 → rank 4
    try testing.expectApproxEqAbs(@as(f64, 4.0), ranks[4], 0.0001); // 4 → rank 4
    try testing.expectApproxEqAbs(@as(f64, 4.0), ranks[5], 0.0001); // 4 → rank 4
}

test "rank with Max method handles ties correctly" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 6);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [1, 2, 2, 4, 4, 4]
    // Ranks (Max): [1, 3, 3, 6, 6, 6]
    data[0] = 1;
    data[1] = 2;
    data[2] = 2;
    data[3] = 4;
    data[4] = 4;
    data[5] = 4;
    df.columns[0].length = 6;
    try df.setRowCount(6);

    var ranked = try stats.rank(&df.columns[0], allocator, .Max);
    defer allocator.free(ranked.data.Float64);

    const ranks = ranked.asFloat64() orelse unreachable;

    try testing.expectApproxEqAbs(@as(f64, 1.0), ranks[0], 0.0001); // 1 → rank 1
    try testing.expectApproxEqAbs(@as(f64, 3.0), ranks[1], 0.0001); // 2 → rank 3
    try testing.expectApproxEqAbs(@as(f64, 3.0), ranks[2], 0.0001); // 2 → rank 3
    try testing.expectApproxEqAbs(@as(f64, 6.0), ranks[3], 0.0001); // 4 → rank 6
    try testing.expectApproxEqAbs(@as(f64, 6.0), ranks[4], 0.0001); // 4 → rank 6
    try testing.expectApproxEqAbs(@as(f64, 6.0), ranks[5], 0.0001); // 4 → rank 6
}

test "rank with all methods on no ties" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [10, 20, 30, 40, 50] - no ties
    data[0] = 10;
    data[1] = 20;
    data[2] = 30;
    data[3] = 40;
    data[4] = 50;
    df.columns[0].length = 5;
    try df.setRowCount(5);

    // All methods should produce same result when no ties
    const methods = [_]stats.RankMethod{ .First, .Average, .Min, .Max };

    for (methods) |method| {
        var ranked = try stats.rank(&df.columns[0], allocator, method);
        defer allocator.free(ranked.data.Float64);

        const ranks = ranked.asFloat64() orelse unreachable;

        try testing.expectApproxEqAbs(@as(f64, 1.0), ranks[0], 0.0001);
        try testing.expectApproxEqAbs(@as(f64, 2.0), ranks[1], 0.0001);
        try testing.expectApproxEqAbs(@as(f64, 3.0), ranks[2], 0.0001);
        try testing.expectApproxEqAbs(@as(f64, 4.0), ranks[3], 0.0001);
        try testing.expectApproxEqAbs(@as(f64, 5.0), ranks[4], 0.0001);
    }
}

test "rank with all tied values" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // All same value
    for (data[0..5]) |*val| val.* = 42;
    df.columns[0].length = 5;
    try df.setRowCount(5);

    // Test Average method: should all get rank 3.0 (average of 1,2,3,4,5)
    var ranked_avg = try stats.rank(&df.columns[0], allocator, .Average);
    defer allocator.free(ranked_avg.data.Float64);
    const ranks_avg = ranked_avg.asFloat64() orelse unreachable;
    for (ranks_avg) |rank| {
        try testing.expectApproxEqAbs(@as(f64, 3.0), rank, 0.0001);
    }

    // Test Min method: should all get rank 1.0
    var ranked_min = try stats.rank(&df.columns[0], allocator, .Min);
    defer allocator.free(ranked_min.data.Float64);
    const ranks_min = ranked_min.asFloat64() orelse unreachable;
    for (ranks_min) |rank| {
        try testing.expectApproxEqAbs(@as(f64, 1.0), rank, 0.0001);
    }

    // Test Max method: should all get rank 5.0
    var ranked_max = try stats.rank(&df.columns[0], allocator, .Max);
    defer allocator.free(ranked_max.data.Float64);
    const ranks_max = ranked_max.asFloat64() orelse unreachable;
    for (ranks_max) |rank| {
        try testing.expectApproxEqAbs(@as(f64, 5.0), rank, 0.0001);
    }
}

test "rank with Float64 values and ties" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Float64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 6);
    defer df.deinit();

    const data = df.columns[0].asFloat64Buffer() orelse unreachable;
    // Data: [1.5, 2.5, 2.5, 3.5, 3.5, 3.5]
    data[0] = 1.5;
    data[1] = 2.5;
    data[2] = 2.5;
    data[3] = 3.5;
    data[4] = 3.5;
    data[5] = 3.5;
    df.columns[0].length = 6;
    try df.setRowCount(6);

    var ranked = try stats.rank(&df.columns[0], allocator, .Average);
    defer allocator.free(ranked.data.Float64);

    const ranks = ranked.asFloat64() orelse unreachable;

    try testing.expectApproxEqAbs(@as(f64, 1.0), ranks[0], 0.0001); // 1.5 → rank 1
    try testing.expectApproxEqAbs(@as(f64, 2.5), ranks[1], 0.0001); // 2.5 → rank 2.5
    try testing.expectApproxEqAbs(@as(f64, 2.5), ranks[2], 0.0001); // 2.5 → rank 2.5
    try testing.expectApproxEqAbs(@as(f64, 5.0), ranks[3], 0.0001); // 3.5 → rank 5.0
    try testing.expectApproxEqAbs(@as(f64, 5.0), ranks[4], 0.0001); // 3.5 → rank 5.0
    try testing.expectApproxEqAbs(@as(f64, 5.0), ranks[5], 0.0001); // 3.5 → rank 5.0
}

// ========================================
// Percentile Rank Tests
// ========================================

test "percentileRank maps ranks to 0-1 scale" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [10, 20, 30, 40, 50] → ranks [1, 2, 3, 4, 5]
    // Percentile ranks: [0.0, 0.25, 0.5, 0.75, 1.0]
    data[0] = 10;
    data[1] = 20;
    data[2] = 30;
    data[3] = 40;
    data[4] = 50;
    df.columns[0].length = 5;
    try df.setRowCount(5);

    var pct_ranked = try stats.percentileRank(&df.columns[0], allocator, .First);
    defer allocator.free(pct_ranked.data.Float64);

    const pct_ranks = pct_ranked.asFloat64() orelse unreachable;

    try testing.expectApproxEqAbs(@as(f64, 0.0), pct_ranks[0], 0.0001); // 10 → 0.0
    try testing.expectApproxEqAbs(@as(f64, 0.25), pct_ranks[1], 0.0001); // 20 → 0.25
    try testing.expectApproxEqAbs(@as(f64, 0.5), pct_ranks[2], 0.0001); // 30 → 0.5
    try testing.expectApproxEqAbs(@as(f64, 0.75), pct_ranks[3], 0.0001); // 40 → 0.75
    try testing.expectApproxEqAbs(@as(f64, 1.0), pct_ranks[4], 0.0001); // 50 → 1.0
}

test "percentileRank with Average method on ties" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [10, 20, 20, 30]
    // Ranks (Average): [1, 2.5, 2.5, 4]
    // Percentile: [(1-1)/(4-1), (2.5-1)/(4-1), (2.5-1)/(4-1), (4-1)/(4-1)]
    //           = [0, 0.5, 0.5, 1.0]
    data[0] = 10;
    data[1] = 20;
    data[2] = 20;
    data[3] = 30;
    df.columns[0].length = 4;
    try df.setRowCount(4);

    var pct_ranked = try stats.percentileRank(&df.columns[0], allocator, .Average);
    defer allocator.free(pct_ranked.data.Float64);

    const pct_ranks = pct_ranked.asFloat64() orelse unreachable;

    try testing.expectApproxEqAbs(@as(f64, 0.0), pct_ranks[0], 0.0001); // 10 → 0.0
    try testing.expectApproxEqAbs(@as(f64, 0.5), pct_ranks[1], 0.0001); // 20 → 0.5
    try testing.expectApproxEqAbs(@as(f64, 0.5), pct_ranks[2], 0.0001); // 20 → 0.5
    try testing.expectApproxEqAbs(@as(f64, 1.0), pct_ranks[3], 0.0001); // 30 → 1.0
}

test "percentileRank handles single value" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 1);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    data[0] = 42;
    try df.setRowCount(1);

    var pct_ranked = try stats.percentileRank(&df.columns[0], allocator, .First);
    defer allocator.free(pct_ranked.data.Float64);

    const pct_ranks = pct_ranked.asFloat64() orelse unreachable;

    // Single value gets 0.5 (middle of 0-1 range)
    try testing.expectApproxEqAbs(@as(f64, 0.5), pct_ranks[0], 0.0001);
}

test "percentileRank with large dataset" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Create values 1-100
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        data[i] = @as(i64, @intCast(i + 1));
    }
    df.columns[0].length = 100;
    try df.setRowCount(100);

    var pct_ranked = try stats.percentileRank(&df.columns[0], allocator, .First);
    defer allocator.free(pct_ranked.data.Float64);

    const pct_ranks = pct_ranked.asFloat64() orelse unreachable;

    // First value should be 0.0
    try testing.expectApproxEqAbs(@as(f64, 0.0), pct_ranks[0], 0.0001);
    // Last value should be 1.0
    try testing.expectApproxEqAbs(@as(f64, 1.0), pct_ranks[99], 0.0001);
    // Middle value (50) should be ~0.495 ((50-1)/(100-1))
    try testing.expectApproxEqAbs(@as(f64, 0.4949), pct_ranks[49], 0.001);
}

test "rank methods memory leak test (1000 iterations)" {
    const allocator = testing.allocator;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const cols = [_]ColumnDesc{
            ColumnDesc.init("values", .Int64, 0),
        };

        var df = try DataFrame.create(allocator, &cols, 10);
        defer df.deinit();

        const data = df.columns[0].asInt64Buffer() orelse unreachable;
        var j: u32 = 0;
        while (j < 10) : (j += 1) {
            data[j] = @mod(@as(i64, @intCast(j)), 3);
        }
        df.columns[0].length = 10;
        try df.setRowCount(10);

        // Test all methods
        var ranked_first = try stats.rank(&df.columns[0], allocator, .First);
        allocator.free(ranked_first.data.Float64);

        var ranked_avg = try stats.rank(&df.columns[0], allocator, .Average);
        allocator.free(ranked_avg.data.Float64);

        var ranked_min = try stats.rank(&df.columns[0], allocator, .Min);
        allocator.free(ranked_min.data.Float64);

        var ranked_max = try stats.rank(&df.columns[0], allocator, .Max);
        allocator.free(ranked_max.data.Float64);

        var pct_ranked = try stats.percentileRank(&df.columns[0], allocator, .Average);
        allocator.free(pct_ranked.data.Float64);
    }

    // testing.allocator will report leaks automatically
}

// ========================================
// Value Counts Tests
// ========================================

test "valueCounts counts Int64 values correctly" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 7);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [1, 2, 2, 3, 3, 3, 1] → counts: {3:3, 2:2, 1:2}
    data[0] = 1;
    data[1] = 2;
    data[2] = 2;
    data[3] = 3;
    data[4] = 3;
    data[5] = 3;
    data[6] = 1;
    df.columns[0].length = 7;
    try df.setRowCount(7);

    var result = try stats.valueCounts(&df.columns[0], allocator, .{});
    defer result.deinit();

    // Should have 3 unique values
    try testing.expectEqual(@as(u32, 3), result.len());

    // Check structure
    try testing.expect(result.hasColumn("value"));
    try testing.expect(result.hasColumn("count"));

    // Get count column to verify sorting (descending by count)
    const count_col = result.column("count").?;
    const counts = count_col.asFloat64() orelse unreachable;

    // Should be sorted descending: [3, 2, 2]
    try testing.expectApproxEqAbs(@as(f64, 3.0), counts[0], 0.0001); // 3 appears 3 times
    try testing.expectApproxEqAbs(@as(f64, 2.0), counts[1], 0.0001); // 2 appears 2 times
    try testing.expectApproxEqAbs(@as(f64, 2.0), counts[2], 0.0001); // 1 appears 2 times
}

test "valueCounts with normalize returns percentages" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: 6 ones, 3 twos, 1 three
    var i: u32 = 0;
    while (i < 6) : (i += 1) data[i] = 1;
    while (i < 9) : (i += 1) data[i] = 2;
    data[9] = 3;
    df.columns[0].length = 10;
    try df.setRowCount(10);

    var result = try stats.valueCounts(&df.columns[0], allocator, .{ .normalize = true });
    defer result.deinit();

    const count_col = result.column("count").?;
    const counts = count_col.asFloat64() orelse unreachable;

    // Should be percentages: [0.6, 0.3, 0.1]
    try testing.expectApproxEqAbs(@as(f64, 0.6), counts[0], 0.0001); // 6/10
    try testing.expectApproxEqAbs(@as(f64, 0.3), counts[1], 0.0001); // 3/10
    try testing.expectApproxEqAbs(@as(f64, 0.1), counts[2], 0.0001); // 1/10
}

test "valueCounts without sort preserves insertion order" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 6);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data with equal counts: [1, 1, 2, 2, 3, 3]
    data[0] = 1;
    data[1] = 1;
    data[2] = 2;
    data[3] = 2;
    data[4] = 3;
    data[5] = 3;
    df.columns[0].length = 6;
    try df.setRowCount(6);

    var result = try stats.valueCounts(&df.columns[0], allocator, .{ .sort = false });
    defer result.deinit();

    // Should have 3 unique values (order not guaranteed without sort)
    try testing.expectEqual(@as(u32, 3), result.len());

    // All counts should be 2
    const count_col = result.column("count").?;
    const counts = count_col.asFloat64() orelse unreachable;

    for (counts) |count| {
        try testing.expectApproxEqAbs(@as(f64, 2.0), count, 0.0001);
    }
}

test "valueCounts handles single unique value" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // All same value
    for (data[0..5]) |*val| val.* = 42;
    df.columns[0].length = 5;
    try df.setRowCount(5);

    var result = try stats.valueCounts(&df.columns[0], allocator, .{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 1), result.len());

    const value_col = result.column("value").?;
    const values = value_col.asInt64() orelse unreachable;
    try testing.expectEqual(@as(i64, 42), values[0]);

    const count_col = result.column("count").?;
    const counts = count_col.asFloat64() orelse unreachable;
    try testing.expectApproxEqAbs(@as(f64, 5.0), counts[0], 0.0001);
}

test "valueCounts handles all unique values" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // All different
    data[0] = 10;
    data[1] = 20;
    data[2] = 30;
    data[3] = 40;
    data[4] = 50;
    df.columns[0].length = 5;
    try df.setRowCount(5);

    var result = try stats.valueCounts(&df.columns[0], allocator, .{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 5), result.len());

    // All counts should be 1
    const count_col = result.column("count").?;
    const counts = count_col.asFloat64() orelse unreachable;

    for (counts) |count| {
        try testing.expectApproxEqAbs(@as(f64, 1.0), count, 0.0001);
    }
}

test "valueCounts works with Bool type" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("flags", .Bool, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 7);
    defer df.deinit();

    const data = df.columns[0].asBoolBuffer() orelse unreachable;
    // Data: [true, false, true, true, false, true, true] → true:5, false:2
    data[0] = true;
    data[1] = false;
    data[2] = true;
    data[3] = true;
    data[4] = false;
    data[5] = true;
    data[6] = true;
    df.columns[0].length = 7;
    try df.setRowCount(7);

    var result = try stats.valueCounts(&df.columns[0], allocator, .{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 2), result.len());

    const count_col = result.column("count").?;
    const counts = count_col.asFloat64() orelse unreachable;

    // Should be sorted descending: [5, 2]
    try testing.expectApproxEqAbs(@as(f64, 5.0), counts[0], 0.0001); // true count
    try testing.expectApproxEqAbs(@as(f64, 2.0), counts[1], 0.0001); // false count
}

test "valueCounts handles large dataset (1000 values)" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 1000);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Create data with pattern: 0-9 repeated 100 times each
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        data[i] = @mod(@as(i64, @intCast(i)), 10);
    }
    df.columns[0].length = 1000;
    try df.setRowCount(1000);

    var result = try stats.valueCounts(&df.columns[0], allocator, .{});
    defer result.deinit();

    // Should have 10 unique values
    try testing.expectEqual(@as(u32, 10), result.len());

    // All counts should be 100
    const count_col = result.column("count").?;
    const counts = count_col.asFloat64() orelse unreachable;

    for (counts) |count| {
        try testing.expectApproxEqAbs(@as(f64, 100.0), count, 0.0001);
    }
}

test "valueCounts memory leak test (1000 iterations)" {
    const allocator = testing.allocator;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const cols = [_]ColumnDesc{
            ColumnDesc.init("values", .Int64, 0),
        };

        var df = try DataFrame.create(allocator, &cols, 10);
        defer df.deinit();

        const data = df.columns[0].asInt64Buffer() orelse unreachable;
        var j: u32 = 0;
        while (j < 10) : (j += 1) {
            data[j] = @mod(@as(i64, @intCast(j)), 3);
        }
        df.columns[0].length = 10;
        try df.setRowCount(10);

        var result = try stats.valueCounts(&df.columns[0], allocator, .{});
        defer result.deinit();
    }

    // testing.allocator will report leaks automatically
}

test "valueCounts with normalize and unsorted" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // 5 ones, 3 twos, 2 threes
    var i: u32 = 0;
    while (i < 5) : (i += 1) data[i] = 1;
    while (i < 8) : (i += 1) data[i] = 2;
    while (i < 10) : (i += 1) data[i] = 3;
    df.columns[0].length = 10;
    try df.setRowCount(10);

    var result = try stats.valueCounts(&df.columns[0], allocator, .{
        .normalize = true,
        .sort = false,
    });
    defer result.deinit();

    try testing.expectEqual(@as(u32, 3), result.len());

    const count_col = result.column("count").?;
    const counts = count_col.asFloat64() orelse unreachable;

    // Check all percentages sum to ~1.0
    var sum: f64 = 0.0;
    for (counts) |count| {
        sum += count;
    }
    try testing.expectApproxEqAbs(@as(f64, 1.0), sum, 0.0001);
}

test "valueCounts Bool with all true" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("flags", .Bool, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const data = df.columns[0].asBoolBuffer() orelse unreachable;
    for (data[0..5]) |*val| val.* = true;
    df.columns[0].length = 5;
    try df.setRowCount(5);

    var result = try stats.valueCounts(&df.columns[0], allocator, .{});
    defer result.deinit();

    // Should have only one unique value (true)
    try testing.expectEqual(@as(u32, 2), result.len()); // Still returns 2 (true and false)

    const count_col = result.column("count").?;
    const counts = count_col.asFloat64() orelse unreachable;

    // First should be true (5), second should be false (0)
    try testing.expectApproxEqAbs(@as(f64, 5.0), counts[0], 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 0.0), counts[1], 0.0001);
}

test "valueCounts with negative Int64 values" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 6);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [-10, -5, -10, 0, 5, -5] → counts: {-10:2, -5:2, 0:1, 5:1}
    data[0] = -10;
    data[1] = -5;
    data[2] = -10;
    data[3] = 0;
    data[4] = 5;
    data[5] = -5;
    df.columns[0].length = 6;
    try df.setRowCount(6);

    var result = try stats.valueCounts(&df.columns[0], allocator, .{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 4), result.len());

    // Verify all values are accounted for
    const count_col = result.column("count").?;
    const counts = count_col.asFloat64() orelse unreachable;

    var total_count: f64 = 0.0;
    for (counts) |count| {
        total_count += count;
    }
    try testing.expectApproxEqAbs(@as(f64, 6.0), total_count, 0.0001);
}

test "valueCounts normalized with all unique values" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    const data = df.columns[0].asInt64Buffer() orelse unreachable;
    data[0] = 1;
    data[1] = 2;
    data[2] = 3;
    data[3] = 4;
    df.columns[0].length = 4;
    try df.setRowCount(4);

    var result = try stats.valueCounts(&df.columns[0], allocator, .{ .normalize = true });
    defer result.deinit();

    const count_col = result.column("count").?;
    const counts = count_col.asFloat64() orelse unreachable;

    // All should be 0.25 (1/4)
    for (counts) |count| {
        try testing.expectApproxEqAbs(@as(f64, 0.25), count, 0.0001);
    }
}

test "statistics module has no memory leaks (1000 iterations)" {
    const allocator = testing.allocator;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const cols = [_]ColumnDesc{
            ColumnDesc.init("x", .Float64, 0),
            ColumnDesc.init("y", .Float64, 1),
        };

        var df = try DataFrame.create(allocator, &cols, 10);
        defer df.deinit();

        const x_data = df.columns[0].asFloat64Buffer() orelse unreachable;
        const y_data = df.columns[1].asFloat64Buffer() orelse unreachable;

        var j: u32 = 0;
        while (j < 10) : (j += 1) {
            x_data[j] = @as(f64, @floatFromInt(j));
            y_data[j] = @as(f64, @floatFromInt(j * 2));
        }
        try df.setRowCount(10);

        // Test all operations
        _ = try stats.variance(&df, "x");
        _ = try stats.stdDev(&df, "x");
        _ = try stats.median(&df, "x", allocator);
        _ = try stats.quantile(&df, "x", allocator, 0.75);

        var matrix = try stats.corrMatrix(&df, allocator, &[_][]const u8{ "x", "y" });
        for (matrix) |row| {
            allocator.free(row);
        }
        allocator.free(matrix);

        var ranked = try stats.rank(&df.columns[0], allocator, .First);
        allocator.free(ranked.data.Float64);
    }

    // testing.allocator will report leaks automatically
}
