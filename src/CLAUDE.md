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
//! See RFC.md Section 4.1 for type specifications.

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

---

**Last Updated**: 2025-10-27
**Related**: See `/CLAUDE.md` for project-wide guidelines
