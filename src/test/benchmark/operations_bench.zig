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
///
/// **NOTE**: This benchmark includes CSV generation + parsing overhead for creating
/// test DataFrames (~350ms per 10K DataFrame = ~700ms total for 10K × 10K).
/// For join-only performance, see `src/profiling_tools/benchmark_join.zig` which
/// shows actual join operation is ~5ms for 10K × 10K.
///
/// **Why measure with CSV overhead?**
/// - Represents real-world workflow: user loads CSV → performs join
/// - Tests full pipeline: parse → join → result
/// - Useful for end-to-end performance comparison
pub fn benchmarkJoin(
    allocator: std.mem.Allocator,
    left_rows: u32,
    right_rows: u32,
) !BenchmarkResult {
    std.debug.assert(left_rows > 0); // Pre-condition #1
    std.debug.assert(right_rows > 0); // Pre-condition #2

    // START TIMING: Includes DataFrame creation (CSV gen + parse)
    // This is intentional - measures real-world "load CSV and join" workflow
    const start = std.time.nanoTimestamp();

    // Create two DataFrames (via CSV - includes parsing overhead)
    var df1 = try createTestDataFrame(allocator, left_rows);
    defer df1.deinit();

    var df2 = try createTestDataFrame(allocator, right_rows);
    defer df2.deinit();

    // Perform join
    const join_cols = [_][]const u8{"name"};
    var joined = try df1.innerJoin(allocator, &df2, &join_cols);
    defer joined.deinit();

    const end = std.time.nanoTimestamp();

    // Verify we got join results
    std.debug.assert(joined.row_count > 0); // Post-condition

    // Use total processed rows for throughput (left + right)
    const total_rows = left_rows + right_rows;
    return BenchmarkResult.compute(start, end, total_rows);
}

/// Benchmark pure inner join (no CSV overhead)
///
/// This measures ONLY the join algorithm performance, excluding CSV generation/parsing.
/// Creates DataFrames directly in memory for accurate join-only timing.
///
/// **Use this to measure**:
/// - Join algorithm optimization (e.g., column-wise memcpy vs row-by-row)
/// - Hash table performance
/// - Memory copy efficiency
///
/// **Target**: <10ms for 10K × 10K join
pub fn benchmarkPureJoin(
    allocator: std.mem.Allocator,
    row_count: u32,
) !BenchmarkResult {
    std.debug.assert(row_count > 0); // Pre-condition

    // Create left DataFrame directly (no CSV)
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

    // Create right DataFrame directly (no CSV)
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

    // START TIMING: Pure join algorithm only
    const start = std.time.nanoTimestamp();

    // Perform join
    const join_cols = [_][]const u8{"id"};
    var joined = try left.innerJoin(allocator, &right, &join_cols);
    defer joined.deinit();

    const end = std.time.nanoTimestamp();

    // Verify we got join results
    std.debug.assert(joined.row_count == row_count); // Post-condition: 1:1 join
    std.debug.assert(joined.columns.len == left_cols.len + right_cols.len - 1); // Post-condition: all columns minus duplicate key

    // Use total processed rows for throughput (left + right)
    const total_rows = row_count * 2;
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
