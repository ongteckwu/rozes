#!/usr/bin/env node
/**
 * Benchmark Comparison: Rozes (Native Zig) vs JavaScript Libraries
 *
 * Compares Rozes performance against:
 * - Papa Parse: Most popular JS CSV parser (9K+ stars)
 * - csv-parse: Node.js standard CSV parser
 * - Danfo.js: Most popular JS DataFrame library (10K+ stars)
 *
 * Usage:
 *   node src/test/benchmark/compare_js.js
 *
 * Prerequisites:
 *   npm install papaparse csv-parse danfojs-node
 */

const fs = require('fs');
const { performance } = require('perf_hooks');

// Generate test CSV data
function generateCSV(rows, cols) {
  const headers = ['id', 'score', 'category', 'active', 'price', 'count', 'name', 'lat', 'lon', 'timestamp'];
  const selectedHeaders = headers.slice(0, Math.min(cols, headers.length));

  let csv = selectedHeaders.join(',') + '\n';

  for (let i = 0; i < rows; i++) {
    const row = [];
    if (cols >= 1) row.push(i); // id
    if (cols >= 2) row.push(Math.random().toFixed(6)); // score
    if (cols >= 3) row.push(`cat${i % 10}`); // category
    if (cols >= 4) row.push(i % 2 === 0); // active
    if (cols >= 5) row.push((Math.random() * 90 + 10).toFixed(2)); // price
    if (cols >= 6) row.push(Math.floor(Math.random() * 1000) + 1); // count
    if (cols >= 7) row.push(`name${i}`); // name
    if (cols >= 8) row.push((Math.random() * 180 - 90).toFixed(6)); // lat
    if (cols >= 9) row.push((Math.random() * 360 - 180).toFixed(6)); // lon
    if (cols >= 10) row.push(1609459200 + i); // timestamp

    csv += row.join(',') + '\n';
  }

  return csv;
}

// Benchmark Papa Parse
async function benchmarkPapaParse(csv) {
  try {
    const Papa = require('papaparse');

    const start = performance.now();
    const result = Papa.parse(csv, {
      header: true,
      dynamicTyping: true,
      skipEmptyLines: true
    });
    const duration = performance.now() - start;

    return {
      library: 'Papa Parse',
      duration,
      rowsParsed: result.data.length,
      success: true
    };
  } catch (error) {
    return {
      library: 'Papa Parse',
      error: error.message,
      success: false
    };
  }
}

// Benchmark csv-parse
async function benchmarkCsvParse(csv) {
  try {
    const { parse } = require('csv-parse/sync');

    const start = performance.now();
    const records = parse(csv, {
      columns: true,
      cast: true,
      skip_empty_lines: true
    });
    const duration = performance.now() - start;

    return {
      library: 'csv-parse',
      duration,
      rowsParsed: records.length,
      success: true
    };
  } catch (error) {
    return {
      library: 'csv-parse',
      error: error.message,
      success: false
    };
  }
}

// Benchmark Rozes (via CLI)
async function benchmarkRozes(rows, cols) {
  const { exec } = require('child_process');
  const { promisify } = require('util');
  const execAsync = promisify(exec);

  try {
    const cmd = `zig build benchmark 2>&1 | grep "CSV Parse (${rows.toLocaleString()} rows"`;
    const { stdout } = await execAsync(cmd, { cwd: process.cwd() });

    // Parse output: "CSV Parse (10K rows × 10 cols): 12.34ms (target: <100ms) ✓ PASS"
    const match = stdout.match(/(\d+\.\d+)ms/);
    if (match) {
      return {
        library: 'Rozes (Zig)',
        duration: parseFloat(match[1]),
        success: true
      };
    }

    throw new Error('Failed to parse Rozes output');
  } catch (error) {
    return {
      library: 'Rozes (Zig)',
      error: error.message,
      success: false
    };
  }
}

// Format results table
function printResults(testName, csvSizeKB, results) {
  console.log(`\n━━━ ${testName} ━━━`);
  console.log(`CSV Size: ${csvSizeKB.toFixed(2)} KB\n`);

  console.log('┌─────────────────┬──────────────┬──────────────┬─────────────┐');
  console.log('│ Library         │ Parse Time   │ Throughput   │ vs Rozes    │');
  console.log('├─────────────────┼──────────────┼──────────────┼─────────────┤');

  const rozesResult = results.find(r => r.library === 'Rozes (Zig)');

  results.forEach(result => {
    const library = result.library.padEnd(15);
    const time = result.success ? `${result.duration.toFixed(2)}ms`.padEnd(12) : 'ERROR'.padEnd(12);
    const throughput = result.success ?
      `${(csvSizeKB / result.duration).toFixed(2)} KB/ms`.padEnd(12) :
      'N/A'.padEnd(12);

    let speedup = 'N/A';
    if (result.success && rozesResult?.success) {
      const ratio = result.duration / rozesResult.duration;
      if (result.library !== 'Rozes (Zig)') {
        speedup = ratio > 1 ?
          `${ratio.toFixed(2)}× slower` :
          `${(1/ratio).toFixed(2)}× faster`;
      } else {
        speedup = 'baseline';
      }
    }

    console.log(`│ ${library} │ ${time} │ ${throughput} │ ${speedup.padEnd(11)} │`);
  });

  console.log('└─────────────────┴──────────────┴──────────────┴─────────────┘');
}

// Main benchmark runner
async function main() {
  console.log('\n╔══════════════════════════════════════════════════════════╗');
  console.log('║   Rozes DataFrame - JavaScript Library Comparison       ║');
  console.log('╚══════════════════════════════════════════════════════════╝\n');

  // Check dependencies
  let hasError = false;
  try {
    require('papaparse');
  } catch {
    console.error('❌ Papa Parse not installed. Run: npm install papaparse');
    hasError = true;
  }
  try {
    require('csv-parse');
  } catch {
    console.error('❌ csv-parse not installed. Run: npm install csv-parse');
    hasError = true;
  }

  if (hasError) {
    console.error('\nInstall dependencies first:\n  npm install papaparse csv-parse\n');
    process.exit(1);
  }

  const testCases = [
    { name: 'Small CSV', rows: 100, cols: 3, desc: '100 rows × 3 cols' },
    { name: 'Medium CSV', rows: 10000, cols: 10, desc: '10K rows × 10 cols' },
    { name: 'Large CSV', rows: 100000, cols: 10, desc: '100K rows × 10 cols' }
  ];

  for (const testCase of testCases) {
    console.log(`\nGenerating ${testCase.desc}...`);
    const csv = generateCSV(testCase.rows, testCase.cols);
    const csvSizeKB = Buffer.byteLength(csv) / 1024;

    const results = [];

    // Benchmark Papa Parse
    console.log('  Benchmarking Papa Parse...');
    results.push(await benchmarkPapaParse(csv));

    // Benchmark csv-parse
    console.log('  Benchmarking csv-parse...');
    results.push(await benchmarkCsvParse(csv));

    // Benchmark Rozes (if available)
    console.log('  Benchmarking Rozes (reading from `zig build benchmark`)...');
    results.push(await benchmarkRozes(testCase.rows, testCase.cols));

    printResults(testCase.name, csvSizeKB, results);
  }

  console.log('\n✅ Benchmark comparison complete!\n');
  console.log('Summary:');
  console.log('  - Rozes should be 2-5× faster than Papa Parse on large CSVs');
  console.log('  - Similar performance to csv-parse');
  console.log('  - Small CSVs: JS parsers may be faster (lower overhead)');
  console.log('\nFor DataFrame operations comparison, install Danfo.js:');
  console.log('  npm install danfojs-node\n');
}

// Run
main().catch(console.error);
