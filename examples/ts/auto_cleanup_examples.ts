/**
 * Rozes DataFrame - Auto Cleanup Examples (TypeScript)
 *
 * This file demonstrates the two memory management approaches in TypeScript:
 * 1. Manual cleanup (default - recommended for production)
 * 2. Auto cleanup (convenient for prototyping)
 *
 * Compile: npx tsc examples/node/auto_cleanup_examples.ts
 * Run: node examples/node/auto_cleanup_examples.js
 */

import { Rozes, DataFrame, CSVOptions } from '../../dist/index';

// Sample CSV data
const salesData = `date,product,quantity,revenue
2024-01-01,Widget A,100,1500.00
2024-01-01,Widget B,50,750.00
2024-01-02,Widget A,120,1800.00
2024-01-02,Widget C,80,1200.00
2024-01-03,Widget B,90,1350.00`;

/**
 * Example 1: Manual Memory Management (Production Recommended)
 *
 * ✅ Best for: Production code, performance-critical applications
 * ✅ Advantages:
 *    - Deterministic cleanup (you control when memory is freed)
 *    - No GC pauses from Wasm cleanup
 *    - Easier to debug memory issues
 *    - Better performance in tight loops
 *
 * ⚠️ Must call df.free() when done
 */
async function exampleManualCleanup(): Promise<void> {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 1: Manual Memory Management (Production)');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();

  // Parse CSV without autoCleanup (default)
  const df: DataFrame = rozes.DataFrame.fromCSV(salesData);

  try {
    // Use the DataFrame with type safety
    const shape = df.shape;
    console.log(`Shape: ${shape.rows} rows × ${shape.cols} cols`);
    console.log(`Columns: ${df.columns.join(', ')}`);

    // Access typed column data
    const quantities = df.column('quantity');
    if (quantities instanceof BigInt64Array) {
      const totalQuantity = Array.from(quantities).reduce((sum, val) => sum + Number(val), 0);
      console.log(`Total quantity sold: ${totalQuantity}`);
    }

  } finally {
    // MUST free memory explicitly
    df.free();
    console.log('✅ Memory freed explicitly');
  }
}

/**
 * Example 2: Automatic Memory Management (Prototyping)
 *
 * ✅ Best for: Scripts, exploratory data analysis, prototyping
 * ✅ Advantages:
 *    - No need to call df.free()
 *    - Convenient for quick scripts
 *    - Memory freed automatically when DataFrame goes out of scope
 *
 * ⚠️ Disadvantages:
 *    - Non-deterministic cleanup (GC decides when)
 *    - Memory can grow in loops (1000 DataFrames → wait for GC)
 *    - GC pauses can be 10-100ms
 */
async function exampleAutoCleanup(): Promise<void> {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 2: Automatic Memory Management (Prototyping)');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();

  // Parse CSV with autoCleanup enabled
  const options: CSVOptions = { autoCleanup: true };
  const df: DataFrame = rozes.DataFrame.fromCSV(salesData, options);

  // Use the DataFrame
  console.log(`Shape: ${df.shape.rows} rows × ${df.shape.cols} cols`);
  console.log(`Columns: ${df.columns.join(', ')}`);

  // Access typed column data
  const revenues = df.column('revenue');
  if (revenues instanceof Float64Array) {
    const totalRevenue = revenues.reduce((sum, val) => sum + val, 0);
    console.log(`Total revenue: $${totalRevenue.toFixed(2)}`);
  }

  // No need to call df.free() - memory freed automatically on GC
  console.log('✅ Memory will be freed automatically (no df.free() needed)');
}

/**
 * Example 3: Type-Safe CSV Options
 */
async function exampleTypeSafeOptions(): Promise<void> {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 3: Type-Safe CSV Options');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();

  // All CSV options with types
  const options: CSVOptions = {
    delimiter: ',',
    has_headers: true,
    skip_blank_lines: true,
    trim_whitespace: false,
    autoCleanup: true  // TypeScript will autocomplete this!
  };

  const df = rozes.DataFrame.fromCSV(salesData, options);

  console.log(`Loaded with options: ${JSON.stringify(options, null, 2)}`);
  console.log(`Shape: ${df.shape.rows} rows × ${df.shape.cols} cols`);

  // TypeScript knows df.shape returns DataFrameShape
  const { rows, cols } = df.shape;
  console.log(`Destructured: ${rows} rows, ${cols} cols`);

  console.log('✅ Type-safe options with IntelliSense support');
}

/**
 * Example 4: Processing with Type Guards
 */
async function exampleTypeGuards(): Promise<void> {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 4: Type Guards for Column Data');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();
  const df = rozes.DataFrame.fromCSV(salesData, { autoCleanup: true });

  // Type guard for Float64Array
  const revenues = df.column('revenue');
  if (revenues instanceof Float64Array) {
    const mean = revenues.reduce((sum, val) => sum + val, 0) / revenues.length;
    console.log(`Average revenue: $${mean.toFixed(2)} (Float64Array)`);
  }

  // Type guard for BigInt64Array
  const quantities = df.column('quantity');
  if (quantities instanceof BigInt64Array) {
    const total = Array.from(quantities).reduce((sum, val) => sum + Number(val), 0);
    console.log(`Total quantity: ${total} units (BigInt64Array)`);
  }

  // Null check
  const nonexistent = df.column('invalid');
  if (nonexistent === null) {
    console.log('✅ Type-safe null handling');
  }

  console.log('✅ Type guards work perfectly with TypeScript');
}

/**
 * Example 5: Batch Processing with Types
 */
async function exampleBatchProcessingTyped(): Promise<void> {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 5: Batch Processing (Type-Safe)');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();

  interface FileStats {
    filename: string;
    rows: number;
    cols: number;
  }

  const stats: FileStats[] = [];
  const fileCount = 50;

  console.log(`Processing ${fileCount} CSV files...`);

  for (let i = 0; i < fileCount; i++) {
    // Manual cleanup for predictable memory usage
    const df = rozes.DataFrame.fromCSV(salesData);

    // Collect typed stats
    stats.push({
      filename: `file_${i}.csv`,
      rows: df.shape.rows,
      cols: df.shape.cols
    });

    // Free immediately
    df.free();

    if ((i + 1) % 10 === 0) {
      console.log(`  Processed ${i + 1}/${fileCount} files...`);
    }
  }

  // Aggregate stats with type safety
  const totalRows = stats.reduce((sum, s) => sum + s.rows, 0);
  const avgRows = totalRows / stats.length;

  console.log(`✅ Processed ${totalRows} total rows`);
  console.log(`   Average: ${avgRows.toFixed(1)} rows per file`);
  console.log('   Type-safe throughout!');
}

/**
 * Example 6: Error Handling with Types
 */
async function exampleErrorHandling(): Promise<void> {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 6: Error Handling (Type-Safe)');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();

  try {
    // Invalid CSV
    const df = rozes.DataFrame.fromCSV('invalid,csv\ndata', { autoCleanup: true });
    console.log('Parsed:', df.shape);
  } catch (err) {
    // Type-safe error handling
    if (err instanceof Error) {
      console.log(`Caught error: ${err.message}`);
    }
  }

  // Valid CSV with auto cleanup
  const df = rozes.DataFrame.fromCSV(salesData, { autoCleanup: true });

  try {
    // Use DataFrame
    const shape = df.shape;
    console.log(`Shape: ${shape.rows} rows × ${shape.cols} cols`);

    // Can still manually free even with autoCleanup
    df.free();
    console.log('✅ Manual free() works with autoCleanup: true');

  } catch (err) {
    if (err instanceof Error) {
      console.error('Error:', err.message);
    }
  }
}

/**
 * Example 7: Reading from File (Type-Safe)
 */
async function exampleFileOperations(): Promise<void> {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 7: File Operations (Type-Safe)');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();
  const fs = require('fs');

  // Create temp file with explicit type
  const tempFile: string = '/tmp/rozes_test_ts.csv';
  fs.writeFileSync(tempFile, salesData);

  try {
    // Load with type-safe options
    const options: CSVOptions = {
      has_headers: true,
      autoCleanup: true
    };

    const df: DataFrame = rozes.DataFrame.fromCSVFile(tempFile, options);

    console.log(`Loaded: ${df.shape.rows} rows × ${df.shape.cols} cols`);

    // Type-safe column access
    const columns: string[] = df.columns;
    console.log(`Columns (${columns.length}): ${columns.join(', ')}`);

    console.log('✅ File operations are type-safe');

  } finally {
    fs.unlinkSync(tempFile);
  }
}

/**
 * Example 8: Best Practices with TypeScript
 */
async function bestPracticesTypescript(): Promise<void> {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Best Practices with TypeScript');
  console.log('═══════════════════════════════════════════════════════════\n');

  console.log('📋 TypeScript Benefits with Rozes:');
  console.log('   ✅ Full IntelliSense support for all options');
  console.log('   ✅ Compile-time type checking');
  console.log('   ✅ CSVOptions interface for autocomplete');
  console.log('   ✅ Typed DataFrame.shape and DataFrame.columns');
  console.log('   ✅ Type guards for column data (Float64Array | BigInt64Array | null)');
  console.log('   ✅ RozesError type for error handling\n');

  console.log('📋 Recommended Pattern:');
  console.log('   ```typescript');
  console.log('   const options: CSVOptions = { autoCleanup: true };');
  console.log('   const df: DataFrame = rozes.DataFrame.fromCSV(csv, options);');
  console.log('   ');
  console.log('   const col = df.column("age");');
  console.log('   if (col instanceof BigInt64Array) {');
  console.log('     // Type-safe processing');
  console.log('   }');
  console.log('   ```\n');

  console.log('💡 Pro Tips for TypeScript:');
  console.log('   - Use CSVOptions interface for type safety');
  console.log('   - Type guard column results before processing');
  console.log('   - Leverage IntelliSense for options');
  console.log('   - Try/catch with Error type checks');
}

/**
 * Main runner
 */
async function runAllExamples(): Promise<void> {
  console.log('╔═══════════════════════════════════════════════════════════╗');
  console.log('║  Rozes DataFrame - TypeScript Auto Cleanup Examples      ║');
  console.log('╚═══════════════════════════════════════════════════════════╝');

  await exampleManualCleanup();
  await exampleAutoCleanup();
  await exampleTypeSafeOptions();
  await exampleTypeGuards();
  await exampleBatchProcessingTyped();
  await exampleErrorHandling();
  await exampleFileOperations();
  await bestPracticesTypescript();

  console.log('\n╔═══════════════════════════════════════════════════════════╗');
  console.log('║  ✅ All TypeScript examples completed!                    ║');
  console.log('╚═══════════════════════════════════════════════════════════╝\n');
}

// Run all examples
runAllExamples().catch((err: Error) => {
  console.error('Error:', err.message);
  process.exit(1);
});
