// merge_test.zig - Tests for DataFrame merge operations
//
// Test Coverage:
// - Inner merge (only matching keys)
// - Left merge (all from left, matching from right)
// - Right merge (all from right, matching from left)
// - Outer merge (union of all keys)
// - Cross merge (cartesian product)
// - Multi-column merge keys
// - Suffix handling for overlapping columns
// - Edge cases (empty, no matches)
// - Memory leak tests

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const ColumnDesc = @import("../../../core/types.zig").ColumnDesc;
const combine = @import("../../../core/combine.zig");
const MergeHow = combine.MergeHow;
const MergeOptions = combine.MergeOptions;

// Helper: Create simple left DataFrame (users)
fn createLeftDF(allocator: std.mem.Allocator) !DataFrame {
    const cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("name", .String, 1),
        ColumnDesc.init("age", .Int64, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 3);
    errdefer df.deinit();

    // Fill id column
    const id_col = df.columnMut("id").?;
    const id_data = id_col.asInt64Buffer().?;
    id_data[0] = 1;
    id_data[1] = 2;
    id_data[2] = 3;
    id_col.length = 3;

    // Fill name column
    const name_col = df.columnMut("name").?;
    const string_col = name_col.asStringColumnMut().?;
    try string_col.append(df.arena.allocator(), "Alice");
    try string_col.append(df.arena.allocator(), "Bob");
    try string_col.append(df.arena.allocator(), "Charlie");
    name_col.length = 3;

    // Fill age column
    const age_col = df.columnMut("age").?;
    const age_data = age_col.asInt64Buffer().?;
    age_data[0] = 30;
    age_data[1] = 25;
    age_data[2] = 35;
    age_col.length = 3;

    df.row_count = 3;
    return df;
}

// Helper: Create simple right DataFrame (orders)
fn createRightDF(allocator: std.mem.Allocator) !DataFrame {
    const cols = [_]ColumnDesc{
        ColumnDesc.init("user_id", .Int64, 0),
        ColumnDesc.init("product", .String, 1),
        ColumnDesc.init("quantity", .Int64, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    errdefer df.deinit();

    // Fill user_id column
    const id_col = df.columnMut("user_id").?;
    const id_data = id_col.asInt64Buffer().?;
    id_data[0] = 1;
    id_data[1] = 1;
    id_data[2] = 2;
    id_data[3] = 4; // No match in left
    id_col.length = 4;

    // Fill product column
    const prod_col = df.columnMut("product").?;
    const string_col = prod_col.asStringColumnMut().?;
    try string_col.append(df.arena.allocator(), "Widget");
    try string_col.append(df.arena.allocator(), "Gadget");
    try string_col.append(df.arena.allocator(), "Doohickey");
    try string_col.append(df.arena.allocator(), "Thingamajig");
    prod_col.length = 4;

    // Fill quantity column
    const qty_col = df.columnMut("quantity").?;
    const qty_data = qty_col.asInt64Buffer().?;
    qty_data[0] = 10;
    qty_data[1] = 5;
    qty_data[2] = 3;
    qty_data[3] = 7;
    qty_col.length = 4;

    df.row_count = 4;
    return df;
}

// Test 1: Inner merge - only matching keys
test "merge inner - basic join" {
    const allocator = testing.allocator;

    var left = try createLeftDF(allocator);
    defer left.deinit();

    var right = try createRightDF(allocator);
    defer right.deinit();

    // Inner merge on id = user_id
    var result = try combine.merge(allocator, &left, &right, .{
        .how = .inner,
        .left_on = &[_][]const u8{"id"},
        .right_on = &[_][]const u8{"user_id"},
    });
    defer result.deinit();

    // Validate dimensions
    // id=1 has 2 matches, id=2 has 1 match, id=3 has 0 matches = 3 rows total
    try testing.expectEqual(@as(u32, 3), result.row_count);

    // Should have: id, name, age, product, quantity (user_id is skipped as it's the key)
    try testing.expectEqual(@as(usize, 5), result.columns.len);

    // Validate column names
    try testing.expect(result.column("id") != null);
    try testing.expect(result.column("name") != null);
    try testing.expect(result.column("age") != null);
    try testing.expect(result.column("product") != null);
    try testing.expect(result.column("quantity") != null);

    // Validate data - first row (id=1, first match)
    const id_col = result.column("id").?;
    const ids = id_col.asInt64().?;
    try testing.expectEqual(@as(i64, 1), ids[0]);
    try testing.expectEqual(@as(i64, 1), ids[1]); // Second match for id=1
    try testing.expectEqual(@as(i64, 2), ids[2]);

    // Validate quantities
    const qty_col = result.column("quantity").?;
    const qtys = qty_col.asInt64().?;
    try testing.expectEqual(@as(i64, 10), qtys[0]); // Widget
    try testing.expectEqual(@as(i64, 5), qtys[1]); // Gadget
    try testing.expectEqual(@as(i64, 3), qtys[2]); // Doohickey
}

// Test 2: Inner merge - no matches (empty result)
test "merge inner - no matches" {
    const allocator = testing.allocator;

    // Left: id = 1, 2, 3
    var left = try createLeftDF(allocator);
    defer left.deinit();

    // Right: user_id = 10, 20 (no overlap)
    const cols = [_]ColumnDesc{
        ColumnDesc.init("user_id", .Int64, 0),
        ColumnDesc.init("score", .Float64, 1),
    };
    var right = try DataFrame.create(allocator, &cols, 2);
    defer right.deinit();

    const id_col = right.columnMut("user_id").?;
    const id_data = id_col.asInt64Buffer().?;
    id_data[0] = 10;
    id_data[1] = 20;
    id_col.length = 2;

    const score_col = right.columnMut("score").?;
    const score_data = score_col.asFloat64Buffer().?;
    score_data[0] = 95.5;
    score_data[1] = 87.3;
    score_col.length = 2;

    right.row_count = 2;

    // Inner merge should return empty DataFrame
    var result = try combine.merge(allocator, &left, &right, .{
        .how = .inner,
        .left_on = &[_][]const u8{"id"},
        .right_on = &[_][]const u8{"user_id"},
    });
    defer result.deinit();

    // Should have 0 rows (no matches)
    try testing.expectEqual(@as(u32, 0), result.row_count);

    // But should have all columns
    try testing.expect(result.columns.len > 0);
}

// Test 3: Inner merge - multi-column keys
test "merge inner - multi-column keys" {
    const allocator = testing.allocator;

    // Left: id, year
    const left_cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("year", .Int64, 1),
        ColumnDesc.init("value", .Float64, 2),
    };
    var left = try DataFrame.create(allocator, &left_cols, 2);
    defer left.deinit();

    const left_id = left.columnMut("id").?.asInt64Buffer().?;
    left_id[0] = 1;
    left_id[1] = 1;
    left.columnMut("id").?.length = 2;

    const left_year = left.columnMut("year").?.asInt64Buffer().?;
    left_year[0] = 2023;
    left_year[1] = 2024;
    left.columnMut("year").?.length = 2;

    const left_val = left.columnMut("value").?.asFloat64Buffer().?;
    left_val[0] = 100.0;
    left_val[1] = 200.0;
    left.columnMut("value").?.length = 2;

    left.row_count = 2;

    // Right: id, year, category
    const right_cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("year", .Int64, 1),
        ColumnDesc.init("category", .String, 2),
    };
    var right = try DataFrame.create(allocator, &right_cols, 2);
    defer right.deinit();

    const right_id = right.columnMut("id").?.asInt64Buffer().?;
    right_id[0] = 1;
    right_id[1] = 1;
    right.columnMut("id").?.length = 2;

    const right_year = right.columnMut("year").?.asInt64Buffer().?;
    right_year[0] = 2023;
    right_year[1] = 2025; // No match
    right.columnMut("year").?.length = 2;

    const right_cat = right.columnMut("category").?.asStringColumnMut().?;
    try right_cat.append(right.arena.allocator(), "A");
    try right_cat.append(right.arena.allocator(), "B");
    right.columnMut("category").?.length = 2;

    right.row_count = 2;

    // Merge on both id AND year
    var result = try combine.merge(allocator, &left, &right, .{
        .how = .inner,
        .left_on = &[_][]const u8{ "id", "year" },
        .right_on = &[_][]const u8{ "id", "year" },
    });
    defer result.deinit();

    // Only (1, 2023) matches
    try testing.expectEqual(@as(u32, 1), result.row_count);

    const result_val = result.column("value").?.asFloat64().?;
    try testing.expectApproxEqRel(@as(f64, 100.0), result_val[0], 0.001);
}

// Test 4: Suffix handling for overlapping columns
test "merge inner - overlapping column names" {
    const allocator = testing.allocator;

    // Left: id, name, score
    const left_cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("name", .String, 1),
        ColumnDesc.init("score", .Float64, 2),
    };
    var left = try DataFrame.create(allocator, &left_cols, 1);
    defer left.deinit();

    left.columnMut("id").?.asInt64Buffer().?[0] = 1;
    left.columnMut("id").?.length = 1;

    const left_name = left.columnMut("name").?.asStringColumnMut().?;
    try left_name.append(left.arena.allocator(), "Alice");
    left.columnMut("name").?.length = 1;

    left.columnMut("score").?.asFloat64Buffer().?[0] = 95.5;
    left.columnMut("score").?.length = 1;

    left.row_count = 1;

    // Right: user_id, name (overlaps!), age
    const right_cols = [_]ColumnDesc{
        ColumnDesc.init("user_id", .Int64, 0),
        ColumnDesc.init("name", .String, 1),
        ColumnDesc.init("age", .Int64, 2),
    };
    var right = try DataFrame.create(allocator, &right_cols, 1);
    defer right.deinit();

    right.columnMut("user_id").?.asInt64Buffer().?[0] = 1;
    right.columnMut("user_id").?.length = 1;

    const right_name = right.columnMut("name").?.asStringColumnMut().?;
    try right_name.append(right.arena.allocator(), "Alice Smith");
    right.columnMut("name").?.length = 1;

    right.columnMut("age").?.asInt64Buffer().?[0] = 30;
    right.columnMut("age").?.length = 1;

    right.row_count = 1;

    // Merge with custom suffixes
    var result = try combine.merge(allocator, &left, &right, .{
        .how = .inner,
        .left_on = &[_][]const u8{"id"},
        .right_on = &[_][]const u8{"user_id"},
        .suffixes = .{ .left = "_left", .right = "_right" },
    });
    defer result.deinit();

    // Should have: id, name (from left), score, name_right, age
    try testing.expectEqual(@as(u32, 1), result.row_count);

    // Original name column from left (no suffix)
    try testing.expect(result.column("name") != null);

    // Right name with suffix
    try testing.expect(result.column("name_right") != null);
}

// Test 5: Column not found error
test "merge inner - column not found" {
    const allocator = testing.allocator;

    var left = try createLeftDF(allocator);
    defer left.deinit();

    var right = try createRightDF(allocator);
    defer right.deinit();

    // Try to merge on non-existent column
    const result = combine.merge(allocator, &left, &right, .{
        .how = .inner,
        .left_on = &[_][]const u8{"nonexistent"},
        .right_on = &[_][]const u8{"user_id"},
    });

    try testing.expectError(error.ColumnNotFound, result);
}

// Test 6: Left merge - all from left, matching from right
test "merge left - keeps all left rows" {
    const allocator = testing.allocator;

    var left = try createLeftDF(allocator);
    defer left.deinit();

    var right = try createRightDF(allocator);
    defer right.deinit();

    // Left merge
    var result = try combine.merge(allocator, &left, &right, .{
        .how = .left,
        .left_on = &[_][]const u8{"id"},
        .right_on = &[_][]const u8{"user_id"},
    });
    defer result.deinit();

    // Should have 4 rows: id=1 (2 matches), id=2 (1 match), id=3 (0 matches)
    try testing.expectEqual(@as(u32, 4), result.row_count);

    // Check that id=3 is present with NaN quantities
    const id_col = result.column("id").?;
    const ids = id_col.asInt64().?;

    // Find id=3
    var found_id3 = false;
    var idx: u32 = 0;
    while (idx < result.row_count) : (idx += 1) {
        if (ids[idx] == 3) {
            found_id3 = true;

            // Check that quantity is NaN (default value for unmatched)
            const qty_col = result.column("quantity").?;
            const qtys = qty_col.asInt64().?;
            try testing.expectEqual(@as(i64, 0), qtys[idx]); // Default for Int64
            break;
        }
    }
    try testing.expect(found_id3);
}

// Test 7: Right merge - all from right, matching from left
test "merge right - keeps all right rows" {
    const allocator = testing.allocator;

    var left = try createLeftDF(allocator);
    defer left.deinit();

    var right = try createRightDF(allocator);
    defer right.deinit();

    // Right merge
    var result = try combine.merge(allocator, &left, &right, .{
        .how = .right,
        .left_on = &[_][]const u8{"id"},
        .right_on = &[_][]const u8{"user_id"},
    });
    defer result.deinit();

    // Should have 4 rows (all from right): user_id=1 (2 rows), user_id=2 (1 row), user_id=4 (1 row, no match)
    try testing.expectEqual(@as(u32, 4), result.row_count);

    // Check that user_id=4 is present (no match in left)
    const qty_col = result.column("quantity").?;
    const qtys = qty_col.asInt64().?;

    // user_id=4 should be the last row
    try testing.expectEqual(@as(i64, 7), qtys[3]); // Thingamajig
}

// Test 8: Outer merge - union of all keys
test "merge outer - all rows from both" {
    const allocator = testing.allocator;

    var left = try createLeftDF(allocator);
    defer left.deinit();

    var right = try createRightDF(allocator);
    defer right.deinit();

    // Outer merge
    var result = try combine.merge(allocator, &left, &right, .{
        .how = .outer,
        .left_on = &[_][]const u8{"id"},
        .right_on = &[_][]const u8{"user_id"},
    });
    defer result.deinit();

    // Should have 5 rows:
    // - id=1 with 2 right matches (2 rows)
    // - id=2 with 1 right match (1 row)
    // - id=3 with no right match (1 row)
    // - user_id=4 with no left match (1 row)
    try testing.expectEqual(@as(u32, 5), result.row_count);
}

// Test 9: Cross merge - cartesian product
test "merge cross - all combinations" {
    const allocator = testing.allocator;

    // Small DataFrames for cross join (2x3 = 6 rows)
    const left_cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("name", .String, 1),
    };
    var left = try DataFrame.create(allocator, &left_cols, 2);
    defer left.deinit();

    left.columnMut("id").?.asInt64Buffer().?[0] = 1;
    left.columnMut("id").?.asInt64Buffer().?[1] = 2;
    left.columnMut("id").?.length = 2;

    const left_name = left.columnMut("name").?.asStringColumnMut().?;
    try left_name.append(left.arena.allocator(), "A");
    try left_name.append(left.arena.allocator(), "B");
    left.columnMut("name").?.length = 2;

    left.row_count = 2;

    const right_cols = [_]ColumnDesc{
        ColumnDesc.init("color", .String, 0),
    };
    var right = try DataFrame.create(allocator, &right_cols, 3);
    defer right.deinit();

    const right_color = right.columnMut("color").?.asStringColumnMut().?;
    try right_color.append(right.arena.allocator(), "Red");
    try right_color.append(right.arena.allocator(), "Green");
    try right_color.append(right.arena.allocator(), "Blue");
    right.columnMut("color").?.length = 3;

    right.row_count = 3;

    // Cross merge
    var result = try combine.merge(allocator, &left, &right, .{
        .how = .cross,
        .left_on = &[_][]const u8{"id"}, // Ignored in cross join
        .right_on = &[_][]const u8{"color"},
    });
    defer result.deinit();

    // Should have 2 * 3 = 6 rows (all combinations)
    try testing.expectEqual(@as(u32, 6), result.row_count);

    // Should have id, name, color columns
    try testing.expectEqual(@as(usize, 3), result.columns.len);
}

// Test 10: Memory leak test (100 iterations)
test "merge - memory leak test" {
    const allocator = testing.allocator;

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        var left = try createLeftDF(allocator);
        defer left.deinit();

        var right = try createRightDF(allocator);
        defer right.deinit();

        var result = try combine.merge(allocator, &left, &right, .{
            .how = .inner,
            .left_on = &[_][]const u8{"id"},
            .right_on = &[_][]const u8{"user_id"},
        });
        result.deinit();
    }

    // If we reach here, no leaks detected by testing.allocator
}
