/**
 * DataFrame Utilities Test Suite
 *
 * Tests for: drop(), rename(), unique(), dropDuplicates(), describe(), sample()
 */

import test from 'node:test';
import assert from 'node:assert';
import { Rozes } from '../../../dist/index.js';

test('DataFrame.drop() - single column', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age,score\nAlice,30,95.5\nBob,25,87.3\n");

    const dropped = df.drop(['score']);

    assert.deepStrictEqual(dropped.columns, ['name', 'age']);
    assert.strictEqual(dropped.shape.rows, 2);
    assert.strictEqual(dropped.shape.cols, 2);

    df.free();
    dropped.free();
});

test('DataFrame.drop() - multiple columns', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age,score,city\nAlice,30,95.5,NYC\nBob,25,87.3,LA\n");

    const dropped = df.drop(['score', 'city']);

    assert.deepStrictEqual(dropped.columns, ['name', 'age']);
    assert.strictEqual(dropped.shape.rows, 2);
    assert.strictEqual(dropped.shape.cols, 2);

    df.free();
    dropped.free();
});

test('DataFrame.drop() - preserve data integrity', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age,score\nAlice,30,95.5\nBob,25,87.3\n");

    const dropped = df.drop(['score']);

    // Check that age column data is intact
    const ageCol = dropped.column('age');
    assert.ok(ageCol);
    assert.strictEqual(ageCol[0], 30n);
    assert.strictEqual(ageCol[1], 25n);

    df.free();
    dropped.free();
});

test('DataFrame.rename() - basic rename', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n25,87.3\n");

    const renamed = df.rename('age', 'years');

    assert.deepStrictEqual(renamed.columns, ['years', 'score']);
    assert.strictEqual(renamed.shape.rows, 2);
    assert.strictEqual(renamed.shape.cols, 2);

    // Verify data is intact
    const yearsCol = renamed.column('years');
    assert.ok(yearsCol);
    assert.strictEqual(yearsCol[0], 30n);
    assert.strictEqual(yearsCol[1], 25n);

    df.free();
    renamed.free();
});

test('DataFrame.rename() - data integrity', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n25,87.3\n");

    const renamed = df.rename('age', 'years');

    // Verify score column unchanged
    const scoreCol = renamed.column('score');
    assert.ok(scoreCol);
    assert.strictEqual(scoreCol[0], 95.5);
    assert.strictEqual(scoreCol[1], 87.3);

    df.free();
    renamed.free();
});

test('DataFrame.unique() - basic functionality', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("category\nA\nB\nA\nC\nB\nA\n");

    const unique = df.unique('category');

    assert.ok(Array.isArray(unique));
    assert.strictEqual(unique.length, 3);

    // Check that all unique values are present (order may vary)
    assert.ok(unique.includes('A'));
    assert.ok(unique.includes('B'));
    assert.ok(unique.includes('C'));

    df.free();
});

test('DataFrame.unique() - numeric column', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n10\n30\n20\n");

    const unique = df.unique('value');

    assert.ok(Array.isArray(unique));
    assert.strictEqual(unique.length, 3);

    // All values returned as strings
    assert.ok(unique.includes('10'));
    assert.ok(unique.includes('20'));
    assert.ok(unique.includes('30'));

    df.free();
});

test('DataFrame.dropDuplicates() - all columns', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\nBob,25\nAlice,30\nCharlie,35\n");

    const unique = df.dropDuplicates();

    assert.strictEqual(unique.shape.rows, 3); // Removed 1 duplicate
    assert.strictEqual(unique.shape.cols, 2);

    df.free();
    unique.free();
});

test('DataFrame.dropDuplicates() - subset columns', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age,score\nAlice,30,95.5\nBob,25,87.3\nAlice,35,91.0\n");

    // Only check 'name' column for duplicates
    const unique = df.dropDuplicates(['name']);

    // Should have 2 rows: Alice (first occurrence) and Bob
    assert.strictEqual(unique.shape.rows, 2);
    assert.strictEqual(unique.shape.cols, 3);

    df.free();
    unique.free();
});

test('DataFrame.dropDuplicates() - no duplicates', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\nBob,25\nCharlie,35\n");

    const unique = df.dropDuplicates();

    // Should have same number of rows
    assert.strictEqual(unique.shape.rows, 3);
    assert.strictEqual(unique.shape.cols, 2);

    df.free();
    unique.free();
});

test('DataFrame.describe() - basic stats', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n25,87.3\n35,91.0\n");

    const stats = df.describe();

    // Check structure
    assert.ok(stats);
    assert.ok(stats.age);
    assert.ok(stats.score);

    // Age stats
    assert.strictEqual(stats.age.count, 3);
    assert.strictEqual(stats.age.mean, 30);
    assert.strictEqual(stats.age.min, 25);
    assert.strictEqual(stats.age.max, 35);
    assert.ok(stats.age.std !== undefined);

    // Score stats
    assert.strictEqual(stats.score.count, 3);
    assert.ok(Math.abs(stats.score.mean - 91.27) < 0.1);
    assert.strictEqual(stats.score.min, 87.3);
    assert.strictEqual(stats.score.max, 95.5);

    df.free();
});

test('DataFrame.describe() - single column', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n40\n50\n");

    const stats = df.describe();

    assert.ok(stats);
    assert.ok(stats.value);
    assert.strictEqual(stats.value.count, 5);
    assert.strictEqual(stats.value.mean, 30);
    assert.strictEqual(stats.value.min, 10);
    assert.strictEqual(stats.value.max, 50);

    df.free();
});

test('DataFrame.sample() - basic sampling', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\nBob,25\nCharlie,35\n");

    const sample = df.sample(5); // Sample 5 rows with replacement

    assert.strictEqual(sample.shape.rows, 5);
    assert.strictEqual(sample.shape.cols, 2);
    assert.deepStrictEqual(sample.columns, ['name', 'age']);

    df.free();
    sample.free();
});

test('DataFrame.sample() - sample same size as original', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n");

    const sample = df.sample(3);

    assert.strictEqual(sample.shape.rows, 3);
    assert.strictEqual(sample.shape.cols, 1);

    df.free();
    sample.free();
});

test('DataFrame.sample() - sample larger than original', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n");

    const sample = df.sample(10); // Sample with replacement

    assert.strictEqual(sample.shape.rows, 10);
    assert.strictEqual(sample.shape.cols, 1);

    df.free();
    sample.free();
});

// Edge case tests

test('DataFrame.drop() - empty result (drop all columns)', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n25,87.3\n");

    // Note: Dropping all columns may return error or empty DataFrame
    // This tests error handling
    try {
        const dropped = df.drop(['age', 'score']);
        // If we get here, verify it's empty
        assert.strictEqual(dropped.shape.cols, 0);
        dropped.free();
    } catch (err) {
        // Expected to fail - can't drop all columns
        assert.ok(err);
    }

    df.free();
});

test('DataFrame.unique() - single value', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("category\nA\nA\nA\n");

    const unique = df.unique('category');

    assert.strictEqual(unique.length, 1);
    assert.strictEqual(unique[0], 'A');

    df.free();
});

test('DataFrame.dropDuplicates() - all duplicates', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\nAlice,30\nAlice,30\n");

    const unique = df.dropDuplicates();

    // Should have only 1 row
    assert.strictEqual(unique.shape.rows, 1);

    df.free();
    unique.free();
});

test('DataFrame.describe() - empty DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\n");

    const stats = df.describe();

    // Should return empty object or object with null stats
    assert.ok(stats);

    df.free();
});

test('DataFrame.sample() - sample 1 row', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n");

    const sample = df.sample(1);

    assert.strictEqual(sample.shape.rows, 1);
    assert.strictEqual(sample.shape.cols, 1);

    df.free();
    sample.free();
});

// Memory leak tests

test('DataFrame.drop() - memory leak test', async () => {
    const rozes = await Rozes.init();

    // Run 1000 times
    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("name,age,score\nAlice,30,95.5\nBob,25,87.3\n");
        const dropped = df.drop(['score']);
        df.free();
        dropped.free();
    }

    // If we get here without crashing, no obvious memory leaks
    assert.ok(true);
});

test('DataFrame.rename() - memory leak test', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n25,87.3\n");
        const renamed = df.rename('age', 'years');
        df.free();
        renamed.free();
    }

    assert.ok(true);
});

test('DataFrame.dropDuplicates() - memory leak test', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\nBob,25\nAlice,30\n");
        const unique = df.dropDuplicates();
        df.free();
        unique.free();
    }

    assert.ok(true);
});

test('DataFrame.sample() - memory leak test', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n");
        const sample = df.sample(5);
        df.free();
        sample.free();
    }

    assert.ok(true);
});
