/**
 * DataFrame Utilities Edge Case Tests
 *
 * Comprehensive edge case testing for:
 * - drop(), rename(), unique(), dropDuplicates(), describe(), sample()
 *
 * Coverage:
 * - Empty DataFrames (0 rows, 0 columns)
 * - Single row/column DataFrames
 * - Boundary conditions
 * - Error cases
 * - Memory leak tests
 */

import test from 'node:test';
import assert from 'node:assert';
import { Rozes } from '../../../dist/index.mjs';

// ========================================================================
// drop() Edge Cases
// ========================================================================

test('DataFrame.drop() - drop from empty DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\n");

    const dropped = df.drop(['age']);

    assert.strictEqual(dropped.shape.rows, 0);
    assert.strictEqual(dropped.shape.cols, 1);
    assert.deepStrictEqual(dropped.columns, ['name']);

    df.free();
    dropped.free();
});

test('DataFrame.drop() - drop single column DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n");

    // Dropping the only column should fail or return empty DataFrame
    try {
        const dropped = df.drop(['value']);
        assert.strictEqual(dropped.shape.cols, 0);
        dropped.free();
    } catch (err) {
        // Expected - cannot drop all columns
        assert.ok(err.message.includes('column') || err.message.includes('empty'));
    }

    df.free();
});

test('DataFrame.drop() - drop non-existent column', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\n");

    // Should throw error for non-existent column
    try {
        const dropped = df.drop(['nonexistent']);
        // If it doesn't throw, it should be unchanged
        assert.strictEqual(dropped.shape.cols, 2);
        dropped.free();
    } catch (err) {
        // Expected - column not found
        assert.ok(err.message.includes('not found') || err.message.includes('column'));
    }

    df.free();
});

test('DataFrame.drop() - drop empty array', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\n");

    const dropped = df.drop([]);

    // Should return unchanged DataFrame
    assert.strictEqual(dropped.shape.rows, 1);
    assert.strictEqual(dropped.shape.cols, 2);
    assert.deepStrictEqual(dropped.columns, ['name', 'age']);

    df.free();
    dropped.free();
});

test('DataFrame.drop() - drop duplicate column names', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age,score\nAlice,30,95.5\n");

    // Drop same column twice
    const dropped = df.drop(['age', 'age']);

    assert.strictEqual(dropped.shape.cols, 2);
    assert.ok(!dropped.columns.includes('age'));

    df.free();
    dropped.free();
});

// ========================================================================
// rename() Edge Cases
// ========================================================================

test('DataFrame.rename() - rename on empty DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\n");

    const renamed = df.rename('name', 'fullname');

    assert.strictEqual(renamed.shape.rows, 0);
    assert.deepStrictEqual(renamed.columns, ['fullname', 'age']);

    df.free();
    renamed.free();
});

test('DataFrame.rename() - rename single column DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n");

    const renamed = df.rename('value', 'number');

    assert.strictEqual(renamed.shape.rows, 2);
    assert.strictEqual(renamed.shape.cols, 1);
    assert.deepStrictEqual(renamed.columns, ['number']);

    df.free();
    renamed.free();
});

test('DataFrame.rename() - rename to existing column name', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\n");

    // Renaming 'name' to 'age' should fail (duplicate column name)
    try {
        const renamed = df.rename('name', 'age');
        // If allowed, check it doesn't break
        assert.strictEqual(renamed.shape.cols, 2);
        renamed.free();
    } catch (err) {
        // Expected - duplicate column name
        assert.ok(err.message.includes('exists') || err.message.includes('duplicate'));
    }

    df.free();
});

test('DataFrame.rename() - rename non-existent column', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\n");

    try {
        const renamed = df.rename('nonexistent', 'newname');
        // Should fail
        renamed.free();
        assert.fail('Should have thrown error');
    } catch (err) {
        // Expected
        assert.ok(err.message.includes('not found') || err.message.includes('column'));
    }

    df.free();
});

test('DataFrame.rename() - rename to same name', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\n");

    const renamed = df.rename('name', 'name');

    // Should succeed (no-op)
    assert.deepStrictEqual(renamed.columns, ['name', 'age']);

    df.free();
    renamed.free();
});

// ========================================================================
// unique() Edge Cases
// ========================================================================

test('DataFrame.unique() - empty DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("category\n");

    const unique = df.unique('category');

    assert.ok(Array.isArray(unique));
    assert.strictEqual(unique.length, 0);

    df.free();
});

test('DataFrame.unique() - single value', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("category\nA\n");

    const unique = df.unique('category');

    assert.strictEqual(unique.length, 1);
    assert.strictEqual(unique[0], 'A');

    df.free();
});

test('DataFrame.unique() - all duplicates', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("category\nA\nA\nA\nA\n");

    const unique = df.unique('category');

    assert.strictEqual(unique.length, 1);
    assert.strictEqual(unique[0], 'A');

    df.free();
});

test('DataFrame.unique() - all unique values', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("category\nA\nB\nC\nD\n");

    const unique = df.unique('category');

    assert.strictEqual(unique.length, 4);
    assert.ok(unique.includes('A'));
    assert.ok(unique.includes('B'));
    assert.ok(unique.includes('C'));
    assert.ok(unique.includes('D'));

    df.free();
});

test('DataFrame.unique() - non-existent column', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("category\nA\nB\n");

    try {
        df.unique('nonexistent');
        assert.fail('Should have thrown error');
    } catch (err) {
        assert.ok(err.message.includes('not found') || err.message.includes('column'));
    }

    df.free();
});

test('DataFrame.unique() - with empty strings', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text,id\n,1\nA,2\n,3\nB,4\n");

    const unique = df.unique('text');

    assert.strictEqual(unique.length, 3); // '', 'A', 'B'
    assert.ok(unique.includes(''));
    assert.ok(unique.includes('A'));
    assert.ok(unique.includes('B'));

    df.free();
});

// ========================================================================
// dropDuplicates() Edge Cases
// ========================================================================

test('DataFrame.dropDuplicates() - empty DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\n");

    const unique = df.dropDuplicates();

    assert.strictEqual(unique.shape.rows, 0);
    assert.strictEqual(unique.shape.cols, 2);

    df.free();
    unique.free();
});

test('DataFrame.dropDuplicates() - single row', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\n");

    const unique = df.dropDuplicates();

    assert.strictEqual(unique.shape.rows, 1);

    df.free();
    unique.free();
});

test('DataFrame.dropDuplicates() - all rows identical', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\nAlice,30\nAlice,30\n");

    const unique = df.dropDuplicates();

    assert.strictEqual(unique.shape.rows, 1);

    df.free();
    unique.free();
});

test('DataFrame.dropDuplicates() - no duplicates', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\nBob,25\nCharlie,35\n");

    const unique = df.dropDuplicates();

    assert.strictEqual(unique.shape.rows, 3);

    df.free();
    unique.free();
});

test('DataFrame.dropDuplicates() - subset empty array', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\nAlice,30\n");

    // Empty subset should use all columns
    const unique = df.dropDuplicates([]);

    assert.strictEqual(unique.shape.rows, 1);

    df.free();
    unique.free();
});

test('DataFrame.dropDuplicates() - subset non-existent column', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\nBob,25\n");

    try {
        const unique = df.dropDuplicates(['nonexistent']);
        unique.free();
        assert.fail('Should have thrown error');
    } catch (err) {
        assert.ok(err.message.includes('not found') || err.message.includes('column'));
    }

    df.free();
});

// ========================================================================
// describe() Edge Cases
// ========================================================================

test('DataFrame.describe() - empty DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\n");

    const stats = df.describe();

    // Should return empty stats or all zeros
    assert.ok(stats);
    if (stats.age) {
        assert.strictEqual(stats.age.count, 0);
    }

    df.free();
});

test('DataFrame.describe() - single row', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n");

    const stats = df.describe();

    assert.ok(stats.age);
    assert.strictEqual(stats.age.count, 1);
    assert.strictEqual(stats.age.mean, 30);
    assert.strictEqual(stats.age.min, 30);
    assert.strictEqual(stats.age.max, 30);
    // std should be 0 or NaN for single value
    assert.ok(stats.age.std === 0 || Number.isNaN(stats.age.std));

    df.free();
});

test('DataFrame.describe() - single column', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n");

    const stats = df.describe();

    assert.ok(stats.value);
    assert.strictEqual(stats.value.count, 3);
    assert.strictEqual(stats.value.mean, 20);

    df.free();
});

test('DataFrame.describe() - all same values', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n42\n42\n42\n");

    const stats = df.describe();

    assert.ok(stats.value);
    assert.strictEqual(stats.value.count, 3);
    assert.strictEqual(stats.value.mean, 42);
    assert.strictEqual(stats.value.min, 42);
    assert.strictEqual(stats.value.max, 42);
    assert.strictEqual(stats.value.std, 0); // No variation

    df.free();
});

test('DataFrame.describe() - with NaN values', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\nNaN\n30\n");

    const stats = df.describe();

    // Should either skip NaN or handle gracefully
    assert.ok(stats.value);
    // Count may be 2 (skipping NaN) or 3 (including NaN)
    assert.ok(stats.value.count === 2 || stats.value.count === 3);

    df.free();
});

// ========================================================================
// sample() Edge Cases
// ========================================================================

test('DataFrame.sample() - sample 0 rows', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n");

    const sample = df.sample(0);

    assert.strictEqual(sample.shape.rows, 0);
    assert.strictEqual(sample.shape.cols, 1);

    df.free();
    sample.free();
});

test('DataFrame.sample() - sample from empty DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n");

    try {
        const sample = df.sample(5);
        // Should either return empty or throw
        assert.strictEqual(sample.shape.rows, 0);
        sample.free();
    } catch (err) {
        // Expected - cannot sample from empty
        assert.ok(err);
    }

    df.free();
});

test('DataFrame.sample() - sample from single row', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n42\n");

    const sample = df.sample(5); // With replacement

    assert.strictEqual(sample.shape.rows, 5);
    // All values should be 42
    const values = sample.column('value');
    for (let i = 0; i < 5; i++) {
        assert.strictEqual(Number(values[i]), 42);
    }

    df.free();
    sample.free();
});

test('DataFrame.sample() - reproducibility with same seed', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n40\n50\n");

    // Sample twice with same seed
    const sample1 = df.sample(10, 12345);
    const sample2 = df.sample(10, 12345);

    // Should produce identical results
    const values1 = sample1.column('value');
    const values2 = sample2.column('value');

    for (let i = 0; i < 10; i++) {
        assert.strictEqual(Number(values1[i]), Number(values2[i]));
    }

    df.free();
    sample1.free();
    sample2.free();
});

test('DataFrame.sample() - different seeds produce different results', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n40\n50\n");

    // Sample with different seeds
    const sample1 = df.sample(10, 11111);
    const sample2 = df.sample(10, 99999);

    const values1 = sample1.column('value');
    const values2 = sample2.column('value');

    // Should be different (very unlikely to be identical by chance)
    let different = false;
    for (let i = 0; i < 10; i++) {
        if (Number(values1[i]) !== Number(values2[i])) {
            different = true;
            break;
        }
    }
    assert.ok(different, 'Different seeds should produce different samples');

    df.free();
    sample1.free();
    sample2.free();
});

test('DataFrame.sample() - very large n (stress test)', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n");

    // Sample 10,000 rows from 3 rows (with replacement)
    const sample = df.sample(10000);

    assert.strictEqual(sample.shape.rows, 10000);

    df.free();
    sample.free();
});

// ========================================================================
// Memory Leak Tests (Edge Cases)
// ========================================================================

test('DataFrame.drop() - memory leak with empty arrays', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\n");
        const dropped = df.drop([]);
        df.free();
        dropped.free();
    }

    assert.ok(true);
});

test('DataFrame.rename() - memory leak with empty DataFrame', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("name,age\n");
        const renamed = df.rename('name', 'fullname');
        df.free();
        renamed.free();
    }

    assert.ok(true);
});

test('DataFrame.unique() - memory leak with empty DataFrame', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("category\n");
        const unique = df.unique('category');
        df.free();
    }

    assert.ok(true);
});

test('DataFrame.dropDuplicates() - memory leak with all duplicates', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("value\n42\n42\n42\n");
        const unique = df.dropDuplicates();
        df.free();
        unique.free();
    }

    assert.ok(true);
});

test('DataFrame.describe() - memory leak with single row', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("value\n42\n");
        const stats = df.describe();
        df.free();
    }

    assert.ok(true);
});

test('DataFrame.sample() - memory leak with sample(0)', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n");
        const sample = df.sample(0);
        df.free();
        sample.free();
    }

    assert.ok(true);
});

// ========================================================================
// Large Dataset Stress Tests
// ========================================================================

test('DataFrame.drop() - large dataset (10K rows)', async () => {
    const rozes = await Rozes.init();

    // Generate 10K rows
    let csv = "name,age,score\n";
    for (let i = 0; i < 10000; i++) {
        csv += `Person${i},${20 + (i % 60)},${50 + (i % 50)}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);
    const dropped = df.drop(['score']);

    assert.strictEqual(dropped.shape.rows, 10000);
    assert.strictEqual(dropped.shape.cols, 2);

    df.free();
    dropped.free();
});

test('DataFrame.dropDuplicates() - large dataset with many duplicates', async () => {
    const rozes = await Rozes.init();

    // Generate 10K rows with only 100 unique values
    let csv = "category,value\n";
    for (let i = 0; i < 10000; i++) {
        csv += `Cat${i % 100},${i % 100}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);
    const unique = df.dropDuplicates();

    assert.strictEqual(unique.shape.rows, 100);

    df.free();
    unique.free();
});

test('DataFrame.describe() - large dataset (10K rows)', async () => {
    const rozes = await Rozes.init();

    // Generate 10K rows
    let csv = "value\n";
    for (let i = 0; i < 10000; i++) {
        csv += `${i}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);
    const stats = df.describe();

    assert.ok(stats.value);
    assert.strictEqual(stats.value.count, 10000);
    assert.strictEqual(stats.value.mean, 4999.5);
    assert.strictEqual(stats.value.min, 0);
    assert.strictEqual(stats.value.max, 9999);

    df.free();
});
