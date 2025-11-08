/**
 * Generates sample stock price data for financial analytics examples.
 *
 * Creates CSV with:
 * - Daily OHLCV (Open, High, Low, Close, Volume) data for 5 stocks
 * - 252 trading days (~1 year)
 * - Realistic price movements with volatility
 */

const fs = require('fs');
const path = require('path');

// Configuration
const TRADING_DAYS = 252;  // ~1 year
const STOCKS = [
  { symbol: 'AAPL', initialPrice: 150.00, volatility: 0.02 },
  { symbol: 'GOOGL', initialPrice: 2800.00, volatility: 0.025 },
  { symbol: 'MSFT', initialPrice: 300.00, volatility: 0.018 },
  { symbol: 'AMZN', initialPrice: 3200.00, volatility: 0.03 },
  { symbol: 'TSLA', initialPrice: 700.00, volatility: 0.04 }
];

function randomNormal(mean = 0, stddev = 1) {
  // Box-Muller transform for normal distribution
  const u1 = Math.random();
  const u2 = Math.random();
  const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  return mean + z * stddev;
}

function generateStockPrices(config) {
  const { symbol, initialPrice, volatility } = config;
  const prices = [];
  let currentPrice = initialPrice;

  // Start date: 2024-01-02 (first trading day of 2024)
  const startDate = new Date('2024-01-02');

  for (let day = 0; day < TRADING_DAYS; day++) {
    // Calculate date (skip weekends)
    const date = new Date(startDate);
    let daysToAdd = day;
    let currentDate = new Date(startDate);

    while (daysToAdd > 0) {
      currentDate.setDate(currentDate.getDate() + 1);
      const dayOfWeek = currentDate.getDay();
      if (dayOfWeek !== 0 && dayOfWeek !== 6) {  // Skip Sunday (0) and Saturday (6)
        daysToAdd--;
      }
    }

    // Generate daily price movement
    const returnPct = randomNormal(0.001, volatility);  // Slight upward bias
    const open = currentPrice;
    const close = open * (1 + returnPct);

    // Generate high/low with some randomness
    const dailyRange = Math.abs(open * volatility * randomNormal(0, 1));
    const high = Math.max(open, close) + dailyRange * 0.5;
    const low = Math.min(open, close) - dailyRange * 0.5;

    // Generate volume (millions of shares)
    const avgVolume = 50000000;
    const volumeNoise = randomNormal(0, 0.3);
    const volume = Math.floor(avgVolume * (1 + volumeNoise));

    prices.push({
      date: currentDate.toISOString().split('T')[0],
      symbol: symbol,
      open: open.toFixed(2),
      high: high.toFixed(2),
      low: low.toFixed(2),
      close: close.toFixed(2),
      volume: volume
    });

    currentPrice = close;
  }

  return prices;
}

function recordToCSVRow(record) {
  return [
    record.date,
    record.symbol,
    record.open,
    record.high,
    record.low,
    record.close,
    record.volume
  ].join(',');
}

function generateCSV() {
  console.log(`Generating ${TRADING_DAYS} trading days for ${STOCKS.length} stocks...`);

  // Generate prices for all stocks
  const allPrices = [];
  for (const stock of STOCKS) {
    const stockPrices = generateStockPrices(stock);
    allPrices.push(...stockPrices);
  }

  // Sort by date, then symbol
  allPrices.sort((a, b) => {
    if (a.date !== b.date) {
      return a.date.localeCompare(b.date);
    }
    return a.symbol.localeCompare(b.symbol);
  });

  // Write CSV
  const header = 'date,symbol,open,high,low,close,volume';
  const rows = allPrices.map(recordToCSVRow);
  const csv = [header, ...rows].join('\n');

  const outputPath = path.join(__dirname, 'stock_prices.csv');
  fs.writeFileSync(outputPath, csv);

  console.log(`✓ Generated ${allPrices.length} records (${TRADING_DAYS} days × ${STOCKS.length} stocks)`);
  console.log(`✓ Saved to: ${outputPath}`);
  console.log(`✓ File size: ${(fs.statSync(outputPath).size / 1024).toFixed(2)} KB`);
  console.log('\nStocks:');
  for (const stock of STOCKS) {
    console.log(`  - ${stock.symbol}: $${stock.initialPrice} (volatility: ${(stock.volatility * 100).toFixed(1)}%)`);
  }
  console.log(`\nDate range: ${allPrices[0].date} to ${allPrices[allPrices.length - 1].date}`);
}

// Run generator
generateCSV();
