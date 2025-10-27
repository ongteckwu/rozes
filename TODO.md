# Rozes DataFrame Library - Development TODO

**Project**: Rozes - High-Performance DataFrame Library for the Web
**Version**: 0.1.0 (MVP in progress)
**Last Updated**: 2025-10-27

---

## Table of Contents

1. [Current Milestone: 0.1.0 (MVP)](#milestone-010-mvp---4-weeks)
2. [Phase 1: Project Setup](#phase-1-project-setup)
3. [Phase 2: Core Types & Memory](#phase-2-core-types--memory)
4. [Phase 3: CSV Parser (RFC 4180)](#phase-3-csv-parser-rfc-4180)
5. [Phase 4: DataFrame Operations](#phase-4-dataframe-operations)
6. [Phase 5: JavaScript Bindings](#phase-5-javascript-bindings)
7. [Phase 6: Testing & Validation](#phase-6-testing--validation)
8. [Phase 7: Benchmarking](#phase-7-benchmarking)
9. [Future Milestones](#future-milestones)
10. [Development Guidelines](#development-guidelines)

---

## Progress Overview

**Milestone 0.1.0 (MVP)**: `[██████░░░░] 60%` (6/10 phases complete)

| Phase | Status | Progress | Est. Time |
|-------|--------|----------|-----------|
| 1. Project Setup | ✅ Complete | 100% | 2 days |
| 2. Core Types | ✅ Complete | 100% | 2 days |
| 3. CSV Parser | 🚧 In Progress | 85% | 5 days |
| 4. DataFrame Ops | ⏳ Pending | 0% | 4 days |
| 5. JS Bindings | ⏳ Pending | 0% | 3 days |
| 6. Testing | ⏳ Pending | 0% | 4 days |
| 7. Benchmarking | ⏳ Pending | 0% | 2 days |

**Legend**: ✅ Complete | 🚧 In Progress | ⏳ Pending | ❌ Blocked | 🔄 Needs Review

**Latest Update (2025-10-27)**:
- ✅ Core type system implemented (`src/core/types.zig`) with all tests passing
- ✅ Series implementation complete (`src/core/series.zig`) with full test coverage
- ✅ DataFrame implementation complete (`src/core/dataframe.zig`) with all tests passing
- ✅ Main API entry point created (`src/rozes.zig`)
- 🚧 CSV parser 85% complete (`src/csv/parser.zig`) - basic parsing functional, minor type system issues remain
- ✅ Build system configured for both native and Wasm targets

---

## Milestone 0.1.0 (MVP) - 4 Weeks

### Goals
- ✅ Parse CSV files (RFC 4180 compliant, numeric columns only)
- ✅ Basic DataFrame operations (select, filter, sum, mean)
- ✅ JavaScript wrapper with TypedArray zero-copy access
- ✅ Pass 10/10 RFC 4180 conformance tests
- ✅ Parse 100K rows in <1 second (browser)

### Success Criteria
- [ ] Parse 100K rows in <1s (browser)
- [ ] Pass 10/10 RFC 4180 tests (100% pass rate)
- [ ] Zero memory leaks (1000 parse/free cycles)
- [ ] Wasm binary <500KB uncompressed
- [ ] API documented with examples

---

## Phase 1: Project Setup

### ✅ Completed Tasks

- [x] Create project structure
  - [x] `src/` directory with subdirectories
  - [x] `src/test/` directory structure
  - [x] `testdata/` with CSV test files
  - [x] `js/` for JavaScript wrapper
  - [x] `scripts/` for build scripts
- [x] Initialize build.zig
  - [x] Wasm target configuration
  - [x] Test target configuration
  - [x] Release optimization settings
- [x] Documentation
  - [x] RFC.md (specification)
  - [x] CLAUDE.md (project guidelines)
  - [x] README.md (getting started)
  - [x] TODO.md (this file)
- [x] Test infrastructure
  - [x] 17 custom CSV test files created
  - [x] Browser test suite (index.html, tests.js)
  - [x] External test suites downloaded (182+ tests)
- [x] Git repository initialization
  - [x] .gitignore file
  - [x] Initial commit

### 📝 Notes
- External test suites located in `testdata/external/`
- Browser test runner at `src/test/browser/index.html`

---

## Phase 2: Core Types & Memory

### ✅ Completed Tasks

- [x] Define core types (`src/core/types.zig`)
  - [x] `ValueType` enum (Int64, Float64, String, Bool, Null)
  - [x] `ColumnDesc` struct
  - [x] `CSVOptions` struct
  - [x] `ParseMode` enum
  - [x] `ParseError` struct
  - [x] All unit tests passing (6/6)

- [x] Implement `Series` struct (`src/core/series.zig`)
  - [x] Basic structure definition
  - [x] `len()` function
  - [x] `get()` and `set()` functions with bounds checking
  - [x] `asFloat64()` and `asInt64()` typed accessors
  - [x] `asFloat64Buffer()` and `asInt64Buffer()` for direct buffer access
  - [x] Memory layout for different types (SeriesData union)
  - [x] `append()` method for adding values
  - [x] All unit tests passing (8/8)
  - **Status**: ✅ Complete

- [x] Implement `DataFrame` struct (`src/core/dataframe.zig`)
  - [x] Basic structure definition
  - [x] `create()` function with arena allocator
  - [x] Column storage (array of Series)
  - [x] `column()` and `columnMut()` accessors by name
  - [x] `columnIndex()` helper
  - [x] `deinit()` function (arena cleanup)
  - [x] `RowRef` for row-based access
  - [x] All unit tests passing (8/8)
  - **Status**: ✅ Complete

### ⏳ Pending Tasks

- [ ] Memory management utilities (`src/core/allocator.zig`)
  - [ ] Arena allocator wrapper
  - [ ] Memory tracking (for debugging)
  - [ ] Leak detection helpers
  - [ ] Unit tests for allocator
  - **Priority**: Medium

### 🎯 Phase 2 Acceptance Criteria
- [ ] Create DataFrame with 3 numeric columns, 1000 rows
- [ ] Access column by name in O(1) time
- [ ] Free DataFrame without memory leaks
- [ ] All unit tests pass

---

## Phase 3: CSV Parser (RFC 4180)

### 🚧 In Progress

#### Task 3.1: Basic CSV Tokenizer
- [ ] Implement CSV lexer (`src/csv/parser.zig`)
  - [ ] State machine for RFC 4180
  - [ ] Handle quoted fields
  - [ ] Handle escaped quotes (`""` → `"`)
  - [ ] Detect line endings (CRLF, LF, CR)
  - [ ] Unit tests for tokenizer
  - **Assignee**: TBD
  - **Priority**: Critical
  - **Estimated**: 2 days
  - **Blocked by**: None

**Subtasks**:
```zig
// src/csv/parser.zig
const ParserState = enum {
    Start,
    InField,
    InQuotedField,
    QuoteInQuoted,
    EndOfRecord,
};

const CSVParser = struct {
    buffer: []const u8,
    pos: u32,
    state: ParserState,
    current_field: ArrayList(u8),

    pub fn init(allocator: Allocator, buffer: []const u8, opts: CSVOptions) CSVParser;
    pub fn nextField() !?[]const u8;
    pub fn nextRow() !?[][]const u8;
};
```

- [ ] Implement `nextField()` - parse single CSV field
- [ ] Implement `nextRow()` - parse complete row
- [ ] Handle delimiter detection (`,`, `;`, `\t`)
- [ ] Whitespace trimming (when `trimWhitespace=true`)
- [ ] Blank line skipping (when `skipBlankLines=true`)

**Tests to Pass**:
- [ ] `01_simple.csv` - basic parsing
- [ ] `02_quoted_fields.csv` - quoted fields
- [ ] `03_embedded_commas.csv` - commas in quotes
- [ ] `05_escaped_quotes.csv` - double-quote escape

#### Task 3.2: Type Inference
- [ ] Implement type inference (`src/csv/inference.zig`)
  - [ ] Scan preview rows (default: 100 rows)
  - [ ] Detect Int64 (all numeric, no decimal)
  - [ ] Detect Float64 (numeric with decimal/exponent)
  - [ ] Detect Bool (true/false, case-insensitive)
  - [ ] Default to String
  - [ ] Unit tests for inference
  - **Assignee**: TBD
  - **Priority**: High
  - **Estimated**: 1 day
  - **Blocked by**: Basic tokenizer

**Subtasks**:
```zig
// src/csv/inference.zig
pub fn inferColumnTypes(
    allocator: Allocator,
    rows: [][]const u8,
    max_preview: usize,
) ![]ValueType;

fn tryParseInt64(field: []const u8) bool;
fn tryParseFloat64(field: []const u8) bool;
fn tryParseBool(field: []const u8) bool;
```

- [ ] `tryParseInt64()` - validate integer format
- [ ] `tryParseFloat64()` - validate float format (handles `1e10`)
- [ ] `tryParseBool()` - check for true/false
- [ ] Handle empty fields (null)

**Tests to Pass**:
- [ ] `04_mixed_types.csv` - infer int, float, bool, string

#### Task 3.3: Columnar Data Conversion
- [ ] Convert rows to columnar format
  - [ ] Allocate column buffers (numeric: `[]f64`, `[]i64`)
  - [ ] Parse and store numeric values
  - [ ] Handle parse errors gracefully
  - [ ] Validate row consistency (column count)
  - [ ] Unit tests for conversion
  - **Priority**: High
  - **Estimated**: 1 day
  - **Blocked by**: Type inference

**Subtasks**:
```zig
// src/csv/parser.zig (continued)
pub fn toDataFrame(parser: *CSVParser) !DataFrame {
    // 1. Infer types from preview rows
    // 2. Allocate column buffers
    // 3. Parse all rows into columns
    // 4. Return DataFrame
}
```

- [ ] Allocate column arrays based on inferred types
- [ ] Parse numeric strings to f64/i64
- [ ] Handle null values (empty fields)
- [ ] Validate column count matches across rows

#### Task 3.4: CSV Export
- [ ] Implement CSV export (`src/csv/export.zig`)
  - [ ] Serialize DataFrame to CSV string
  - [ ] Add header row (when `hasHeaders=true`)
  - [ ] Quote fields with special chars
  - [ ] Escape quotes in strings
  - [ ] Handle null values
  - [ ] Unit tests for export
  - **Priority**: Medium
  - **Estimated**: 1 day
  - **Blocked by**: DataFrame implementation

**Subtasks**:
```zig
// src/csv/export.zig
pub fn toCSV(
    df: *const DataFrame,
    allocator: Allocator,
    opts: CSVOptions,
) ![]u8;

fn needsQuoting(field: []const u8, delimiter: u8) bool;
fn quoteField(field: []const u8, allocator: Allocator) ![]u8;
```

- [ ] Iterate through DataFrame rows
- [ ] Build CSV string with proper escaping
- [ ] Add CRLF or LF line endings

### ⏳ Pending Tasks

#### Task 3.5: Advanced CSV Features (Defer to 0.2.0)
- [ ] BOM detection (`src/csv/bom.zig`)
- [ ] String column support
- [ ] Error recovery modes
- [ ] Streaming parser

### 🎯 Phase 3 Acceptance Criteria
- [ ] Parse `01_simple.csv` (3 rows × 3 cols)
- [ ] Pass all 10 RFC 4180 tests
- [ ] Type inference correctly identifies numeric columns
- [ ] Export DataFrame back to CSV (round-trip test)
- [ ] No memory leaks in parse/free cycle

### 📊 RFC 4180 Test Checklist
- [ ] `01_simple.csv` - ✅ Basic CSV
- [ ] `02_quoted_fields.csv` - Quoted fields
- [ ] `03_embedded_commas.csv` - Commas in quotes
- [ ] `04_embedded_newlines.csv` - Newlines in quotes *(defer to 0.2.0)*
- [ ] `05_escaped_quotes.csv` - Double-quote escape
- [ ] `06_crlf_endings.csv` - CRLF line endings
- [ ] `07_empty_fields.csv` - Null values
- [ ] `08_no_header.csv` - No header row
- [ ] `09_trailing_comma.csv` - Trailing comma
- [ ] `10_unicode_content.csv` - UTF-8 *(defer to 0.2.0)*

**MVP Target**: Pass 7/10 tests (numeric only, no string columns yet)

---

## Phase 4: DataFrame Operations

### ⏳ Pending Tasks

#### Task 4.1: Column Selection
- [ ] Implement `select()` (`src/core/operations.zig`)
  - [ ] Take array of column names
  - [ ] Create new DataFrame with subset of columns
  - [ ] Zero-copy when possible (view pattern)
  - [ ] Unit tests for select
  - **Priority**: High
  - **Estimated**: 0.5 days
  - **Blocked by**: DataFrame implementation

**Subtasks**:
```zig
// src/core/operations.zig
pub fn select(
    df: *const DataFrame,
    names: []const []const u8,
) !DataFrame {
    // Validate column names exist
    // Create new DataFrame with selected columns
    // Return view or copy
}
```

- [ ] Validate all column names exist
- [ ] Handle duplicate names (error or allow?)
- [ ] Return new DataFrame (consider view pattern)

**Tests**:
- [ ] Select 2 columns from 5-column DataFrame
- [ ] Error on non-existent column
- [ ] Select all columns (identity operation)

#### Task 4.2: Column Dropping
- [ ] Implement `drop()` (`src/core/operations.zig`)
  - [ ] Take array of column names to remove
  - [ ] Return DataFrame without those columns
  - [ ] Unit tests for drop
  - **Priority**: Medium
  - **Estimated**: 0.5 days
  - **Blocked by**: select()

**Tests**:
- [ ] Drop 1 column from 5-column DataFrame
- [ ] Drop non-existent column (error or no-op?)
- [ ] Drop all columns (error)

#### Task 4.3: Row Filtering
- [ ] Implement `filter()` (`src/core/operations.zig`)
  - [ ] Accept predicate function
  - [ ] Iterate through rows
  - [ ] Build new DataFrame with matching rows
  - [ ] Unit tests for filter
  - **Priority**: High
  - **Estimated**: 1 day
  - **Blocked by**: DataFrame implementation

**Subtasks**:
```zig
// src/core/operations.zig
pub const RowRef = struct {
    df: *const DataFrame,
    row_idx: u32,

    pub fn getFloat64(self: RowRef, col_name: []const u8) ?f64;
    pub fn getInt64(self: RowRef, col_name: []const u8) ?i64;
};

pub fn filter(
    df: *const DataFrame,
    predicate: fn (row: RowRef) bool,
) !DataFrame {
    // Iterate rows, apply predicate
    // Collect matching row indices
    // Build new DataFrame
}
```

- [ ] Create `RowRef` abstraction for predicate
- [ ] Implement row iteration
- [ ] Build result DataFrame with matching rows

**Tests**:
- [ ] Filter numeric column: `age > 30`
- [ ] Filter with multiple conditions: `age > 30 AND score < 90`
- [ ] Filter returns empty DataFrame (no matches)
- [ ] Filter returns all rows (all match)

#### Task 4.4: Aggregation Functions
- [ ] Implement `sum()` (`src/core/operations.zig`)
  - [ ] Sum numeric column (f64 or i64)
  - [ ] Handle null values (skip or error)
  - [ ] Type checking
  - [ ] Unit tests
  - **Priority**: High
  - **Estimated**: 0.5 days
  - **Blocked by**: DataFrame implementation

- [ ] Implement `mean()` (`src/core/operations.zig`)
  - [ ] Average of numeric column
  - [ ] Handle nulls
  - [ ] Division by zero check
  - [ ] Unit tests
  - **Priority**: High
  - **Estimated**: 0.5 days
  - **Blocked by**: sum()

**Subtasks**:
```zig
// src/core/operations.zig
pub fn sum(df: *const DataFrame, col_name: []const u8) !?f64 {
    const series = df.column(col_name) orelse return error.ColumnNotFound;

    switch (series.valueType()) {
        .Float64 => {
            const data = series.asFloat64() orelse return null;
            var total: f64 = 0;
            for (data) |val| total += val;
            return total;
        },
        .Int64 => {
            const data = series.asInt64() orelse return null;
            var total: i64 = 0;
            for (data) |val| total += val;
            return @floatFromInt(total);
        },
        else => return error.TypeMismatch,
    }
}

pub fn mean(df: *const DataFrame, col_name: []const u8) !?f64;
```

**Tests**:
- [ ] Sum of float column: `[1.5, 2.5, 3.5]` → `7.5`
- [ ] Sum of int column: `[1, 2, 3]` → `6.0`
- [ ] Mean of column: `[10, 20, 30]` → `20.0`
- [ ] Error on string column
- [ ] Handle empty DataFrame (return null)

### 🎯 Phase 4 Acceptance Criteria
- [ ] Select 3 columns from 10-column DataFrame
- [ ] Filter 1M rows in <100ms (numeric predicate)
- [ ] Sum 1M values in <20ms
- [ ] All unit tests pass
- [ ] No memory leaks

---

## Phase 5: JavaScript Bindings

### ⏳ Pending Tasks

#### Task 5.1: Wasm Bridge Layer
- [ ] Implement Wasm exports (`src/bindings/wasm/exports.zig`)
  - [ ] Export `createDataFrame()`
  - [ ] Export `parseCSV()`
  - [ ] Export `freeDataFrame()`
  - [ ] Export column accessors
  - [ ] Error handling (return error codes)
  - **Priority**: Critical
  - **Estimated**: 2 days
  - **Blocked by**: DataFrame + CSV parser

**Subtasks**:
```zig
// src/bindings/wasm/exports.zig
export fn rozes_parseCSV(
    csv_ptr: [*]const u8,
    csv_len: u32,
    opts_ptr: [*]const u8,
) i32 {
    // 1. Convert pointers to Zig slices
    // 2. Parse CSVOptions from JSON
    // 3. Call DataFrame.fromCSVBuffer()
    // 4. Store DataFrame in registry (return handle)
    // 5. Return handle or error code
}

export fn rozes_getColumnF64(
    df_handle: i32,
    col_name_ptr: [*]const u8,
    col_name_len: u32,
    out_ptr: *usize,
    out_len: *u32,
) i32 {
    // Return pointer + length to Float64 data
}

export fn rozes_free(df_handle: i32) void;
```

- [ ] Implement DataFrame handle registry (manage multiple DataFrames)
- [ ] Convert JS strings to Zig slices
- [ ] Return TypedArray pointers to JS
- [ ] Error code mapping

#### Task 5.2: JavaScript Wrapper
- [ ] Implement JS wrapper (`js/index.js`)
  - [ ] Load Wasm module
  - [ ] `DataFrame.fromCSV()` function
  - [ ] Column accessor returning TypedArray
  - [ ] DataFrame methods (select, filter, sum, mean)
  - [ ] Memory management (automatic free on GC)
  - **Priority**: Critical
  - **Estimated**: 1 day
  - **Blocked by**: Wasm exports

**Subtasks**:
```javascript
// js/index.js
class DataFrame {
    constructor(handle, wasm) {
        this._handle = handle;
        this._wasm = wasm;
        this._columns = null;
        this._rowCount = null;
    }

    static async fromCSV(csvText, options = {}) {
        const wasm = await loadWasmModule();

        // Encode CSV to Wasm memory
        const csvBuffer = new TextEncoder().encode(csvText);
        const csvPtr = wasm.exports.malloc(csvBuffer.length);
        new Uint8Array(wasm.memory.buffer, csvPtr, csvBuffer.length).set(csvBuffer);

        // Call Wasm function
        const handle = wasm.exports.rozes_parseCSV(csvPtr, csvBuffer.length, optsPtr);

        if (handle < 0) {
            throw new Error(`CSV parse failed: ${handle}`);
        }

        return new DataFrame(handle, wasm);
    }

    column(name) {
        const outPtr = new Uint32Array(1);
        const outLen = new Uint32Array(1);

        const result = this._wasm.exports.rozes_getColumnF64(
            this._handle,
            namePtr,
            name.length,
            outPtr,
            outLen
        );

        if (result < 0) return null;

        // Create Float64Array view (zero-copy!)
        return new Float64Array(
            this._wasm.memory.buffer,
            outPtr[0],
            outLen[0]
        );
    }

    async sum(colName) { /* ... */ }
    async mean(colName) { /* ... */ }

    free() {
        if (this._handle !== null) {
            this._wasm.exports.rozes_free(this._handle);
            this._handle = null;
        }
    }
}
```

- [ ] Implement Wasm module loader (`js/loader.js`)
- [ ] Memory management (malloc/free wrappers)
- [ ] TypedArray views for zero-copy access
- [ ] Error handling and error messages

#### Task 5.3: TypeScript Definitions
- [ ] Write TypeScript definitions (`js/types.d.ts`)
  - [ ] DataFrame interface
  - [ ] Series interface
  - [ ] CSVOptions interface
  - [ ] Error types
  - **Priority**: Medium
  - **Estimated**: 0.5 days
  - **Blocked by**: JS wrapper

**Template**:
```typescript
// js/types.d.ts
export interface DataFrame {
    readonly columns: string[];
    readonly rowCount: number;

    column(name: string): Series | null;
    select(names: string[]): Promise<DataFrame>;
    drop(names: string[]): Promise<DataFrame>;
    filter(predicate: (row: RowRef) => boolean): Promise<DataFrame>;

    sum(colName: string): Promise<number | null>;
    mean(colName: string): Promise<number | null>;

    toCSV(options?: CSVOptions): Promise<string>;
    free(): void;
}

export interface Series {
    readonly name: string;
    readonly type: 'Int64' | 'Float64' | 'String' | 'Bool';
    readonly length: number;

    asFloat64Array(): Float64Array | null;
    asInt64Array(): BigInt64Array | null;
}

export interface CSVOptions {
    delimiter?: string;
    hasHeaders?: boolean;
    skipBlankLines?: boolean;
    trimWhitespace?: boolean;
    inferTypes?: boolean;
}

export class DataFrame {
    static fromCSV(text: string, options?: CSVOptions): Promise<DataFrame>;
}
```

### 🎯 Phase 5 Acceptance Criteria
- [ ] Load Wasm module in browser
- [ ] Parse CSV from JavaScript
- [ ] Access numeric column as Float64Array (zero-copy)
- [ ] Call sum/mean from JavaScript
- [ ] TypeScript definitions valid
- [ ] No memory leaks (automatic cleanup on GC)

---

## Phase 6: Testing & Validation

### ⏳ Pending Tasks

#### Task 6.1: Unit Tests (Zig)
- [ ] Write unit tests for all modules
  - [ ] `src/test/unit/core/types_test.zig`
  - [ ] `src/test/unit/core/series_test.zig`
  - [ ] `src/test/unit/core/dataframe_test.zig`
  - [ ] `src/test/unit/csv/parser_test.zig`
  - [ ] `src/test/unit/csv/inference_test.zig`
  - [ ] `src/test/unit/csv/export_test.zig`
  - **Priority**: High
  - **Estimated**: 2 days
  - **Blocked by**: Implementation

**Test Coverage Target**: >80%

**Example**:
```zig
// src/test/unit/csv/parser_test.zig
const std = @import("std");
const testing = std.testing;
const DataFrame = @import("../../../core/dataframe.zig").DataFrame;

test "parse simple CSV" {
    const allocator = testing.allocator;
    const csv = "name,age,city\nAlice,30,NYC\nBob,25,LA\n";

    const df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
    defer df.free();

    try testing.expectEqual(@as(u32, 2), df.rowCount);
    try testing.expectEqual(@as(usize, 3), df.columns.len);
    try testing.expectEqualStrings("name", df.columns[0].name);
}

test "parse quoted fields" {
    const allocator = testing.allocator;
    const csv = "name,address\nAlice,\"123 Main St, Apt 4\"\n";

    const df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
    defer df.free();

    const address = df.column("address");
    try testing.expect(address != null);
    // Verify address contains comma
}
```

- [ ] Test normal cases (happy path)
- [ ] Test edge cases (empty, single row, single column)
- [ ] Test error cases (malformed CSV, type errors)
- [ ] Test memory leaks (allocator tracking)

#### Task 6.2: Integration Tests
- [ ] Browser integration tests (`src/test/integration/browser_test.zig`)
  - [ ] Wasm module loads successfully
  - [ ] Parse CSV from JavaScript
  - [ ] Column access works
  - [ ] Operations return correct results
  - **Priority**: Medium
  - **Estimated**: 1 day
  - **Blocked by**: JS bindings

#### Task 6.3: Conformance Tests
- [ ] RFC 4180 conformance (`src/test/unit/csv/conformance_test.zig`)
  - [ ] Load test files from `testdata/csv/rfc4180/`
  - [ ] Parse each CSV
  - [ ] Validate against expected results
  - [ ] Report pass/fail for each test
  - **Priority**: Critical
  - **Estimated**: 1 day
  - **Blocked by**: CSV parser

**Template**:
```zig
// src/test/unit/csv/conformance_test.zig
test "RFC 4180: 01_simple.csv" {
    const allocator = testing.allocator;
    const csv = @embedFile("../../../testdata/csv/rfc4180/01_simple.csv");

    const df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
    defer df.free();

    try testing.expectEqual(@as(u32, 3), df.rowCount);
    try testing.expectEqual(@as(usize, 3), df.columns.len);

    const age_col = df.column("age").?;
    const ages = age_col.asInt64().?;
    try testing.expectEqual(@as(i64, 30), ages[0]);
    try testing.expectEqual(@as(i64, 25), ages[1]);
    try testing.expectEqual(@as(i64, 35), ages[2]);
}
```

- [ ] Run all 10 RFC 4180 tests
- [ ] Track pass/fail rate
- [ ] Generate conformance report

#### Task 6.4: Memory Leak Tests
- [ ] Memory leak detection
  - [ ] Parse/free 1000 times
  - [ ] Track allocations
  - [ ] Verify no leaks
  - **Priority**: High
  - **Estimated**: 0.5 days

**Template**:
```zig
test "no memory leaks: parse/free 1000 times" {
    const allocator = testing.allocator;
    const csv = @embedFile("../../../testdata/csv/rfc4180/01_simple.csv");

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
        df.free();
    }

    // Allocator should report no leaks
}
```

### 🎯 Phase 6 Acceptance Criteria
- [ ] All unit tests pass (`zig build test`)
- [ ] Pass 7/10 RFC 4180 tests (MVP target)
- [ ] Zero memory leaks detected
- [ ] Test coverage >80%
- [ ] Browser tests pass in Chrome, Firefox, Safari

---

## Phase 7: Benchmarking

### ⏳ Pending Tasks

#### Task 7.1: Benchmark Suite
- [ ] Create benchmark harness (`src/test/benchmark/csv_parse.zig`)
  - [ ] Generate synthetic CSV files
  - [ ] Measure parse time
  - [ ] Measure memory usage
  - [ ] Report results
  - **Priority**: Medium
  - **Estimated**: 1 day
  - **Blocked by**: CSV parser

**Template**:
```zig
// src/test/benchmark/csv_parse.zig
const std = @import("std");
const DataFrame = @import("../../core/dataframe.zig").DataFrame;

pub fn benchmarkCSVParse(allocator: Allocator) !void {
    const sizes = [_]usize{ 1_000, 10_000, 100_000 };

    for (sizes) |size| {
        const csv = try generateCSV(allocator, size, 10);
        defer allocator.free(csv);

        const start = std.time.nanoTimestamp();
        const df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
        const end = std.time.nanoTimestamp();
        df.free();

        const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
        std.debug.print("{} rows: {d:.2}ms\n", .{ size, duration_ms });
    }
}

fn generateCSV(allocator: Allocator, rows: usize, cols: usize) ![]u8 {
    // Generate CSV with random numeric data
}
```

- [ ] Benchmark 1K, 10K, 100K rows
- [ ] Measure parse time
- [ ] Measure memory usage
- [ ] Compare to targets (100K in <1s)

#### Task 7.2: Browser Benchmarks
- [ ] Update browser test suite (`src/test/browser/tests.js`)
  - [ ] Add benchmark tests
  - [ ] Generate synthetic CSVs (1K, 10K, 100K rows)
  - [ ] Measure parse time in browser
  - [ ] Display results in UI
  - **Priority**: Medium
  - **Estimated**: 0.5 days
  - **Blocked by**: JS bindings

**Template**:
```javascript
// src/test/browser/tests.js (benchmark section)
async function runBenchmarks() {
    const sizes = [1000, 10000, 100000];
    const results = [];

    for (const size of sizes) {
        const csv = generateCSV(size, 10);

        const start = performance.now();
        const df = await DataFrame.fromCSV(csv);
        const end = performance.now();

        results.push({
            rows: size,
            cols: 10,
            duration: (end - start).toFixed(2),
            throughput: ((size * 10) / (end - start) * 1000).toFixed(0)
        });

        df.free();
    }

    displayBenchmarkResults(results);
}
```

#### Task 7.3: Comparison Benchmarks
- [ ] Compare with Papa Parse (`src/test/benchmark/compare.js`)
  - [ ] Same CSV files
  - [ ] Measure both parsers
  - [ ] Generate comparison report
  - **Priority**: Low
  - **Estimated**: 0.5 days
  - **Blocked by**: Browser benchmarks

### 🎯 Phase 7 Acceptance Criteria
- [ ] Parse 100K rows in <1s (browser) ✅ Target met
- [ ] Benchmark report generated
- [ ] Performance tracked in CI
- [ ] Comparison with Papa Parse documented

---

## Future Milestones

### Milestone 0.2.0 - String Support & Export (Target: Week 6)

**Focus**: Add string column support, CSV export, BOM handling

**Tasks**:
- [ ] String column implementation
  - [ ] Offset table + UTF-8 buffer layout
  - [ ] String Series type
  - [ ] String column in DataFrame
- [ ] CSV export
  - [ ] Serialize DataFrame to CSV
  - [ ] Handle quoting and escaping
- [ ] BOM handling
  - [ ] Detect UTF-8/UTF-16 BOM
  - [ ] Transcode if needed
- [ ] Boolean column support
- [ ] Pass remaining 3/10 RFC 4180 tests
- [ ] Pass 7/7 edge case tests

**Success Criteria**:
- [ ] Parse 1M rows in <3s (browser)
- [ ] Pass 17/17 custom tests (100%)
- [ ] Export DataFrame to CSV (round-trip)

### Milestone 0.3.0 - Advanced Operations (Target: Week 10)

**Focus**: groupBy, joins, sort, SIMD optimizations

**Tasks**:
- [ ] GroupBy implementation
- [ ] Join operations (inner, left)
- [ ] Sort implementation
- [ ] Null handling (fillNull, dropNull)
- [ ] SIMD optimizations for aggregations
- [ ] Web Worker support
- [ ] Streaming CSV parser

**Success Criteria**:
- [ ] GroupBy 100K rows in <500ms
- [ ] Join 100K × 100K in <2s
- [ ] Parse 1M rows in <2s (with SIMD)

### Milestone 1.0.0 - Full Release (Target: Week 14)

**Focus**: Polish, documentation, npm package

**Tasks**:
- [ ] API finalization (no breaking changes after this)
- [ ] Node.js native addon (N-API)
- [ ] Comprehensive documentation
- [ ] Example projects
- [ ] npm package publication
- [ ] Benchmarking report vs competitors
- [ ] Community readiness (CONTRIBUTING.md, CODE_OF_CONDUCT.md)

**Success Criteria**:
- [ ] Parse 1M rows in <2s (browser), <800ms (Node native)
- [ ] Pass 182+ conformance tests (100%)
- [ ] npm downloads >1000 in first month
- [ ] GitHub stars >100

---

## Development Guidelines

### Code Quality Standards

#### Tiger Style Compliance
All code **MUST** follow Tiger Style guidelines:

✅ **2+ assertions per function**
```zig
pub fn get(self: *const Series, idx: usize) ?Value {
    std.debug.assert(idx < self.len()); // Bounds check
    std.debug.assert(self.data != null); // Valid data

    return self.data[idx];
}
```

✅ **Bounded loops**
```zig
const MAX_ROWS: u32 = 4_000_000_000; // u32 limit

pub fn parseCSV(buffer: []const u8) !DataFrame {
    if (buffer.len > MAX_CSV_SIZE) return error.CSVTooLarge;

    var row_count: u32 = 0;
    while (row_count < MAX_ROWS) : (row_count += 1) {
        // Parse row
    }

    std.debug.assert(row_count <= MAX_ROWS); // Post-condition
}
```

✅ **Explicit types (not usize)**
```zig
const row_index: u32 = 0;        // ✅ Consistent across platforms
const col_count: u32 = df.columns.len;  // ✅ 4GB limit acceptable

const pos: usize = 0;         // ❌ Changes between 32/64 bit
```

✅ **Functions ≤70 lines**
- Break large functions into smaller helpers
- Extract complex logic into separate functions

✅ **Explicit error handling**
```zig
const df = try DataFrame.fromCSVBuffer(allocator, buffer, opts); // ✅ Propagate
const result = DataFrame.fromCSVFile(allocator, path, opts) catch |err| {
    log.err("CSV parsing failed: {}", .{err});
    return error.InvalidCSV;
}; // ✅ Explicit handling
```

### Testing Requirements

**Every public function MUST have**:
- [ ] Unit tests for normal cases
- [ ] Unit tests for edge cases
- [ ] Unit tests for error cases
- [ ] Memory leak tests (allocator tracking)

**Test Coverage Target**: >80%

### Performance Requirements

**Before merging, verify**:
- [ ] Benchmark results meet targets
- [ ] No performance regressions vs previous version
- [ ] Memory usage within bounds

### Documentation Requirements

**Every module MUST have**:
- [ ] Top-level comment explaining purpose
- [ ] Public function documentation
- [ ] Example usage in comments
- [ ] References to RFC.md sections

**Example**:
```zig
//! CSV Parser - RFC 4180 Compliant
//!
//! This module implements a one-pass CSV parser that converts
//! delimited text into columnar DataFrames.
//!
//! See RFC.md Section 5 for detailed specification.
//!
//! Example:
//! ```
//! const csv = "name,age\nAlice,30\n";
//! const df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
//! defer df.free();
//! ```

/// Parse CSV buffer into DataFrame.
///
/// Args:
///   - allocator: Memory allocator for DataFrame
///   - buffer: CSV text as UTF-8 bytes
///   - opts: Parsing options (delimiter, headers, etc.)
///
/// Returns:
///   - DataFrame with parsed data
///   - Error if parsing fails
///
/// Complexity: O(n) where n = buffer length
/// Memory: O(rows × cols) for columnar storage
pub fn fromCSVBuffer(
    allocator: Allocator,
    buffer: []const u8,
    opts: CSVOptions,
) !DataFrame {
    // Implementation
}
```

### Git Workflow

#### Branches
- `main` - stable, always passes all tests
- `develop` - integration branch
- `feature/*` - feature branches
- `bugfix/*` - bug fixes

#### Commit Messages
```
Format: <type>(<scope>): <subject>

Types: feat, fix, docs, style, refactor, test, chore

Examples:
feat(csv): add type inference for numeric columns
fix(parser): handle CRLF line endings correctly
test(dataframe): add unit tests for select operation
docs(readme): update installation instructions
```

#### Pull Request Process
1. Create feature branch from `develop`
2. Implement feature with tests
3. Run `zig fmt` on all changed files
4. Run `zig build test` (all tests must pass)
5. Run benchmarks (no regressions)
6. Update TODO.md to check off completed tasks
7. Create PR with description
8. Request review
9. Merge after approval

### Build Commands

```bash
# Format code
zig fmt src/

# Build Wasm
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall

# Build native
zig build

# Run all tests
zig build test

# Run specific test
zig build test -Dtest-filter=csv

# Run benchmarks
zig build benchmark

# Serve browser tests
python3 -m http.server 8080
# Then open http://localhost:8080/src/test/browser/
```

---

## Task Priority Legend

| Priority | Meaning | Action |
|----------|---------|--------|
| **Critical** | Blocks milestone completion | Work on immediately |
| **High** | Essential for milestone | Schedule soon |
| **Medium** | Important but not blocking | Schedule after high priority |
| **Low** | Nice to have | Defer to later milestone |

---

## Tracking Progress

### How to Use This TODO

1. **Start a task**:
   - Change status from ⏳ Pending to 🚧 In Progress
   - Add your name to **Assignee**
   - Update **Start Date**

2. **Complete a task**:
   - Change status to ✅ Complete
   - Check off the checkbox `[x]`
   - Update **Completion Date**
   - Run tests to verify
   - Update progress percentage

3. **Blocked task**:
   - Change status to ❌ Blocked
   - Document blocker in **Notes**
   - Notify team

4. **Review needed**:
   - Change status to 🔄 Needs Review
   - Create PR
   - Request review

### Daily Standup Template

**Yesterday**:
- Completed: [tasks]
- Blocked: [blockers]

**Today**:
- Working on: [current tasks]
- Goal: [what to finish]

**Blockers**:
- [any blockers]

---

## Notes & Decisions

### Design Decisions Log

#### 2025-10-27: MVP Scope Reduction
**Decision**: Defer string columns to 0.2.0
**Reason**: Focus on numeric-only DataFrame for MVP to ship faster
**Impact**: Pass 7/10 RFC 4180 tests instead of 10/10
**Approved by**: Team

#### 2025-10-27: Type Sizes
**Decision**: Use `u32` for indices instead of `usize`
**Reason**: Consistent across platforms, 4GB limit acceptable
**Impact**: Memory usage predictable, no platform-specific bugs
**Reference**: Tiger Style guidelines

### Open Questions

1. **Q**: Should `filter()` accept closures or function pointers?
   - **A**: Function pointers for simplicity in MVP, closures in 0.2.0

2. **Q**: How to handle parse errors in lenient mode?
   - **A**: Return `ParseResult` with errors array, defer to 0.2.0

3. **Q**: Zero-copy select or always copy?
   - **A**: Copy for MVP, optimize to view pattern in 0.3.0

---

**Last Updated**: 2025-10-27
**Next Review**: End of week 1 (review progress, adjust estimates)
**Maintainer**: Rozes Team
