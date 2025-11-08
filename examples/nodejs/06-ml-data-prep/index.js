/**
 * ML Data Preparation Pipeline with Rozes
 * Demonstrates: Feature engineering, normalization, derived features
 */

import { Rozes, DataFrame } from 'rozes';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log('=== Rozes ML Data Prep Pipeline ===\n');

  // Initialize Rozes
  await Rozes.init();

  const dataPath = path.join(__dirname, 'customers.csv');
  if (!fs.existsSync(dataPath)) {
    console.error('❌ customers.csv not found. Run: npm run generate-data');
    process.exit(1);
  }

  const csvData = fs.readFileSync(dataPath, 'utf8');
  const df = DataFrame.fromCSV(csvData, { hasHeader: true, inferTypes: true });
  console.log(`✓ Loaded ${df.shape()[0]} records\n`);

// 1. Feature Engineering: Create age bins
console.log('1️⃣  Feature Engineering: Age Bins');
const dfWithAgeBin = df.withColumn('age_bin', row => {
  const age = row.get('age');
  if (age < 25) return 'young';
  if (age < 45) return 'middle';
  if (age < 65) return 'senior';
  return 'elder';
});
console.log('✓ Created age_bin column (young/middle/senior/elder)\n');

// 2. Feature Engineering: Income-to-Purchases Ratio
console.log('2️⃣  Feature Engineering: Income-to-Purchases Ratio');
const dfWithRatio = dfWithAgeBin.withColumn('income_per_purchase', row => {
  const income = row.get('income');
  const purchases = row.get('purchases');
  return purchases > 0 ? income / purchases : 0;
});
console.log('✓ Created income_per_purchase ratio column\n');

// 3. Normalization: Min-Max Scaling for Age
console.log('3️⃣  Normalization: Min-Max Scaling');
const ageCol = dfWithRatio.column('age');
const ageMin = Math.min(...Array.from({length: ageCol.length()}, (_, i) => ageCol.get(i)));
const ageMax = Math.max(...Array.from({length: ageCol.length()}, (_, i) => ageCol.get(i)));
const dfNormalized = dfWithRatio.withColumn('age_normalized', row => {
  const age = row.get('age');
  return (age - ageMin) / (ageMax - ageMin);
});
console.log(`✓ Normalized age column (min: ${ageMin}, max: ${ageMax})\n`);

// 4. Rank Feature
console.log('4️⃣  Rank Feature: Income Ranking');
const dfWithRank = dfNormalized.rank('income', false);
const rankCol = dfWithRank.column('income_rank');
console.log(`✓ Created income_rank column (ranks 1-${rankCol.length()})\n`);

// 5. Export Prepared Data
console.log('5️⃣  Export Prepared Data');
const preparedCSV = dfWithRank.toCSV({ header: true, delimiter: ',' });
fs.writeFileSync(path.join(__dirname, 'customers_prepared.csv'), preparedCSV);
console.log('✓ Exported to customers_prepared.csv\n');

  // Summary
  console.log('Summary:');
  console.log(`  Original columns: ${df.columns().length}`);
  console.log(`  Prepared columns: ${dfWithRank.columns().length}`);
  console.log(`  New features: age_bin, income_per_purchase, age_normalized, income_rank\n`);

  df.free();
  dfWithAgeBin.free();
  dfWithRatio.free();
  dfNormalized.free();
  dfWithRank.free();
  console.log('=== ML Data Prep Complete ===');
}

main().catch(console.error);
