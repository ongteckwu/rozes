const std = @import("std");
const rozes = @import("rozes");
const DataFrame = rozes.DataFrame;
const ColumnDesc = rozes.ColumnDesc;

/// Profile join operation to identify bottlenecks across 3 phases:
/// - Phase 1: Hash table build from right DataFrame
/// - Phase 2: Hash table probe with left DataFrame
/// - Phase 3: Result DataFrame construction and data copying
///
/// **Goal**: Identify which phase takes the most time to focus optimization effort
///
/// **Expected bottlenecks** (from TODO.md):
/// 1. Data copying (~40-60% of time)
/// 2. Hash table probes (~20-30%)
/// 3. Memory allocations (~10-20%)
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Join Performance Profiling ===\n", .{});
    std.debug.print("Analyzing bottlenecks across 3 phases\n", .{});
    std.debug.print("Baseline: 740ms for 10K x 10K join\n", .{});
    std.debug.print("Target: <500ms (need 32% improvement)\n\n", .{});

    // Profile with different data sizes
    try profileJoinPhases(allocator, 1_000, "1K x 1K");
    try profileJoinPhases(allocator, 5_000, "5K x 5K");
    try profileJoinPhases(allocator, 10_000, "10K x 10K (BENCHMARK)");

    std.debug.print("\n=== Profiling Complete ===\n", .{});
}

fn profileJoinPhases(allocator: std.mem.Allocator, row_count: u32, label: []const u8) !void {
    std.debug.print("Test: {s} join\n", .{label});
    std.debug.print("-----------------------------\n", .{});

    // Create test DataFrames (4 columns each for realistic workload)
    const left_cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("val1", .Float64, 1),
        ColumnDesc.init("val2", .Int64, 2),
        ColumnDesc.init("active", .Bool, 3),
    };

    var left = try DataFrame.create(allocator, &left_cols, row_count);
    defer left.deinit();

    // Fill left data
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

    const right_cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("right_val1", .Int64, 1),
        ColumnDesc.init("right_val2", .Float64, 2),
    };

    var right = try DataFrame.create(allocator, &right_cols, row_count);
    defer right.deinit();

    // Fill right data
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

    // Profile Phase 1: Hash table build
    std.debug.print("  Phase 1: Hash table build (right DataFrame)\n", .{});
    const phase1_start = std.time.nanoTimestamp();

    // Simulate hash table build - we'll need to copy this from join.zig
    var hash_map = std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(u32)){};
    defer {
        var iter = hash_map.valueIterator();
        while (iter.next()) |list| {
            list.deinit(allocator);
        }
        hash_map.deinit(allocator);
    }

    try hash_map.ensureTotalCapacity(allocator, row_count);

    // Simple hash function (FNV-1a) for id column
    var row_idx: u32 = 0;
    while (row_idx < row_count) : (row_idx += 1) {
        const id = right_ids[row_idx];
        const hash = hashInt64(id);

        const gop = try hash_map.getOrPut(allocator, hash);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }
        try gop.value_ptr.append(allocator, row_idx);
    }

    const phase1_end = std.time.nanoTimestamp();
    const phase1_ns: u64 = @intCast(phase1_end - phase1_start);
    const phase1_ms = @as(f64, @floatFromInt(phase1_ns)) / 1_000_000.0;
    std.debug.print("    Duration: {d:.2}ms\n", .{phase1_ms});

    // Profile Phase 2: Hash table probe
    std.debug.print("  Phase 2: Hash table probe (left DataFrame)\n", .{});
    const phase2_start = std.time.nanoTimestamp();

    var matches = std.ArrayListUnmanaged(MatchResult){};
    defer matches.deinit(allocator);
    try matches.ensureTotalCapacity(allocator, row_count);

    row_idx = 0;
    while (row_idx < row_count) : (row_idx += 1) {
        const id = left_ids[row_idx];
        const hash = hashInt64(id);

        if (hash_map.get(hash)) |entries| {
            for (entries.items) |right_idx| {
                try matches.append(allocator, .{
                    .left_idx = row_idx,
                    .right_idx = right_idx,
                });
            }
        }
    }

    const phase2_end = std.time.nanoTimestamp();
    const phase2_ns: u64 = @intCast(phase2_end - phase2_start);
    const phase2_ms = @as(f64, @floatFromInt(phase2_ns)) / 1_000_000.0;
    std.debug.print("    Duration: {d:.2}ms\n", .{phase2_ms});
    std.debug.print("    Matches found: {}\n", .{matches.items.len});

    // Profile Phase 3: Result DataFrame build and data copying
    std.debug.print("  Phase 3: Result DataFrame build + data copy\n", .{});
    const phase3_start = std.time.nanoTimestamp();

    // Create result DataFrame
    const result_cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("val1", .Float64, 1),
        ColumnDesc.init("val2", .Int64, 2),
        ColumnDesc.init("active", .Bool, 3),
        ColumnDesc.init("right_val1", .Int64, 4),
        ColumnDesc.init("right_val2", .Float64, 5),
    };

    var result = try DataFrame.create(allocator, &result_cols, @intCast(matches.items.len));
    defer result.deinit();

    // Copy data from left columns
    const result_ids = result.columns[0].asInt64Buffer() orelse unreachable;
    const result_val1 = result.columns[1].asFloat64Buffer() orelse unreachable;
    const result_val2 = result.columns[2].asInt64Buffer() orelse unreachable;
    const result_active = result.columns[3].asBoolBuffer() orelse unreachable;
    const result_right_val1 = result.columns[4].asInt64Buffer() orelse unreachable;
    const result_right_val2 = result.columns[5].asFloat64Buffer() orelse unreachable;

    // Copy data (row-by-row for now)
    var match_idx: u32 = 0;
    const max_matches: u32 = @intCast(matches.items.len);
    while (match_idx < max_matches) : (match_idx += 1) {
        const match = matches.items[match_idx];

        // Copy from left
        result_ids[match_idx] = left_ids[match.left_idx];
        result_val1[match_idx] = left_val1[match.left_idx];
        result_val2[match_idx] = left_val2[match.left_idx];
        result_active[match_idx] = left_active[match.left_idx];

        // Copy from right
        result_right_val1[match_idx] = right_val1[match.right_idx];
        result_right_val2[match_idx] = right_val2[match.right_idx];
    }

    try result.setRowCount(@intCast(matches.items.len));

    const phase3_end = std.time.nanoTimestamp();
    const phase3_ns: u64 = @intCast(phase3_end - phase3_start);
    const phase3_ms = @as(f64, @floatFromInt(phase3_ns)) / 1_000_000.0;
    std.debug.print("    Duration: {d:.2}ms\n", .{phase3_ms});

    // Summary
    const total_ms = phase1_ms + phase2_ms + phase3_ms;
    std.debug.print("\n  Total: {d:.2}ms\n", .{total_ms});
    std.debug.print("  Breakdown:\n", .{});
    std.debug.print("    Phase 1 (hash build): {d:.1}%\n", .{phase1_ms / total_ms * 100.0});
    std.debug.print("    Phase 2 (probe):      {d:.1}%\n", .{phase2_ms / total_ms * 100.0});
    std.debug.print("    Phase 3 (copy):       {d:.1}%\n", .{phase3_ms / total_ms * 100.0});

    if (row_count == 10_000) {
        const target_ms: f64 = 500.0;
        if (total_ms < target_ms) {
            std.debug.print("  ✓ Target achieved!\n", .{});
        } else {
            const improvement_needed = (total_ms - target_ms) / total_ms * 100.0;
            std.debug.print("  ✗ Need {d:.1}% improvement to hit target\n", .{improvement_needed});
        }
    }

    std.debug.print("\n", .{});
}

const MatchResult = struct {
    left_idx: u32,
    right_idx: u32,
};

/// FNV-1a hash for Int64 values
fn hashInt64(value: i64) u64 {
    const FNV_OFFSET: u64 = 14695981039346656037;
    const FNV_PRIME: u64 = 1099511628211;

    var hash: u64 = FNV_OFFSET;
    const bytes = std.mem.asBytes(&value);

    for (bytes) |byte| {
        hash ^= byte;
        hash *%= FNV_PRIME;
    }

    return hash;
}
