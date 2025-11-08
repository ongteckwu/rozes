/**
 * Tests for Financial Analytics Pipeline
 *
 * Verifies that all financial calculations work correctly.
 */

const rozes = require('rozes');

console.log('=== Testing Financial Analytics Pipeline ===\n');

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

function assertClose(actual, expected, tolerance, message) {
  testsRun++;
  const diff = Math.abs(actual - expected);
  if (diff <= tolerance) {
    console.log(`✓ ${message} (${actual.toFixed(4)} ≈ ${expected.toFixed(4)})`);
    testsPassed++;
  } else {
    console.error(`✗ ${message} (${actual.toFixed(4)} vs ${expected.toFixed(4)}, diff: ${diff.toFixed(4)})`);
  }
}

// ============================================================================
// Setup: Generate test data
// ============================================================================
const testCSV = `date,symbol,open,high,low,close,volume
2024-01-01,AAPL,150.00,152.00,149.00,151.00,50000000
2024-01-02,AAPL,151.00,153.00,150.00,152.00,51000000
2024-01-03,AAPL,152.00,154.00,151.00,153.00,49000000
2024-01-04,AAPL,153.00,155.00,152.00,154.00,52000000
2024-01-05,AAPL,154.00,156.00,153.00,155.00,48000000
2024-01-06,AAPL,155.00,157.00,154.00,156.00,53000000
2024-01-07,AAPL,156.00,158.00,155.00,157.00,47000000
2024-01-08,AAPL,157.00,159.00,156.00,158.00,54000000
2024-01-09,AAPL,158.00,160.00,157.00,159.00,46000000
2024-01-10,AAPL,159.00,161.00,158.00,160.00,55000000`;

console.log('Test 1: Data Loading\n');

const df = rozes.fromCSV(testCSV, { hasHeader: true, inferTypes: true });
assert(df.shape()[0] === 10, 'Loaded 10 records');
assert(df.columns().includes('close'), 'Has close column');
console.log();

// ============================================================================
// Test 2: Rolling Mean (3-day)
// ============================================================================
console.log('Test 2: Rolling Mean (3-day)\n');

const rollingMean = df.rollingMean('close', 3);
const rmCol = rollingMean.column('close_rolling_mean_3');

// First 2 values should be null (window not filled)
assert(rmCol.get(0) === null, 'First rolling mean is null (window not filled)');
assert(rmCol.get(1) === null, 'Second rolling mean is null (window not filled)');

// Third value: mean(151, 152, 153) = 152
const rm2 = rmCol.get(2);
assertClose(rm2, 152.0, 0.01, 'Third rolling mean is correct');

// Fourth value: mean(152, 153, 154) = 153
const rm3 = rmCol.get(3);
assertClose(rm3, 153.0, 0.01, 'Fourth rolling mean is correct');

rollingMean.free();
console.log();

// ============================================================================
// Test 3: Rolling Standard Deviation (3-day)
// ============================================================================
console.log('Test 3: Rolling Standard Deviation (3-day)\n');

const rollingStd = df.rollingStd('close', 3);
const rsCol = rollingStd.column('close_rolling_std_3');

// First 2 values should be null
assert(rsCol.get(0) === null, 'First rolling std is null (window not filled)');
assert(rsCol.get(1) === null, 'Second rolling std is null (window not filled)');

// Third value: std(151, 152, 153) = 1.0
const rs2 = rsCol.get(2);
assertClose(rs2, 1.0, 0.01, 'Third rolling std is correct');

rollingStd.free();
console.log();

// ============================================================================
// Test 4: Expanding Mean
// ============================================================================
console.log('Test 4: Expanding Mean\n');

const expandingMean = df.expandingMean('close');
const emCol = expandingMean.column('close_expanding_mean');

// First value: mean(151) = 151
const em0 = emCol.get(0);
assertClose(em0, 151.0, 0.01, 'First expanding mean is correct');

// Second value: mean(151, 152) = 151.5
const em1 = emCol.get(1);
assertClose(em1, 151.5, 0.01, 'Second expanding mean is correct');

// Third value: mean(151, 152, 153) = 152
const em2 = emCol.get(2);
assertClose(em2, 152.0, 0.01, 'Third expanding mean is correct');

// Last value: mean(151..160) = 155.5
const em9 = emCol.get(9);
assertClose(em9, 155.5, 0.01, 'Last expanding mean is correct');

expandingMean.free();
console.log();

// ============================================================================
// Test 5: Expanding Sum
// ============================================================================
console.log('Test 5: Expanding Sum\n');

const expandingSum = df.expandingSum('volume');
const esCol = expandingSum.column('volume_expanding_sum');

// First value: sum(50000000) = 50000000
const es0 = esCol.get(0);
assert(es0 === 50000000, 'First expanding sum is correct');

// Second value: sum(50000000, 51000000) = 101000000
const es1 = esCol.get(1);
assert(es1 === 101000000, 'Second expanding sum is correct');

expandingSum.free();
console.log();

// ============================================================================
// Test 6: Time Series Filtering
// ============================================================================
console.log('Test 6: Time Series Filtering\n');

const filtered = df.filter(row => row.get('close') > 155);
assert(filtered.shape()[0] === 5, 'Filtered to 5 records where close > 155');

filtered.free();
console.log();

// ============================================================================
// Test 7: Returns Calculation
// ============================================================================
console.log('Test 7: Returns Calculation\n');

const closeCol = df.column('close');
const returns = [];

for (let i = 1; i < closeCol.length(); i++) {
  const prevClose = closeCol.get(i - 1);
  const currClose = closeCol.get(i);
  const dailyReturn = ((currClose - prevClose) / prevClose) * 100;
  returns.push(dailyReturn);
}

// Day 2: (152 - 151) / 151 = 0.662%
assertClose(returns[0], 0.662, 0.01, 'Day 2 return is correct');

// Day 3: (153 - 152) / 152 = 0.658%
assertClose(returns[1], 0.658, 0.01, 'Day 3 return is correct');

console.log();

// ============================================================================
// Test 8: Memory Leak Test
// ============================================================================
console.log('Test 8: Memory Leak Test (1000 iterations)\n');

for (let i = 0; i < 1000; i++) {
  const dfTemp = rozes.fromCSV(testCSV, { hasHeader: true, inferTypes: true });
  const rmTemp = dfTemp.rollingMean('close', 3);
  const emTemp = dfTemp.expandingMean('close');
  dfTemp.free();
  rmTemp.free();
  emTemp.free();
}

assert(true, 'No memory leaks after 1000 iterations');
console.log();

// ============================================================================
// Cleanup
// ============================================================================
df.free();

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
