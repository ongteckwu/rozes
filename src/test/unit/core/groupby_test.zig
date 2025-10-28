//! Unit tests for GroupBy functionality
//!
//! Tests grouping operations and aggregations for DataFrames.

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const GroupBy = @import("../../../core/dataframe.zig").GroupBy;
const AggSpec = @import("../../../core/dataframe.zig").AggSpec;
const AggFunc = @import("../../../core/dataframe.zig").AggFunc;
const ColumnDesc = @import("../../../core/types.zig").ColumnDesc;

test "GroupBy.init creates groups from DataFrame" {
    const allocator = testing.allocator;

    // Create DataFrame with city column
    const cols = [_]ColumnDesc{
        ColumnDesc.init("city", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    // Fill data: NYC, LA, NYC, SF, LA
    const city_col = df.columnMut("city").?;
    const string_col = city_col.asStringColumnMut().?;
    try string_col.append(df.arena.allocator(), "NYC");
    try string_col.append(df.arena.allocator(), "LA");
    try string_col.append(df.arena.allocator(), "NYC");
    try string_col.append(df.arena.allocator(), "SF");
    try string_col.append(df.arena.allocator(), "LA");

    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    ages[0] = 30;
    ages[1] = 25;
    ages[2] = 35;
    ages[3] = 28;
    ages[4] = 40;

    city_col.length = 5;
    age_col.length = 5;
    try df.setRowCount(5);

    // Group by city
    var grouped = try df.groupBy(allocator, "city");
    defer grouped.deinit();

    // Should have 3 groups: NYC, LA, SF
    try testing.expectEqual(@as(usize, 3), grouped.groups.items.len);
}

test "GroupBy.init groups Int64 column" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("category", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 6);
    defer df.deinit();

    // Fill data: categories 1, 2, 1, 3, 2, 1
    const cat_col = df.columnMut("category").?;
    const categories = cat_col.asInt64Buffer().?;
    categories[0] = 1;
    categories[1] = 2;
    categories[2] = 1;
    categories[3] = 3;
    categories[4] = 2;
    categories[5] = 1;

    const val_col = df.columnMut("value").?;
    const values = val_col.asFloat64Buffer().?;
    values[0] = 10.0;
    values[1] = 20.0;
    values[2] = 15.0;
    values[3] = 30.0;
    values[4] = 25.0;
    values[5] = 12.0;

    cat_col.length = 6;
    val_col.length = 6;
    try df.setRowCount(6);

    // Group by category
    var grouped = try df.groupBy(allocator, "category");
    defer grouped.deinit();

    // Should have 3 groups: 1, 2, 3
    try testing.expectEqual(@as(usize, 3), grouped.groups.items.len);
}

test "GroupBy.init groups Bool column" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("active", .Bool, 0),
        ColumnDesc.init("count", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    // Fill data: true, false, true, false
    const active_col = df.columnMut("active").?;
    const actives = active_col.asBoolBuffer().?;
    actives[0] = true;
    actives[1] = false;
    actives[2] = true;
    actives[3] = false;

    const count_col = df.columnMut("count").?;
    const counts = count_col.asInt64Buffer().?;
    counts[0] = 5;
    counts[1] = 3;
    counts[2] = 8;
    counts[3] = 2;

    active_col.length = 4;
    count_col.length = 4;
    try df.setRowCount(4);

    // Group by active
    var grouped = try df.groupBy(allocator, "active");
    defer grouped.deinit();

    // Should have 2 groups: true, false
    try testing.expectEqual(@as(usize, 2), grouped.groups.items.len);
}

test "GroupBy.agg computes count aggregation" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("city", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 5);
    defer df.deinit();

    // Fill data
    const city_col = df.columnMut("city").?;
    const string_col = city_col.asStringColumnMut().?;
    try string_col.append(df.arena.allocator(), "NYC");
    try string_col.append(df.arena.allocator(), "LA");
    try string_col.append(df.arena.allocator(), "NYC");
    try string_col.append(df.arena.allocator(), "SF");
    try string_col.append(df.arena.allocator(), "LA");

    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    ages[0] = 30;
    ages[1] = 25;
    ages[2] = 35;
    ages[3] = 28;
    ages[4] = 40;

    city_col.length = 5;
    age_col.length = 5;
    try df.setRowCount(5);

    // Group by city and count
    var grouped = try df.groupBy(allocator, "city");
    defer grouped.deinit();

    const specs = [_]AggSpec{
        .{ .column = "city", .func = .Count },
    };

    var result = try grouped.agg(allocator, &specs);
    defer result.deinit();

    // Should have 3 rows (NYC, LA, SF)
    try testing.expectEqual(@as(u32, 3), result.row_count);

    // Check count column exists
    const count_col = result.column("city_Count");
    try testing.expect(count_col != null);

    const counts = count_col.?.asFloat64().?;
    // Counts should be 2, 2, 1 (order may vary due to hash map)
    var total_count: f64 = 0;
    for (counts) |c| {
        total_count += c;
    }
    try testing.expectEqual(@as(f64, 5.0), total_count); // Total should be 5
}

test "GroupBy.agg computes sum aggregation for Int64" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("category", .Int64, 0),
        ColumnDesc.init("value", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    // Fill data: categories [1, 2, 1, 2], values [10, 20, 30, 40]
    const cat_col = df.columnMut("category").?;
    const categories = cat_col.asInt64Buffer().?;
    categories[0] = 1;
    categories[1] = 2;
    categories[2] = 1;
    categories[3] = 2;

    const val_col = df.columnMut("value").?;
    const values = val_col.asInt64Buffer().?;
    values[0] = 10;
    values[1] = 20;
    values[2] = 30;
    values[3] = 40;

    cat_col.length = 4;
    val_col.length = 4;
    try df.setRowCount(4);

    // Group by category and sum values
    var grouped = try df.groupBy(allocator, "category");
    defer grouped.deinit();

    const specs = [_]AggSpec{
        .{ .column = "value", .func = .Sum },
    };

    var result = try grouped.agg(allocator, &specs);
    defer result.deinit();

    // Should have 2 rows (category 1 and 2)
    try testing.expectEqual(@as(u32, 2), result.row_count);

    // Check sum column
    const sum_col = result.column("value_Sum");
    try testing.expect(sum_col != null);

    const sums = sum_col.?.asFloat64().?;
    var total_sum: f64 = 0;
    for (sums) |s| {
        total_sum += s;
    }
    // Total sum should be 10 + 20 + 30 + 40 = 100
    try testing.expectEqual(@as(f64, 100.0), total_sum);
}

test "GroupBy.agg computes sum aggregation for Float64" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("category", .Int64, 0),
        ColumnDesc.init("amount", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    // Fill data
    const cat_col = df.columnMut("category").?;
    const categories = cat_col.asInt64Buffer().?;
    categories[0] = 1;
    categories[1] = 2;
    categories[2] = 1;
    categories[3] = 2;

    const amt_col = df.columnMut("amount").?;
    const amounts = amt_col.asFloat64Buffer().?;
    amounts[0] = 10.5;
    amounts[1] = 20.3;
    amounts[2] = 15.2;
    amounts[3] = 25.0;

    cat_col.length = 4;
    amt_col.length = 4;
    try df.setRowCount(4);

    // Group and sum
    var grouped = try df.groupBy(allocator, "category");
    defer grouped.deinit();

    const specs = [_]AggSpec{
        .{ .column = "amount", .func = .Sum },
    };

    var result = try grouped.agg(allocator, &specs);
    defer result.deinit();

    try testing.expectEqual(@as(u32, 2), result.row_count);

    const sum_col = result.column("amount_Sum");
    const sums = sum_col.?.asFloat64().?;

    var total: f64 = 0;
    for (sums) |s| {
        total += s;
    }
    // Total should be 10.5 + 20.3 + 15.2 + 25.0 = 71.0
    try testing.expectApproxEqRel(@as(f64, 71.0), total, 0.0001);
}

test "GroupBy.agg computes mean aggregation" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("group", .Int64, 0),
        ColumnDesc.init("score", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 6);
    defer df.deinit();

    // Group 1: [10, 20, 30] → mean = 20
    // Group 2: [40, 50, 60] → mean = 50
    const grp_col = df.columnMut("group").?;
    const groups = grp_col.asInt64Buffer().?;
    groups[0] = 1;
    groups[1] = 1;
    groups[2] = 1;
    groups[3] = 2;
    groups[4] = 2;
    groups[5] = 2;

    const score_col = df.columnMut("score").?;
    const scores = score_col.asFloat64Buffer().?;
    scores[0] = 10.0;
    scores[1] = 20.0;
    scores[2] = 30.0;
    scores[3] = 40.0;
    scores[4] = 50.0;
    scores[5] = 60.0;

    grp_col.length = 6;
    score_col.length = 6;
    try df.setRowCount(6);

    // Group and compute mean
    var grouped = try df.groupBy(allocator, "group");
    defer grouped.deinit();

    const specs = [_]AggSpec{
        .{ .column = "score", .func = .Mean },
    };

    var result = try grouped.agg(allocator, &specs);
    defer result.deinit();

    try testing.expectEqual(@as(u32, 2), result.row_count);

    const mean_col = result.column("score_Mean");
    const means = mean_col.?.asFloat64().?;

    // One group should have mean 20, other should have mean 50
    const mean1 = means[0];
    const mean2 = means[1];

    if (mean1 == 20.0) {
        try testing.expectEqual(@as(f64, 50.0), mean2);
    } else {
        try testing.expectEqual(@as(f64, 50.0), mean1);
        try testing.expectEqual(@as(f64, 20.0), mean2);
    }
}

test "GroupBy.agg computes min aggregation" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("category", .Int64, 0),
        ColumnDesc.init("value", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    // Category 1: [30, 10] → min = 10
    // Category 2: [25, 40] → min = 25
    const cat_col = df.columnMut("category").?;
    const categories = cat_col.asInt64Buffer().?;
    categories[0] = 1;
    categories[1] = 2;
    categories[2] = 1;
    categories[3] = 2;

    const val_col = df.columnMut("value").?;
    const values = val_col.asInt64Buffer().?;
    values[0] = 30;
    values[1] = 25;
    values[2] = 10;
    values[3] = 40;

    cat_col.length = 4;
    val_col.length = 4;
    try df.setRowCount(4);

    var grouped = try df.groupBy(allocator, "category");
    defer grouped.deinit();

    const specs = [_]AggSpec{
        .{ .column = "value", .func = .Min },
    };

    var result = try grouped.agg(allocator, &specs);
    defer result.deinit();

    const min_col = result.column("value_Min");
    const mins = min_col.?.asFloat64().?;

    // Should have mins of 10 and 25 (order may vary)
    const min1 = mins[0];
    const min2 = mins[1];

    if (min1 == 10.0) {
        try testing.expectEqual(@as(f64, 25.0), min2);
    } else {
        try testing.expectEqual(@as(f64, 25.0), min1);
        try testing.expectEqual(@as(f64, 10.0), min2);
    }
}

test "GroupBy.agg computes max aggregation" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("category", .Int64, 0),
        ColumnDesc.init("value", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    // Category 1: [30, 10] → max = 30
    // Category 2: [25, 40] → max = 40
    const cat_col = df.columnMut("category").?;
    const categories = cat_col.asInt64Buffer().?;
    categories[0] = 1;
    categories[1] = 2;
    categories[2] = 1;
    categories[3] = 2;

    const val_col = df.columnMut("value").?;
    const values = val_col.asInt64Buffer().?;
    values[0] = 30;
    values[1] = 25;
    values[2] = 10;
    values[3] = 40;

    cat_col.length = 4;
    val_col.length = 4;
    try df.setRowCount(4);

    var grouped = try df.groupBy(allocator, "category");
    defer grouped.deinit();

    const specs = [_]AggSpec{
        .{ .column = "value", .func = .Max },
    };

    var result = try grouped.agg(allocator, &specs);
    defer result.deinit();

    const max_col = result.column("value_Max");
    const maxs = max_col.?.asFloat64().?;

    // Should have maxs of 30 and 40 (order may vary)
    const max1 = maxs[0];
    const max2 = maxs[1];

    if (max1 == 30.0) {
        try testing.expectEqual(@as(f64, 40.0), max2);
    } else {
        try testing.expectEqual(@as(f64, 40.0), max1);
        try testing.expectEqual(@as(f64, 30.0), max2);
    }
}

test "GroupBy.agg computes multiple aggregations" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("city", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
        ColumnDesc.init("score", .Float64, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 3);
    defer df.deinit();

    const city_col = df.columnMut("city").?;
    const string_col = city_col.asStringColumnMut().?;
    try string_col.append(df.arena.allocator(), "NYC");
    try string_col.append(df.arena.allocator(), "NYC");
    try string_col.append(df.arena.allocator(), "LA");

    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    ages[0] = 30;
    ages[1] = 40;
    ages[2] = 25;

    const score_col = df.columnMut("score").?;
    const scores = score_col.asFloat64Buffer().?;
    scores[0] = 90.0;
    scores[1] = 95.0;
    scores[2] = 85.0;

    city_col.length = 3;
    age_col.length = 3;
    score_col.length = 3;
    try df.setRowCount(3);

    var grouped = try df.groupBy(allocator, "city");
    defer grouped.deinit();

    const specs = [_]AggSpec{
        .{ .column = "age", .func = .Mean },
        .{ .column = "score", .func = .Sum },
        .{ .column = "city", .func = .Count },
    };

    var result = try grouped.agg(allocator, &specs);
    defer result.deinit();

    // Should have 2 groups (NYC, LA)
    try testing.expectEqual(@as(u32, 2), result.row_count);

    // Should have 4 columns: city, age_Mean, score_Sum, city_Count
    try testing.expectEqual(@as(usize, 4), result.columns.len);

    // Check columns exist
    try testing.expect(result.column("city") != null);
    try testing.expect(result.column("age_Mean") != null);
    try testing.expect(result.column("score_Sum") != null);
    try testing.expect(result.column("city_Count") != null);
}

test "GroupBy handles single-row groups" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 3);
    defer df.deinit();

    // Each row is its own group
    const id_col = df.columnMut("id").?;
    const ids = id_col.asInt64Buffer().?;
    ids[0] = 1;
    ids[1] = 2;
    ids[2] = 3;

    const val_col = df.columnMut("value").?;
    const values = val_col.asFloat64Buffer().?;
    values[0] = 10.0;
    values[1] = 20.0;
    values[2] = 30.0;

    id_col.length = 3;
    val_col.length = 3;
    try df.setRowCount(3);

    var grouped = try df.groupBy(allocator, "id");
    defer grouped.deinit();

    // Should have 3 groups
    try testing.expectEqual(@as(usize, 3), grouped.groups.items.len);

    const specs = [_]AggSpec{
        .{ .column = "value", .func = .Mean },
    };

    var result = try grouped.agg(allocator, &specs);
    defer result.deinit();

    // Mean of single value equals the value itself
    const mean_col = result.column("value_Mean");
    const means = mean_col.?.asFloat64().?;

    var total: f64 = 0;
    for (means) |m| {
        total += m;
    }
    // Total mean should equal sum of all values / 1 per group = 60
    try testing.expectEqual(@as(f64, 60.0), total);
}

test "GroupBy handles all rows in one group" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("category", .String, 0),
        ColumnDesc.init("amount", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 4);
    defer df.deinit();

    // All rows have same category
    const cat_col = df.columnMut("category").?;
    const string_col = cat_col.asStringColumnMut().?;
    try string_col.append(df.arena.allocator(), "A");
    try string_col.append(df.arena.allocator(), "A");
    try string_col.append(df.arena.allocator(), "A");
    try string_col.append(df.arena.allocator(), "A");

    const amt_col = df.columnMut("amount").?;
    const amounts = amt_col.asInt64Buffer().?;
    amounts[0] = 10;
    amounts[1] = 20;
    amounts[2] = 30;
    amounts[3] = 40;

    cat_col.length = 4;
    amt_col.length = 4;
    try df.setRowCount(4);

    var grouped = try df.groupBy(allocator, "category");
    defer grouped.deinit();

    // Should have only 1 group
    try testing.expectEqual(@as(usize, 1), grouped.groups.items.len);

    const specs = [_]AggSpec{
        .{ .column = "amount", .func = .Sum },
        .{ .column = "category", .func = .Count },
    };

    var result = try grouped.agg(allocator, &specs);
    defer result.deinit();

    try testing.expectEqual(@as(u32, 1), result.row_count);

    const sum_col = result.column("amount_Sum");
    const sums = sum_col.?.asFloat64().?;
    try testing.expectEqual(@as(f64, 100.0), sums[0]);

    const count_col = result.column("category_Count");
    const counts = count_col.?.asFloat64().?;
    try testing.expectEqual(@as(f64, 4.0), counts[0]);
}

test "GroupBy.agg returns error for non-numeric aggregation on String" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("category", .Int64, 0),
        ColumnDesc.init("name", .String, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 2);
    defer df.deinit();

    const cat_col = df.columnMut("category").?;
    const categories = cat_col.asInt64Buffer().?;
    categories[0] = 1;
    categories[1] = 1;

    const name_col = df.columnMut("name").?;
    const string_col = name_col.asStringColumnMut().?;
    try string_col.append(df.arena.allocator(), "Alice");
    try string_col.append(df.arena.allocator(), "Bob");

    cat_col.length = 2;
    name_col.length = 2;
    try df.setRowCount(2);

    var grouped = try df.groupBy(allocator, "category");
    defer grouped.deinit();

    // Try to sum a string column - should fail
    const specs = [_]AggSpec{
        .{ .column = "name", .func = .Sum },
    };

    const result = grouped.agg(allocator, &specs);
    try testing.expectError(error.TypeMismatch, result);
}
