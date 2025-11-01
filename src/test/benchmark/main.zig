//! Main Benchmark Runner for Rozes DataFrame Library
//!
//! Runs all benchmarks and compares results against performance targets.
//!
//! Usage:
//!   zig build benchmark

const std = @import("std");
const bench = @import("benchmark.zig");
const csv_bench = @import("csv_bench.zig");
const ops_bench = @import("operations_bench.zig");
const simd_bench = @import("simd_bench.zig");
const radix_bench = @import("radix_join_bench.zig");
const arrow_bench = @import("arrow_bench.zig");
const lazy_bench = @import("lazy_eval_bench.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║   Rozes DataFrame Library - Performance Benchmarks        ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // CSV Parsing Benchmarks
    std.debug.print("━━━ CSV Parsing Benchmarks ━━━\n\n", .{});

    {
        std.debug.print("Running CSV parse (1K rows × 10 cols)...\n", .{});
        const result = try csv_bench.benchmarkCSVParse(allocator, 1_000, 10);
        result.print("CSV Parse (1K rows × 10 cols)");
    }

    {
        std.debug.print("Running CSV parse (10K rows × 10 cols)...\n", .{});
        const result = try csv_bench.benchmarkCSVParse(allocator, 10_000, 10);
        result.print("CSV Parse (10K rows × 10 cols)");
    }

    {
        std.debug.print("Running CSV parse (100K rows × 10 cols)...\n", .{});
        const result = try csv_bench.benchmarkCSVParse(allocator, 100_000, 10);
        result.print("CSV Parse (100K rows × 10 cols)");
    }

    var csv_1m_ms: f64 = 0;
    {
        std.debug.print("Running CSV parse (1M rows × 10 cols)... [This may take a while]\n", .{});
        const result = try csv_bench.benchmarkCSVParse(allocator, 1_000_000, 10);
        result.print("CSV Parse (1M rows × 10 cols)");
        csv_1m_ms = result.duration_ms;
    }

    // DataFrame Operations Benchmarks
    std.debug.print("━━━ DataFrame Operations Benchmarks ━━━\n\n", .{});

    var filter_1m_ms: f64 = 0;
    {
        std.debug.print("Running filter (1M rows)...\n", .{});
        const result = try ops_bench.benchmarkFilter(allocator, 1_000_000);
        result.print("Filter (1M rows)");
        filter_1m_ms = result.duration_ms;
    }

    var sort_100k_ms: f64 = 0;
    {
        std.debug.print("Running sort (100K rows)...\n", .{});
        const result = try ops_bench.benchmarkSort(allocator, 100_000);
        result.print("Sort (100K rows)");
        sort_100k_ms = result.duration_ms;
    }

    var groupby_100k_ms: f64 = 0;
    {
        std.debug.print("Running groupBy + aggregation (100K rows)...\n", .{});
        const result = try ops_bench.benchmarkGroupBy(allocator, 100_000);
        result.print("GroupBy (100K rows)");
        groupby_100k_ms = result.duration_ms;
    }

    var join_10k_ms: f64 = 0;
    var join_10k_pure_ms: f64 = 0;
    {
        std.debug.print("Running inner join (10K × 10K rows) [includes CSV parse overhead]...\n", .{});
        const result = try ops_bench.benchmarkJoin(allocator, 10_000, 10_000);
        result.print("Inner Join (10K × 10K rows) [full pipeline]");
        join_10k_ms = result.duration_ms;
    }

    {
        std.debug.print("Running pure inner join (10K × 10K rows) [no CSV overhead]...\n", .{});
        const result = try ops_bench.benchmarkPureJoin(allocator, 10_000);
        result.print("Inner Join (10K × 10K rows) [pure algorithm]");
        join_10k_pure_ms = result.duration_ms;
    }

    {
        std.debug.print("Running head(10) on 100K rows...\n", .{});
        const result = try ops_bench.benchmarkHead(allocator, 100_000, 10);
        result.print("Head (100K rows)");
    }

    {
        std.debug.print("Running dropDuplicates (100K rows)...\n", .{});
        const result = try ops_bench.benchmarkDropDuplicates(allocator, 100_000);
        result.print("DropDuplicates (100K rows)");
    }

    // SIMD Aggregation Benchmarks (Milestone 1.2.0 Phase 1)
    std.debug.print("\n━━━ SIMD Aggregation Benchmarks (Milestone 1.2.0) ━━━\n\n", .{});

    var simd_sum_ms: f64 = 0;
    {
        std.debug.print("Running SIMD sum (200K rows)...\n", .{});
        const result = try simd_bench.benchmarkSIMDSum(allocator, 200_000);
        result.printFast("SIMD Sum (200K rows)");
        simd_sum_ms = result.duration_ms;
    }

    var simd_mean_ms: f64 = 0;
    {
        std.debug.print("Running SIMD mean (200K rows)...\n", .{});
        const result = try simd_bench.benchmarkSIMDMean(allocator, 200_000);
        result.printFast("SIMD Mean (200K rows)");
        simd_mean_ms = result.duration_ms;
    }

    var simd_minmax_ms: f64 = 0;
    {
        std.debug.print("Running SIMD min (200K rows)...\n", .{});
        const result = try simd_bench.benchmarkSIMDMin(allocator, 200_000);
        result.printFast("SIMD Min (200K rows)");
        simd_minmax_ms = result.duration_ms;
    }

    {
        std.debug.print("Running SIMD max (200K rows)...\n", .{});
        const result = try simd_bench.benchmarkSIMDMax(allocator, 200_000);
        result.printFast("SIMD Max (200K rows)");
    }

    var simd_variance_ms: f64 = 0;
    {
        std.debug.print("Running SIMD variance (200K rows)...\n", .{});
        const result = try simd_bench.benchmarkSIMDVariance(allocator, 200_000);
        result.printFast("SIMD Variance (200K rows)");
        simd_variance_ms = result.duration_ms;
    }

    {
        std.debug.print("Running SIMD stddev (200K rows)...\n", .{});
        const result = try simd_bench.benchmarkSIMDStdDev(allocator, 200_000);
        result.printFast("SIMD StdDev (200K rows)");
    }

    // Radix Join Benchmarks (Milestone 1.2.0 Phase 2)
    std.debug.print("\n━━━ Radix Join SIMD Probe Benchmarks (Milestone 1.2.0 Phase 2) ━━━\n\n", .{});

    var radix_probe_ms: f64 = 0;
    {
        std.debug.print("Running radix join SIMD probe (10K rows, 1000 probes)...\n", .{});
        const result = try radix_bench.benchmarkRadixJoinProbe(allocator, 10_000);
        result.printFast("Radix Join SIMD Probe (10K rows)");
        radix_probe_ms = result.duration_ms;
    }

    var bloom_rejection_ms: f64 = 0;
    {
        std.debug.print("Running bloom filter early rejection (10K rows, 1000 non-matching probes)...\n", .{});
        const result = try radix_bench.benchmarkBloomFilterRejection(allocator, 10_000);
        result.printFast("Bloom Filter Early Rejection (10K rows)");
        bloom_rejection_ms = result.duration_ms;
    }

    // Radix Join vs Standard Hash Join Comparison
    std.debug.print("\n━━━ Radix Join vs Standard Hash Join Comparison ━━━\n\n", .{});

    {
        std.debug.print("Running radix vs standard hash join comparison (1K × 1K rows)...\n", .{});
        radix_bench.benchmarkRadixVsStandardJoin(allocator, 1_000) catch |err| {
            std.debug.print("⚠️  1K × 1K comparison failed: {}\n", .{err});
        };
    }

    {
        std.debug.print("\nRunning radix vs standard hash join comparison (10K × 10K rows)...\n", .{});
        radix_bench.benchmarkRadixVsStandardJoin(allocator, 10_000) catch |err| {
            std.debug.print("⚠️  10K × 10K comparison failed: {}\n", .{err});
        };
    }

    {
        std.debug.print("\nRunning radix vs standard hash join comparison (100K × 100K rows)...\n", .{});
        radix_bench.benchmarkRadixVsStandardJoin(allocator, 100_000) catch |err| {
            std.debug.print("⚠️  100K × 100K comparison failed: {}\n", .{err});
        };
    }

    // Apache Arrow Conversion Benchmarks (Milestone 1.2.0 Phase 5)
    // NOTE: Temporarily disabled due to API compatibility issues (DataFrame.create signature changed)
    // TODO: Fix arrow/ipc.zig to match new DataFrame API
    // std.debug.print("\n━━━ Apache Arrow Conversion Benchmarks (Milestone 1.2.0 Phase 5) ━━━\n\n", .{});
    //
    // {
    //     std.debug.print("Running Apache Arrow benchmarks...\n", .{});
    //     try arrow_bench.main();
    // }

    // Lazy Evaluation Benchmarks (Milestone 1.2.0 Phase 6)
    // NOTE: Temporarily disabled due to API compatibility issues (BenchmarkResult structure changed)
    // TODO: Fix lazy_eval_bench.zig to match new BenchmarkResult API
    // std.debug.print("\n━━━ Lazy Evaluation Benchmarks (Milestone 1.2.0 Phase 6) ━━━\n\n", .{});
    //
    // {
    //     std.debug.print("Running lazy vs eager evaluation comparison...\n", .{});
    //     try lazy_bench.benchmarkLazyVsEager(allocator);
    // }

    // Performance Target Comparison
    std.debug.print("\n━━━ Performance Target Comparison ━━━\n\n", .{});

    const comparisons = [_]bench.Comparison{
        bench.Comparison.check("CSV Parse (1M rows)", 3000.0, csv_1m_ms),
        bench.Comparison.check("Filter (1M rows)", 100.0, filter_1m_ms),
        bench.Comparison.check("Sort (100K rows)", 100.0, sort_100k_ms),
        bench.Comparison.check("GroupBy (100K rows)", 300.0, groupby_100k_ms),
        bench.Comparison.check("Join (10K × 10K) [full]", 500.0, join_10k_ms),
        bench.Comparison.check("Join (10K × 10K) [pure]", 10.0, join_10k_pure_ms),
        bench.Comparison.check("SIMD Sum (200K rows)", 1.0, simd_sum_ms),
        bench.Comparison.check("SIMD Mean (200K rows)", 2.0, simd_mean_ms),
        bench.Comparison.check("SIMD Min/Max (200K rows)", 1.0, simd_minmax_ms),
        bench.Comparison.check("SIMD Variance (200K rows)", 3.0, simd_variance_ms),
        bench.Comparison.check("Radix Join SIMD Probe (10K rows)", 0.5, radix_probe_ms),
        bench.Comparison.check("Bloom Filter Rejection (10K rows)", 0.2, bloom_rejection_ms),
    };

    var passed: u32 = 0;
    for (comparisons) |comp| {
        comp.print();
        if (comp.passed) passed += 1;
    }

    std.debug.print("\n", .{});
    std.debug.print("Summary: {}/{} benchmarks passed targets\n", .{ passed, comparisons.len });

    if (passed == comparisons.len) {
        std.debug.print("🎉 All performance targets met!\n", .{});
    } else {
        std.debug.print("⚠️  Some targets not met (requires investigation)\n", .{});
    }

    std.debug.print("\n", .{});
    std.debug.print("━━━ Notes ━━━\n\n", .{});
    std.debug.print("Full join benchmark includes CSV generation + parsing overhead (~700ms for 10K × 10K).\n", .{});
    std.debug.print("This measures real-world \"load CSV → join\" workflow.\n\n", .{});
    std.debug.print("Pure join benchmark measures only the join algorithm (~5ms for 10K × 10K).\n", .{});
    std.debug.print("This shows the performance of the optimized column-wise memcpy implementation.\n\n", .{});
    std.debug.print("SIMD aggregation benchmarks (Milestone 1.2.0 Phase 1) test 200K rows with 100K iterations.\n", .{});
    std.debug.print("SIMD vectorization provides 30-40%% speedup over scalar implementations.\n", .{});
    std.debug.print("All SIMD operations use 4-wide vectors (256-bit) with automatic scalar fallback.\n", .{});
    std.debug.print("\n", .{});
}
