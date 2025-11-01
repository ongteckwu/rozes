// Apache Arrow Conversion Benchmarks
// Tests performance of DataFrame ↔ Arrow conversions

const std = @import("std");
const rozes = @import("rozes");
const DataFrame = rozes.DataFrame;
const Series = rozes.Series;
const ColumnDesc = rozes.ColumnDesc;
const arrow_ipc = rozes.arrow_ipc;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Apache Arrow Conversion Benchmarks ===\n\n", .{});

    // Test different sizes
    const sizes = [_]u32{ 1_000, 10_000, 100_000 };

    for (sizes) |size| {
        try benchmarkToArrow(allocator, size);
        try benchmarkFromArrow(allocator, size);
        try benchmarkRoundTrip(allocator, size);
        std.debug.print("\n", .{});
    }
}

fn benchmarkToArrow(allocator: std.mem.Allocator, row_count: u32) !void {
    std.debug.assert(row_count > 0); // Tiger Style: validate input
    std.debug.assert(row_count <= 1_000_000); // Tiger Style: bounded size

    // Create test DataFrame
    var df = try createTestDataFrame(allocator, row_count);
    defer df.deinit();

    // Benchmark conversion to Arrow
    const start = std.time.nanoTimestamp();
    var batch = try df.toArrow(allocator);
    const end = std.time.nanoTimestamp();
    defer batch.deinit();
    defer batch.schema.deinit();

    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    std.debug.print("DataFrame → Arrow ({} rows): {d:.2}ms\n", .{ row_count, duration_ms });

    // Verify conversion overhead is reasonable
    std.debug.assert(duration_ms < 1000.0); // <1s for any size
}

fn benchmarkFromArrow(allocator: std.mem.Allocator, row_count: u32) !void {
    std.debug.assert(row_count > 0);
    std.debug.assert(row_count <= 1_000_000);

    // Create Arrow batch
    var df_temp = try createTestDataFrame(allocator, row_count);
    defer df_temp.deinit();

    var batch = try df_temp.toArrow(allocator);
    defer batch.deinit();
    defer batch.schema.deinit();

    // Benchmark conversion from Arrow
    const start = std.time.nanoTimestamp();
    var df = try DataFrame.fromArrow(allocator, &batch);
    const end = std.time.nanoTimestamp();
    defer df.deinit();

    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    std.debug.print("Arrow → DataFrame ({} rows): {d:.2}ms\n", .{ row_count, duration_ms });

    // Verify conversion overhead
    std.debug.assert(duration_ms < 1000.0);
}

fn benchmarkRoundTrip(allocator: std.mem.Allocator, row_count: u32) !void {
    std.debug.assert(row_count > 0);
    std.debug.assert(row_count <= 1_000_000);

    // Create original DataFrame
    var df1 = try createTestDataFrame(allocator, row_count);
    defer df1.deinit();

    // Round-trip: DataFrame → Arrow → DataFrame
    const start = std.time.nanoTimestamp();

    var batch = try df1.toArrow(allocator);
    defer batch.deinit();
    defer batch.schema.deinit();

    var df2 = try DataFrame.fromArrow(allocator, &batch);
    defer df2.deinit();

    const end = std.time.nanoTimestamp();

    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    std.debug.print("Round-trip ({} rows): {d:.2}ms\n", .{ row_count, duration_ms });

    // Verify structure matches
    std.debug.assert(df1.columns.len == df2.columns.len);
    std.debug.assert(df1.row_count == df2.row_count);

    // Verify conversion overhead is acceptable (<10% of data size)
    const data_size_mb = @as(f64, @floatFromInt(row_count * 3 * 8)) / (1024.0 * 1024.0);
    const max_overhead_ms = data_size_mb * 10.0; // 10ms per MB
    std.debug.assert(duration_ms < max_overhead_ms);
}

fn createTestDataFrame(allocator: std.mem.Allocator, row_count: u32) !DataFrame {
    std.debug.assert(row_count > 0);
    std.debug.assert(row_count <= 10_000_000); // 10M max

    const column_descs = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
        ColumnDesc.init("flag", .Bool, 2),
    };

    var df = try DataFrame.create(allocator, &column_descs, row_count);
    errdefer df.deinit();

    // Column 1: Int64
    const int_data = try allocator.alloc(i64, row_count);
    var i: u32 = 0;
    const max_iterations: u32 = 10_000_000; // Tiger Style: bounded loop
    while (i < row_count and i < max_iterations) : (i += 1) {
        int_data[i] = @as(i64, @intCast(i));
    }
    std.debug.assert(i == row_count); // Post-condition

    df.columns[0] = Series{
        .name = "id",
        .value_type = .Int64,
        .data = .{ .Int64 = int_data },
        .length = row_count,
    };

    // Column 2: Float64
    const float_data = try allocator.alloc(f64, row_count);
    i = 0;
    while (i < row_count and i < max_iterations) : (i += 1) {
        float_data[i] = @as(f64, @floatFromInt(i)) * 1.5;
    }
    std.debug.assert(i == row_count);

    df.columns[1] = Series{
        .name = "value",
        .value_type = .Float64,
        .data = .{ .Float64 = float_data },
        .length = row_count,
    };

    // Column 3: Bool
    const bool_data = try allocator.alloc(bool, row_count);
    i = 0;
    while (i < row_count and i < max_iterations) : (i += 1) {
        bool_data[i] = (i % 2 == 0);
    }
    std.debug.assert(i == row_count);

    df.columns[2] = Series{
        .name = "flag",
        .value_type = .Bool,
        .data = .{ .Bool = bool_data },
        .length = row_count,
    };

    return df;
}
