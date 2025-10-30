//! Unit tests for DataFrame sorting operations
//!
//! Tests cover:
//! - Single-column sorting (ascending/descending)
//! - Multi-column sorting
//! - All column types (Int64, Float64, String, Bool)
//! - Stable sort verification
//! - Error cases

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const Series = @import("../../../core/series.zig").Series;
const types = @import("../../../core/types.zig");
const sort_mod = @import("../../../core/sort.zig");

const ColumnDesc = types.ColumnDesc;
const ValueType = types.ValueType;
const SortOrder = sort_mod.SortOrder;
const SortSpec = sort_mod.SortSpec;

// Test: Single column sort - Int64 ascending
test "sort Int64 column ascending" {
    const allocator = testing.allocator;

    // Create test DataFrame
    const cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    // Fill with unsorted data
    const values = df.columns[1].asInt64Buffer() orelse unreachable;
    values[0] = 42;
    values[1] = 10;
    values[2] = 95;
    values[3] = 23;
    values[4] = 67;
    df.row_count = 5;

    // Sort by value column
    var sorted = try sort_mod.sort(&df, allocator, "value", .Ascending);
    defer sorted.deinit();

    // Verify sorted order
    const sorted_values = sorted.columns[1].asInt64Buffer() orelse unreachable;
    try testing.expectEqual(@as(i64, 10), sorted_values[0]);
    try testing.expectEqual(@as(i64, 23), sorted_values[1]);
    try testing.expectEqual(@as(i64, 42), sorted_values[2]);
    try testing.expectEqual(@as(i64, 67), sorted_values[3]);
    try testing.expectEqual(@as(i64, 95), sorted_values[4]);
}

// Test: Single column sort - Int64 descending
test "sort Int64 column descending" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const values = df.columns[0].asInt64Buffer() orelse unreachable;
    values[0] = 42;
    values[1] = 10;
    values[2] = 95;
    values[3] = 23;
    values[4] = 67;
    df.row_count = 5;

    var sorted = try sort_mod.sort(&df, allocator, "value", .Descending);
    defer sorted.deinit();

    const sorted_values = sorted.columns[0].asInt64Buffer() orelse unreachable;
    try testing.expectEqual(@as(i64, 95), sorted_values[0]);
    try testing.expectEqual(@as(i64, 67), sorted_values[1]);
    try testing.expectEqual(@as(i64, 42), sorted_values[2]);
    try testing.expectEqual(@as(i64, 23), sorted_values[3]);
    try testing.expectEqual(@as(i64, 10), sorted_values[4]);
}

// Test: Single column sort - Float64 ascending
test "sort Float64 column ascending" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("score", .Float64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    const scores = df.columns[0].asFloat64Buffer() orelse unreachable;
    scores[0] = 87.5;
    scores[1] = 92.3;
    scores[2] = 78.9;
    scores[3] = 95.1;
    df.row_count = 4;

    var sorted = try sort_mod.sort(&df, allocator, "score", .Ascending);
    defer sorted.deinit();

    const sorted_scores = sorted.columns[0].asFloat64Buffer() orelse unreachable;
    try testing.expectApproxEqAbs(@as(f64, 78.9), sorted_scores[0], 0.01);
    try testing.expectApproxEqAbs(@as(f64, 87.5), sorted_scores[1], 0.01);
    try testing.expectApproxEqAbs(@as(f64, 92.3), sorted_scores[2], 0.01);
    try testing.expectApproxEqAbs(@as(f64, 95.1), sorted_scores[3], 0.01);
}

// Test: Single column sort - Bool ascending
test "sort Bool column ascending" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("active", .Bool, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const active = df.columns[0].asBoolBuffer() orelse unreachable;
    active[0] = true;
    active[1] = false;
    active[2] = true;
    active[3] = false;
    active[4] = true;
    df.row_count = 5;

    var sorted = try sort_mod.sort(&df, allocator, "active", .Ascending);
    defer sorted.deinit();

    const sorted_active = sorted.columns[0].asBoolBuffer() orelse unreachable;
    // false < true
    try testing.expect(!sorted_active[0]);
    try testing.expect(!sorted_active[1]);
    try testing.expect(sorted_active[2]);
    try testing.expect(sorted_active[3]);
    try testing.expect(sorted_active[4]);
}

// Test: Single column sort - String ascending
test "sort String column ascending" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    const arena_alloc = df.arena.allocator();
    try df.columns[0].appendString(arena_alloc, "Charlie");
    try df.columns[0].appendString(arena_alloc, "Alice");
    try df.columns[0].appendString(arena_alloc, "David");
    try df.columns[0].appendString(arena_alloc, "Bob");
    df.row_count = 4;

    var sorted = try sort_mod.sort(&df, allocator, "name", .Ascending);
    defer sorted.deinit();

    const sorted_col = sorted.columns[0].asStringColumn() orelse unreachable;
    try testing.expectEqualStrings("Alice", sorted_col.get(0));
    try testing.expectEqualStrings("Bob", sorted_col.get(1));
    try testing.expectEqualStrings("Charlie", sorted_col.get(2));
    try testing.expectEqualStrings("David", sorted_col.get(3));
}

// Test: Multi-column sort
test "sortBy multiple columns" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("city", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
        ColumnDesc.init("score", .Float64, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 6);
    defer df.deinit();

    // Add data - same city, different ages
    const arena_alloc = df.arena.allocator();
    try df.columns[0].appendString(arena_alloc, "NYC");
    try df.columns[0].appendString(arena_alloc, "NYC");
    try df.columns[0].appendString(arena_alloc, "LA");
    try df.columns[0].appendString(arena_alloc, "LA");
    try df.columns[0].appendString(arena_alloc, "NYC");
    try df.columns[0].appendString(arena_alloc, "LA");

    const ages = df.columns[1].asInt64Buffer() orelse unreachable;
    ages[0] = 30;
    ages[1] = 25;
    ages[2] = 35;
    ages[3] = 28;
    ages[4] = 25;
    ages[5] = 35;

    const scores = df.columns[2].asFloat64Buffer() orelse unreachable;
    scores[0] = 85.0;
    scores[1] = 90.0;
    scores[2] = 78.0;
    scores[3] = 92.0;
    scores[4] = 88.0;
    scores[5] = 82.0;

    df.row_count = 6;

    // Sort by city ASC, then age DESC
    const specs = [_]SortSpec{
        .{ .column = "city", .order = .Ascending },
        .{ .column = "age", .order = .Descending },
    };

    var sorted = try sort_mod.sortBy(&df, allocator, &specs);
    defer sorted.deinit();

    // Verify order: LA (35, 35, 28), NYC (30, 25, 25)
    const sorted_cities = sorted.columns[0].asStringColumn() orelse unreachable;
    const sorted_ages = sorted.columns[1].asInt64Buffer() orelse unreachable;

    // LA with ages descending
    try testing.expectEqualStrings("LA", sorted_cities.get(0));
    try testing.expectEqual(@as(i64, 35), sorted_ages[0]);

    try testing.expectEqualStrings("LA", sorted_cities.get(1));
    try testing.expectEqual(@as(i64, 35), sorted_ages[1]);

    try testing.expectEqualStrings("LA", sorted_cities.get(2));
    try testing.expectEqual(@as(i64, 28), sorted_ages[2]);

    // NYC with ages descending
    try testing.expectEqualStrings("NYC", sorted_cities.get(3));
    try testing.expectEqual(@as(i64, 30), sorted_ages[3]);

    try testing.expectEqualStrings("NYC", sorted_cities.get(4));
    try testing.expectEqual(@as(i64, 25), sorted_ages[4]);

    try testing.expectEqualStrings("NYC", sorted_cities.get(5));
    try testing.expectEqual(@as(i64, 25), sorted_ages[5]);
}

// Test: Stable sort - verify original order preserved for equal values
test "sort is stable" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("category", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const ids = df.columns[0].asInt64Buffer() orelse unreachable;
    ids[0] = 1;
    ids[1] = 2;
    ids[2] = 3;
    ids[3] = 4;
    ids[4] = 5;

    const categories = df.columns[1].asInt64Buffer() orelse unreachable;
    categories[0] = 100;
    categories[1] = 200;
    categories[2] = 100;
    categories[3] = 200;
    categories[4] = 100;

    df.row_count = 5;

    // Sort by category (ascending)
    var sorted = try sort_mod.sort(&df, allocator, "category", .Ascending);
    defer sorted.deinit();

    const sorted_ids = sorted.columns[0].asInt64Buffer() orelse unreachable;
    const sorted_cats = sorted.columns[1].asInt64Buffer() orelse unreachable;

    // Category 100: ids should be 1, 3, 5 (original order)
    try testing.expectEqual(@as(i64, 100), sorted_cats[0]);
    try testing.expectEqual(@as(i64, 1), sorted_ids[0]);

    try testing.expectEqual(@as(i64, 100), sorted_cats[1]);
    try testing.expectEqual(@as(i64, 3), sorted_ids[1]);

    try testing.expectEqual(@as(i64, 100), sorted_cats[2]);
    try testing.expectEqual(@as(i64, 5), sorted_ids[2]);

    // Category 200: ids should be 2, 4 (original order)
    try testing.expectEqual(@as(i64, 200), sorted_cats[3]);
    try testing.expectEqual(@as(i64, 2), sorted_ids[3]);

    try testing.expectEqual(@as(i64, 200), sorted_cats[4]);
    try testing.expectEqual(@as(i64, 4), sorted_ids[4]);
}

// Test: Sort preserves row count
test "sort preserves row count" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    const values = df.columns[0].asInt64Buffer() orelse unreachable;
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        values[i] = @intCast(100 - i); // Reverse order
    }
    df.row_count = 100;

    var sorted = try sort_mod.sort(&df, allocator, "value", .Ascending);
    defer sorted.deinit();

    try testing.expectEqual(@as(u32, 100), sorted.row_count);
}

// Test: Sort empty DataFrame (should return empty DataFrame)
test "sort empty DataFrame returns empty DataFrame" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 1);
    defer df.deinit();

    // Set row count to 0
    try df.setRowCount(0);

    // Sort empty DataFrame should succeed
    var sorted = try sort_mod.sort(&df, allocator, "value", .Ascending);
    defer sorted.deinit();

    // Should return empty DataFrame with same structure
    try testing.expectEqual(@as(u32, 0), sorted.row_count);
    try testing.expectEqual(@as(usize, 1), sorted.columns.len);
    try testing.expectEqualStrings("value", sorted.column_descs[0].name);
}

// Test: Sort by non-existent column
test "sort by non-existent column returns error" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const values = df.columns[0].asInt64Buffer() orelse unreachable;
    values[0] = 1;
    values[1] = 2;
    values[2] = 3;
    values[3] = 4;
    values[4] = 5;
    df.row_count = 5;

    const result = sort_mod.sort(&df, allocator, "nonexistent", .Ascending);
    try testing.expectError(error.ColumnNotFound, result);
}

// Test: Memory leak test - 1000 sorts
test "sort releases all memory" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var iteration: usize = 0;
    while (iteration < 1000) : (iteration += 1) {
        var df = try DataFrame.create(allocator, &cols, 10);
        defer df.deinit();

        const values = df.columns[0].asInt64Buffer() orelse unreachable;
        var i: u32 = 0;
        while (i < 10) : (i += 1) {
            values[i] = @intCast(10 - i);
        }
        df.row_count = 10;

        var sorted = try sort_mod.sort(&df, allocator, "value", .Ascending);
        sorted.deinit();
    }

    // testing.allocator will report leaks automatically
}

// Test: Sort with negative numbers
test "sort handles negative Int64 values" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const values = df.columns[0].asInt64Buffer() orelse unreachable;
    values[0] = -10;
    values[1] = 5;
    values[2] = -20;
    values[3] = 0;
    values[4] = 15;
    df.row_count = 5;

    var sorted = try sort_mod.sort(&df, allocator, "value", .Ascending);
    defer sorted.deinit();

    const sorted_values = sorted.columns[0].asInt64Buffer() orelse unreachable;
    try testing.expectEqual(@as(i64, -20), sorted_values[0]);
    try testing.expectEqual(@as(i64, -10), sorted_values[1]);
    try testing.expectEqual(@as(i64, 0), sorted_values[2]);
    try testing.expectEqual(@as(i64, 5), sorted_values[3]);
    try testing.expectEqual(@as(i64, 15), sorted_values[4]);
}

// Test: Sort with NaN values in Float64
test "sort handles NaN in Float64 column" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Float64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    const values = df.columns[0].asFloat64Buffer() orelse unreachable;
    values[0] = 42.0;
    values[1] = std.math.nan(f64);
    values[2] = 10.0;
    values[3] = 95.0;
    df.row_count = 4;

    var sorted = try sort_mod.sort(&df, allocator, "value", .Ascending);
    defer sorted.deinit();

    // NaN should sort to end (or beginning depending on implementation)
    // Just verify it doesn't crash
    try testing.expectEqual(@as(u32, 4), sorted.row_count);
}

// Test: Sort with duplicate values
test "sort handles duplicate values" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 6);
    defer df.deinit();

    const values = df.columns[0].asInt64Buffer() orelse unreachable;
    values[0] = 10;
    values[1] = 20;
    values[2] = 10;
    values[3] = 30;
    values[4] = 20;
    values[5] = 10;
    df.row_count = 6;

    var sorted = try sort_mod.sort(&df, allocator, "value", .Ascending);
    defer sorted.deinit();

    const sorted_values = sorted.columns[0].asInt64Buffer() orelse unreachable;
    try testing.expectEqual(@as(i64, 10), sorted_values[0]);
    try testing.expectEqual(@as(i64, 10), sorted_values[1]);
    try testing.expectEqual(@as(i64, 10), sorted_values[2]);
    try testing.expectEqual(@as(i64, 20), sorted_values[3]);
    try testing.expectEqual(@as(i64, 20), sorted_values[4]);
    try testing.expectEqual(@as(i64, 30), sorted_values[5]);
}

// Test: Sort with single row (edge case)
test "sort single row DataFrame" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 1);
    defer df.deinit();

    const values = df.columns[0].asInt64Buffer() orelse unreachable;
    values[0] = 42;
    df.row_count = 1;

    var sorted = try sort_mod.sort(&df, allocator, "value", .Ascending);
    defer sorted.deinit();

    const sorted_values = sorted.columns[0].asInt64Buffer() orelse unreachable;
    try testing.expectEqual(@as(i64, 42), sorted_values[0]);
}

// Test: Sort with two rows (edge case)
test "sort two row DataFrame" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 2);
    defer df.deinit();

    const values = df.columns[0].asInt64Buffer() orelse unreachable;
    values[0] = 95;
    values[1] = 10;
    df.row_count = 2;

    var sorted = try sort_mod.sort(&df, allocator, "value", .Ascending);
    defer sorted.deinit();

    const sorted_values = sorted.columns[0].asInt64Buffer() orelse unreachable;
    try testing.expectEqual(@as(i64, 10), sorted_values[0]);
    try testing.expectEqual(@as(i64, 95), sorted_values[1]);
}

// Test: SortOrder.apply function
test "SortOrder.apply inverts comparison correctly" {
    // Ascending: preserves order
    try testing.expectEqual(std.math.Order.lt, SortOrder.Ascending.apply(.lt));
    try testing.expectEqual(std.math.Order.gt, SortOrder.Ascending.apply(.gt));
    try testing.expectEqual(std.math.Order.eq, SortOrder.Ascending.apply(.eq));

    // Descending: inverts order
    try testing.expectEqual(std.math.Order.gt, SortOrder.Descending.apply(.lt));
    try testing.expectEqual(std.math.Order.lt, SortOrder.Descending.apply(.gt));
    try testing.expectEqual(std.math.Order.eq, SortOrder.Descending.apply(.eq));
}
