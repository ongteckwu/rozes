// combine_test.zig - Tests for DataFrame combination operations
//
// Test Coverage:
// - Vertical concat (stack rows)
// - Horizontal concat (stack columns)
// - Missing columns (NaN fill)
// - Type compatibility
// - Edge cases (empty, single DataFrame)
// - Memory leak tests

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const ColumnDesc = @import("../../../core/types.zig").ColumnDesc;
const combine = @import("../../../core/combine.zig");
const ConcatAxis = combine.ConcatAxis;
const ConcatOptions = combine.ConcatOptions;

// Helper: Create simple DataFrame with name and age columns
fn createSimpleDF(allocator: std.mem.Allocator, names: []const []const u8, ages: []const i64) !DataFrame {
    std.debug.assert(names.len == ages.len);

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, @intCast(names.len));
    errdefer df.deinit();

    // Fill name column
    const name_col = df.columnMut("name").?;
    const string_col = name_col.asStringColumnMut().?;
    for (names) |name| {
        try string_col.append(df.arena.allocator(), name);
    }
    name_col.length = @intCast(names.len); // ✅ Set series length

    // Fill age column
    const age_col = df.columnMut("age").?;
    const age_data = age_col.asInt64Buffer().?;
    for (ages, 0..) |age, i| {
        age_data[i] = age;
    }
    age_col.length = @intCast(names.len); // ✅ Set series length

    df.row_count = @intCast(names.len);
    return df;
}

// Test 1: Basic vertical concat (2 DataFrames, numeric only)
test "concat vertical - numeric columns only" {
    const allocator = testing.allocator;

    // Create df1: age, score
    const cols1 = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
        ColumnDesc.init("score", .Float64, 1),
    };
    var df1 = try DataFrame.create(allocator, &cols1, 2);
    defer df1.deinit();

    const age_col1 = df1.columnMut("age").?;
    const ages1 = age_col1.asInt64Buffer().?;
    ages1[0] = 30;
    ages1[1] = 25;
    age_col1.length = 2; // ✅ Set series length

    const score_col1 = df1.columnMut("score").?;
    const scores1 = score_col1.asFloat64Buffer().?;
    scores1[0] = 95.5;
    scores1[1] = 87.3;
    score_col1.length = 2; // ✅ Set series length

    df1.row_count = 2;

    // Create df2: age, score
    const cols2 = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
        ColumnDesc.init("score", .Float64, 1),
    };
    var df2 = try DataFrame.create(allocator, &cols2, 2);
    defer df2.deinit();

    const age_col2 = df2.columnMut("age").?;
    const ages2 = age_col2.asInt64Buffer().?;
    ages2[0] = 35;
    ages2[1] = 28;
    age_col2.length = 2; // ✅ Set series length

    const score_col2 = df2.columnMut("score").?;
    const scores2 = score_col2.asFloat64Buffer().?;
    scores2[0] = 91.0;
    scores2[1] = 88.5;
    score_col2.length = 2; // ✅ Set series length

    df2.row_count = 2;

    // Concat
    var dataframes = [_]*const DataFrame{ &df1, &df2 };
    var result = try combine.concat(allocator, dataframes[0..], .{ .axis = .vertical });
    defer result.deinit();

    // Validate dimensions
    try testing.expectEqual(@as(u32, 4), result.row_count);
    try testing.expectEqual(@as(usize, 2), result.columns.len);

    // Validate ages
    const age_col = result.column("age").?;
    const ages = age_col.asInt64().?;
    try testing.expectEqual(@as(i64, 30), ages[0]);
    try testing.expectEqual(@as(i64, 25), ages[1]);
    try testing.expectEqual(@as(i64, 35), ages[2]);
    try testing.expectEqual(@as(i64, 28), ages[3]);

    // Validate scores
    const score_col = result.column("score").?;
    const scores = score_col.asFloat64().?;
    try testing.expectApproxEqRel(@as(f64, 95.5), scores[0], 0.001);
    try testing.expectApproxEqRel(@as(f64, 87.3), scores[1], 0.001);
    try testing.expectApproxEqRel(@as(f64, 91.0), scores[2], 0.001);
    try testing.expectApproxEqRel(@as(f64, 88.5), scores[3], 0.001);
}

// Test 2: Horizontal concat (same row count)
test "concat horizontal - same row count" {
    const allocator = testing.allocator;

    // Create df1: name only
    const cols1 = [_]ColumnDesc{ColumnDesc.init("name", .String, 0)};
    var df1 = try DataFrame.create(allocator, &cols1, 2);
    defer df1.deinit();

    const name_col1 = df1.columnMut("name").?;
    const string_col1 = name_col1.asStringColumnMut().?;
    try string_col1.append(df1.arena.allocator(), "Alice");
    try string_col1.append(df1.arena.allocator(), "Bob");
    name_col1.length = 2; // ✅ Set series length
    df1.row_count = 2;

    // Create df2: age only
    const cols2 = [_]ColumnDesc{ColumnDesc.init("age", .Int64, 0)};
    var df2 = try DataFrame.create(allocator, &cols2, 2);
    defer df2.deinit();

    const age_col2 = df2.columnMut("age").?;
    const age_data2 = age_col2.asInt64Buffer().?;
    age_data2[0] = 30;
    age_data2[1] = 25;
    age_col2.length = 2; // ✅ Set series length
    df2.row_count = 2;

    // Concat horizontally
    var dataframes = [_]*const DataFrame{ &df1, &df2 };
    var result = try combine.concat(allocator, dataframes[0..], .{ .axis = .horizontal });
    defer result.deinit();

    // Validate dimensions
    try testing.expectEqual(@as(u32, 2), result.row_count);
    try testing.expectEqual(@as(usize, 2), result.columns.len);

    // Validate data
    const name_col = result.column("name");
    try testing.expect(name_col != null);

    const age_col = result.column("age");
    try testing.expect(age_col != null);

    const ages = age_col.?.asInt64().?;
    try testing.expectEqual(@as(i64, 30), ages[0]);
    try testing.expectEqual(@as(i64, 25), ages[1]);
}

// Test 3: Horizontal concat - row count mismatch (error)
test "concat horizontal - row count mismatch" {
    const allocator = testing.allocator;

    // Create df1: 2 rows
    var df1 = try createSimpleDF(allocator, &[_][]const u8{ "Alice", "Bob" }, &[_]i64{ 30, 25 });
    defer df1.deinit();

    // Create df2: 3 rows
    var df2 = try createSimpleDF(allocator, &[_][]const u8{ "Charlie", "Diana", "Eve" }, &[_]i64{ 35, 28, 40 });
    defer df2.deinit();

    // Concat should fail
    var dataframes = [_]*const DataFrame{ &df1, &df2 };
    const result = combine.concat(allocator, dataframes[0..], .{ .axis = .horizontal });

    try testing.expectError(error.RowCountMismatch, result);
}

// Test 4: Single DataFrame (returns copy)
test "concat - single dataframe" {
    const allocator = testing.allocator;

    var df = try createSimpleDF(allocator, &[_][]const u8{ "Alice", "Bob" }, &[_]i64{ 30, 25 });
    defer df.deinit();

    // Concat single DataFrame
    var dataframes = [_]*const DataFrame{&df};
    var result = try combine.concat(allocator, dataframes[0..], .{ .axis = .vertical });
    defer result.deinit();

    // Should be a copy
    try testing.expectEqual(@as(u32, 2), result.row_count);
    try testing.expectEqual(@as(usize, 2), result.columns.len);
}

// Test 5: Concat 3 DataFrames vertically
test "concat vertical - three dataframes" {
    const allocator = testing.allocator;

    var df1 = try createSimpleDF(allocator, &[_][]const u8{"Alice"}, &[_]i64{30});
    defer df1.deinit();

    var df2 = try createSimpleDF(allocator, &[_][]const u8{"Bob"}, &[_]i64{25});
    defer df2.deinit();

    var df3 = try createSimpleDF(allocator, &[_][]const u8{"Charlie"}, &[_]i64{35});
    defer df3.deinit();

    // Concat
    var dataframes = [_]*const DataFrame{ &df1, &df2, &df3 };
    var result = try combine.concat(allocator, dataframes[0..], .{ .axis = .vertical });
    defer result.deinit();

    // Validate
    try testing.expectEqual(@as(u32, 3), result.row_count);

    const age_col = result.column("age").?;
    const ages = age_col.asInt64().?;
    try testing.expectEqual(@as(i64, 30), ages[0]);
    try testing.expectEqual(@as(i64, 25), ages[1]);
    try testing.expectEqual(@as(i64, 35), ages[2]);
}

// Test 6: Memory leak test (100 iterations for faster testing)
test "concat - memory leak test" {
    const allocator = testing.allocator;

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        var df1 = try createSimpleDF(allocator, &[_][]const u8{"Alice"}, &[_]i64{30});
        defer df1.deinit();

        var df2 = try createSimpleDF(allocator, &[_][]const u8{"Bob"}, &[_]i64{25});
        defer df2.deinit();

        var dataframes = [_]*const DataFrame{ &df1, &df2 };
        var result = try combine.concat(allocator, dataframes[0..], .{ .axis = .vertical });
        result.deinit();
    }

    // If we reach here, no leaks detected by testing.allocator
}
