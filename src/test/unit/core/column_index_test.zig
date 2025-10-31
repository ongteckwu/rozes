//! Tests for Column Index HashMap Optimization
//!
//! Verifies O(1) column lookup performance and correctness

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const ColumnDesc = @import("../../../core/types.zig").ColumnDesc;

test "column() uses hash map for O(1) lookup" {
    const allocator = testing.allocator;

    const columns = [_]ColumnDesc{
        ColumnDesc.init("col_0", .Int64, 0),
        ColumnDesc.init("col_1", .Int64, 1),
        ColumnDesc.init("col_2", .Int64, 2),
    };

    var df = try DataFrame.create(allocator, &columns, 10);
    defer df.deinit();

    // Verify lookup works for all columns
    const col_0 = df.column("col_0").?;
    try testing.expectEqualStrings("col_0", col_0.name);

    const col_2 = df.column("col_2").?;
    try testing.expectEqualStrings("col_2", col_2.name);

    // Verify null for non-existent column
    const not_found = df.column("not_exists");
    try testing.expect(not_found == null);
}

test "columnIndex() returns correct indices via hash map" {
    const allocator = testing.allocator;

    const columns = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
        ColumnDesc.init("score", .Float64, 2),
        ColumnDesc.init("active", .Bool, 3),
    };

    var df = try DataFrame.create(allocator, &columns, 100);
    defer df.deinit();

    // Test all column indices
    try testing.expectEqual(@as(usize, 0), df.columnIndex("name").?);
    try testing.expectEqual(@as(usize, 1), df.columnIndex("age").?);
    try testing.expectEqual(@as(usize, 2), df.columnIndex("score").?);
    try testing.expectEqual(@as(usize, 3), df.columnIndex("active").?);

    // Test non-existent column
    try testing.expect(df.columnIndex("nonexistent") == null);
}

test "column lookup with wide DataFrame (100 columns)" {
    const allocator = testing.allocator;

    // Create DataFrame with 100 columns
    const col_descs = try allocator.alloc(ColumnDesc, 100);
    defer allocator.free(col_descs);

    // Track column names for cleanup
    var col_names: [100][]const u8 = undefined;

    for (col_descs, 0..) |*desc, i| {
        const name = try std.fmt.allocPrint(allocator, "column_{}", .{i});
        col_names[i] = name;
        desc.* = ColumnDesc.init(name, .Int64, @intCast(i));
    }

    defer {
        for (col_names) |name| {
            allocator.free(name);
        }
    }

    var df = try DataFrame.create(allocator, col_descs, 10);
    defer df.deinit();

    // Lookup should be fast even for last column (O(1) vs O(n))
    const col_99 = df.column("column_99").?;
    try testing.expectEqualStrings("column_99", col_99.name);

    // Verify index correctness
    try testing.expectEqual(@as(usize, 99), df.columnIndex("column_99").?);
    try testing.expectEqual(@as(usize, 0), df.columnIndex("column_0").?);
    try testing.expectEqual(@as(usize, 50), df.columnIndex("column_50").?);
}

test "column index handles duplicate column names" {
    const allocator = testing.allocator;

    // DataFrame with duplicate column names (edge case from transpose)
    const columns = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
        ColumnDesc.init("value", .Int64, 1), // Duplicate name
        ColumnDesc.init("value", .Int64, 2), // Duplicate name
    };

    var df = try DataFrame.create(allocator, &columns, 10);
    defer df.deinit();

    // Hash map will return the LAST occurrence (index 2)
    const idx = df.columnIndex("value").?;
    try testing.expectEqual(@as(usize, 2), idx);

    // Verify column lookup returns last duplicate
    const col = df.column("value").?;
    try testing.expectEqualStrings("value", col.name);
}

test "hasColumn() uses hash map" {
    const allocator = testing.allocator;

    const columns = [_]ColumnDesc{
        ColumnDesc.init("a", .Int64, 0),
        ColumnDesc.init("b", .Float64, 1),
        ColumnDesc.init("c", .Bool, 2),
    };

    var df = try DataFrame.create(allocator, &columns, 5);
    defer df.deinit();

    // Test existence checks
    try testing.expect(df.hasColumn("a"));
    try testing.expect(df.hasColumn("b"));
    try testing.expect(df.hasColumn("c"));
    try testing.expect(!df.hasColumn("d"));
    try testing.expect(!df.hasColumn("nonexistent"));
}

test "column index correctness after DataFrame creation" {
    const allocator = testing.allocator;

    const columns = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("name", .String, 1),
        ColumnDesc.init("price", .Float64, 2),
    };

    var df = try DataFrame.create(allocator, &columns, 50);
    defer df.deinit();

    // Verify index was built correctly
    try testing.expectEqual(@as(usize, 3), df.column_index.count());

    // Verify all columns accessible
    try testing.expect(df.column("id") != null);
    try testing.expect(df.column("name") != null);
    try testing.expect(df.column("price") != null);

    // Verify indices match column positions
    const id_idx = df.columnIndex("id").?;
    const name_idx = df.columnIndex("name").?;
    const price_idx = df.columnIndex("price").?;

    try testing.expectEqual(@as(usize, 0), id_idx);
    try testing.expectEqual(@as(usize, 1), name_idx);
    try testing.expectEqual(@as(usize, 2), price_idx);
}

test "column lookup with special characters in names" {
    const allocator = testing.allocator;

    const columns = [_]ColumnDesc{
        ColumnDesc.init("user_id", .Int64, 0),
        ColumnDesc.init("first-name", .String, 1),
        ColumnDesc.init("email@domain", .String, 2),
        ColumnDesc.init("score.avg", .Float64, 3),
    };

    var df = try DataFrame.create(allocator, &columns, 10);
    defer df.deinit();

    // All special character names should work
    try testing.expect(df.column("user_id") != null);
    try testing.expect(df.column("first-name") != null);
    try testing.expect(df.column("email@domain") != null);
    try testing.expect(df.column("score.avg") != null);

    // Verify exact match required
    try testing.expect(df.column("user-id") == null);
    try testing.expect(df.column("user_ID") == null);
}

test "column index memory is managed by arena" {
    const allocator = testing.allocator;

    const columns = [_]ColumnDesc{
        ColumnDesc.init("a", .Int64, 0),
        ColumnDesc.init("b", .Int64, 1),
    };

    // Create and destroy DataFrame multiple times
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var df = try DataFrame.create(allocator, &columns, 10);
        defer df.deinit();

        // Use the column index
        _ = df.column("a");
        _ = df.column("b");
    }

    // testing.allocator will catch any leaks
}

test "column index with case-sensitive names" {
    const allocator = testing.allocator;

    const columns = [_]ColumnDesc{
        ColumnDesc.init("Name", .Int64, 0), // Capital N
        ColumnDesc.init("name", .Int64, 1), // Lowercase n
    };

    var df = try DataFrame.create(allocator, &columns, 5);
    defer df.deinit();

    // Names are case-sensitive
    const idx1 = df.columnIndex("Name");
    try testing.expect(idx1 != null);
    try testing.expectEqual(@as(usize, 0), idx1.?);

    const idx2 = df.columnIndex("name");
    try testing.expect(idx2 != null);
    try testing.expectEqual(@as(usize, 1), idx2.?);

    // Wrong case should not match
    try testing.expect(df.columnIndex("NAME") == null);
}

test "column index performance: worst case O(1) vs O(n)" {
    const allocator = testing.allocator;

    // Create DataFrame with 1000 columns
    const COL_COUNT = 1000;
    const col_descs = try allocator.alloc(ColumnDesc, COL_COUNT);
    defer allocator.free(col_descs);

    // Track column names for cleanup
    const col_names = try allocator.alloc([]const u8, COL_COUNT);
    defer allocator.free(col_names);

    for (col_descs, 0..) |*desc, i| {
        const name = try std.fmt.allocPrint(allocator, "col_{}", .{i});
        col_names[i] = name;
        desc.* = ColumnDesc.init(name, .Int64, @intCast(i));
    }

    defer {
        for (col_names) |name| {
            allocator.free(name);
        }
    }

    var df = try DataFrame.create(allocator, col_descs, 10);
    defer df.deinit();

    // Measure lookup time for last column (worst case for O(n))
    const start = std.time.nanoTimestamp();

    // Perform 10,000 lookups
    var j: usize = 0;
    while (j < 10_000) : (j += 1) {
        const col = df.column("col_999");
        std.debug.assert(col != null);
    }

    const end = std.time.nanoTimestamp();
    const duration_ns = end - start;
    const avg_lookup_ns = @divFloor(duration_ns, 10_000);

    // With O(1) hash map, average lookup should be <1000ns (1μs)
    // With O(n) linear scan, would be ~10,000ns+ for 1000 columns
    std.debug.print("\nColumn lookup performance (1000 columns):\n", .{});
    std.debug.print("  Average lookup time: {}ns\n", .{avg_lookup_ns});
    std.debug.print("  Total for 10K lookups: {d:.2}ms\n", .{@as(f64, @floatFromInt(duration_ns)) / 1_000_000.0});

    // Verify performance is reasonable (should be <500ns per lookup with O(1))
    try testing.expect(avg_lookup_ns < 1000); // <1μs per lookup
}
