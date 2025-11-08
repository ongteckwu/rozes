/**
 * Data Cleaning Pipeline with Rozes DataFrame
 *
 * Demonstrates:
 * 1. Missing data detection and handling (isna, dropna, fillna)
 * 2. Duplicate detection and removal (dropDuplicates)
 * 3. Outlier detection and filtering
 * 4. String cleaning and normalization (str operations)
 * 5. Data validation and quality metrics
 */

import { Rozes, DataFrame } from 'rozes';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log('=== Rozes Data Cleaning Pipeline ===\n');

  // Initialize Rozes
  await Rozes.init();

  // Load dirty data
  const dataPath = path.join(__dirname, 'customer_data_dirty.csv');
  if (!fs.existsSync(dataPath)) {
    console.error('❌ customer_data_dirty.csv not found. Run: npm run generate-data');
    process.exit(1);
  }

  const csvData = fs.readFileSync(dataPath, 'utf8');

  console.log('📊 Loading dirty customer data...');
  const startLoad = Date.now();
  const df = DataFrame.fromCSV(csvData, { hasHeader: true, inferTypes: true });
  const loadTime = Date.now() - startLoad;

  console.log(`✓ Loaded ${df.shape.rows} records in ${loadTime.toFixed(2)}ms`);
  console.log(`  Columns: ${df.columns.join(', ')}\n`);

  // ============================================================================
  // Step 1: Missing Data Analysis
  // ============================================================================
  console.log('1️⃣  Missing Data Analysis');
  console.log('────────────────────────────────────────────────────────────');

  const start1 = Date.now();
  const columns = df.columns;
  console.log('Column                Missing Values  Percentage');

  for (const col of columns) {
    const isnaDF = df.isna(col);
    const naCount = isnaDF.column(col + '_isna').sum();
    const percentage = ((naCount / df.shape.rows) * 100).toFixed(2);
    console.log(`${col.padEnd(20)} ${String(naCount).padStart(14)} ${String(percentage + '%').padStart(12)}`);
    isnaDF.free();
  }

  console.log(`\n⚡ Computed in ${(Date.now() - start1).toFixed(2)}ms\n`);

  // ============================================================================
  // Step 2: Remove Rows with Missing Critical Data
  // ============================================================================
  console.log('2️⃣  Remove Rows with Missing Critical Data');
  console.log('────────────────────────────────────────────────────────────');

  const start2 = Date.now();
  // Drop rows where customer_id, first_name, last_name, or amount is null
  const cleanedMissing = df
    .dropna('customer_id')
    .dropna('first_name')
    .dropna('last_name')
    .dropna('amount');

  const removedMissing = df.shape.rows - cleanedMissing.shape.rows;
  console.log(`Rows before: ${df.shape.rows}`);
  console.log(`Rows after:  ${cleanedMissing.shape.rows}`);
  console.log(`Removed:     ${removedMissing} rows with missing critical data`);
  console.log(`\n⚡ Computed in ${(Date.now() - start2).toFixed(2)}ms\n`);

  // ============================================================================
  // Step 3: Duplicate Detection and Removal
  // ============================================================================
  console.log('3️⃣  Duplicate Detection and Removal');
  console.log('────────────────────────────────────────────────────────────');

  const start3 = Date.now();
  const cleanedDuplicates = cleanedMissing.dropDuplicates(['customer_id', 'product', 'amount']);
  const removedDuplicates = cleanedMissing.shape.rows - cleanedDuplicates.shape.rows;

  console.log(`Rows before: ${cleanedMissing.shape.rows}`);
  console.log(`Rows after:  ${cleanedDuplicates.shape.rows}`);
  console.log(`Removed:     ${removedDuplicates} duplicate records`);
  console.log(`\n⚡ Computed in ${(Date.now() - start3).toFixed(2)}ms\n`);

  // ============================================================================
  // Step 4: Outlier Detection and Removal
  // ============================================================================
  console.log('4️⃣  Outlier Detection and Removal');
  console.log('────────────────────────────────────────────────────────────');

  const start4 = Date.now();

  // Remove unrealistic ages (>120 years)
  const ageFiltered = cleanedDuplicates.filter(row => {
    const age = row.get('age');
    return age !== null && age > 0 && age <= 120;
  });

  // Remove extreme quantities (>500 units)
  const cleanedOutliers = ageFiltered.filter(row => {
    const quantity = row.get('quantity');
    return quantity !== null && quantity > 0 && quantity <= 500;
  });

  const removedOutliers = cleanedDuplicates.shape.rows - cleanedOutliers.shape.rows;

  console.log(`Rows before: ${cleanedDuplicates.shape.rows}`);
  console.log(`Rows after:  ${cleanedOutliers.shape.rows}`);
  console.log(`Removed:     ${removedOutliers} outlier records`);
  console.log(`\n⚡ Computed in ${(Date.now() - start4).toFixed(2)}ms\n`);

  // ============================================================================
  // Step 5: String Cleaning and Normalization
  // ============================================================================
  console.log('5️⃣  String Cleaning and Normalization');
  console.log('────────────────────────────────────────────────────────────');

  const start5 = Date.now();

  // Trim whitespace from first_name
  let normalized = cleanedOutliers.strTrim('first_name');

  // Normalize city names to title case
  const cityCol = normalized.column('city');
  const cityValues = [];
  for (let i = 0; i < cityCol.length(); i++) {
    const city = cityCol.get(i);
    if (city) {
      // Title case: "new york" -> "New York"
      const titleCase = city.split(' ')
        .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
        .join(' ');
      cityValues.push(titleCase);
    } else {
      cityValues.push(city);
    }
  }

  // Replace city column with normalized values
  const cityNormalized = normalized.withColumn('city', row => {
    const idx = row.index;
    return cityValues[idx];
  });

  normalized.free();
  normalized = cityNormalized;

  console.log('✓ Trimmed whitespace from first_name');
  console.log('✓ Normalized city names to title case');
  console.log(`\n⚡ Computed in ${(Date.now() - start5).toFixed(2)}ms\n`);

  // ============================================================================
  // Step 6: Data Quality Summary
  // ============================================================================
  console.log('6️⃣  Data Quality Summary');
  console.log('────────────────────────────────────────────────────────────');

  const originalCount = df.shape.rows;
  const cleanedCount = normalized.shape.rows;
  const totalRemoved = originalCount - cleanedCount;
  const retentionRate = ((cleanedCount / originalCount) * 100).toFixed(2);

  console.log(`Original records:    ${originalCount}`);
  console.log(`Cleaned records:     ${cleanedCount}`);
  console.log(`Total removed:       ${totalRemoved}`);
  console.log(`Retention rate:      ${retentionRate}%`);
  console.log('\nBreakdown:');
  console.log(`  Missing data:      ${removedMissing} rows`);
  console.log(`  Duplicates:        ${removedDuplicates} rows`);
  console.log(`  Outliers:          ${removedOutliers} rows`);

  // ============================================================================
  // Step 7: Export Cleaned Data
  // ============================================================================
  console.log('\n7️⃣  Export Cleaned Data');
  console.log('────────────────────────────────────────────────────────────');

  const start7 = Date.now();
  const cleanedCSV = normalized.toCSV({ header: true, delimiter: ',' });
  const outputPath = path.join(__dirname, 'customer_data_clean.csv');
  fs.writeFileSync(outputPath, cleanedCSV);

  console.log(`✓ Exported to: ${outputPath}`);
  console.log(`✓ File size: ${(cleanedCSV.length / 1024).toFixed(2)} KB`);
  console.log(`⚡ Exported in ${(Date.now() - start7).toFixed(2)}ms\n`);

  // ============================================================================
  // Cleanup
  // ============================================================================
  df.free();
  cleanedMissing.free();
  cleanedDuplicates.free();
  ageFiltered.free();
  cleanedOutliers.free();
  normalized.free();

  console.log('✓ All DataFrames cleaned up\n');
  console.log('=== Data Cleaning Complete ===');
}

main().catch(console.error);
