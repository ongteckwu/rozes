# Rozes TypeScript Examples

This directory contains TypeScript examples demonstrating the Rozes DataFrame API.

## Setup

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Build the project** (optional):
   ```bash
   npm run build
   ```

## Running Examples

Each example can be run directly with ts-node:

```bash
# CSV Export
npm run csv-export

# Missing Data Handling
npm run missing-data

# String Operations
npm run string-ops

# Advanced Aggregations
npm run advanced-agg

# Window Operations
npm run window-ops

# Reshape Operations
npm run reshape

# Apache Arrow Interop
npm run arrow-interop

# Lazy Evaluation
npm run lazy-eval
```

Alternatively, run examples directly with tsx:

```bash
npx tsx csv_export.ts
npx tsx missing_data.ts
npx tsx string_ops.ts
# ... etc
```

## Examples Overview

### 1. CSV Export (`csv_export.ts`)
Demonstrates all CSV export options:
- Basic export with default options
- Custom delimiters (TSV, pipe-separated)
- Custom line endings (CRLF)
- Export without headers
- Column selection before export
- Filter and export
- Round-trip testing

### 2. Missing Data (`missing_data.ts`)
Missing data handling operations:
- `isna()` - Detect missing values
- `notna()` - Detect non-missing values
- `fillna()` - Fill missing values
- `dropna()` - Remove rows with missing values
- Chaining operations
- Counting missing values per column

### 3. String Operations (`string_ops.ts`)
String manipulation operations:
- `strLower()` - Convert to lowercase
- `strUpper()` - Convert to uppercase
- `strTrim()` - Remove whitespace
- `strContains()` - Check if contains substring
- `strReplace()` - Replace substring
- `strSlice()` - Extract substring
- `strStartsWith()` - Check prefix
- `strEndsWith()` - Check suffix
- `strLen()` - String length
- Chaining string operations

### 4. Advanced Aggregations (`advanced_agg.ts`)
Statistical aggregation operations:
- `median()` - Calculate median
- `quantile()` - Calculate percentiles
- `valueCounts()` - Frequency distribution
- `corrMatrix()` - Correlation matrix
- `rank()` - Rank values
- Statistical summaries
- Outlier detection (IQR method)

### 5. Window Operations (`window_ops.ts`)
Rolling and expanding window operations:
- `rollingSum()` - Rolling sum
- `rollingMean()` - Moving average (SMA)
- `rollingMin()` - Rolling minimum
- `rollingMax()` - Rolling maximum
- `rollingStd()` - Rolling standard deviation
- `expandingSum()` - Cumulative sum
- `expandingMean()` - Cumulative average
- Technical indicators (Bollinger Bands)

### 6. Reshape Operations (`reshape.ts`)
DataFrame reshaping operations:
- `pivot()` - Long to wide format
- `melt()` - Wide to long format
- `transpose()` - Swap rows and columns
- `stack()` - Stack columns into rows
- `unstack()` - Unstack rows into columns
- Round-trip transformations

### 7. Apache Arrow Interop (`arrow_interop.ts`)
⚠️ **MVP**: Schema-only export/import (v1.3.0)

Apache Arrow format interoperability:
- `toArrow()` - Export schema to Arrow format
- `fromArrow()` - Import from Arrow schema
- Round-trip testing
- Type mapping (Rozes ↔ Arrow)
- Schema validation

**Note**: Full IPC data transfer planned for v1.4.0

### 8. Lazy Evaluation (`lazy_evaluation.ts`)
⚠️ **MVP**: `select()` + `limit()` only (v1.3.0)

Lazy evaluation and query optimization:
- `lazy()` - Create LazyDataFrame
- `select()` - Projection pushdown
- `limit()` - Row limit
- `collect()` - Execute optimized query plan
- Performance comparison (lazy vs eager)

**Note**: `filter()`, `groupBy()`, `join()` planned for v1.4.0

## Type Safety

All examples demonstrate TypeScript type safety with:
- Type annotations for variables
- Return type declarations for functions
- Proper DataFrame and Column type usage
- Type-safe error handling

## Differences from JavaScript Examples

The TypeScript examples include:
- **Type annotations**: Explicit types for all variables and function parameters
- **Type safety**: Compile-time type checking
- **Better IDE support**: Autocomplete and IntelliSense
- **Type imports**: Import types from `dist/index.mjs`

## TypeScript Configuration

See `tsconfig.json` for TypeScript compiler settings:
- Target: ES2020
- Module: ES2020
- Strict mode enabled
- Source maps enabled

## Prerequisites

- Node.js 18+
- TypeScript 5.0+
- Rozes WASM module built (`zig-out/bin/rozes.wasm`)

## Additional Resources

- [Rozes Documentation](../../README.md)
- [Node.js API Documentation](../../docs/NODEJS_API.md)
- [JavaScript Examples](../js/) - JavaScript versions of these examples
