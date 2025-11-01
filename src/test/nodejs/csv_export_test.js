/**
 * Node.js Tests for CSV Export (Priority 5 - Milestone 1.1.0)
 *
 * Tests: toCSV() with various options and edge cases
 */

import { Rozes } from '../../../dist/index.js';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main() {
  console.log('🧪 Testing CSV Export (Priority 5)\n');

  // Initialize Rozes by reading Wasm binary directly (for Node.js)
  const wasmPath = join(__dirname, '../../../dist/rozes.wasm');
  const wasmBinary = readFileSync(wasmPath);
  const rozes = await Rozes.init(wasmBinary);
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
      console.error('   Error:', err.message);
      if (err.stack) {
        console.error('   Stack:', err.stack.split('\n').slice(1, 3).join('\n'));
      }
    }
  }

  // ============================================================================
  // Test 1: Basic CSV Export
  // ============================================================================

  test('Basic CSV export with default options', () => {
    const csvInput = `name,age,score
Alice,30,95.5
Bob,25,87.3
Charlie,35,91.0`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Should have headers and data
    if (!csvOutput.includes('name,age,score')) {
      throw new Error('Expected headers in output');
    }
    if (!csvOutput.includes('Alice,30,95.5')) {
      throw new Error('Expected data row in output');
    }
  });

  test('CSV export without headers', () => {
    const csvInput = `name,age,score
Alice,30,95.5
Bob,25,87.3`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV({ has_headers: false });
    df.free();

    // Should NOT have headers
    if (csvOutput.includes('name,age,score')) {
      throw new Error('Should not have headers');
    }
    // Should have data
    if (!csvOutput.includes('Alice,30,95.5')) {
      throw new Error('Expected data row in output');
    }
  });

  test('CSV export with tab delimiter', () => {
    const csvInput = `name,age,score
Alice,30,95.5
Bob,25,87.3`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const tsvOutput = df.toCSV({ delimiter: '\t' });
    df.free();

    // Should use tabs instead of commas
    if (!tsvOutput.includes('name\tage\tscore')) {
      throw new Error('Expected tab-separated headers');
    }
    if (!tsvOutput.includes('Alice\t30\t95.5')) {
      throw new Error('Expected tab-separated data');
    }
  });

  // ============================================================================
  // Test 2: Round-Trip Testing
  // ============================================================================

  test('Round-trip: CSV → DataFrame → CSV', () => {
    const csvInput = `name,age,city
Alice,30,NYC
Bob,25,LA
Charlie,35,SF`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Parse output back
    const df2 = rozes.DataFrame.fromCSV(csvOutput);
    const shape = df2.shape;
    df2.free();

    if (shape.rows !== 3) {
      throw new Error(`Expected 3 rows, got ${shape.rows}`);
    }
    if (shape.cols !== 3) {
      throw new Error(`Expected 3 cols, got ${shape.cols}`);
    }
  });

  test('Round-trip with numeric data preserved', () => {
    const csvInput = `age,score
30,95.5
25,87.3
35,91.0`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();

    // Parse output back
    const df2 = rozes.DataFrame.fromCSV(csvOutput);
    const ages = df2.column('age');
    const scores = df2.column('score');

    df.free();
    df2.free();

    // Check numeric values preserved
    const firstAge = ages instanceof BigInt64Array ? Number(ages[0]) : ages[0];
    const firstScore = scores[0];

    if (firstAge !== 30) {
      throw new Error(`Expected age 30, got ${firstAge}`);
    }
    if (Math.abs(firstScore - 95.5) > 0.01) {
      throw new Error(`Expected score 95.5, got ${firstScore}`);
    }
  });

  // ============================================================================
  // Test 3: Edge Cases - Special Characters
  // ============================================================================

  test('CSV export with empty strings', () => {
    const csvInput = `name,value
,10
Bob,20
,30`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Should preserve empty values
    const lines = csvOutput.trim().split('\n');
    if (lines.length !== 4) { // header + 3 rows
      throw new Error(`Expected 4 lines, got ${lines.length}`);
    }
  });

  test('CSV export with quoted fields (commas)', () => {
    const csvInput = `name,description
Alice,"Hello, World"
Bob,"Test, data"`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Should quote fields with commas
    if (!csvOutput.includes('"Hello, World"') && !csvOutput.includes('"Hello,World"')) {
      throw new Error('Expected quoted field with comma in output');
    }
  });

  test('CSV export with quoted fields (newlines)', () => {
    const csvInput = `name,bio
Alice,"Line1\nLine2"
Bob,"Test\nData"`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Should preserve newlines in quoted fields
    if (!csvOutput.includes('Line1') || !csvOutput.includes('Line2')) {
      throw new Error('Expected newlines preserved in output');
    }
  });

  test('CSV export with escaped quotes', () => {
    const csvInput = `name,quote
Alice,"She said ""Hello"""
Bob,"He said ""Hi"""`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Should escape quotes by doubling them
    if (!csvOutput.includes('""') || csvOutput.includes('\\"')) {
      throw new Error('Expected doubled quotes, not escaped quotes');
    }
  });

  test('CSV export with UTF-8 characters', () => {
    const csvInput = `name,value
Hello 世界,10
Émilie,20
🚀 Rocket,30`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Should preserve UTF-8 characters
    if (!csvOutput.includes('世界')) {
      throw new Error('Expected Chinese characters in output');
    }
    if (!csvOutput.includes('Émilie')) {
      throw new Error('Expected accented characters in output');
    }
    if (!csvOutput.includes('🚀')) {
      throw new Error('Expected emoji in output');
    }
  });

  // ============================================================================
  // Test 4: Boolean and Mixed Types
  // ============================================================================

  test('CSV export with boolean columns', () => {
    const csvInput = `name,active
Alice,true
Bob,false
Charlie,true`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Should output boolean values
    if (!csvOutput.includes('true') || !csvOutput.includes('false')) {
      throw new Error('Expected boolean values in output');
    }
  });

  test('CSV export with all column types', () => {
    const csvInput = `name,age,score,active
Alice,30,95.5,true
Bob,25,87.3,false`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Should have all data types
    const lines = csvOutput.trim().split('\n');
    if (lines.length !== 3) { // header + 2 rows
      throw new Error(`Expected 3 lines, got ${lines.length}`);
    }

    // Should preserve column order
    if (!lines[0].startsWith('name,age,score,active')) {
      throw new Error('Expected column order preserved');
    }
  });

  // ============================================================================
  // Test 5: Large DataFrames
  // ============================================================================

  test('CSV export with 1000 rows', () => {
    // Generate large CSV
    let csvInput = 'name,age,score\n';
    for (let i = 0; i < 1000; i++) {
      csvInput += `Person${i},${20 + i % 50},${80 + (i % 20)}\n`;
    }

    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Should have 1000 data rows + 1 header
    const lines = csvOutput.trim().split('\n');
    if (lines.length !== 1001) {
      throw new Error(`Expected 1001 lines, got ${lines.length}`);
    }
  });

  test('CSV export with wide DataFrame (50 columns)', () => {
    // Generate wide CSV
    const cols = [];
    const vals = [];
    for (let i = 0; i < 50; i++) {
      cols.push(`col${i}`);
      vals.push(i);
    }
    const csvInput = cols.join(',') + '\n' + vals.join(',') + '\n';

    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Should have all 50 columns
    const headerLine = csvOutput.split('\n')[0];
    const headerCols = headerLine.split(',');
    if (headerCols.length !== 50) {
      throw new Error(`Expected 50 columns, got ${headerCols.length}`);
    }
  });

  // ============================================================================
  // Test 6: Empty and Single-Row DataFrames
  // ============================================================================

  test('CSV export with single row', () => {
    const csvInput = `name,age
Alice,30`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    const lines = csvOutput.trim().split('\n');
    if (lines.length !== 2) { // header + 1 row
      throw new Error(`Expected 2 lines, got ${lines.length}`);
    }
  });

  test('CSV export with empty DataFrame (headers only)', () => {
    const csvInput = `name,age,score\n`;
    const df = rozes.DataFrame.fromCSV(csvInput);
    const csvOutput = df.toCSV();
    df.free();

    // Should have only headers
    const lines = csvOutput.trim().split('\n');
    if (lines.length !== 1 || !lines[0].includes('name,age,score')) {
      throw new Error('Expected only header row for empty DataFrame');
    }
  });

  // ============================================================================
  // Results
  // ============================================================================

  console.log(`\n${'='.repeat(60)}`);
  console.log(`Results: ${passedTests}/${totalTests} tests passed`);
  console.log('='.repeat(60));

  if (passedTests === totalTests) {
    console.log('\n✅ All tests passed!');
    process.exit(0);
  } else {
    console.log(`\n❌ ${totalTests - passedTests} test(s) failed`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
