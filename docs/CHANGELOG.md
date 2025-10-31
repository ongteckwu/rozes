# Changelog

All notable changes to the Rozes DataFrame library will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - 2025-10-31

### Added

- Automatic memory cleanup via FinalizationRegistry (default enabled, Chrome 84+, Firefox 79+, Safari 14.1+, Node.js 14.6+)
- `autoCleanup: true` option for automatic GC-based cleanup
- Manual `df.free()` still available (3× faster in tight loops, recommended for production)
- `df.filter(columnName, operator, value)` - numeric comparison (==, !=, >, <, >=, <=)
- `df.select(columnNames)` - select specific columns
- `df.head(n)` / `df.tail(n)` - get first/last N rows
- `df.sort(columnName, descending)` - single column sort
- `df.groupBy(groupColumn, valueColumn, aggFunc)` - aggregation (sum, mean, count, min, max)
- `df.join(other, on, how)` - join DataFrames (inner, left)
- `df.toCSV(options)` - serialize to CSV string (RFC 4180 compliant)
- String columns: `df.column(name)` returns `string[]`
- Boolean columns: `df.column(name)` returns `Uint8Array`
- TypeScript full type inference: `Float64Array | Int32Array | BigInt64Array | Uint8Array | string[] | null`
- 5 automated memory leak test suites: gc_verification, wasm_memory, error_recovery, auto_vs_manual, memory_pressure
- `zig build memory-test` command
- Documentation: `docs/MEMORY_MANAGEMENT.md`, `docs/MEMORY_TESTING.md`
- Examples: `auto_cleanup_examples.js/ts`, `operations.js/ts`
- Tests: 461/463 passing (99.6%), 28/33 memory tests passing (85%)

### Changed

- Default: `autoCleanup: true` (GC-based cleanup)
- Performance: GroupBy.sum 1.15ms (8.6M rows/sec), Join.inner 597µs (3.4M rows/sec)
- Heap growth: -0.30 MB with auto cleanup
- Wasm memory: 0.63 MB baseline, 5-15 MB with auto cleanup (non-deterministic GC)

### Fixed

- Zero memory leaks in 1000-iteration tests
- FinalizationRegistry properly unregisters on manual `free()` (prevents double-free)
- Boolean column type: correct `Uint8Array` handling
- String column: proper UTF-8 decoding in Wasm→JS bridge

### Known Limitations

- Right/outer/cross join deferred to 1.2.0 (inner/left implemented)
- Hash caching for string columns deferred (performance optimization)
- Stream API for large files (>1GB) deferred

---

## [1.0.0] - 2025-10-31

### Added

- DataFrame creation from CSV, JSON, programmatic APIs
- Column selection, filtering, sorting, renaming
- Row slicing: `head()`, `tail()`, `sample()`
- Schema inspection: `info()`, `describe()`
- Type inference: Int64, Float64, String, Bool, Categorical, Null
- CSV parsing: RFC 4180 compliant (quoted fields, embedded commas/newlines, CRLF/LF/CR, BOM)
- JSON parsing: NDJSON, JSON Array, Columnar JSON
- GroupBy: `sum()`, `mean()`, `min()`, `max()`, `count()`
- Join: inner, left, right, outer, cross
- Window operations: `rolling()`, `expanding()`
- String operations: case conversion, length, predicates
- Reshape: `pivot()`, `melt()`, `transpose()`, `stack()`, `unstack()`
- Combine: `concat()`, `merge()`, `append()`, `update()`
- Functional: `apply()`, `map()` (with type conversion)
- Missing values: `fillna()`, `dropna()`, `isNull()`
- Statistics: `corr()`, `cov()`, `rank()`, `valueCounts()`
- Categorical type: dictionary-encoded, 80-92% memory savings
- SIMD string comparison: 2-4× faster (>16 bytes)
- String interning: 4-8× memory reduction
- Hash caching: 38% join speedup, 32% groupby speedup
- SIMD CSV delimiter detection: 37.3% faster (909ms → 570ms)
- Column name lookups: O(n) → O(1) via HashMap
- CommonJS/ESM support, TypeScript definitions
- WASI stub implementation (40+ no-op functions)
- `DataFrame.fromCSVFile(path)` for Node.js
- BigInt column handling for Int64 types
- 62KB WASM bundle (35KB gzipped)
- 461/463 tests passing (99.6%)
- Documentation: ZIG_API.md, NODEJS_API.md, MIGRATION.md, benchmarks

### Changed

- CSV parsing: 570ms (1M rows)
- Filter: 20.99ms (1M rows)
- Sort: 11.06ms (100K rows)
- GroupBy: 1.92ms (100K rows, 32% faster)
- Join: 11.21ms (10K×10K, 98% faster)
- Pure Join: 1.42ms (10K×10K)
- 3.67× faster than Papa Parse, 7.55× faster than csv-parse

### Fixed

- CSV: BOM detection, line ending normalization, trailing delimiters, empty CSV, quoted fields
- NaN handling: IEEE 754 NaN in sort, consistent aggregation
- Memory: zero leaks (1000-iteration tests), categorical deep copy, arena allocator cleanup
- Type conversion: cross-type map functions, Int64↔Float64 distinction, Bool handling
- Tiger Style: 2+ assertions/function, bounded loops, functions ≤70 lines

---

## [0.7.0] - 2025-10-30

### Added

- API convenience methods: `sample()`, `info()`, `unique()`, `nunique()`
- String interning infrastructure (4-8× memory reduction)
- SIMD string comparison (2-4× faster)
- Hash caching in StringColumn (38% join speedup, 32% groupby speedup)
- CSV SIMD delimiter detection (37.3% faster)
- Bundle size optimization: 86KB → 62KB (27% reduction)
- JavaScript comparison benchmarks (`compare_js.js`)
- Pure join benchmark (separate from full pipeline)
- Documentation: API.md, MIGRATION.md, STRING_OPTIMIZATIONS.md, BENCHMARK_BASELINE_REPORT.md

### Changed

- Column name lookups: O(n) → O(1) via HashMap
- Pure join performance: 1.42ms (10K×10K, 85.8% faster than target)
- GroupBy performance: 2.83ms → 1.92ms (32% faster)

---

## [0.6.0] - 2025-10-30

### Added

- Reshape operations: `pivot()`, `melt()`, `transpose()`, `stack()`, `unstack()`
- Combine operations: `concat()`, `merge()` (5 types), `append()`, `update()`
- Functional operations: `apply()`, `map()` (with type conversion)
- Cross-type map: Int64→Float64, Float64→Int64, Bool→Int64
- 98 new tests (52 reshape, 29 combine, 17 functional)

### Changed

- Join optimization: 605ms → 11.21ms (98% faster, column-wise memcpy + hash map)
- Test coverage: 258/264 → 400/405 (maintained 98.8%)

---

## [0.5.0] - 2025-10-30

### Added

- JSON parsing: NDJSON, JSON Array, Columnar JSON, manual schema override
- Rich error messages with row/column context (`RichError` struct)
- Categorical type: dictionary-encoded, deep copy support, 80-92% memory savings
- Statistical functions: enhanced `rank()`, `valueCounts()`

### Changed

- Test coverage: 258+ tests
- Benchmark results: 4/5 passing (join at 605ms, target 500ms)

---

## [0.4.0] - 2025-10-28

### Added

- Window operations: `rolling()`, `expanding()`
- String operations: `toLowerCase()`, `toUpperCase()`, `capitalize()`, `startsWith()`, `endsWith()`, `contains()`, `length()`
- Categorical type: dictionary-encoded, memory-efficient
- Statistical functions: `corr()`, `cov()`, `rank()`, `describe()`
- Missing value handling: `fillna()`, `dropna()`, `isNull()`

### Changed

- Test coverage: 258/264 tests (97.7%)
- Benchmark results: 4/5 passing

---

## [0.3.0] - 2025-10-28

### Added

- Sort operations: single/multi-column, NaN handling, ascending/descending
- GroupBy operations: `sum()`, `mean()`, `min()`, `max()`, `count()`, hash-based FNV-1a, multi-key
- Join operations: inner, left, right, outer, cross (5 types), hash join O(n+m)
- SIMD infrastructure: `compareFloat64Batch()` (2× throughput), `compareInt64Batch()` (2× throughput), `findNextSpecialChar()` (16× throughput)

### Changed

- CSV parsing: 555ms (1M rows)
- Join: 593ms (10K×10K, 19% over target, later optimized to 11.21ms)
- Test coverage: 258+ tests

---

## [0.2.0] - 2025-10-28

### Added

- String column support: offset table, UTF-8 validation
- Boolean column support
- CSV conformance: 125/125 RFC 4180 tests, BOM detection, line ending normalization, trailing delimiters, empty CSV
- External test suites: csv-spectrum (15), PapaParse (100+), uniVocity (50+), **Total: 139 tests (136/137 passing, 99%)**

### Changed

- Conformance: 17% → 97% pass rate
- Type inference: default to String instead of error

---

## [0.1.0] - 2025-10-27

### Added

- Core DataFrame engine: creation, manipulation, Series, column selection, filtering, renaming, row slicing (`head()`, `tail()`)
- CSV parsing: RFC 4180 compliant, type inference (Int64, Float64, Bool, String, Null), automatic header detection
- WebAssembly bindings: browser WASM, TypeScript/JavaScript API wrapper, arena allocator memory management
- Testing: 83 unit tests, 7 memory leak tests, browser test runner, conformance suite
- Performance: 74KB WASM bundle (40KB gzipped), 555ms CSV parsing (1M rows), columnar layout
- Tiger Style: 2+ assertions, bounded loops with MAX, functions ≤70 lines, explicit types (u32), explicit error handling

---

## Links

- [GitHub Repository](https://github.com/yourusername/rozes)
- [Zig API Documentation](./ZIG_API.md)
- [Node.js API Documentation](./NODEJS_API.md)
- [Migration Guide](./MIGRATION.md)
- [Benchmark Report](./BENCHMARK_BASELINE_REPORT.md)

---

**Legend**:

- **Added**: New features
- **Changed**: Changes to existing functionality
- **Deprecated**: Features to be removed in future versions
- **Removed**: Features removed
- **Fixed**: Bug fixes
- **Security**: Security fixes
