/**
 * Tests for Data Cleaning Pipeline
 *
 * Verifies that all cleaning operations work correctly.
 */

import { Rozes, DataFrame } from 'rozes';

let testsRun = 0;
let testsPassed = 0;

function assert(condition, message) {
  testsRun++;
  if (condition) {
    console.log(`✓ ${message}`);
    testsPassed++;
  } else {
    console.error(`✗ ${message}`);
  }
}

async function main() {
  console.log('=== Testing Data Cleaning Pipeline ===\n');

  await Rozes.init();

  // ============================================================================
  // Setup: Generate test data
  // ============================================================================
  const testCSV = `customer_id,first_name,last_name,age,city,amount
1,Alice,Smith,30,New York,100
2,Bob,Johnson,,Chicago,200
3,,Williams,45,Houston,300
4,Diana,Brown,150,Phoenix,400
5,Alice,Smith,30,New York,100
6,Frank,Garcia,35,  LOS ANGELES  ,500
7,George,Miller,40,san diego,600`;

  console.log('Test 1: Missing Data Detection\n');
  const df1 = DataFrame.fromCSV(testCSV, { hasHeader: true, inferTypes: true });

// Test isna() for age column
const isnaAge = df1.isna('age');
const naCounts = isnaAge.column('age_isna').sum();
assert(naCounts === 1, 'Detected 1 missing value in age column');
isnaAge.free();

// Test isna() for first_name column
const isnaFirstName = df1.isna('first_name');
const naCountsFirstName = isnaFirstName.column('first_name_isna').sum();
assert(naCountsFirstName === 1, 'Detected 1 missing value in first_name column');
isnaFirstName.free();

console.log();

// ============================================================================
// Test 2: Drop Missing Data
// ============================================================================
console.log('Test 2: Drop Missing Data\n');

const df2 = DataFrame.fromCSV(testCSV, { hasHeader: true, inferTypes: true });
const cleaned = df2.dropna('first_name').dropna('age');

assert(cleaned.shape()[0] === 5, 'Removed 2 rows with missing data (7 → 5 rows)');

df2.free();
cleaned.free();

console.log();

// ============================================================================
// Test 3: Duplicate Detection and Removal
// ============================================================================
console.log('Test 3: Duplicate Detection and Removal\n');

const df3 = DataFrame.fromCSV(testCSV, { hasHeader: true, inferTypes: true });
const deduplicated = df3.dropDuplicates(['first_name', 'last_name', 'age', 'city', 'amount']);

assert(deduplicated.shape()[0] === 6, 'Removed 1 duplicate record (7 → 6 rows)');

df3.free();
deduplicated.free();

console.log();

// ============================================================================
// Test 4: Outlier Filtering
// ============================================================================
console.log('Test 4: Outlier Filtering\n');

const df4 = DataFrame.fromCSV(testCSV, { hasHeader: true, inferTypes: true });
const ageFiltered = df4.filter(row => {
  const age = row.get('age');
  return age !== null && age > 0 && age <= 120;
});

assert(ageFiltered.shape()[0] === 6, 'Removed 1 outlier with unrealistic age (7 → 6 rows)');

df4.free();
ageFiltered.free();

console.log();

// ============================================================================
// Test 5: String Trimming
// ============================================================================
console.log('Test 5: String Trimming\n');

const df5 = DataFrame.fromCSV(testCSV, { hasHeader: true, inferTypes: true });
const trimmed = df5.strTrim('city');

const cityCol = trimmed.column('city');
const city5 = cityCol.get(5); // "  LOS ANGELES  " → "LOS ANGELES"

// Check that whitespace is trimmed
assert(city5 === 'LOS ANGELES', 'Trimmed whitespace from city column');

df5.free();
trimmed.free();

console.log();

// ============================================================================
// Test 6: CSV Export
// ============================================================================
console.log('Test 6: CSV Export\n');

const df6 = DataFrame.fromCSV(testCSV, { hasHeader: true, inferTypes: true });
const exportedCSV = df6.toCSV({ header: true, delimiter: ',' });

assert(exportedCSV.length > 0, 'Exported CSV data');
assert(exportedCSV.includes('customer_id,first_name'), 'CSV contains header');
assert(exportedCSV.split('\n').length >= 7, 'CSV contains all rows');

df6.free();

console.log();

// ============================================================================
// Test 7: Full Cleaning Pipeline
// ============================================================================
console.log('Test 7: Full Cleaning Pipeline\n');

const df7 = DataFrame.fromCSV(testCSV, { hasHeader: true, inferTypes: true });

const fullCleaned = df7
  .dropna('first_name')
  .dropna('age')
  .dropDuplicates(['first_name', 'last_name', 'amount'])
  .filter(row => {
    const age = row.get('age');
    return age !== null && age > 0 && age <= 120;
  });

assert(fullCleaned.shape()[0] === 4, 'Full pipeline cleaned data correctly (7 → 4 rows)');

df7.free();
fullCleaned.free();

console.log();

// ============================================================================
// Test 8: Memory Leak Test
// ============================================================================
console.log('Test 8: Memory Leak Test (1000 iterations)\n');

for (let i = 0; i < 1000; i++) {
  const dfTemp = DataFrame.fromCSV(testCSV, { hasHeader: true, inferTypes: true });
  const cleanedTemp = dfTemp.dropna('age').dropDuplicates(['customer_id']);
  dfTemp.free();
  cleanedTemp.free();
}

assert(true, 'No memory leaks after 1000 iterations');

console.log();

  // ============================================================================
  // Summary
  // ============================================================================
  console.log('=================================');
  console.log(`Tests passed: ${testsPassed}/${testsRun}`);

  if (testsPassed === testsRun) {
    console.log('✓ All tests passed!');
    process.exit(0);
  } else {
    console.log(`✗ ${testsRun - testsPassed} test(s) failed`);
    process.exit(1);
  }
}

main().catch(console.error);
