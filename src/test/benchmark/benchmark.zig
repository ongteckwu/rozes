//! Benchmark Infrastructure for Rozes DataFrame Library
//!
//! Provides timing utilities and result formatting for performance benchmarks.
//! All benchmarks should use ReleaseFast optimization mode for accurate results.

const std = @import("std");

/// Result of a benchmark run
pub const BenchmarkResult = struct {
    duration_ns: u64,
    duration_ms: f64,
    throughput: f64, // rows/sec or operations/sec
    row_count: u32,

    /// Computes result from start/end timestamps
    pub fn compute(
        start_ns: i128,
        end_ns: i128,
        row_count: u32,
    ) BenchmarkResult {
        std.debug.assert(end_ns >= start_ns); // Pre-condition #1
        std.debug.assert(row_count > 0); // Pre-condition #2

        const duration_ns: u64 = @intCast(end_ns - start_ns);
        const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
        const duration_sec = duration_ms / 1000.0;
        const throughput = @as(f64, @floatFromInt(row_count)) / duration_sec;

        std.debug.assert(duration_ms > 0); // Post-condition #1
        std.debug.assert(throughput > 0); // Post-condition #2

        return BenchmarkResult{
            .duration_ns = duration_ns,
            .duration_ms = duration_ms,
            .throughput = throughput,
            .row_count = row_count,
        };
    }

    /// Prints benchmark result in standardized format
    pub fn print(self: BenchmarkResult, name: []const u8) void {
        std.debug.assert(self.duration_ms > 0); // Pre-condition #1
        std.debug.assert(self.throughput > 0); // Pre-condition #2

        std.debug.print("{s}:\n", .{name});
        std.debug.print("  Duration: {d:.2}ms\n", .{self.duration_ms});
        std.debug.print("  Throughput: {d:.0} rows/sec\n", .{self.throughput});
        std.debug.print("  Row Count: {}\n\n", .{self.row_count});
    }
};

/// Generates test CSV data
///
/// Args:
///   - allocator: Memory allocator for CSV buffer
///   - rows: Number of data rows to generate
///   - cols: Number of columns to generate
///
/// Returns: CSV string (caller must free)
///
/// Example:
/// ```zig
/// const csv = try generateCSV(allocator, 1000, 10);
/// defer allocator.free(csv);
/// ```
pub fn generateCSV(
    allocator: std.mem.Allocator,
    rows: u32,
    cols: u32,
) ![]const u8 {
    std.debug.assert(rows > 0); // Pre-condition #1
    std.debug.assert(cols > 0); // Pre-condition #2
    std.debug.assert(rows <= 10_000_000); // Reasonable limit
    std.debug.assert(cols <= 1000); // Reasonable limit

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    // Generate header
    var col: u32 = 0;
    while (col < cols) : (col += 1) {
        try buf.writer(allocator).print("col{}", .{col});
        if (col < cols - 1) try buf.append(allocator, ',');
    }
    try buf.append(allocator, '\n');

    std.debug.assert(col == cols); // Post-condition #1

    // Generate data rows
    var row: u32 = 0;
    while (row < rows) : (row += 1) {
        col = 0;
        while (col < cols) : (col += 1) {
            // Generate numeric data (avoid parsing overhead for now)
            try buf.writer(allocator).print("{}", .{row * 10 + col});
            if (col < cols - 1) try buf.append(allocator, ',');
        }
        try buf.append(allocator, '\n');
    }

    std.debug.assert(row == rows); // Post-condition #2

    return try buf.toOwnedSlice(allocator);
}

/// Generates test CSV with mixed types
///
/// Args:
///   - allocator: Memory allocator for CSV buffer
///   - rows: Number of data rows to generate
///
/// Returns: CSV string with Int64, Float64, String, Bool columns
pub fn generateMixedCSV(
    allocator: std.mem.Allocator,
    rows: u32,
) ![]const u8 {
    std.debug.assert(rows > 0); // Pre-condition #1
    std.debug.assert(rows <= 10_000_000); // Reasonable limit

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    // Header: id (Int64), score (Float64), name (String), active (Bool)
    try buf.appendSlice(allocator,"id,score,name,active\n");

    const names = [_][]const u8{ "Alice", "Bob", "Charlie", "Diana", "Eve" };

    var row: u32 = 0;
    while (row < rows) : (row += 1) {
        // id: sequential integers
        try buf.writer(allocator).print("{}", .{row + 1});
        try buf.append(allocator, ',');

        // score: floating point
        const score = @as(f64, @floatFromInt((row % 100))) + 0.5;
        try buf.writer(allocator).print("{d:.1}", .{score});
        try buf.append(allocator, ',');

        // name: string (cycle through names)
        try buf.appendSlice(allocator, names[row % names.len]);
        try buf.append(allocator, ',');

        // active: boolean
        const active = (row % 2) == 0;
        try buf.appendSlice(allocator, if (active) "true" else "false");
        try buf.append(allocator, '\n');
    }

    std.debug.assert(row == rows); // Post-condition #2

    return try buf.toOwnedSlice(allocator);
}

/// Comparison helper for benchmark results
pub const Comparison = struct {
    name: []const u8,
    target_ms: f64,
    actual_ms: f64,
    passed: bool,

    pub fn check(name: []const u8, target_ms: f64, actual_ms: f64) Comparison {
        std.debug.assert(target_ms > 0); // Pre-condition #1
        std.debug.assert(actual_ms > 0); // Pre-condition #2

        return Comparison{
            .name = name,
            .target_ms = target_ms,
            .actual_ms = actual_ms,
            .passed = actual_ms < target_ms,
        };
    }

    pub fn print(self: Comparison) void {
        const status = if (self.passed) "✓" else "✗";
        const diff = self.actual_ms - self.target_ms;
        const pct = (diff / self.target_ms) * 100.0;

        std.debug.print("{s} {s}: Target <{d:.0}ms | Actual: {d:.2}ms", .{
            status,
            self.name,
            self.target_ms,
            self.actual_ms,
        });

        if (self.passed) {
            std.debug.print(" ({d:.1}% faster)\n", .{-pct});
        } else {
            std.debug.print(" ({d:.1}% slower)\n", .{pct});
        }
    }
};
