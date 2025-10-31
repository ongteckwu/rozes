# Rozes DataFrame Library - Development TODO

**Version**: 1.1.0 (planned) | **Last Updated**: 2025-10-31

---

## Current Status

**Milestone 1.0.0**: ✅ **COMPLETE** (Released 2025-10-31)
- 461/463 tests passing (99.6%)
- 6/6 benchmarks passing
- 100% RFC 4180 CSV compliance
- Node.js npm package published
- TypeScript type definitions
- Tiger Style compliant

**Milestone 1.1.0**: 🎯 **NEXT** (Planned 2-3 weeks)
**Goal**: Remove df.free() requirement + Expose full DataFrame API to Node.js

---

## Milestone 1.1.0 Roadmap

**Timeline**: 2-3 weeks | **Status**: 🎯 **PLANNED**

**Goal**: Automatic memory management + Full DataFrame API in Node.js

---

### Priority 1: Automatic Memory Management (Week 1) - 🔥 **TOP PRIORITY**

**Goal**: Remove df.free() requirement with optional automatic cleanup

**Why this is Priority 1**: Users currently must call `df.free()` manually. WASM memory is separate from JavaScript heap, so GC doesn't free it automatically. This is the #1 pain point for Node.js users.

**Approach**: Hybrid system with FinalizationRegistry
- Default: `autoCleanup: false` (manual free required - safe for production)
- Opt-in: `autoCleanup: true` (automatic cleanup on GC - convenience for prototyping)

**Tasks**:

- [ ] Implement FinalizationRegistry-based auto cleanup (4h)
  ```typescript
  const registry = new FinalizationRegistry((handle) => {
    wasm.instance.exports.rozes_free(handle);
  });

  class DataFrame {
    constructor(handle, wasm, autoCleanup = false) {
      this._handle = handle;
      this._wasm = wasm;
      this._freed = false;

      if (autoCleanup) {
        registry.register(this, handle, this);
      }
    }

    free() {
      if (!this._freed) {
        registry.unregister(this);
        this._wasm.instance.exports.rozes_free(this._handle);
        this._freed = true;
      }
    }
  }
  ```
- [ ] Add `autoCleanup` option to DataFrame constructor (1h)
- [ ] Add comprehensive documentation (3h)
  - Tradeoffs: deterministic vs non-deterministic cleanup
  - When to use auto vs manual
  - Memory pressure considerations
  - **Recommendation**: Use manual for production, auto for prototyping
- [ ] Test with large datasets (1000+ DataFrames) (2h)
- [ ] Browser compatibility testing (Chrome 84+, Firefox 79+, Safari 14.1+) (1h)

**Estimated**: 12 hours (1.5 days)

**Tradeoffs Documented**:

**✅ Advantages**:
- Better DX: No manual memory management
- Prevents leaks: Automatic cleanup when DF goes out of scope
- Backward compatible: Manual `free()` still works

**❌ Disadvantages**:
- Non-deterministic cleanup: GC runs when it wants
- Memory pressure: 1000 DataFrames in loop → memory grows until GC runs
- Performance unpredictable: GC pauses can be 10-100ms
- Debugging harder: Memory leaks harder to track

**Acceptance**:
- Auto cleanup works correctly (no premature GC) ✅
- Manual free() still available and preferred for production ✅
- Documentation clearly explains tradeoffs ✅
- Tests pass on all supported browsers ✅

---

### Priority 2: Node.js API Extension - Core Operations (Week 1)

**Goal**: Expose essential DataFrame operations to Node.js

**Tasks**:

- [ ] Add WASM exports for core operations (6h)
  - `rozes_filter()` - Filter rows by predicate
  - `rozes_select()` - Select columns
  - `rozes_head()` / `rozes_tail()` - Get first/last N rows
  - `rozes_sort()` - Single column sort
- [ ] Implement TypeScript wrappers in `dist/index.js` (8h)
  - `df.filter(columnName, operator, value)`
  - `df.select(columnNames)`
  - `df.head(n)` / `df.tail(n)`
  - `df.sort(columnName, descending)`
- [ ] Add TypeScript definitions to `dist/index.d.ts` (2h)
- [ ] Write tests for all new operations (2h)
- [ ] Update examples with new operations (2h)

**Estimated**: 20 hours (2-3 days)

**Acceptance**:
- All 4 operations work correctly in Node.js ✅
- TypeScript autocomplete works ✅
- Tests passing ✅
- Examples demonstrate chaining (filter → select → sort) ✅

---

### Priority 3: Advanced DataFrame Operations (Week 2)

**Goal**: GroupBy and Join operations for Node.js

**Tasks**:

- [ ] Add WASM exports for aggregations (8h)
  - `rozes_groupby()` - Group by columns
  - `rozes_aggregate()` - Apply aggregation functions
  - Support: `sum`, `mean`, `count`, `min`, `max`
- [ ] Add WASM exports for joins (8h)
  - `rozes_join()` - Join two DataFrames
  - Support: `inner`, `left`, `right`, `outer`, `cross`
- [ ] Implement TypeScript wrappers (6h)
  - `df.groupBy(columns).sum(column)` - Chaining API
  - `df.groupBy(columns).mean(column)`
  - `df.join(other, { on, how })`
- [ ] Add TypeScript definitions (2h)
  ```typescript
  groupBy(columns: string[]): GroupBy;
  interface GroupBy {
    sum(column: string): DataFrame;
    mean(column: string): DataFrame;
    count(): DataFrame;
    min(column: string): DataFrame;
    max(column: string): DataFrame;
  }
  join(other: DataFrame, options: JoinOptions): DataFrame;
  ```
- [ ] Write comprehensive tests (4h)
- [ ] Update benchmarks (2h)

**Estimated**: 30 hours (3-4 days)

**Acceptance**:
- GroupBy with 5 aggregations works ✅
- Join with 5 types works ✅
- Chaining API functional ✅
- Performance maintained (no regression) ✅

---

### Priority 4: String & Boolean Column Access (Week 2)

**Goal**: Full column type support in Node.js

**Current limitation**: `df.column(name)` only returns numeric types (Int64, Float64)

**Tasks**:

- [ ] Add WASM exports for string columns (4h)
  - `rozes_getColumnString()` - Return string array
  - Handle UTF-8 encoding/decoding
- [ ] Add WASM exports for boolean columns (2h)
  - `rozes_getColumnBool()` - Return boolean array
- [ ] Update TypeScript wrappers (2h)
  - `df.column(name)` returns String[] or Boolean[] as appropriate
  - Detect column type and return correct array type
- [ ] Update TypeScript definitions (1h)
  ```typescript
  column(name: string): Float64Array | Int32Array | BigInt64Array | string[] | boolean[] | null;
  ```
- [ ] Write tests for all column types (2h)

**Estimated**: 11 hours (1-2 days)

**Acceptance**:
- String columns accessible ✅
- Boolean columns accessible ✅
- TypeScript types correct ✅
- Tests passing ✅

---

### Priority 5: CSV Export (Week 3)

**Goal**: Implement toCSV() and toCSVFile()

**Current limitation**: Can parse CSV but can't export back to CSV

**Tasks**:

- [ ] Implement WASM export function (8h)
  - `rozes_toCSV()` - Serialize DataFrame to CSV string
  - Handle quoted fields correctly (RFC 4180 compliance)
  - Support options: delimiter, quoteChar, includeHeader
- [ ] Add TypeScript wrapper (2h)
  - `df.toCSV(options)` - Return CSV string
  - `df.toCSVFile(path, options)` - Write to file (Node.js only)
- [ ] CSV options support (2h)
  ```typescript
  interface CSVExportOptions {
    delimiter?: string;
    quoteChar?: string;
    includeHeader?: boolean;
    quoteAll?: boolean;
  }
  ```
- [ ] Handle edge cases (4h)
  - Quoted fields with embedded commas
  - Quoted fields with embedded newlines
  - Double-quote escaping
  - UTF-8 encoding
- [ ] Write tests against RFC 4180 conformance suite (4h)

**Estimated**: 20 hours (2-3 days)

**Acceptance**:
- toCSV() returns valid RFC 4180 CSV ✅
- toCSVFile() writes correct CSV to disk ✅
- All edge cases handled ✅
- Conformance tests pass ✅

---

## Success Criteria (1.1.0 Release)

**Automatic Memory Management**:
- ✅ Optional auto cleanup via FinalizationRegistry
- ✅ Manual free() still available and preferred for production
- ✅ Comprehensive documentation on tradeoffs
- ✅ Browser compatibility (Chrome 84+, Firefox 79+, Safari 14.1+)

**Node.js API**:
- ✅ Filter, select, head, tail, sort available
- ✅ GroupBy with 5 aggregation functions
- ✅ Join (inner, left, right, outer, cross) available
- ✅ String and boolean column access
- ✅ CSV export (toCSV, toCSVFile)

**Testing**:
- ✅ All new operations have unit tests
- ✅ Integration tests for chained operations
- ✅ Memory leak tests with auto cleanup enabled
- ✅ Browser compatibility tests

**Documentation**:
- ✅ NODEJS_API.md updated with all new operations
- ✅ Examples showing filter, groupBy, join
- ✅ Migration guide updated (Papa Parse → Rozes)
- ✅ CHANGELOG.md with all changes
- ✅ README.md updated

**Performance**:
- ✅ No regression in existing benchmarks
- ✅ New operations meet performance targets

**Total Estimate**: 93 hours (2-3 weeks across 5 priorities)

---

## Future Milestones (1.2.0+)

**Reshape & Combine Operations** (1.2.0):
- Pivot, melt, transpose
- Concat, merge, append
- Estimated: 27 hours (3-4 days)

**Statistical & Window Operations** (1.3.0):
- Window functions (rolling, expanding)
- Statistical functions (corr, cov, rank, describe)
- Estimated: 45 hours (5-6 days)

**Advanced Optimizations** (1.4.0+):
- SIMD aggregations (30% groupby speedup)
- Radix hash join for integer keys (2-3× speedup)
- Parallel CSV type inference (2-4× faster)
- Parallel DataFrame operations (2-6× on large data)
- Apache Arrow compatibility layer
- Lazy evaluation & query optimization (2-10× chained ops)

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

**Last Updated**: 2025-10-31
**Next Review**: When Milestone 1.1.0 tasks begin
