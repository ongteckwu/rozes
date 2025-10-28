//! Unit tests for additional DataFrame operations
//!
//! Tests for: unique(), dropDuplicates(), rename(), head(), tail(), describe()

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const ColumnDesc = @import("../../../core/types.zig").ColumnDesc;
const Summary = @import("../../../core/additional_ops.zig").Summary;

// ============================================================================
// unique() tests
// ============================================================================

test "unique returns distinct Int64 values" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("values", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const values = df.columns[0].asInt64Buffer() orelse unreachable;
    // Data: [1, 2, 2, 3, 3, 3, 4, 4, 4, 4]
    values[0] = 1;
    values[1] = 2;
    values[2] = 2;
    values[3] = 3;
    values[4] = 3;
    values[5] = 3;
    values[6] = 4;
    values[7] = 4;
    values[8] = 4;
    values[9] = 4;
    try df.setRowCount(10);

    const unique_values = try df.unique(allocator, "values");
    defer {
        for (unique_values) |val| allocator.free(val);
        allocator.free(unique_values);
    }

    // Should have 4 unique values: 1, 2, 3, 4
    try testing.expectEqual(@as(usize, 4), unique_values.len);
}

test "unique returns distinct String values" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("city", .String, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    var col = &df.columns[0];
    try col.appendString(df.arena.allocator(), "NYC");
    try col.appendString(df.arena.allocator(), "LA");
    try col.appendString(df.arena.allocator(), "NYC");
    try col.appendString(df.arena.allocator(), "SF");
    try col.appendString(df.arena.allocator(), "LA");
    try df.setRowCount(5);

    const unique_values = try df.unique(allocator, "city");
    defer {
        for (unique_values) |val| allocator.free(val);
        allocator.free(unique_values);
    }

    // Should have 3 unique values: NYC, LA, SF
    try testing.expectEqual(@as(usize, 3), unique_values.len);
}

test "unique returns error for non-existent column" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();
    try df.setRowCount(5);

    try testing.expectError(error.ColumnNotFound, df.unique(allocator, "nonexistent"));
}

test "unique handles Bool column (max 2 values)" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("flag", .Bool, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const flags = df.columns[0].asBoolBuffer() orelse unreachable;
    flags[0] = true;
    flags[1] = false;
    flags[2] = true;
    flags[3] = false;
    flags[4] = true;
    try df.setRowCount(5);

    const unique_values = try df.unique(allocator, "flag");
    defer {
        for (unique_values) |val| allocator.free(val);
        allocator.free(unique_values);
    }

    // Should have 2 values: true, false
    try testing.expectEqual(@as(usize, 2), unique_values.len);
}

// ============================================================================
// dropDuplicates() tests
// ============================================================================

test "dropDuplicates removes duplicate rows (all columns)" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    // Add data with duplicates
    var name_col = &df.columns[0];
    try name_col.appendString(df.arena.allocator(), "Alice");
    try name_col.appendString(df.arena.allocator(), "Bob");
    try name_col.appendString(df.arena.allocator(), "Alice"); // Duplicate
    try name_col.appendString(df.arena.allocator(), "Charlie");
    try name_col.appendString(df.arena.allocator(), "Bob"); // Duplicate

    const ages = df.columns[1].asInt64Buffer() orelse unreachable;
    ages[0] = 30;
    ages[1] = 25;
    ages[2] = 30; // Same as row 0
    ages[3] = 35;
    ages[4] = 25; // Same as row 1

    try df.setRowCount(5);

    var result = try df.dropDuplicates(allocator, null);
    defer result.deinit();

    // Should have 3 unique rows: Alice/30, Bob/25, Charlie/35
    try testing.expectEqual(@as(u32, 3), result.row_count);
}

test "dropDuplicates with subset columns" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
        ColumnDesc.init("score", .Float64, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    // Add data - duplicate names but different scores
    var name_col = &df.columns[0];
    try name_col.appendString(df.arena.allocator(), "Alice");
    try name_col.appendString(df.arena.allocator(), "Bob");
    try name_col.appendString(df.arena.allocator(), "Alice"); // Duplicate name
    try name_col.appendString(df.arena.allocator(), "Bob"); // Duplicate name

    const ages = df.columns[1].asInt64Buffer() orelse unreachable;
    ages[0] = 30;
    ages[1] = 25;
    ages[2] = 30;
    ages[3] = 25;

    const scores = df.columns[2].asFloat64Buffer() orelse unreachable;
    scores[0] = 95.5;
    scores[1] = 87.3;
    scores[2] = 92.0; // Different score for Alice
    scores[3] = 88.0; // Different score for Bob

    try df.setRowCount(4);

    // Drop duplicates based on name only
    const subset = [_][]const u8{"name"};
    var result = try df.dropDuplicates(allocator, &subset);
    defer result.deinit();

    // Should have 2 rows: first Alice, first Bob
    try testing.expectEqual(@as(u32, 2), result.row_count);
}

test "dropDuplicates preserves order (keeps first occurrence)" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const ids = df.columns[0].asInt64Buffer() orelse unreachable;
    ids[0] = 1;
    ids[1] = 2;
    ids[2] = 1; // Duplicate
    ids[3] = 3;
    ids[4] = 2; // Duplicate

    const values = df.columns[1].asInt64Buffer() orelse unreachable;
    values[0] = 100;
    values[1] = 200;
    values[2] = 999; // Should be ignored
    values[3] = 300;
    values[4] = 888; // Should be ignored

    try df.setRowCount(5);

    const subset = [_][]const u8{"id"};
    var result = try df.dropDuplicates(allocator, &subset);
    defer result.deinit();

    // Should have 3 rows in original order
    try testing.expectEqual(@as(u32, 3), result.row_count);

    const result_ids = result.columns[0].asInt64() orelse unreachable;
    const result_values = result.columns[1].asInt64() orelse unreachable;

    // Verify first occurrences kept
    try testing.expectEqual(@as(i64, 1), result_ids[0]);
    try testing.expectEqual(@as(i64, 100), result_values[0]); // First id=1

    try testing.expectEqual(@as(i64, 2), result_ids[1]);
    try testing.expectEqual(@as(i64, 200), result_values[1]); // First id=2

    try testing.expectEqual(@as(i64, 3), result_ids[2]);
    try testing.expectEqual(@as(i64, 300), result_values[2]);
}

// ============================================================================
// rename() tests
// ============================================================================

test "rename changes column names" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("old_name", .Int64, 0),
        ColumnDesc.init("old_score", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();
    try df.setRowCount(5);

    var rename_map = std.StringHashMap([]const u8).init(allocator);
    defer rename_map.deinit();

    try rename_map.put("old_name", "new_name");
    try rename_map.put("old_score", "new_score");

    var result = try df.rename(allocator, &rename_map);
    defer result.deinit();

    try testing.expectEqualStrings("new_name", result.column_descs[0].name);
    try testing.expectEqualStrings("new_score", result.column_descs[1].name);
}

test "rename preserves data" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 3);
    defer df.deinit();

    const ages = df.columns[0].asInt64Buffer() orelse unreachable;
    ages[0] = 30;
    ages[1] = 25;
    ages[2] = 35;
    try df.setRowCount(3);

    var rename_map = std.StringHashMap([]const u8).init(allocator);
    defer rename_map.deinit();
    try rename_map.put("age", "years");

    var result = try df.rename(allocator, &rename_map);
    defer result.deinit();

    const result_ages = result.columns[0].asInt64() orelse unreachable;
    try testing.expectEqual(@as(i64, 30), result_ages[0]);
    try testing.expectEqual(@as(i64, 25), result_ages[1]);
    try testing.expectEqual(@as(i64, 35), result_ages[2]);
}

test "rename keeps unmapped columns unchanged" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 1);
    defer df.deinit();

    // Initialize string column data
    try df.columns[0].appendString(df.arena.allocator(), "Alice");

    // Initialize int column data
    const ages = df.columns[1].asInt64Buffer() orelse unreachable;
    ages[0] = 30;

    try df.setRowCount(1);

    var rename_map = std.StringHashMap([]const u8).init(allocator);
    defer rename_map.deinit();
    try rename_map.put("age", "years"); // Only rename age

    var result = try df.rename(allocator, &rename_map);
    defer result.deinit();

    try testing.expectEqualStrings("name", result.column_descs[0].name); // Unchanged
    try testing.expectEqualStrings("years", result.column_descs[1].name); // Renamed
}

// ============================================================================
// head() tests
// ============================================================================

test "head returns first n rows" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const ids = df.columns[0].asInt64Buffer() orelse unreachable;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        ids[i] = @intCast(i + 1);
    }
    try df.setRowCount(10);

    var result = try df.head(allocator, 3);
    defer result.deinit();

    try testing.expectEqual(@as(u32, 3), result.row_count);

    const result_ids = result.columns[0].asInt64() orelse unreachable;
    try testing.expectEqual(@as(i64, 1), result_ids[0]);
    try testing.expectEqual(@as(i64, 2), result_ids[1]);
    try testing.expectEqual(@as(i64, 3), result_ids[2]);
}

test "head returns all rows if n > row_count" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();
    try df.setRowCount(5);

    var result = try df.head(allocator, 100);
    defer result.deinit();

    try testing.expectEqual(@as(u32, 5), result.row_count);
}

test "head works with String columns" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 3);
    defer df.deinit();

    var col = &df.columns[0];
    try col.appendString(df.arena.allocator(), "Alice");
    try col.appendString(df.arena.allocator(), "Bob");
    try col.appendString(df.arena.allocator(), "Charlie");
    try df.setRowCount(3);

    var result = try df.head(allocator, 2);
    defer result.deinit();

    try testing.expectEqual(@as(u32, 2), result.row_count);

    const result_col = result.columns[0].asStringColumn() orelse unreachable;
    try testing.expectEqualStrings("Alice", result_col.get(0));
    try testing.expectEqualStrings("Bob", result_col.get(1));
}

// ============================================================================
// tail() tests
// ============================================================================

test "tail returns last n rows" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const ids = df.columns[0].asInt64Buffer() orelse unreachable;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        ids[i] = @intCast(i + 1);
    }
    try df.setRowCount(10);

    var result = try df.tail(allocator, 3);
    defer result.deinit();

    try testing.expectEqual(@as(u32, 3), result.row_count);

    const result_ids = result.columns[0].asInt64() orelse unreachable;
    try testing.expectEqual(@as(i64, 8), result_ids[0]);
    try testing.expectEqual(@as(i64, 9), result_ids[1]);
    try testing.expectEqual(@as(i64, 10), result_ids[2]);
}

test "tail returns all rows if n > row_count" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();
    try df.setRowCount(5);

    var result = try df.tail(allocator, 100);
    defer result.deinit();

    try testing.expectEqual(@as(u32, 5), result.row_count);
}

test "tail works with String columns" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 3);
    defer df.deinit();

    var col = &df.columns[0];
    try col.appendString(df.arena.allocator(), "Alice");
    try col.appendString(df.arena.allocator(), "Bob");
    try col.appendString(df.arena.allocator(), "Charlie");
    try df.setRowCount(3);

    var result = try df.tail(allocator, 2);
    defer result.deinit();

    try testing.expectEqual(@as(u32, 2), result.row_count);

    const result_col = result.columns[0].asStringColumn() orelse unreachable;
    try testing.expectEqualStrings("Bob", result_col.get(0));
    try testing.expectEqualStrings("Charlie", result_col.get(1));
}

// ============================================================================
// describe() tests
// ============================================================================

test "describe returns statistical summary for Int64 column" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    const ages = df.columns[0].asInt64Buffer() orelse unreachable;
    // Ages: [20, 30, 40, 50, 60]
    ages[0] = 20;
    ages[1] = 30;
    ages[2] = 40;
    ages[3] = 50;
    ages[4] = 60;
    try df.setRowCount(5);

    var summary = try df.describe(allocator);
    defer summary.deinit();

    const age_summary = summary.get("age") orelse return error.ColumnNotFound;

    try testing.expectEqual(@as(u32, 5), age_summary.count);
    try testing.expectEqual(@as(?f64, 40.0), age_summary.mean);
    try testing.expectEqual(@as(?f64, 20.0), age_summary.min);
    try testing.expectEqual(@as(?f64, 60.0), age_summary.max);

    // Standard deviation should be ~14.14
    try testing.expect(age_summary.std.? > 14.0 and age_summary.std.? < 15.0);
}

test "describe returns statistical summary for Float64 column" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("score", .Float64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 3);
    defer df.deinit();

    const scores = df.columns[0].asFloat64Buffer() orelse unreachable;
    scores[0] = 85.5;
    scores[1] = 90.0;
    scores[2] = 95.5;
    try df.setRowCount(3);

    var summary = try df.describe(allocator);
    defer summary.deinit();

    const score_summary = summary.get("score") orelse return error.ColumnNotFound;

    try testing.expectEqual(@as(u32, 3), score_summary.count);
    try testing.expectApproxEqAbs(@as(f64, 90.33), score_summary.mean.?, 0.01);
    try testing.expectEqual(@as(?f64, 85.5), score_summary.min);
    try testing.expectEqual(@as(?f64, 95.5), score_summary.max);
}

test "describe handles non-numeric columns (returns count only)" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 2);
    defer df.deinit();

    var name_col = &df.columns[0];
    try name_col.appendString(df.arena.allocator(), "Alice");
    try name_col.appendString(df.arena.allocator(), "Bob");

    const ages = df.columns[1].asInt64Buffer() orelse unreachable;
    ages[0] = 30;
    ages[1] = 25;

    try df.setRowCount(2);

    var summary = try df.describe(allocator);
    defer summary.deinit();

    const name_summary = summary.get("name") orelse return error.ColumnNotFound;
    try testing.expectEqual(@as(u32, 2), name_summary.count);
    try testing.expectEqual(@as(?f64, null), name_summary.mean);
    try testing.expectEqual(@as(?f64, null), name_summary.std);
    try testing.expectEqual(@as(?f64, null), name_summary.min);
    try testing.expectEqual(@as(?f64, null), name_summary.max);

    const age_summary = summary.get("age") orelse return error.ColumnNotFound;
    try testing.expectEqual(@as(u32, 2), age_summary.count);
    try testing.expect(age_summary.mean != null); // Numeric column has stats
}

test "describe handles empty DataFrame" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 1);
    defer df.deinit();
    try df.setRowCount(0);

    var summary = try df.describe(allocator);
    defer summary.deinit();

    // Empty DataFrame should still have column entry but with count=0
    try testing.expectEqual(@as(usize, 1), summary.count());
}
