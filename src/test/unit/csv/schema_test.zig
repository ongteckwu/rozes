//! Unit Tests for CSV Manual Schema Specification
//!
//! Tests manual type specification overriding auto-detection,
//! especially for categorical type assignment.

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const ValueType = @import("../../../core/types.zig").ValueType;
const CSVOptions = @import("../../../core/types.zig").CSVOptions;
const SchemaMap = @import("../../../core/types.zig").SchemaMap;

// Test 1: Basic schema specification for single column
test "Schema: force column to Int64" {
    const allocator = testing.allocator;

    const csv = "value\n42\n100\n200\n";

    // Create manual schema
    var schema = SchemaMap.init(allocator);
    defer schema.deinit();
    try schema.put("value", .Int64);

    // Parse with manual schema
    var opts = CSVOptions{};
    opts.schema = &schema;

    var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
    defer df.deinit();

    // Verify column type is Int64
    try testing.expectEqual(@as(usize, 1), df.columnCount());
    const col = df.column("value").?;
    try testing.expectEqual(ValueType.Int64, col.value_type);

    // Verify values
    const data = col.asInt64().?;
    try testing.expectEqual(@as(i64, 42), data[0]);
    try testing.expectEqual(@as(i64, 100), data[1]);
    try testing.expectEqual(@as(i64, 200), data[2]);
}

// Test 2: Force column to Categorical (override auto-detection)
test "Schema: force column to Categorical" {
    const allocator = testing.allocator;

    const csv = "region\nEast\nWest\nEast\nSouth\nEast\n";

    // Create manual schema to force categorical
    var schema = SchemaMap.init(allocator);
    defer schema.deinit();
    try schema.put("region", .Categorical);

    var opts = CSVOptions{};
    opts.schema = &schema;

    var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
    defer df.deinit();

    // Verify column type is Categorical
    const col = df.column("region").?;
    try testing.expectEqual(ValueType.Categorical, col.value_type);

    // Verify categorical encoding
    const cat_col = col.asCategoricalColumn().?;
    try testing.expectEqual(@as(u32, 5), cat_col.count);
    try testing.expectEqual(@as(u32, 3), cat_col.categoryCount()); // East, West, South
}

// Test 3: Mixed schema - some columns manual, some auto-detected
test "Schema: mixed manual and auto-detection" {
    const allocator = testing.allocator;

    const csv = "name,age,region\nAlice,30,East\nBob,25,West\nCharlie,35,East\n";

    // Specify only region as categorical, let others auto-detect
    var schema = SchemaMap.init(allocator);
    defer schema.deinit();
    try schema.put("region", .Categorical);

    var opts = CSVOptions{};
    opts.schema = &schema;

    var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
    defer df.deinit();

    // Verify types
    try testing.expectEqual(ValueType.String, df.column("name").?.value_type); // Auto-detected
    try testing.expectEqual(ValueType.Int64, df.column("age").?.value_type); // Auto-detected
    try testing.expectEqual(ValueType.Categorical, df.column("region").?.value_type); // Manual
}

// Test 4: Schema with multiple categorical columns
test "Schema: multiple categorical columns" {
    const allocator = testing.allocator;

    const csv = "region,country,city\nEast,USA,NYC\nWest,USA,LA\nEast,UK,London\n";

    // Force all three columns to categorical
    var schema = SchemaMap.init(allocator);
    defer schema.deinit();
    try schema.put("region", .Categorical);
    try schema.put("country", .Categorical);
    try schema.put("city", .Categorical);

    var opts = CSVOptions{};
    opts.schema = &schema;

    var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
    defer df.deinit();

    // Verify all columns are categorical
    try testing.expectEqual(ValueType.Categorical, df.column("region").?.value_type);
    try testing.expectEqual(ValueType.Categorical, df.column("country").?.value_type);
    try testing.expectEqual(ValueType.Categorical, df.column("city").?.value_type);

    // Verify category counts
    try testing.expectEqual(@as(u32, 2), df.column("region").?.asCategoricalColumn().?.categoryCount());
    try testing.expectEqual(@as(u32, 2), df.column("country").?.asCategoricalColumn().?.categoryCount());
    try testing.expectEqual(@as(u32, 3), df.column("city").?.asCategoricalColumn().?.categoryCount());
}

// Test 5: Schema overrides String → Categorical
test "Schema: override String inference with Categorical" {
    const allocator = testing.allocator;

    // High cardinality data that would normally be String
    const csv = "id\nA001\nA002\nA003\nA004\nA005\n";

    // Force to categorical even though cardinality is high
    var schema = SchemaMap.init(allocator);
    defer schema.deinit();
    try schema.put("id", .Categorical);

    var opts = CSVOptions{};
    opts.schema = &schema;

    var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
    defer df.deinit();

    // Should be categorical (manual override)
    try testing.expectEqual(ValueType.Categorical, df.column("id").?.value_type);
    try testing.expectEqual(@as(u32, 5), df.column("id").?.asCategoricalColumn().?.categoryCount());
}

// Test 6: Schema overrides Float64 → Int64
test "Schema: override Float64 inference with Int64" {
    const allocator = testing.allocator;

    const csv = "value\n10.0\n20.0\n30.0\n";

    // Force to Int64 even though fields have decimals
    var schema = SchemaMap.init(allocator);
    defer schema.deinit();
    try schema.put("value", .Int64);

    var opts = CSVOptions{};
    opts.schema = &schema;

    var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
    defer df.deinit();

    // Should be Int64 (note: parsing might fail if not valid integers)
    try testing.expectEqual(ValueType.Int64, df.column("value").?.value_type);
}

// Test 7: Schema with non-existent column (should be ignored)
test "Schema: non-existent column in schema is ignored" {
    const allocator = testing.allocator;

    const csv = "age\n30\n25\n";

    // Schema specifies column that doesn't exist
    var schema = SchemaMap.init(allocator);
    defer schema.deinit();
    try schema.put("age", .Int64);
    try schema.put("nonexistent", .Categorical); // This column doesn't exist

    var opts = CSVOptions{};
    opts.schema = &schema;

    var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
    defer df.deinit();

    // Should parse successfully, ignoring non-existent column
    try testing.expectEqual(@as(usize, 1), df.columnCount());
    try testing.expectEqual(ValueType.Int64, df.column("age").?.value_type);
}

// Test 8: Schema with infer_types = false
test "Schema: use schema only when infer_types = false" {
    const allocator = testing.allocator;

    const csv = "name,age\nAlice,30\nBob,25\n";

    // Disable auto-inference, rely entirely on schema
    var schema = SchemaMap.init(allocator);
    defer schema.deinit();
    try schema.put("name", .String);
    try schema.put("age", .Int64);

    var opts = CSVOptions{};
    opts.infer_types = false;
    opts.schema = &schema;

    var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
    defer df.deinit();

    // Columns should use schema types
    try testing.expectEqual(ValueType.String, df.column("name").?.value_type);
    try testing.expectEqual(ValueType.Int64, df.column("age").?.value_type);
}

// Test 9: Schema with partial specification and infer_types = false
test "Schema: partial schema with infer_types = false defaults to String" {
    const allocator = testing.allocator;

    const csv = "name,age,city\nAlice,30,NYC\n";

    // Only specify age, leave others unspecified
    var schema = SchemaMap.init(allocator);
    defer schema.deinit();
    try schema.put("age", .Int64);

    var opts = CSVOptions{};
    opts.infer_types = false;
    opts.schema = &schema;

    var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
    defer df.deinit();

    // Specified column uses schema, others default to String
    try testing.expectEqual(ValueType.String, df.column("name").?.value_type);
    try testing.expectEqual(ValueType.Int64, df.column("age").?.value_type);
    try testing.expectEqual(ValueType.String, df.column("city").?.value_type);
}

// Test 10: Large dataset with categorical schema
test "Schema: large dataset with categorical specification" {
    const allocator = testing.allocator;

    // Generate CSV with 1000 rows
    var csv_buf = std.ArrayList(u8).init(allocator);
    defer csv_buf.deinit();

    try csv_buf.appendSlice("region\n");
    const regions = [_][]const u8{ "North", "South", "East", "West", "Central" };

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        try csv_buf.writer().print("{s}\n", .{regions[i % 5]});
    }

    // Force to categorical
    var schema = SchemaMap.init(allocator);
    defer schema.deinit();
    try schema.put("region", .Categorical);

    var opts = CSVOptions{};
    opts.schema = &schema;

    var df = try DataFrame.fromCSVBuffer(allocator, csv_buf.items, opts);
    defer df.deinit();

    // Verify categorical type and category count
    try testing.expectEqual(ValueType.Categorical, df.column("region").?.value_type);
    try testing.expectEqual(@as(u32, 1000), df.len());
    try testing.expectEqual(@as(u32, 5), df.column("region").?.asCategoricalColumn().?.categoryCount());
}

// Test 11: Schema validation - empty schema error
test "Schema: empty schema returns error" {
    const allocator = testing.allocator;

    var schema = SchemaMap.init(allocator);
    defer schema.deinit();
    // Empty schema (no entries)

    var opts = CSVOptions{};
    opts.schema = &schema;

    // Should fail validation
    try testing.expectError(error.EmptySchema, opts.validate());
}

// Test 12: Memory leak test with schema
test "Schema: no memory leaks with repeated parsing" {
    const allocator = testing.allocator;

    const csv = "region\nEast\nWest\n";

    var iter: u32 = 0;
    while (iter < 1000) : (iter += 1) {
        var schema = SchemaMap.init(allocator);
        defer schema.deinit();
        try schema.put("region", .Categorical);

        var opts = CSVOptions{};
        opts.schema = &schema;

        var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
        df.deinit();
    }

    // testing.allocator will report leaks automatically
}
