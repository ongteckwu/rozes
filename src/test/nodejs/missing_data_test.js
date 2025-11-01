/**
 * Rozes DataFrame - Missing Data Operations Tests
 *
 * Tests for dropna(), isna(), and notna() operations
 */

import { Rozes } from '../../../dist/index.js';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main() {
    console.log('🧪 Testing Missing Data Operations\n');

    // Initialize Rozes
    const wasmPath = join(__dirname, '../../../dist/rozes.wasm');
    const wasmBinary = readFileSync(wasmPath);
    const rozes = await Rozes.init(wasmBinary);
    const DataFrame = rozes.DataFrame;

    let passed = 0;
    let failed = 0;

    function assert(condition, message) {
        if (!condition) {
            console.error(`❌ FAIL: ${message}`);
            failed++;
            throw new Error(message);
        }
        passed++;
    }

    // ========================================================================
    // dropna() Tests
    // ========================================================================

    console.log('Testing dropna()...');

    // Test: Drop rows with NaN values
    {
        const csv = "age,score\n30,95.5\n25,NaN\n35,91.0\n";
        const df = DataFrame.fromCSV(csv);
        const cleaned = df.dropna();

        assert(cleaned.shape.rows === 2, 'Should have 2 rows after dropping NaN');
        assert(cleaned.shape.cols === 2, 'Should still have 2 columns');

        const ages = cleaned.column('age');
        assert(Number(ages[0]) === 30 && Number(ages[1]) === 35, 'Ages should be correct');

        const scores = cleaned.column('score');
        assert(scores[0] === 95.5 && scores[1] === 91.0, 'Scores should be correct');

        cleaned.free();
        df.free();
        console.log('  ✅ Drop rows with NaN values');
    }

    // Test: Handle DataFrames with no missing values
    {
        const csv = "age,score\n30,95.5\n25,87.3\n35,91.0\n";
        const df = DataFrame.fromCSV(csv);
        const cleaned = df.dropna();

        assert(cleaned.shape.rows === 3, 'Should keep all rows');
        assert(cleaned.shape.cols === 2, 'Should keep all columns');

        cleaned.free();
        df.free();
        console.log('  ✅ Handle DataFrames with no missing values');
    }

    // Test: Handle DataFrames with all missing values
    {
        const csv = "age,score\nNaN,NaN\nNaN,NaN\n";
        const df = DataFrame.fromCSV(csv);
        const cleaned = df.dropna();

        assert(cleaned.shape.rows === 0, 'Should have 0 rows');
        assert(cleaned.shape.cols === 2, 'Should keep columns');

        cleaned.free();
        df.free();
        console.log('  ✅ Handle DataFrames with all missing values');
    }

    // Test: Memory leak test (1000 iterations)
    {
        const csv = "age,score\n30,95.5\n25,NaN\n35,91.0\n";
        for (let i = 0; i < 1000; i++) {
            const df = DataFrame.fromCSV(csv);
            const cleaned = df.dropna();
            cleaned.free();
            df.free();
        }
        console.log('  ✅ No memory leaks (1000 iterations)');
    }

    // ========================================================================
    // isna() Tests
    // ========================================================================

    console.log('\nTesting isna()...');

    // Test: Identify NaN values in column
    {
        const csv = "age,score\n30,95.5\n25,NaN\n35,91.0\n";
        const df = DataFrame.fromCSV(csv);
        const mask = df.isna('score');

        assert(mask instanceof Uint8Array, 'Should return Uint8Array');
        assert(mask.length === 3, 'Mask should have 3 elements');
        assert(mask[0] === 0, 'First value should not be missing');
        assert(mask[1] === 1, 'Second value should be missing');
        assert(mask[2] === 0, 'Third value should not be missing');

        df.free();
        console.log('  ✅ Identify NaN values in column');
    }

    // Test: Return all zeros for column with no missing values
    {
        const csv = "age,score\n30,95.5\n25,87.3\n35,91.0\n";
        const df = DataFrame.fromCSV(csv);
        const mask = df.isna('age');

        assert(mask.length === 3, 'Mask should have 3 elements');
        assert(mask[0] === 0 && mask[1] === 0 && mask[2] === 0, 'All should be non-missing');

        df.free();
        console.log('  ✅ Return all zeros for column with no missing values');
    }

    // Test: Return all ones for column with all missing values
    {
        const csv = "age,score\nNaN,NaN\nNaN,NaN\n";
        const df = DataFrame.fromCSV(csv);
        const mask = df.isna('score');

        assert(mask.length === 2, 'Mask should have 2 elements');
        assert(mask[0] === 1 && mask[1] === 1, 'All should be missing');

        df.free();
        console.log('  ✅ Return all ones for column with all missing values');
    }

    // Test: Memory leak test (1000 iterations)
    {
        const csv = "age,score\n30,95.5\n25,NaN\n35,91.0\n";
        for (let i = 0; i < 1000; i++) {
            const df = DataFrame.fromCSV(csv);
            const mask = df.isna('score');
            df.free();
        }
        console.log('  ✅ No memory leaks (1000 iterations)');
    }

    // ========================================================================
    // notna() Tests
    // ========================================================================

    console.log('\nTesting notna()...');

    // Test: Identify non-missing values in column
    {
        const csv = "age,score\n30,95.5\n25,NaN\n35,91.0\n";
        const df = DataFrame.fromCSV(csv);
        const mask = df.notna('score');

        assert(mask instanceof Uint8Array, 'Should return Uint8Array');
        assert(mask.length === 3, 'Mask should have 3 elements');
        assert(mask[0] === 1, 'First value should be present');
        assert(mask[1] === 0, 'Second value should be missing');
        assert(mask[2] === 1, 'Third value should be present');

        df.free();
        console.log('  ✅ Identify non-missing values in column');
    }

    // Test: Inverse of isna()
    {
        const csv = "age,score\n30,95.5\n25,NaN\n35,91.0\n";
        const df = DataFrame.fromCSV(csv);

        const isnaMask = df.isna('score');
        const notnaMask = df.notna('score');

        for (let i = 0; i < isnaMask.length; i++) {
            assert(isnaMask[i] + notnaMask[i] === 1, `isna and notna should be inverses at index ${i}`);
        }

        df.free();
        console.log('  ✅ Inverse of isna()');
    }

    // Test: Memory leak test (1000 iterations)
    {
        const csv = "age,score\n30,95.5\n25,NaN\n35,91.0\n";
        for (let i = 0; i < 1000; i++) {
            const df = DataFrame.fromCSV(csv);
            const mask = df.notna('score');
            df.free();
        }
        console.log('  ✅ No memory leaks (1000 iterations)');
    }

    // ========================================================================
    // Summary
    // ========================================================================

    console.log(`\n📊 Test Summary: ${passed} passed, ${failed} failed`);
    if (failed > 0) {
        process.exit(1);
    }
}

main().catch((err) => {
    console.error('Test error:', err);
    process.exit(1);
});
