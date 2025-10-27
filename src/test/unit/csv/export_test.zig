//! Unit tests for CSV export functionality
//!
//! Tests for src/csv/export.zig

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const ColumnDesc = @import("../../../core/types.zig").ColumnDesc;
const CSVOptions = @import("../../../core/types.zig").CSVOptions;
const CSVParser = @import("../../../csv/parser.zig").CSVParser;
const toCSV = @import("../../../csv/export.zig").toCSV;

test "CSV round-trip: parse and export" {
    const allocator = testing.allocator;

    const original_csv = "age,score\n30,95.5\n25,87.3\n";

    // Parse CSV
    var parser = try CSVParser.init(allocator, original_csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Export back to CSV
    const exported_csv = try df.toCSV(allocator, .{});
    defer allocator.free(exported_csv);

    // Parse exported CSV
    var parser2 = try CSVParser.init(allocator, exported_csv, .{});
    defer parser2.deinit();

    var df2 = try parser2.toDataFrame();
    defer df2.deinit();

    // Verify data matches
    try testing.expectEqual(df.len(), df2.len());
    try testing.expectEqual(df.columnCount(), df2.columnCount());

    // Check age column
    const ages1 = df.column("age").?.asInt64().?;
    const ages2 = df2.column("age").?.asInt64().?;
    try testing.expectEqual(ages1[0], ages2[0]);
    try testing.expectEqual(ages1[1], ages2[1]);

    // Check score column
    const scores1 = df.column("score").?.asFloat64().?;
    const scores2 = df2.column("score").?.asFloat64().?;

    // Allow small floating point differences
    try testing.expectApproxEqRel(scores1[0], scores2[0], 0.01);
    try testing.expectApproxEqRel(scores1[1], scores2[1], 0.01);
}

test "CSV export: quoted fields with commas" {
    const allocator = testing.allocator;

    // This would need string column support (0.2.0+)
    // For now, test that numeric columns work correctly
    const cols = [_]ColumnDesc{
        ColumnDesc.init("value", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const col = df.columnMut("value").?;
    const data = col.asInt64Buffer().?;
    data[0] = 1000;
    data[1] = 2000;

    try df.setRowCount(2);

    const csv = try df.toCSV(allocator, .{});
    defer allocator.free(csv);

    // Should not quote numeric values
    try testing.expect(std.mem.indexOf(u8, csv, "\"") == null);
    try testing.expect(std.mem.indexOf(u8, csv, "1000") != null);
    try testing.expect(std.mem.indexOf(u8, csv, "2000") != null);
}

test "CSV export: empty DataFrame" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("a", .Int64, 0),
        ColumnDesc.init("b", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    try df.setRowCount(0);

    const csv = try df.toCSV(allocator, .{});
    defer allocator.free(csv);

    // Should only have header
    try testing.expectEqualStrings("a,b\n", csv);
}

test "CSV export: single row" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("x", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const col = df.columnMut("x").?;
    const data = col.asInt64Buffer().?;
    data[0] = 42;

    try df.setRowCount(1);

    const csv = try df.toCSV(allocator, .{});
    defer allocator.free(csv);

    try testing.expect(std.mem.indexOf(u8, csv, "x\n") != null);
    try testing.expect(std.mem.indexOf(u8, csv, "42") != null);
}

test "CSV export: multiple columns" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("a", .Int64, 0),
        ColumnDesc.init("b", .Int64, 1),
        ColumnDesc.init("c", .Int64, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const col_a = df.columnMut("a").?;
    col_a.asInt64Buffer().?[0] = 1;

    const col_b = df.columnMut("b").?;
    col_b.asInt64Buffer().?[0] = 2;

    const col_c = df.columnMut("c").?;
    col_c.asInt64Buffer().?[0] = 3;

    try df.setRowCount(1);

    const csv = try df.toCSV(allocator, .{});
    defer allocator.free(csv);

    try testing.expect(std.mem.indexOf(u8, csv, "a,b,c") != null);
    try testing.expect(std.mem.indexOf(u8, csv, "1,2,3") != null);
}

test "CSV export: without headers" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("x", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const col = df.columnMut("x").?;
    col.asInt64Buffer().?[0] = 99;

    try df.setRowCount(1);

    const csv = try df.toCSV(allocator, .{ .has_headers = false });
    defer allocator.free(csv);

    // Should not have header row
    try testing.expect(std.mem.indexOf(u8, csv, "x") == null);
    try testing.expect(std.mem.indexOf(u8, csv, "99") != null);
}
