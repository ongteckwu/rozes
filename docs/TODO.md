# Rozes DataFrame Library - Development TODO

**Version**: 0.6.0 (planning) | **Last Updated**: 2025-10-30

---

## Current Status

**Milestone 0.6.0**: Core Operations & Advanced Features
**Progress**: `[______________] 0%` 🚧 **PLANNING**

| Phase | Status | Progress | Est. Time | Actual Time |
|-------|--------|----------|-----------|-------------|
| 1. Pivot & Reshape | 🚧 Planning | 0% | 3 days | - |
| 2. Concat & Merge | 🚧 Planning | 0% | 3 days | - |
| 3. Apply & Map Operations | 🚧 Planning | 0% | 2 days | - |
| 4. Join Optimization | 🚧 Planning | 0% | 2 days | - |
| 5. Documentation & Testing | 🚧 Planning | 0% | 1 day | - |

**Goal**: Add essential reshape operations (pivot, concat, merge), user-defined functions (apply, map), and optimize join performance.

**Focus**: Core DataFrame reshaping (pivot/unpivot, concat, merge), functional programming (apply/map), join optimization to meet <500ms target.

**Foundation**: 258+ tests passing, 4/5 benchmarks (join needs optimization), 100% RFC 4180 conformance, zero memory leaks, Tiger Style compliant.

---

## Completed Milestones

**✅ 0.5.0** (2025-10-30, 5 days): JSON parsing (NDJSON/Array/Columnar), rich error messages, manual schema, categorical deep copy, value counts, enhanced rank. 258+ tests, 4/5 benchmarks (join 605ms).

**✅ 0.4.0** (2025-10-28, 5.5 days): Window ops, string ops, categorical type, stats functions, missing value handling. 258/264 tests, 4/5 benchmarks.

**✅ 0.3.0** (2025-10-28, 4.5 days): Sort, GroupBy, Join, SIMD infrastructure. CSV 555ms, Join 593ms (19% over target).

**✅ 0.2.0** (2025-10-28, 1.5 days): String/Boolean columns, UTF-8 support, 125/125 RFC 4180 conformance.

**✅ 0.1.0** (2025-10-27, 4 weeks): Core DataFrame engine, CSV parser, 74KB WASM, 83 unit tests.

**✅ External Conformance** (2025-10-28): 139 tests from 6 libraries (Polars, pandas, DuckDB, csv-spectrum, PapaParse, univocity). 99% pass rate (136/137).

---

## Milestone 0.6.0 - Core Operations & Advanced Features

**Timeline**: 11 days | **Status**: 🚧 **PLANNING**

**Goal**: Add essential DataFrame reshape operations (pivot, concat, merge), enable user-defined functions (apply, map), and optimize join performance to meet benchmark targets.

### Phase 1: Pivot & Reshape Operations (Days 1-3) - 🚧 **NOT STARTED**

**Goal**: Implement pivot tables and reshape operations (wide ↔ long format)

#### Day 1: Pivot Table Implementation (1 day)

**Tasks**:
- [ ] Implement `pivot()` in `src/core/reshape.zig` (new module)
- [ ] Support aggregation functions (sum, mean, count, min, max)
- [ ] Handle duplicate values (aggregate automatically)
- [ ] Support multi-value columns
- [ ] Create 10+ unit tests for pivot
- [ ] Test with large datasets (10K rows → pivoted)

**API Design**:
```zig
// Transform long format → wide format
const pivoted = try df.pivot(allocator, .{
    .index = "date",           // Row labels
    .columns = "region",       // Column labels
    .values = "sales",         // Values to aggregate
    .aggfunc = .sum,          // Aggregation function
});
defer pivoted.deinit();
```

**Features**:
- Multiple aggregation functions (sum, mean, count, min, max, std)
- Automatic handling of missing combinations (fill with NaN)
- Efficient hash-based grouping

**Deliverable**: Pivot tables working with 10+ tests

---

#### Day 2: Unpivot (Melt) Implementation (1 day)

**Tasks**:
- [ ] Implement `melt()` in `src/core/reshape.zig`
- [ ] Transform wide format → long format
- [ ] Support variable/value column naming
- [ ] Handle id_vars (columns to preserve)
- [ ] Create 10+ unit tests for melt
- [ ] Round-trip test (pivot → melt → pivot)

**Deliverable**: Melt working with 10+ tests, round-trip verified

---

#### Day 3: Transpose & Stack/Unstack (1 day)

**Tasks**:
- [ ] Implement `transpose()` - swap rows and columns
- [ ] Implement `stack()` - collapse column level to row level
- [ ] Implement `unstack()` - pivot row level to column level
- [ ] Create 10+ unit tests for each operation
- [ ] Performance test (1K rows, 100 columns → transpose)

**Deliverable**: All 3 reshape operations working with 30+ tests

---

### Phase 2: Concat & Merge Operations (Days 4-6) - 🚧 **NOT STARTED**

**Goal**: Combine DataFrames vertically and horizontally with SQL-style merge

#### Day 4: Concat Implementation (1 day)

**Tasks**:
- [ ] Implement `concat()` in `src/core/combine.zig` (new module)
- [ ] Support vertical stacking (axis=0, row-wise)
- [ ] Support horizontal stacking (axis=1, column-wise)
- [ ] Handle missing columns (fill with NaN)
- [ ] Ignore index option (default: false)
- [ ] Create 10+ unit tests for concat
- [ ] Test with mismatched schemas

**API Design**:
```zig
// Vertical concat (stack rows)
const combined = try DataFrame.concat(allocator, &[_]*DataFrame{df1, df2, df3}, .{
    .axis = .vertical,  // Stack rows (default)
    .ignore_index = false,
});
defer combined.deinit();
```

**Features**:
- Automatic schema alignment (add missing columns with NaN)
- Type checking (reject incompatible column types)
- Efficient bulk copying

**Deliverable**: Concat working for vertical/horizontal with 10+ tests

---

#### Day 5: Merge Implementation (1 day)

**Tasks**:
- [ ] Implement `merge()` in `src/core/combine.zig`
- [ ] Support merge strategies (inner, left, right, outer, cross)
- [ ] Handle multiple keys (multi-column merge)
- [ ] Suffix handling for overlapping columns
- [ ] Create 10+ unit tests for merge
- [ ] Test all 5 merge types

**Merge Types**:
- **inner**: Only matching keys (intersection)
- **left**: All from left, matching from right
- **right**: All from right, matching from left
- **outer**: All keys from both (union)
- **cross**: Cartesian product (all combinations)

**Deliverable**: Merge working for all 5 types with 10+ tests

---

#### Day 6: Append & Update Operations (1 day)

**Tasks**:
- [ ] Implement `append()` - add rows to existing DataFrame
- [ ] Implement `update()` - modify values based on another DataFrame
- [ ] Support in-place and copy modes
- [ ] Create 10+ unit tests for append/update
- [ ] Performance test (append 10K rows in batches)

**Deliverable**: Append/update working with 10+ tests

---

### Phase 3: Apply & Map Operations (Days 7-8) - 🚧 **NOT STARTED**

**Goal**: Enable user-defined functions for custom transformations

#### Day 7: Apply Implementation (1 day)

**Tasks**:
- [ ] Implement `apply()` in `src/core/functional.zig` (new module)
- [ ] Support row-wise and column-wise functions
- [ ] Type-safe function signatures using comptime
- [ ] Create 10+ unit tests for apply
- [ ] Performance test (apply to 100K rows)

**API Design**:
```zig
// Apply function to each row
fn calculateDiscount(row: RowRef) f64 {
    const price = row.getFloat64("price") orelse return 0;
    const quantity = row.getInt64("quantity") orelse return 0;
    return price * @as(f64, @floatFromInt(quantity)) * 0.1;
}

const discounts = try df.apply(allocator, calculateDiscount, .{
    .axis = .rows,       // Apply to each row
    .result_type = .Float64,
});
defer discounts.deinit();
```

**Features**:
- Comptime type checking (function signature validation)
- Support for Series → Series (column operations)
- Support for RowRef → Value (row operations)

**Deliverable**: Apply working for rows/columns with 10+ tests

---

#### Day 8: Map & Filter with Functions (1 day)

**Tasks**:
- [ ] Implement `map()` for element-wise transformations
- [ ] Implement `filter()` overload with custom functions
- [ ] Support lambda-style inline functions
- [ ] Create 10+ unit tests for map/filter
- [ ] Chain operations test (map → filter → apply)

**Deliverable**: Map/filter with functions, chaining tested

---

### Phase 4: Join Optimization (Days 9-10) - 🚧 **NOT STARTED**

**Goal**: Reduce join time from 605ms to <500ms (currently 20.9% over target)

**Current Performance**: 605ms for 10K × 10K inner join

#### Day 9: Profiling & Batch Copying (1 day)

**Tasks**:
- [ ] Profile join operation with sampling profiler
- [ ] Identify top 3 bottlenecks (hash build, probe, data copy)
- [ ] Implement batch `memcpy` for column data (32 rows at once)
- [ ] Pre-allocate result DataFrame with capacity hint
- [ ] Benchmark after batch copying
- [ ] Target: 605ms → <500ms (≥17% improvement)

**Optimization Strategy**:
```zig
// Batch copy 32 rows at once
const BATCH_SIZE = 32;
var batch_indices: [BATCH_SIZE]u32 = undefined;
var batch_count: u32 = 0;

for (matches.items) |match| {
    batch_indices[batch_count] = match.left_idx;
    batch_count += 1;

    if (batch_count == BATCH_SIZE) {
        copyRowsBatch(result, left_df, batch_indices[0..BATCH_SIZE]);  // ✅ Fast
        batch_count = 0;
    }
}
```

**Expected Bottlenecks**:
1. Data copying (~40-60% of time)
2. Hash table probes (~20-30%)
3. Memory allocations (~10-20%)

**Deliverable**: Join time <500ms, profiling report

---

#### Day 10: SIMD Optimization & Final Tuning (1 day)

**Tasks**:
- [ ] Use SIMD for numeric column copying (if available)
- [ ] Optimize hash table parameters (load factor, capacity)
- [ ] Final profiling and micro-optimizations
- [ ] Verify all join types still work (inner, left, right, outer)
- [ ] Benchmark suite verification (target: <500ms)
- [ ] Update join tests with new performance expectations

**SIMD Strategy** (optional):
- Use SIMD batch copy for Int64/Float64 columns (16 bytes at once)
- Expected: 5-10% additional speedup

**Deliverable**: Join time <500ms, all tests passing, **5/5 benchmarks met**

---

### Phase 5: Documentation & Testing (Day 11) - 🚧 **NOT STARTED**

**Goal**: Update documentation, run final tests, verify benchmarks

**Tasks**:
- [ ] Update `docs/FEATURES.md` with pivot/reshape operations
- [ ] Update `docs/FEATURES.md` with concat/merge operations
- [ ] Update `docs/FEATURES.md` with apply/map operations
- [ ] Run comprehensive benchmark suite (all 5 benchmarks must pass)
- [ ] Verify 0 memory leaks across all new features
- [ ] Update `docs/TODO.md` (mark 0.6.0 complete)
- [ ] Create `docs/MIGRATION_0.5_to_0.6.md` (breaking changes if any)

**Benchmarks** (All Must Pass):
- CSV Parse (1M rows): <3000ms (current: 645ms ✅)
- Filter (1M rows): <100ms (current: 11ms ✅)
- Sort (100K rows): <100ms (current: 10ms ✅)
- GroupBy (100K rows): <300ms (current: 1.7ms ✅)
- **Join (10K × 10K): <500ms (current: 605ms ❌ → MUST FIX)**

**Deliverable**: 0.6.0 release-ready documentation, **5/5 benchmarks passing**

---

## Milestone 0.6.0 Success Criteria

- ✅ **Pivot & Reshape**: pivot(), melt(), transpose(), stack(), unstack() (40+ tests)
- ✅ **Concat & Merge**: concat(), merge() (5 types), append(), update() (30+ tests)
- ✅ **Apply & Map**: apply(), map(), custom functions (20+ tests)
- ✅ **Join Optimization**: <500ms for 10K × 10K inner join (currently 605ms) **CRITICAL**
- ✅ 340+ unit tests passing (80+ new)
- ✅ **5/5 benchmarks passing** (join optimization is BLOCKING)
- ✅ 0 memory leaks (1000-iteration stress tests)
- ✅ Tiger Style compliant (all new code)
- ✅ Documentation updated (FEATURES.md, TODO.md, MIGRATION.md)

---

## Milestone 1.0.0 - Production Release (FUTURE)

**Tasks**: API finalization, Node.js N-API addon, npm publication, benchmarking report, community readiness
**Targets**: Filter 1M <100ms, Sort 1M <500ms, GroupBy 100K <300ms, Join 100K×100K <2s, 182+ conformance tests

---

## Development Guidelines

### Quick Commands

```bash
# Format code
zig fmt src/

# Build WASM module
zig build

# Run ALL tests (unit + conformance)
zig build test

# Run conformance tests only
zig build conformance

# Serve browser tests
python3 -m http.server 8080
# Navigate to http://localhost:8080/js/test.html
```

### Code Quality Standards

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
- ✅ Performance benchmarks

**Documentation**:

- ✅ Top-level module comments
- ✅ Public function documentation
- ✅ Example usage in comments
- ✅ References to RFC.md sections

### Git Workflow

**Before Committing**:

1. Run `zig fmt src/`
2. Run `zig build test` (all tests must pass)
3. Run `zig build conformance` (139/139 must pass)
4. Verify Tiger Style compliance
5. Update TODO.md with completed tasks

**Commit Message Format**:

```
<type>(<scope>): <subject>

Types: feat, fix, docs, style, refactor, test, chore

Examples:
feat(reshape): add pivot table implementation
fix(join): optimize batch copying for 20% speedup
test(merge): add comprehensive tests for all merge types
```

---

## Notes & Decisions

### Join Optimization Target (2025-10-30)

**Current**: 605ms for 10K × 10K inner join (20.9% over 500ms target)
**Priority**: CRITICAL for 0.6.0 (blocking 5/5 benchmark success)
**Approach**: Batch copying (32 rows), SIMD for numeric columns, hash table tuning
**Expected**: ~17-25% improvement needed

### Key Design Decisions

- **Trailing delimiter** (2025-10-28): Check `current_col_index > 0` → 125/125 conformance
- **Type inference** (2025-10-27): Unknown/mixed → String (preserve data, no loss)
- **No-header CSV** (2025-10-27): Auto-detect by filename ("no_header")
- **Categorical deep copy** (2025-10-30): Independent dictionaries for filtered/joined DataFrames
- **Manual schema** (2025-10-30): Override auto-detection for specific columns

---

**Last Updated**: 2025-10-30
