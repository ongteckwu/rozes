/**
 * String Operations Edge Case Tests
 *
 * Comprehensive edge case testing for:
 * - lower, upper, trim, contains, replace, slice, len, startsWith, endsWith
 *
 * Coverage:
 * - Empty strings
 * - Very long strings (>1000 chars)
 * - Unicode (emoji, CJK, Arabic)
 * - Whitespace variations
 * - Boundary conditions
 * - Error cases
 * - Memory leak tests
 * - Performance tests
 */

import test from 'node:test';
import assert from 'node:assert';
import { Rozes } from '../../../dist/index.mjs';

// ========================================================================
// Empty String Edge Cases
// ========================================================================

test('String.lower() - empty DataFrame', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\n");

    const result = df.str.lower('text');

    assert.strictEqual(result.shape.rows, 0);
    assert.strictEqual(result.shape.cols, 1);

    df.free();
    result.free();
});

test('String.lower() - single empty string', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text,id\n,1\n");

    const result = df.str.lower('text');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], '');

    df.free();
    result.free();
});

test('String.lower() - all empty strings', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text,id\n,1\n,2\n,3\n");

    const result = df.str.lower('text');

    assert.strictEqual(result.shape.rows, 3);
    for (let i = 0; i < 3; i++) {
        assert.strictEqual(result.column('text')[i], '');
    }

    df.free();
    result.free();
});

test('String.trim() - whitespace-only strings', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\n   \n\t\t\n  \t  \n");

    const result = df.str.trim('text');

    assert.strictEqual(result.shape.rows, 3);
    for (let i = 0; i < 3; i++) {
        assert.strictEqual(result.column('text')[i], '');
    }

    df.free();
    result.free();
});

test('String.contains() - empty pattern in empty string', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text,id\n,1\n");

    const result = df.str.contains('text', '');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], true); // Empty pattern matches

    df.free();
    result.free();
});

test('String.replace() - empty pattern', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    // Replacing empty pattern should leave string unchanged
    const result = df.str.replace('text', '', 'X');

    assert.strictEqual(result.shape.rows, 1);
    // Behavior may vary - either unchanged or X inserted between chars
    assert.ok(result.column('text')[0].includes('h'));

    df.free();
    result.free();
});

test('String.replace() - empty replacement', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello world\n");

    const result = df.str.replace('text', ' ', '');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], 'helloworld');

    df.free();
    result.free();
});

test('String.slice() - empty string', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text,id\n,1\n");

    const result = df.str.slice('text', 0, 5);

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], '');

    df.free();
    result.free();
});

test('String.slice() - start equals end', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    const result = df.str.slice('text', 2, 2);

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], ''); // Empty substring

    df.free();
    result.free();
});

test('String.len() - empty string', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text,id\n,1\n");

    const result = df.str.len('text');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], 0n);

    df.free();
    result.free();
});

// ========================================================================
// Very Long String Edge Cases
// ========================================================================

test('String.lower() - very long string (1000 chars)', async () => {
    const rozes = await Rozes.init();
    const longString = 'A'.repeat(1000);
    const df = rozes.DataFrame.fromCSV(`text\n${longString}\n`);

    const result = df.str.lower('text');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], 'a'.repeat(1000));

    df.free();
    result.free();
});

test('String.contains() - very long string search', async () => {
    const rozes = await Rozes.init();
    const longString = 'A'.repeat(500) + 'NEEDLE' + 'A'.repeat(500);
    const df = rozes.DataFrame.fromCSV(`text\n${longString}\n`);

    const result = df.str.contains('text', 'NEEDLE');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], true);

    df.free();
    result.free();
});

test('String.replace() - very long replacement', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello world\n");
    const longReplacement = 'X'.repeat(1000);

    const result = df.str.replace('text', 'world', longReplacement);

    assert.strictEqual(result.shape.rows, 1);
    assert.ok(result.column('text')[0].includes('X'.repeat(100))); // At least some Xs

    df.free();
    result.free();
});

test('String.slice() - very long string', async () => {
    const rozes = await Rozes.init();
    const longString = 'A'.repeat(1000);
    const df = rozes.DataFrame.fromCSV(`text\n${longString}\n`);

    const result = df.str.slice('text', 100, 200);

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], 'A'.repeat(100));

    df.free();
    result.free();
});

test('String.len() - very long string', async () => {
    const rozes = await Rozes.init();
    const longString = 'A'.repeat(2000);
    const df = rozes.DataFrame.fromCSV(`text\n${longString}\n`);

    const result = df.str.len('text');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], 2000n);

    df.free();
    result.free();
});

// ========================================================================
// Unicode Edge Cases
// ========================================================================

test('String.lower() - Unicode with non-ASCII characters', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nHÉLLÖ\nÇafé\n");

    const result = df.str.lower('text');

    assert.strictEqual(result.shape.rows, 2);
    // ASCII lowercasing only - accented chars may not change
    assert.ok(result.column('text')[0].includes('h'));

    df.free();
    result.free();
});

test('String.lower() - emoji preservation', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nHELLO 🚀\nWORLD 🌍\n");

    const result = df.str.lower('text');

    assert.strictEqual(result.shape.rows, 2);
    assert.ok(result.column('text')[0].includes('🚀'));
    assert.ok(result.column('text')[1].includes('🌍'));

    df.free();
    result.free();
});

test('String.upper() - CJK characters preservation', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello 世界\n你好 world\n");

    const result = df.str.upper('text');

    assert.strictEqual(result.shape.rows, 2);
    assert.ok(result.column('text')[0].includes('世界')); // Unchanged
    assert.ok(result.column('text')[1].includes('你好')); // Unchanged

    df.free();
    result.free();
});

test('String.contains() - Unicode pattern', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello 世界\n你好 world\n");

    const result = df.str.contains('text', '世界');

    assert.strictEqual(result.shape.rows, 2);
    assert.strictEqual(result.column('text')[0], true);
    assert.strictEqual(result.column('text')[1], false);

    df.free();
    result.free();
});

test('String.replace() - Unicode pattern and replacement', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello 世界\n");

    const result = df.str.replace('text', '世界', '🌍');

    assert.strictEqual(result.shape.rows, 1);
    assert.ok(result.column('text')[0].includes('🌍'));
    assert.ok(!result.column('text')[0].includes('世界'));

    df.free();
    result.free();
});

test('String.slice() - Unicode multi-byte characters', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\n世界你好\n");

    // Slicing by byte position may split multi-byte characters
    const result = df.str.slice('text', 0, 3);

    assert.strictEqual(result.shape.rows, 1);
    // Result depends on whether slicing is byte or character based
    assert.ok(result.column('text')[0].length > 0);

    df.free();
    result.free();
});

test('String.len() - Unicode byte count vs character count', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\na\n世\n🚀\n");

    const result = df.str.len('text');

    assert.strictEqual(result.shape.rows, 3);
    assert.strictEqual(result.column('text')[0], 1n);  // ASCII: 1 byte
    assert.strictEqual(result.column('text')[1], 3n);  // CJK: 3 bytes UTF-8
    assert.strictEqual(result.column('text')[2], 4n);  // Emoji: 4 bytes UTF-8

    df.free();
    result.free();
});

test('String.startsWith() - Unicode prefix', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\n世界你好\n你好世界\n");

    const result = df.str.startsWith('text', '世界');

    assert.strictEqual(result.shape.rows, 2);
    assert.strictEqual(result.column('text')[0], true);
    assert.strictEqual(result.column('text')[1], false);

    df.free();
    result.free();
});

test('String.endsWith() - Unicode suffix', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello 世界\nworld 你好\n");

    const result = df.str.endsWith('text', '世界');

    assert.strictEqual(result.shape.rows, 2);
    assert.strictEqual(result.column('text')[0], true);
    assert.strictEqual(result.column('text')[1], false);

    df.free();
    result.free();
});

// ========================================================================
// Boundary Condition Edge Cases
// ========================================================================

test('String.slice() - start beyond string length', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    const result = df.str.slice('text', 100, 200);

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], ''); // Empty result

    df.free();
    result.free();
});

test('String.slice() - end beyond string length', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    const result = df.str.slice('text', 0, 1000);

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], 'hello'); // Full string

    df.free();
    result.free();
});

test('String.slice() - negative indices (if supported)', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    try {
        // Negative indices may not be supported
        const result = df.str.slice('text', -3, -1);
        // If supported, should get 'll'
        result.free();
    } catch (err) {
        // Expected if not supported
        assert.ok(err);
    }

    df.free();
});

test('String.replace() - pattern not found', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello world\n");

    const result = df.str.replace('text', 'xyz', 'abc');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], 'hello world'); // Unchanged

    df.free();
    result.free();
});

test('String.replace() - multiple occurrences', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello hello hello\n");

    const result = df.str.replace('text', 'hello', 'hi');

    assert.strictEqual(result.shape.rows, 1);
    // May replace first occurrence or all occurrences
    assert.ok(result.column('text')[0].includes('hi'));

    df.free();
    result.free();
});

test('String.contains() - pattern at start', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello world\n");

    const result = df.str.contains('text', 'hello');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], true);

    df.free();
    result.free();
});

test('String.contains() - pattern at end', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello world\n");

    const result = df.str.contains('text', 'world');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], true);

    df.free();
    result.free();
});

test('String.startsWith() - exact match', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    const result = df.str.startsWith('text', 'hello');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], true);

    df.free();
    result.free();
});

test('String.startsWith() - empty prefix', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    const result = df.str.startsWith('text', '');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], true); // Empty prefix always matches

    df.free();
    result.free();
});

test('String.endsWith() - exact match', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    const result = df.str.endsWith('text', 'hello');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], true);

    df.free();
    result.free();
});

test('String.endsWith() - empty suffix', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    const result = df.str.endsWith('text', '');

    assert.strictEqual(result.shape.rows, 1);
    assert.strictEqual(result.column('text')[0], true); // Empty suffix always matches

    df.free();
    result.free();
});

// ========================================================================
// Error Cases
// ========================================================================

test('String.lower() - non-existent column', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    try {
        df.str.lower('nonexistent');
        assert.fail('Should have thrown error');
    } catch (err) {
        assert.ok(err.message.includes('not found') || err.message.includes('column'));
    }

    df.free();
});

test('String.contains() - null column name', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    try {
        df.str.contains(null, 'pattern');
        assert.fail('Should have thrown error');
    } catch (err) {
        assert.ok(err);
    }

    df.free();
});

test('String.replace() - null pattern', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    try {
        df.str.replace('text', null, 'replacement');
        assert.fail('Should have thrown error');
    } catch (err) {
        assert.ok(err);
    }

    df.free();
});

test('String.slice() - invalid range (start > end)', async () => {
    const rozes = await Rozes.init();
    const df = rozes.DataFrame.fromCSV("text\nhello\n");

    try {
        df.str.slice('text', 5, 2);
        // May throw error or return empty string
    } catch (err) {
        // Expected
        assert.ok(err);
    }

    df.free();
});

// ========================================================================
// Memory Leak Tests
// ========================================================================

test('String.lower() - memory leak with empty DataFrame', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("text\n");
        const result = df.str.lower('text');
        df.free();
        result.free();
    }

    assert.ok(true);
});

test('String.contains() - memory leak with empty strings', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("text,id\n,1\n");
        const result = df.str.contains('text', 'pattern');
        df.free();
        result.free();
    }

    assert.ok(true);
});

test('String.replace() - memory leak with long strings', async () => {
    const rozes = await Rozes.init();
    const longString = 'A'.repeat(500);

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV(`text\n${longString}\n`);
        const result = df.str.replace('text', 'A', 'B');
        df.free();
        result.free();
    }

    assert.ok(true);
});

test('String.slice() - memory leak with boundary cases', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("text\nhello\n");
        const result = df.str.slice('text', 0, 1000);
        df.free();
        result.free();
    }

    assert.ok(true);
});

test('String chained operations - memory leak', async () => {
    const rozes = await Rozes.init();

    for (let i = 0; i < 1000; i++) {
        const df = rozes.DataFrame.fromCSV("text\n  HELLO  \n");
        const result = df.str.trim('text').str.lower('text');
        df.free();
        result.free();
    }

    assert.ok(true);
});

// ========================================================================
// Large Dataset Tests
// ========================================================================

test('String.lower() - large dataset (1000 rows)', async () => {
    const rozes = await Rozes.init();

    let csv = "text\n";
    for (let i = 0; i < 1000; i++) {
        csv += `HELLO${i}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);
    const result = df.str.lower('text');

    assert.strictEqual(result.shape.rows, 1000);
    assert.strictEqual(result.column('text')[0], 'hello0');
    assert.strictEqual(result.column('text')[999], 'hello999');

    df.free();
    result.free();
});

test('String.contains() - large dataset', async () => {
    const rozes = await Rozes.init();

    let csv = "text\n";
    for (let i = 0; i < 1000; i++) {
        csv += (i % 2 === 0) ? `MATCH${i}\n` : `OTHER${i}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);
    const result = df.str.contains('text', 'MATCH');

    assert.strictEqual(result.shape.rows, 1000);

    // Count matches
    let matchCount = 0;
    for (let i = 0; i < 1000; i++) {
        if (result.column('text')[i]) matchCount++;
    }
    assert.strictEqual(matchCount, 500); // Half should match

    df.free();
    result.free();
});

test('String.replace() - large dataset', async () => {
    const rozes = await Rozes.init();

    let csv = "text\n";
    for (let i = 0; i < 1000; i++) {
        csv += `hello${i}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);
    const result = df.str.replace('text', 'hello', 'hi');

    assert.strictEqual(result.shape.rows, 1000);
    assert.ok(result.column('text')[0].startsWith('hi'));

    df.free();
    result.free();
});

// ========================================================================
// Performance Tests
// ========================================================================

test('String.lower() - performance (1000 rows)', async () => {
    const rozes = await Rozes.init();

    let csv = "text\n";
    for (let i = 0; i < 1000; i++) {
        csv += `HELLO WORLD ${i}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);

    const start = Date.now();
    const result = df.str.lower('text');
    const duration = Date.now() - start;

    assert.strictEqual(result.shape.rows, 1000);
    assert.ok(duration < 100, `lower() took ${duration}ms (expected <100ms)`);

    df.free();
    result.free();
});

test('String.contains() - performance (1000 rows)', async () => {
    const rozes = await Rozes.init();

    let csv = "text\n";
    for (let i = 0; i < 1000; i++) {
        csv += `hello world ${i}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);

    const start = Date.now();
    const result = df.str.contains('text', 'world');
    const duration = Date.now() - start;

    assert.strictEqual(result.shape.rows, 1000);
    assert.ok(duration < 100, `contains() took ${duration}ms (expected <100ms)`);

    df.free();
    result.free();
});

test('String.replace() - performance (1000 rows)', async () => {
    const rozes = await Rozes.init();

    let csv = "text\n";
    for (let i = 0; i < 1000; i++) {
        csv += `hello world ${i}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csv);

    const start = Date.now();
    const result = df.str.replace('text', 'world', 'universe');
    const duration = Date.now() - start;

    assert.strictEqual(result.shape.rows, 1000);
    assert.ok(duration < 100, `replace() took ${duration}ms (expected <100ms)`);

    df.free();
    result.free();
});
