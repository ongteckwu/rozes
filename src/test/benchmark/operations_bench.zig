//! DataFrame Operations Benchmarks
//!
//! Measures performance of filter, sort, groupBy, join operations.

const std = @import("std");
const bench = @import("benchmark.zig");
const rozes = @import("rozes");
const DataFrame = rozes.DataFrame;
const RowRef = rozes.RowRef;
const CSVParser = rozes.CSVParser;
const ColumnDesc = rozes.types.ColumnDesc;
const SortOrder = rozes.SortOrder;
const AggFunc = rozes.AggFunc;
const AggSpec = rozes.AggSpec;

const BenchmarkResult = bench.BenchmarkResult;

/// Helper: Create test DataFrame for benchmarks
fn createTestDataFrame(
    allocator: std.mem.Allocator,
    rows: u32,
) !DataFrame {
    std.debug.assert(rows > 0); // Pre-condition

    const csv = try bench.generateMixedCSV(allocator, rows);
    defer allocator.free(csv);

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    return try parser.toDataFrame();
}

/// Filter predicate: score > 50.0
fn filterScoreOver50(row: RowRef) bool {
    const score = row.getFloat64("score") orelse return false;
    return score > 50.0;
}

/// Benchmark filter operation
pub fn benchmarkFilter(
    allocator: std.mem.Allocator,
    rows: u32,
) !BenchmarkResult {
    std.debug.assert(rows > 0); // Pre-condition

    var df = try createTestDataFrame(allocator, rows);
    defer df.deinit();

    const start = std.time.nanoTimestamp();

    var filtered = try df.filter(filterScoreOver50);
    defer filtered.deinit();

    const end = std.time.nanoTimestamp();

    // Verify we got some results
    std.debug.assert(filtered.row_count > 0); // Post-condition
    std.debug.assert(filtered.row_count < rows); // Post-condition


    return BenchmarkResult.compute(start, end, rows);
}

/// Benchmark sort operation (single column)
pub fn benchmarkSort(
    allocator: std.mem.Allocator,
    rows: u32,
) !BenchmarkResult {
    std.debug.assert(rows > 0); // Pre-condition

    var df = try createTestDataFrame(allocator, rows);
    defer df.deinit();

    const start = std.time.nanoTimestamp();

    var sorted = try df.sort(allocator, "score", .Ascending);
    defer sorted.deinit();

    const end = std.time.nanoTimestamp();

    // Verify row count matches
    std.debug.assert(sorted.row_count == rows); // Post-condition


    return BenchmarkResult.compute(start, end, rows);
}

/// Benchmark groupBy + aggregation
pub fn benchmarkGroupBy(
    allocator: std.mem.Allocator,
    rows: u32,
) !BenchmarkResult {
    std.debug.assert(rows > 0); // Pre-condition

    var df = try createTestDataFrame(allocator, rows);
    defer df.deinit();

    const start = std.time.nanoTimestamp();

    var grouped = try df.groupBy(allocator, "name");
    defer grouped.deinit();

    const agg_specs = [_]AggSpec{
        .{ .column = "score", .func = .Mean },
        .{ .column = "id", .func = .Count },
    };

    var result = try grouped.agg(allocator, &agg_specs);
    defer result.deinit();

    const end = std.time.nanoTimestamp();

    // Verify we got grouped results
    std.debug.assert(result.row_count > 0); // Post-condition
    std.debug.assert(result.row_count <= 5); // Post-condition: max 5 unique names


    return BenchmarkResult.compute(start, end, rows);
}

/// Benchmark inner join
pub fn benchmarkJoin(
    allocator: std.mem.Allocator,
    left_rows: u32,
    right_rows: u32,
) !BenchmarkResult {
    std.debug.assert(left_rows > 0); // Pre-condition #1
    std.debug.assert(right_rows > 0); // Pre-condition #2

    // Create two DataFrames
    var df1 = try createTestDataFrame(allocator, left_rows);
    defer df1.deinit();

    var df2 = try createTestDataFrame(allocator, right_rows);
    defer df2.deinit();

    const start = std.time.nanoTimestamp();

    const join_cols = [_][]const u8{"name"};
    var joined = try df1.innerJoin(allocator, &df2, &join_cols);
    defer joined.deinit();

    const end = std.time.nanoTimestamp();

    // Verify we got join results
    std.debug.assert(joined.row_count > 0); // Post-condition


    // Use total processed rows for throughput
    const total_rows = left_rows + right_rows;
    return BenchmarkResult.compute(start, end, total_rows);
}

/// Benchmark head() operation
pub fn benchmarkHead(
    allocator: std.mem.Allocator,
    rows: u32,
    n: u32,
) !BenchmarkResult {
    std.debug.assert(rows > 0); // Pre-condition #1
    std.debug.assert(n > 0); // Pre-condition #2

    var df = try createTestDataFrame(allocator, rows);
    defer df.deinit();

    const start = std.time.nanoTimestamp();

    var head = try df.head(allocator, n);
    defer head.deinit();

    const end = std.time.nanoTimestamp();

    // Verify result
    std.debug.assert(head.row_count == @min(n, rows)); // Post-condition


    return BenchmarkResult.compute(start, end, rows);
}

/// Benchmark dropDuplicates() operation
pub fn benchmarkDropDuplicates(
    allocator: std.mem.Allocator,
    rows: u32,
) !BenchmarkResult {
    std.debug.assert(rows > 0); // Pre-condition

    var df = try createTestDataFrame(allocator, rows);
    defer df.deinit();

    const start = std.time.nanoTimestamp();

    const subset = [_][]const u8{"name"};
    var deduped = try df.dropDuplicates(allocator, &subset);
    defer deduped.deinit();

    const end = std.time.nanoTimestamp();

    // Verify deduplication happened
    std.debug.assert(deduped.row_count <= rows); // Post-condition
    std.debug.assert(deduped.row_count <= 5); // Post-condition: max 5 unique names


    return BenchmarkResult.compute(start, end, rows);
}
