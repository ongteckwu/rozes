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
    {
        std.debug.print("Running inner join (10K × 10K rows)...\n", .{});
        const result = try ops_bench.benchmarkJoin(allocator, 10_000, 10_000);
        result.print("Inner Join (10K × 10K rows)");
        join_10k_ms = result.duration_ms;
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

    // Performance Target Comparison
    std.debug.print("━━━ Performance Target Comparison ━━━\n\n", .{});

    const comparisons = [_]bench.Comparison{
        bench.Comparison.check("CSV Parse (1M rows)", 3000.0, csv_1m_ms),
        bench.Comparison.check("Filter (1M rows)", 100.0, filter_1m_ms),
        bench.Comparison.check("Sort (100K rows)", 100.0, sort_100k_ms),
        bench.Comparison.check("GroupBy (100K rows)", 300.0, groupby_100k_ms),
        bench.Comparison.check("Join (10K × 10K)", 500.0, join_10k_ms),
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
        std.debug.print("⚠️  Some targets not met (optimization needed)\n", .{});
    }

    std.debug.print("\n", .{});
}
