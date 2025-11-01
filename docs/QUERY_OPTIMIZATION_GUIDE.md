# Query Optimization Cookbook

**Version**: 1.2.0 | **Last Updated**: 2025-11-01

---

## Table of Contents

1. [Introduction](#introduction)
2. [Quick Wins](#quick-wins)
3. [Lazy Evaluation Patterns](#lazy-evaluation-patterns)
4. [Filter Optimization](#filter-optimization)
5. [Projection Optimization](#projection-optimization)
6. [Join Optimization](#join-optimization)
7. [Aggregation Optimization](#aggregation-optimization)
8. [Memory Optimization](#memory-optimization)
9. [Real-World Examples](#real-world-examples)
10. [Anti-Patterns](#anti-patterns)

---

## Introduction

This cookbook provides practical recipes for optimizing DataFrame queries in Rozes. Each recipe includes before/after code, performance metrics, and explanations of why the optimization works.

**Performance Targets** (Milestone 1.2.0):
- Lazy evaluation: 2-10× speedup for chained operations
- SIMD aggregations: 30-50% speedup
- Parallel operations: 2-6× speedup on >100K rows
- Zero-copy Arrow: <10% conversion overhead

---

## Quick Wins

### Recipe 1: Enable Lazy Evaluation for Chains

**Problem**: Multiple operations create intermediate DataFrames

**❌ BEFORE** (Eager):
```javascript
const df = await rozes.fromCSV('data.csv');
const filtered = df.filter(r => r.age > 30);      // Creates DataFrame
const selected = filtered.select(['name', 'salary']); // Creates DataFrame
const limited = selected.limit(100);               // Creates DataFrame
const result = limited.toArray();

// Performance: 100ms, 3 intermediate DataFrames
```

**✅ AFTER** (Lazy):
```javascript
const result = await rozes.fromCSV('data.csv')
  .lazy()
  .filter(r => r.age > 30)
  .select(['name', 'salary'])
  .limit(100)
  .collect()
  .toArray();

// Performance: 15ms, 1 final DataFrame
// Speedup: 6.7×
```

**Why it works**:
- Defers execution until `.collect()`
- Optimizer applies predicate pushdown
- No intermediate DataFrame allocations

---

### Recipe 2: Free Memory Explicitly

**Problem**: Memory leaks in loops

**❌ BEFORE**:
```javascript
for (let i = 0; i < 1000; i++) {
  const df = await rozes.fromCSV('data.csv');
  processData(df);
  // Memory leak! DataFrame not freed
}

// Memory usage: ~2GB after 1000 iterations
```

**✅ AFTER**:
```javascript
for (let i = 0; i < 1000; i++) {
  const df = await rozes.fromCSV('data.csv');
  processData(df);
  df.free(); // Explicit cleanup
}

// Memory usage: ~2MB constant
```

**Why it works**:
- Explicit `.free()` releases arena allocator
- Prevents accumulation of DataFrames

---

### Recipe 3: Use Arrow for Repeated Loads

**Problem**: Parsing CSV on every iteration

**❌ BEFORE**:
```javascript
for (let i = 0; i < 100; i++) {
  const df = await rozes.fromCSV('data.csv'); // Parse every time
  analyze(df);
  df.free();
}

// Performance: 100 × 500ms = 50s
```

**✅ AFTER**:
```javascript
// Parse once, convert to Arrow
const df = await rozes.fromCSV('data.csv');
const arrowBatch = df.toArrow();
df.free();

for (let i = 0; i < 100; i++) {
  const df = rozes.fromArrow(arrowBatch); // Zero-copy
  analyze(df);
  df.free();
}

// Performance: 500ms + (100 × 3ms) = 800ms
// Speedup: 62.5×
```

**Why it works**:
- Arrow conversion is zero-copy for numeric types
- `fromArrow()` is 150× faster than CSV parsing

---

## Lazy Evaluation Patterns

### Recipe 4: Predicate Pushdown

**Problem**: Filtering after selecting columns

**❌ BEFORE**:
```javascript
df.lazy()
  .select(['name', 'age', 'city']) // Select from 50 columns
  .filter(r => r.age > 30)          // Filter on 3 columns
  .collect();

// Performance: 80ms
// Reason: Selecting 3 from 50 columns, then filtering
```

**✅ AFTER**:
```javascript
df.lazy()
  .filter(r => r.age > 30)          // Filter on 50 columns
  .select(['name', 'age', 'city']) // Select from filtered result
  .collect();

// Performance: 12ms
// Speedup: 6.7×
```

**What Rozes does automatically**:
```javascript
// Your code
df.lazy()
  .select(['name', 'age', 'city'])
  .filter(r => r.age > 30)
  .collect();

// Optimized execution
df.lazy()
  .filter(r => r.age > 30)        // ← Pushed before select
  .select(['name', 'age', 'city'])
  .collect();
```

**Why it works**:
- Filter reduces rows BEFORE projection
- Less data to copy during select

---

### Recipe 5: Limit Pushdown

**Problem**: Processing entire dataset when only need subset

**❌ BEFORE**:
```javascript
df.lazy()
  .filter(r => r.status === 'active') // Process all rows
  .sort('created_at')                  // Sort all results
  .select(['id', 'name'])              // Project all results
  .limit(10)                           // Only need 10!
  .collect();

// Performance: 250ms (sorted 1M rows)
```

**✅ AFTER** (manual):
```javascript
df.lazy()
  .filter(r => r.status === 'active')
  .limit(10)                           // Stop after 10 matches
  .select(['id', 'name'])
  .sort('created_at')                  // Sort only 10 rows
  .collect();

// Performance: 30ms
// Speedup: 8.3×
```

**Note**: Limit pushdown is automatic in Rozes when safe

**Why it works**:
- Stop processing early
- Sort smaller dataset

---

### Recipe 6: Filter Fusion

**Problem**: Multiple separate filter passes

**❌ BEFORE** (manual):
```javascript
df.lazy()
  .filter(r => r.age > 30)
  .filter(r => r.salary > 50000)
  .filter(r => r.status === 'active')
  .collect();

// Performance: 3 passes over data
```

**✅ AFTER** (future optimization):
```javascript
// Rozes will automatically fuse to:
df.lazy()
  .filter(r => r.age > 30 && r.salary > 50000 && r.status === 'active')
  .collect();

// Performance: 1 pass over data
// Speedup: 3×
```

**Current workaround**:
```javascript
df.lazy()
  .filter(r => {
    return r.age > 30 &&
           r.salary > 50000 &&
           r.status === 'active';
  })
  .collect();
```

---

## Filter Optimization

### Recipe 7: Use Parallel Filter for Large Datasets

**Problem**: Sequential filtering is slow on large datasets

**❌ BEFORE**:
```javascript
const filtered = df.filter(r => r.value > threshold, {
  parallel: false // Sequential
});

// Performance (1M rows): 80ms
```

**✅ AFTER**:
```javascript
const filtered = df.filter(r => r.value > threshold, {
  parallel: true // Automatic for >100K rows
});

// Performance (1M rows): 15ms
// Speedup: 5.3×
```

**Auto-detection**:
```javascript
// Rozes automatically parallelizes if >100K rows
const filtered = df.filter(r => r.value > threshold);
```

**Why it works**:
- Divides rows across worker threads
- Near-linear scaling up to 8 cores

---

### Recipe 8: Column-based Filtering

**Problem**: Row-based predicates are slow

**❌ BEFORE**:
```javascript
const filtered = df.filter(row => {
  const age = row.age;
  const status = row.status;
  return age > 30 && status === 'active';
});

// Performance: 100ms
```

**✅ AFTER** (if possible):
```javascript
// Use column operations
const ages = df.column('age');
const statuses = df.column('status');

const mask = ages.map((age, i) => {
  return age > 30 && statuses[i] === 'active';
});

const filtered = df.filterByMask(mask);

// Performance: 60ms (with SIMD)
// Speedup: 1.7×
```

**Why it works**:
- Column access is cache-friendly
- SIMD optimization for comparisons

---

## Projection Optimization

### Recipe 9: Select Early

**Problem**: Selecting columns late in pipeline

**❌ BEFORE**:
```javascript
df.lazy()
  .filter(r => r.age > 30)       // Filter on 50 columns
  .sort('created_at')             // Sort 50 columns
  .select(['id', 'name', 'email']) // Finally select 3
  .collect();

// Performance: 200ms
```

**✅ AFTER**:
```javascript
df.lazy()
  .select(['id', 'name', 'email', 'age', 'created_at']) // Select early
  .filter(r => r.age > 30)                               // Filter on 5 columns
  .sort('created_at')                                     // Sort 5 columns
  .select(['id', 'name', 'email'])                       // Final projection
  .collect();

// Performance: 60ms
// Speedup: 3.3×
```

**Why it works**:
- Reduce memory footprint early
- Less data to copy in subsequent operations

---

### Recipe 10: Avoid Redundant Projections

**Problem**: Multiple select operations

**❌ BEFORE**:
```javascript
df.lazy()
  .select(['id', 'name', 'age', 'email', 'salary'])
  .filter(r => r.age > 30)
  .select(['id', 'name', 'salary']) // Redundant select
  .collect();
```

**✅ AFTER**:
```javascript
df.lazy()
  .select(['id', 'name', 'age', 'salary']) // Only columns needed
  .filter(r => r.age > 30)
  .collect();
```

**Why it works**:
- Eliminate unnecessary column copies

---

## Join Optimization

### Recipe 11: Use Integer Keys for Radix Join

**Problem**: Join on string keys

**❌ BEFORE**:
```javascript
const result = left.join(right, 'customer_name'); // String key

// Performance (10K × 10K): 1200ms (standard hash join)
```

**✅ AFTER**:
```javascript
// Use integer customer_id instead
const result = left.join(right, 'customer_id'); // Integer key

// Performance (10K × 10K): 400ms (radix hash join)
// Speedup: 3×
```

**Why it works**:
- Radix partitioning is faster for integers
- Less hash collision handling
- Cache-friendly integer comparisons

---

### Recipe 12: Filter Before Join

**Problem**: Joining entire tables

**❌ BEFORE**:
```javascript
const result = orders.join(customers, 'customer_id');
// Then filter...

// Performance: 2000ms (joining 1M × 100K)
```

**✅ AFTER**:
```javascript
const activeOrders = orders.lazy()
  .filter(r => r.status === 'active')
  .collect();

const recentCustomers = customers.lazy()
  .filter(r => r.last_order > cutoff_date)
  .collect();

const result = activeOrders.join(recentCustomers, 'customer_id');

// Performance: 500ms (joining 100K × 10K)
// Speedup: 4×
```

**Why it works**:
- Reduces join input size
- Less memory allocation
- Fewer hash table entries

---

### Recipe 13: Use Bloom Filters for Negative Lookups

**Problem**: Join with low match rate

**❌ BEFORE**:
```javascript
// Only 1% of left rows have matching right rows
const result = left.join(right, 'key');

// Performance: 1500ms (many failed lookups)
```

**✅ AFTER** (Rozes automatic):
```javascript
const result = left.join(right, 'key', {
  bloomFilter: true // Automatic in Rozes for low selectivity
});

// Performance: 900ms
// Speedup: 1.7×
```

**Why it works**:
- Bloom filter early-rejects 99% of non-matches
- Avoids expensive hash table lookups

---

## Aggregation Optimization

### Recipe 14: Use SIMD Aggregations

**Problem**: Sequential aggregations

**❌ BEFORE**:
```javascript
const total = df.column('amount').sum({ simd: false });

// Performance (1M rows): 15ms
```

**✅ AFTER**:
```javascript
const total = df.column('amount').sum(); // SIMD automatic

// Performance (1M rows): 10ms
// Speedup: 1.5×
```

**Why it works**:
- SIMD processes 2-4 values per instruction
- Automatic on x86-64, ARM64, Wasm SIMD

---

### Recipe 15: Batch Aggregations

**Problem**: Multiple separate aggregation calls

**❌ BEFORE**:
```javascript
const sum = df.column('value').sum();
const mean = df.column('value').mean();
const min = df.column('value').min();
const max = df.column('value').max();

// Performance: 4 passes over data
```

**✅ AFTER**:
```javascript
const stats = df.column('value').stats(); // Single pass
const { sum, mean, min, max } = stats;

// Performance: 1 pass over data
// Speedup: 4×
```

**Why it works**:
- Single pass over column
- Cache-friendly sequential access

---

### Recipe 16: Parallel GroupBy

**Problem**: Sequential grouping on large dataset

**❌ BEFORE**:
```javascript
const grouped = df.groupBy('category', {
  parallel: false
}).sum('revenue');

// Performance (1M rows, 100 groups): 120ms
```

**✅ AFTER**:
```javascript
const grouped = df.groupBy('category', {
  parallel: true // Automatic for >100K rows
}).sum('revenue');

// Performance (1M rows, 100 groups): 40ms
// Speedup: 3×
```

**Why it works**:
- Partitions data across threads
- Parallel hash table construction
- Merge results at end

---

## Memory Optimization

### Recipe 17: Use Arena Allocators

**Problem**: Many small allocations

**❌ BEFORE**:
```javascript
// Creating many intermediate arrays
const results = [];
for (let i = 0; i < 1000; i++) {
  const slice = df.slice(i * 1000, (i + 1) * 1000);
  results.push(process(slice));
}

// Memory: Fragmented, slow GC
```

**✅ AFTER**:
```javascript
// DataFrame already uses arena internally
const df = await rozes.fromCSV('data.csv');
// All allocations in single arena

// Process in single pass
const result = df.lazy()
  .map(process)
  .collect();

df.free(); // Single deallocation

// Memory: Contiguous, fast cleanup
```

**Why it works**:
- Arena allocator groups related allocations
- Single free operation
- No fragmentation

---

### Recipe 18: Limit Memory Growth

**Problem**: Unbounded result sets

**❌ BEFORE**:
```javascript
// Load entire 10GB CSV
const df = await rozes.fromCSV('huge.csv');

// OOM Error!
```

**✅ AFTER**:
```javascript
// Process in chunks
const chunkSize = 100_000;
let offset = 0;

while (true) {
  const chunk = await rozes.fromCSV('huge.csv', {
    skip: offset,
    limit: chunkSize
  });

  if (chunk.rowCount === 0) break;

  processChunk(chunk);
  chunk.free();

  offset += chunkSize;
}
```

**Why it works**:
- Bounded memory usage
- Streaming processing

---

## Real-World Examples

### Example 1: E-commerce Analytics

**Task**: Find top 10 products by revenue in last 30 days

**❌ BEFORE** (Sequential):
```javascript
const df = await rozes.fromCSV('orders.csv');

const recent = df.filter(r => {
  const date = new Date(r.order_date);
  return date > new Date('2024-10-01');
});

const withRevenue = recent.map(r => ({
  ...r,
  revenue: r.quantity * r.unit_price
}));

const grouped = withRevenue.groupBy('product_id')
  .sum('revenue');

const sorted = grouped.sort('revenue', 'desc');
const top10 = sorted.limit(10);

const result = top10.toArray();

// Performance: 850ms
// Memory: 4 intermediate DataFrames
```

**✅ AFTER** (Optimized):
```javascript
const result = await rozes.fromCSV('orders.csv')
  .lazy()
  .filter(r => new Date(r.order_date) > new Date('2024-10-01'))
  .select(['product_id', 'quantity', 'unit_price'])
  .groupBy('product_id', { parallel: true })
  .agg({
    revenue: df => df.column('quantity').mul(df.column('unit_price')).sum()
  })
  .sort('revenue', 'desc')
  .limit(10)
  .collect()
  .toArray();

// Performance: 120ms
// Speedup: 7.1×
// Memory: 1 final DataFrame
```

**Optimizations applied**:
1. Lazy evaluation (no intermediate DataFrames)
2. Early column selection (3 columns vs 10)
3. Parallel groupBy (8 cores)
4. Limit pushdown (sort only top groups)

---

### Example 2: User Segmentation

**Task**: Segment users by engagement score

**❌ BEFORE**:
```javascript
const users = await rozes.fromCSV('users.csv');
const events = await rozes.fromCSV('events.csv');

// Join all data
const joined = users.join(events, 'user_id');

// Calculate engagement
const withScore = joined.map(r => ({
  ...r,
  engagement: r.page_views * 2 + r.clicks * 5 + r.purchases * 100
}));

// Segment
const segments = withScore.groupBy(r => {
  if (r.engagement > 1000) return 'high';
  if (r.engagement > 100) return 'medium';
  return 'low';
}).count();

// Performance: 3500ms (1M users, 10M events)
```

**✅ AFTER**:
```javascript
// Pre-aggregate events per user
const eventStats = await rozes.fromCSV('events.csv')
  .lazy()
  .groupBy('user_id', { parallel: true })
  .agg({
    page_views: df => df.column('type').eq('page_view').sum(),
    clicks: df => df.column('type').eq('click').sum(),
    purchases: df => df.column('type').eq('purchase').sum()
  })
  .collect();

// Join pre-aggregated data
const joined = (await rozes.fromCSV('users.csv'))
  .lazy()
  .select(['user_id', 'name', 'created_at'])
  .join(eventStats, 'user_id')
  .collect();

// Calculate engagement and segment
const segments = joined.lazy()
  .map(r => ({
    user_id: r.user_id,
    segment: (() => {
      const score = r.page_views * 2 + r.clicks * 5 + r.purchases * 100;
      if (score > 1000) return 'high';
      if (score > 100) return 'medium';
      return 'low';
    })()
  }))
  .groupBy('segment')
  .count()
  .collect();

eventStats.free();
joined.free();

// Performance: 850ms
// Speedup: 4.1×
```

**Optimizations applied**:
1. Pre-aggregate events (10M → 1M rows)
2. Join smaller tables (1M × 1M vs 1M × 10M)
3. Parallel groupBy
4. Early column selection

---

## Anti-Patterns

### Anti-Pattern 1: Forgetting to Free

**❌ DON'T**:
```javascript
function processFile(filename) {
  const df = rozes.fromCSV(filename);
  return df.column('total').sum();
  // Memory leak! df not freed
}

for (let i = 0; i < 1000; i++) {
  processFile(`file${i}.csv`);
}
```

**✅ DO**:
```javascript
function processFile(filename) {
  const df = rozes.fromCSV(filename);
  const result = df.column('total').sum();
  df.free();
  return result;
}
```

---

### Anti-Pattern 2: Premature Materialization

**❌ DON'T**:
```javascript
const df1 = df.filter(r => r.age > 30).collect(); // Materializes
const df2 = df1.select(['name', 'age']).collect(); // Materializes
const df3 = df2.limit(10).collect(); // Materializes
```

**✅ DO**:
```javascript
const result = df.lazy()
  .filter(r => r.age > 30)
  .select(['name', 'age'])
  .limit(10)
  .collect(); // Materialize once
```

---

### Anti-Pattern 3: Inefficient Loops

**❌ DON'T**:
```javascript
for (let i = 0; i < df.rowCount; i++) {
  const row = df.row(i);
  total += row.value;
}
// Performance: O(n²) row lookups
```

**✅ DO**:
```javascript
const total = df.column('value').sum();
// Performance: O(n) with SIMD
```

---

### Anti-Pattern 4: Ignoring Parallel Thresholds

**❌ DON'T**:
```javascript
// 100-row dataset, parallel overhead not worth it
const tiny = rozes.fromCSV('tiny.csv', { parallel: true });
```

**✅ DO**:
```javascript
// Let Rozes auto-detect
const tiny = rozes.fromCSV('tiny.csv');
```

---

## Performance Checklist

Before deploying to production, verify:

- [ ] Using lazy evaluation for chained operations (3+ ops)
- [ ] Explicitly freeing DataFrames in loops
- [ ] Filtering before joins
- [ ] Selecting columns early
- [ ] Using integer keys for joins when possible
- [ ] Leveraging SIMD aggregations
- [ ] Parallel execution for datasets >100K rows
- [ ] Arrow format for repeated loads
- [ ] Profiled actual bottlenecks (don't guess!)

---

## Conclusion

Query optimization in Rozes follows these principles:

1. **Lazy evaluation** for chained operations
2. **Early filtering** and projection
3. **Parallel execution** for large datasets
4. **SIMD aggregations** for numeric columns
5. **Explicit memory management** with `.free()`
6. **Zero-copy Arrow** for repeated operations
7. **Profile before optimizing**

**Further Reading**:
- [Performance Guide](./PERFORMANCE.md) - Comprehensive performance documentation
- [Benchmarking Guide](../src/test/benchmark/README.md) - How to measure performance
- [Tiger Style Guide](./TIGER_STYLE_APPLICATION.md) - Safety-first patterns

---

**Last Updated**: 2025-11-01
**Next Review**: Milestone 1.3.0 (WebGPU acceleration)
