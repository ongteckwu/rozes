//! Core Type Definitions for Rozes DataFrame Library
//!
//! This module defines the fundamental types used throughout the library:
//! - ValueType: Enum for supported data types
//! - ColumnDesc: Column metadata
//! - CSVOptions: CSV parsing configuration
//! - ParseMode: Error handling strategies
//! - ParseError: Error information
//!
//! See docs/RFC.md Section 3 for detailed type specifications.

const std = @import("std");

/// Supported data types in a DataFrame column.
///
/// MVP (0.1.0) supports only numeric types (Int64, Float64).
/// String and Bool support deferred to 0.2.0.
pub const ValueType = enum {
    /// 64-bit signed integer
    Int64,

    /// 64-bit floating point
    Float64,

    /// UTF-8 string (0.2.0+)
    String,

    /// Boolean (0.2.0+)
    Bool,

    /// Null/missing value
    Null,

    /// Returns the size in bytes for fixed-size types
    pub fn sizeOf(self: ValueType) ?u8 {
        std.debug.assert(@intFromEnum(self) >= 0); // Valid enum value

        return switch (self) {
            .Int64 => blk: {
                const result: ?u8 = 8;
                std.debug.assert(result.? > 0); // Non-zero for fixed types
                break :blk result;
            },
            .Float64 => blk: {
                const result: ?u8 = 8;
                std.debug.assert(result.? > 0);
                break :blk result;
            },
            .Bool => blk: {
                const result: ?u8 = 1;
                std.debug.assert(result.? > 0);
                break :blk result;
            },
            .String, .Null => null,
        };
    }

    /// Returns true if this is a numeric type
    pub fn isNumeric(self: ValueType) bool {
        std.debug.assert(@intFromEnum(self) >= 0); // Valid enum value

        const result = switch (self) {
            .Int64, .Float64 => true,
            else => false,
        };

        std.debug.assert(result == (self == .Int64 or self == .Float64)); // Post-condition
        return result;
    }
};

/// Column metadata descriptor
pub const ColumnDesc = struct {
    /// Column name (from CSV header or auto-generated)
    name: []const u8,

    /// Data type of the column
    value_type: ValueType,

    /// Index position in the DataFrame
    index: u32,

    /// Creates a column descriptor
    pub fn init(name: []const u8, value_type: ValueType, index: u32) ColumnDesc {
        std.debug.assert(name.len > 0); // Column name cannot be empty
        std.debug.assert(index < std.math.maxInt(u32)); // Reasonable column limit

        return ColumnDesc{
            .name = name,
            .value_type = value_type,
            .index = index,
        };
    }
};

/// CSV parsing options
pub const CSVOptions = struct {
    /// Field delimiter (default: ',')
    delimiter: u8 = ',',

    /// Whether first row contains headers (default: true)
    has_headers: bool = true,

    /// Skip blank lines (default: true)
    skip_blank_lines: bool = true,

    /// Trim whitespace from fields (default: false)
    trim_whitespace: bool = false,

    /// Automatically infer column types (default: true)
    infer_types: bool = true,

    /// Number of rows to preview for type inference (default: 100)
    preview_rows: u32 = 100,

    /// Parse mode for error handling (default: Strict)
    parse_mode: ParseMode = .Strict,

    /// Maximum CSV size in bytes (safety limit)
    max_csv_size: u32 = 1024 * 1024 * 1024, // 1GB default (fits in u32)

    /// Validates options are reasonable
    pub fn validate(self: CSVOptions) !void {
        std.debug.assert(self.delimiter != 0); // Must have delimiter

        // Check errors before assertions
        if (self.preview_rows == 0) return error.InvalidPreviewRows;
        if (self.preview_rows > 10_000) return error.PreviewRowsTooLarge;
        if (self.max_csv_size == 0) return error.InvalidMaxSize;

        std.debug.assert(self.preview_rows > 0); // Must preview at least 1 row
        std.debug.assert(self.preview_rows <= 10_000); // Reasonable preview limit
        std.debug.assert(self.max_csv_size > 0); // Must allow some data
    }
};

/// Error handling strategy for CSV parsing
pub const ParseMode = enum {
    /// Fail on first error
    Strict,

    /// Skip malformed rows, continue parsing (0.2.0+)
    Lenient,

    /// Collect all errors, return result with error list (0.2.0+)
    Collect,
};

/// Parse error information (for Lenient/Collect modes)
pub const ParseError = struct {
    /// Row number where error occurred (1-indexed)
    row: u32,

    /// Column number where error occurred (0-indexed)
    column: u32,

    /// Error message
    message: []const u8,

    /// Error type
    error_type: ParseErrorType,

    pub fn init(row: u32, column: u32, message: []const u8, error_type: ParseErrorType) ParseError {
        std.debug.assert(message.len > 0); // Error message required

        return ParseError{
            .row = row,
            .column = column,
            .message = message,
            .error_type = error_type,
        };
    }
};

/// Types of parse errors
pub const ParseErrorType = enum {
    /// Unexpected end of input
    UnexpectedEOF,

    /// Invalid field format
    InvalidField,

    /// Type mismatch (expected number, got string)
    TypeMismatch,

    /// Inconsistent column count
    ColumnCountMismatch,

    /// Quote not properly closed
    UnterminatedQuote,

    /// Invalid escape sequence
    InvalidEscape,
};

/// Common error set for Rozes operations
pub const RozesError = error{
    /// CSV is too large
    CSVTooLarge,

    /// Invalid CSV format
    InvalidCSV,

    /// Column not found
    ColumnNotFound,

    /// Type mismatch in operation
    TypeMismatch,

    /// Index out of bounds
    IndexOutOfBounds,

    /// Invalid configuration
    InvalidOptions,

    /// Memory allocation failed
    OutOfMemory,

    /// Preview rows setting too large
    PreviewRowsTooLarge,

    /// Invalid max size setting
    InvalidMaxSize,

    /// Invalid preview rows setting
    InvalidPreviewRows,
};

// Tests
test "ValueType.sizeOf returns correct sizes" {
    const testing = std.testing;

    try testing.expectEqual(@as(?u8, 8), ValueType.Int64.sizeOf());
    try testing.expectEqual(@as(?u8, 8), ValueType.Float64.sizeOf());
    try testing.expectEqual(@as(?u8, 1), ValueType.Bool.sizeOf());
    try testing.expectEqual(@as(?u8, null), ValueType.String.sizeOf());
    try testing.expectEqual(@as(?u8, null), ValueType.Null.sizeOf());
}

test "ValueType.isNumeric identifies numeric types" {
    const testing = std.testing;

    try testing.expect(ValueType.Int64.isNumeric());
    try testing.expect(ValueType.Float64.isNumeric());
    try testing.expect(!ValueType.String.isNumeric());
    try testing.expect(!ValueType.Bool.isNumeric());
    try testing.expect(!ValueType.Null.isNumeric());
}

test "ColumnDesc.init creates valid descriptor" {
    const testing = std.testing;

    const col = ColumnDesc.init("age", .Int64, 0);

    try testing.expectEqualStrings("age", col.name);
    try testing.expectEqual(ValueType.Int64, col.value_type);
    try testing.expectEqual(@as(u32, 0), col.index);
}

test "CSVOptions.validate accepts valid options" {
    const opts = CSVOptions{};
    try opts.validate();
}

test "CSVOptions.validate rejects invalid preview rows" {
    const testing = std.testing;

    const opts = CSVOptions{ .preview_rows = 20_000 };
    try testing.expectError(error.PreviewRowsTooLarge, opts.validate());
}

test "ParseError.init creates valid error" {
    const testing = std.testing;

    const err = ParseError.init(5, 2, "Invalid number format", .TypeMismatch);

    try testing.expectEqual(@as(u32, 5), err.row);
    try testing.expectEqual(@as(u32, 2), err.column);
    try testing.expectEqualStrings("Invalid number format", err.message);
    try testing.expectEqual(ParseErrorType.TypeMismatch, err.error_type);
}
