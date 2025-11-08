/**
 * Reshaping Pipeline with Rozes
 * Demonstrates: pivot, melt, transpose for data transformation
 */

import { Rozes, DataFrame } from 'rozes';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log('=== Rozes Reshaping Pipeline ===\n');

  // Initialize Rozes
  await Rozes.init();

  const dataPath = path.join(__dirname, 'sales.csv');
  if (!fs.existsSync(dataPath)) {
    console.error('❌ sales.csv not found. Run: npm run generate-data');
    process.exit(1);
  }

  const csvData = fs.readFileSync(dataPath, 'utf8');
  const df = DataFrame.fromCSV(csvData, { hasHeader: true, inferTypes: true });
  console.log(`✓ Loaded ${df.shape()[0]} sales records\n`);

// 1. Pivot: Product × Quarter Matrix
console.log('1️⃣  Pivot Table: Product Sales by Quarter');
console.log('────────────────────────────────────────────────────────────');
const pivoted = df.pivot('product', 'quarter', 'sales', 'sum');
console.log(`Shape: ${pivoted.shape()[0]} products × ${pivoted.shape()[1]} columns`);
console.log(`Columns: ${pivoted.columns().slice(0, 5).join(', ')}...\n`);

// Display pivot table
const products = pivoted.column('product');
console.log('Product      Q1        Q2        Q3        Q4');
console.log('──────────────────────────────────────────────────');
for (let i = 0; i < Math.min(3, products.length()); i++) {
  const product = products.get(i).padEnd(11);
  const q1 = (pivoted.column('Q1').get(i) || 0).toFixed(0).padStart(8);
  const q2 = (pivoted.column('Q2').get(i) || 0).toFixed(0).padStart(9);
  const q3 = (pivoted.column('Q3').get(i) || 0).toFixed(0).padStart(9);
  const q4 = (pivoted.column('Q4').get(i) || 0).toFixed(0).padStart(9);
  console.log(`${product} ${q1} ${q2} ${q3} ${q4}`);
}
console.log();

// 2. Melt: Wide to Long Format
console.log('2️⃣  Melt: Convert Pivot Back to Long Format');
console.log('────────────────────────────────────────────────────────────');
const melted = pivoted.melt('product', ['Q1', 'Q2', 'Q3', 'Q4'], 'quarter', 'sales');
console.log(`Shape: ${melted.shape()[0]} rows × ${melted.shape()[1]} columns`);
console.log(`Columns: ${melted.columns().join(', ')}\n`);

// Display first few melted rows
console.log('Product      Quarter  Sales');
console.log('──────────────────────────────────');
for (let i = 0; i < Math.min(6, melted.shape()[0]); i++) {
  const product = melted.column('product').get(i).padEnd(11);
  const quarter = melted.column('quarter').get(i).padEnd(7);
  const sales = (melted.column('sales').get(i) || 0).toFixed(0).padStart(8);
  console.log(`${product} ${quarter} ${sales}`);
}
console.log();

// 3. Transpose: Swap Rows and Columns
console.log('3️⃣  Transpose: Swap Rows and Columns');
console.log('────────────────────────────────────────────────────────────');
const transposed = pivoted.transpose();
console.log(`Original: ${pivoted.shape()[0]} rows × ${pivoted.shape()[1]} cols`);
console.log(`Transposed: ${transposed.shape()[0]} rows × ${transposed.shape()[1]} cols\n`);

  // Summary
  console.log('Summary:');
  console.log(`  Original data: ${df.shape()[0]} rows (long format)`);
  console.log(`  Pivoted: ${pivoted.shape()[0]} rows (wide format)`);
  console.log(`  Melted: ${melted.shape()[0]} rows (long format)`);
  console.log(`  Transposed: ${transposed.shape()[0]} rows\n`);

  // Cleanup
  [df, pivoted, melted, transposed].forEach(d => d.free());
  console.log('=== Reshaping Complete ===');
}

main().catch(console.error);
