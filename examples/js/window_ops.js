/**
 * Window Operations API Showcase
 *
 * Demonstrates rolling and expanding window operations:
 * - rollingSum() - Rolling sum over window
 * - rollingMean() - Rolling average
 * - rollingMin() - Rolling minimum
 * - rollingMax() - Rolling maximum
 * - rollingStd() - Rolling standard deviation
 * - expandingSum() - Cumulative sum
 * - expandingMean() - Cumulative average
 */

import { Rozes } from '../../dist/index.mjs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main() {
  console.log('📈 Window Operations API Showcase\n');

  // Initialize Rozes
  const wasmPath = join(__dirname, '../../zig-out/bin/rozes.wasm');
  const rozes = await Rozes.init(wasmPath);
  console.log('✅ Rozes initialized\n');

  const DataFrame = rozes.DataFrame;

  // Sample dataset - Stock prices over time
  const csv = `date,price,volume,high,low
2024-01-01,100.0,1000,102.0,98.0
2024-01-02,102.5,1100,104.0,101.0
2024-01-03,101.0,950,103.0,99.0
2024-01-04,105.0,1200,107.0,104.0
2024-01-05,103.5,1050,105.0,102.0
2024-01-06,107.0,1300,109.0,106.0
2024-01-07,106.0,1150,108.0,105.0
2024-01-08,108.5,1400,110.0,107.0
2024-01-09,107.5,1250,109.0,106.0
2024-01-10,110.0,1500,112.0,109.0`;

  const df = DataFrame.fromCSV(csv);
  console.log('Stock Price Data:');
  df.show();
  console.log();

  // Example 1: Rolling sum
  console.log('1️⃣  Rolling Sum: rollingSum()');
  console.log('─'.repeat(50));
  console.log('3-day rolling sum of volume:');
  const dfRollingSum = df.rollingSum('volume', 3);
  dfRollingSum.select(['date', 'volume', 'volume_rolling_sum']).show();
  console.log();

  // Example 2: Rolling mean (moving average)
  console.log('2️⃣  Rolling Mean: rollingMean()');
  console.log('─'.repeat(50));
  console.log('3-day moving average (SMA-3) of price:');
  const dfSMA3 = df.rollingMean('price', 3);
  dfSMA3.select(['date', 'price', 'price_rolling_mean']).show();
  console.log();

  console.log('5-day moving average (SMA-5) of price:');
  const dfSMA5 = df.rollingMean('price', 5);
  dfSMA5.select(['date', 'price', 'price_rolling_mean']).show();
  console.log();

  // Example 3: Rolling minimum
  console.log('3️⃣  Rolling Minimum: rollingMin()');
  console.log('─'.repeat(50));
  console.log('3-day rolling minimum price:');
  const dfRollingMin = df.rollingMin('price', 3);
  dfRollingMin.select(['date', 'price', 'price_rolling_min']).show();
  console.log();

  // Example 4: Rolling maximum
  console.log('4️⃣  Rolling Maximum: rollingMax()');
  console.log('─'.repeat(50));
  console.log('3-day rolling maximum price:');
  const dfRollingMax = df.rollingMax('price', 3);
  dfRollingMax.select(['date', 'price', 'price_rolling_max']).show();
  console.log();

  // Example 5: Rolling standard deviation
  console.log('5️⃣  Rolling Standard Deviation: rollingStd()');
  console.log('─'.repeat(50));
  console.log('3-day rolling standard deviation (volatility):');
  const dfRollingStd = df.rollingStd('price', 3);
  dfRollingStd.select(['date', 'price', 'price_rolling_std']).show();
  console.log();

  // Example 6: Expanding sum (cumulative sum)
  console.log('6️⃣  Expanding Sum: expandingSum()');
  console.log('─'.repeat(50));
  console.log('Cumulative volume:');
  const dfCumSum = df.expandingSum('volume');
  dfCumSum.select(['date', 'volume', 'volume_expanding_sum']).show();
  console.log();

  // Example 7: Expanding mean (cumulative average)
  console.log('7️⃣  Expanding Mean: expandingMean()');
  console.log('─'.repeat(50));
  console.log('Cumulative average price:');
  const dfCumMean = df.expandingMean('price');
  dfCumMean.select(['date', 'price', 'price_expanding_mean']).show();
  console.log();

  // Example 8: Multiple window sizes
  console.log('8️⃣  Multiple Window Sizes');
  console.log('─'.repeat(50));
  console.log('Compare SMA-3, SMA-5, and SMA-7:');
  const dfMultiSMA = df
    .rollingMean('price', 3)
    .rollingMean('price', 5);

  // For display, select relevant columns
  console.log('(Showing first 8 rows for clarity)');
  const dfDisplay = dfMultiSMA.select(['date', 'price', 'price_rolling_mean']);
  dfDisplay.head(8).show();
  console.log();

  // Example 9: Bollinger Bands (SMA ± 2*STD)
  console.log('9️⃣  Bollinger Bands (Technical Indicator)');
  console.log('─'.repeat(50));
  const windowSize = 3;
  const dfBollinger = df
    .rollingMean('price', windowSize)
    .rollingStd('price', windowSize);

  console.log(`${windowSize}-period Bollinger Bands:`);
  console.log('(Middle Band = SMA, Upper/Lower = SMA ± 2*STD)');
  dfBollinger.select(['date', 'price', 'price_rolling_mean', 'price_rolling_std']).show();
  console.log();

  // Example 10: Volume-Weighted Average Price (VWAP approximation)
  console.log('🔟 Volume Analysis');
  console.log('─'.repeat(50));
  console.log('Volume moving average (3-day):');
  const dfVolumeMA = df.rollingMean('volume', 3);
  dfVolumeMA.select(['date', 'volume', 'volume_rolling_mean']).show();
  console.log();

  // Example 11: Price range analysis
  console.log('1️⃣1️⃣  Price Range Analysis');
  console.log('─'.repeat(50));
  console.log('3-day rolling high/low range:');
  const dfHighRolling = df.rollingMax('high', 3);
  const dfLowRolling = dfHighRolling.rollingMin('low', 3);
  dfLowRolling.select(['date', 'high', 'high_rolling_max', 'low', 'low_rolling_min']).show();
  console.log();

  // Example 12: Trend detection with cumulative metrics
  console.log('1️⃣2️⃣  Trend Detection');
  console.log('─'.repeat(50));
  console.log('Price vs Cumulative Average (trend indicator):');
  const dfTrend = df.expandingMean('price');
  console.log('When price > expanding_mean → Uptrend');
  console.log('When price < expanding_mean → Downtrend');
  dfTrend.select(['date', 'price', 'price_expanding_mean']).show();
  console.log();

  // Example 13: Chaining window operations
  console.log('1️⃣3️⃣  Chaining Window Operations');
  console.log('─'.repeat(50));
  console.log('Complete technical analysis (SMA + volatility + volume):');
  const dfTechnical = df
    .rollingMean('price', 3)
    .rollingStd('price', 3)
    .rollingMean('volume', 3);

  dfTechnical.select(['date', 'price', 'price_rolling_mean', 'price_rolling_std', 'volume_rolling_mean']).show();
  console.log();

  // Cleanup
  df.free();
  dfRollingSum.free();
  dfSMA3.free();
  dfSMA5.free();
  dfRollingMin.free();
  dfRollingMax.free();
  dfRollingStd.free();
  dfCumSum.free();
  dfCumMean.free();
  dfMultiSMA.free();
  dfDisplay.free();
  dfBollinger.free();
  dfVolumeMA.free();
  dfHighRolling.free();
  dfLowRolling.free();
  dfTrend.free();
  dfTechnical.free();

  console.log('✅ Window operations showcase complete!');
}

// Run examples
main().catch(console.error);
