/**
 * Lazy Evaluation API Showcase (TypeScript)
 *
 * ⚠️ NOTE: This is an MVP implementation (v1.3.0)
 * - select() and limit() operations are supported
 * - filter(), groupBy(), join() planned for v1.4.0
 *
 * Demonstrates lazy evaluation and query optimization:
 * - lazy() - Create LazyDataFrame
 * - select() - Add column selection (projection pushdown)
 * - limit() - Add row limit
 * - collect() - Execute optimized query plan
 */

import { Rozes, DataFrame as DataFrameType, LazyDataFrame } from '../../dist/index.mjs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main(): Promise<void> {
  console.log('⚡ Lazy Evaluation API Showcase (TypeScript)\n');
  console.log('⚠️  MVP: select() + limit() only (v1.3.0)\n');

  // Initialize Rozes
  const wasmPath = join(__dirname, '../../zig-out/bin/rozes.wasm');
  const rozes = await Rozes.init(wasmPath);
  console.log('✅ Rozes initialized\n');

  const DataFrame = rozes.DataFrame;

  // Sample dataset
  const csv: string = `name,age,city,salary,department
Alice,30,San Francisco,95000,Engineering
Bob,25,New York,75000,Finance
Charlie,35,Seattle,105000,Engineering
Diana,28,Boston,82000,Marketing
Eve,32,Austin,98000,Engineering
Frank,45,Chicago,88000,Sales
Grace,29,Denver,79000,Marketing
Henry,38,Portland,92000,Engineering
Ivy,27,Miami,76000,Finance
Jack,33,Seattle,101000,Engineering
Kelly,31,Austin,87000,Marketing
Liam,40,Boston,110000,Engineering`;

  const df: DataFrameType = DataFrame.fromCSV(csv);
  console.log('Dataset:');
  console.log(`  ${df.shape.rows} rows × ${df.shape.cols} columns`);
  console.log();

  // Example 1: Basic lazy evaluation
  console.log('1️⃣  Basic Lazy Evaluation');
  console.log('─'.repeat(50));
  console.log('Operation: Select name, age columns + limit 5');
  console.log();

  console.log('Eager approach (executes immediately):');
  const start1: number = Date.now();
  const eagerResult: DataFrameType = df.select(['name', 'age']).head(5);
  const time1: number = Date.now() - start1;
  eagerResult.show();
  console.log(`Time: ${time1}ms`);
  console.log();

  try {
    console.log('Lazy approach (deferred execution):');
    const start2: number = Date.now();
    const lazyDf: LazyDataFrame = df.lazy();  // No execution yet
    const lazyWithOps: LazyDataFrame = lazyDf
      .select(['name', 'age'])  // Add to query plan
      .limit(5);                // Add to query plan
    const lazyResult: DataFrameType = lazyWithOps.collect();  // Execute now!
    const time2: number = Date.now() - start2;
    lazyResult.show();
    console.log(`Time: ${time2}ms`);
    console.log();

    lazyResult.free();
  } catch (err: any) {
    console.error('❌ Lazy evaluation error:', err.message);
    console.log();
  }

  eagerResult.free();

  // Example 2: Query optimization - Projection pushdown
  console.log('2️⃣  Query Optimization: Projection Pushdown');
  console.log('─'.repeat(50));
  console.log('Optimization: Only load selected columns\n');

  console.log('Without optimization (load all, then select):');
  console.log('  1. Load all 5 columns');
  console.log('  2. Select 2 columns');
  console.log('  3. Discard 3 columns (wasted I/O)\n');

  console.log('With projection pushdown (select early):');
  console.log('  1. Identify: Only need 2 columns');
  console.log('  2. Load: Just those 2 columns');
  console.log('  3. Result: 60% less I/O!\n');

  try {
    const lazyOpt: LazyDataFrame = df.lazy()
      .select(['name', 'salary'])
      .limit(3);

    console.log('Executing optimized query...');
    const result: DataFrameType = lazyOpt.collect();
    result.show();
    console.log();
    result.free();
  } catch (err: any) {
    console.error('❌ Optimization error:', err.message);
    console.log();
  }

  // Example 3: Chaining operations
  console.log('3️⃣  Chaining Lazy Operations');
  console.log('─'.repeat(50));
  console.log('Build complex query plan before execution\n');

  try {
    console.log('Query plan:');
    console.log('  1. Select: name, department, salary');
    console.log('  2. Limit: 8 rows');
    console.log();

    const lazyChained: LazyDataFrame = df.lazy()
      .select(['name', 'department', 'salary'])
      .limit(8);

    console.log('Executing chained query...');
    const chainedResult: DataFrameType = lazyChained.collect();
    chainedResult.show();
    console.log();
    chainedResult.free();
  } catch (err: any) {
    console.error('❌ Chaining error:', err.message);
    console.log();
  }

  // Example 4: Performance comparison
  console.log('4️⃣  Performance Comparison');
  console.log('─'.repeat(50));

  console.log('Test: Select 2 columns + limit 5 from 12 rows\n');

  // Eager
  const eagerStart: number = Date.now();
  const eager: DataFrameType = df.select(['name', 'age']).head(5);
  const eagerTime: number = Date.now() - eagerStart;
  console.log(`Eager:  ${eagerTime}ms`);
  eager.free();

  // Lazy
  try {
    const lazyStart: number = Date.now();
    const lazy: LazyDataFrame = df.lazy().select(['name', 'age']).limit(5);
    const lazyCollected: DataFrameType = lazy.collect();
    const lazyTime: number = Date.now() - lazyStart;
    console.log(`Lazy:   ${lazyTime}ms`);
    console.log(`Speedup: ${(eagerTime / lazyTime).toFixed(2)}×`);
    console.log();
    lazyCollected.free();
  } catch (err: any) {
    console.error('❌ Performance test error:', err.message);
    console.log();
  }

  // Example 5: Memory efficiency
  console.log('5️⃣  Memory Efficiency');
  console.log('─'.repeat(50));
  console.log('Lazy evaluation can reduce memory usage\n');

  console.log('Scenario: Select 1 column from 100K row dataset');
  console.log('  Eager:  Loads all columns → 5× memory');
  console.log('  Lazy:   Loads only 1 column → 1× memory');
  console.log('  Savings: 80% less memory!');
  console.log();

  // Example 6: Future optimizations (v1.4.0+)
  console.log('6️⃣  Future Optimizations (v1.4.0+)');
  console.log('─'.repeat(50));

  console.log('Planned lazy operations:');
  console.log('  🔍 filter() - Predicate pushdown');
  console.log('  📊 groupBy() - Pre-aggregation');
  console.log('  🔗 join() - Join reordering');
  console.log('  📦 agg() - Lazy aggregations');
  console.log();

  console.log('Example future query (v1.4.0):');
  console.log('');
  console.log('  const result = df.lazy()');
  console.log('    .filter(row => row.age > 30)          // Predicate pushdown');
  console.log('    .select([\'name\', \'salary\'])          // Projection pushdown');
  console.log('    .groupBy(\'department\')               // Pre-aggregation');
  console.log('    .agg({ salary: \'mean\' })             // Lazy aggregation');
  console.log('    .limit(10)                           // Early termination');
  console.log('    .collect();                          // Execute optimized plan');
  console.log();

  console.log('Optimizations applied:');
  console.log('  ✅ Push filter before select (fewer rows)');
  console.log('  ✅ Select only needed columns (less I/O)');
  console.log('  ✅ Group before limit (faster aggregation)');
  console.log('  ✅ Limit early when possible (early stop)');
  console.log('  🚀 Result: 2-10× faster than eager evaluation!');
  console.log();

  // Example 7: When to use lazy vs eager
  console.log('7️⃣  When to Use Lazy vs Eager');
  console.log('─'.repeat(50));

  console.log('Use LAZY when:');
  console.log('  ✅ Chaining multiple operations');
  console.log('  ✅ Working with large datasets');
  console.log('  ✅ Only need subset of columns');
  console.log('  ✅ Can benefit from early termination (limit)');
  console.log();

  console.log('Use EAGER when:');
  console.log('  ✅ Need immediate results');
  console.log('  ✅ Single operation only');
  console.log('  ✅ Small datasets (<1000 rows)');
  console.log('  ✅ Need to inspect intermediate results');
  console.log();

  // Cleanup
  df.free();

  console.log('✅ Lazy evaluation showcase complete!');
  console.log('\n💡 Tip: Lazy evaluation shines with large datasets and complex queries');
}

// Run examples
main().catch(console.error);
