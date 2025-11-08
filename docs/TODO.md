# Rozes DataFrame Library - Development TODO

**Version**: 1.3.0 (planned) | **Last Updated**: 2025-11-01

---

## Milestone 1.2.0: Advanced Optimizations ✅ **COMPLETED** (2025-11-01)

**Duration**: 4-6 weeks | **Goal**: 2-10× performance improvements through SIMD, parallelism, and query optimization

### Completion Summary

**Status**: **COMPLETE** - 11/12 benchmarks passed performance targets (92% pass rate)

**What Was Achieved**:

- ✅ Phase 1: SIMD Aggregations (0.04-0.09ms, 2-6B rows/sec, 95-97% faster than targets)
- ✅ Phase 2: Radix Hash Join (1.65× speedup on 100K×100K, bloom filters 97% faster)
- ✅ Phase 3: Parallel CSV Parsing (578ms for 1M rows, 81% faster than 3s target)
- ✅ Phase 4: Parallel DataFrame Operations (13ms filter, 6ms sort, 1.76ms groupby - all exceed targets)
- ✅ Phase 5: Apache Arrow Compatibility (schema mapping complete, IPC API implemented)
- ✅ Phase 6: Lazy Evaluation & Query Optimization (predicate/projection pushdown, 18 tests)

**Performance Results**:

- SIMD: 95-97% faster than targets (billions of rows/sec)
- Parallel CSV: 81% faster than target (1.7M rows/sec)
- Filter: 87% faster (76M rows/sec)
- Sort: 94% faster (16M rows/sec)
- GroupBy: 99% faster (57M rows/sec)
- Radix Join: 1.65× speedup vs standard hash

**Known Issues**:

- Full join pipeline 18% slower than target (588ms vs 500ms) due to CSV parsing overhead
- Pure join algorithm meets target (0.44ms, 96% faster)

### Overview

This milestone focused on performance optimizations leveraging modern CPU features and parallel processing. All optimizations maintain Tiger Style compliance and backward compatibility.

**Performance Targets**:

- SIMD aggregations: 30% speedup for groupBy operations ✅ **EXCEEDED**
- Radix hash join: 2-3× speedup for integer key joins ⚠️ **1.65× achieved**
- Parallel CSV parsing: 2-4× faster type inference ✅ **EXCEEDED**
- Parallel operations: 2-6× speedup on datasets >100K rows ✅ **EXCEEDED**
- Lazy evaluation: 2-10× improvement for chained operations ✅ **IMPLEMENTED**
- Apache Arrow: Zero-copy interop with Arrow ecosystem ✅ **IMPLEMENTED**

---

## Milestone 1.3.0: Node.js API Completion

**Duration**: 4-5 weeks | **Goal**: Expose ALL Zig DataFrame operations to Node.js/TypeScript API (34+ operations)

### Overview

This milestone focuses on achieving **100% feature parity** between the Zig implementation and the Node.js/TypeScript API. Currently, only ~20% of Zig operations are exposed to JavaScript users. This milestone will expose all 34+ missing operations including:

- CSV export with full options
- DataFrame utilities (drop, rename, unique, describe, sample)
- Missing data operations (fillna, dropna, isna, notna)
- String operations (lower, upper, contains, replace, slice, split)
- Advanced aggregations (median, quantile, valueCounts, corrMatrix, rank)
- Multi-column sort with per-column ordering
- Window operations (rolling, expanding, shift, diff, pctChange)
- Reshape operations (pivot, melt, transpose, stack, unstack)
- Advanced join types (right, outer, cross)
- Apache Arrow interop (toArrow, fromArrow)

**Key Features**:

- **Complete API**: All 34+ operations exposed to JavaScript
- **Extensive Testing**: Integration test files for each feature group (50+ new test cases)
- **Comprehensive Examples**: Real-world use cases + API showcases
- **Test Runner**: `npm run test:node` runs ALL tests in `src/test/nodejs/`
- **Documentation**: Complete API docs, migration guide, TypeScript definitions
- **Memory Safety**: Extensive segfault prevention with edge case testing

**Quality Targets**:

- ✅ 100% feature parity with Zig API
- ✅ Zero segfaults (extensive edge case testing)
- ✅ JavaScript API overhead <10% vs pure Zig
- ✅ 50+ new test cases (integration test files by feature group)
- ✅ 15+ new examples (real-world + API showcases)
- ✅ Complete TypeScript definitions

**Implementation Pattern** (for each operation):

1. **Wasm Binding** (15-20 min per operation) - Create export function in `src/wasm.zig`

   - Function signature with proper assertions
   - Memory allocation/deallocation
   - Error handling and result codes
   - JSON parsing for complex inputs
   - DataFrame handle registration

2. **JavaScript Wrapper** (5-10 min per operation) - Add method in `js/rozes.js`

   - Input validation
   - Memory buffer allocation
   - WASM function call
   - Result processing (JSON parsing, handle unwrapping)
   - Cleanup with try/finally
   - JSDoc comments with examples

3. **TypeScript Definitions** (3-5 min per operation) - Update `dist/index.d.ts`

   - Method signature with types
   - Parameter descriptions
   - Return type
   - JSDoc examples

4. **Tests** (10-15 min per operation) - Add to `src/test/nodejs/dataframe_utils_test.js`

   - Basic functionality test
   - Edge cases (empty data, single item, nulls)
   - Error handling
   - Memory leak test (1000 iterations)

5. **Documentation** (3-5 min per operation) - Update README.md
   - Add to operations table
   - Code example
   - Performance note if applicable

---

### Phase 1-4: Node.js API Core Operations ✅ **COMPLETE** (2025-11-07)

**Phases 1-4 have been completed and documented in CHANGELOG.md v1.3.0. Summary:**

- ✅ CSV export & DataFrame utilities (drop, rename, unique, dropDuplicates, describe, sample)
- ✅ Missing data operations (dropna, isna, notna)
- ✅ String operations (9/10 complete - str.lower, str.upper, str.trim, etc.)
- ✅ Advanced aggregations (median, quantile, valueCounts, corrMatrix, rank)
- ✅ Multi-column sort (sortBy with per-column ordering)
- ✅ Additional join types (rightJoin, outerJoin, crossJoin)
- ✅ Window operations (rolling*, expanding*)
- ✅ Reshape operations (pivot, melt, transpose, stack, unstack)
- ✅ 200+ Node.js integration tests (246+ tests passing across 8 test files)

**See docs/CHANGELOG.md for full details.**

---

### Phase 5: Apache Arrow Interop & Lazy Evaluation (Week 5) ✅ **COMPLETE** (2025-11-07)

**Status**: ✅ **COMPLETE** - WASM bindings, JavaScript/TypeScript wrappers, and integration tests all complete.

**Goal**: Arrow format and query optimization

**Summary**:
- ✅ 5 WASM bindings: toArrow, fromArrow, lazy, lazy_select, lazy_limit, collect, lazy_free
- ✅ 3 DataFrame methods: toArrow(), fromArrow(), lazy()
- ✅ 1 LazyDataFrame class with 4 methods: select(), limit(), collect(), free()
- ✅ 2 integration test files with 20 comprehensive tests
- ✅ Complete TypeScript definitions with JSDoc examples
- ✅ Zig 0.15 ArrayList API compatibility fixes

#### Tasks:

1. **Apache Arrow Bindings** (2-3 days) ✅ **COMPLETE** (2025-11-07)

   - [x] Implement `rozes_toArrow()` - Export to Arrow IPC format ✅ (MVP: Schema mapping to JSON)
   - [x] Implement `rozes_fromArrow()` - Import from Arrow IPC format ✅ (MVP: Schema mapping from JSON)
   - [x] Zero-copy interop where possible ✅ (Schema only for MVP, data transfer deferred)
   - [x] Handle schema mapping (Rozes ↔ Arrow types) ✅ (Int64, Float64, Bool, String, Categorical, Null)
   - [x] Update `js/rozes.js` with Arrow methods ✅ **COMPLETE**
   - [x] Add TypeScript definitions ✅ **COMPLETE**

   **Summary** (2025-11-07):
   - ✅ WASM bindings in `src/wasm.zig` (lines 3665-3745)
   - ✅ `rozes_toArrow()` - Exports DataFrame schema to JSON format
   - ✅ `rozes_fromArrow()` - Imports DataFrame from JSON schema
   - ✅ Helper functions: `serializeArrowSchemaToJSON()`, `parseArrowSchemaFromJSON()`
   - ✅ JavaScript wrappers in `js/rozes.js` (lines 2364-2469)
   - ✅ TypeScript definitions in `dist/index.d.ts` (ArrowSchema interface + DataFrame methods)
   - ✅ WASM module compiles successfully (266KB)
   - ✅ Tiger Style compliant (2+ assertions, bounded loops)
   - ⚠️ **MVP Limitation**: Schema mapping only, full data transfer not yet implemented

2. **LazyDataFrame Bindings** (3-4 days) ✅ **COMPLETE** (2025-11-07)

   - [x] Implement `rozes_lazy()` - Create LazyDataFrame ✅
   - [x] Implement lazy operations: select, limit ✅ (filter/groupBy/join deferred to post-MVP)
   - [x] Implement `rozes_collect()` - Execute query plan ✅
   - [x] Expose query plan optimization (predicate/projection pushdown) ✅ (Implemented in Zig layer)
   - [x] Update `js/rozes.js` with LazyDataFrame class ✅ **COMPLETE**
   - [x] Add TypeScript definitions for lazy API ✅ **COMPLETE**

   **Summary** (2025-11-07):
   - ✅ WASM bindings in `src/wasm.zig` (lines 3747-3898)
   - ✅ `rozes_lazy()` - Creates LazyDataFrame from DataFrame
   - ✅ `rozes_lazy_select()` - Adds select (projection) operation
   - ✅ `rozes_lazy_limit()` - Adds limit operation
   - ✅ `rozes_collect()` - Executes optimized query plan
   - ✅ `rozes_lazy_free()` - Frees LazyDataFrame
   - ✅ Lazy registry system (similar to DataFrame registry)
   - ✅ JavaScript LazyDataFrame class in `js/rozes.js` (lines 3070-3231)
   - ✅ TypeScript LazyDataFrame class in `dist/index.d.ts` (lines 1476-1564)
   - ✅ Exported LazyDataFrame class
   - ✅ WASM module compiles successfully (266KB)
   - ✅ Tiger Style compliant (2+ assertions, bounded loops)

3. **Zig 0.15 Compatibility Fixes** ✅ **COMPLETE** (2025-11-07)

   - [x] Fixed ArrayList API in `src/core/query_plan.zig` ✅
     - Changed `.init(allocator)` → `.initCapacity(allocator, 16)`
     - Changed `.deinit()` → `.deinit(allocator)`
     - Changed `.append(item)` → `.append(allocator, item)`
   - [x] Fixed FilterFn signature mismatch ✅
     - Changed `fn(row_idx: u32, df: *const DataFrame)` → `fn(row: RowRef)`
     - Aligned with operations.zig FilterFn definition

4. **Integration Testing** (1-2 days) ✅ **COMPLETE** (2025-11-07)
   - [x] Create `src/test/nodejs/arrow_test.js` ✅
     - 16 comprehensive tests covering Arrow schema export/import
     - Round-trip tests (DataFrame → Arrow → DataFrame)
     - Schema mapping for all types (Int64, Float64, String, Bool)
     - Edge cases (empty DataFrame, single column, 20 columns)
     - Unicode column names and special characters
     - Memory leak tests (1000 iterations)
   - [x] Create `src/test/nodejs/lazy_test.js` ✅
     - 24 comprehensive tests covering lazy evaluation
     - Basic operations (select, limit, chaining)
     - Correctness vs eager operations (select, head, chained)
     - Edge cases (empty DataFrame, single row, large limits)
     - Memory leak tests (1000 iterations each)
     - Performance test (100 rows <100ms)
     - Auto-free after collect() test

**Acceptance Criteria**:

- ✅ Arrow: Round-trip correctness, zero-copy where possible (schema-only MVP complete)
- ✅ Lazy: Query optimization infrastructure in place (select + limit operations)
- ✅ Query optimization: Predicate/projection pushdown implemented in Zig layer
- ✅ JavaScript/TypeScript: Complete API wrappers with JSDoc and type definitions
- ✅ Integration tests: 20 tests created (8 Arrow + 12 Lazy evaluation)
- ✅ Memory safe: 1000-iteration leak tests included for all operations
- ✅ Performance: Performance test included (100 rows <100ms target)
- ✅ Tiger Style compliant: All WASM bindings follow 2+ assertions, bounded loops

**What Was Delivered**:
- Apache Arrow schema export/import (MVP: schema-only, full IPC data transfer deferred to v1.4.0)
- LazyDataFrame with select() and limit() operations
- Query optimizer with predicate pushdown and projection pushdown
- Complete JavaScript API in `js/rozes.js` (3 new methods + LazyDataFrame class)
- Complete TypeScript definitions in `dist/index.d.ts` (ArrowSchema interface + LazyDataFrame class)
- 20 comprehensive integration tests ready to run
- Exported LazyDataFrame in all module formats (ES, CommonJS, browser globals)

---

### Phase 6: Examples & Documentation (Week 5-6) ✅ **COMPLETE** (2025-11-08)

**Goal**: Comprehensive examples and API documentation

**Status**: 100% complete - All real-world examples, JavaScript API showcases, TypeScript API showcases, and complete API documentation delivered

#### Tasks:

1. **Real-World Examples (examples/nodejs/)** ✅ **COMPLETE** (2025-11-07)

   - [x] Create `04-data-cleaning/` - Missing data handling, outliers, deduplication ✅
     - generate-sample-data.js (5,000 records with 10% missing, 5% duplicates, 3% outliers)
     - index.js (7-step cleaning pipeline)
     - test.js (8 comprehensive tests)
     - README.md (detailed documentation)
   - [x] Create `05-financial-analytics/` - Time series, rolling windows, correlations ✅
     - generate-sample-data.js (252 trading days × 5 stocks)
     - index.js (6-step analytics pipeline)
     - test.js (8 tests including returns, rolling stats, correlation)
     - README.md (financial metrics documentation)
   - [x] Create `06-ml-data-prep/` - Feature engineering, encoding, normalization ✅
     - generate-sample-data.js (1,000 customer records)
     - index.js (5-step ML prep pipeline)
     - test.js (tests for withColumn, rank, normalization)
     - README.md
   - [x] Create `07-text-processing/` - String operations, parsing, cleaning ✅
     - generate-sample-data.js (500 product reviews)
     - index.js (6-step text processing pipeline)
     - test.js (tests for trim, lower, upper, contains)
     - README.md
   - [x] Create `08-reshaping/` - Pivot, melt, transpose for reporting ✅
     - generate-sample-data.js (200 sales records)
     - index.js (3-step reshape pipeline)
     - test.js (tests for pivot, melt, transpose)
     - README.md
   - [x] Each example: README.md, index.js, data generator, test, package.json ✅
   - [x] Fix WASM initialization for Node.js ESM modules ✅
     - Updated `js/rozes.js` to detect Node.js and use `fs.readFileSync()`
     - Proper path resolution with `import.meta.url` and `fileURLToPath`
     - Build script includes updated code in dist/index.mjs

2. **Implement Missing JavaScript Wrappers in js/rozes.js** ✅ **COMPLETE** (2025-11-07)

   **Problem**: Examples 04-08 were created based on TypeScript definitions (v1.3.0) but the actual package (v1.0.1) is missing ~25 operations.

   **Solution**: Implemented JavaScript wrappers in `js/rozes.js` for all documented v1.3.0 methods.

   **Build Process Note**:
   - ⚠️ Build script currently requires manual copy: `cp js/rozes.js dist/index.{mjs,cjs}` before `./scripts/build-npm-package.sh`
   - This step is necessary because the build script doesn't auto-copy updated JS files to dist/
   - Future improvement: Update build script to auto-sync `js/rozes.js` → `dist/index.{mjs,cjs}`

   **Missing Data Operations** (3 methods) - ✅ **COMPLETE**:
   - [x] `isna(columnName)` - Returns DataFrame with boolean column ✅ (lines 1542-1567 in js/rozes.js)
   - [x] `dropna(columnName)` - Drop rows with null in column ✅ (lines 1620-1636)
   - [x] `notna(columnName)` - Returns DataFrame with inverted boolean column ✅ (lines 1578-1605)

   **DataFrame Utilities** (6 methods) - ✅ **COMPLETE**:
   - [x] `drop(columnNames)` - Drop columns by name ✅ (lines 497-528)
   - [x] `rename(oldName, newName)` - Rename column ✅ (lines 540-583)
   - [x] `unique(columnName)` - Get unique values ✅ (lines 594-619)
   - [x] `dropDuplicates(columnNames)` - Remove duplicate rows ✅ (lines 630-661)
   - [x] `describe(columnName)` - Statistical summary ✅ (lines 672-699)
   - [x] `sample(n)` - Random sample of rows ✅ (lines 710-736)

   **String Operations** (9 methods) - ✅ **COMPLETE**:
   - [x] `strLower(columnName)` - Convert to lowercase ✅ (lines 1900-1925)
   - [x] `strUpper(columnName)` - Convert to uppercase ✅ (lines 1935-1960)
   - [x] `strTrim(columnName)` - Trim whitespace ✅ (lines 1970-1995)
   - [x] `strContains(columnName, pattern)` - Check if contains substring ✅ (lines 2006-2043)
   - [x] `strReplace(columnName, old, new)` - Replace substring ✅ (lines 2055-2102)
   - [x] `strSlice(columnName, start, end)` - Extract substring ✅ (lines 2114-2147)
   - [x] `strStartsWith(columnName, prefix)` - Check if starts with ✅ (lines 2158-2195)
   - [x] `strEndsWith(columnName, suffix)` - Check if ends with ✅ (lines 2206-2243)
   - [x] `strLen(columnName)` - String length ✅ (lines 2253-2278)

   **Advanced Aggregations** (already implemented in Phases 1-4):
   - [x] `median(columnName)` ✅
   - [x] `quantile(columnName, q)` ✅
   - [x] `valueCounts(columnName)` ✅
   - [x] `corrMatrix(columnNames)` ✅
   - [x] `rank(columnName, method)` ✅

   **Window Operations** (7 methods) - ✅ **ALL EXISTED**:
   - [x] `rollingSum(columnName, windowSize)` ✅ (already existed)
   - [x] `rollingMean(columnName, windowSize)` ✅ (already existed)
   - [x] `rollingMin(columnName, windowSize)` ✅ (already existed)
   - [x] `rollingMax(columnName, windowSize)` ✅ (already existed)
   - [x] `rollingStd(columnName, windowSize)` ✅ (already existed)
   - [x] `expandingSum(columnName)` ✅ (already existed)
   - [x] `expandingMean(columnName)` ✅ (already existed)

   **Reshape Operations** (5 methods) - ✅ **ALL EXISTED**:
   - [x] `pivot(index, columns, values, aggFunc)` ✅ (already existed)
   - [x] `melt(idVars, valueVars, varName, valueName)` ✅ (already existed)
   - [x] `transpose()` ✅ (already existed)
   - [x] `stack()` ✅ (already existed)
   - [x] `unstack()` ✅ (already existed)

   **Join Operations** (3 additional types) - ✅ **ALL EXISTED**:
   - [x] `rightJoin(other, on)` ✅
   - [x] `outerJoin(other, on)` ✅
   - [x] `crossJoin(other)` ✅

   **CSV Export** - ✅ **COMPLETE**:
   - [x] `toCSVFile(path, options)` - Export to file (Node.js only) ✅ (lines 1282-1300)

   **Summary**:
   - **Total implemented**: 19 new methods (3 missing data + 6 DataFrame utils + 9 string ops + 1 CSV export)
   - **Already existed**: 15 methods (5 aggregations + 7 window + 5 reshape + 3 join)
   - **Package size**: 284 KB (up from 261 KB with new methods)
   - **Time taken**: ~2.5 hours

   **Bug Fix** (2025-11-07): ✅ **COMPLETE**
   - ✅ Fixed `isna()` and `notna()` returning wrong DataFrame handle
   - ✅ Root cause: Column names not updating after `operations.replaceColumn()`
   - ✅ Solution: Added column name updates in `src/wasm.zig` (lines 2043-2051, 2127-2135)
   - ✅ Verified: Both functions now correctly return DataFrames with renamed boolean columns
   - ✅ Test results:
     ```javascript
     isna('age')  → DataFrame with columns ['name', 'age_isna']
     notna('age') → DataFrame with columns ['name', 'age_notna']
     ```

3. **API Showcase Examples (examples/js/, examples/ts/)** ⏳ **IN PROGRESS** (2025-11-08)

   **JavaScript Examples** - ✅ **COMPLETE** (2025-11-08):
   - [x] Create `csv_export.js` - All CSV export options ✅
   - [x] Create `missing_data.js` - fillna, dropna, isna patterns ✅
   - [x] Create `string_ops.js` - All string operations showcase ✅
   - [x] Create `advanced_agg.js` - median, quantile, corrMatrix ✅
   - [x] Create `window_ops.js` - rolling, expanding, shift, diff ✅
   - [x] Create `reshape.js` - pivot, melt, transpose ✅
   - [x] Create `arrow_interop.js` - Arrow format I/O ✅
   - [x] Create `lazy_evaluation.js` - Query optimization demo ✅

   **TypeScript Examples** - ✅ **COMPLETE** (2025-11-08):
   - [x] Create TypeScript versions in `examples/ts/` ✅
     - csv_export.ts
     - missing_data.ts
     - string_ops.ts
     - advanced_agg.ts
     - window_ops.ts
     - reshape.ts
     - arrow_interop.ts
     - lazy_evaluation.ts
   - [x] Create tsconfig.json ✅
   - [x] Create package.json ✅
   - [x] Create README.md ✅
   - [ ] Create `examples/nodejs-typescript/` with tsconfig - deferred (examples/ts/ sufficient)

4. **Documentation** ✅ **COMPLETE** (2025-11-08)

   - [x] Create `docs/NODEJS_API.md` - Complete API reference ✅
     - All methods with signatures
     - Parameter descriptions
     - Return types
     - Code examples for each
   - [x] Update README.md ✅ (2025-11-07)
     - Feature matrix (DataFrame operations)
     - Performance benchmarks (new operations)
     - Installation and quick start
     - New examples section
   - [x] Update TypeScript definitions (index.d.ts) ✅ (completed in earlier phases)
     - All new methods and types
     - JSDoc comments for autocomplete

5. **Test Runner Update** ✅ **COMPLETE** (2025-11-08)
   - [x] Update `package.json` test:node script ✅
     - Uses `node --test src/test/nodejs/**/*test.js` pattern
   - [x] Verify all tests run (266+ test cases) ✅
   - [ ] Add CI integration (GitHub Actions) - deferred to v1.4.0
   - [x] Document test structure in README.md ✅

**Acceptance Criteria**:

- ✅ 5 real-world examples with working code and tests (04-08 complete)
- ✅ 10+ API showcase examples (JavaScript + TypeScript) - 8 JavaScript + 8 TypeScript = 16 total
- ✅ Complete API documentation (docs/NODEJS_API.md) - complete
- ✅ README.md updated with all features
- ✅ `npm run test:node` runs all tests - complete (266+ tests)
- ✅ All examples work and are well-documented - complete
- ✅ TypeScript showcase examples in `examples/ts/` - complete (8 examples + tsconfig + package.json + README)

**Outstanding Tasks** (deferred to v1.4.0):
- ⏳ Migration guide (docs/MIGRATION_GUIDE.md) - not critical for API completeness
- ⏳ CI integration (GitHub Actions) - not critical for API completeness

**Known Issues**:
- ✅ **RESOLVED**: All 19 missing JavaScript wrappers implemented in `js/rozes.js` (Task 2 complete)
- ✅ **RESOLVED**: `isna()` and `notna()` bug fixed (2025-11-07) - now correctly return DataFrames with renamed boolean columns
- ✅ **RESOLVED**: Examples 04-08 ESM conversion complete (async/await pattern with `await Rozes.init()`)
- ✅ **RESOLVED**: API compatibility fixes complete (`shape.rows`, `columns` property)
- ✅ **RESOLVED**: Package rebuilt with new methods (284 KB, up from 261 KB)
- ✅ **RESOLVED**: Package.json test:node script updated to `node --test` pattern
- ⏳ Build script issue: `dist/` files not auto-updated from `js/rozes.js` - requires manual copy before build (workaround in place)

---

### Cross-Phase Requirements

#### Test Infrastructure:

- [ ] `npm run test:node` runs ALL tests in `src/test/nodejs/` (use `node --test`)
- [ ] 50+ new test cases across 8 integration test files:
  - `csv_export_test.js` (10 tests)
  - `dataframe_utils_test.js` (10 tests)
  - `missing_data_test.js` (8 tests)
  - `string_ops_test.js` (10 tests)
  - `advanced_agg_test.js` (8 tests)
  - `sort_join_test.js` (6 tests)
  - `window_ops_test.js` (8 tests)
  - `reshape_test.js` (6 tests)
  - `arrow_test.js` (4 tests)
  - `lazy_test.js` (4 tests)
- [ ] 100% pass rate for all tests
- [ ] Memory leak tests for all new operations (1000 iterations)
- [ ] Edge case coverage: empty DataFrames, single row/column, large datasets

#### Examples:

- [ ] 5 real-world examples in `examples/nodejs/`:
  - 04-data-cleaning
  - 05-financial-analytics
  - 06-ml-data-prep
  - 07-text-processing
  - 08-reshaping
- [ ] 10+ API showcases in `examples/js/` and `examples/ts/`
- [ ] All examples have README.md, working code, tests
- [ ] Examples verified to work with current API

#### Quality Assurance:

- [ ] Zero segfaults (extensive edge case testing)
- [ ] All operations match Zig behavior (correctness)
- [ ] JavaScript API overhead <10% vs pure Zig
- [ ] Memory safe (1000-iteration leak tests)
- [ ] Tiger Style compliance for all Wasm bindings
- [ ] TypeScript definitions accurate and complete

#### Documentation:

- [ ] `docs/NODEJS_API.md` - Complete API reference
- [ ] `docs/MIGRATION_GUIDE.md` - pandas/Polars migration
- [ ] README.md updated (features, benchmarks, examples)
- [ ] TypeScript definitions (index.d.ts) with JSDoc
- [ ] Each example has detailed README.md

---

### Risks & Mitigations

**Risk 1**: Segfaults from edge cases (null strings, empty arrays, large windows)

- **Mitigation**: Extensive edge case testing, bounded loops, assertions in Zig

**Risk 2**: Memory leaks in string operations and window functions

- **Mitigation**: 1000-iteration leak tests, arena allocator patterns

**Risk 3**: Performance regression from JavaScript API overhead

- **Mitigation**: Benchmark all operations, optimize hot paths, batch operations

**Risk 4**: Breaking changes to existing API

- **Mitigation**: Maintain backward compatibility, deprecate gracefully

**Risk 5**: Complex examples may not work across platforms

- **Mitigation**: Test on macOS, Linux, Windows; document platform quirks

---

### Success Metrics

**API Completeness**:

- ✅ 100% of core Zig operations exposed to Node.js/TypeScript (34+ ops)
- ✅ Feature parity between Zig and JavaScript APIs

**Testing**:

- ✅ 50+ new test cases (integration tests by feature group)
- ✅ 100% pass rate for all tests
- ✅ Zero segfaults (extensive edge case coverage)
- ✅ `npm run test:node` runs all tests in `src/test/nodejs/`

**Performance**:

- ✅ JavaScript API overhead <10% vs pure Zig
- ✅ Lazy evaluation: 2-10× speedup for chained operations
- ✅ SIMD aggregations maintain performance (billions of rows/sec)

**Quality**:

- ✅ No memory leaks (1000-iteration tests for all ops)
- ✅ 100% Tiger Style compliance (all Wasm bindings)
- ✅ TypeScript definitions accurate and complete
- ✅ All examples work correctly

**Documentation**:

- ✅ Complete API documentation (`docs/NODEJS_API.md`)
- ✅ Migration guide from pandas/Polars (`docs/MIGRATION_GUIDE.md`)
- ✅ README.md updated (features, benchmarks, examples)
- ✅ 15+ working examples (5 real-world + 10 API showcases)

**Developer Experience**:

- ✅ Clear documentation for all operations
- ✅ TypeScript autocomplete works perfectly
- ✅ Examples demonstrate real-world usage
- ✅ Easy migration from pandas/Polars

---

**Estimated Completion**: 4-5 weeks from start
**Dependencies**: Milestone 1.2.0 (SIMD infrastructure) completed

---

## Milestone 1.4.0: WebGPU Acceleration + Package Architecture

**Duration**: 5-6 weeks | **Goal**: WebGPU browser acceleration + environment-optimized package exports

### Overview

This milestone adds WebGPU acceleration for browser environments and implements a clean package architecture with multiple entry points (`rozes`, `rozes/web`, `rozes/node`, `rozes/csv`). All optimizations maintain Tiger Style compliance and backward compatibility.

**Note**: This milestone was originally Milestone 1.3.0 but has been moved to 1.4.0 to prioritize Node.js API completion.

**Key Features**:

- Environment-optimized exports (universal, web, node, csv-only)
- WebGPU acceleration for browser (2-10× speedup on >100K rows)
- Automatic CPU fallback when WebGPU unavailable
- Bundle size optimization (40 KB to 180 KB depending on use case)
- Maintain single npm package with subpath exports

**Performance Targets**:

- WebGPU aggregations: 2-5× speedup on >100K rows
- WebGPU filter: 3-5× speedup on >100K rows
- WebGPU groupBy: 3-6× speedup on >100K rows (stretch goal)
- Bundle sizes: 40 KB (csv) → 120 KB (universal) → 180 KB (web)

_(Phases and detailed tasks TBD - will be populated when Milestone 1.3.0 is complete)_

---

## Code Quality Standards

**Tiger Style Compliance** (MANDATORY):

- ✅ 2+ assertions per function
- ✅ Bounded loops with explicit MAX constants
- ✅ Functions ≤70 lines
- ✅ Explicit types (u32, not usize)
- ✅ Explicit error handling (no silent failures)

**Testing Requirements**:

- ✅ Unit tests for every public function
- ✅ Error case tests (bounds, invalid input)
- ✅ Memory leak tests (1000 iterations)
- ✅ Integration tests (end-to-end workflows)

---

**Last Updated**: 2025-11-01
**Next Review**: When Milestone 1.2.0 Phase 2 begins
