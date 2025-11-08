/**
 * Missing Data API Showcase (TypeScript)
 *
 * Demonstrates missing data handling operations:
 * - isna() / notna() - Detect missing values
 * - fillna() - Fill missing values
 * - dropna() - Remove rows with missing values
 */

import { Rozes, DataFrame as DataFrameType, Column } from '../../dist/index.mjs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main(): Promise<void> {
  console.log('🔍 Missing Data API Showcase (TypeScript)\n');

  // Initialize Rozes
  const wasmPath = join(__dirname, '../../zig-out/bin/rozes.wasm');
  const rozes = await Rozes.init(wasmPath);
  console.log('✅ Rozes initialized\n');

  const DataFrame = rozes.DataFrame;

  // Sample dataset with missing values
  const csv: string = `name,age,city,score,department
Alice,30,San Francisco,95.5,Engineering
Bob,,New York,87.3,Finance
Charlie,35,,91.0,Engineering
Diana,28,Boston,,Marketing
Eve,32,Austin,93.2,
Frank,,,,Sales
Grace,29,Seattle,89.5,Engineering`;

  const df: DataFrameType = DataFrame.fromCSV(csv);
  console.log('Original DataFrame (with missing values):');
  df.show();
  console.log(`Shape: ${df.shape.rows} rows × ${df.shape.cols} columns\n`);

  // Example 1: Detect missing values with isna()
  console.log('1️⃣  Detect Missing Values: isna()');
  console.log('─'.repeat(50));
  console.log('Check age column for missing values:');
  const ageIsna: DataFrameType = df.isna('age');
  ageIsna.show();
  console.log();

  console.log('Check score column for missing values:');
  const scoreIsna: DataFrameType = df.isna('score');
  scoreIsna.show();
  console.log();

  // Example 2: Detect non-missing values with notna()
  console.log('2️⃣  Detect Non-Missing Values: notna()');
  console.log('─'.repeat(50));
  console.log('Check city column for non-missing values:');
  const cityNotna: DataFrameType = df.notna('city');
  cityNotna.show();
  console.log();

  // Example 3: Drop rows with missing values in specific column
  console.log('3️⃣  Drop Rows with Missing Values: dropna()');
  console.log('─'.repeat(50));
  console.log('Remove rows where age is missing:');
  const dfNoMissingAge: DataFrameType = df.dropna('age');
  dfNoMissingAge.show();
  console.log(`Shape: ${dfNoMissingAge.shape.rows} rows × ${dfNoMissingAge.shape.cols} columns`);
  console.log();

  console.log('Remove rows where score is missing:');
  const dfNoMissingScore: DataFrameType = df.dropna('score');
  dfNoMissingScore.show();
  console.log(`Shape: ${dfNoMissingScore.shape.rows} rows × ${dfNoMissingScore.shape.cols} columns`);
  console.log();

  // Example 4: Fill missing values with fillna()
  console.log('4️⃣  Fill Missing Values: fillna()');
  console.log('─'.repeat(50));
  console.log('Fill missing ages with 0:');
  const dfAgesFilled: DataFrameType = df.fillna('age', 0);
  dfAgesFilled.show();
  console.log();

  console.log('Fill missing scores with mean (90.0):');
  const dfScoresFilled: DataFrameType = df.fillna('score', 90.0);
  dfScoresFilled.show();
  console.log();

  console.log('Fill missing departments with "Unknown":');
  const dfDeptFilled: DataFrameType = df.fillna('department', 'Unknown');
  dfDeptFilled.show();
  console.log();

  // Example 5: Chaining operations - drop then fill
  console.log('5️⃣  Chaining Operations: Drop + Fill');
  console.log('─'.repeat(50));
  console.log('Strategy: Drop rows with >2 missing, then fill remaining:');

  // First drop rows with missing age (most critical)
  const dfStep1: DataFrameType = df.dropna('age');
  console.log('Step 1: After dropping missing age:');
  dfStep1.show();

  // Then fill remaining missing values
  const dfStep2: DataFrameType = dfStep1.fillna('city', 'Unknown City');
  const dfStep3: DataFrameType = dfStep2.fillna('score', 0.0);
  const dfFinal: DataFrameType = dfStep3.fillna('department', 'Unknown');
  console.log('\nStep 2: After filling all remaining missing values:');
  dfFinal.show();
  console.log();

  // Example 6: Filter based on missing value detection
  console.log('6️⃣  Filter Using isna() Results');
  console.log('─'.repeat(50));
  console.log('Find rows where department is NOT missing:');

  const deptNotna: DataFrameType = df.notna('department');
  // Filter original df using the boolean column
  const hashedDf: DataFrameType = df.filter((row) => {
    const dept = row.get('department');
    return dept !== null && dept !== undefined && dept !== '';
  });
  hashedDf.show();
  console.log();

  // Example 7: Count missing values per column
  console.log('7️⃣  Count Missing Values Per Column');
  console.log('─'.repeat(50));
  const columns: string[] = df.columns;
  console.log('Missing value counts:');

  for (const col of columns) {
    const isnaResult: DataFrameType = df.isna(col);
    const columnData: Column | null = isnaResult.column(col + '_isna');
    if (columnData) {
      const values: any[] = columnData.data;
      let missingCount: number = 0;
      for (let i = 0; i < values.length; i++) {
        if (values[i] === true || values[i] === 1) {
          missingCount++;
        }
      }
      console.log(`  ${col}: ${missingCount} missing`);
    }
    isnaResult.free();
  }
  console.log();

  // Example 8: Complete missing data workflow
  console.log('8️⃣  Complete Workflow: Detect → Drop → Fill');
  console.log('─'.repeat(50));

  // Step 1: Identify columns with missing data
  console.log('Step 1: Identify missing data');
  const ageMissing: DataFrameType = df.isna('age');
  console.log('Age missing:');
  ageMissing.show();

  // Step 2: Drop critical missing rows
  console.log('\nStep 2: Drop rows with missing age (critical field)');
  const cleanedDf: DataFrameType = df.dropna('age');
  cleanedDf.show();

  // Step 3: Fill non-critical missing values
  console.log('\nStep 3: Fill remaining missing values');
  const fullyCleanedDf: DataFrameType = cleanedDf
    .fillna('city', 'Unknown')
    .fillna('score', 85.0)
    .fillna('department', 'Unassigned');
  fullyCleanedDf.show();
  console.log();

  // Cleanup
  df.free();
  ageIsna.free();
  scoreIsna.free();
  cityNotna.free();
  dfNoMissingAge.free();
  dfNoMissingScore.free();
  dfAgesFilled.free();
  dfScoresFilled.free();
  dfDeptFilled.free();
  dfStep1.free();
  dfStep2.free();
  dfStep3.free();
  dfFinal.free();
  hashedDf.free();
  deptNotna.free();
  ageMissing.free();
  cleanedDf.free();
  fullyCleanedDf.free();

  console.log('✅ Missing data showcase complete!');
}

// Run examples
main().catch(console.error);
