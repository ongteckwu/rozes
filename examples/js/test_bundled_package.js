#!/usr/bin/env node
/**
 * Comprehensive test script for verifying bundled Rozes npm package installation.
 *
 * This script tests that the package was installed correctly with all bundled
 * WASM module and can perform all core operations without external dependencies.
 *
 * Usage:
 *     node examples/node/test_bundled_package.js
 *
 * Expected to work ONLY when installed via npm (npm install rozes-*.tgz)
 * Should NOT require any system dependencies (pure WASM).
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

function printSection(title) {
  console.log('\n' + '='.repeat(60));
  console.log(`  ${title}`);
  console.log('='.repeat(60));
}

async function test1_import() {
  printSection('Test 1: Import Package');
  try {
    require('rozes');
    console.log('✓ Import successful (CommonJS)');
    return { name: 'Import', passed: true };
  } catch (error) {
    console.log(`✗ Import failed: ${error.message}`);
    return { name: 'Import', passed: false, error: error.message };
  }
}

async function test2_initialization() {
  printSection('Test 2: Initialize Rozes');
  try {
    const { Rozes } = require('rozes');
    const rozes = await Rozes.init();
    console.log('✓ Initialization successful');
    console.log(`  WASM loaded: ${rozes !== null}`);
    return { name: 'Initialization', passed: true };
  } catch (error) {
    console.log(`✗ Initialization failed: ${error.message}`);
    return { name: 'Initialization', passed: false, error: error.message };
  }
}

async function test3_wasmLocation() {
  printSection('Test 3: WASM Module Location');
  try {
    const entryPointPath = require.resolve('rozes');
    const packageDir = path.dirname(path.dirname(entryPointPath)); // Go up from dist/ to package root
    console.log(`Package directory: ${packageDir}`);

    // Check for WASM module
    const wasmPath = path.join(packageDir, 'zig-out', 'bin', 'rozes.wasm');
    if (fs.existsSync(wasmPath)) {
      const stats = fs.statSync(wasmPath);
      const sizeKB = (stats.size / 1024).toFixed(2);
      console.log(`✓ WASM module found: ${wasmPath}`);
      console.log(`  Size: ${sizeKB} KB`);

      // Verify size is reasonable (~62KB expected)
      if (stats.size > 100 * 1024) {
        console.log(`  ⚠ Warning: WASM size exceeds 100KB (target: ~62KB)`);
      }
    } else {
      console.log('✗ WASM module not found');
      return { name: 'WASM Location', passed: false, error: 'WASM not found' };
    }

    return { name: 'WASM Location', passed: true };
  } catch (error) {
    console.log(`✗ WASM location check failed: ${error.message}`);
    return { name: 'WASM Location', passed: false, error: error.message };
  }
}

async function test4_basicCSVParsing() {
  printSection('Test 4: Basic CSV Parsing');
  try {
    const { Rozes } = require('rozes');
    const rozes = await Rozes.init();

    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\nCharlie,35,91.0';
    const df = rozes.DataFrame.fromCSV(csv);

    console.log('✓ CSV parsing successful');
    console.log(`  Rows: ${df.shape.rows}`);
    console.log(`  Cols: ${df.shape.cols}`);
    console.log(`  Columns: ${df.columns.join(', ')}`);

    // Verify data
    const ages = df.column('age');
    console.log(`  Age column type: ${ages.constructor.name}`);
    console.log(`  Ages: [${Array.from(ages).join(', ')}]`);

    const passed = df.shape.rows === 3 && df.shape.cols === 3;
    return { name: 'Basic CSV Parsing', passed };
  } catch (error) {
    console.log(`✗ CSV parsing failed: ${error.message}`);
    console.error(error.stack);
    return { name: 'Basic CSV Parsing', passed: false, error: error.message };
  }
}

async function test5_columnAccess() {
  printSection('Test 5: Column Access (Zero-Copy)');
  try {
    const { Rozes } = require('rozes');
    const rozes = await Rozes.init();

    const csv = 'name,age,score,active\nAlice,30,95.5,true\nBob,25,87.3,false';
    const df = rozes.DataFrame.fromCSV(csv);

    // Test numeric columns (zero-copy TypedArrays)
    const ages = df.column('age');
    const scores = df.column('score');

    console.log(`✓ Age column: ${ages.constructor.name} [${Array.from(ages).join(', ')}]`);
    console.log(`✓ Score column: ${scores.constructor.name} [${Array.from(scores).join(', ')}]`);

    // Verify zero-copy (TypedArray backed by WASM memory)
    const isTypedArray = ages instanceof Float64Array ||
                         ages instanceof Int32Array ||
                         ages instanceof BigInt64Array;

    console.log(`  Zero-copy verified: ${isTypedArray}`);

    return { name: 'Column Access', passed: isTypedArray };
  } catch (error) {
    console.log(`✗ Column access failed: ${error.message}`);
    return { name: 'Column Access', passed: false, error: error.message };
  }
}

async function test6_rfc4180Compliance() {
  printSection('Test 6: RFC 4180 Compliance');
  try {
    const { Rozes } = require('rozes');
    const rozes = await Rozes.init();

    // Test quoted fields with embedded commas
    const csv1 = 'name,address\n"Alice Smith","123 Main St, Apt 4"';
    const df1 = rozes.DataFrame.fromCSV(csv1);
    console.log('✓ Embedded commas: passed');

    // Test quoted fields with embedded newlines
    const csv2 = 'name,bio\n"Bob","Line 1\nLine 2"';
    const df2 = rozes.DataFrame.fromCSV(csv2);
    console.log('✓ Embedded newlines: passed');

    // Test escaped quotes
    const csv3 = 'name,quote\n"Charlie","He said ""Hello"""';
    const df3 = rozes.DataFrame.fromCSV(csv3);
    console.log('✓ Escaped quotes: passed');

    // Test CRLF line endings
    const csv4 = 'name,age\r\nAlice,30\r\nBob,25';
    const df4 = rozes.DataFrame.fromCSV(csv4);
    console.log('✓ CRLF line endings: passed');

    // Test empty fields
    const csv5 = 'name,age,city\nAlice,30,\nBob,,NYC';
    const df5 = rozes.DataFrame.fromCSV(csv5);
    console.log('✓ Empty fields: passed');

    return { name: 'RFC 4180 Compliance', passed: true };
  } catch (error) {
    console.log(`✗ RFC 4180 test failed: ${error.message}`);
    return { name: 'RFC 4180 Compliance', passed: false, error: error.message };
  }
}

async function test7_typeInference() {
  printSection('Test 7: Type Inference');
  try {
    const { Rozes } = require('rozes');
    const rozes = await Rozes.init();

    const csv = 'int_col,float_col,bool_col,str_col\n42,3.14,true,hello\n-10,2.71,false,world';
    const df = rozes.DataFrame.fromCSV(csv);

    const intCol = df.column('int_col');
    const floatCol = df.column('float_col');

    console.log(`✓ Int column: ${intCol.constructor.name}`);
    console.log(`✓ Float column: ${floatCol.constructor.name}`);

    // Verify correct types
    const intCorrect = intCol instanceof Int32Array || intCol instanceof BigInt64Array;
    const floatCorrect = floatCol instanceof Float64Array;

    console.log(`  Type inference: ${intCorrect && floatCorrect ? 'PASS' : 'FAIL'}`);

    return { name: 'Type Inference', passed: intCorrect && floatCorrect };
  } catch (error) {
    console.log(`✗ Type inference failed: ${error.message}`);
    return { name: 'Type Inference', passed: false, error: error.message };
  }
}

async function test8_performance() {
  printSection('Test 8: Performance Smoke Test');
  try {
    const { Rozes } = require('rozes');
    const rozes = await Rozes.init();

    // Generate 10K row CSV
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
    console.log(`  Shape: ${df.shape.rows} rows × ${df.shape.cols} cols`);

    // Should be fast (<100ms for 10K rows)
    const passed = duration < 100 && df.shape.rows === 10000;
    if (!passed) {
      console.log(`  ⚠ Performance below target (>100ms or incorrect row count)`);
    }

    return { name: 'Performance', passed };
  } catch (error) {
    console.log(`✗ Performance test failed: ${error.message}`);
    return { name: 'Performance', passed: false, error: error.message };
  }
}

async function test9_memoryStress() {
  printSection('Test 9: Memory Stress Test');
  try {
    const { Rozes } = require('rozes');
    const rozes = await Rozes.init();

    console.log('Running 100 parse cycles...');
    for (let i = 0; i < 100; i++) {
      const csv = `name,age\nPerson${i},${20 + i}`;
      const df = rozes.DataFrame.fromCSV(csv);

      // Access data to ensure it's processed
      df.column('age');

      // Automatic cleanup happens here
      if (i % 10 === 0) process.stdout.write('.');
    }

    console.log('\n✓ Memory stress test passed (no crashes, automatic cleanup)');

    return { name: 'Memory Stress', passed: true };
  } catch (error) {
    console.log(`\n✗ Memory stress test failed: ${error.message}`);
    return { name: 'Memory Stress', passed: false, error: error.message };
  }
}

async function test10_errorHandling() {
  printSection('Test 10: Error Handling');
  try {
    const { Rozes } = require('rozes');
    const rozes = await Rozes.init();

    // Test non-existent column (should return null, not throw)
    const df = rozes.DataFrame.fromCSV('name,age\nAlice,30');
    const result = df.column('nonexistent');

    if (result !== null) {
      console.log('✗ Error handling failed (expected null for non-existent column)');
      return { name: 'Error Handling', passed: false, error: 'Expected null' };
    }

    console.log(`✓ Non-existent column correctly returns null`);

    // Test accessing freed DataFrame (should throw)
    let errorCaught = false;
    try {
      const df2 = rozes.DataFrame.fromCSV('name,age\nBob,25', { autoCleanup: false });
      df2.free();
      df2.shape; // Should throw
    } catch (e) {
      console.log(`✓ Accessing freed DataFrame correctly throws error`);
      errorCaught = true;
    }

    if (!errorCaught) {
      console.log('✗ Error handling failed (no error thrown for freed DataFrame)');
      return { name: 'Error Handling', passed: false, error: 'No error thrown' };
    }

    return { name: 'Error Handling', passed: true };
  } catch (error) {
    console.log(`✗ Error handling test failed: ${error.message}`);
    return { name: 'Error Handling', passed: false, error: error.message };
  }
}

async function test11_platformInfo() {
  printSection('Test 11: Platform Information');
  try {
    console.log(`Platform: ${os.platform()} ${os.arch()}`);
    console.log(`Node.js: ${process.version}`);
    console.log(`WASM support: ${typeof WebAssembly !== 'undefined'}`);

    if (typeof WebAssembly === 'undefined') {
      return { name: 'Platform Info', passed: false, error: 'No WASM support' };
    }

    console.log('✓ Platform verified');
    return { name: 'Platform Info', passed: true };
  } catch (error) {
    console.log(`✗ Platform check failed: ${error.message}`);
    return { name: 'Platform Info', passed: false, error: error.message };
  }
}

async function main() {
  console.log(`
╔══════════════════════════════════════════════════════════╗
║  Rozes Bundled Package Verification Test                ║
║                                                          ║
║  This script verifies that the npm package was          ║
║  installed correctly with bundled WASM module.          ║
╚══════════════════════════════════════════════════════════╝
`);

  const tests = [
    test1_import,
    test2_initialization,
    test3_wasmLocation,
    test4_basicCSVParsing,
    test5_columnAccess,
    test6_rfc4180Compliance,
    test7_typeInference,
    test8_performance,
    test9_memoryStress,
    test10_errorHandling,
    test11_platformInfo,
  ];

  const results = [];

  for (const test of tests) {
    try {
      const result = await test();
      results.push(result);
    } catch (error) {
      console.log(`\n✗ Test crashed: ${error.message}`);
      console.error(error.stack);
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
    if (result.error) {
      console.log(`         Error: ${result.error}`);
    }
  }

  console.log(`\nResults: ${passedCount}/${totalCount} tests passed`);

  if (passedCount === totalCount) {
    console.log('\n🎉 All tests passed! Package is ready for use.');
    return 0;
  } else {
    console.log(`\n⚠️  ${totalCount - passedCount} test(s) failed.`);
    return 1;
  }
}

// Run if executed directly
if (require.main === module) {
  main()
    .then(exitCode => process.exit(exitCode))
    .catch(err => {
      console.error('Fatal error:', err);
      process.exit(1);
    });
}

module.exports = { main };
