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
/// String and Bool support added in 0.2.0.
/// Categorical type added in 0.4.0.
pub const ValueType = enum {
    /// 64-bit signed integer
    Int64,

    /// 64-bit floating point
    Float64,

    /// UTF-8 string (0.2.0+)
    String,

    /// Boolean (0.2.0+)
    Bool,

    /// Categorical - Dictionary-encoded string column (0.4.0+)
    /// Provides 4-8× memory reduction for low-cardinality data
    Categorical,

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
            .Categorical => blk: {
                // Categorical stores u32 indices (4 bytes per value)
                const result: ?u8 = 4;
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
        // Allow empty column names - RFC 4180 doesn't forbid them
        // Empty column names are valid edge cases (e.g., ",b,c" header row)
        std.debug.assert(index < std.math.maxInt(u32)); // Reasonable column limit
        std.debug.assert(@intFromPtr(name.ptr) != 0); // Name pointer must be valid

        return ColumnDesc{
            .name = name,
            .value_type = value_type,
            .index = index,
        };
    }
};

/// Manual schema specification for CSV columns
///
/// Maps column names to their desired ValueType, overriding auto-detection.
/// Use this to force specific columns to be categorical, or to correct
/// type inference issues.
///
/// Example:
/// ```zig
/// var schema = std.StringHashMap(ValueType).init(allocator);
/// try schema.put("region", .Categorical);
/// try schema.put("country", .Categorical);
/// try schema.put("age", .Int64);
/// ```
pub const SchemaMap = std.StringHashMap(ValueType);

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
    /// Set to false if providing full manual schema
    infer_types: bool = true,

    /// Number of rows to preview for type inference (default: 100)
    preview_rows: u32 = 100,

    /// Parse mode for error handling (default: Strict)
    parse_mode: ParseMode = .Strict,

    /// Maximum CSV size in bytes (safety limit)
    max_csv_size: u32 = 1024 * 1024 * 1024, // 1GB default (fits in u32)

    /// Manual schema specification (optional)
    /// If provided, overrides auto-detection for specified columns.
    /// Columns not in schema will still use auto-detection (if infer_types = true).
    /// Set to null to rely entirely on auto-detection (default: null)
    schema: ?*const SchemaMap = null,

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

        // Validate schema if provided
        if (self.schema) |schema_map| {
            std.debug.assert(schema_map.count() <= 10_000); // Reasonable column limit

            // Schema must have at least one column
            if (schema_map.count() == 0) return error.EmptySchema;

            // All schema entries must have valid ValueType (checked by type system)
        }
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

/// Rich error context for better developer experience (Phase 4)
/// Provides detailed error information including row, column, field value, and hints
pub const RichError = struct {
    /// Error code
    code: ErrorCode,

    /// Human-readable error message
    message: []const u8,

    /// Row number where error occurred (optional, 1-indexed for user display)
    row_number: ?u32,

    /// Column name where error occurred (optional)
    column_name: ?[]const u8,

    /// Problematic field value (optional, truncated to 100 chars)
    field_value: ?[]const u8,

    /// Helpful hint for fixing the error (optional)
    hint: ?[]const u8,

    pub fn init(code: ErrorCode, message: []const u8) RichError {
        std.debug.assert(message.len > 0); // Message required
        std.debug.assert(@intFromEnum(code) < 0); // Must be an error code (negative)

        return RichError{
            .code = code,
            .message = message,
            .row_number = null,
            .column_name = null,
            .field_value = null,
            .hint = null,
        };
    }

    /// Builder pattern: Add row number context
    pub fn withRow(self: RichError, row: u32) RichError {
        var result = self;
        result.row_number = row;
        return result;
    }

    /// Builder pattern: Add column name context
    pub fn withColumn(self: RichError, column: []const u8) RichError {
        std.debug.assert(column.len > 0); // Column name required

        var result = self;
        result.column_name = column;
        return result;
    }

    /// Builder pattern: Add field value context
    pub fn withFieldValue(self: RichError, value: []const u8) RichError {
        var result = self;
        result.field_value = value;
        return result;
    }

    /// Builder pattern: Add helpful hint
    pub fn withHint(self: RichError, hint_text: []const u8) RichError {
        std.debug.assert(hint_text.len > 0); // Hint required

        var result = self;
        result.hint = hint_text;
        return result;
    }

    /// Format error as detailed message
    pub fn format(self: *const RichError, allocator: std.mem.Allocator) ![]const u8 {
        std.debug.assert(self.message.len > 0); // Valid message
        std.debug.assert(@intFromEnum(self.code) < 0); // Must be error code (negative)

        var buffer = std.ArrayListUnmanaged(u8){};
        defer buffer.deinit(allocator);

        // Main error message
        try buffer.writer(allocator).print("RozesError: {s}", .{self.message});

        // Add location context
        if (self.row_number) |row| {
            try buffer.writer(allocator).print(" at row {}", .{row});
        }

        if (self.column_name) |col_name| {
            try buffer.writer(allocator).print(" in column '{s}'", .{col_name});
        }

        try buffer.append(allocator, '\n');

        // Add field value if available
        if (self.field_value) |value| {
            const truncated = if (value.len > 100) value[0..100] else value;
            try buffer.writer(allocator).print("  Field value: \"{s}\"", .{truncated});
            if (value.len > 100) {
                try buffer.appendSlice(allocator, "...");
            }
            try buffer.append(allocator, '\n');
        }

        // Add hint if available
        if (self.hint) |hint_text| {
            try buffer.writer(allocator).print("  Hint: {s}\n", .{hint_text});
        }

        return buffer.toOwnedSlice(allocator);
    }
};

/// Error codes for JavaScript interop
pub const ErrorCode = enum(i32) {
    /// Success
    Success = 0,

    /// Out of memory
    OutOfMemory = -1,

    /// Invalid CSV format
    InvalidFormat = -2,

    /// Type mismatch
    TypeMismatch = -3,

    /// Column not found
    ColumnNotFound = -4,

    /// Index out of bounds
    IndexOutOfBounds = -5,

    /// Invalid configuration
    InvalidOptions = -6,

    /// Too many DataFrames
    TooManyDataFrames = -7,

    /// Invalid handle
    InvalidHandle = -8,

    /// CSV too large
    CSVTooLarge = -9,

    /// Convert from Zig error to error code
    pub fn fromError(err: anytype) ErrorCode {
        return switch (err) {
            error.OutOfMemory => .OutOfMemory,
            error.InvalidCSV, error.InvalidFormat => .InvalidFormat,
            error.TypeMismatch => .TypeMismatch,
            error.ColumnNotFound => .ColumnNotFound,
            error.IndexOutOfBounds => .IndexOutOfBounds,
            error.InvalidOptions, error.PreviewRowsTooLarge, error.InvalidMaxSize, error.InvalidPreviewRows => .InvalidOptions,
            error.CSVTooLarge => .CSVTooLarge,
            else => .InvalidFormat,
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

/// Error recovery mode for tolerant CSV parsing
pub const ErrorRecoveryMode = enum {
    /// Skip malformed rows entirely (default)
    SkipRow,

    /// Fill malformed fields with null values
    FillNull,

    /// Best-effort type coercion (e.g., "abc" → 0 for integers)
    BestEffort,
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
    try testing.expectEqual(@as(?u8, 4), ValueType.Categorical.sizeOf());
    try testing.expectEqual(@as(?u8, null), ValueType.String.sizeOf());
    try testing.expectEqual(@as(?u8, null), ValueType.Null.sizeOf());
}

test "ValueType.isNumeric identifies numeric types" {
    const testing = std.testing;

    try testing.expect(ValueType.Int64.isNumeric());
    try testing.expect(ValueType.Float64.isNumeric());
    try testing.expect(!ValueType.String.isNumeric());
    try testing.expect(!ValueType.Bool.isNumeric());
    try testing.expect(!ValueType.Categorical.isNumeric());
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
