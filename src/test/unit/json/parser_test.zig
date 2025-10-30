//! JSON Parser Unit Tests
//!
//! Tests for src/json/parser.zig - NDJSON, Array, and Columnar formats

const std = @import("std");
const testing = std.testing;
const JSONParser = @import("../../../json/parser.zig").JSONParser;
const JSONOptions = @import("../../../json/parser.zig").JSONOptions;
const JSONFormat = @import("../../../json/parser.zig").JSONFormat;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const ValueType = @import("../../../core/types.zig").ValueType;

// ============================================================================
// NDJSON Parser Tests
// ============================================================================

test "NDJSON: Simple objects with 3 fields" {
    const allocator = testing.allocator;

    const json =
        \\{"name": "Alice", "age": 30, "score": 95.5}
        \\{"name": "Bob", "age": 25, "score": 87.3}
        \\{"name": "Charlie", "age": 35, "score": 91.0}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Validate structure
    try testing.expectEqual(@as(u32, 3), df.row_count);
    try testing.expectEqual(@as(usize, 3), df.columns.len);
}

test "NDJSON: Missing keys in some objects" {
    const allocator = testing.allocator;

    const json =
        \\{"name": "Alice", "age": 30, "score": 95.5}
        \\{"name": "Bob", "age": 25}
        \\{"name": "Charlie", "score": 91.0}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should have all 3 columns
    try testing.expectEqual(@as(u32, 3), df.row_count);
    try testing.expectEqual(@as(usize, 3), df.columns.len);

    // Missing values should be filled with defaults (0, NaN, false)
}

test "NDJSON: Empty lines are skipped" {
    const allocator = testing.allocator;

    const json =
        \\{"name": "Alice", "age": 30}
        \\
        \\{"name": "Bob", "age": 25}
        \\
        \\
        \\{"name": "Charlie", "age": 35}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should have 3 rows (empty lines ignored)
    try testing.expectEqual(@as(u32, 3), df.row_count);
}

test "NDJSON: Mixed types - integers and floats" {
    const allocator = testing.allocator;

    const json =
        \\{"id": 1, "value": 42}
        \\{"id": 2, "value": 3.14}
        \\{"id": 3, "value": 100}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);

    // Value column should be inferred as Float64 (can represent both int and float)
    const value_col = df.column("value");
    try testing.expect(value_col != null);
    try testing.expectEqual(ValueType.Float64, value_col.?.value_type);
}

test "NDJSON: Boolean values" {
    const allocator = testing.allocator;

    const json =
        \\{"active": true, "count": 10}
        \\{"active": false, "count": 20}
        \\{"active": true, "count": 30}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);

    const active_col = df.column("active");
    try testing.expect(active_col != null);
    try testing.expectEqual(ValueType.Bool, active_col.?.value_type);
}

test "NDJSON: Null values" {
    const allocator = testing.allocator;

    const json =
        \\{"id": 1, "value": 42}
        \\{"id": 2, "value": null}
        \\{"id": 3, "value": 100}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);

    // Null values should be represented as NaN for numeric types
    const value_col = df.column("value");
    try testing.expect(value_col != null);
}

test "NDJSON: Integer type inference" {
    const allocator = testing.allocator;

    const json =
        \\{"id": 1}
        \\{"id": 2}
        \\{"id": 3}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const id_col = df.column("id");
    try testing.expect(id_col != null);
    try testing.expectEqual(ValueType.Int64, id_col.?.value_type);
}

test "NDJSON: Float type inference" {
    const allocator = testing.allocator;

    const json =
        \\{"value": 3.14}
        \\{"value": 2.71}
        \\{"value": 1.41}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const value_col = df.column("value");
    try testing.expect(value_col != null);
    try testing.expectEqual(ValueType.Float64, value_col.?.value_type);
}

test "NDJSON: CRLF line endings" {
    const allocator = testing.allocator;

    const json = "{\"id\": 1}\r\n{\"id\": 2}\r\n{\"id\": 3}\r\n";

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);
}

test "NDJSON: LF-only line endings" {
    const allocator = testing.allocator;

    const json = "{\"id\": 1}\n{\"id\": 2}\n{\"id\": 3}\n";

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);
}

test "NDJSON: Reject arrays at top level" {
    const allocator = testing.allocator;

    const json = "[1, 2, 3]\n{\"id\": 2}\n";

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    // First line is an array, not an object - should error
    try testing.expectError(error.ExpectedObject, parser.toDataFrame());
}

test "NDJSON: Large dataset (1000 lines)" {
    const allocator = testing.allocator;

    // Generate 1000 lines of NDJSON
    var json_buffer = try std.ArrayList(u8).initCapacity(allocator, 50000);
    defer json_buffer.deinit(allocator);

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        try json_buffer.writer(allocator).print("{{\"id\": {}, \"value\": {}}}\n", .{ i, i * 2 });
    }

    var parser = try JSONParser.init(allocator, json_buffer.items, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 1000), df.row_count);
    try testing.expectEqual(@as(usize, 2), df.columns.len);
}

test "NDJSON: Empty JSON (no data)" {
    const allocator = testing.allocator;

    const json = " "; // Whitespace only

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    // Should error with NoDataRows
    try testing.expectError(error.NoDataRows, parser.toDataFrame());
}

test "NDJSON: Single object" {
    const allocator = testing.allocator;

    const json = "{\"id\": 1, \"name\": \"Alice\"}";

    var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 1), df.row_count);
    try testing.expectEqual(@as(usize, 2), df.columns.len);
}

// ============================================================================
// Memory Leak Tests
// ============================================================================

test "NDJSON: Memory leak test (1000 iterations)" {
    const allocator = testing.allocator;

    const json =
        \\{"name": "Alice", "age": 30, "score": 95.5}
        \\{"name": "Bob", "age": 25, "score": 87.3}
        \\{"name": "Charlie", "age": 35, "score": 91.0}
    ;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
        defer parser.deinit();

        var df = try parser.toDataFrame();
        defer df.deinit();

        // Verify basic structure
        try testing.expectEqual(@as(u32, 3), df.row_count);
    }

    // testing.allocator will report leaks automatically
}

test "NDJSON: Memory leak with missing keys (1000 iterations)" {
    const allocator = testing.allocator;

    const json =
        \\{"name": "Alice", "age": 30}
        \\{"name": "Bob", "score": 87.3}
        \\{"age": 35, "score": 91.0}
    ;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        var parser = try JSONParser.init(allocator, json, .{ .format = .LineDelimited });
        defer parser.deinit();

        var df = try parser.toDataFrame();
        defer df.deinit();
    }
}

// ============================================================================
// JSON Array Parser Tests
// ============================================================================

test "Array: Simple array with 3 objects" {
    const allocator = testing.allocator;

    const json =
        \\[
        \\  {"name": "Alice", "age": 30, "score": 95.5},
        \\  {"name": "Bob", "age": 25, "score": 87.3},
        \\  {"name": "Charlie", "age": 35, "score": 91.0}
        \\]
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Array });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);
    try testing.expectEqual(@as(usize, 3), df.columns.len);
}

test "Array: Missing keys in some objects" {
    const allocator = testing.allocator;

    const json =
        \\[
        \\  {"name": "Alice", "age": 30, "score": 95.5},
        \\  {"name": "Bob", "age": 25},
        \\  {"name": "Charlie", "score": 91.0}
        \\]
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Array });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);
    try testing.expectEqual(@as(usize, 3), df.columns.len);
}

test "Array: Mixed types - integers and floats" {
    const allocator = testing.allocator;

    const json =
        \\[
        \\  {"id": 1, "value": 42},
        \\  {"id": 2, "value": 3.14},
        \\  {"id": 3, "value": 100}
        \\]
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Array });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);

    const value_col = df.column("value");
    try testing.expect(value_col != null);
    try testing.expectEqual(ValueType.Float64, value_col.?.value_type);
}

test "Array: Boolean values" {
    const allocator = testing.allocator;

    const json =
        \\[
        \\  {"active": true, "count": 10},
        \\  {"active": false, "count": 20},
        \\  {"active": true, "count": 30}
        \\]
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Array });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const active_col = df.column("active");
    try testing.expect(active_col != null);
    try testing.expectEqual(ValueType.Bool, active_col.?.value_type);
}

test "Array: Null values" {
    const allocator = testing.allocator;

    const json =
        \\[
        \\  {"id": 1, "value": 42},
        \\  {"id": 2, "value": null},
        \\  {"id": 3, "value": 100}
        \\]
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Array });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);
}

test "Array: Empty array" {
    const allocator = testing.allocator;

    const json = "[]";

    var parser = try JSONParser.init(allocator, json, .{ .format = .Array });
    defer parser.deinit();

    try testing.expectError(error.NoDataRows, parser.toDataFrame());
}

test "Array: Single object" {
    const allocator = testing.allocator;

    const json = "[{\"id\": 1, \"name\": \"Alice\"}]";

    var parser = try JSONParser.init(allocator, json, .{ .format = .Array });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 1), df.row_count);
}

test "Array: Reject non-array JSON" {
    const allocator = testing.allocator;

    const json = "{\"id\": 1}";

    var parser = try JSONParser.init(allocator, json, .{ .format = .Array });
    defer parser.deinit();

    try testing.expectError(error.ExpectedArray, parser.toDataFrame());
}

test "Array: Reject array with non-object elements" {
    const allocator = testing.allocator;

    const json = "[1, 2, 3]";

    var parser = try JSONParser.init(allocator, json, .{ .format = .Array });
    defer parser.deinit();

    try testing.expectError(error.ExpectedObject, parser.toDataFrame());
}

test "Array: Large dataset (1000 objects)" {
    const allocator = testing.allocator;

    var json_buffer = try std.ArrayList(u8).initCapacity(allocator, 50000);
    defer json_buffer.deinit(allocator);

    try json_buffer.appendSlice(allocator, "[");
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        if (i > 0) try json_buffer.appendSlice(allocator, ",");
        try json_buffer.writer(allocator).print("{{\"id\": {}, \"value\": {}}}", .{ i, i * 2 });
    }
    try json_buffer.appendSlice(allocator, "]");

    var parser = try JSONParser.init(allocator, json_buffer.items, .{ .format = .Array });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 1000), df.row_count);
}

test "Array: Memory leak test (1000 iterations)" {
    const allocator = testing.allocator;

    const json =
        \\[
        \\  {"name": "Alice", "age": 30},
        \\  {"name": "Bob", "age": 25}
        \\]
    ;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        var parser = try JSONParser.init(allocator, json, .{ .format = .Array });
        defer parser.deinit();

        var df = try parser.toDataFrame();
        defer df.deinit();
    }
}

// ============================================================================
// Columnar JSON Parser Tests
// ============================================================================

test "Columnar: Simple columnar format" {
    const allocator = testing.allocator;

    const json =
        \\{
        \\  "name": ["Alice", "Bob", "Charlie"],
        \\  "age": [30, 25, 35],
        \\  "score": [95.5, 87.3, 91.0]
        \\}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Columnar });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);
    try testing.expectEqual(@as(usize, 3), df.columns.len);
}

test "Columnar: Mixed types in columns" {
    const allocator = testing.allocator;

    const json =
        \\{
        \\  "id": [1, 2, 3],
        \\  "value": [42, 3.14, 100]
        \\}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Columnar });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const value_col = df.column("value");
    try testing.expect(value_col != null);
    try testing.expectEqual(ValueType.Float64, value_col.?.value_type);
}

test "Columnar: Boolean columns" {
    const allocator = testing.allocator;

    const json =
        \\{
        \\  "active": [true, false, true],
        \\  "count": [10, 20, 30]
        \\}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Columnar });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const active_col = df.column("active");
    try testing.expect(active_col != null);
    try testing.expectEqual(ValueType.Bool, active_col.?.value_type);
}

test "Columnar: Null values in columns" {
    const allocator = testing.allocator;

    const json =
        \\{
        \\  "id": [1, 2, 3],
        \\  "value": [42, null, 100]
        \\}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Columnar });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);
}

test "Columnar: Single row" {
    const allocator = testing.allocator;

    const json =
        \\{
        \\  "name": ["Alice"],
        \\  "age": [30]
        \\}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Columnar });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 1), df.row_count);
}

test "Columnar: Empty columns" {
    const allocator = testing.allocator;

    const json =
        \\{
        \\  "name": [],
        \\  "age": []
        \\}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Columnar });
    defer parser.deinit();

    try testing.expectError(error.NoDataRows, parser.toDataFrame());
}

test "Columnar: Inconsistent column lengths" {
    const allocator = testing.allocator;

    const json =
        \\{
        \\  "name": ["Alice", "Bob"],
        \\  "age": [30, 25, 35]
        \\}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Columnar });
    defer parser.deinit();

    try testing.expectError(error.InconsistentColumnLengths, parser.toDataFrame());
}

test "Columnar: Reject non-object JSON" {
    const allocator = testing.allocator;

    const json = "[1, 2, 3]";

    var parser = try JSONParser.init(allocator, json, .{ .format = .Columnar });
    defer parser.deinit();

    try testing.expectError(error.ExpectedObject, parser.toDataFrame());
}

test "Columnar: Reject non-array values" {
    const allocator = testing.allocator;

    const json =
        \\{
        \\  "name": ["Alice", "Bob"],
        \\  "age": 30
        \\}
    ;

    var parser = try JSONParser.init(allocator, json, .{ .format = .Columnar });
    defer parser.deinit();

    try testing.expectError(error.ExpectedArray, parser.toDataFrame());
}

test "Columnar: Large dataset (1000 rows)" {
    const allocator = testing.allocator;

    var json_buffer = try std.ArrayList(u8).initCapacity(allocator, 50000);
    defer json_buffer.deinit(allocator);

    try json_buffer.appendSlice(allocator, "{\"id\": [");
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        if (i > 0) try json_buffer.appendSlice(allocator, ",");
        try json_buffer.writer(allocator).print("{}", .{i});
    }
    try json_buffer.appendSlice(allocator, "], \"value\": [");
    i = 0;
    while (i < 1000) : (i += 1) {
        if (i > 0) try json_buffer.appendSlice(allocator, ",");
        try json_buffer.writer(allocator).print("{}", .{i * 2});
    }
    try json_buffer.appendSlice(allocator, "]}");

    var parser = try JSONParser.init(allocator, json_buffer.items, .{ .format = .Columnar });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 1000), df.row_count);
}

test "Columnar: Memory leak test (1000 iterations)" {
    const allocator = testing.allocator;

    const json =
        \\{
        \\  "age": [30, 25, 35],
        \\  "score": [95.5, 87.3, 91.0]
        \\}
    ;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        var parser = try JSONParser.init(allocator, json, .{ .format = .Columnar });
        defer parser.deinit();

        var df = try parser.toDataFrame();
        defer df.deinit();
    }

    // testing.allocator will report leaks automatically
}
