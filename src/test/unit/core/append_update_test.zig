// append_update_test.zig - Tests for append() and update() operations
//
// Tests DataFrame append and update operations for correctness, error handling,
// and performance with large datasets.

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const Series = @import("../../../core/series.zig").Series;
const ColumnDesc = @import("../../../core/types.zig").ColumnDesc;
const ValueType = @import("../../../core/types.zig").ValueType;
const combine = @import("../../../core/combine.zig");
const append = combine.append;
const update = combine.update;
const AppendOptions = combine.AppendOptions;
const UpdateOptions = combine.UpdateOptions;

// ============================================================================
// Append Tests
// ============================================================================

test "append - basic append with matching schema" {
    const allocator = testing.allocator;

    // Create first DataFrame
    const cols1 = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var df1 = try DataFrame.create(allocator, &cols1, 3);
    defer df1.deinit();

    df1.row_count = 3;
    df1.columns[0].length = 3;
    df1.columns[1].length = 3;

    const id_data1 = df1.columns[0].data.Int64;
    id_data1[0] = 1;
    id_data1[1] = 2;
    id_data1[2] = 3;

    const val_data1 = df1.columns[1].data.Float64;
    val_data1[0] = 10.0;
    val_data1[1] = 20.0;
    val_data1[2] = 30.0;

    // Create second DataFrame
    const cols2 = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var df2 = try DataFrame.create(allocator, &cols2, 2);
    defer df2.deinit();

    df2.row_count = 2;
    df2.columns[0].length = 2;
    df2.columns[1].length = 2;

    const id_data2 = df2.columns[0].data.Int64;
    id_data2[0] = 4;
    id_data2[1] = 5;

    const val_data2 = df2.columns[1].data.Float64;
    val_data2[0] = 40.0;
    val_data2[1] = 50.0;

    // Append
    var result = try append(allocator, &df1, &df2, .{});
    defer result.deinit();

    // Verify
    try testing.expectEqual(@as(u32, 5), result.row_count);
    try testing.expectEqual(@as(usize, 2), result.columns.len);

    const id_result = result.columns[0].data.Int64;
    try testing.expectEqual(@as(i64, 1), id_result[0]);
    try testing.expectEqual(@as(i64, 2), id_result[1]);
    try testing.expectEqual(@as(i64, 3), id_result[2]);
    try testing.expectEqual(@as(i64, 4), id_result[3]);
    try testing.expectEqual(@as(i64, 5), id_result[4]);

    const val_result = result.columns[1].data.Float64;
    try testing.expectEqual(@as(f64, 10.0), val_result[0]);
    try testing.expectEqual(@as(f64, 50.0), val_result[4]);
}

test "append - schema mismatch - different column count" {
    const allocator = testing.allocator;

    // Create first DataFrame (2 columns)
    const cols1 = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var df1 = try DataFrame.create(allocator, &cols1, 2);
    defer df1.deinit();
    df1.row_count = 2;
    df1.columns[0].length = 2;
    df1.columns[1].length = 2;

    // Create second DataFrame (3 columns)
    const cols2 = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
        ColumnDesc.init("extra", .Int64, 2),
    };

    var df2 = try DataFrame.create(allocator, &cols2, 2);
    defer df2.deinit();
    df2.row_count = 2;
    df2.columns[0].length = 2;
    df2.columns[1].length = 2;
    df2.columns[2].length = 2;

    // Should fail with schema mismatch
    try testing.expectError(error.SchemaMismatch, append(allocator, &df1, &df2, .{}));
}

test "append - schema mismatch - different column names" {
    const allocator = testing.allocator;

    // Create first DataFrame
    const cols1 = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var df1 = try DataFrame.create(allocator, &cols1, 2);
    defer df1.deinit();
    df1.row_count = 2;
    df1.columns[0].length = 2;
    df1.columns[1].length = 2;

    // Create second DataFrame with different column name
    const cols2 = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("amount", .Float64, 1), // Different name
    };

    var df2 = try DataFrame.create(allocator, &cols2, 2);
    defer df2.deinit();
    df2.row_count = 2;
    df2.columns[0].length = 2;
    df2.columns[1].length = 2;

    // Should fail with schema mismatch
    try testing.expectError(error.SchemaMismatch, append(allocator, &df1, &df2, .{}));
}

test "append - schema mismatch - different column types" {
    const allocator = testing.allocator;

    // Create first DataFrame
    const cols1 = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var df1 = try DataFrame.create(allocator, &cols1, 2);
    defer df1.deinit();
    df1.row_count = 2;
    df1.columns[0].length = 2;
    df1.columns[1].length = 2;

    // Create second DataFrame with different column type
    const cols2 = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Int64, 1), // Int64 instead of Float64
    };

    var df2 = try DataFrame.create(allocator, &cols2, 2);
    defer df2.deinit();
    df2.row_count = 2;
    df2.columns[0].length = 2;
    df2.columns[1].length = 2;

    // Should fail with schema mismatch
    try testing.expectError(error.SchemaMismatch, append(allocator, &df1, &df2, .{}));
}

test "append - skip schema verification" {
    const allocator = testing.allocator;

    // Create first DataFrame
    const cols1 = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var df1 = try DataFrame.create(allocator, &cols1, 2);
    defer df1.deinit();
    df1.row_count = 2;
    df1.columns[0].length = 2;
    df1.columns[1].length = 2;

    // Create second DataFrame with different schema
    const cols2 = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("amount", .Float64, 1),
        ColumnDesc.init("extra", .Int64, 2),
    };

    var df2 = try DataFrame.create(allocator, &cols2, 2);
    defer df2.deinit();
    df2.row_count = 2;
    df2.columns[0].length = 2;
    df2.columns[1].length = 2;
    df2.columns[2].length = 2;

    // Should succeed with verify_schema=false (delegates to concat which handles schema alignment)
    var result = try append(allocator, &df1, &df2, .{ .verify_schema = false });
    defer result.deinit();

    try testing.expectEqual(@as(u32, 4), result.row_count);
}

test "append - memory leak test (100 iterations)" {
    const allocator = testing.allocator;

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const cols = [_]ColumnDesc{
            ColumnDesc.init("id", .Int64, 0),
            ColumnDesc.init("value", .Float64, 1),
        };

        var df1 = try DataFrame.create(allocator, &cols, 10);
        defer df1.deinit();
        df1.row_count = 10;
        df1.columns[0].length = 10;
        df1.columns[1].length = 10;

        var df2 = try DataFrame.create(allocator, &cols, 10);
        defer df2.deinit();
        df2.row_count = 10;
        df2.columns[0].length = 10;
        df2.columns[1].length = 10;

        var result = try append(allocator, &df1, &df2, .{});
        defer result.deinit();
    }
}

// ============================================================================
// Update Tests
// ============================================================================

test "update - basic update with matching key" {
    const allocator = testing.allocator;

    // Create base DataFrame
    const cols_base = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var base = try DataFrame.create(allocator, &cols_base, 3);
    defer base.deinit();

    base.row_count = 3;
    base.columns[0].length = 3;
    base.columns[1].length = 3;

    const id_base = base.columns[0].data.Int64;
    id_base[0] = 1;
    id_base[1] = 2;
    id_base[2] = 3;

    const val_base = base.columns[1].data.Float64;
    val_base[0] = 10.0;
    val_base[1] = 20.0;
    val_base[2] = 30.0;

    // Create update DataFrame
    const cols_update = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var updates = try DataFrame.create(allocator, &cols_update, 2);
    defer updates.deinit();

    updates.row_count = 2;
    updates.columns[0].length = 2;
    updates.columns[1].length = 2;

    const id_update = updates.columns[0].data.Int64;
    id_update[0] = 2; // Update id=2
    id_update[1] = 3; // Update id=3

    const val_update = updates.columns[1].data.Float64;
    val_update[0] = 200.0; // New value for id=2
    val_update[1] = 300.0; // New value for id=3

    // Update
    var result = try update(allocator, &base, &updates, .{
        .on = &[_][]const u8{"id"},
    });
    defer result.deinit();

    // Verify
    try testing.expectEqual(@as(u32, 3), result.row_count); // Same row count as base

    const id_result = result.columns[0].data.Int64;
    try testing.expectEqual(@as(i64, 1), id_result[0]); // Unchanged
    try testing.expectEqual(@as(i64, 2), id_result[1]);
    try testing.expectEqual(@as(i64, 3), id_result[2]);

    const val_result = result.columns[1].data.Float64;
    try testing.expectEqual(@as(f64, 10.0), val_result[0]); // Unchanged (no match)
    try testing.expectEqual(@as(f64, 200.0), val_result[1]); // Updated
    try testing.expectEqual(@as(f64, 300.0), val_result[2]); // Updated
}

test "update - no matching keys (no changes)" {
    const allocator = testing.allocator;

    // Create base DataFrame
    const cols_base = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var base = try DataFrame.create(allocator, &cols_base, 3);
    defer base.deinit();

    base.row_count = 3;
    base.columns[0].length = 3;
    base.columns[1].length = 3;

    const id_base = base.columns[0].data.Int64;
    id_base[0] = 1;
    id_base[1] = 2;
    id_base[2] = 3;

    const val_base = base.columns[1].data.Float64;
    val_base[0] = 10.0;
    val_base[1] = 20.0;
    val_base[2] = 30.0;

    // Create update DataFrame with non-matching keys
    const cols_update = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var updates = try DataFrame.create(allocator, &cols_update, 2);
    defer updates.deinit();

    updates.row_count = 2;
    updates.columns[0].length = 2;
    updates.columns[1].length = 2;

    const id_update = updates.columns[0].data.Int64;
    id_update[0] = 100; // No match
    id_update[1] = 200; // No match

    const val_update = updates.columns[1].data.Float64;
    val_update[0] = 1000.0;
    val_update[1] = 2000.0;

    // Update
    var result = try update(allocator, &base, &updates, .{
        .on = &[_][]const u8{"id"},
    });
    defer result.deinit();

    // Verify - all values should remain unchanged
    const val_result = result.columns[1].data.Float64;
    try testing.expectEqual(@as(f64, 10.0), val_result[0]);
    try testing.expectEqual(@as(f64, 20.0), val_result[1]);
    try testing.expectEqual(@as(f64, 30.0), val_result[2]);
}

test "update - multi-column key" {
    const allocator = testing.allocator;

    // Create base DataFrame
    const cols_base = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("year", .Int64, 1),
        ColumnDesc.init("value", .Float64, 2),
    };

    var base = try DataFrame.create(allocator, &cols_base, 4);
    defer base.deinit();

    base.row_count = 4;
    base.columns[0].length = 4;
    base.columns[1].length = 4;
    base.columns[2].length = 4;

    const id_base = base.columns[0].data.Int64;
    id_base[0] = 1;
    id_base[1] = 1; // Same id, different year
    id_base[2] = 2;
    id_base[3] = 2; // Same id, different year

    const year_base = base.columns[1].data.Int64;
    year_base[0] = 2020;
    year_base[1] = 2021;
    year_base[2] = 2020;
    year_base[3] = 2021;

    const val_base = base.columns[2].data.Float64;
    val_base[0] = 100.0;
    val_base[1] = 110.0;
    val_base[2] = 200.0;
    val_base[3] = 210.0;

    // Create update DataFrame
    const cols_update = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("year", .Int64, 1),
        ColumnDesc.init("value", .Float64, 2),
    };

    var updates = try DataFrame.create(allocator, &cols_update, 2);
    defer updates.deinit();

    updates.row_count = 2;
    updates.columns[0].length = 2;
    updates.columns[1].length = 2;
    updates.columns[2].length = 2;

    const id_update = updates.columns[0].data.Int64;
    id_update[0] = 1; // Update id=1, year=2020
    id_update[1] = 2; // Update id=2, year=2021

    const year_update = updates.columns[1].data.Int64;
    year_update[0] = 2020;
    year_update[1] = 2021;

    const val_update = updates.columns[2].data.Float64;
    val_update[0] = 1000.0;
    val_update[1] = 2100.0;

    // Update with multi-column key
    var result = try update(allocator, &base, &updates, .{
        .on = &[_][]const u8{ "id", "year" },
    });
    defer result.deinit();

    // Verify
    const val_result = result.columns[2].data.Float64;
    try testing.expectEqual(@as(f64, 1000.0), val_result[0]); // Updated (id=1, year=2020)
    try testing.expectEqual(@as(f64, 110.0), val_result[1]); // Unchanged (id=1, year=2021, no match)
    try testing.expectEqual(@as(f64, 200.0), val_result[2]); // Unchanged (id=2, year=2020, no match)
    try testing.expectEqual(@as(f64, 2100.0), val_result[3]); // Updated (id=2, year=2021)
}

test "update - partial column overlap" {
    const allocator = testing.allocator;

    // Create base DataFrame (3 columns)
    const cols_base = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value1", .Float64, 1),
        ColumnDesc.init("value2", .Float64, 2),
    };

    var base = try DataFrame.create(allocator, &cols_base, 2);
    defer base.deinit();

    base.row_count = 2;
    base.columns[0].length = 2;
    base.columns[1].length = 2;
    base.columns[2].length = 2;

    const id_base = base.columns[0].data.Int64;
    id_base[0] = 1;
    id_base[1] = 2;

    const val1_base = base.columns[1].data.Float64;
    val1_base[0] = 10.0;
    val1_base[1] = 20.0;

    const val2_base = base.columns[2].data.Float64;
    val2_base[0] = 100.0;
    val2_base[1] = 200.0;

    // Create update DataFrame (only has id and value1, not value2)
    const cols_update = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value1", .Float64, 1),
    };

    var updates = try DataFrame.create(allocator, &cols_update, 1);
    defer updates.deinit();

    updates.row_count = 1;
    updates.columns[0].length = 1;
    updates.columns[1].length = 1;

    const id_update = updates.columns[0].data.Int64;
    id_update[0] = 1;

    const val1_update = updates.columns[1].data.Float64;
    val1_update[0] = 1000.0;

    // Update
    var result = try update(allocator, &base, &updates, .{
        .on = &[_][]const u8{"id"},
    });
    defer result.deinit();

    // Verify - value1 updated, value2 unchanged
    const val1_result = result.columns[1].data.Float64;
    try testing.expectEqual(@as(f64, 1000.0), val1_result[0]); // Updated
    try testing.expectEqual(@as(f64, 20.0), val1_result[1]); // Unchanged

    const val2_result = result.columns[2].data.Float64;
    try testing.expectEqual(@as(f64, 100.0), val2_result[0]); // Unchanged (not in updates)
    try testing.expectEqual(@as(f64, 200.0), val2_result[1]); // Unchanged
}

test "update - memory leak test (100 iterations)" {
    const allocator = testing.allocator;

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const cols = [_]ColumnDesc{
            ColumnDesc.init("id", .Int64, 0),
            ColumnDesc.init("value", .Float64, 1),
        };

        var base = try DataFrame.create(allocator, &cols, 10);
        defer base.deinit();
        base.row_count = 10;
        base.columns[0].length = 10;
        base.columns[1].length = 10;

        var updates = try DataFrame.create(allocator, &cols, 5);
        defer updates.deinit();
        updates.row_count = 5;
        updates.columns[0].length = 5;
        updates.columns[1].length = 5;

        var result = try update(allocator, &base, &updates, .{
            .on = &[_][]const u8{"id"},
        });
        defer result.deinit();
    }
}

// ============================================================================
// Performance Tests
// ============================================================================

test "append - performance test (10K rows in batches)" {
    const allocator = testing.allocator;

    // Create base DataFrame
    const cols = [_]ColumnDesc{
        ColumnDesc.init("id", .Int64, 0),
        ColumnDesc.init("value", .Float64, 1),
    };

    var accumulated = try DataFrame.create(allocator, &cols, 100);
    defer accumulated.deinit();
    accumulated.row_count = 100;
    accumulated.columns[0].length = 100;
    accumulated.columns[1].length = 100;

    // Initialize base data
    var row: u32 = 0;
    while (row < 100) : (row += 1) {
        accumulated.columns[0].data.Int64[row] = @intCast(row);
        accumulated.columns[1].data.Float64[row] = @floatFromInt(row);
    }

    const start = std.time.milliTimestamp();

    // Append 100 batches of 100 rows each (10K total rows)
    var batch: u32 = 0;
    while (batch < 100) : (batch += 1) {
        var batch_df = try DataFrame.create(allocator, &cols, 100);
        defer batch_df.deinit();
        batch_df.row_count = 100;
        batch_df.columns[0].length = 100;
        batch_df.columns[1].length = 100;

        // Fill batch data
        row = 0;
        while (row < 100) : (row += 1) {
            batch_df.columns[0].data.Int64[row] = @intCast(100 * (batch + 1) + row);
            batch_df.columns[1].data.Float64[row] = @floatFromInt(100 * (batch + 1) + row);
        }

        const new_accumulated = try append(allocator, &accumulated, &batch_df, .{});
        accumulated.deinit();
        accumulated = new_accumulated;
    }

    const end = std.time.milliTimestamp();
    const duration = end - start;

    std.debug.print("\nAppend 10K rows (100 batches): {}ms\n", .{duration});

    // Verify final size
    try testing.expectEqual(@as(u32, 10100), accumulated.row_count); // 100 initial + 100*100 appended
}
