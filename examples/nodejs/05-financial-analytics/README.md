# Financial Analytics Example

Demonstrates Rozes DataFrame capabilities for financial time series analysis:

- **Time Series Data**: OHLCV (Open, High, Low, Close, Volume) stock data
- **Rolling Windows**: `rollingMean()`, `rollingStd()` for moving averages and volatility
- **Expanding Windows**: `expandingMean()`, `expandingSum()` for cumulative metrics
- **Daily Returns**: Percentage change calculations
- **Correlation Matrix**: Cross-stock correlation analysis
- **Financial Metrics**: Total/annualized returns, volatility, Sharpe ratio, max drawdown

## Dataset

252 trading days (~1 year) for 5 stocks:
- **AAPL**: Apple Inc. (volatility: 2.0%)
- **GOOGL**: Alphabet Inc. (volatility: 2.5%)
- **MSFT**: Microsoft Corp. (volatility: 1.8%)
- **AMZN**: Amazon.com Inc. (volatility: 3.0%)
- **TSLA**: Tesla Inc. (volatility: 4.0%)

Total: 1,260 daily price records with OHLCV data.

## Installation

```bash
npm install
```

**Note**: This example uses a locally built `rozes` package. Build the package first:

```bash
cd ../../..
./scripts/build-npm-package.sh
cd examples/nodejs/05-financial-analytics
npm install
```

## Usage

### 1. Generate Sample Data

```bash
npm run generate-data
```

This creates `stock_prices.csv` with 1,260 records (252 days × 5 stocks).

### 2. Run Analytics

```bash
npm start
```

### 3. Run Tests

```bash
npm test
```

## Expected Output

```
=== Rozes Financial Analytics Pipeline ===

📊 Loading stock price data...
✓ Loaded 1260 records in 42.34ms
  Columns: date, symbol, open, high, low, close, volume
  Stocks: 5 symbols

1️⃣  Filter to AAPL Stock
────────────────────────────────────────────────────────────
Filtered to 252 AAPL records
Date range: 2024-01-02 to 2024-12-31
⚡ Filtered in 8.23ms

2️⃣  Calculate Daily Returns
────────────────────────────────────────────────────────────
Average daily return: 0.1234%
⚡ Computed in 5.67ms

3️⃣  20-Day Rolling Mean (Moving Average)
────────────────────────────────────────────────────────────
Date          Close    20-Day MA
─────────────────────────────────────
2024-01-02   151.23      null
2024-01-07   149.87      null
2024-01-12   152.45      null
2024-01-17   155.67      null
2024-01-22   153.89   152.84
⚡ Computed in 12.45ms

4️⃣  20-Day Rolling Standard Deviation (Volatility)
────────────────────────────────────────────────────────────
Date          Daily Return  20-Day Vol
─────────────────────────────────────────
2024-12-15    -0.5423%     1.8765%
2024-12-16     1.2341%     1.9123%
2024-12-17    -0.3456%     1.8543%
...
⚡ Computed in 15.23ms

5️⃣  Expanding Mean (Cumulative Average Price)
────────────────────────────────────────────────────────────
Date          Close    Expanding Mean
─────────────────────────────────────────
2024-01-02   151.23         151.23
2024-07-02   168.45         159.87
2024-12-31   175.23         163.45
⚡ Computed in 18.56ms

6️⃣  Correlation Matrix (Daily Returns Across Stocks)
────────────────────────────────────────────────────────────
         AAPL  GOOGL   MSFT   AMZN   TSLA
─────────────────────────────────────────────────────
AAPL    1.000  0.756  0.823  0.698  0.543
GOOGL   0.756  1.000  0.812  0.745  0.612
MSFT    0.823  0.812  1.000  0.734  0.587
AMZN    0.698  0.745  0.734  1.000  0.623
TSLA    0.543  0.612  0.587  0.623  1.000
⚡ Computed in 45.67ms

7️⃣  Financial Metrics Summary (AAPL)
────────────────────────────────────────────────────────────
Total Return:       15.87%
Annualized Return:  15.87%
Annualized Vol:     31.75%
Sharpe Ratio:       0.41
Max Drawdown:       -12.34%
⚡ Computed in 8.92ms

✓ All DataFrames cleaned up

=== Financial Analytics Complete ===
```

## Key Techniques

### Time Series Filtering

```javascript
// Filter to a single stock
const aapl = df
  .filter(row => row.get('symbol') === 'AAPL')
  .sortBy('date', 'asc');
```

### Daily Returns Calculation

```javascript
// Calculate percentage change day-over-day
const closeCol = df.column('close');
const returns = [];

for (let i = 1; i < closeCol.length(); i++) {
  const prevClose = closeCol.get(i - 1);
  const currClose = closeCol.get(i);
  const dailyReturn = ((currClose - prevClose) / prevClose) * 100;
  returns.push(dailyReturn);
}

const dfWithReturns = df.withColumn('daily_return', row => {
  return returns[row.index];
});
```

### Rolling Windows (Moving Averages)

```javascript
// 20-day simple moving average
const ma20 = df.rollingMean('close', 20);

// 20-day volatility (rolling std)
const vol20 = df.rollingStd('daily_return', 20);
```

### Expanding Windows (Cumulative Metrics)

```javascript
// Cumulative average price from start to each day
const expandingAvg = df.expandingMean('close');

// Cumulative total volume
const expandingVol = df.expandingSum('volume');
```

### Correlation Matrix

```javascript
// Calculate pairwise correlations
const symbols = ['AAPL', 'GOOGL', 'MSFT'];
const corrMatrix = {};

for (const sym1 of symbols) {
  corrMatrix[sym1] = {};
  for (const sym2 of symbols) {
    // Extract returns for each stock
    const returns1 = getReturns(df, sym1);
    const returns2 = getReturns(df, sym2);

    // Calculate Pearson correlation
    const corr = calculateCorrelation(returns1, returns2);
    corrMatrix[sym1][sym2] = corr;
  }
}
```

### Financial Metrics

```javascript
// Total return
const totalReturn = (closeCol.get(n-1) - closeCol.get(0)) / closeCol.get(0);

// Annualized volatility
const dailyVol = calculateStdDev(returns);
const annualizedVol = dailyVol * Math.sqrt(252);

// Sharpe ratio (risk-adjusted return)
const sharpeRatio = (annualizedReturn - riskFreeRate) / annualizedVol;

// Maximum drawdown
let maxPrice = closeCol.get(0);
let maxDrawdown = 0;
for (let i = 0; i < n; i++) {
  maxPrice = Math.max(maxPrice, closeCol.get(i));
  const drawdown = (closeCol.get(i) - maxPrice) / maxPrice;
  maxDrawdown = Math.min(maxDrawdown, drawdown);
}
```

## Performance Notes

- **CSV loading**: ~40ms for 1,260 records (5 stocks × 252 days)
- **Rolling mean (20-day)**: ~10-15ms per column
- **Rolling std (20-day)**: ~12-18ms per column
- **Expanding mean**: ~15-20ms per column
- **Correlation matrix**: ~40-50ms for 5×5 stocks
- **Total analytics**: ~150-200ms for complete pipeline

On larger datasets (10K+ days, 100+ stocks), expect similar relative performance with SIMD/parallel optimizations.

## Real-World Applications

This pipeline demonstrates techniques commonly used for:

- **Portfolio Analytics**: Multi-asset correlation, diversification analysis
- **Risk Management**: Volatility tracking, VaR (Value at Risk) calculations
- **Trading Signals**: Moving average crossovers, momentum indicators
- **Performance Attribution**: Sharpe ratio, alpha/beta calculations
- **Market Research**: Cross-sectional analysis, factor modeling

## Financial Metrics Explained

### Total Return
Percentage change from start to end of period:
```
(Final Price - Initial Price) / Initial Price × 100%
```

### Annualized Return
Compound annual growth rate (CAGR):
```
(1 + Total Return)^(252/Days) - 1
```

### Annualized Volatility
Standard deviation of daily returns, scaled to annual:
```
Daily Std Dev × √252
```

### Sharpe Ratio
Risk-adjusted return (higher is better):
```
(Annualized Return - Risk Free Rate) / Annualized Volatility
```

### Maximum Drawdown
Largest peak-to-trough decline (more negative is worse):
```
min((Price[i] - Peak Price) / Peak Price) × 100%
```

## License

MIT
