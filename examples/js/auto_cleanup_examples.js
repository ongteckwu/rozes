/**
 * Rozes DataFrame - Auto Cleanup Examples
 *
 * This file demonstrates the two memory management approaches:
 * 1. Manual cleanup (default - recommended for production)
 * 2. Auto cleanup (convenient for prototyping)
 *
 * Run with: node examples/node/auto_cleanup_examples.js
 */

const { Rozes } = require('../../dist/index.js');

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
async function exampleManualCleanup() {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 1: Manual Memory Management (Production)');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();

  // Parse CSV without autoCleanup (default)
  const df = rozes.DataFrame.fromCSV(salesData);

  try {
    // Use the DataFrame
    console.log(`Shape: ${df.shape.rows} rows × ${df.shape.cols} cols`);
    console.log(`Columns: ${df.columns.join(', ')}`);

    const quantities = df.column('quantity');
    const totalQuantity = quantities.reduce((sum, val) => sum + Number(val), 0n);
    console.log(`Total quantity sold: ${totalQuantity}`);

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
async function exampleAutoCleanup() {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 2: Automatic Memory Management (Prototyping)');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();

  // Parse CSV with autoCleanup enabled
  const df = rozes.DataFrame.fromCSV(salesData, { autoCleanup: true });

  // Use the DataFrame
  console.log(`Shape: ${df.shape.rows} rows × ${df.shape.cols} cols`);
  console.log(`Columns: ${df.columns.join(', ')}`);

  const revenues = df.column('revenue');
  const totalRevenue = revenues.reduce((sum, val) => sum + val, 0);
  console.log(`Total revenue: $${totalRevenue.toFixed(2)}`);

  // No need to call df.free() - memory freed automatically on GC
  console.log('✅ Memory will be freed automatically (no df.free() needed)');
}

/**
 * Example 3: Processing Multiple Files (Manual Cleanup)
 *
 * When processing many DataFrames in a loop, manual cleanup is recommended
 * for predictable memory usage.
 */
async function exampleBatchProcessingManual() {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 3: Batch Processing with Manual Cleanup');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();

  // Simulate processing 100 CSV files
  const fileCount = 100;
  let totalRows = 0;

  console.log(`Processing ${fileCount} CSV files...`);

  for (let i = 0; i < fileCount; i++) {
    // Parse CSV
    const df = rozes.DataFrame.fromCSV(salesData);

    // Process data
    totalRows += df.shape.rows;

    // Free immediately (deterministic cleanup)
    df.free();

    if ((i + 1) % 20 === 0) {
      console.log(`  Processed ${i + 1}/${fileCount} files...`);
    }
  }

  console.log(`✅ Processed ${totalRows} total rows across ${fileCount} files`);
  console.log('   Memory freed deterministically after each DataFrame');
}

/**
 * Example 4: Processing Multiple Files (Auto Cleanup)
 *
 * Auto cleanup works, but memory grows until GC runs.
 * Not recommended for tight loops or large datasets.
 */
async function exampleBatchProcessingAuto() {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 4: Batch Processing with Auto Cleanup');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();

  // Simulate processing 100 CSV files
  const fileCount = 100;
  let totalRows = 0;

  console.log(`Processing ${fileCount} CSV files...`);
  console.log('⚠️  Memory will grow until GC runs (non-deterministic)\n');

  for (let i = 0; i < fileCount; i++) {
    // Parse CSV with auto cleanup
    const df = rozes.DataFrame.fromCSV(salesData, { autoCleanup: true });

    // Process data
    totalRows += df.shape.rows;

    // Don't free - let GC handle it
    // Memory grows until GC decides to run

    if ((i + 1) % 20 === 0) {
      console.log(`  Processed ${i + 1}/${fileCount} files...`);
    }
  }

  console.log(`✅ Processed ${totalRows} total rows across ${fileCount} files`);
  console.log('   Memory will be freed eventually by GC (timing unpredictable)');
}

/**
 * Example 5: Hybrid Approach (Auto Cleanup + Optional Manual Free)
 *
 * Best of both worlds: Use auto cleanup for safety, but still call free()
 * when you know the DataFrame is no longer needed.
 */
async function exampleHybridApproach() {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 5: Hybrid Approach (Recommended for Scripts)');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();

  // Enable auto cleanup as a safety net
  const df = rozes.DataFrame.fromCSV(salesData, { autoCleanup: true });

  try {
    // Use the DataFrame
    console.log(`Shape: ${df.shape.rows} rows × ${df.shape.cols} cols`);

    const quantities = df.column('quantity');
    const avgQuantity = quantities.reduce((sum, val) => sum + Number(val), 0n) / BigInt(quantities.length);
    console.log(`Average quantity: ${avgQuantity}`);

    // Still call free() for deterministic cleanup
    df.free();
    console.log('✅ Memory freed immediately (explicit call)');

  } catch (err) {
    // If error occurs, auto cleanup ensures no leak
    console.error('Error:', err);
    console.log('✅ Auto cleanup will free memory automatically');
  }
}

/**
 * Example 6: Reading from File with Auto Cleanup
 */
async function exampleFileWithAutoCleanup() {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Example 6: Reading from File with Auto Cleanup');
  console.log('═══════════════════════════════════════════════════════════\n');

  const rozes = await Rozes.init();
  const fs = require('fs');

  // Create a temporary CSV file
  const tempFile = '/tmp/rozes_test.csv';
  fs.writeFileSync(tempFile, salesData);

  try {
    // Load CSV from file with auto cleanup
    const df = rozes.DataFrame.fromCSVFile(tempFile, { autoCleanup: true });

    console.log(`Loaded from file: ${df.shape.rows} rows × ${df.shape.cols} cols`);
    console.log(`Columns: ${df.columns.join(', ')}`);

    // Use the data
    const revenues = df.column('revenue');
    console.log(`Revenue column length: ${revenues.length}`);

    console.log('✅ Memory will be freed automatically');

  } finally {
    // Clean up temp file
    fs.unlinkSync(tempFile);
  }
}

/**
 * Example 7: Best Practices Summary
 */
async function bestPracticesSummary() {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Best Practices Summary');
  console.log('═══════════════════════════════════════════════════════════\n');

  console.log('📋 When to use MANUAL cleanup (autoCleanup: false, default):');
  console.log('   ✅ Production applications');
  console.log('   ✅ Performance-critical code');
  console.log('   ✅ Tight loops processing many DataFrames');
  console.log('   ✅ Long-running servers');
  console.log('   ✅ When you need predictable memory usage\n');

  console.log('📋 When to use AUTO cleanup (autoCleanup: true):');
  console.log('   ✅ Quick scripts and prototypes');
  console.log('   ✅ Interactive data exploration');
  console.log('   ✅ Jupyter-style notebooks');
  console.log('   ✅ When convenience > performance');
  console.log('   ✅ Short-lived processes\n');

  console.log('📋 Hybrid approach (recommended for scripts):');
  console.log('   ✅ Enable autoCleanup as a safety net');
  console.log('   ✅ Still call free() when possible');
  console.log('   ✅ Best of both worlds!\n');

  console.log('💡 Pro Tips:');
  console.log('   - Manual cleanup = 100% predictable');
  console.log('   - Auto cleanup = convenient but GC-dependent');
  console.log('   - You can still call free() with autoCleanup: true');
  console.log('   - FinalizationRegistry works in Node.js 14+ and all modern browsers');
}

/**
 * Main runner
 */
async function runAllExamples() {
  console.log('╔═══════════════════════════════════════════════════════════╗');
  console.log('║  Rozes DataFrame - Auto Cleanup Examples                 ║');
  console.log('╚═══════════════════════════════════════════════════════════╝');

  await exampleManualCleanup();
  await exampleAutoCleanup();
  await exampleBatchProcessingManual();
  await exampleBatchProcessingAuto();
  await exampleHybridApproach();
  await exampleFileWithAutoCleanup();
  await bestPracticesSummary();

  console.log('\n╔═══════════════════════════════════════════════════════════╗');
  console.log('║  ✅ All examples completed!                               ║');
  console.log('╚═══════════════════════════════════════════════════════════╝\n');
}

// Run all examples
runAllExamples().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
