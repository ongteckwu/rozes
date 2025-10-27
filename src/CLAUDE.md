# Rozes Source Code - Implementation Guide

**Purpose**: Implementation patterns, code organization, and Zig-specific guidelines for the Rozes source code.

---

## Table of Contents

1. [Source Organization](#source-organization)
2. [Zig Implementation Patterns](#zig-implementation-patterns)
3. [Tiger Style Enforcement](#tiger-style-enforcement)
4. [Common Code Patterns](#common-code-patterns)
5. [Error Handling](#error-handling)
6. [Memory Management](#memory-management)
7. [Testing Patterns](#testing-patterns)

---

## Source Organization

### Directory Structure

```
src/
├── core/                      # Core DataFrame engine
│   ├── types.zig              # Core type definitions
│   ├── allocator.zig          # Memory management utilities
│   ├── series.zig             # Series implementation
│   ├── dataframe.zig          # DataFrame implementation
│   └── operations.zig         # DataFrame operations (filter, select, etc.)
├── csv/                       # CSV parsing and export
│   ├── parser.zig             # CSV parser (RFC 4180)
│   ├── export.zig             # CSV serialization
│   ├── types.zig              # CSVOptions, ParseState
│   ├── inference.zig          # Type inference
│   └── bom.zig                # BOM detection/handling
├── bindings/                  # Platform bindings
│   ├── wasm/                  # WebAssembly
│   │   ├── bridge.zig         # JS ↔ Wasm memory bridge
│   │   └── exports.zig        # Exported Wasm functions
│   └── node/                  # Node.js N-API (optional)
│       └── addon.zig
└── rozes.zig                  # Main API surface (public exports)
```

### Module Responsibilities

#### `core/types.zig` - Type Definitions
**Purpose**: Define all core types used throughout the project
**Exports**:
- `ValueType` enum
- `ColumnDesc` struct
- `CSVOptions` struct
- `ParseMode` enum
- `ParseError` struct

**Pattern**:
```zig
//! Core type definitions for Rozes DataFrame library.
//!
//! This module contains all fundamental types used across the codebase.
//! See docs/RFC.md Section 4.1 for type specifications.

const std = @import("std");

/// Supported data types for DataFrame columns
pub const ValueType = enum {
    Int64,
    Float64,
    String,
    Bool,
    Null,

    /// Returns the size in bytes for this type
    pub fn sizeOf(self: ValueType) usize {
        return switch (self) {
            .Int64 => @sizeOf(i64),
            .Float64 => @sizeOf(f64),
            .Bool => @sizeOf(bool),
            .String, .Null => 0, // Variable size
        };
    }
};

/// Column descriptor with name and type
pub const ColumnDesc = struct {
    name: []const u8,
    valueType: ValueType,
};

// ... more types
```

#### `core/series.zig` - Series Implementation
**Purpose**: 1D homogeneous typed array
**Exports**:
- `Series` struct
- Column accessor methods

**Pattern**:
```zig
//! Series - 1D homogeneous typed array
//!
//! A Series represents a single column of data with a uniform type.
//! Data is stored contiguously for cache efficiency.

const std = @import("std");
const types = @import("types.zig");
const ValueType = types.ValueType;

pub const Series = struct {
    name: []const u8,
    valueType: ValueType,
    data: union(ValueType) {
        Int64: []i64,
        Float64: []f64,
        String: StringColumn,
        Bool: []bool,
        Null: void,
    },
    length: u32,

    /// Get the length of the Series
    pub fn len(self: *const Series) u32 {
        std.debug.assert(self.length > 0); // Series should have data
        return self.length;
    }

    /// Get value at index (with type checking)
    pub fn get(self: *const Series, idx: u32) ?Value {
        std.debug.assert(idx < self.length); // Bounds check

        return switch (self.valueType) {
            .Int64 => Value{ .Int64 = self.data.Int64[idx] },
            .Float64 => Value{ .Float64 = self.data.Float64[idx] },
            .Bool => Value{ .Bool = self.data.Bool[idx] },
            .String => Value{ .String = self.data.String.get(idx) },
            .Null => null,
        };
    }

    /// Access as Float64 array (returns null if wrong type)
    pub fn asFloat64(self: *const Series) ?[]f64 {
        std.debug.assert(self.length > 0);

        return switch (self.valueType) {
            .Float64 => self.data.Float64,
            else => null,
        };
    }

    // ... more methods
};

/// String column with offset table for efficient storage
const StringColumn = struct {
    offsets: []u32,      // offsets[i] = start of string i
    buffer: []u8,        // contiguous UTF-8 data
    row_count: u32,

    pub fn get(self: *const StringColumn, idx: u32) []const u8 {
        std.debug.assert(idx < self.row_count);

        const start = if (idx == 0) 0 else self.offsets[idx - 1];
        const end = self.offsets[idx];

        std.debug.assert(start <= end);
        std.debug.assert(end <= self.buffer.len);

        return self.buffer[start..end];
    }
};
```

#### `core/dataframe.zig` - DataFrame Implementation
**Purpose**: 2D tabular data structure
**Exports**:
- `DataFrame` struct
- CSV import/export functions
- Column operations

**Pattern**:
```zig
//! DataFrame - 2D tabular data structure
//!
//! DataFrame stores data in columnar format for efficient operations.
//! Each column is a Series with homogeneous type.

const std = @import("std");
const types = @import("types.zig");
const Series = @import("series.zig").Series;

pub const DataFrame = struct {
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,  // For lifecycle management
    columns: []ColumnDesc,
    series: []Series,
    rowCount: u32,

    /// Create DataFrame with specified columns
    pub fn create(
        allocator: std.mem.Allocator,
        columns: []ColumnDesc,
        rowCount: u32,
    ) !DataFrame {
        std.debug.assert(columns.len > 0); // Need at least 1 column
        std.debug.assert(rowCount > 0); // Need at least 1 row

        // Create arena for all allocations
        const arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer {
            arena.deinit();
            allocator.destroy(arena);
        }

        const arena_alloc = arena.allocator();

        // Allocate columns and series
        const df_columns = try arena_alloc.dupe(ColumnDesc, columns);
        const df_series = try arena_alloc.alloc(Series, columns.len);

        return DataFrame{
            .allocator = allocator,
            .arena = arena,
            .columns = df_columns,
            .series = df_series,
            .rowCount = rowCount,
        };
    }

    /// Free all DataFrame memory (single operation via arena)
    pub fn free(self: DataFrame) void {
        self.arena.deinit();
        self.allocator.destroy(self.arena);
    }

    /// Get column by name
    pub fn column(self: *const DataFrame, name: []const u8) ?*const Series {
        std.debug.assert(self.series.len > 0);

        for (self.series, 0..) |*series, i| {
            if (std.mem.eql(u8, self.columns[i].name, name)) {
                return series;
            }
        }
        return null;
    }

    // ... more methods
};
```

#### `csv/parser.zig` - CSV Parser
**Purpose**: RFC 4180 compliant CSV parsing
**Exports**:
- `CSVParser` struct
- Parsing functions

**Pattern**:
```zig
//! CSV Parser - RFC 4180 Compliant
//!
//! One-pass parser with state machine for efficient parsing.
//! Converts CSV text to columnar DataFrame.

const std = @import("std");
const types = @import("../core/types.zig");
const DataFrame = @import("../core/dataframe.zig").DataFrame;

const ParserState = enum {
    Start,
    InField,
    InQuotedField,
    QuoteInQuoted,
    EndOfRecord,
};

const MAX_CSV_SIZE: u32 = 1_000_000_000; // 1GB max
const MAX_COLUMNS: u32 = 10_000;
const MAX_ROWS: u32 = 4_000_000_000; // u32 limit

pub const CSVParser = struct {
    allocator: std.mem.Allocator,
    buffer: []const u8,
    pos: u32,
    state: ParserState,
    opts: types.CSVOptions,
    current_field: std.ArrayList(u8),
    current_row: std.ArrayList([]const u8),
    rows: std.ArrayList([][]const u8),

    pub fn init(
        allocator: std.mem.Allocator,
        buffer: []const u8,
        opts: types.CSVOptions,
    ) !CSVParser {
        std.debug.assert(buffer.len > 0); // Non-empty buffer
        std.debug.assert(buffer.len <= MAX_CSV_SIZE); // Size check

        return CSVParser{
            .allocator = allocator,
            .buffer = buffer,
            .pos = 0,
            .state = .Start,
            .opts = opts,
            .current_field = std.ArrayList(u8).init(allocator),
            .current_row = std.ArrayList([]const u8).init(allocator),
            .rows = std.ArrayList([][]const u8).init(allocator),
        };
    }

    /// Parse next field from CSV
    pub fn nextField(self: *CSVParser) !?[]const u8 {
        std.debug.assert(self.pos <= self.buffer.len);

        while (self.pos < self.buffer.len) {
            const char = self.buffer[self.pos];
            self.pos += 1;

            switch (self.state) {
                .Start => {
                    if (char == self.opts.quoteChar) {
                        self.state = .InQuotedField;
                    } else if (char == self.opts.delimiter) {
                        // Empty field
                        return try self.finishField();
                    } else if (char == '\n' or char == '\r') {
                        self.state = .EndOfRecord;
                        return null; // End of row
                    } else {
                        try self.current_field.append(char);
                        self.state = .InField;
                    }
                },
                .InField => {
                    if (char == self.opts.delimiter) {
                        self.state = .Start;
                        return try self.finishField();
                    } else if (char == '\n' or char == '\r') {
                        self.state = .EndOfRecord;
                        const field = try self.finishField();
                        return field;
                    } else {
                        try self.current_field.append(char);
                    }
                },
                .InQuotedField => {
                    if (char == self.opts.quoteChar) {
                        self.state = .QuoteInQuoted;
                    } else {
                        try self.current_field.append(char);
                    }
                },
                .QuoteInQuoted => {
                    if (char == self.opts.quoteChar) {
                        // Escaped quote
                        try self.current_field.append(self.opts.quoteChar);
                        self.state = .InQuotedField;
                    } else if (char == self.opts.delimiter) {
                        self.state = .Start;
                        return try self.finishField();
                    } else if (char == '\n' or char == '\r') {
                        self.state = .EndOfRecord;
                        return try self.finishField();
                    } else {
                        return error.InvalidQuoting;
                    }
                },
                .EndOfRecord => unreachable,
            }
        }

        // End of buffer
        if (self.current_field.items.len > 0) {
            return try self.finishField();
        }
        return null;
    }

    fn finishField(self: *CSVParser) ![]const u8 {
        const field = try self.current_field.toOwnedSlice();
        return field;
    }

    /// Parse entire CSV to DataFrame
    pub fn toDataFrame(self: *CSVParser) !DataFrame {
        // Implementation in Phase 3
    }
};
```

---

## Zig Implementation Patterns

### Pattern 1: Bounded Loops with Explicit Limits

**Always set maximum iterations**:
```zig
const MAX_ROWS: u32 = 4_000_000_000; // u32 limit

pub fn parseCSV(buffer: []const u8) !DataFrame {
    std.debug.assert(buffer.len > 0); // Pre-condition

    var row_count: u32 = 0;
    while (row_count < MAX_ROWS) : (row_count += 1) {
        // Parse row
        if (is_end_of_file) break;
    }

    std.debug.assert(row_count <= MAX_ROWS); // Post-condition
    return dataframe;
}
```

**Common Unbounded Loop Issues**:

1. **For loops over slices** - Need explicit MAX check:
```zig
// ❌ WRONG - No explicit bound
pub fn columnIndex(self: *const DataFrame, name: []const u8) ?usize {
    for (self.columnDescs, 0..) |desc, i| {  // What if columnDescs is corrupted?
        if (std.mem.eql(u8, desc.name, name)) return i;
    }
    return null;
}

// ✅ CORRECT - Explicit bound with while loop
pub fn columnIndex(self: *const DataFrame, name: []const u8) ?u32 {
    std.debug.assert(name.len > 0);
    std.debug.assert(self.columnDescs.len <= MAX_COLS);

    var i: u32 = 0;
    while (i < MAX_COLS and i < self.columnDescs.len) : (i += 1) {
        if (std.mem.eql(u8, self.columnDescs[i].name, name)) {
            return i;
        }
    }

    std.debug.assert(i <= MAX_COLS); // Post-condition
    return null;
}
```

2. **Nested loops** - Both need bounds:
```zig
// ❌ WRONG - Nested unbounded loops
fn fillDataFrame(df: *DataFrame, rows: []const [][]const u8) !void {
    for (df.columns, 0..) |*col, col_idx| {
        for (rows, 0..) |row, row_idx| {
            // ... process
        }
    }
}

// ✅ CORRECT - Both loops bounded
fn fillDataFrame(df: *DataFrame, rows: []const [][]const u8) !void {
    std.debug.assert(rows.len > 0);
    std.debug.assert(df.columns.len <= MAX_COLS);

    var col_idx: u32 = 0;
    while (col_idx < MAX_COLS and col_idx < df.columns.len) : (col_idx += 1) {
        var row_idx: u32 = 0;
        while (row_idx < MAX_ROWS and row_idx < rows.len) : (row_idx += 1) {
            // ... process
        }
        std.debug.assert(row_idx <= MAX_ROWS);
    }
    std.debug.assert(col_idx <= MAX_COLS);
}
```

3. **Character-by-character parsing** - Need field length limit:
```zig
// ❌ WRONG - No field length limit
pub fn nextField(self: *CSVParser) !?[]const u8 {
    while (self.pos < self.buffer.len) {  // What if one field is 1GB?
        const char = self.buffer[self.pos];
        self.pos += 1;
        try self.current_field.append(char);
    }
}

// ✅ CORRECT - Field length bounded
const MAX_FIELD_LENGTH: u32 = 1_000_000; // 1MB per field

pub fn nextField(self: *CSVParser) !?[]const u8 {
    std.debug.assert(self.pos <= self.buffer.len);

    while (self.pos < self.buffer.len) {
        if (self.current_field.items.len >= MAX_FIELD_LENGTH) {
            return error.FieldTooLarge;
        }

        const char = self.buffer[self.pos];
        self.pos += 1;
        // ... process char
    }

    std.debug.assert(self.pos <= self.buffer.len);
}
```

### Pattern 2: Arena Allocator for Lifecycle Management

**Use arena for grouped allocations**:
```zig
pub fn fromCSVBuffer(
    allocator: std.mem.Allocator,
    buffer: []const u8,
    opts: CSVOptions,
) !DataFrame {
    // Create arena for all DataFrame allocations
    const arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer {
        arena.deinit();
        allocator.destroy(arena);
    }

    const arena_alloc = arena.allocator();

    // All allocations use arena_alloc
    const columns = try arena_alloc.alloc(ColumnDesc, col_count);
    const series = try arena_alloc.alloc(Series, col_count);

    // Single free via arena
    return DataFrame{ .arena = arena, /* ... */ };
}
```

### Pattern 3: Explicit Type Sizes

**Use u32 instead of usize**:
```zig
// ✅ Correct - consistent across platforms
const row_index: u32 = 0;
const col_count: u32 = @intCast(df.columns.len);

// ❌ Wrong - platform-dependent
const row_index: usize = 0;
```

### Pattern 4: Tagged Unions for Variant Types

**Use tagged unions for type-safe variants**:
```zig
pub const Value = union(ValueType) {
    Int64: i64,
    Float64: f64,
    String: []const u8,
    Bool: bool,
    Null: void,

    pub fn asFloat64(self: Value) ?f64 {
        return switch (self) {
            .Float64 => |val| val,
            .Int64 => |val| @floatFromInt(val),
            else => null,
        };
    }
};
```

### Pattern 5: Comptime for Zero-Overhead Abstractions

**Use comptime for type-generic code**:
```zig
fn generateColumnAccessor(comptime T: type) type {
    return struct {
        pub fn get(data: []const T, idx: u32) T {
            std.debug.assert(idx < data.len);
            return data[idx];
        }

        pub fn sum(data: []const T) T {
            var total: T = 0;
            for (data) |val| total += val;
            return total;
        }
    };
}

const Float64Accessor = generateColumnAccessor(f64);
const Int64Accessor = generateColumnAccessor(i64);
```

---

## Tiger Style Enforcement

### 2+ Assertions Per Function

**Every function MUST have at least 2 assertions**:
```zig
pub fn get(self: *const Series, idx: u32) ?Value {
    std.debug.assert(idx < self.length);     // Assertion 1: Bounds check
    std.debug.assert(self.data != null);      // Assertion 2: Valid data

    return self.data[idx];
}
```

**Common Assertion Patterns**:

1. **Simple Getters/Setters** - Still need 2 assertions:
```zig
// ❌ WRONG - Only returns value
pub fn isEmpty(self: *const Series) bool {
    return self.length == 0;
}

// ✅ CORRECT - Has pre/post assertions
pub fn isEmpty(self: *const Series) bool {
    std.debug.assert(self.length <= MAX_ROWS); // Invariant check
    const result = self.length == 0;
    std.debug.assert(result == (self.length == 0)); // Post-condition
    return result;
}
```

2. **Enum Methods** - Validate enum value:
```zig
// ❌ WRONG - No assertions
pub fn sizeOf(self: ValueType) ?u8 {
    return switch (self) {
        .Int64 => 8,
        .Float64 => 8,
        .Bool => 1,
        .String, .Null => null,
    };
}

// ✅ CORRECT - Validate enum and result
pub fn sizeOf(self: ValueType) ?u8 {
    std.debug.assert(@intFromEnum(self) >= 0); // Valid enum value

    const result = switch (self) {
        .Int64 => 8,
        .Float64 => 8,
        .Bool => 1,
        .String, .Null => null,
    };

    std.debug.assert(result == null or result.? > 0); // Non-zero for fixed types
    return result;
}
```

3. **Validation Functions** - Check BEFORE errors:
```zig
// ❌ WRONG - Assertions after error checks
pub fn validate(self: CSVOptions) !void {
    std.debug.assert(self.delimiter != 0);

    if (self.previewRows == 0) return error.InvalidPreviewRows;

    std.debug.assert(self.previewRows > 0); // Redundant!
}

// ✅ CORRECT - Assertions before errors
pub fn validate(self: CSVOptions) !void {
    std.debug.assert(self.delimiter != 0); // Pre-condition
    std.debug.assert(self.previewRows > 0 or
                    self.previewRows <= 10_000); // Range check

    if (self.previewRows == 0) return error.InvalidPreviewRows;
    if (self.previewRows > 10_000) return error.PreviewRowsTooLarge;
}
```

### Explicit Error Handling

**Never ignore errors**:
```zig
// ✅ Correct - propagate error
const df = try DataFrame.fromCSVBuffer(allocator, buffer, opts);

// ✅ Correct - handle explicitly
const df = DataFrame.fromCSVBuffer(allocator, buffer, opts) catch |err| {
    log.err("CSV parsing failed: {}", .{err});
    return error.InvalidCSV;
};

// ⚠️ Only with proof that error is impossible
const df = DataFrame.create(allocator, cols, 0) catch unreachable;

// ❌ Never ignore silently
const df = DataFrame.create(allocator, cols, 0) catch null;
```

**CRITICAL: Silent Error Handling = Data Loss**:

1. **Never catch and return default values**:
```zig
// ❌ CRITICAL DATA LOSS - User has no idea allocation failed!
pub fn columnNames(self: *const DataFrame) []const []const u8 {
    const allocator = self.arena.allocator();
    var names = allocator.alloc([]const u8, self.columns.len) catch return &[_][]const u8{};
    // ... returns empty array on allocation failure
}

// ✅ CORRECT - Propagate error to caller
pub fn columnNames(self: *const DataFrame, allocator: std.mem.Allocator) ![]const []const u8 {
    std.debug.assert(self.columns.len > 0);
    std.debug.assert(self.columns.len <= MAX_COLS);

    var names = try allocator.alloc([]const u8, self.columns.len);
    // ... caller handles error
    return names;
}
```

2. **Never catch parse errors and default to 0**:
```zig
// ❌ CRITICAL DATA LOSS - "abc" becomes 0, user never knows!
for (rows, 0..) |row, row_idx| {
    buffer[row_idx] = std.fmt.parseInt(i64, row[col_idx], 10) catch 0;
    // ☝️ Silent data corruption
}

// ✅ CORRECT - Fail fast in Strict mode
for (rows, 0..) |row, row_idx| {
    buffer[row_idx] = std.fmt.parseInt(i64, row[col_idx], 10) catch |err| {
        std.log.err("Failed to parse Int64 at row {}, col {}: '{}' - {}",
            .{row_idx, col_idx, row[col_idx], err});
        return error.TypeMismatch;
    };
}

// ✅ ACCEPTABLE - Lenient mode with error tracking (0.2.0)
for (rows, 0..) |row, row_idx| {
    buffer[row_idx] = std.fmt.parseInt(i64, row[col_idx], 10) catch blk: {
        try self.errors.append(ParseError.init(
            row_idx, col_idx, "Invalid integer format", .TypeMismatch
        ));
        break :blk 0; // Explicit fallback with error logged
    };
}
```

### Functions ≤70 Lines

**Break large functions into helpers**:
```zig
// ❌ Too large (>70 lines)
pub fn parseCSV(buffer: []const u8) !DataFrame {
    // 100 lines of parsing logic
}

// ✅ Correct - broken into helpers
pub fn parseCSV(buffer: []const u8) !DataFrame {
    const headers = try parseHeaders(buffer);
    const rows = try parseRows(buffer, headers.len);
    const types = try inferTypes(rows);
    return try buildDataFrame(headers, rows, types);
}

fn parseHeaders(buffer: []const u8) ![][]const u8 { /* ... */ }
fn parseRows(buffer: []const u8, col_count: u32) ![][]const u8 { /* ... */ }
fn inferTypes(rows: [][]const u8) ![]ValueType { /* ... */ }
```

---

## Common Code Patterns

### Pattern: CSV Field Parsing with State Machine

```zig
const ParserState = enum { Start, InField, InQuotedField, QuoteInQuoted };

fn parseField(parser: *CSVParser) ![]const u8 {
    std.debug.assert(parser.pos <= parser.buffer.len);
    std.debug.assert(parser.current_field.items.len == 0);

    while (parser.pos < parser.buffer.len) {
        const char = parser.buffer[parser.pos];
        parser.pos += 1;

        switch (parser.state) {
            .Start => { /* handle start */ },
            .InField => { /* handle unquoted field */ },
            .InQuotedField => { /* handle quoted field */ },
            .QuoteInQuoted => { /* handle quote escape */ },
        }
    }

    return try parser.current_field.toOwnedSlice();
}
```

### Pattern: Type Inference

```zig
fn inferColumnType(fields: [][]const u8) ValueType {
    std.debug.assert(fields.len > 0);
    std.debug.assert(fields.len <= 100); // Preview limit

    var all_int = true;
    var all_float = true;
    var all_bool = true;

    for (fields) |field| {
        if (!tryParseInt64(field)) all_int = false;
        if (!tryParseFloat64(field)) all_float = false;
        if (!tryParseBool(field)) all_bool = false;
    }

    if (all_int) return .Int64;
    if (all_float) return .Float64;
    if (all_bool) return .Bool;
    return .String;
}
```

### Pattern: Columnar Storage Conversion

```zig
fn rowsToColumns(
    allocator: std.mem.Allocator,
    rows: [][]const u8,
    types: []ValueType,
) ![]Series {
    std.debug.assert(rows.len > 0);
    std.debug.assert(types.len > 0);
    std.debug.assert(rows[0].len == types.len);

    const col_count = types.len;
    const row_count: u32 = @intCast(rows.len);

    var series = try allocator.alloc(Series, col_count);

    for (types, 0..) |typ, col_idx| {
        switch (typ) {
            .Float64 => {
                var data = try allocator.alloc(f64, row_count);
                for (rows, 0..) |row, row_idx| {
                    data[row_idx] = try std.fmt.parseFloat(f64, row[col_idx]);
                }
                series[col_idx] = Series{
                    .valueType = .Float64,
                    .data = .{ .Float64 = data },
                    .length = row_count,
                };
            },
            // ... other types
        }
    }

    return series;
}
```

---

## Error Handling

### Error Set Definitions

**Define clear error sets per module**:
```zig
// src/csv/parser.zig
pub const CSVError = error{
    InvalidFormat,
    UnexpectedEndOfFile,
    TooManyColumns,
    TooManyRows,
    InvalidQuoting,
    OutOfMemory,
};

// src/core/dataframe.zig
pub const DataFrameError = error{
    ColumnNotFound,
    TypeMismatch,
    IndexOutOfBounds,
    EmptyDataFrame,
    OutOfMemory,
};
```

### Error Context

**Provide context when returning errors**:
```zig
pub fn column(self: *const DataFrame, name: []const u8) !*const Series {
    std.debug.assert(self.series.len > 0);

    for (self.series, 0..) |*series, i| {
        if (std.mem.eql(u8, self.columns[i].name, name)) {
            return series;
        }
    }

    // Provide context in error
    std.log.err("Column not found: {s}", .{name});
    return error.ColumnNotFound;
}
```

---

## Memory Management

### Allocation Strategy

**DataFrame lifecycle**:
1. Create arena allocator
2. All DataFrame allocations use arena
3. Single `free()` call cleans up everything

```zig
pub const DataFrame = struct {
    arena: *std.heap.ArenaAllocator,
    // ... fields

    pub fn free(self: DataFrame) void {
        self.arena.deinit();
        self.allocator.destroy(self.arena);
    }
};
```

### Memory Tracking (Debug Builds)

```zig
const MemoryTracker = struct {
    allocator: std.mem.Allocator,
    total_allocated: u64 = 0,
    total_freed: u64 = 0,
    peak_usage: u64 = 0,

    pub fn alloc(self: *MemoryTracker, size: usize) ![]u8 {
        const mem = try self.allocator.alloc(u8, size);
        self.total_allocated += size;
        self.peak_usage = @max(self.peak_usage, self.current());
        return mem;
    }

    pub fn current(self: *const MemoryTracker) u64 {
        return self.total_allocated - self.total_freed;
    }
};
```

---

## Testing Patterns

### Testing Requirements

**CRITICAL**: Every code change MUST include tests. No exceptions.

**Test Coverage Requirements**:
1. **Unit Tests** - Every public function must have at least one unit test
2. **Error Case Tests** - Test error conditions (bounds, invalid input, parse failures)
3. **Integration Tests** - Test workflows (CSV → DataFrame → operations)
4. **Memory Leak Tests** - 1000 iterations of create/free cycles
5. **Conformance Tests** - RFC 4180 compliance using testdata files

**Test Location**: See `../CLAUDE.md` for test organization - all tests go in `src/test/`, NOT in source files

### Unit Test Template

**Every public function needs a unit test**:
```zig
// src/core/series.zig
test "Series.len returns correct length" {
    const allocator = std.testing.allocator;

    const data = try allocator.alloc(f64, 100);
    defer allocator.free(data);

    const series = Series{
        .name = "test",
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 100,
    };

    try std.testing.expectEqual(@as(u32, 100), series.len());
}

test "Series.get checks bounds" {
    const allocator = std.testing.allocator;

    const data = try allocator.alloc(f64, 10);
    defer allocator.free(data);
    data[0] = 1.5;
    data[9] = 9.5;

    const series = Series{
        .name = "test",
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 10,
    };

    // Valid access
    const val0 = series.get(0);
    try std.testing.expect(val0 != null);
    try std.testing.expectEqual(@as(f64, 1.5), val0.?.Float64);

    // Out of bounds should panic (in debug)
    // Cannot test assertion failure in release
}
```

### Memory Leak Test Template

```zig
test "DataFrame.free releases all memory" {
    const allocator = std.testing.allocator;

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const df = try DataFrame.create(
            allocator,
            &[_]ColumnDesc{
                .{ .name = "col1", .valueType = .Float64 },
                .{ .name = "col2", .valueType = .Int64 },
            },
            100,
        );
        df.free();
    }

    // testing.allocator will report leaks automatically
}
```

### Integration Test Template

```zig
test "CSV parse → DataFrame → CSV export round-trip" {
    const allocator = std.testing.allocator;

    const original_csv = "name,age\nAlice,30\nBob,25\n";

    // Parse CSV
    const df = try DataFrame.fromCSVBuffer(allocator, original_csv, .{});
    defer df.free();

    // Export to CSV
    const exported_csv = try df.toCSV(allocator, .{});
    defer allocator.free(exported_csv);

    // Compare (may have whitespace differences)
    try std.testing.expectEqualStrings(original_csv, exported_csv);
}
```

### Test Examples for Common Issues

**1. Test Error Handling - Never Silent Failures**:
```zig
test "fillDataFrame fails on type mismatch instead of silently defaulting to 0" {
    const allocator = std.testing.allocator;

    // CSV with invalid integer value
    const csv = "age\nabc\n";  // "abc" is not a valid integer

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    // ✅ Should FAIL with error, NOT return DataFrame with age=0
    try std.testing.expectError(error.TypeMismatch, parser.toDataFrame());
}

test "columnNames propagates allocation error instead of returning empty array" {
    const allocator = std.testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    // ✅ Should return error, NOT empty array
    // (Use FailingAllocator to test this)
}
```

**2. Test BOM Handling**:
```zig
test "CSVParser skips UTF-8 BOM at start of file" {
    const allocator = std.testing.allocator;

    // CSV with BOM (0xEF 0xBB 0xBF) followed by content
    const csv_with_bom = "\xEF\xBB\xBFname,age\nAlice,30\n";

    var parser = try CSVParser.init(allocator, csv_with_bom, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // ✅ Should parse correctly, ignoring BOM
    try std.testing.expectEqual(@as(u32, 1), df.rowCount);
    try std.testing.expectEqualStrings("name", df.columnDescs[0].name);
}
```

**3. Test Line Ending Handling**:
```zig
test "CSVParser handles CRLF line endings" {
    const allocator = std.testing.allocator;

    const csv = "name,age\r\nAlice,30\r\nBob,25\r\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try std.testing.expectEqual(@as(u32, 2), df.rowCount);
}

test "CSVParser handles CR-only line endings (old Mac format)" {
    const allocator = std.testing.allocator;

    const csv = "name,age\rAlice,30\rBob,25\r";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try std.testing.expectEqual(@as(u32, 2), df.rowCount);
}

test "CSVParser handles LF-only line endings (Unix)" {
    const allocator = std.testing.allocator;

    const csv = "name,age\nAlice,30\nBob,25\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try std.testing.expectEqual(@as(u32, 2), df.rowCount);
}
```

**4. Test Empty CSV Handling**:
```zig
test "toDataFrame allows empty CSV with headers only" {
    const allocator = std.testing.allocator;

    const csv = "name,age,score\n";  // Headers but no data rows

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // ✅ Should create DataFrame with 0 rows, 3 columns
    try std.testing.expectEqual(@as(u32, 0), df.rowCount);
    try std.testing.expectEqual(@as(usize, 3), df.columns.len);
    try std.testing.expectEqualStrings("name", df.columnDescs[0].name);
    try std.testing.expectEqualStrings("age", df.columnDescs[1].name);
    try std.testing.expectEqualStrings("score", df.columnDescs[2].name);
}
```

**5. Test Type Inference Edge Cases**:
```zig
test "inferColumnType detects Float64 when preview has ints but later rows have decimals" {
    const allocator = std.testing.allocator;

    // First 50 rows are integers, row 51 has decimal
    var csv = std.ArrayList(u8).init(allocator);
    defer csv.deinit();

    try csv.appendSlice("value\n");
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        try csv.writer().print("{}\n", .{i});
    }
    try csv.appendSlice("50.5\n");  // Decimal at row 51

    var parser = try CSVParser.init(allocator, csv.items, .{
        .previewRows = 100,  // Preview should see row 51
    });
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // ✅ Should detect as Float64, not Int64
    try std.testing.expectEqual(ValueType.Float64, df.columns[0].valueType);
}
```

**6. Test Bounded Loops**:
```zig
test "nextField rejects field larger than MAX_FIELD_LENGTH" {
    const allocator = std.testing.allocator;

    // Create CSV with field exceeding 1MB
    var csv = std.ArrayList(u8).init(allocator);
    defer csv.deinit();

    try csv.appendSlice("data\n\"");
    // Append 2MB of 'A' characters
    var i: usize = 0;
    while (i < 2_000_000) : (i += 1) {
        try csv.append('A');
    }
    try csv.appendSlice("\"\n");

    var parser = try CSVParser.init(allocator, csv.items, .{});
    defer parser.deinit();

    // ✅ Should reject with FieldTooLarge error
    try std.testing.expectError(error.FieldTooLarge, parser.toDataFrame());
}
```

**7. Test RFC 4180 Conformance** (using testdata files):
```zig
test "RFC 4180: 01_simple.csv" {
    const allocator = std.testing.allocator;
    const csv = @embedFile("../../../testdata/csv/rfc4180/01_simple.csv");

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Validate structure
    try std.testing.expectEqual(@as(u32, 3), df.rowCount);
    try std.testing.expectEqual(@as(usize, 3), df.columns.len);
    try std.testing.expectEqualStrings("name", df.columnDescs[0].name);

    // Validate data
    const age_col = df.column("age").?;
    const ages = age_col.asInt64().?;
    try std.testing.expectEqual(@as(i64, 30), ages[0]);
    try std.testing.expectEqual(@as(i64, 25), ages[1]);
    try std.testing.expectEqual(@as(i64, 35), ages[2]);
}

test "RFC 4180: 04_embedded_newlines.csv - quoted fields with newlines" {
    const allocator = std.testing.allocator;
    const csv = "name,bio\n\"Alice\",\"Line 1\nLine 2\"\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try std.testing.expectEqual(@as(u32, 1), df.rowCount);
    // Bio should contain the newline
    const bio_col = df.column("bio").?;
    // ✅ Should preserve embedded newline in quoted field
}
```

---

## CSV Parsing - Data Processing Correctness

### RFC 4180 Compliance Checklist

**MUST HANDLE**:
1. ✅ Quoted fields with embedded delimiters
2. ✅ Quoted fields with embedded newlines
3. ✅ Escaped quotes (`""` → `"`)
4. ✅ CRLF line endings
5. ⚠️ CR-only line endings (old Mac format)
6. ❌ UTF-8 BOM detection (0xEF 0xBB 0xBF)
7. ✅ Empty fields
8. ⚠️ Empty CSV with headers only

### Critical CSV Parsing Issues

**1. BOM Detection**:
```zig
// ❌ MISSING - CSV may start with BOM
pub fn init(allocator: std.mem.Allocator, buffer: []const u8, opts: CSVOptions) !CSVParser {
    return CSVParser{
        .buffer = buffer,
        .pos = 0,  // Starts at 0, doesn't check for BOM
        // ...
    };
}

// ✅ CORRECT - Skip BOM if present
pub fn init(allocator: std.mem.Allocator, buffer: []const u8, opts: CSVOptions) !CSVParser {
    std.debug.assert(buffer.len > 0);
    std.debug.assert(buffer.len <= MAX_CSV_SIZE);

    // Skip UTF-8 BOM if present
    const start_pos: u32 = if (buffer.len >= 3 and
        buffer[0] == 0xEF and buffer[1] == 0xBB and buffer[2] == 0xBF)
        3
    else
        0;

    return CSVParser{
        .buffer = buffer,
        .pos = start_pos,  // ✅ Skip BOM
        // ...
    };
}
```

**2. Line Ending Normalization** - Avoid code duplication:
```zig
// ❌ WRONG - CRLF handling duplicated in 3 places
} else if (char == '\n' or char == '\r') {
    if (char == '\r' and self.pos < self.buffer.len and self.buffer[self.pos] == '\n') {
        self.pos += 1; // Skip LF in CRLF
    }
    // ... repeated 3 times in different states!
}

// ✅ CORRECT - Centralized line ending detection
fn skipLineEnding(self: *CSVParser) void {
    std.debug.assert(self.pos <= self.buffer.len);

    if (self.pos >= self.buffer.len) return;

    const char = self.buffer[self.pos];
    if (char == '\r') {
        self.pos += 1;
        // Check for CRLF
        if (self.pos < self.buffer.len and self.buffer[self.pos] == '\n') {
            self.pos += 1;
        }
    } else if (char == '\n') {
        self.pos += 1;
    }
}

// Use consistently:
} else if (char == '\n' or char == '\r') {
    self.skipLineEnding();
    self.state = .EndOfRecord;
    return null;
}
```

**3. Empty CSV Handling**:
```zig
// ❌ WRONG - Returns error for headers-only CSV
if (data_rows.len == 0) {
    return error.NoDataRows;  // User just wanted schema!
}

// ✅ CORRECT - Allow empty DataFrames
if (data_rows.len == 0) {
    // Create empty DataFrame with columns but no rows
    var df = try DataFrame.create(self.allocator, col_descs, 0);
    return df;
}
```

**4. Type Inference Edge Cases**:
```zig
// ❌ WRONG - 100 row preview too small for 1M row file
const preview_count = @min(self.opts.previewRows, @as(u32, @intCast(data_rows.len)));

// ✅ BETTER - Adaptive preview based on file size
const preview_count = if (data_rows.len < 1000)
    @intCast(data_rows.len)
else if (data_rows.len < 100_000)
    @min(self.opts.previewRows, @intCast(data_rows.len / 10)) // 10% sample
else
    @min(self.opts.previewRows * 10, 10_000); // 1% sample, capped at 10K
```

**5. Int vs Float Ambiguity**:
```zig
// ❌ WRONG - "42" parses as Int, but row 101 might have "42.5"
if (all_int) return .Int64;
if (all_float) return .Float64;

// ✅ CORRECT - Check for decimal indicators first
var has_decimals = false;
for (rows) |row| {
    if (col_idx >= row.len) continue;
    const field = row[col_idx];
    if (field.len == 0) continue;

    if (std.mem.indexOfScalar(u8, field, '.') != null or
        std.mem.indexOfScalar(u8, field, 'e') != null or
        std.mem.indexOfScalar(u8, field, 'E') != null) {
        has_decimals = true;
        break;
    }
}

// If any field has decimal, treat whole column as Float64
if (has_decimals) {
    // Validate all fields parse as float
    return .Float64;
} else {
    // Validate all fields parse as int
    return .Int64;
}
```

---

**Last Updated**: 2025-10-27
**Related**: See `../CLAUDE.md` for project-wide guidelines and `../docs/` for full documentation
