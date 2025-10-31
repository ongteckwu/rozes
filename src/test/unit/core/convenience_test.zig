//! Tests for DataFrame and Series convenience methods
//!
//! Tests:
//! - DataFrame.sample(n) - Random sampling
//! - DataFrame.info() - Schema information
//! - Series.unique() - Get unique values
//! - Series.nunique() - Count unique values

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const Series = @import("../../../core/series.zig").Series;
const SeriesValue = @import("../../../core/series.zig").SeriesValue;
const ColumnDesc = @import("../../../core/types.zig").ColumnDesc;

// ============================================================================
// DataFrame.sample() Tests
// ============================================================================

test "DataFrame.sample returns n random rows" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
        ColumnDesc.init("score", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    // Fill with data
    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        ages[i] = @intCast(i);
    }

    const score_col = df.columnMut("score").?;
    const scores = score_col.asFloat64Buffer().?;
    i = 0;
    while (i < 100) : (i += 1) {
        scores[i] = @floatFromInt(i * 2);
    }

    try df.setRowCount(100);

    // Sample 10 rows
    var sample_df = try df.sample(allocator, 10);
    defer sample_df.deinit();

    try testing.expectEqual(@as(u32, 10), sample_df.len());
    try testing.expectEqual(@as(usize, 2), sample_df.columnCount());
}

test "DataFrame.sample handles n larger than row count" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        ages[i] = @intCast(i);
    }
    try df.setRowCount(10);

    // Request more rows than available
    var sample_df = try df.sample(allocator, 100);
    defer sample_df.deinit();

    // Should return min(100, 10) = 10 rows
    try testing.expectEqual(@as(u32, 10), sample_df.len());
}

test "DataFrame.sample handles empty DataFrame" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 0);
    defer df.deinit();

    var sample_df = try df.sample(allocator, 10);
    defer sample_df.deinit();

    try testing.expectEqual(@as(u32, 0), sample_df.len());
}

test "DataFrame.sample with String columns" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const name_col = df.columnMut("name").?;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        var buf: [20]u8 = undefined;
        const name = try std.fmt.bufPrint(&buf, "Name_{d}", .{i});
        try name_col.appendString(df.getAllocator(), name);
    }

    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    i = 0;
    while (i < 10) : (i += 1) {
        ages[i] = @intCast(i + 20);
    }

    try df.setRowCount(10);

    var sample_df = try df.sample(allocator, 5);
    defer sample_df.deinit();

    try testing.expectEqual(@as(u32, 5), sample_df.len());
    try testing.expectEqual(@as(usize, 2), sample_df.columnCount());
}

// ============================================================================
// DataFrame.info() Tests
// ============================================================================

test "DataFrame.info displays schema information" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
        ColumnDesc.init("score", .Float64, 1),
        ColumnDesc.init("active", .Bool, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    try df.setRowCount(100);

    // Write to string buffer
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const writer = buf.writer(allocator);
    try df.info(writer);

    const output = try buf.toOwnedSlice(allocator);
    defer allocator.free(output);

    // Verify output contains expected information
    try testing.expect(std.mem.indexOf(u8, output, "DataFrame Info:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Rows: 100") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Columns: 3") != null);
    try testing.expect(std.mem.indexOf(u8, output, "age") != null);
    try testing.expect(std.mem.indexOf(u8, output, "score") != null);
    try testing.expect(std.mem.indexOf(u8, output, "active") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Int64") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Float64") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Bool") != null);
}

test "DataFrame.info with String columns shows memory usage" {
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    const name_col = df.columnMut("name").?;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try name_col.appendString(df.getAllocator(), "Test Name");
    }

    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    i = 0;
    while (i < 10) : (i += 1) {
        ages[i] = @intCast(i + 20);
    }

    try df.setRowCount(10);

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const writer = buf.writer(allocator);
    try df.info(writer);

    const output = try buf.toOwnedSlice(allocator);
    defer allocator.free(output);

    // Verify String column memory is reported
    try testing.expect(std.mem.indexOf(u8, output, "Total Memory:") != null);
}

// ============================================================================
// Series.unique() Tests
// ============================================================================

test "Series.unique returns unique Int64 values" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "numbers", .Int64, 10);
    defer series.deinit(allocator);

    const buffer = series.asInt64Buffer().?;
    buffer[0] = 10;
    buffer[1] = 20;
    buffer[2] = 10; // duplicate
    buffer[3] = 30;
    buffer[4] = 20; // duplicate
    buffer[5] = 40;
    series.length = 6;

    const unique_vals = try series.unique(allocator);
    defer {
        for (unique_vals) |val| allocator.free(val);
        allocator.free(unique_vals);
    }

    // Should have 4 unique values: 10, 20, 30, 40
    try testing.expectEqual(@as(usize, 4), unique_vals.len);
}

test "Series.unique returns unique Float64 values" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "scores", .Float64, 10);
    defer series.deinit(allocator);

    const buffer = series.asFloat64Buffer().?;
    buffer[0] = 1.5;
    buffer[1] = 2.5;
    buffer[2] = 1.5; // duplicate
    buffer[3] = 3.5;
    series.length = 4;

    const unique_vals = try series.unique(allocator);
    defer {
        for (unique_vals) |val| allocator.free(val);
        allocator.free(unique_vals);
    }

    // Should have 3 unique values
    try testing.expectEqual(@as(usize, 3), unique_vals.len);
}

test "Series.unique returns unique String values" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "names", .String, 10);
    defer series.deinit(allocator);

    try series.appendString(allocator, "Alice");
    try series.appendString(allocator, "Bob");
    try series.appendString(allocator, "Alice"); // duplicate
    try series.appendString(allocator, "Charlie");
    try series.appendString(allocator, "Bob"); // duplicate

    const unique_vals = try series.unique(allocator);
    defer {
        for (unique_vals) |val| allocator.free(val);
        allocator.free(unique_vals);
    }

    // Should have 3 unique values: Alice, Bob, Charlie
    try testing.expectEqual(@as(usize, 3), unique_vals.len);
}

test "Series.unique returns unique Bool values" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "flags", .Bool, 10);
    defer series.deinit(allocator);

    const buffer = series.asBoolBuffer().?;
    buffer[0] = true;
    buffer[1] = false;
    buffer[2] = true; // duplicate
    buffer[3] = false; // duplicate
    buffer[4] = true; // duplicate
    series.length = 5;

    const unique_vals = try series.unique(allocator);
    defer {
        for (unique_vals) |val| allocator.free(val);
        allocator.free(unique_vals);
    }

    // Should have 2 unique values: true, false
    try testing.expectEqual(@as(usize, 2), unique_vals.len);
}

test "Series.unique handles empty series" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "empty", .Int64, 10);
    defer series.deinit(allocator);

    const unique_vals = try series.unique(allocator);
    defer allocator.free(unique_vals);

    try testing.expectEqual(@as(usize, 0), unique_vals.len);
}

test "Series.unique handles all duplicate values" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "same", .Int64, 10);
    defer series.deinit(allocator);

    const buffer = series.asInt64Buffer().?;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        buffer[i] = 42; // All same value
    }
    series.length = 10;

    const unique_vals = try series.unique(allocator);
    defer {
        for (unique_vals) |val| allocator.free(val);
        allocator.free(unique_vals);
    }

    // Should have only 1 unique value
    try testing.expectEqual(@as(usize, 1), unique_vals.len);
    try testing.expectEqualStrings("42", unique_vals[0]);
}

// ============================================================================
// Series.nunique() Tests
// ============================================================================

test "Series.nunique counts unique Int64 values" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "numbers", .Int64, 10);
    defer series.deinit(allocator);

    const buffer = series.asInt64Buffer().?;
    buffer[0] = 10;
    buffer[1] = 20;
    buffer[2] = 10; // duplicate
    buffer[3] = 30;
    buffer[4] = 20; // duplicate
    buffer[5] = 40;
    series.length = 6;

    const count = try series.nunique(allocator);

    try testing.expectEqual(@as(u32, 4), count);
}

test "Series.nunique counts unique Float64 values" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "scores", .Float64, 10);
    defer series.deinit(allocator);

    const buffer = series.asFloat64Buffer().?;
    buffer[0] = 1.5;
    buffer[1] = 2.5;
    buffer[2] = 1.5; // duplicate
    buffer[3] = 3.5;
    series.length = 4;

    const count = try series.nunique(allocator);

    try testing.expectEqual(@as(u32, 3), count);
}

test "Series.nunique counts unique String values" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "names", .String, 10);
    defer series.deinit(allocator);

    try series.appendString(allocator, "Alice");
    try series.appendString(allocator, "Bob");
    try series.appendString(allocator, "Alice"); // duplicate
    try series.appendString(allocator, "Charlie");

    const count = try series.nunique(allocator);

    try testing.expectEqual(@as(u32, 3), count);
}

test "Series.nunique counts unique Bool values" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "flags", .Bool, 10);
    defer series.deinit(allocator);

    const buffer = series.asBoolBuffer().?;
    buffer[0] = true;
    buffer[1] = false;
    buffer[2] = true; // duplicate
    buffer[3] = false; // duplicate
    series.length = 4;

    const count = try series.nunique(allocator);

    try testing.expectEqual(@as(u32, 2), count);
}

test "Series.nunique handles empty series" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "empty", .Int64, 10);
    defer series.deinit(allocator);

    const count = try series.nunique(allocator);

    try testing.expectEqual(@as(u32, 0), count);
}

test "Series.nunique handles all duplicate values" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "same", .Int64, 10);
    defer series.deinit(allocator);

    const buffer = series.asInt64Buffer().?;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        buffer[i] = 42; // All same value
    }
    series.length = 10;

    const count = try series.nunique(allocator);

    try testing.expectEqual(@as(u32, 1), count);
}

test "Series.nunique with Bool series containing only true" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "flags", .Bool, 10);
    defer series.deinit(allocator);

    const buffer = series.asBoolBuffer().?;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        buffer[i] = true;
    }
    series.length = 10;

    const count = try series.nunique(allocator);

    try testing.expectEqual(@as(u32, 1), count);
}

test "Series.nunique with Bool series containing only false" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "flags", .Bool, 10);
    defer series.deinit(allocator);

    const buffer = series.asBoolBuffer().?;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        buffer[i] = false;
    }
    series.length = 10;

    const count = try series.nunique(allocator);

    try testing.expectEqual(@as(u32, 1), count);
}
