//! CSV Parsing Benchmarks
//!
//! Measures CSV parsing performance for various file sizes and column counts.

const std = @import("std");
const bench = @import("benchmark.zig");
const rozes = @import("rozes");
const DataFrame = rozes.DataFrame;
const CSVParser = rozes.CSVParser;
const types = rozes.types;

const BenchmarkResult = bench.BenchmarkResult;

/// Benchmark CSV parsing with numeric data
///
/// Args:
///   - allocator: Memory allocator
///   - rows: Number of rows to parse
///   - cols: Number of columns
///
/// Returns: Benchmark result with timing and throughput
pub fn benchmarkCSVParse(
    allocator: std.mem.Allocator,
    rows: u32,
    cols: u32,
) !BenchmarkResult {
    std.debug.assert(rows > 0); // Pre-condition #1
    std.debug.assert(cols > 0); // Pre-condition #2

    // Generate test CSV
    const csv = try bench.generateCSV(allocator, rows, cols);
    defer allocator.free(csv);

    // Benchmark parsing
    const start = std.time.nanoTimestamp();

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const end = std.time.nanoTimestamp();

    // Verify correctness
    std.debug.assert(df.row_count == rows); // Post-condition #1
    std.debug.assert(df.columns.len == cols); // Post-condition #2

    return BenchmarkResult.compute(start, end, rows);
}

/// Benchmark CSV parsing with mixed types
pub fn benchmarkCSVParseMixed(
    allocator: std.mem.Allocator,
    rows: u32,
) !BenchmarkResult {
    std.debug.assert(rows > 0); // Pre-condition #1

    // Generate mixed-type CSV
    const csv = try bench.generateMixedCSV(allocator, rows);
    defer allocator.free(csv);

    // Benchmark parsing
    const start = std.time.nanoTimestamp();

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const end = std.time.nanoTimestamp();

    // Verify correctness
    std.debug.assert(df.row_count == rows); // Post-condition #1
    std.debug.assert(df.columns.len == 4); // Post-condition #2: id, score, name, active

    return BenchmarkResult.compute(start, end, rows);
}

/// Benchmark type inference overhead
pub fn benchmarkTypeInference(
    allocator: std.mem.Allocator,
    rows: u32,
) !BenchmarkResult {
    std.debug.assert(rows > 0); // Pre-condition

    // Generate CSV that triggers type inference
    const csv = try bench.generateMixedCSV(allocator, rows);
    defer allocator.free(csv);

    // Benchmark just the type inference phase
    const start = std.time.nanoTimestamp();

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    // Parse rows (this includes type inference)
    _ = try parser.toDataFrame();

    const end = std.time.nanoTimestamp();


    return BenchmarkResult.compute(start, end, rows);
}
