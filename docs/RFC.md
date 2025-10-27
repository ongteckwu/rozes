# RFC: Rozes – High-Performance DataFrame Library for the Web

**Version**: 2.0
**Date**: 2025-10-27
**Authors**: Rozes Team
**Status**: Active Development

---

## Table of Contents

1. [Purpose & Goals](#1-purpose--goals)
2. [Scope](#2-scope)
3. [Definitions & Terminology](#3-definitions--terminology)
4. [API Specification](#4-api-specification)
5. [CSV Parsing Specification](#5-csv-parsing-specification)
6. [Architecture & Build System](#6-architecture--build-system)
7. [Testing & Conformance](#7-testing--conformance)
8. [Performance Targets](#8-performance-targets)
9. [Roadmap & Milestones](#9-roadmap--milestones)
10. [Risks & Mitigations](#10-risks--mitigations)
11. [References](#11-references)

---

## 1. Purpose & Goals

### Purpose

Define the specification for a high-performance DataFrame library in Zig, compiled to WebAssembly (and native Node.js addon), to enable near-native tabular data manipulation on the web and server with CSV ingest/export as the primary capability.

### Goals

✅ **Near-Native Performance**: Provide a DataFrame library with near-native performance in browsers and Node.js
✅ **Seamless API**: Offer intuitive API for JavaScript/TypeScript users and native Zig developers
✅ **CSV First**: Robust, highly-optimized CSV parsing and export as first-class capability
✅ **Columnar Layout**: Efficient columnar memory layout with minimal data-copy between JS and Wasm
✅ **Rich Operations**: Support filter, select, aggregation (sum, mean, count), groupBy, join
✅ **Cross-Platform**: Browser (Wasm) and Node.js (native addon or Wasm)
✅ **Benchmark Driven**: Position as "fastest DataFrame for the web" via rigorous benchmarking

---

## 2. Scope

### In Scope (v1.0)

- ✅ Core DataFrame and Series abstractions (columns, rows)
- ✅ CSV import (parsing) and CSV export (serialization)
- ✅ Basic operations: select, filter, add/drop columns
- ✅ Aggregation: sum, mean, count, min, max
- ✅ groupBy operations
- ✅ Simple joins (inner, left)
- ✅ Sort operations
- ✅ Null value handling
- ✅ Type inference (int64, float64, bool, string)
- ✅ API wrapper for JavaScript/TypeScript (browser & Node)
- ✅ Build system targeting wasm32-unknown-unknown and native addons
- ✅ Memory/TypedArray bridging between JS and Wasm
- ✅ Benchmark harness
- ✅ Streaming CSV parsing for large files
- ✅ Error recovery modes (strict, lenient, best-effort)
- ✅ BOM (Byte Order Mark) handling for UTF-8/UTF-16

### Out of Scope (for v1.0)

- ❌ Full Pandas-level feature set (multi-index, time-series)
- ❌ Parquet/Arrow IO (future consideration)
- ❌ Distributed / out-of-core execution
- ❌ GUI/visualization (library is backend-focused)
- ❌ Native mobile/embedded variants

### Future Considerations (v2.0+)

- Binary serialization format (faster than CSV)
- Apache Arrow interoperability
- Advanced time-series operations
- Multi-threaded operations (worker pool)
- Lazy evaluation / query optimization

---

## 3. Definitions & Terminology

| Term | Definition |
|------|------------|
| **DataFrame** | A 2D tabular data structure composed of named columns (each a Series) |
| **Series** | A 1D homogeneous typed array of values (int64, float64, string, bool) with optional name |
| **CSV Import/Export** | Reading/writing RFC 4180-compliant delimited text files into/from DataFrames |
| **Columnar Layout** | Data stored column-by-column (not row-by-row) for efficient vectorized operations |
| **Wasm** | WebAssembly binary target for browser and Node.js |
| **JS Wrapper** | JavaScript/TypeScript interface to the underlying Wasm/native module |
| **Allocator** | Zig memory allocator; in Wasm uses linear memory, in native uses system allocator |
| **TypedArray** | JS concept (Float64Array, Int32Array) for zero-copy memory between JS ↔ Wasm |
| **Arena Allocator** | Zig allocator that frees all memory in a single operation (used for DataFrame lifecycle) |
| **BOM** | Byte Order Mark - UTF-8 (EF BB BF) or UTF-16 (FF FE / FE FF) file header |

---

## 4. API Specification

### 4.1 Core Types

```zig
pub const ValueType = enum {
    Int64,
    Float64,
    String,
    Bool,
    Null,    // NEW: explicit null type
};

pub const ColumnDesc = struct {
    name: []const u8,
    valueType: ValueType,
};

pub const CSVOptions = struct {
    delimiter: u8 = ',',
    hasHeaders: bool = true,
    skipBlankLines: bool = true,
    trimWhitespace: bool = true,
    quoteChar: u8 = '"',
    escapeChar: u8 = '"',
    maxRowsToPreview: usize = 100,
    inferTypes: bool = true,

    // NEW: Advanced options
    detectBOM: bool = true,           // Auto-detect UTF-8/UTF-16 BOM
    stripBOM: bool = true,             // Remove BOM from output
    parseMode: ParseMode = .Strict,    // Error handling mode
    memoryLimit: ?u64 = null,          // Bytes, null = unlimited
    nullValues: []const []const u8 = &[_][]const u8{ "NULL", "NA", "" },
};

// NEW: Parse mode for error handling
pub const ParseMode = enum {
    Strict,      // Fail on first error
    Lenient,     // Skip bad rows, log errors
    BestEffort,  // Attempt to recover, fill with null
};

// NEW: Parse result with error reporting
pub const ParseResult = struct {
    dataframe: DataFrame,
    errors: []ParseError,
    rows_skipped: u32,
};

pub const ParseError = struct {
    row: u32,
    column: u32,
    kind: enum {
        UnexpectedQuote,
        MissingQuote,
        ColumnCountMismatch,
        InvalidEncoding,
    },
    message: []const u8,
};
```

### 4.2 Series API

```zig
pub const Series = struct {
    pub const Self = Series;

    pub fn len(self: *const Self) usize;
    pub fn get(self: *const Self, idx: usize) ?Value;
    pub fn name(self: *const Self) []const u8;
    pub fn valueType(self: *const Self) ValueType;

    // Typed access (returns null if type mismatch)
    pub fn asFloat64(self: *const Self) ?[]f64;
    pub fn asInt64(self: *const Self) ?[]i64;
    pub fn asString(self: *const Self) ?[][]const u8;
    pub fn asBool(self: *const Self) ?[]bool;
};
```

### 4.3 DataFrame API

```zig
pub const DataFrame = struct {
    allocator: *std.mem.Allocator,
    columns: []ColumnDesc,
    rowCount: u32,

    // Creation
    pub fn create(
        allocator: *std.mem.Allocator,
        columns: []ColumnDesc,
        rowCount: usize,
    ) !DataFrame;

    // CSV Import
    pub fn fromCSVFile(
        allocator: *std.mem.Allocator,
        path: []const u8,
        opts: CSVOptions,
    ) !DataFrame;

    pub fn fromCSVBuffer(
        allocator: *std.mem.Allocator,
        buffer: []const u8,
        opts: CSVOptions,
    ) !DataFrame;

    // NEW: Streaming CSV import
    pub const StreamingCSVReader = struct {
        pub fn init(
            allocator: Allocator,
            reader: std.io.Reader,
            opts: CSVOptions,
            chunk_size: usize,
        ) !StreamingCSVReader;

        pub fn nextChunk(self: *StreamingCSVReader) !?DataFrame;
        pub fn deinit(self: *StreamingCSVReader) void;
    };

    // Column Access
    pub fn column(self: *const DataFrame, name: []const u8) ?Series;
    pub fn columnIndex(self: *const DataFrame, name: []const u8) ?usize;

    // Selection
    pub fn select(self: *const DataFrame, names: []const []const u8) !DataFrame;
    pub fn drop(self: *const DataFrame, names: []const []const u8) !DataFrame;

    // NEW: Slice/view without copying
    pub fn slice(
        self: *const DataFrame,
        start_row: u32,
        end_row: u32,
    ) DataFrameView;

    // Filtering
    pub fn filter(
        self: *const DataFrame,
        predicate: fn (row: RowRef) bool,
    ) !DataFrame;

    // Column Operations
    pub fn withColumn(
        self: *const DataFrame,
        name: []const u8,
        series: Series,
    ) !DataFrame;

    // NEW: Type coercion
    pub fn castColumn(
        self: *const DataFrame,
        col_name: []const u8,
        new_type: ValueType,
    ) !DataFrame;

    // NEW: Column reordering
    pub fn reorderColumns(
        self: *const DataFrame,
        new_order: []const []const u8,
    ) !DataFrame;

    // Aggregation
    pub fn sum(self: *const DataFrame, colName: []const u8) !?f64;
    pub fn mean(self: *const DataFrame, colName: []const u8) !?f64;
    pub fn min(self: *const DataFrame, colName: []const u8) !?f64;
    pub fn max(self: *const DataFrame, colName: []const u8) !?f64;
    pub fn count(self: *const DataFrame, colName: []const u8) !u32;

    // NEW: Group by operations
    pub fn groupBy(
        self: *const DataFrame,
        columns: []const []const u8,
    ) !GroupedDataFrame;

    // NEW: Join operations
    pub fn innerJoin(
        self: *const DataFrame,
        other: *const DataFrame,
        on: []const u8,
    ) !DataFrame;

    pub fn leftJoin(
        self: *const DataFrame,
        other: *const DataFrame,
        on: []const u8,
    ) !DataFrame;

    // NEW: Sort operations
    pub fn sortBy(
        self: *const DataFrame,
        col_name: []const u8,
        ascending: bool,
    ) !DataFrame;

    // NEW: Null handling
    pub fn fillNull(
        self: *const DataFrame,
        col_name: []const u8,
        value: Value,
    ) !DataFrame;

    pub fn dropNull(
        self: *const DataFrame,
        col_name: []const u8,
    ) !DataFrame;

    // CSV Export
    pub fn toCSV(
        self: *const DataFrame,
        allocator: *std.mem.Allocator,
        opts: CSVOptions,
    ) ![]u8;

    // Memory Management
    pub fn free(self: DataFrame) void;
};
```

### 4.4 JavaScript/TypeScript API

```typescript
// Import via ESM
import { DataFrame, Series, CSVOptions } from "rozes";

interface DataFrame {
    readonly columns: string[];
    readonly rowCount: number;

    // Column access
    column(name: string): Series | null;

    // Selection
    select(names: string[]): Promise<DataFrame>;
    drop(names: string[]): Promise<DataFrame>;
    slice(startRow: number, endRow: number): DataFrameView;

    // Filtering
    filter(predicate: (row: RowRef) => boolean): Promise<DataFrame>;

    // Column operations
    withColumn(name: string, values: Series): Promise<DataFrame>;
    castColumn(colName: string, newType: ValueType): Promise<DataFrame>;
    reorderColumns(newOrder: string[]): Promise<DataFrame>;

    // Aggregation
    sum(colName: string): Promise<number | null>;
    mean(colName: string): Promise<number | null>;
    min(colName: string): Promise<number | null>;
    max(colName: string): Promise<number | null>;
    count(colName: string): Promise<number>;

    // Group by
    groupBy(columns: string[]): Promise<GroupedDataFrame>;

    // Join
    innerJoin(other: DataFrame, on: string): Promise<DataFrame>;
    leftJoin(other: DataFrame, on: string): Promise<DataFrame>;

    // Sort
    sortBy(colName: string, ascending?: boolean): Promise<DataFrame>;

    // Null handling
    fillNull(colName: string, value: any): Promise<DataFrame>;
    dropNull(colName: string): Promise<DataFrame>;

    // CSV Export
    toCSV(options?: CSVOptions): Promise<string>;
}

interface Series {
    readonly name: string;
    readonly type: ValueType;
    readonly length: number;

    // Zero-copy typed array access
    asFloat64Array(): Float64Array | null;
    asInt64Array(): BigInt64Array | null;
    asStringArray(): string[] | null;
    asBoolArray(): Uint8Array | null;
}

interface CSVOptions {
    delimiter?: string;
    hasHeaders?: boolean;
    skipBlankLines?: boolean;
    trimWhitespace?: boolean;
    quoteChar?: string;
    escapeChar?: string;
    inferTypes?: boolean;
    detectBOM?: boolean;
    stripBOM?: boolean;
    parseMode?: 'strict' | 'lenient' | 'bestEffort';
    memoryLimit?: number;
    nullValues?: string[];
}

class DataFrame {
    // CSV Import
    static fromCSV(textOrBlob: string | Blob, options?: CSVOptions): Promise<DataFrame>;

    // Streaming import
    static async *streamCSV(blob: Blob, options?: CSVOptions, chunkSize?: number): AsyncGenerator<DataFrame>;

    // From JSON
    static fromJSON(obj: Record<string, any[]>): Promise<DataFrame>;
}
```

---

## 5. CSV Parsing Specification

### 5.1 RFC 4180 Compliance

Rozes **MUST** support all RFC 4180 requirements:

✅ **Quoted Fields**: Fields enclosed in double quotes
✅ **Embedded Commas**: Commas inside quoted fields are data, not delimiters
✅ **Embedded Newlines**: Newlines inside quoted fields are preserved
✅ **Quote Escaping**: Double-quote escape (`""` → `"`)
✅ **Line Endings**: Support CRLF (`\r\n`), LF (`\n`), and CR (`\r`)
✅ **Header Row**: Optional header row (controlled by `hasHeaders` option)
✅ **Empty Fields**: Empty values represented as null or empty string
✅ **Custom Delimiters**: Support `,`, `;`, `\t`, `|` and others

### 5.2 Advanced CSV Features

#### BOM (Byte Order Mark) Handling

**UTF-8 BOM**: `EF BB BF`
**UTF-16LE BOM**: `FF FE`
**UTF-16BE BOM**: `FE FF`

**Behavior**:
- If `detectBOM=true`: Auto-detect encoding from BOM
- If `stripBOM=true`: Remove BOM from output
- Transcode UTF-16 to UTF-8 internally

#### Type Inference

When `inferTypes=true`, apply the following rules in order:

1. **Int64**: All numeric, no decimal point, no scientific notation
2. **Float64**: Numeric with decimal or scientific notation (`1.23`, `1e10`)
3. **Bool**: `true`, `false`, `TRUE`, `FALSE` (case-insensitive)
4. **String**: Default fallback

#### Null Value Detection

Fields matching `nullValues` array are converted to null:
- Default: `["NULL", "NA", ""]`
- Case-sensitive matching
- Empty strings always null (unless in `nullValues`)

#### Error Recovery

**Parse Modes**:

| Mode | Behavior on Error | Use Case |
|------|-------------------|----------|
| `Strict` | Fail immediately, return error | Production data validation |
| `Lenient` | Skip bad row, log error | Data exploration |
| `BestEffort` | Attempt recovery, fill nulls | Messy real-world data |

### 5.3 Performance Requirements

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Throughput** | Parse ≥1M rows × 10 cols in <3s | Chrome 90+, modern laptop |
| **Memory** | Peak memory <2× CSV size (numeric) | Via browser DevTools |
| **Memory** | Peak memory <3× CSV size (string-heavy) | Via browser DevTools |
| **Export** | Export 1M rows in <1s | Same as import |
| **Streaming** | Handle 100MB+ without UI freeze | Using Web Worker |

### 5.4 CSV Parser Architecture

**One-Pass Parsing**:
- Single pass through CSV buffer
- Minimize allocations
- Avoid creating intermediate JS objects

**Columnar Storage**:
- Parse directly into columnar buffers
- Numeric columns: contiguous `[]f64` or `[]i64`
- String columns: offset table + UTF-8 buffer

**Memory Layout** (String Column):
```
offsets: [u32; rowCount]  // Start offset of each string
buffer:  [u8; totalBytes] // Contiguous UTF-8 data
```

---

## 6. Architecture & Build System

### 6.1 Project Structure

```
rozes/
├── src/
│   ├── core/              # Core DataFrame engine
│   │   ├── types.zig      # ValueType, ColumnDesc, DataFrame, Series
│   │   ├── allocator.zig  # Memory management utilities
│   │   ├── series.zig     # Series implementation
│   │   ├── dataframe.zig  # DataFrame implementation
│   │   └── operations.zig # Filter, select, aggregation
│   ├── csv/               # CSV parsing and export
│   │   ├── parser.zig     # CSV parser (RFC 4180 compliant)
│   │   ├── export.zig     # CSV export/serialization
│   │   ├── types.zig      # CSVOptions, ParseState
│   │   ├── inference.zig  # Type inference
│   │   └── bom.zig        # BOM detection/handling
│   ├── bindings/          # Platform bindings
│   │   ├── wasm/          # WebAssembly glue code
│   │   │   ├── bridge.zig # JS ↔ Wasm memory bridge
│   │   │   └── exports.zig # Exported Wasm functions
│   │   └── node/          # Node.js N-API addon (optional)
│   ├── test/              # Test suites
│   │   ├── unit/          # Zig unit tests
│   │   ├── integration/   # Integration tests
│   │   ├── browser/       # Browser test runner
│   │   └── benchmark/     # Performance benchmarks
│   └── rozes.zig          # Main API surface
├── js/                    # JavaScript wrapper
│   ├── index.js           # ESM interface
│   ├── loader.js          # Wasm loader & memory management
│   ├── types.d.ts         # TypeScript definitions
│   └── worker.js          # Web Worker support
├── testdata/              # Test fixtures
│   ├── csv/               # CSV test files
│   │   ├── rfc4180/       # RFC 4180 compliance (10 tests)
│   │   ├── edge_cases/    # Edge cases (7 tests)
│   │   ├── large/         # Large files (100K, 1M rows)
│   │   └── malformed/     # Invalid CSVs
│   └── external/          # External test suites
│       ├── csv-spectrum/  # 15 official edge case tests
│       ├── PapaParse/     # 100+ Papa Parse tests
│       └── csv-parsers-comparison/ # 50+ uniVocity tests
├── scripts/               # Build and test scripts
│   ├── build_wasm.sh
│   ├── download_conformance_tests.sh
│   └── benchmark.sh
└── build.zig              # Build configuration
```

### 6.2 Build Targets

**Browser/Wasm**:
```bash
zig build -Dtarget=wasm32-unknown-unknown -Doptimize=ReleaseSmall
```
- Output: `rozes.wasm` (target: <300KB compressed)
- Features: Full DataFrame + CSV support
- Limitations: No native file I/O

**Node.js Native Addon** (optional):
```bash
zig build -Dtarget=native -Doptimize=ReleaseFast
```
- Output: `rozes.node` (N-API addon)
- Features: Full support + native file I/O
- Performance: 2-3× faster than Wasm

**Node.js Wasm** (fallback):
- Same as browser Wasm
- Use when native addon unavailable

### 6.3 Memory Management

**Arena Allocator Pattern**:
```zig
pub fn fromCSVBuffer(
    allocator: Allocator,
    buffer: []const u8,
    opts: CSVOptions,
) !DataFrame {
    const arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer {
        arena.deinit();
        allocator.destroy(arena);
    }

    const arena_alloc = arena.allocator();
    // All DataFrame allocations use arena_alloc
    // Single df.free() frees everything

    return dataframe_with_arena;
}
```

**TypedArray Bridge** (Zero-Copy):
```zig
pub fn columnAsFloat64(df: *const DataFrame, name: []const u8) ?[]f64 {
    const series = df.column(name) orelse return null;
    const data = series.asFloat64() orelse return null;

    // Return pointer to Wasm memory
    // JS creates Float64Array view directly
    return data;
}
```

### 6.4 Performance Optimization

**SIMD Targets**:
- Numeric filters: `df.filter(|row| row.age > 30)`
- Aggregations: `sum`, `mean`, `min`, `max`
- Type inference: parallel scanning
- CSV delimiter detection

**Expected Speedups**:
- Sum/mean: 4-8× faster (AVX2)
- Filter: 3-5× faster
- Delimiter scan: 2-4× faster

**Web Worker Support**:
```javascript
// Offload CSV parsing to worker
const worker = new Worker('rozes-worker.js');
worker.postMessage({ csv: csvText });
worker.onmessage = (e) => {
    const df = e.data.dataframe;
};
```

---

## 7. Testing & Conformance

### 7.1 Test Suite Overview

**Total Tests**: 182+ test cases

| Category | Count | Location | Purpose |
|----------|-------|----------|---------|
| Custom RFC 4180 | 10 | `testdata/csv/rfc4180/` | Core RFC compliance |
| Custom Edge Cases | 7 | `testdata/csv/edge_cases/` | Unusual but valid scenarios |
| csv-spectrum | 15 | `testdata/external/csv-spectrum/` | Official edge cases |
| Papa Parse | 100+ | `testdata/external/PapaParse/tests/` | Real-world scenarios |
| uniVocity | 50+ | `testdata/external/csv-parsers-comparison/` | Problematic CSVs |

### 7.2 Custom Test Cases

#### RFC 4180 Compliance Tests

1. **01_simple.csv**: Basic CSV with headers, no special chars
2. **02_quoted_fields.csv**: Fields enclosed in quotes
3. **03_embedded_commas.csv**: Commas inside quoted fields
4. **04_embedded_newlines.csv**: Newlines inside quoted fields
5. **05_escaped_quotes.csv**: Double-quote escape (`""`)
6. **06_crlf_endings.csv**: CRLF line endings
7. **07_empty_fields.csv**: Empty/null values
8. **08_no_header.csv**: CSV without header row
9. **09_trailing_comma.csv**: Trailing comma (empty column)
10. **10_unicode_content.csv**: UTF-8 (emoji, CJK, Arabic)

#### Edge Case Tests

1. **01_single_column.csv**: Only one column
2. **02_single_row.csv**: Header + 1 data row
3. **03_blank_lines.csv**: Blank lines to skip
4. **04_mixed_types.csv**: Int, float, bool, string
5. **05_special_characters.csv**: Special symbols, unicode math
6. **06_very_long_field.csv**: Fields >500 characters
7. **07_numbers_as_strings.csv**: Preserve leading zeros (zip codes)

### 7.3 External Test Suites

#### csv-spectrum (15 tests)
- **Source**: https://github.com/maxogden/csv-spectrum
- **License**: MIT
- **Download**: `./scripts/download_conformance_tests.sh`
- **Expected**: JSON files with expected parse results
- **Coverage**: Empty fields, quotes, newlines, UTF-8, JSON in CSV

#### Papa Parse (100+ tests)
- **Source**: https://github.com/mholt/PapaParse
- **License**: MIT
- **Location**: `testdata/external/PapaParse/tests/`
- **Coverage**: Streaming, encoding, type detection, error handling

#### uniVocity (50+ tests)
- **Source**: https://github.com/uniVocity/csv-parsers-comparison
- **License**: Apache 2.0
- **Location**: `testdata/external/csv-parsers-comparison/src/main/resources/`
- **Coverage**: Malformed CSVs, unusual delimiters, encoding issues

### 7.4 Browser Test Suite

**Interactive Test Runner**: `src/test/browser/index.html`

**Features**:
- 17 custom tests (10 RFC 4180 + 7 edge cases)
- Real-time execution with progress bar
- Performance benchmarks (1K, 10K, 100K rows)
- Filter results (all, passed, failed)
- Console output with color-coded logging

**Running**:
```bash
# Build WASM
zig build -Dtarget=wasm32-freestanding

# Serve tests
python3 -m http.server 8080

# Open browser
open http://localhost:8080/src/test/browser/
```

### 7.5 Conformance Success Criteria

**RFC 4180 Compliance**:
- ✅ 100% pass rate on custom RFC 4180 tests (10/10)
- ✅ 100% pass rate on custom edge cases (7/7)
- ✅ 100% pass rate on csv-spectrum (15/15)

**Performance**:
- ✅ Parse 100K rows in <1 second (browser)
- ✅ Parse 1M rows in <3 seconds (browser)
- ✅ Peak memory <2× CSV size (numeric data)
- ✅ No memory leaks (1000 parse/free cycles)

**Cross-Browser**:
- ✅ Pass all tests on Chrome 90+, Firefox 88+, Safari 14+, Edge 90+
- ✅ No crashes or hangs on large datasets
- ✅ Consistent results across browsers

---

## 8. Performance Targets

### 8.1 CSV Parsing

| Dataset | Size | Rows | Cols | Target (Browser) | Target (Node Native) |
|---------|------|------|------|------------------|----------------------|
| Small | 100KB | 1K | 10 | <50ms | <20ms |
| Medium | 10MB | 100K | 10 | <1s | <400ms |
| Large | 100MB | 1M | 10 | <3s | <1s |
| Wide | 50MB | 10K | 100 | <1s | <400ms |
| String-Heavy | 50MB | 100K | 5 | <1s | <400ms |

**Comparison Targets** (beat existing JS libraries):
- Papa Parse: 5-10s for 1M rows → **Target: <3s** (2-3× faster)
- csv-parser: 8-12s for 1M rows → **Target: <3s** (3-4× faster)

### 8.2 DataFrame Operations

| Operation | Dataset | Target | Notes |
|-----------|---------|--------|-------|
| Filter (numeric) | 1M rows | <100ms | SIMD optimized |
| Select (columns) | 1M rows | O(1) | Zero-copy view |
| Sum/Mean | 1M values | <20ms | SIMD aggregation |
| GroupBy | 100K rows | <500ms | Hash-based grouping |
| Join (inner) | 100K × 100K | <2s | Hash join |
| Sort | 1M rows | <500ms | Quicksort/Radix |

### 8.3 Memory Usage

**Numeric Columns**:
- Target: <1.5× raw data size
- Overhead: Column metadata, null bitmap

**String Columns**:
- Target: <2× raw data size
- Layout: Offset table + UTF-8 buffer

**Mixed DataFrame**:
- Target: <2.5× raw CSV size
- Depends on type distribution

### 8.4 Wasm Binary Size

- **Uncompressed**: <500KB
- **Compressed (gzip)**: <300KB
- **Load Time**: <100ms (modern browser)

---

## 9. Roadmap & Milestones

### Milestone 0.1.0 (MVP) - Target: 4 weeks

**Deliverables**:
- ✅ Project scaffolding, build system (Wasm + Node)
- ✅ Series + DataFrame creation from JS arrays/objects
- ✅ CSV import from buffer (float64/int64 only)
- ✅ JS wrapper with `DataFrame.fromCSV(...)`
- ✅ Basic CSV parser (RFC 4180 compliant)
- ✅ Unit tests for CSV parsing
- ✅ DataFrame operations: select, filter, sum, mean
- ✅ Browser test suite (10 RFC 4180 tests)
- ✅ Initial benchmarks vs Papa Parse

**Success Criteria**:
- Parse 100K rows in <1s
- Pass 10/10 RFC 4180 tests
- Zero memory leaks

### Milestone 0.2.0 - Target: 6 weeks

**Deliverables**:
- ✅ String and boolean column types
- ✅ CSV export support
- ✅ Type inference (`inferTypes` option)
- ✅ DataFrame filter and column add/drop
- ✅ BOM detection and handling
- ✅ Error recovery modes (strict, lenient)
- ✅ Browser demo page (CSV import + filtering)
- ✅ Edge case tests (7 tests)
- ✅ External test suite integration (csv-spectrum)

**Success Criteria**:
- Parse 1M rows in <3s
- Pass 27/27 conformance tests (10 + 7 + 10 csv-spectrum)
- Memory <2× CSV size

### Milestone 0.3.0 - Target: 10 weeks

**Deliverables**:
- ✅ Aggregation (groupBy, sum/mean by group)
- ✅ Joins (inner, left)
- ✅ Sort operations
- ✅ Null handling (fillNull, dropNull)
- ✅ SIMD optimizations for filters/aggregations
- ✅ Web Worker support for browser
- ✅ Streaming CSV parser
- ✅ npm package published
- ✅ Documentation and examples

**Success Criteria**:
- Parse 1M rows in <2s (with SIMD)
- GroupBy 100K rows in <500ms
- Pass 100+ external tests (Papa Parse)

### Milestone 1.0.0 (Full Release) - Target: 14 weeks

**Deliverables**:
- ✅ Polished API (finalize breaking changes)
- ✅ Benchmarking report vs existing libraries
- ✅ CLI benchmark harness
- ✅ Node native binding (N-API addon)
- ✅ Streaming CSV import/export
- ✅ Memory usage profiling and optimization
- ✅ Comprehensive documentation
- ✅ Example projects (data analysis, ETL)
- ✅ Community readiness (CONTRIBUTING.md, CODE_OF_CONDUCT.md)

**Success Criteria**:
- Parse 1M rows in <2s (browser), <800ms (Node native)
- Pass 182+ conformance tests (100% pass rate)
- Memory <2× CSV size consistently
- npm downloads >1000 in first month
- GitHub stars >100

### Future Roadmap (v2.0+)

- Binary serialization format (10-100× faster reload)
- Apache Arrow interoperability
- Advanced time-series operations (rolling windows, resampling)
- Multi-threaded operations (worker pool)
- Lazy evaluation / query optimization
- Python bindings (PyO3)
- Rust/Wasm interop (Polars integration?)

---

## 10. Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| **Browser/Wasm memory/GC constraints** | High | Medium | Use Web Worker, chunked parsing, careful memory layout, benchmark early |
| **JS ↔ Wasm data transfer overhead** | High | Medium | Minimize boundary crossings, expose TypedArray buffers, batch operations |
| **CSV edge cases cause bugs** | Medium | High | Build full test suite (RFC 4180 + external), fuzzing, integrate 182+ tests |
| **Feature creep delays release** | High | Medium | Focus on CSV + core ops for MVP, defer joins/groupBy to 0.3.0 |
| **Competition from Polars-Wasm** | Medium | High | Benchmark rigorously, market via performance reports, differentiate (Zig, browser-first) |
| **SIMD not supported on all browsers** | Low | Low | Detect SIMD at runtime, provide scalar fallback |
| **Memory leaks in Wasm** | High | Low | Extensive leak testing, arena allocator pattern, automated checks |
| **Type inference errors** | Medium | Medium | Provide `inferTypes=false` option, allow manual schema specification |

---

## 11. References

### Specifications

- [RFC 4180 - CSV Format](https://www.rfc-editor.org/rfc/rfc4180) - Official CSV specification
- [ECMA-404 JSON](https://www.ecma-international.org/publications-and-standards/standards/ecma-404/) - For JSON export

### Benchmarks

- [LeanyLabs CSV Benchmarks](https://leanylabs.com/blog/js-csv-parsers-benchmarks/) - JS CSV parser comparison
- [OneSchema CSV Comparison](https://www.oneschema.co/csv-parsing) - Performance analysis

### Test Suites

- [csv-spectrum](https://github.com/maxogden/csv-spectrum) - Official CSV edge case tests (MIT)
- [Papa Parse](https://github.com/mholt/PapaParse) - Popular JS CSV parser (MIT)
- [uniVocity](https://github.com/uniVocity/csv-parsers-comparison) - CSV parser comparison (Apache 2.0)

### Zig Resources

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- [Zig Build System](https://ziglang.org/learn/build-system/)
- [Zig WebAssembly](https://ziglang.org/learn/overview/#webassembly-support)

### WebAssembly

- [MDN WebAssembly](https://developer.mozilla.org/en-US/docs/WebAssembly)
- [WebAssembly Specification](https://webassembly.github.io/spec/)

### Coding Standards

- [Tiger Style Guide](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md) - Safety-first Zig patterns

---

**RFC Version**: 2.0
**Last Updated**: 2025-10-27
**Status**: Active Development
**Next Review**: Upon completion of Milestone 0.1.0
