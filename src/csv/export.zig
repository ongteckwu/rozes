//! CSV Export - Serialize DataFrame to CSV format
//!
//! Converts a DataFrame back to CSV text format following RFC 4180.
//! Handles field quoting, quote escaping, and proper line endings.
//!
//! See docs/RFC.md Section 5.5 for CSV export specification.
//!
//! Example:
//! ```
//! const csv = try toCSV(df, allocator, .{});
//! defer allocator.free(csv);
//! ```

const std = @import("std");
const core_types = @import("../core/types.zig");
const DataFrame = @import("../core/dataframe.zig").DataFrame;
const Series = @import("../core/series.zig").Series;
const ValueType = core_types.ValueType;
const CSVOptions = core_types.CSVOptions;

/// Maximum output size (1GB)
const MAX_OUTPUT_SIZE: u32 = 1024 * 1024 * 1024;

/// Exports a DataFrame to CSV format
///
/// Args:
///   - df: DataFrame to export
///   - allocator: Memory allocator for output buffer
///   - opts: CSV formatting options
///
/// Returns: Allocated CSV string (caller must free)
pub fn toCSV(
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    opts: CSVOptions,
) ![]u8 {
    std.debug.assert(df.columnCount() > 0); // Need columns
    std.debug.assert(df.columnCount() <= 10_000); // Reasonable limit

    var output = std.ArrayListUnmanaged(u8){};
    errdefer output.deinit(allocator);

    const writer = output.writer(allocator);

    // Write header row if requested
    if (opts.has_headers) {
        try writeHeaderRow(df, writer, opts);
    }

    // Write data rows
    try writeDataRows(df, writer, opts);

    return try output.toOwnedSlice(allocator);
}

/// Writes the header row
fn writeHeaderRow(
    df: *const DataFrame,
    writer: anytype,
    opts: CSVOptions,
) !void {
    std.debug.assert(df.columnCount() > 0); // Need columns
    std.debug.assert(df.columnCount() <= 10_000); // Reasonable limit

    const col_count = df.columnCount();
    var col_idx: u32 = 0;

    while (col_idx < 10_000 and col_idx < col_count) : (col_idx += 1) {
        if (col_idx > 0) {
            try writer.writeByte(opts.delimiter);
        }

        const col_name = df.column_descs[col_idx].name;
        try writeField(writer, col_name, opts);
    }

    std.debug.assert(col_idx == col_count); // Wrote all columns

    // Write line ending
    try writeLineEnding(writer, opts);
}

/// Writes all data rows
fn writeDataRows(
    df: *const DataFrame,
    writer: anytype,
    opts: CSVOptions,
) !void {
    std.debug.assert(df.len() <= std.math.maxInt(u32)); // Within limits

    const row_count = df.len();
    const col_count = df.columnCount();

    var row_idx: u32 = 0;
    while (row_idx < std.math.maxInt(u32) and row_idx < row_count) : (row_idx += 1) {
        var col_idx: u32 = 0;
        while (col_idx < 10_000 and col_idx < col_count) : (col_idx += 1) {
            if (col_idx > 0) {
                try writer.writeByte(opts.delimiter);
            }

            // Get column and write value
            const col = &df.columns[col_idx];
            try writeValue(writer, col, row_idx, opts);
        }

        std.debug.assert(col_idx == col_count); // Wrote all columns

        // Write line ending
        try writeLineEnding(writer, opts);
    }

    std.debug.assert(row_idx == row_count); // Wrote all rows
}

/// Writes a single field value, quoting if necessary
fn writeField(
    writer: anytype,
    field: []const u8,
    opts: CSVOptions,
) !void {
    std.debug.assert(field.len < 1_000_000); // Reasonable field size

    const needs_quoting = needsQuoting(field, opts);

    if (needs_quoting) {
        try writer.writeByte('"');
        // Escape quotes by doubling them
        for (field) |c| {
            if (c == '"') {
                try writer.writeAll("\"\"");
            } else {
                try writer.writeByte(c);
            }
        }
        try writer.writeByte('"');
    } else {
        try writer.writeAll(field);
    }
}

/// Writes a value from a Series at the given row index
fn writeValue(
    writer: anytype,
    col: *const Series,
    row_idx: u32,
    opts: CSVOptions,
) !void {
    std.debug.assert(row_idx < col.length); // Valid index

    switch (col.value_type) {
        .Int64 => {
            const data = col.asInt64() orelse return error.TypeMismatch;
            try writer.print("{}", .{data[row_idx]});
        },
        .Float64 => {
            const data = col.asFloat64() orelse return error.TypeMismatch;
            // Use fixed precision for floats
            try writer.print("{d}", .{data[row_idx]});
        },
        .Bool => {
            const data = col.asBool() orelse return error.TypeMismatch;
            const bool_str = if (data[row_idx]) "true" else "false";
            try writeField(writer, bool_str, opts);
        },
        .String => {
            // String support in 0.2.0
            try writer.writeAll("");
        },
        .Null => {
            // Empty field for null
            try writer.writeAll("");
        },
    }
}

/// Checks if a field needs to be quoted
fn needsQuoting(field: []const u8, opts: CSVOptions) bool {
    std.debug.assert(field.len < 1_000_000); // Reasonable size

    if (field.len == 0) {
        return false; // Empty fields don't need quotes
    }

    // Check for delimiter
    for (field) |c| {
        if (c == opts.delimiter) return true;
        if (c == '"') return true; // Contains quote
        if (c == '\n' or c == '\r') return true; // Contains newline
    }

    // Check if starts/ends with whitespace
    if (opts.trim_whitespace) {
        const first = field[0];
        const last = field[field.len - 1];
        if (first == ' ' or first == '\t' or last == ' ' or last == '\t') {
            return true;
        }
    }

    return false;
}

/// Writes the appropriate line ending
fn writeLineEnding(writer: anytype, opts: CSVOptions) !void {
    _ = opts; // Reserved for future line ending option

    // Use LF for simplicity (Unix standard)
    try writer.writeByte('\n');
}

// Tests
test "toCSV exports simple DataFrame" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const ColumnDesc = @import("../core/types.zig").ColumnDesc;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
        ColumnDesc.init("score", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    // Set data
    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    ages[0] = 30;
    ages[1] = 25;

    const score_col = df.columnMut("score").?;
    const scores = score_col.asFloat64Buffer().?;
    scores[0] = 95.5;
    scores[1] = 87.3;

    try df.setRowCount(2);

    // Export to CSV
    const csv = try toCSV(&df, allocator, .{});
    defer allocator.free(csv);

    // Verify output (allowing for float precision variations)
    try testing.expect(std.mem.indexOf(u8, csv, "age,score") != null);
    try testing.expect(std.mem.indexOf(u8, csv, "30,") != null);
    try testing.expect(std.mem.indexOf(u8, csv, "25,") != null);
}

test "writeField quotes fields with delimiter" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    const opts = CSVOptions{};
    try writeField(output.writer(allocator), "hello, world", opts);

    const result = output.items;
    try testing.expectEqualStrings("\"hello, world\"", result);
}

test "writeField escapes quotes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    const opts = CSVOptions{};
    try writeField(output.writer(allocator), "hello \"world\"", opts);

    const result = output.items;
    try testing.expectEqualStrings("\"hello \"\"world\"\"\"", result);
}

test "writeField does not quote simple fields" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    const opts = CSVOptions{};
    try writeField(output.writer(allocator), "hello", opts);

    const result = output.items;
    try testing.expectEqualStrings("hello", result);
}

test "needsQuoting detects delimiter" {
    const opts = CSVOptions{};
    const testing = std.testing;

    try testing.expect(needsQuoting("hello,world", opts));
    try testing.expect(!needsQuoting("hello", opts));
}

test "needsQuoting detects quotes" {
    const opts = CSVOptions{};
    const testing = std.testing;

    try testing.expect(needsQuoting("hello \"world\"", opts));
    try testing.expect(!needsQuoting("hello world", opts));
}

test "needsQuoting detects newlines" {
    const opts = CSVOptions{};
    const testing = std.testing;

    try testing.expect(needsQuoting("hello\nworld", opts));
    try testing.expect(needsQuoting("hello\rworld", opts));
    try testing.expect(!needsQuoting("hello world", opts));
}

test "toCSV handles empty DataFrame" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const ColumnDesc = @import("../core/types.zig").ColumnDesc;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("col1", .Int64, 0),
        ColumnDesc.init("col2", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    try df.setRowCount(0);

    // Export to CSV
    const csv = try toCSV(&df, allocator, .{});
    defer allocator.free(csv);

    // Should only have header row
    try testing.expectEqualStrings("col1,col2\n", csv);
}
