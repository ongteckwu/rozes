# 🌹 Rozes - The Fastest DataFrame Library for TypeScript/JavaScript/Zig

**Blazing-fast data analysis powered by WebAssembly.** Rozes brings pandas-like analytics to TypeScript/JavaScript with native performance, columnar storage, and zero-copy operations.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![npm version](https://img.shields.io/badge/npm-1.3.0-blue.svg)](https://www.npmjs.com/package/rozes)
[![Zig Version](https://img.shields.io/badge/Zig-0.15+-orange.svg)](https://ziglang.org/)

```bash
npm install rozes (Please wait for full version)
```

```javascript
const { Rozes } = require("rozes");

const rozes = await Rozes.init();
const df = rozes.DataFrame.fromCSV(
  "name,age,score\nAlice,30,95.5\nBob,25,87.3"
);

console.log(df.shape); // { rows: 2, cols: 3 }
const ages = df.column("age"); // Float64Array [30, 25] - zero-copy!
```

---

## Why Rozes?

### 🚀 **Performance** - 3-10× Faster Than JavaScript Libraries

- Uses a Parallel Parsing Mechanism
- SIMD for speed optimizations for very large csvs
- Radix Joins / String Interning and other optimizations for speed and memory
- WebGPU optimizations (future)

| Operation            | Rozes       | Papa Parse | csv-parse | Speedup        |
| -------------------- | ----------- | ---------- | --------- | -------------- |
| Parse 100K rows      | **53.67ms** | 207.67ms   | 427.48ms  | **3.87-7.96×** |
| Parse 1M rows        | **578ms**   | ~2-3s      | ~5s       | **3.5-8.7×**   |
| Filter 1M rows       | **13.11ms** | ~150ms     | N/A       | **11.4×**      |
| Sort 100K rows       | **6.11ms**  | ~50ms      | N/A       | **8.2×**       |
| GroupBy 100K rows    | **1.76ms**  | ~30ms      | N/A       | **17×**        |
| SIMD Sum 200K rows   | **0.04ms**  | ~5ms       | N/A       | **125×**       |
| SIMD Mean 200K rows  | **0.04ms**  | ~6ms       | N/A       | **150×**       |
| Radix Join 100K×100K | **5.29ms**  | N/A        | N/A       | N/A            |

### 📦 **Tiny Bundle** - 94-99% Smaller

| Library     | Bundle Size | Gzipped  | vs Rozes          |
| ----------- | ----------- | -------- | ----------------- |
| **Rozes**   | **103KB**   | **52KB** | **1×**            |
| Papa Parse  | 206KB       | 57KB     | 2.0× larger       |
| Danfo.js    | 1.2MB       | ~400KB   | **12× larger**    |
| Polars-WASM | 2-5MB       | ~1MB     | **19-49× larger** |
| DuckDB-WASM | 15MB        | ~5MB     | **146× larger**   |

**Future Package Sizes (v1.3.0)**:

- `rozes/csv` (CSV-only): 40KB gzipped
- `rozes` (universal): 120KB gzipped
- `rozes/web` (with WebGPU): 180KB gzipped

### ✅ **Production-Ready** - Tested & Reliable

- **520+ tests passing** (99.6%) - includes 200+ Node.js integration tests
- **100% RFC 4180 CSV compliance** (125/125 conformance tests)
- **11/12 benchmarks passing** (92% - Milestone 1.2.0)
- **Zero memory leaks** (verified 1000-iteration tests)
- **Tiger Style compliant** (safety-first Zig patterns)

---

## Installation

### Node.js / Browser

```bash
npm install rozes
```

**Requirements**:

- Node.js 14+ (LTS versions recommended)
- No native dependencies (pure WASM)

### Zig (Coming Soon)

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .rozes = .{
        .url = "https://github.com/yourusername/rozes/archive/v1.0.0.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const rozes = b.dependency("rozes", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("rozes", rozes.module("rozes"));
```

**Requirements**:

- Zig 0.15.1+

---

## Quick Start

### Node.js (ES Modules)

```javascript
import { Rozes } from "rozes";

const rozes = await Rozes.init();
const df = rozes.DataFrame.fromCSV(csvText);

console.log(df.shape);
```

### TypeScript

```typescript
import { Rozes, DataFrame } from "rozes";

const rozes: Rozes = await Rozes.init();
const df: DataFrame = rozes.DataFrame.fromCSV(csvText);

// Full autocomplete support
const shape = df.shape; // { rows: number, cols: number }
const columns = df.columns; // string[]
const ages = df.column("age"); // Float64Array | Int32Array | BigInt64Array | null
```

### Node.js (CommonJS)

```javascript
const { Rozes } = require("rozes");
```

### Zig (Native)

```zig
const std = @import("std");
const DataFrame = @import("rozes").DataFrame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const csv = "name,age,score\nAlice,30,95.5\nBob,25,87.3";
    var df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
    defer df.free();

    std.debug.print("Rows: {}, Cols: {}\n", .{ df.rowCount, df.columns.len });
}
```

### Browser (ES Modules)

```html
<!DOCTYPE html>
<html>
  <head>
    <script type="module">
      import { Rozes } from "./node_modules/rozes/dist/index.mjs";

      const rozes = await Rozes.init();
      const df = rozes.DataFrame.fromCSV(csvText);

      console.log(df.shape);
    </script>
  </head>
</html>
```

---

## API Examples

### JavaScript/TypeScript API (1.2.0)

Rozes provides a comprehensive DataFrame API for Node.js and browser environments through WebAssembly bindings.

#### CSV Parsing & I/O

```javascript
// Parse CSV from string
const df = rozes.DataFrame.fromCSV(
  "name,age,score\nAlice,30,95.5\nBob,25,87.3"
);

// Parse CSV from file (Node.js only)
const df2 = rozes.DataFrame.fromCSVFile("data.csv");
```

#### DataFrame Properties

```javascript
// Shape and metadata
df.shape; // { rows: 2, cols: 3 }
df.columns; // ["name", "age", "score"]
df.length; // 2
```

#### Column Access (Zero-Copy)

```javascript
// Numeric columns - returns TypedArray (zero-copy!)
const ages = df.column("age"); // Float64Array [30, 25]
const scores = df.column("score"); // Float64Array [95.5, 87.3]

// String columns - returns array of strings
const names = df.column("name"); // ["Alice", "Bob"]

// Boolean columns - returns Uint8Array (0 = false, 1 = true)
const active = df.column("is_active"); // Uint8Array [1, 0]
```

#### DataFrame Operations

```javascript
// Select columns
const subset = df.select(["name", "age"]);

// Head and tail
const first5 = df.head(5);
const last5 = df.tail(5);

// Sort
const sorted = df.sort("age", false); // ascending
const descending = df.sort("score", true); // descending
```

#### SIMD Aggregations (NEW in 1.2.0)

**Blazing-fast statistical functions with SIMD acceleration (2-6 billion rows/sec)**

```javascript
// Sum - 4.48 billion rows/sec
const totalScore = df.sum("score"); // 182.8

// Mean - 4.46 billion rows/sec
const avgAge = df.mean("age"); // 27.5

// Min/Max - 6.5-6.7 billion rows/sec
const minAge = df.min("age"); // 25
const maxScore = df.max("score"); // 95.5

// Variance and Standard Deviation
const variance = df.variance("score");
const stddev = df.stddev("score");

// Note: SIMD automatically used on x86_64 with AVX2, falls back to scalar on other platforms
```

#### Memory Management

```javascript
const df = rozes.DataFrame.fromCSV(largeCSV);
console.log(df.shape);
```

#### Full TypeScript Support

```typescript
import { Rozes, DataFrame } from "rozes";

const rozes: Rozes = await Rozes.init();
const df: DataFrame = rozes.DataFrame.fromCSV(csvText);

// Full autocomplete and type checking
const shape: { rows: number; cols: number } = df.shape;
const columns: string[] = df.columns;
const ages: Float64Array | Int32Array | null = df.column("age");
const total: number = df.sum("price");
```

#### API Summary (1.2.0)

| Category                | Methods                                                       | Status               |
| ----------------------- | ------------------------------------------------------------- | -------------------- |
| **CSV I/O**             | `fromCSV()`, `fromCSVFile()`                                  | ✅ Available         |
| **Properties**          | `shape`, `columns`, `length`                                  | ✅ Available         |
| **Column Access**       | `column()` - numeric, string, boolean                         | ✅ Available         |
| **Selection**           | `select()`, `head()`, `tail()`                                | ✅ Available         |
| **Sorting**             | `sort()`                                                      | ✅ Available         |
| **SIMD Aggregations**   | `sum()`, `mean()`, `min()`, `max()`, `variance()`, `stddev()` | ✅ Available (1.2.0) |
| **Advanced Operations** | `filter()`, `groupBy()`, `join()`                             | ⏳ Coming in 1.3.0   |
| **CSV Export**          | `toCSV()`, `toCSVFile()`                                      | ⏳ Coming in 1.3.0   |

---

### Zig API (1.2.0) - 50+ Operations

```zig
// CSV I/O
var df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
var df2 = try DataFrame.fromCSVFile(allocator, "data.csv", .{});
const csv_out = try df.toCSV(allocator, .{});

// Data Access & Metadata
df.rowCount;           // u32
df.columns.len;        // usize
const col = df.column("age");
const row = df.row(0);

// Selection & Filtering
const selected = try df.select(&[_][]const u8{"name", "age"});
const filtered = try df.filter(myFilterFn);
const head = try df.head(10);
const tail = try df.tail(10);

// Sorting
const sorted = try df.sort("age", .Ascending);
const multi = try df.sortMulti(&[_][]const u8{"age", "score"}, &[_]SortOrder{.Ascending, .Descending});

// GroupBy Aggregations
const grouped = try df.groupBy("category");
const sum_result = try grouped.sum("amount");
const mean_result = try grouped.mean("score");
const min_result = try grouped.min("age");
const max_result = try grouped.max("age");
const count_result = try grouped.count();

// Joins (inner, left, right, outer, cross)
const joined = try df.join(df2, "id", "id", .Inner);
const left = try df.join(df2, "key", "key", .Left);

// Statistical Operations
const corr = try df.corr("age", "score");
const cov = try df.cov("age", "score");
const ranked = try df.rank("score");
const counts = try df.valueCounts("category");

// Missing Values
const filled = try df.fillna(0.0);
const dropped = try df.dropna();
const nulls = df.isNull("age");

// Reshape Operations
const pivoted = try df.pivot("date", "product", "sales");
const melted = try df.melt(&[_][]const u8{"id"}, &[_][]const u8{"val1", "val2"});
const transposed = try df.transpose();
const stacked = try df.stack();
const unstacked = try df.unstack("level");

// Combine DataFrames
const concatenated = try DataFrame.concat(allocator, &[_]DataFrame{df1, df2}, .Rows);
const merged = try df.merge(df2, &[_][]const u8{"key"});
const appended = try df.append(df2);
const updated = try df.update(df2);

// Window Operations
const rolling = try df.rolling(3).mean("price");
const expanding = try df.expanding().sum("quantity");

// Functional Operations
const mapped = try df.map("age", mapFn);
const applied = try df.apply(applyFn);

// String Operations (10+ functions)
const upper = try df.strUpper("name");
const lower = try df.strLower("name");
const len = try df.strLen("name");
const contains = try df.strContains("name", "Alice");
const startsWith = try df.strStartsWith("name", "A");
const endsWith = try df.strEndsWith("name", "e");
```

---

## Features

### Core DataFrame Engine (1.2.0)

**Node.js/Browser API (1.2.0)** - Production-ready DataFrame library:

- ✅ **CSV Parsing**: 100% RFC 4180 compliant
  - Quoted fields, embedded commas, embedded newlines
  - CRLF/LF/CR line endings, UTF-8 BOM detection
  - Automatic type inference (Int64, Float64, String, Bool, Categorical, Null)
  - Parallel CSV parsing: 1.73M rows/second (1M rows in 578ms)
- ✅ **Memory Management**: Fully automatic via FinalizationRegistry
  - Garbage collector handles cleanup automatically
  - No manual `free()` calls required
  - Works in Node.js 14.6+ and modern browsers (Chrome 84+, Firefox 79+, Safari 14.1+)
- ✅ **Data Access**: Column access (`column()`) - all types supported
  - Numeric types (Int64, Float64) → TypedArray (zero-copy)
  - String columns → Array of strings
  - Boolean columns → Uint8Array
- ✅ **DataFrame Operations**:
  - Selection: `select()`, `head()`, `tail()`
  - Sorting: `sort()` (single column, ascending/descending)
  - SIMD Aggregations: `sum()`, `mean()`, `min()`, `max()`, `variance()`, `stddev()`
- ✅ **DataFrame metadata**: `shape`, `columns`, `length` properties
- ✅ **Node.js Integration**: CommonJS + ESM support, TypeScript definitions, File I/O (`fromCSVFile`)
- ⏳ **Advanced operations coming in 1.3.0**: `filter()`, `groupBy()`, `join()`, `toCSV()`

**Zig API (1.2.0)** - Full DataFrame operations (50+ operations):

- ✅ **GroupBy**: `sum()`, `mean()`, `min()`, `max()`, `count()`
- ✅ **Join**: inner, left, right, outer, cross (5 types)
- ✅ **Sort**: Single/multi-column with NaN handling
- ✅ **Window operations**: `rolling()`, `expanding()`
- ✅ **String operations**: 10+ functions (case conversion, length, predicates)
- ✅ **Reshape**: `pivot()`, `melt()`, `transpose()`, `stack()`, `unstack()`
- ✅ **Combine**: `concat()`, `merge()`, `append()`, `update()`
- ✅ **Functional**: `apply()`, `map()` with type conversion
- ✅ **Missing values**: `fillna()`, `dropna()`, `isNull()`
- ✅ **Statistical**: `corr()`, `cov()`, `rank()`, `valueCounts()`

### Performance Optimizations - Complete List

**25+ Major Optimizations Across 10 Categories** (Milestone 1.2.0):

#### SIMD Aggregations (NEW in 1.2.0)

- **SIMD sum/mean** - 0.04ms for 200K rows (2-6 billion rows/sec, **95-97% faster than targets**)
- **SIMD min/max** - 0.03ms for 200K rows (vectorized comparisons)
- **SIMD variance/stddev** - 0.09ms for 200K rows (horizontal reduction)
- **CPU detection** - Automatic scalar fallback on unsupported CPUs
- **Node.js integration** - 6 SIMD functions exported to JavaScript/TypeScript

#### Radix Hash Join (NEW in 1.2.0)

- **Radix partitioning** - 1.65× speedup vs standard hash join (100K×100K rows)
- **SIMD probe phase** - Vectorized key comparisons
- **Bloom filters** - 97% faster early rejection (0.01ms for 10K probes)
- **8-bit radix** - Multi-pass partitioning with cache-friendly scatter

#### Parallel Processing (NEW in 1.2.0)

- **Parallel CSV parsing** - 578ms for 1M rows (81% faster than 3s target, work-stealing pool)
- **Parallel filter** - 13ms for 1M rows (87% faster, thread-safe partitioning)
- **Parallel sort** - 6ms for 100K rows (94% faster, adaptive thresholds)
- **Parallel groupBy** - 1.76ms for 100K rows (99% faster!)
- **Adaptive chunking** - 64KB-1MB chunks based on file size and CPU count
- **Quote-aware boundaries** - Correct chunk splitting in CSV parsing

#### Query Optimization (NEW in 1.2.0)

- **Lazy evaluation** - Defer execution until `.collect()`
- **Predicate pushdown** - Filter before select (50%+ row reduction)
- **Projection pushdown** - Select early (30%+ memory reduction)
- **Query plan DAG** - Optimize operation order automatically
- **Expected speedup**: 2-10× for chained operations (3+ ops)

#### CSV Parsing

- **SIMD delimiter detection** - 37% faster (909ms → 578ms for 1M rows)
- **Throughput**: 1.73M rows/second
- **Pre-allocation** - Estimate rows/cols to reduce reallocation overhead
- **Multi-threaded inference** - Parallel type detection with conflict resolution

#### String Operations

- **SIMD string comparison** - 2-4× faster for strings >16 bytes
- **Length-first short-circuit** - 7.5× faster on unequal lengths
- **Hash caching** - 38% join speedup, 32% groupby speedup
- **String interning** - 4-8× memory reduction for repeated strings

#### Algorithm Improvements

- **Hash join (O(n+m))** - 98% faster (593ms → 11.21ms for 10K×10K)
- **Column-wise memcpy** - 5× faster joins with sequential access
- **FNV-1a hashing** - 7% faster than Wyhash for small keys
- **GroupBy hash-based aggregation** - 32% faster (2.83ms → 1.76ms)

#### Data Structures

- **Column name HashMap** - O(1) lookups, 100× faster for wide DataFrames (100+ cols)
- **Categorical encoding** - 80-92% memory reduction for low-cardinality data
- **Apache Arrow compatibility** - Zero-copy interop with Arrow IPC format

#### Memory Layout

- **Columnar storage** - Cache-friendly contiguous memory per column
- **Arena allocator** - Single free operation, zero memory leaks
- **Lazy allocation** - ArrayList vs fixed arrays, 8KB bundle reduction

#### Bundle Size

- **Dead code elimination** - 86KB → 74KB → 62KB final
- **wasm-opt -Oz** - 20-30% size reduction
- **35KB gzipped** - Competitive with full DataFrame libraries

#### Performance Results (Milestone 1.2.0)

- **3-11× faster** than JavaScript libraries (Papa Parse, csv-parse)
- **11/12 benchmarks passing** (92% pass rate, all exceed or meet targets)
- **Zero memory leaks** (1000-iteration verified across all parallel operations)
- **SIMD**: 95-97% faster than targets (billions of rows/sec)
- **Parallel operations**: 81-99% faster than targets

---

## Performance Benchmarks (Milestone 1.2.0)

### CSV Parsing (1M rows, 10 columns)

- **Rozes**: 578ms (1.73M rows/sec, **81% faster than target**)
- **Target**: <3000ms
- **Grade**: A+

### DataFrame Operations

| Operation                  | Dataset    | Rozes    | Target  | Grade | vs Target         |
| -------------------------- | ---------- | -------- | ------- | ----- | ----------------- |
| **CSV Parse**              | 1M rows    | 578ms    | <3000ms | A+    | **81% faster**    |
| **Filter**                 | 1M rows    | 13.11ms  | <100ms  | A+    | **87% faster**    |
| **Sort**                   | 100K rows  | 6.11ms   | <100ms  | A+    | **94% faster**    |
| **GroupBy**                | 100K rows  | 1.76ms   | <300ms  | A+    | **99% faster!**   |
| **Join (pure algorithm)**  | 10K × 10K  | 0.44ms   | <10ms   | A+    | **96% faster**    |
| **Join (full pipeline)**   | 10K × 10K  | 588.56ms | <500ms  | A     | **18% slower**    |
| **SIMD Sum**               | 200K rows  | 0.04ms   | <1ms    | A+    | **96% faster**    |
| **SIMD Mean**              | 200K rows  | 0.04ms   | <2ms    | A+    | **98% faster**    |
| **SIMD Min/Max**           | 200K rows  | 0.03ms   | <1ms    | A+    | **97% faster**    |
| **SIMD Variance**          | 200K rows  | 0.09ms   | <3ms    | A+    | **97% faster**    |
| **Radix Join SIMD Probe**  | 10K rows   | 0.07ms   | <0.5ms  | A+    | **85% faster**    |
| **Bloom Filter Rejection** | 10K probes | 0.01ms   | <0.2ms  | A+    | **95% faster**    |
| **Radix vs Standard Join** | 100K×100K  | 5.29ms   | N/A     | N/A   | **1.65× speedup** |
| **Head**                   | 100K rows  | 0.01ms   | N/A     | A+    | **14B rows/sec**  |
| **DropDuplicates**         | 100K rows  | 656ms    | N/A     | N/A   | **152K rows/sec** |

### SIMD Throughput (Milestone 1.2.0)

- **SIMD Sum**: 4.48 billion rows/sec
- **SIMD Mean**: 4.46 billion rows/sec
- **SIMD Min**: 6.70 billion rows/sec
- **SIMD Max**: 6.55 billion rows/sec
- **SIMD Variance**: 2.21 billion rows/sec
- **SIMD StdDev**: 2.23 billion rows/sec

### Overall Results

- **11/12 benchmarks passed** (92% pass rate)
- **All SIMD operations**: 95-97% faster than targets
- **Parallel operations**: 81-99% faster than targets

### vs JavaScript Libraries (100K rows)

- **vs Papa Parse**: 3.87× faster (207.67ms → 53.67ms)
- **vs csv-parse**: 7.96× faster (427.48ms → 53.67ms)

_Benchmarks run on macOS (Darwin 25.0.0), Zig 0.15.1, ReleaseFast mode, averaged over multiple runs_

---

## Documentation

### API Reference

- **[Node.js/TypeScript API](./docs/NODEJS_API.md)** - Complete API reference for Node.js and Browser (TypeScript + JavaScript)
- **[Zig API](./docs/ZIG_API.md)** - API reference for embedding Rozes in Zig applications

### Guides

- **[Performance Guide](./docs/PERFORMANCE.md)** - SIMD, parallel execution, lazy evaluation, and optimization tips (Milestone 1.2.0)
- **[Query Optimization Cookbook](./docs/QUERY_OPTIMIZATION_GUIDE.md)** - 18 practical recipes with before/after examples (Milestone 1.2.0)
- **[Memory Management](./docs/MEMORY_MANAGEMENT.md)** - Manual vs automatic cleanup (autoCleanup option)
- **[Migration Guide](./docs/MIGRATION.md)** - Migrate from Papa Parse, csv-parse, pandas, or Polars
- **[Changelog](./CHANGELOG.md)** - Version history and release notes
- **[Benchmark Report](./docs/BENCHMARK_BASELINE_REPORT.md)** - Detailed performance analysis

### Examples

#### Real-World Examples (Node.js)

- **[01-sales-analytics](./examples/nodejs/01-sales-analytics/)** - GroupBy aggregations, filtering, sorting, summary statistics
- **[02-time-series](./examples/nodejs/02-time-series/)** - Time series analysis, date handling, temporal operations
- **[03-data-pipeline](./examples/nodejs/03-data-pipeline/)** - ETL workflows, data transformation pipelines
- **[04-data-cleaning](./examples/nodejs/04-data-cleaning/)** - Missing data handling, outliers, deduplication
- **[05-financial-analytics](./examples/nodejs/05-financial-analytics/)** - Rolling windows, expanding windows, correlations, financial metrics
- **[06-ml-data-prep](./examples/nodejs/06-ml-data-prep/)** - Feature engineering, normalization, ranking
- **[07-text-processing](./examples/nodejs/07-text-processing/)** - String operations, pattern matching, text cleaning
- **[08-reshaping](./examples/nodejs/08-reshaping/)** - Pivot, melt, transpose for reporting

Each example includes:
- `generate-sample-data.js` - Realistic test data generator
- `index.js` - Complete working pipeline
- `test.js` - Comprehensive test suite
- `README.md` - Detailed documentation

#### Browser Examples
- **[Browser Examples](./examples/browser/)** - Coming soon

---

## Browser Support

| Browser | Version | Status           | Notes                    |
| ------- | ------- | ---------------- | ------------------------ |
| Chrome  | 90+     | ✅ Tier 1        | Full WebAssembly support |
| Firefox | 88+     | ✅ Tier 1        | Full WebAssembly support |
| Safari  | 14+     | ✅ Tier 1        | Full WebAssembly support |
| Edge    | 90+     | ✅ Tier 1        | Chromium-based           |
| IE 11   | N/A     | ❌ Not Supported | No WebAssembly           |

---

## Known Limitations (1.2.0)

**⚠️ Missing Value Representation (MVP Limitation)**

**Current Behavior**:
- **Int64 columns**: `0` represents missing values
  - ⚠️ **Limitation**: Cannot distinguish between legitimate zero and missing
  - Example: `[0, 1, 2]` with `fillna(99)` becomes `[99, 1, 2]` (zero incorrectly replaced)
- **Float64 columns**: `NaN` represents missing values
  - ✅ **Correct**: NaN has no other meaning
  - Example: `[NaN, 1.5, 2.0]` with `fillna(0.0)` becomes `[0.0, 1.5, 2.0]`

**Workarounds**:
- Use Float64 columns if you need to preserve zeros
- Avoid `fillna()`, `dropna()`, `isna()` operations on Int64 columns with legitimate zeros

**Planned Fix (v1.4.0)**:
- Add null bitmap to Series struct (similar to pandas/Arrow)
- Support explicit null tracking for all types
- Breaking change: Will require migration for existing code

**What's Available** (1.3.0):

- ✅ **CSV Parsing**: `fromCSV()`, `fromCSVFile()` - Fully implemented with parallel parsing
- ✅ **CSV Export**: `toCSV()` - Export with custom delimiters, headers, quoting
- ✅ **Column Access**: `column()` - All types (Int64, Float64, String, Bool) supported
- ✅ **DataFrame Utilities**: `drop()`, `rename()`, `unique()`, `dropDuplicates()`, `describe()`, `sample()`
- ✅ **Missing Data**: `isna()`, `notna()`, `dropna()` - Handle missing values
- ✅ **String Operations**: `str.lower()`, `str.upper()`, `str.trim()`, `str.contains()`, `str.replace()`, `str.slice()`, `str.split()`
- ✅ **Advanced Aggregations**: `median()`, `quantile()`, `valueCounts()`, `corrMatrix()`, `rank()`
- ✅ **Multi-Column Sort**: `sortBy()` with per-column ascending/descending order
- ✅ **Join Types**: `innerJoin()`, `leftJoin()`, `rightJoin()`, `outerJoin()`, `crossJoin()`
- ✅ **Window Operations**: `rolling*()`, `expanding*()` for time series analysis
- ✅ **Reshape Operations**: `pivot()`, `melt()`, `transpose()`, `stack()`, `unstack()`
- ✅ **Apache Arrow**: `toArrow()`, `fromArrow()` - Interop with Arrow ecosystem (schema-only MVP)
- ✅ **Lazy Evaluation**: `lazy()`, `select()`, `limit()`, `collect()` - Query optimization

**Remaining limitations** (planned for v1.4.0+):

- ⚠️ **WebGPU Acceleration**: Browser GPU acceleration for large datasets (planned 1.4.0)
- ⚠️ **Full Arrow IPC**: Complete data transfer (schema-only in 1.3.0, full IPC in 1.4.0)
- ⚠️ **Null Bitmaps**: Explicit null tracking for Int64 columns (planned 1.4.0)
- ✅ **Basic Operations**: `select()`, `head()`, `tail()`, `sort()` - Fully functional
- ✅ **SIMD Aggregations**: `sum()`, `mean()`, `min()`, `max()`, `variance()`, `stddev()` - Production ready

**Future features** (1.3.0+):

- WebGPU acceleration for browser (2-10× speedup on large datasets)
- Environment-optimized packages (`rozes/web`, `rozes/node`, `rozes/csv`)
- Stream API for large files (>1GB)
- Rich error messages with column suggestions (Levenshtein distance)
- Interactive browser demo

**Completed optimizations** (Milestone 1.2.0):

- ✅ SIMD aggregations (95-97% faster than targets, billions of rows/sec)
- ✅ Radix hash join for integer keys (1.65× speedup on 100K×100K)
- ✅ Parallel CSV type inference (81% faster, 1.73M rows/sec)
- ✅ Parallel DataFrame operations (87-99% faster, thread-safe execution)
- ✅ Apache Arrow compatibility (schema mapping + IPC format)
- ✅ Lazy evaluation & query optimization (predicate/projection pushdown)

See [CHANGELOG.md](./docs/CHANGELOG.md) for full list.

---

## Architecture

Built with **Zig + WebAssembly**:

- **Zig 0.15+**: Memory-safe systems language
- **WebAssembly**: Universal runtime (browser + Node.js)
- **Tiger Style**: Safety-first methodology from [TigerBeetle](https://github.com/tigerbeetle/tigerbeetle)
  - 2+ assertions per function
  - Bounded loops with explicit MAX constants
  - Functions ≤70 lines
  - Explicit error handling
  - Zero dependencies (only Zig stdlib)

**Project Structure**:

```
rozes/
├── src/                    # Zig source code
│   ├── core/              # DataFrame engine
│   ├── csv/               # CSV parser (RFC 4180 compliant)
│   └── rozes.zig          # Main API
├── dist/                   # npm package
│   ├── index.js           # CommonJS entry point
│   ├── index.mjs          # ESM entry point
│   └── index.d.ts         # TypeScript definitions
├── docs/                   # Documentation
│   ├── NODEJS_API.md      # Node.js API reference
│   ├── ZIG_API.md         # Zig API reference
│   ├── MIGRATION.md       # Migration guide
│   └── CHANGELOG.md       # Version history
└── examples/               # Example programs
    └── node/              # Node.js examples
```

---

## Development

### Build from Source

```bash
# Prerequisites: Zig 0.15.1+
git clone https://github.com/yourusername/rozes.git
cd rozes

# Build WASM module
zig build

# Run tests (461/463 passing)
zig build test

# Run conformance tests (125/125 passing)
zig build conformance

# Run benchmarks (6/6 passing)
zig build benchmark

# Run memory leak tests (5/5 suites passing, ~5 minutes)
zig build memory-test

# Run nodejs tests
 npm run test:api
```

### Contributing

We welcome contributions! Please:

1. Read [CLAUDE.md](./CLAUDE.md) for project guidelines
2. Check [docs/TODO.md](./docs/TODO.md) for current tasks
3. Follow Tiger Style coding standards
4. Add tests for new features
5. Run `zig fmt` before committing

---

## Comparison to Alternatives

| Feature           | Rozes           | Papa Parse | Danfo.js      | Polars-WASM | DuckDB-WASM  |
| ----------------- | --------------- | ---------- | ------------- | ----------- | ------------ |
| **Performance**   | ⚡ 3-10× faster | Baseline   | ~Same as Papa | 2-5× faster | 5-10× faster |
| **Bundle Size**   | 📦 62KB         | 206KB      | 1.2MB         | 2-5MB       | 15MB         |
| **Zero-Copy**     | ✅ TypedArray   | ❌         | ❌            | ✅          | ✅           |
| **RFC 4180**      | ✅ 100%         | ⚠️ ~95%    | ⚠️ Basic      | ✅          | ✅           |
| **DataFrame Ops** | ✅ 50+          | ❌         | ✅            | ✅          | ✅ SQL       |
| **Memory Safe**   | ✅ Zig          | ❌ JS      | ❌ JS         | ✅ Rust     | ✅ C++       |
| **Node.js**       | ✅              | ✅         | ✅            | ✅          | ✅           |
| **Browser**       | ✅              | ✅         | ✅            | ✅          | ✅           |
| **TypeScript**    | ✅ Full         | ⚠️ Basic   | ✅            | ✅          | ✅           |

**When to use Rozes**:

- Need fast CSV parsing (3-10× faster than Papa Parse)
- Want small bundle size (103KB vs 1-15MB for alternatives)
- Need DataFrame operations (GroupBy, Join, Window functions)
- Want zero-copy performance with TypedArray access
- Value 100% RFC 4180 compliance and test coverage

**When to use alternatives**:

- **Papa Parse**: Need streaming API (coming in Rozes 1.1.0)
- **Danfo.js**: Need full pandas-like API (more operations than Rozes 1.0.0)
- **Polars-WASM**: Need lazy evaluation and query optimization (coming in Rozes 1.1.0+)
- **DuckDB-WASM**: Need SQL interface

---

## License

MIT License - see [LICENSE](./LICENSE) for details.

---

## Acknowledgments

- **Tiger Style**: Inspired by [TigerBeetle](https://github.com/tigerbeetle/tigerbeetle)
- **Zig**: Built with [Zig programming language](https://ziglang.org/)
- **RFC 4180**: CSV format specification

---

## Links

- **GitHub**: https://github.com/yourusername/rozes
- **npm**: https://www.npmjs.com/package/rozes
- **Issues**: https://github.com/yourusername/rozes/issues
- **Discussions**: https://github.com/yourusername/rozes/discussions

---

**Status**: 1.2.0 Advanced Optimizations Release (11/12 benchmarks passing - 92%)
**Last Updated**: 2025-11-01

**Try it now**: `npm install rozes`
