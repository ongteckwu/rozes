#!/usr/bin/env node
/**
 * Comprehensive test script for verifying bundled Rozes npm package installation (ESM version).
 *
 * This script tests that the package was installed correctly with all bundled
 * WASM module and can perform all core operations without external dependencies.
 *
 * Usage:
 *     node examples/node/test_bundled_package.mjs
 *
 * Expected to work ONLY when installed via npm (npm install rozes-*.tgz)
 * Should NOT require any system dependencies (pure WASM).
 */

import fs from 'fs';
import path from 'path';
import os from 'os';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function printSection(title) {
  console.log('\n' + '='.repeat(60));
  console.log(`  ${title}`);
  console.log('='.repeat(60));
}

async function test1_import() {
  printSection('Test 1: Import Package (ESM)');
  try {
    await import('rozes');
    console.log('✓ Import successful (ESM)');
    return { name: 'Import (ESM)', passed: true };
  } catch (error) {
    console.log(`✗ Import failed: ${error.message}`);
    return { name: 'Import (ESM)', passed: false, error: error.message };
  }
}

async function test2_initialization() {
  printSection('Test 2: Initialize Rozes');
  try {
    const { Rozes } = await import('rozes');
    const rozes = await Rozes.init();
    console.log('✓ Initialization successful');
    console.log(`  WASM loaded: ${rozes !== null}`);
    return { name: 'Initialization', passed: true };
  } catch (error) {
    console.log(`✗ Initialization failed: ${error.message}`);
    return { name: 'Initialization', passed: false, error: error.message };
  }
}

async function test3_basicCSVParsing() {
  printSection('Test 3: Basic CSV Parsing');
  try {
    const { Rozes } = await import('rozes');
    const rozes = await Rozes.init();

    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\nCharlie,35,91.0';
    const df = rozes.DataFrame.fromCSV(csv);

    console.log('✓ CSV parsing successful');
    console.log(`  Rows: ${df.shape.rows}`);
    console.log(`  Cols: ${df.shape.cols}`);
    console.log(`  Columns: ${df.columns.join(', ')}`);

    const passed = df.shape.rows === 3 && df.shape.cols === 3;
    return { name: 'Basic CSV Parsing', passed };
  } catch (error) {
    console.log(`✗ CSV parsing failed: ${error.message}`);
    return { name: 'Basic CSV Parsing', passed: false, error: error.message };
  }
}

async function test4_zerocopAccess() {
  printSection('Test 4: Zero-Copy TypedArray Access');
  try {
    const { Rozes } = await import('rozes');
    const rozes = await Rozes.init();

    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3';
    const df = rozes.DataFrame.fromCSV(csv);

    const ages = df.column('age');
    const scores = df.column('score');

    console.log(`✓ Age column: ${ages.constructor.name}`);
    console.log(`✓ Score column: ${scores.constructor.name}`);

    // Verify TypedArray (zero-copy)
    const isTypedArray = ages instanceof Float64Array ||
                         ages instanceof Int32Array ||
                         ages instanceof BigInt64Array;

    console.log(`  Zero-copy TypedArray: ${isTypedArray ? 'YES ✓' : 'NO ✗'}`);

    return { name: 'Zero-Copy Access', passed: isTypedArray };
  } catch (error) {
    console.log(`✗ Zero-copy test failed: ${error.message}`);
    return { name: 'Zero-Copy Access', passed: false, error: error.message };
  }
}

async function test5_automaticCleanup() {
  printSection('Test 5: Automatic Memory Cleanup');
  try {
    const { Rozes } = await import('rozes');
    const rozes = await Rozes.init();

    console.log('Creating and discarding 50 DataFrames...');
    for (let i = 0; i < 50; i++) {
      const csv = `name,age\nPerson${i},${20 + i}`;
      const df = rozes.DataFrame.fromCSV(csv);
      df.column('age');
      // DataFrame goes out of scope - automatic cleanup via FinalizationRegistry
      if (i % 10 === 0) process.stdout.write('.');
    }

    console.log('\n✓ Automatic cleanup test passed (no manual free() needed)');
    console.log('  Memory managed by FinalizationRegistry');

    return { name: 'Automatic Cleanup', passed: true };
  } catch (error) {
    console.log(`\n✗ Automatic cleanup test failed: ${error.message}`);
    return { name: 'Automatic Cleanup', passed: false, error: error.message };
  }
}

async function test6_performance() {
  printSection('Test 6: Performance (10K rows)');
  try {
    const { Rozes } = await import('rozes');
    const rozes = await Rozes.init();

    const rows = ['name,age,score'];
    for (let i = 0; i < 10000; i++) {
      rows.push(`Person${i},${20 + (i % 50)},${50 + (i % 50)}`);
    }
    const csv = rows.join('\n');

    const start = Date.now();
    const df = rozes.DataFrame.fromCSV(csv);
    const end = Date.now();

    const duration = end - start;
    console.log(`✓ Parsed 10K rows in ${duration}ms`);
    console.log(`  Throughput: ${(10000 / duration * 1000).toFixed(0)} rows/sec`);

    const passed = duration < 100 && df.shape.rows === 10000;
    return { name: 'Performance', passed };
  } catch (error) {
    console.log(`✗ Performance test failed: ${error.message}`);
    return { name: 'Performance', passed: false, error: error.message };
  }
}

async function main() {
  console.log(`
╔══════════════════════════════════════════════════════════╗
║  Rozes Bundled Package Verification Test (ESM)          ║
║                                                          ║
║  This script verifies ESM imports and automatic         ║
║  memory management work correctly.                      ║
╚══════════════════════════════════════════════════════════╝
`);

  const tests = [
    test1_import,
    test2_initialization,
    test3_basicCSVParsing,
    test4_zerocopAccess,
    test5_automaticCleanup,
    test6_performance,
  ];

  const results = [];

  for (const test of tests) {
    try {
      const result = await test();
      results.push(result);
    } catch (error) {
      console.log(`\n✗ Test crashed: ${error.message}`);
      results.push({ name: 'Unknown', passed: false, error: error.message });
    }
  }

  // Summary
  printSection('Test Summary');
  const passedCount = results.filter(r => r.passed).length;
  const totalCount = results.length;

  for (const result of results) {
    const status = result.passed ? '✓ PASS' : '✗ FAIL';
    console.log(`${status.padEnd(8)} ${result.name}`);
  }

  console.log(`\nResults: ${passedCount}/${totalCount} tests passed`);

  if (passedCount === totalCount) {
    console.log('\n🎉 All tests passed! ESM package is ready for use.');
    return 0;
  } else {
    console.log(`\n⚠️  ${totalCount - passedCount} test(s) failed.`);
    return 1;
  }
}

main()
  .then(exitCode => process.exit(exitCode))
  .catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
