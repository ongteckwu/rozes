// Benchmark: Lazy Evaluation vs Eager Evaluation
// Measures performance gains from query optimization and lazy evaluation

const std = @import("std");
const rozes = @import("rozes");
const DataFrame = rozes.DataFrame;
const ColumnDesc = rozes.ColumnDesc;
const LazyDataFrame = rozes.LazyDataFrame;
const RowRef = rozes.RowRef;
const BenchmarkResult = @import("benchmark.zig").BenchmarkResult;

/// Helper: Create test DataFrame with numeric columns
fn createTestDataFrame(allocator: std.mem.Allocator, row_count: u32) !DataFrame {
    std.debug.assert(row_count > 0);
    std.debug.assert(row_count <= 10_000_000);

    const col_descs = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("age", .Int64, 0),
        ColumnDesc.init("score", .Float64, 0),
        ColumnDesc.init("salary", .Float64, 0),
        ColumnDesc.init("active", .Bool, 0),
    };

    var df = try DataFrame.create(allocator, &col_descs, row_count);

    // Fill with test data
    const id_data = df.columns[0].data.Int64;
    const age_data = df.columns[1].data.Int64;
    const score_data = df.columns[2].data.Float64;
    const salary_data = df.columns[3].data.Float64;
    const active_data = df.columns[4].data.Bool;

    var i: u32 = 0;
    while (i < row_count) : (i += 1) {
        id_data[i] = @as(i64, @intCast(i));
        age_data[i] = @as(i64, @intCast(20 + (i % 50)));
        score_data[i] = @as(f64, @floatFromInt(50 + (i % 100)));
        salary_data[i] = @as(f64, @floatFromInt(30000 + (i % 70000)));
        active_data[i] = (i % 3 != 0);
    }

    df.row_count = row_count;
    return df;
}

// Filter predicate: age > 35
fn filterAgeOver35(row: RowRef) bool {
    const age = row.getInt64("age") orelse return false;
    return age > 35;
}

/// Benchmark: Eager evaluation (no optimization)
pub fn benchmarkEagerChain(allocator: std.mem.Allocator, row_count: u32) !BenchmarkResult {
    std.debug.assert(row_count > 0);
    std.debug.assert(row_count <= 10_000_000);

    const iterations: u32 = if (row_count >= 1_000_000) 3 else if (row_count >= 100_000) 10 else 50;

    var total_ns: u64 = 0;
    var iter: u32 = 0;

    while (iter < iterations) : (iter += 1) {
        var df = try createTestDataFrame(allocator, row_count);
        defer df.deinit();

        const start = std.time.nanoTimestamp();

        // Eager: Execute operations immediately in suboptimal order
        // 1. Select (projects columns - processes all rows)
        const columns = [_][]const u8{ "age", "score", "salary" };
        var selected = try df.select(&columns);
        defer selected.deinit();

        // 2. Filter (reduces rows - but already projected)
        var filtered = try selected.filter(filterAgeOver35);
        defer filtered.deinit();

        // 3. Limit (takes first N rows)
        var limited = try filtered.head(allocator, 100);
        defer limited.deinit();

        const end = std.time.nanoTimestamp();
        total_ns += @as(u64, @intCast(end - start));

        // Verify result
        std.debug.assert(limited.row_count <= 100);
        std.debug.assert(limited.columns.len == 3);
    }

    const avg_ns = total_ns / iterations;
    const duration_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;

    return BenchmarkResult{
        .name = "Eager Chain",
        .duration_ms = duration_ms,
        .iterations = iterations,
        .rows_processed = row_count,
    };
}

/// Benchmark: Lazy evaluation with optimization
pub fn benchmarkLazyChain(allocator: std.mem.Allocator, row_count: u32) !BenchmarkResult {
    std.debug.assert(row_count > 0);
    std.debug.assert(row_count <= 10_000_000);

    const iterations: u32 = if (row_count >= 1_000_000) 3 else if (row_count >= 100_000) 10 else 50;

    var total_ns: u64 = 0;
    var iter: u32 = 0;

    while (iter < iterations) : (iter += 1) {
        var df = try createTestDataFrame(allocator, row_count);
        defer df.deinit();

        const start = std.time.nanoTimestamp();

        // Lazy: Build query plan (optimized order)
        var lazy = LazyDataFrame.init(allocator, &df);
        defer lazy.deinit();

        // Add operations in suboptimal order
        const columns = [_][]const u8{ "age", "score", "salary" };
        try lazy.select(&columns);
        try lazy.filter(filterAgeOver35);
        try lazy.limit(100);

        // Execute optimized plan
        var result = try lazy.collect();
        defer result.deinit();

        const end = std.time.nanoTimestamp();
        total_ns += @as(u64, @intCast(end - start));

        // Verify result
        std.debug.assert(result.row_count <= 100);
        std.debug.assert(result.columns.len == 3);
    }

    const avg_ns = total_ns / iterations;
    const duration_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;

    return BenchmarkResult{
        .name = "Lazy Chain (Optimized)",
        .duration_ms = duration_ms,
        .iterations = iterations,
        .rows_processed = row_count,
    };
}

/// Benchmark: Complex chained operations (5+ ops)
pub fn benchmarkComplexChain(allocator: std.mem.Allocator, row_count: u32, lazy: bool) !BenchmarkResult {
    std.debug.assert(row_count > 0);
    std.debug.assert(row_count <= 10_000_000);

    const iterations: u32 = if (row_count >= 1_000_000) 3 else if (row_count >= 100_000) 10 else 20;
    const name = if (lazy) "Complex Lazy Chain" else "Complex Eager Chain";

    var total_ns: u64 = 0;
    var iter: u32 = 0;

    while (iter < iterations) : (iter += 1) {
        var df = try createTestDataFrame(allocator, row_count);
        defer df.deinit();

        const start = std.time.nanoTimestamp();

        if (lazy) {
            // Lazy execution
            var lazy_df = LazyDataFrame.init(allocator, &df);
            defer lazy_df.deinit();

            const cols1 = [_][]const u8{ "id", "age", "score", "salary" };
            try lazy_df.select(&cols1);
            try lazy_df.filter(filterAgeOver35);

            const cols2 = [_][]const u8{ "age", "score" };
            try lazy_df.select(&cols2);
            try lazy_df.limit(50);

            var result = try lazy_df.collect();
            defer result.deinit();

            std.debug.assert(result.row_count <= 50);
        } else {
            // Eager execution
            const cols1 = [_][]const u8{ "id", "age", "score", "salary" };
            var selected1 = try df.select(&cols1);
            defer selected1.deinit();

            var filtered = try selected1.filter(filterAgeOver35);
            defer filtered.deinit();

            const cols2 = [_][]const u8{ "age", "score" };
            var selected2 = try filtered.select(&cols2);
            defer selected2.deinit();

            var limited = try selected2.head(allocator, 50);
            defer limited.deinit();

            std.debug.assert(limited.row_count <= 50);
        }

        const end = std.time.nanoTimestamp();
        total_ns += @as(u64, @intCast(end - start));
    }

    const avg_ns = total_ns / iterations;
    const duration_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;

    return BenchmarkResult{
        .name = name,
        .duration_ms = duration_ms,
        .iterations = iterations,
        .rows_processed = row_count,
    };
}

/// Compare lazy vs eager for different dataset sizes
pub fn benchmarkLazyVsEager(allocator: std.mem.Allocator) !void {
    std.debug.print("\n━━━ Lazy Evaluation Benchmarks ━━━\n\n", .{});

    const sizes = [_]u32{ 10_000, 100_000, 1_000_000 };

    for (sizes) |size| {
        std.debug.print("Dataset: {} rows\n", .{size});

        // Eager evaluation
        const eager = try benchmarkEagerChain(allocator, size);
        eager.print("  Eager");

        // Lazy evaluation
        const lazy = try benchmarkLazyChain(allocator, size);
        lazy.print("  Lazy");

        // Calculate speedup
        const speedup = eager.duration_ms / lazy.duration_ms;
        std.debug.print("  Speedup: {d:.2}×\n\n", .{speedup});
    }

    std.debug.print("━━━ Complex Chain Benchmarks ━━━\n\n", .{});

    for (sizes) |size| {
        std.debug.print("Dataset: {} rows (5+ operations)\n", .{size});

        const eager = try benchmarkComplexChain(allocator, size, false);
        eager.print("  Eager");

        const lazy = try benchmarkComplexChain(allocator, size, true);
        lazy.print("  Lazy");

        const speedup = eager.duration_ms / lazy.duration_ms;
        std.debug.print("  Speedup: {d:.2}×\n\n", .{speedup});
    }
}
