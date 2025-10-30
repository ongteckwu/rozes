const std = @import("std");
const rozes = @import("rozes");
const DataFrame = rozes.DataFrame;
const ColumnDesc = rozes.ColumnDesc;
const join_mod = rozes;

/// Benchmark join performance with column-wise memcpy optimization
///
/// **Baseline** (before optimization): 593ms for 100K × 100K join
/// **Target** (after optimization): <500ms
/// **Expected improvement**: 15-20% (5× faster data copying for left columns)
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Join Performance Benchmark ===\n", .{});
    std.debug.print("Optimization: Column-wise memcpy for sequential access\n", .{});
    std.debug.print("See docs/join_optimization_recommendation.md\n\n", .{});

    // Test 1: Small join (10K × 10K)
    try benchmarkJoin(allocator, 10_000, "10K × 10K");

    // Test 2: Medium join (50K × 50K)
    try benchmarkJoin(allocator, 50_000, "50K × 50K");

    // Test 3: Large join (100K × 100K) - THE ACTUAL BENCHMARK
    try benchmarkJoin(allocator, 100_000, "100K × 100K");

    std.debug.print("\n=== Benchmark Complete ===\n", .{});
}

fn benchmarkJoin(allocator: std.mem.Allocator, row_count: u32, label: []const u8) !void {
    std.debug.print("Test: {s} join\n", .{label});
    std.debug.print("-----------------------------\n", .{});

    // Create left DataFrame
    const left_cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("left_val1", .Float64, 1),
        ColumnDesc.init("left_val2", .Int64, 2),
        ColumnDesc.init("left_active", .Bool, 3),
    };

    var left = try DataFrame.create(allocator, &left_cols, row_count);
    defer left.deinit();

    const left_ids = left.columns[0].asInt64Buffer() orelse unreachable;
    const left_val1 = left.columns[1].asFloat64Buffer() orelse unreachable;
    const left_val2 = left.columns[2].asInt64Buffer() orelse unreachable;
    const left_active = left.columns[3].asBoolBuffer() orelse unreachable;

    var i: u32 = 0;
    while (i < row_count) : (i += 1) {
        left_ids[i] = @intCast(i);
        left_val1[i] = @as(f64, @floatFromInt(i)) * 1.5;
        left_val2[i] = @intCast(i * 10);
        left_active[i] = (i % 2) == 0;
    }
    try left.setRowCount(row_count);

    // Create right DataFrame
    const right_cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("right_val1", .Int64, 1),
        ColumnDesc.init("right_val2", .Float64, 2),
    };

    var right = try DataFrame.create(allocator, &right_cols, row_count);
    defer right.deinit();

    const right_ids = right.columns[0].asInt64Buffer() orelse unreachable;
    const right_val1 = right.columns[1].asInt64Buffer() orelse unreachable;
    const right_val2 = right.columns[2].asFloat64Buffer() orelse unreachable;

    i = 0;
    while (i < row_count) : (i += 1) {
        right_ids[i] = @intCast(i);
        right_val1[i] = @intCast(i * 2);
        right_val2[i] = @as(f64, @floatFromInt(i)) * 2.5;
    }
    try right.setRowCount(row_count);

    // Perform join with timing
    const join_cols = [_][]const u8{"id"};

    const start = std.time.nanoTimestamp();
    var result = try left.innerJoin(allocator, &right, &join_cols);
    const end = std.time.nanoTimestamp();
    defer result.deinit();

    const duration_ns: u64 = @intCast(end - start);
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    std.debug.print("  Duration: {d:.2}ms\n", .{duration_ms});
    std.debug.print("  Result rows: {}\n", .{result.row_count});
    std.debug.print("  Result cols: {}\n", .{result.columns.len});

    if (row_count == 100_000) {
        const target_ms: f64 = 500.0;
        const baseline_ms: f64 = 593.0;

        std.debug.print("\n  Baseline: {d:.0}ms\n", .{baseline_ms});
        std.debug.print("  Target: <{d:.0}ms\n", .{target_ms});

        if (duration_ms < target_ms) {
            const improvement = (baseline_ms - duration_ms) / baseline_ms * 100.0;
            std.debug.print("  ✓ PASS ({d:.1}% faster than baseline)\n", .{improvement});
        } else {
            const over = (duration_ms - target_ms) / target_ms * 100.0;
            std.debug.print("  ✗ FAIL ({d:.1}% over target)\n", .{over});
        }
    }

    std.debug.print("\n", .{});
}
