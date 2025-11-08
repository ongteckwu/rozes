/**
 * LazyDataFrame Integration Tests
 *
 * Tests lazy evaluation with query optimization (predicate pushdown, projection pushdown)
 */

import { Rozes } from '../../../dist/index.mjs';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main() {
  console.log('🧪 Testing LazyDataFrame Evaluation\n');

  // Initialize Rozes
  const wasmPath = join(__dirname, '../../../zig-out/bin/rozes.wasm');
  const rozes = await Rozes.init(wasmPath);
  console.log('✅ Rozes initialized (version:', rozes.version, ')\n');

  let passedTests = 0;
  let totalTests = 0;

  function test(name, fn) {
    totalTests++;
    try {
      fn();
      console.log(`✅ ${name}`);
      passedTests++;
    } catch (err) {
      console.error(`❌ ${name}`);
      console.error('  ', err.message);
    }
  }

  const DataFrame = rozes.DataFrame;

  test('Lazy: basic select operation', () => {
    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\nCharlie,35,91.0\n';
    const df = DataFrame.fromCSV(csv);

    const result = df.lazy()
      .select(['name', 'age'])
      .collect();

    if (result.shape.cols !== 2) throw new Error('Should have 2 columns');
    if (result.shape.rows !== 3) throw new Error('Should have 3 rows');
    if (JSON.stringify(result.columns) !== JSON.stringify(['name', 'age'])) {
      throw new Error('Should have name and age columns');
    }

    result.free();
  });

  test('Lazy: basic limit operation', () => {
    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\nCharlie,35,91.0\n';
    const df = DataFrame.fromCSV(csv);

    const result = df.lazy()
      .limit(2)
      .collect();

    if (result.shape.rows !== 2) throw new Error('Should have 2 rows');
    if (result.shape.cols !== 3) throw new Error('Should have 3 columns');

    result.free();
  });

  test('Lazy: chained select + limit', () => {
    const csv = 'name,age,score,city\nAlice,30,95.5,NYC\nBob,25,87.3,LA\nCharlie,35,91.0,SF\nDave,40,88.5,CHI\n';
    const df = DataFrame.fromCSV(csv);

    const result = df.lazy()
      .select(['name', 'age'])
      .limit(2)
      .collect();

    if (result.shape.rows !== 2) throw new Error('Should have 2 rows');
    if (result.shape.cols !== 2) throw new Error('Should have 2 columns');
    if (JSON.stringify(result.columns) !== JSON.stringify(['name', 'age'])) {
      throw new Error('Should have name and age columns');
    }

    result.free();
  });

  test('Lazy: select single column', () => {
    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\n';
    const df = DataFrame.fromCSV(csv);

    const result = df.lazy()
      .select(['name'])
      .collect();

    if (result.shape.cols !== 1) throw new Error('Should have 1 column');
    if (result.columns[0] !== 'name') throw new Error('Should have name column');

    result.free();
  });

  test('Lazy: limit(0) returns empty DataFrame', () => {
    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\n';
    const df = DataFrame.fromCSV(csv);

    const result = df.lazy()
      .limit(0)
      .collect();

    if (result.shape.rows !== 0) throw new Error('Should have 0 rows');
    if (result.shape.cols !== 3) throw new Error('Should still have 3 columns');

    result.free();
  });

  test('Lazy: limit larger than row count', () => {
    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\n';
    const df = DataFrame.fromCSV(csv);

    const result = df.lazy()
      .limit(100)
      .collect();

    if (result.shape.rows !== 2) throw new Error('Should have 2 rows (not 100)');
    if (result.shape.cols !== 3) throw new Error('Should have 3 columns');

    result.free();
  });

  test('Lazy: empty DataFrame handling', () => {
    const csv = 'name,age,score\n'; // Header only
    const df = DataFrame.fromCSV(csv);

    const result = df.lazy()
      .select(['name', 'age'])
      .limit(10)
      .collect();

    if (result.shape.rows !== 0) throw new Error('Should have 0 rows');
    if (result.shape.cols !== 2) throw new Error('Should have 2 columns');

    result.free();
  });

  test('Lazy: correctness vs eager select', () => {
    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\n';
    const df1 = DataFrame.fromCSV(csv);
    const df2 = DataFrame.fromCSV(csv);

    const eager = df1.select(['name', 'age']);
    const lazy = df2.lazy()
      .select(['name', 'age'])
      .collect();

    if (lazy.shape.rows !== eager.shape.rows) throw new Error('Row count should match');
    if (lazy.shape.cols !== eager.shape.cols) throw new Error('Column count should match');
    if (JSON.stringify(lazy.columns) !== JSON.stringify(eager.columns)) {
      throw new Error('Column names should match');
    }

    eager.free();
    lazy.free();
  });

  test('Lazy: correctness vs eager head', () => {
    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\nCharlie,35,91.0\n';
    const df1 = DataFrame.fromCSV(csv);
    const df2 = DataFrame.fromCSV(csv);

    const eager = df1.head(2);
    const lazy = df2.lazy()
      .limit(2)
      .collect();

    if (lazy.shape.rows !== eager.shape.rows) throw new Error('Row count should match');
    if (lazy.shape.cols !== eager.shape.cols) throw new Error('Column count should match');

    eager.free();
    lazy.free();
  });

  test('Lazy: memory leak test - basic operations (1000 iterations)', () => {
    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\n';

    for (let i = 0; i < 1000; i++) {
      const df = DataFrame.fromCSV(csv);
      const result = df.lazy()
        .select(['name', 'age'])
        .collect();
      result.free();
    }
  });

  test('Lazy: memory leak test - chained operations (1000 iterations)', () => {
    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\nCharlie,35,91.0\n';

    for (let i = 0; i < 1000; i++) {
      const df = DataFrame.fromCSV(csv);
      const result = df.lazy()
        .select(['name', 'age'])
        .limit(2)
        .collect();
      result.free();
    }
  });

  test('Lazy: performance test - medium dataset (100 rows)', () => {
    const headers = 'name,age,score,city\n';
    const rows = Array.from({ length: 100 }, (_, i) =>
      `Person${i},${20 + i},${80 + (i % 20)},City${i % 10}`
    ).join('\n');
    const csv = headers + rows + '\n';

    const df = DataFrame.fromCSV(csv);

    const start = Date.now();
    const result = df.lazy()
      .select(['name', 'age'])
      .limit(10)
      .collect();
    const elapsed = Date.now() - start;

    if (elapsed >= 100) throw new Error(`Should complete in <100ms (took ${elapsed}ms)`);
    if (result.shape.rows !== 10) throw new Error('Should have 10 rows');
    if (result.shape.cols !== 2) throw new Error('Should have 2 columns');

    result.free();
  });

  console.log(`\n📊 Lazy Tests: ${passedTests}/${totalTests} passed`);
  if (passedTests < totalTests) {
    process.exit(1);
  }
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
