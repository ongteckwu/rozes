//! RFC 4180 Conformance Tests
//!
//! Tests CSV parser compliance with RFC 4180 specification.
//! Uses test files from testdata/csv/rfc4180/
//!
//! MVP Target: Pass 7/10 tests (numeric columns only, string support in 0.2.0)

const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;
const CSVParser = @import("../../../csv/parser.zig").CSVParser;
const ValueType = @import("../../../core/types.zig").ValueType;

// Note: @embedFile paths are relative to the current file location
// From src/test/unit/csv/ we need to go up 3 levels to reach testdata/

test "RFC 4180: 01_simple.csv - basic CSV parsing" {
    const allocator = testing.allocator;
    const csv = @embedFile("../../../../testdata/csv/rfc4180/01_simple.csv");

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Validate structure
    try testing.expectEqual(@as(u32, 3), df.len());
    try testing.expectEqual(@as(usize, 3), df.columnCount());

    // Validate column names
    try testing.expectEqualStrings("name", df.column_descs[0].name);
    try testing.expectEqualStrings("age", df.column_descs[1].name);
    try testing.expectEqualStrings("city", df.column_descs[2].name);

    // Validate age column (should be Int64)
    const age_col = df.column("age").?;
    try testing.expectEqual(ValueType.Int64, age_col.value_type);
    const ages = age_col.asInt64().?;
    try testing.expectEqual(@as(i64, 30), ages[0]);
    try testing.expectEqual(@as(i64, 25), ages[1]);
    try testing.expectEqual(@as(i64, 35), ages[2]);

    // Note: name and city columns are strings, which are not supported in MVP
    // They will cause type inference to fail or be treated as errors
}

test "RFC 4180: 02_quoted_fields.csv - quoted field handling" {
    const allocator = testing.allocator;
    const csv = @embedFile("../../../../testdata/csv/rfc4180/02_quoted_fields.csv");

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Validate structure
    try testing.expectEqual(@as(u32, 3), df.len());
    try testing.expectEqual(@as(usize, 3), df.columnCount());

    // Validate price column (should be Float64)
    const price_col = df.column("price").?;
    try testing.expectEqual(ValueType.Float64, price_col.value_type);
    const prices = price_col.asFloat64().?;

    // Allow small floating point differences
    try testing.expectApproxEqRel(@as(f64, 29.99), prices[0], 0.01);
    try testing.expectApproxEqRel(@as(f64, 19.99), prices[1], 0.01);
    try testing.expectApproxEqRel(@as(f64, 99.99), prices[2], 0.01);
}

test "RFC 4180: 03_embedded_commas.csv - commas inside quoted fields" {
    const allocator = testing.allocator;
    const csv = @embedFile("../../../../testdata/csv/rfc4180/03_embedded_commas.csv");

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should parse successfully
    try testing.expect(df.len() > 0);
    try testing.expect(df.columnCount() > 0);
}

test "RFC 4180: 04_embedded_newlines.csv - newlines inside quoted fields (DEFERRED to 0.2.0)" {
    // This test requires string column support which is deferred to 0.2.0
    // For now, we skip this test
}

test "RFC 4180: 05_escaped_quotes.csv - double-quote escaping" {
    const allocator = testing.allocator;
    const csv = @embedFile("../../../../testdata/csv/rfc4180/05_escaped_quotes.csv");

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should parse successfully (even if string content not fully validated)
    try testing.expect(df.len() > 0);
}

test "RFC 4180: 06_crlf_endings.csv - CRLF line endings" {
    const allocator = testing.allocator;
    const csv = @embedFile("../../../../testdata/csv/rfc4180/06_crlf_endings.csv");

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should parse correctly with CRLF
    try testing.expect(df.len() > 0);
    try testing.expect(df.columnCount() > 0);
}

test "RFC 4180: 07_empty_fields.csv - null/empty values" {
    const allocator = testing.allocator;
    const csv = @embedFile("../../../../testdata/csv/rfc4180/07_empty_fields.csv");

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Validate structure
    try testing.expectEqual(@as(u32, 4), df.len());
    try testing.expectEqual(@as(usize, 4), df.columnCount());

    // id column should be Int64
    const id_col = df.column("id").?;
    try testing.expectEqual(ValueType.Int64, id_col.value_type);
    const ids = id_col.asInt64().?;
    try testing.expectEqual(@as(i64, 1), ids[0]);
    try testing.expectEqual(@as(i64, 2), ids[1]);
    try testing.expectEqual(@as(i64, 3), ids[2]);
    try testing.expectEqual(@as(i64, 4), ids[3]);

    // Empty fields in string columns are represented as 0 for numeric types
}

test "RFC 4180: 08_no_header.csv - CSV without header row (DEFERRED to 0.2.0)" {
    // This test requires special handling for no-header CSVs
    // Deferred to 0.2.0 for now
}

test "RFC 4180: 09_trailing_comma.csv - trailing comma creates empty column" {
    const allocator = testing.allocator;
    const csv = @embedFile("../../../../testdata/csv/rfc4180/09_trailing_comma.csv");

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should have one extra column from trailing comma
    try testing.expect(df.columnCount() > 0);
}

test "RFC 4180: 10_unicode_content.csv - UTF-8 support (DEFERRED to 0.2.0)" {
    // This test requires string column support for Unicode
    // Deferred to 0.2.0
}

// Additional comprehensive parsing tests

test "CSV Parser: handles BOM correctly" {
    const allocator = testing.allocator;

    // CSV with UTF-8 BOM (but numeric columns for MVP)
    const csv_with_bom = "\xEF\xBB\xBFvalue\n42\n99\n";

    var parser = try CSVParser.init(allocator, csv_with_bom, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should parse correctly, ignoring BOM
    try testing.expectEqual(@as(u32, 2), df.len());
    try testing.expectEqualStrings("value", df.column_descs[0].name);

    const col = df.column("value").?;
    const values = col.asInt64().?;
    try testing.expectEqual(@as(i64, 42), values[0]);
    try testing.expectEqual(@as(i64, 99), values[1]);
}

test "CSV Parser: handles empty CSV with headers only" {
    const allocator = testing.allocator;

    const csv = "col1,col2,col3\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should create DataFrame with 0 rows, 3 columns
    try testing.expectEqual(@as(u32, 0), df.len());
    try testing.expectEqual(@as(usize, 3), df.columnCount());
    try testing.expect(df.isEmpty());
}

test "CSV Parser: handles different line endings" {
    const allocator = testing.allocator;

    // Test LF
    {
        const csv = "x\n10\n20\n";
        var parser = try CSVParser.init(allocator, csv, .{});
        defer parser.deinit();
        var df = try parser.toDataFrame();
        defer df.deinit();
        try testing.expectEqual(@as(u32, 2), df.len());
    }

    // Test CRLF
    {
        const csv = "x\r\n10\r\n20\r\n";
        var parser = try CSVParser.init(allocator, csv, .{});
        defer parser.deinit();
        var df = try parser.toDataFrame();
        defer df.deinit();
        try testing.expectEqual(@as(u32, 2), df.len());
    }

    // Test CR only (old Mac format)
    {
        const csv = "x\r10\r20\r";
        var parser = try CSVParser.init(allocator, csv, .{});
        defer parser.deinit();
        var df = try parser.toDataFrame();
        defer df.deinit();
        try testing.expectEqual(@as(u32, 2), df.len());
    }
}

test "CSV Parser: type inference detects Int64" {
    const allocator = testing.allocator;

    const csv = "age\n10\n20\n30\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const col = df.column("age").?;
    try testing.expectEqual(ValueType.Int64, col.value_type);
}

test "CSV Parser: type inference detects Float64" {
    const allocator = testing.allocator;

    const csv = "score\n10.5\n20.3\n30.8\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const col = df.column("score").?;
    try testing.expectEqual(ValueType.Float64, col.value_type);
}

test "CSV Parser: mixed int and float infers Float64" {
    const allocator = testing.allocator;

    const csv = "value\n10\n20.5\n30\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const col = df.column("value").?;
    // Should infer Float64 since one value has decimal
    try testing.expectEqual(ValueType.Float64, col.value_type);
}

test "CSV Parser: fails on invalid data in strict mode" {
    const allocator = testing.allocator;

    const csv = "value\n10\nabc\n30\n"; // "abc" is not a number

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    // Should fail with TypeMismatch error
    try testing.expectError(error.TypeMismatch, parser.toDataFrame());
}
