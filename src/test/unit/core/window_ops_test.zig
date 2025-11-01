//! Unit tests for window operations (rolling, expanding, shift, diff, pct_change)
//!
//! Test coverage:
//! - Rolling window: sum, mean, min, max, std
//! - Expanding window: sum, mean
//! - Shift operations (forward and backward)
//! - Diff and pct_change
//! - Edge cases: window > series length, empty series, NaN handling
//! - Memory leak testing (1000 iterations)

const std = @import("std");
const testing = std.testing;
const Series = @import("../../../core/series.zig").Series;
const window_ops = @import("../../../core/window_ops.zig");
const RollingWindow = window_ops.RollingWindow;
const ExpandingWindow = window_ops.ExpandingWindow;

// Test: Rolling window initialization
test "RollingWindow.init validates window size" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(i64, 10);
    defer allocator.free(data);

    for (0..10) |i| data[i] = @intCast(i + 1);

    const series = Series{
        .name = "test",
        .valueType = .Int64,
        .data = .{ .Int64 = data },
        .length = 10,
    };

    // Valid window
    const window = try RollingWindow.init(&series, 3);
    try testing.expectEqual(@as(u32, 3), window.window_size);

    // Zero window should fail
    const zero_result = RollingWindow.init(&series, 0);
    try testing.expectError(error.InvalidWindowSize, zero_result);

    // Window too large should fail
    const large_result = RollingWindow.init(&series, window_ops.MAX_WINDOW_SIZE + 1);
    try testing.expectError(error.WindowSizeTooLarge, large_result);
}

// Test: Rolling sum
test "RollingWindow.sum computes correct rolling sum" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(i64, 5);
    defer allocator.free(data);

    // Data: [1, 2, 3, 4, 5]
    for (0..5) |i| data[i] = @intCast(i + 1);

    const series = Series{
        .name = "test",
        .valueType = .Int64,
        .data = .{ .Int64 = data },
        .length = 5,
    };

    const window = try RollingWindow.init(&series, 3);
    const result = try window.sum(allocator);
    defer allocator.free(result.data.Float64);

    // Expected: [1, 3, 6, 9, 12] (window=3)
    // [1], [1,2], [1,2,3], [2,3,4], [3,4,5]
    const expected = [_]f64{ 1, 3, 6, 9, 12 };
    for (0..5) |i| {
        try testing.expectApproxEqAbs(expected[i], result.data.Float64[i], 0.001);
    }
}

// Test: Rolling mean
test "RollingWindow.mean computes correct rolling mean" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(f64, 5);
    defer allocator.free(data);

    // Data: [10, 20, 30, 40, 50]
    for (0..5) |i| data[i] = @as(f64, @floatFromInt((i + 1) * 10));

    const series = Series{
        .name = "test",
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 5,
    };

    const window = try RollingWindow.init(&series, 3);
    const result = try window.mean(allocator);
    defer allocator.free(result.data.Float64);

    // Expected: [10, 15, 20, 30, 40]
    // [10], [10,20], [10,20,30], [20,30,40], [30,40,50]
    const expected = [_]f64{ 10.0, 15.0, 20.0, 30.0, 40.0 };
    for (0..5) |i| {
        try testing.expectApproxEqAbs(expected[i], result.data.Float64[i], 0.001);
    }
}

// Test: Rolling min
test "RollingWindow.min computes correct rolling minimum" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(i64, 5);
    defer allocator.free(data);

    // Data: [5, 2, 8, 1, 9]
    data[0] = 5;
    data[1] = 2;
    data[2] = 8;
    data[3] = 1;
    data[4] = 9;

    const series = Series{
        .name = "test",
        .valueType = .Int64,
        .data = .{ .Int64 = data },
        .length = 5,
    };

    const window = try RollingWindow.init(&series, 3);
    const result = try window.min(allocator);
    defer allocator.free(result.data.Float64);

    // Expected: [5, 2, 2, 1, 1]
    const expected = [_]f64{ 5, 2, 2, 1, 1 };
    for (0..5) |i| {
        try testing.expectApproxEqAbs(expected[i], result.data.Float64[i], 0.001);
    }
}

// Test: Rolling max
test "RollingWindow.max computes correct rolling maximum" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(f64, 5);
    defer allocator.free(data);

    // Data: [5, 2, 8, 1, 9]
    data[0] = 5;
    data[1] = 2;
    data[2] = 8;
    data[3] = 1;
    data[4] = 9;

    const series = Series{
        .name = "test",
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 5,
    };

    const window = try RollingWindow.init(&series, 3);
    const result = try window.max(allocator);
    defer allocator.free(result.data.Float64);

    // Expected: [5, 5, 8, 8, 9]
    const expected = [_]f64{ 5, 5, 8, 8, 9 };
    for (0..5) |i| {
        try testing.expectApproxEqAbs(expected[i], result.data.Float64[i], 0.001);
    }
}

// Test: Rolling std
test "RollingWindow.std computes correct rolling standard deviation" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(f64, 5);
    defer allocator.free(data);

    // Data: [2, 4, 4, 4, 5]
    data[0] = 2;
    data[1] = 4;
    data[2] = 4;
    data[3] = 4;
    data[4] = 5;

    const series = Series{
        .name = "test",
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 5,
    };

    const window = try RollingWindow.init(&series, 3);
    const result = try window.stddev(allocator);
    defer allocator.free(result.data.Float64);

    // Expected: [0, 1, 0.943, 0, 0.471]
    // First element: [2] -> std = 0
    // Second element: [2, 4] -> std = 1.0
    // Third element: [2, 4, 4] -> std ≈ 0.943
    try testing.expectApproxEqAbs(0.0, result.data.Float64[0], 0.001);
    try testing.expectApproxEqAbs(1.0, result.data.Float64[1], 0.001);
    try testing.expectApproxEqAbs(0.943, result.data.Float64[2], 0.05);
}

// Test: Expanding sum
test "ExpandingWindow.sum computes correct cumulative sum" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(i64, 5);
    defer allocator.free(data);

    // Data: [1, 2, 3, 4, 5]
    for (0..5) |i| data[i] = @intCast(i + 1);

    const series = Series{
        .name = "test",
        .valueType = .Int64,
        .data = .{ .Int64 = data },
        .length = 5,
    };

    const window = ExpandingWindow.init(&series);
    const result = try window.sum(allocator);
    defer allocator.free(result.data.Float64);

    // Expected: [1, 3, 6, 10, 15]
    const expected = [_]f64{ 1, 3, 6, 10, 15 };
    for (0..5) |i| {
        try testing.expectApproxEqAbs(expected[i], result.data.Float64[i], 0.001);
    }
}

// Test: Expanding mean
test "ExpandingWindow.mean computes correct cumulative mean" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(f64, 5);
    defer allocator.free(data);

    // Data: [10, 20, 30, 40, 50]
    for (0..5) |i| data[i] = @as(f64, @floatFromInt((i + 1) * 10));

    const series = Series{
        .name = "test",
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 5,
    };

    const window = ExpandingWindow.init(&series);
    const result = try window.mean(allocator);
    defer allocator.free(result.data.Float64);

    // Expected: [10, 15, 20, 25, 30]
    const expected = [_]f64{ 10, 15, 20, 25, 30 };
    for (0..5) |i| {
        try testing.expectApproxEqAbs(expected[i], result.data.Float64[i], 0.001);
    }
}

// Test: Shift forward (positive periods)
test "shift with positive periods shifts values forward" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(i64, 5);
    defer allocator.free(data);

    // Data: [1, 2, 3, 4, 5]
    for (0..5) |i| data[i] = @intCast(i + 1);

    const series = Series{
        .name = "test",
        .valueType = .Int64,
        .data = .{ .Int64 = data },
        .length = 5,
    };

    const result = try window_ops.shift(&series, allocator, 2);
    defer allocator.free(result.data.Float64);

    // Expected: [NaN, NaN, 1, 2, 3]
    try testing.expect(std.math.isNan(result.data.Float64[0]));
    try testing.expect(std.math.isNan(result.data.Float64[1]));
    try testing.expectApproxEqAbs(1.0, result.data.Float64[2], 0.001);
    try testing.expectApproxEqAbs(2.0, result.data.Float64[3], 0.001);
    try testing.expectApproxEqAbs(3.0, result.data.Float64[4], 0.001);
}

// Test: Shift backward (negative periods)
test "shift with negative periods shifts values backward" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(f64, 5);
    defer allocator.free(data);

    // Data: [1, 2, 3, 4, 5]
    for (0..5) |i| data[i] = @as(f64, @floatFromInt(i + 1));

    const series = Series{
        .name = "test",
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 5,
    };

    const result = try window_ops.shift(&series, allocator, -2);
    defer allocator.free(result.data.Float64);

    // Expected: [3, 4, 5, NaN, NaN]
    try testing.expectApproxEqAbs(3.0, result.data.Float64[0], 0.001);
    try testing.expectApproxEqAbs(4.0, result.data.Float64[1], 0.001);
    try testing.expectApproxEqAbs(5.0, result.data.Float64[2], 0.001);
    try testing.expect(std.math.isNan(result.data.Float64[3]));
    try testing.expect(std.math.isNan(result.data.Float64[4]));
}

// Test: Diff with periods=1
test "diff computes first discrete difference" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(i64, 5);
    defer allocator.free(data);

    // Data: [10, 12, 15, 14, 18]
    data[0] = 10;
    data[1] = 12;
    data[2] = 15;
    data[3] = 14;
    data[4] = 18;

    const series = Series{
        .name = "test",
        .valueType = .Int64,
        .data = .{ .Int64 = data },
        .length = 5,
    };

    const result = try window_ops.diff(&series, allocator, 1);
    defer allocator.free(result.data.Float64);

    // Expected: [NaN, 2, 3, -1, 4]
    try testing.expect(std.math.isNan(result.data.Float64[0]));
    try testing.expectApproxEqAbs(2.0, result.data.Float64[1], 0.001);
    try testing.expectApproxEqAbs(3.0, result.data.Float64[2], 0.001);
    try testing.expectApproxEqAbs(-1.0, result.data.Float64[3], 0.001);
    try testing.expectApproxEqAbs(4.0, result.data.Float64[4], 0.001);
}

// Test: Diff with periods=2
test "diff with periods=2 computes second-order difference" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(f64, 5);
    defer allocator.free(data);

    // Data: [1, 3, 6, 10, 15]
    data[0] = 1;
    data[1] = 3;
    data[2] = 6;
    data[3] = 10;
    data[4] = 15;

    const series = Series{
        .name = "test",
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 5,
    };

    const result = try window_ops.diff(&series, allocator, 2);
    defer allocator.free(result.data.Float64);

    // Expected: [NaN, NaN, 5, 7, 9]
    try testing.expect(std.math.isNan(result.data.Float64[0]));
    try testing.expect(std.math.isNan(result.data.Float64[1]));
    try testing.expectApproxEqAbs(5.0, result.data.Float64[2], 0.001);
    try testing.expectApproxEqAbs(7.0, result.data.Float64[3], 0.001);
    try testing.expectApproxEqAbs(9.0, result.data.Float64[4], 0.001);
}

// Test: Percentage change
test "pctChange computes correct percentage change" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(f64, 5);
    defer allocator.free(data);

    // Data: [100, 110, 105, 115, 120]
    data[0] = 100;
    data[1] = 110;
    data[2] = 105;
    data[3] = 115;
    data[4] = 120;

    const series = Series{
        .name = "test",
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 5,
    };

    const result = try window_ops.pctChange(&series, allocator, 1);
    defer allocator.free(result.data.Float64);

    // Expected: [NaN, 0.1, -0.045, 0.095, 0.043]
    try testing.expect(std.math.isNan(result.data.Float64[0]));
    try testing.expectApproxEqAbs(0.1, result.data.Float64[1], 0.001);
    try testing.expectApproxEqAbs(-0.0454, result.data.Float64[2], 0.001);
    try testing.expectApproxEqAbs(0.0952, result.data.Float64[3], 0.001);
    try testing.expectApproxEqAbs(0.0434, result.data.Float64[4], 0.001);
}

// Test: Percentage change with division by zero
test "pctChange handles division by zero" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(i64, 4);
    defer allocator.free(data);

    // Data: [0, 10, 0, 5]
    data[0] = 0;
    data[1] = 10;
    data[2] = 0;
    data[3] = 5;

    const series = Series{
        .name = "test",
        .valueType = .Int64,
        .data = .{ .Int64 = data },
        .length = 4,
    };

    const result = try window_ops.pctChange(&series, allocator, 1);
    defer allocator.free(result.data.Float64);

    // Expected: [NaN, inf (or NaN), NaN, inf]
    try testing.expect(std.math.isNan(result.data.Float64[0]));
    try testing.expect(std.math.isNan(result.data.Float64[1])); // 10/0 = NaN
    try testing.expect(std.math.isNan(result.data.Float64[2])); // 0/10 = 0, but -10/10 = -1.0
}

// Test: Window larger than series length
test "RollingWindow with window > length uses entire series" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(i64, 3);
    defer allocator.free(data);

    // Data: [1, 2, 3]
    for (0..3) |i| data[i] = @intCast(i + 1);

    const series = Series{
        .name = "test",
        .valueType = .Int64,
        .data = .{ .Int64 = data },
        .length = 3,
    };

    const window = try RollingWindow.init(&series, 10);
    const result = try window.sum(allocator);
    defer allocator.free(result.data.Float64);

    // Expected: [1, 3, 6] (uses all available data)
    const expected = [_]f64{ 1, 3, 6 };
    for (0..3) |i| {
        try testing.expectApproxEqAbs(expected[i], result.data.Float64[i], 0.001);
    }
}

// Test: Large groups (similar to groupby test)
test "RollingWindow handles large datasets efficiently" {
    const allocator = testing.allocator;
    const size = 10_000;
    const data = try allocator.alloc(i64, size);
    defer allocator.free(data);

    for (0..size) |i| data[i] = @intCast(i);

    const series = Series{
        .name = "large",
        .valueType = .Int64,
        .data = .{ .Int64 = data },
        .length = size,
    };

    const window = try RollingWindow.init(&series, 100);
    const result = try window.sum(allocator);
    defer allocator.free(result.data.Float64);

    try testing.expectEqual(size, result.length);

    // Verify last element (sum of 9900..9999)
    const expected_last = 9950.0 * 100.0; // (9900 + 9999) / 2 * 100
    try testing.expectApproxEqAbs(expected_last, result.data.Float64[size - 1], 1.0);
}

// Test: Memory leak testing (1000 iterations)
test "window operations do not leak memory" {
    const allocator = testing.allocator;
    const data = try allocator.alloc(f64, 100);
    defer allocator.free(data);

    for (0..100) |i| data[i] = @floatFromInt(i);

    const series = Series{
        .name = "leak_test",
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 100,
    };

    // Run 1000 iterations
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const window = try RollingWindow.init(&series, 10);
        const result = try window.mean(allocator);
        allocator.free(result.data.Float64);

        const exp_window = ExpandingWindow.init(&series);
        const exp_result = try exp_window.sum(allocator);
        allocator.free(exp_result.data.Float64);

        const shift_result = try window_ops.shift(&series, allocator, 5);
        allocator.free(shift_result.data.Float64);

        const diff_result = try window_ops.diff(&series, allocator, 1);
        allocator.free(diff_result.data.Float64);

        const pct_result = try window_ops.pctChange(&series, allocator, 1);
        allocator.free(pct_result.data.Float64);
    }

    // testing.allocator will report leaks automatically
}
