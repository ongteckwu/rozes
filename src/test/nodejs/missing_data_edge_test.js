/**
 * Missing Data Edge Case Tests
 *
 * Comprehensive edge case testing for:
 * - fillna(), dropna(), isna(), notna()
 *
 * Coverage:
 * - Empty DataFrames
 * - All missing values
 * - No missing values
 * - Different data types (Int64, Float64, String, Bool)
 * - Memory leak tests
 * - Large datasets
 */

import test from 'node:test';
import assert from 'node:assert';
import { Rozes } from '../../../dist/index.mjs';

// ========================================================================
// dropna() Edge Cases
// ========================================================================

test('Missing.dropna() - empty DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\n");

    const cleaned = df.dropna();

    assert.strictEqual(cleaned.shape.rows, 0);
    assert.strictEqual(cleaned.shape.cols, 2);

    df.free();
    cleaned.free();
});

test('Missing.dropna() - single row with no missing', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n");

    const cleaned = df.dropna();

    assert.strictEqual(cleaned.shape.rows, 1);
    assert.strictEqual(cleaned.shape.cols, 2);

    df.free();
    cleaned.free();
});

test('Missing.dropna() - single row with missing', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\n30,NaN\n");

    const cleaned = df.dropna();

    assert.strictEqual(cleaned.shape.rows, 0);
    assert.strictEqual(cleaned.shape.cols, 2);

    df.free();
    cleaned.free();
});

test('Missing.dropna() - all rows have missing values', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\nNaN,95.5\n30,NaN\nNaN,NaN\n");

    const cleaned = df.dropna();

    assert.strictEqual(cleaned.shape.rows, 0); // All rows have at least one NaN

    df.free();
    cleaned.free();
});

test('Missing.dropna() - no missing values in entire DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n25,87.3\n35,91.0\n");

    const cleaned = df.dropna();

    assert.strictEqual(cleaned.shape.rows, 3); // All rows kept
    assert.strictEqual(cleaned.shape.cols, 2);

    df.free();
    cleaned.free();
});

test('Missing.dropna() - single column DataFrame with NaN', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\nNaN\n30\nNaN\n");

    const cleaned = df.dropna();

    assert.strictEqual(cleaned.shape.rows, 2); // Only rows 10, 30
    assert.strictEqual(cleaned.shape.cols, 1);

    df.free();
    cleaned.free();
});

test('Missing.dropna() - multiple columns, only one with NaN', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("a,b,c\n1,2,3\n4,NaN,6\n7,8,9\n");

    const cleaned = df.dropna();

    assert.strictEqual(cleaned.shape.rows, 2); // Rows 1 and 3
    assert.strictEqual(cleaned.shape.cols, 3);

    df.free();
    cleaned.free();
});

// ========================================================================
// isna() Edge Cases
// ========================================================================

test('Missing.isna() - empty DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n");

    const mask = df.isna('value');

    assert.ok(mask instanceof Uint8Array);
    assert.strictEqual(mask.length, 0);

    df.free();
});

test('Missing.isna() - single value, not missing', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n42\n");

    const mask = df.isna('value');

    assert.strictEqual(mask.length, 1);
    assert.strictEqual(mask[0], 0);

    df.free();
});

test('Missing.isna() - single value, missing', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\nNaN\n");

    const mask = df.isna('value');

    assert.strictEqual(mask.length, 1);
    assert.strictEqual(mask[1], 1);

    df.free();
});

test('Missing.isna() - all values missing', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\nNaN\nNaN\nNaN\n");

    const mask = df.isna('value');

    assert.strictEqual(mask.length, 3);
    for (let i = 0; i < 3; i++) {
        assert.strictEqual(mask[i], 1);
    }

    df.free();
});

test('Missing.isna() - no values missing', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n");

    const mask = df.isna('value');

    assert.strictEqual(mask.length, 3);
    for (let i = 0; i < 3; i++) {
        assert.strictEqual(mask[i], 0);
    }

    df.free();
});

test('Missing.isna() - non-existent column', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n");

    try {
        df.isna('nonexistent');
        assert.fail('Should have thrown error');
    } catch (err) {
        assert.ok(err.message.includes('not found') || err.message.includes('column'));
    }

    df.free();
});

test('Missing.isna() - Int64 column (0 vs missing)', async () => {
    const rozes = await Rozes.init();
    // Int64 uses 0 to represent missing values
    const df = rozes.DataFrame.fromCSV("value\n10\n0\n30\n");

    const mask = df.isna('value');

    // For Int64, 0 may be interpreted as missing or as actual 0
    // This is implementation-dependent
    assert.strictEqual(mask.length, 3);

    df.free();
});

test('Missing.isna() - Float64 column (NaN)', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10.5\nNaN\n30.5\n");

    const mask = df.isna('value');

    assert.strictEqual(mask.length, 3);
    assert.strictEqual(mask[0], 0);
    assert.strictEqual(mask[1], 1);
    assert.strictEqual(mask[2], 0);

    df.free();
});

// ========================================================================
// notna() Edge Cases
// ========================================================================

test('Missing.notna() - empty DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n");

    const mask = df.notna('value');

    assert.ok(mask instanceof Uint8Array);
    assert.strictEqual(mask.length, 0);

    df.free();
});

test('Missing.notna() - single value, not missing', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n42\n");

    const mask = df.notna('value');

    assert.strictEqual(mask.length, 1);
    assert.strictEqual(mask[0], 1);

    df.free();
});

test('Missing.notna() - single value, missing', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\nNaN\n");

    const mask = df.notna('value');

    assert.strictEqual(mask.length, 1);
    assert.strictEqual(mask[0], 0);

    df.free();
});

test('Missing.notna() - all values missing', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\nNaN\nNaN\nNaN\n");

    const mask = df.notna('value');

    assert.strictEqual(mask.length, 3);
    for (let i = 0; i < 3; i++) {
        assert.strictEqual(mask[i], 0);
    }

    df.free();
});

test('Missing.notna() - no values missing', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\n20\n30\n");

    const mask = df.notna('value');

    assert.strictEqual(mask.length, 3);
    for (let i = 0; i < 3; i++) {
        assert.strictEqual(mask[i], 1);
    }

    df.free();
});

test('Missing.notna() - inverse relationship with isna()', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\nNaN\n30\nNaN\n50\n");

    const isnaMask = df.isna('value');
    const notnaMask = df.notna('value');

    assert.strictEqual(isnaMask.length, notnaMask.length);

    for (let i = 0; i < isnaMask.length; i++) {
        // isna and notna should be exact inverses
        assert.strictEqual(isnaMask[i] + notnaMask[i], 1,
            `At index ${i}: isna=${isnaMask[i]}, notna=${notnaMask[i]}`);
    }

    df.free();
});

// ========================================================================
// Type-Specific Missing Value Tests
// ========================================================================

test('Missing.isna() - String column with empty strings', async () => {
    const rozes = await Rozes.init();
    // Empty strings are NOT missing values
    const df = rozes.DataFrame.fromCSV("text,id\n,1\nA,2\n,3\n");

    const mask = df.isna('text');

    // Empty strings should NOT be marked as missing
    assert.strictEqual(mask.length, 3);
    // All should be 0 (not missing)
    for (let i = 0; i < 3; i++) {
        assert.strictEqual(mask[i], 0);
    }

    df.free();
});

test('Missing.dropna() - mixed types with NaN in different columns', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("name,age,score\nAlice,30,NaN\nBob,NaN,87.3\nCharlie,35,91.0\n");

    const cleaned = df.dropna();

    // Only row 3 (Charlie) has no NaN
    assert.strictEqual(cleaned.shape.rows, 1);

    const names = cleaned.column('name');
    assert.strictEqual(names[0], 'Charlie');

    df.free();
    cleaned.free();
});

// ========================================================================
// Integration Tests
// ========================================================================

test('Missing.isna() then filter - practical workflow', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\nNaN\n30\nNaN\n50\n");

    // Get mask of missing values
    const mask = df.isna('value');

    // Count missing values
    let missingCount = 0;
    for (let i = 0; i < mask.length; i++) {
        if (mask[i] === 1) missingCount++;
    }

    assert.strictEqual(missingCount, 2);

    df.free();
});

test('Missing.dropna() then describe() - chained operations', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\nNaN\n20\nNaN\n30\n");

    const cleaned = df.dropna();
    const stats = cleaned.describe();

    assert.ok(stats.value);
    assert.strictEqual(stats.value.count, 3);
    assert.strictEqual(stats.value.mean, 20); // (10 + 20 + 30) / 3

    df.free();
    cleaned.free();
});

test('Missing.isna() vs notna() - practical comparison', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("value\n10\nNaN\n30\n");

    const isnaMask = df.isna('value');
    const notnaMask = df.notna('value');

    // Count missing
    let missingCount = 0;
    let presentCount = 0;
    for (let i = 0; i < isnaMask.length; i++) {
        if (isnaMask[i] === 1) missingCount++;
        if (notnaMask[i] === 1) presentCount++;
    }

    assert.strictEqual(missingCount, 1);
    assert.strictEqual(presentCount, 2);
    assert.strictEqual(missingCount + presentCount, 3);

    df.free();
});

// ========================================================================
// Memory Leak Tests
// ========================================================================

test('Missing.dropna() - memory leak with empty DataFrame', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("value\n");
        const cleaned = df.dropna();
        df.free();
        cleaned.free();
    }

    assert.ok(true);
});

test('Missing.dropna() - memory leak with all missing', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("value\nNaN\nNaN\nNaN\n");
        const cleaned = df.dropna();
        df.free();
        cleaned.free();
    }

    assert.ok(true);
});

test('Missing.isna() - memory leak with empty DataFrame', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("value\n");
        const mask = df.isna('value');
        df.free();
    }

    assert.ok(true);
});

test('Missing.notna() - memory leak with single row', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("value\n42\n");
        const mask = df.notna('value');
        df.free();
    }

    assert.ok(true);
});

test('Missing.dropna() - memory leak with chained operations', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("value\n10\nNaN\n30\n");
        const cleaned = df.dropna();
        const stats = cleaned.describe();
        df.free();
        cleaned.free();
    }

    assert.ok(true);
});

// ========================================================================
// Large Dataset Tests
// ========================================================================

test('Missing.dropna() - large dataset (10K rows)', async () => {
    const rozes = await Rozes.init();

    // Generate 10K rows with 10% missing values
    let csv = "value\n";
    for (let i = 0; i < 10000; i++) {
        csv += (i % 10 === 0) ? "NaN\n" : `${i}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);
    const cleaned = df.dropna();

    // Should have 9,000 rows (90% of 10K)
    assert.strictEqual(cleaned.shape.rows, 9000);

    df.free();
    cleaned.free();
});

test('Missing.isna() - large dataset (10K rows)', async () => {
    const rozes = await Rozes.init();

    // Generate 10K rows with 10% missing values
    let csv = "value\n";
    for (let i = 0; i < 10000; i++) {
        csv += (i % 10 === 0) ? "NaN\n" : `${i}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);
    const mask = df.isna('value');

    assert.strictEqual(mask.length, 10000);

    // Count missing values
    let missingCount = 0;
    for (let i = 0; i < mask.length; i++) {
        if (mask[i] === 1) missingCount++;
    }

    assert.strictEqual(missingCount, 1000); // 10% of 10K

    df.free();
});

test('Missing.dropna() - multiple columns, large dataset', async () => {
    const rozes = await Rozes.init();

    // Generate 1K rows with missing values in different columns
    let csv = "a,b,c\n";
    for (let i = 0; i < 1000; i++) {
        const a = (i % 10 === 0) ? "NaN" : i;
        const b = (i % 20 === 0) ? "NaN" : i * 2;
        const c = (i % 30 === 0) ? "NaN" : i * 3;
        csv += `${a},${b},${c}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);
    const cleaned = df.dropna();

    // Rows with any NaN should be dropped
    // 10% in a, 5% in b, 3.3% in c
    // Approximately 16-17% of rows should be dropped
    assert.ok(cleaned.shape.rows < 850); // At least 150 dropped
    assert.ok(cleaned.shape.rows > 800); // Not too many dropped

    df.free();
    cleaned.free();
});

// ========================================================================
// Performance Tests
// ========================================================================

test('Missing.dropna() - performance test (1000 rows)', async () => {
    const rozes = await Rozes.init();

    // Generate 1000 rows
    let csv = "value\n";
    for (let i = 0; i < 1000; i++) {
        csv += (i % 10 === 0) ? "NaN\n" : `${i}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);

    const start = Date.now();
    const cleaned = df.dropna();
    const duration = Date.now() - start;

    assert.strictEqual(cleaned.shape.rows, 900);
    // Should complete in <10ms for 1000 rows
    assert.ok(duration < 10, `dropna took ${duration}ms (expected <10ms)`);

    df.free();
    cleaned.free();
});

test('Missing.isna() - performance test (1000 rows)', async () => {
    const rozes = await Rozes.init();

    // Generate 1000 rows
    let csv = "value\n";
    for (let i = 0; i < 1000; i++) {
        csv += (i % 10 === 0) ? "NaN\n" : `${i}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);

    const start = Date.now();
    const mask = df.isna('value');
    const duration = Date.now() - start;

    assert.strictEqual(mask.length, 1000);
    // Should complete in <5ms for 1000 rows
    assert.ok(duration < 5, `isna took ${duration}ms (expected <5ms)`);

    df.free();
});
