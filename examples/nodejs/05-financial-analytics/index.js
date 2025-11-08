/**
 * Financial Analytics Pipeline with Rozes DataFrame
 *
 * Demonstrates:
 * 1. Time series data loading and filtering
 * 2. Rolling window calculations (mean, std)
 * 3. Expanding window calculations (cumulative metrics)
 * 4. Daily returns and volatility
 * 5. Correlation matrix across stocks
 * 6. Financial metrics (Sharpe ratio, max drawdown)
 */

import { Rozes, DataFrame } from 'rozes';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log('=== Rozes Financial Analytics Pipeline ===\n');

  // Initialize Rozes
  await Rozes.init();

  // Load stock price data
  const dataPath = path.join(__dirname, 'stock_prices.csv');
  if (!fs.existsSync(dataPath)) {
    console.error('❌ stock_prices.csv not found. Run: npm run generate-data');
    process.exit(1);
  }

  const csvData = fs.readFileSync(dataPath, 'utf8');

  console.log('📊 Loading stock price data...');
  const startLoad = Date.now();
  const df = DataFrame.fromCSV(csvData, { hasHeader: true, inferTypes: true });
  const loadTime = Date.now() - startLoad;

  console.log(`✓ Loaded ${df.shape()[0]} records in ${loadTime.toFixed(2)}ms`);
  console.log(`  Columns: ${df.columns().join(', ')}`);
  console.log(`  Stocks: ${df.column('symbol').unique().length()} symbols\n`);

  // ============================================================================
  // Step 1: Filter to Single Stock (AAPL)
  // ============================================================================
  console.log('1️⃣  Filter to AAPL Stock');
  console.log('────────────────────────────────────────────────────────────');

  const start1 = Date.now();
  const aapl = df.filter(row => row.get('symbol') === 'AAPL')
    .sortBy('date', 'asc');

  console.log(`Filtered to ${aapl.shape()[0]} AAPL records`);
  console.log(`Date range: ${aapl.column('date').get(0)} to ${aapl.column('date').get(aapl.shape()[0] - 1)}`);
  console.log(`⚡ Filtered in ${(Date.now() - start1).toFixed(2)}ms\n`);

// ============================================================================
// Step 2: Calculate Daily Returns
// ============================================================================
console.log('2️⃣  Calculate Daily Returns');
console.log('────────────────────────────────────────────────────────────');

const start2 = Date.now();

// Calculate daily returns: (close[i] - close[i-1]) / close[i-1]
const closeCol = aapl.column('close');
const returns = [];
returns.push(0); // First day has no return

for (let i = 1; i < closeCol.length(); i++) {
  const prevClose = closeCol.get(i - 1);
  const currClose = closeCol.get(i);
  const dailyReturn = ((currClose - prevClose) / prevClose) * 100;
  returns.push(dailyReturn);
}

const aaplWithReturns = aapl.withColumn('daily_return', row => {
  return returns[row.index];
});

const avgReturn = returns.slice(1).reduce((sum, r) => sum + r, 0) / (returns.length - 1);
console.log(`Average daily return: ${avgReturn.toFixed(4)}%`);
console.log(`⚡ Computed in ${(Date.now() - start2).toFixed(2)}ms\n`);

// ============================================================================
// Step 3: 20-Day Rolling Mean
// ============================================================================
console.log('3️⃣  20-Day Rolling Mean (Moving Average)');
console.log('────────────────────────────────────────────────────────────');

const start3 = Date.now();
const rollingMean = aaplWithReturns.rollingMean('close', 20);

// Show first few values with nulls, then values after window is filled
const closeRM = rollingMean.column('close');
const ma20 = rollingMean.column('close_rolling_mean_20');

console.log('Date          Close    20-Day MA');
console.log('─────────────────────────────────────');
for (let i = 0; i < 25; i += 5) {
  const date = closeRM.get(i) ? rollingMean.column('date').get(i) : 'N/A';
  const close = closeRM.get(i) ? closeRM.get(i).toFixed(2) : 'N/A';
  const ma = ma20.get(i) !== null ? ma20.get(i).toFixed(2) : 'null';
  console.log(`${date}  ${String(close).padStart(8)}  ${String(ma).padStart(8)}`);
}

console.log(`⚡ Computed in ${(Date.now() - start3).toFixed(2)}ms\n`);

// ============================================================================
// Step 4: 20-Day Rolling Standard Deviation (Volatility)
// ============================================================================
console.log('4️⃣  20-Day Rolling Standard Deviation (Volatility)');
console.log('────────────────────────────────────────────────────────────');

const start4 = Date.now();
const rollingStd = aaplWithReturns.rollingStd('daily_return', 20);

const volCol = rollingStd.column('daily_return_rolling_std_20');

// Show last 10 days of volatility
console.log('Date          Daily Return  20-Day Vol');
console.log('─────────────────────────────────────────');
const lastIdx = rollingStd.shape()[0] - 1;
for (let i = lastIdx - 9; i <= lastIdx; i++) {
  const date = rollingStd.column('date').get(i);
  const ret = rollingStd.column('daily_return').get(i).toFixed(4);
  const vol = volCol.get(i) !== null ? volCol.get(i).toFixed(4) : 'null';
  console.log(`${date}  ${String(ret + '%').padStart(12)}  ${String(vol + '%').padStart(10)}`);
}

console.log(`⚡ Computed in ${(Date.now() - start4).toFixed(2)}ms\n`);

// ============================================================================
// Step 5: Expanding Mean (Cumulative Average)
// ============================================================================
console.log('5️⃣  Expanding Mean (Cumulative Average Price)');
console.log('────────────────────────────────────────────────────────────');

const start5 = Date.now();
const expandingMean = aaplWithReturns.expandingMean('close');

const expMeanCol = expandingMean.column('close_expanding_mean');

// Show first, middle, and last values
const midIdx = Math.floor(expandingMean.shape()[0] / 2);
const indices = [0, midIdx, expandingMean.shape()[0] - 1];

console.log('Date          Close    Expanding Mean');
console.log('─────────────────────────────────────────');
for (const i of indices) {
  const date = expandingMean.column('date').get(i);
  const close = expandingMean.column('close').get(i).toFixed(2);
  const expMean = expMeanCol.get(i).toFixed(2);
  console.log(`${date}  ${String(close).padStart(8)}  ${String(expMean).padStart(14)}`);
}

console.log(`⚡ Computed in ${(Date.now() - start5).toFixed(2)}ms\n`);

// ============================================================================
// Step 6: Multi-Stock Correlation Matrix
// ============================================================================
console.log('6️⃣  Correlation Matrix (Daily Returns Across Stocks)');
console.log('────────────────────────────────────────────────────────────');

const start6 = Date.now();

// Calculate returns for all stocks
const symbols = ['AAPL', 'GOOGL', 'MSFT', 'AMZN', 'TSLA'];
const stockReturns = {};

for (const symbol of symbols) {
  const stockDF = df.filter(row => row.get('symbol') === symbol).sortBy('date', 'asc');
  const closeCol = stockDF.column('close');
  const returns = [0]; // First day

  for (let i = 1; i < closeCol.length(); i++) {
    const prevClose = closeCol.get(i - 1);
    const currClose = closeCol.get(i);
    const dailyReturn = (currClose - prevClose) / prevClose;
    returns.push(dailyReturn);
  }

  stockReturns[symbol] = returns.slice(1); // Skip first day
  stockDF.free();
}

// Calculate correlation matrix manually
const corrMatrix = {};
for (const sym1 of symbols) {
  corrMatrix[sym1] = {};
  for (const sym2 of symbols) {
    const returns1 = stockReturns[sym1];
    const returns2 = stockReturns[sym2];

    // Calculate correlation coefficient
    const n = returns1.length;
    const mean1 = returns1.reduce((sum, r) => sum + r, 0) / n;
    const mean2 = returns2.reduce((sum, r) => sum + r, 0) / n;

    let numerator = 0;
    let denom1 = 0;
    let denom2 = 0;

    for (let i = 0; i < n; i++) {
      const diff1 = returns1[i] - mean1;
      const diff2 = returns2[i] - mean2;
      numerator += diff1 * diff2;
      denom1 += diff1 * diff1;
      denom2 += diff2 * diff2;
    }

    const correlation = numerator / Math.sqrt(denom1 * denom2);
    corrMatrix[sym1][sym2] = correlation;
  }
}

// Print correlation matrix
console.log('        ' + symbols.map(s => s.padStart(7)).join(''));
console.log('─────────────────────────────────────────────────────');
for (const sym1 of symbols) {
  const row = symbols.map(sym2 => corrMatrix[sym1][sym2].toFixed(3).padStart(7)).join('');
  console.log(`${sym1.padEnd(7)} ${row}`);
}

console.log(`⚡ Computed in ${(Date.now() - start6).toFixed(2)}ms\n`);

// ============================================================================
// Step 7: Financial Metrics Summary
// ============================================================================
console.log('7️⃣  Financial Metrics Summary (AAPL)');
console.log('────────────────────────────────────────────────────────────');

const start7 = Date.now();

// Calculate metrics
const totalReturn = ((closeCol.get(closeCol.length() - 1) - closeCol.get(0)) / closeCol.get(0)) * 100;
const annualizedReturn = (Math.pow(1 + totalReturn / 100, 252 / closeCol.length()) - 1) * 100;

// Volatility (annualized)
const returnsSq = returns.slice(1).map(r => r * r);
const variance = returnsSq.reduce((sum, r) => sum + r, 0) / returnsSq.length;
const dailyVol = Math.sqrt(variance);
const annualizedVol = dailyVol * Math.sqrt(252);

// Sharpe ratio (assuming 3% risk-free rate)
const riskFreeRate = 3.0;
const sharpeRatio = (annualizedReturn - riskFreeRate) / annualizedVol;

// Max drawdown
let maxPrice = closeCol.get(0);
let maxDrawdown = 0;
for (let i = 0; i < closeCol.length(); i++) {
  const price = closeCol.get(i);
  if (price > maxPrice) {
    maxPrice = price;
  }
  const drawdown = ((price - maxPrice) / maxPrice) * 100;
  if (drawdown < maxDrawdown) {
    maxDrawdown = drawdown;
  }
}

console.log(`Total Return:       ${totalReturn.toFixed(2)}%`);
console.log(`Annualized Return:  ${annualizedReturn.toFixed(2)}%`);
console.log(`Annualized Vol:     ${annualizedVol.toFixed(2)}%`);
console.log(`Sharpe Ratio:       ${sharpeRatio.toFixed(2)}`);
console.log(`Max Drawdown:       ${maxDrawdown.toFixed(2)}%`);
console.log(`⚡ Computed in ${(Date.now() - start7).toFixed(2)}ms\n`);

  // ============================================================================
  // Cleanup
  // ============================================================================
  df.free();
  aapl.free();
  aaplWithReturns.free();
  rollingMean.free();
  rollingStd.free();
  expandingMean.free();

  console.log('✓ All DataFrames cleaned up\n');
  console.log('=== Financial Analytics Complete ===');
}

main().catch(console.error);
