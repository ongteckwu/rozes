# Rozes Node.js/TypeScript API Reference

**Version**: 1.3.0 | **Last Updated**: 2025-11-08

Complete API reference for all DataFrame operations available in the Node.js/TypeScript environment.

---

## Table of Contents

1. [Initialization](#initialization)
2. [DataFrame Creation](#dataframe-creation)
3. [CSV Operations](#csv-operations)
4. [DataFrame Utilities](#dataframe-utilities)
5. [Column Operations](#column-operations)
6. [Row Operations](#row-operations)
7. [Missing Data](#missing-data)
8. [String Operations](#string-operations)
9. [Numeric Operations](#numeric-operations)
10. [Aggregations](#aggregations)
11. [Advanced Aggregations](#advanced-aggregations)
12. [Window Operations](#window-operations)
13. [Sorting](#sorting)
14. [Joins](#joins)
15. [Grouping](#grouping)
16. [Reshape Operations](#reshape-operations)
17. [Apache Arrow](#apache-arrow)
18. [Lazy Evaluation](#lazy-evaluation)
19. [Memory Management](#memory-management)

---

## Initialization

### `Rozes.init(wasmPath?: string): Promise<Rozes>`

Initialize the Rozes WASM module.

**Parameters:**
- `wasmPath` (optional): Path to `rozes.wasm` file. Auto-detected in most environments.

**Returns:** Promise<Rozes> - Initialized Rozes instance

**Example:**
```javascript
import { Rozes } from 'rozes';

// Browser
const rozes = await Rozes.init();

// Node.js (auto-detection)
const rozes = await Rozes.init();

// Node.js (explicit path)
const rozes = await Rozes.init('./node_modules/rozes/zig-out/bin/rozes.wasm');

const DataFrame = rozes.DataFrame;
```

---

## DataFrame Creation

### `DataFrame.fromCSV(csvString, options?): DataFrame`

Create DataFrame from CSV string.

**Parameters:**
- `csvString: string` - CSV data as string
- `options` (optional):
  - `delimiter?: string` - Column delimiter (default: `,`)
  - `hasHeader?: boolean` - Has header row (default: `true`)
  - `quoteChar?: string` - Quote character (default: `"`)
  - `escapeChar?: string` - Escape character (default: `"`)

**Returns:** DataFrame

**Example:**
```javascript
const csv = `name,age,city
Alice,30,NYC
Bob,25,LA`;

const df = DataFrame.fromCSV(csv);
df.show();
//   name    age  city
// 0 Alice    30  NYC
// 1 Bob      25  LA
```

### `DataFrame.create(columns, data): DataFrame`

Create DataFrame from column definitions and data arrays.

**Parameters:**
- `columns: ColumnDef[]` - Array of column definitions
- `data: any[][]` - 2D array of row data

**Example:**
```javascript
const columns = [
  { name: 'name', type: 'String' },
  { name: 'age', type: 'Int64' }
];

const data = [
  ['Alice', 30],
  ['Bob', 25]
];

const df = DataFrame.create(columns, data);
```

---

## CSV Operations

### `df.toCSV(options?): string`

Export DataFrame to CSV string.

**Parameters:**
- `options` (optional):
  - `includeHeaders?: boolean` - Include header row (default: `true`)
  - `delimiter?: string` - Column delimiter (default: `,`)
  - `lineEnding?: string` - Line ending (default: `\n`)

**Returns:** string - CSV formatted data

**Example:**
```javascript
const csv = df.toCSV();
console.log(csv);
// name,age,city
// Alice,30,NYC
// Bob,25,LA

// Custom delimiter
const tsv = df.toCSV({ delimiter: '\t' });

// Without headers
const csvNoHeader = df.toCSV({ includeHeaders: false });
```

### `df.toCSVFile(path, options?): void` (Node.js only)

Export DataFrame to CSV file.

**Parameters:**
- `path: string` - Output file path
- `options` (optional): Same as `toCSV()`

**Example:**
```javascript
import fs from 'fs';

// Method 1: Using toCSV() + fs.writeFileSync
const csvData = df.toCSV();
fs.writeFileSync('output.csv', csvData, 'utf8');

// Method 2: Direct export (if implemented)
// df.toCSVFile('output.csv');
```

---

## DataFrame Utilities

### `df.shape: { rows: number, cols: number }`

Get DataFrame dimensions.

**Returns:** Object with `rows` and `cols` properties

**Example:**
```javascript
console.log(df.shape);
// { rows: 100, cols: 5 }

console.log(`DataFrame has ${df.shape.rows} rows`);
```

### `df.columns: string[]`

Get column names.

**Returns:** Array of column name strings

**Example:**
```javascript
console.log(df.columns);
// ['name', 'age', 'city', 'score']

// Check if column exists
if (df.columns.includes('age')) {
  // ...
}
```

### `df.dtypes: { [key: string]: string }`

Get column data types.

**Returns:** Object mapping column names to types

**Example:**
```javascript
console.log(df.dtypes);
// { name: 'String', age: 'Int64', score: 'Float64' }
```

### `df.show(n?): void`

Display DataFrame (console output).

**Parameters:**
- `n?: number` - Number of rows to show (default: all)

**Example:**
```javascript
df.show();      // Show all rows
df.show(10);    // Show first 10 rows
```

### `df.head(n?): DataFrame`

Get first N rows.

**Parameters:**
- `n?: number` - Number of rows (default: 5)

**Returns:** New DataFrame with first N rows

**Example:**
```javascript
const top5 = df.head();      // First 5 rows
const top10 = df.head(10);   // First 10 rows
```

### `df.tail(n?): DataFrame`

Get last N rows.

**Parameters:**
- `n?: number` - Number of rows (default: 5)

**Returns:** New DataFrame with last N rows

**Example:**
```javascript
const bottom5 = df.tail();    // Last 5 rows
const bottom10 = df.tail(10); // Last 10 rows
```

### `df.drop(columnNames): DataFrame`

Drop columns by name.

**Parameters:**
- `columnNames: string | string[]` - Column name(s) to drop

**Returns:** New DataFrame without specified columns

**Example:**
```javascript
// Drop single column
const df2 = df.drop('age');

// Drop multiple columns
const df3 = df.drop(['age', 'city']);
```

### `df.rename(oldName, newName): DataFrame`

Rename a column.

**Parameters:**
- `oldName: string` - Current column name
- `newName: string` - New column name

**Returns:** New DataFrame with renamed column

**Example:**
```javascript
const df2 = df.rename('age', 'years');
console.log(df2.columns);
// ['name', 'years', 'city']
```

### `df.unique(columnName): any[]`

Get unique values in column.

**Parameters:**
- `columnName: string` - Column name

**Returns:** Array of unique values

**Example:**
```javascript
const cities = df.unique('city');
console.log(cities);
// ['NYC', 'LA', 'Chicago', 'Boston']
```

### `df.dropDuplicates(columnNames?): DataFrame`

Remove duplicate rows.

**Parameters:**
- `columnNames?: string[]` - Columns to check for duplicates (default: all)

**Returns:** New DataFrame without duplicates

**Example:**
```javascript
// Drop rows with duplicate values in all columns
const df2 = df.dropDuplicates();

// Drop rows with duplicate city values
const df3 = df.dropDuplicates(['city']);

// Drop based on multiple columns
const df4 = df.dropDuplicates(['name', 'age']);
```

### `df.describe(columnName?): DataFrame`

Statistical summary of numeric columns.

**Parameters:**
- `columnName?: string` - Specific column (default: all numeric)

**Returns:** DataFrame with statistics (count, mean, std, min, max, etc.)

**Example:**
```javascript
// Describe all numeric columns
const stats = df.describe();
stats.show();

// Describe specific column
const ageStats = df.describe('age');
```

### `df.sample(n, seed?): DataFrame`

Random sample of rows.

**Parameters:**
- `n: number` - Number of rows to sample
- `seed?: number` - Random seed for reproducibility

**Returns:** DataFrame with N randomly sampled rows

**Example:**
```javascript
// Random 10 rows
const sample = df.sample(10);

// Reproducible sample
const sample2 = df.sample(10, 42);
```

---

## Column Operations

### `df.select(columnNames): DataFrame`

Select specific columns.

**Parameters:**
- `columnNames: string[]` - Column names to select

**Returns:** New DataFrame with only selected columns

**Example:**
```javascript
const subset = df.select(['name', 'age']);
subset.show();
//   name    age
// 0 Alice    30
// 1 Bob      25
```

### `df.column(columnName): Column | null`

Get column data.

**Parameters:**
- `columnName: string` - Column name

**Returns:** Column object or null if not found

**Example:**
```javascript
const ageCol = df.column('age');
if (ageCol) {
  console.log(ageCol.data);  // TypedArray or Array
  console.log(ageCol.type);  // 'Int64', 'Float64', etc.
}
```

### `df.withColumn(columnName, values): DataFrame`

Add or replace column.

**Parameters:**
- `columnName: string` - New column name
- `values: any[]` - Column values (must match row count)

**Returns:** New DataFrame with added/replaced column

**Example:**
```javascript
// Add new column
const df2 = df.withColumn('category', ['A', 'B', 'A', 'B']);

// Replace existing column
const df3 = df.withColumn('age', [31, 26, 36, 29]);

// Computed column (from existing data)
const ages = df.column('age').data;
const doubledAges = Array.from(ages).map(a => a * 2);
const df4 = df.withColumn('age_doubled', doubledAges);
```

---

## Row Operations

### `df.filter(predicate): DataFrame`

Filter rows by condition.

**Parameters:**
- `predicate: (row: RowRef) => boolean` - Filter function

**Returns:** New DataFrame with rows matching predicate

**Example:**
```javascript
// Filter by age
const adults = df.filter(row => row.get('age') >= 30);

// Filter by string match
const nycOnly = df.filter(row => row.get('city') === 'NYC');

// Multiple conditions
const filtered = df.filter(row =>
  row.get('age') > 25 && row.get('score') > 80
);
```

### `df.slice(start, end): DataFrame`

Get rows by index range.

**Parameters:**
- `start: number` - Start index (inclusive)
- `end: number` - End index (exclusive)

**Returns:** New DataFrame with sliced rows

**Example:**
```javascript
const rows5to10 = df.slice(5, 10);  // Rows 5-9
const first100 = df.slice(0, 100);  // Rows 0-99
```

---

## Missing Data

### `df.isna(columnName): DataFrame`

Detect missing values.

**Parameters:**
- `columnName: string` - Column to check

**Returns:** New DataFrame with boolean column `{columnName}_isna`

**Example:**
```javascript
const result = df.isna('age');
result.show();
//   name    age  age_isna
// 0 Alice    30  false
// 1 Bob      -   true
// 2 Charlie  35  false
```

### `df.notna(columnName): DataFrame`

Detect non-missing values.

**Parameters:**
- `columnName: string` - Column to check

**Returns:** New DataFrame with boolean column `{columnName}_notna`

**Example:**
```javascript
const result = df.notna('age');
result.show();
//   name    age  age_notna
// 0 Alice    30  true
// 1 Bob      -   false
// 2 Charlie  35  true
```

### `df.dropna(columnName): DataFrame`

Drop rows with missing values.

**Parameters:**
- `columnName: string` - Column to check

**Returns:** New DataFrame without rows having null in specified column

**Example:**
```javascript
// Remove rows where age is missing
const cleaned = df.dropna('age');

// Chain multiple dropna calls
const fullyClean = df
  .dropna('age')
  .dropna('city')
  .dropna('score');
```

### `df.fillna(columnName, fillValue): DataFrame`

Fill missing values.

**Parameters:**
- `columnName: string` - Column to fill
- `fillValue: any` - Value to use for missing data

**Returns:** New DataFrame with filled values

**Example:**
```javascript
// Fill missing ages with 0
const df2 = df.fillna('age', 0);

// Fill missing scores with mean
const meanScore = df.mean('score');
const df3 = df.fillna('score', meanScore);

// Fill missing strings
const df4 = df.fillna('city', 'Unknown');
```

---

## String Operations

All string operations create a new DataFrame with the transformed column.

### `df.strLower(columnName): DataFrame`

Convert strings to lowercase.

**Example:**
```javascript
const df2 = df.strLower('email');
// alice@example.com → alice@example.com
// BOB@EXAMPLE.COM → bob@example.com
```

### `df.strUpper(columnName): DataFrame`

Convert strings to uppercase.

**Example:**
```javascript
const df2 = df.strUpper('product');
// widget → WIDGET
// gadget → GADGET
```

### `df.strTrim(columnName): DataFrame`

Remove leading/trailing whitespace.

**Example:**
```javascript
const df2 = df.strTrim('name');
// "  Alice  " → "Alice"
// "Bob" → "Bob"
```

### `df.strContains(columnName, pattern): DataFrame`

Check if string contains substring.

**Parameters:**
- `columnName: string` - Column name
- `pattern: string` - Substring to search for

**Returns:** New DataFrame with boolean column `{columnName}_contains`

**Example:**
```javascript
const result = df.strContains('email', '@example.com');
result.show();
//   email                    email_contains
// 0 alice@example.com         true
// 1 bob@company.com           false
```

### `df.strReplace(columnName, old, new): DataFrame`

Replace substring.

**Parameters:**
- `columnName: string` - Column name
- `old: string` - Substring to replace
- `new: string` - Replacement substring

**Example:**
```javascript
const df2 = df.strReplace('product', 'Widget', 'Component');
// "Widget A" → "Component A"
// "Gadget B" → "Gadget B"
```

### `df.strSlice(columnName, start, end): DataFrame`

Extract substring.

**Parameters:**
- `columnName: string` - Column name
- `start: number` - Start index
- `end: number` - End index (exclusive)

**Example:**
```javascript
const df2 = df.strSlice('name', 0, 3);
// "Alice" → "Ali"
// "Bob" → "Bob"
```

### `df.strStartsWith(columnName, prefix): DataFrame`

Check if string starts with prefix.

**Parameters:**
- `columnName: string` - Column name
- `prefix: string` - Prefix to check

**Returns:** New DataFrame with boolean column `{columnName}_startswith`

**Example:**
```javascript
const result = df.strStartsWith('product', 'Widget');
//   product          product_startswith
// 0 Widget A         true
// 1 Gadget B         false
```

### `df.strEndsWith(columnName, suffix): DataFrame`

Check if string ends with suffix.

**Parameters:**
- `columnName: string` - Column name
- `suffix: string` - Suffix to check

**Returns:** New DataFrame with boolean column `{columnName}_endswith`

**Example:**
```javascript
const result = df.strEndsWith('email', '.com');
//   email                    email_endswith
// 0 alice@example.com         true
// 1 bob@example.org           false
```

### `df.strLen(columnName): DataFrame`

Get string length.

**Parameters:**
- `columnName: string` - Column name

**Returns:** New DataFrame with integer column `{columnName}_len`

**Example:**
```javascript
const result = df.strLen('name');
//   name     name_len
// 0 Alice    5
// 1 Bob      3
```

---

## Numeric Operations

### `df.abs(columnName): DataFrame`

Absolute value.

**Example:**
```javascript
const df2 = df.abs('temperature');
// -5 → 5, 10 → 10
```

### `df.round(columnName, decimals?): DataFrame`

Round to N decimal places.

**Parameters:**
- `decimals?: number` - Decimal places (default: 0)

**Example:**
```javascript
const df2 = df.round('score', 1);
// 95.567 → 95.6
```

---

## Aggregations

### `df.sum(columnName): number`

Sum of column values.

**Example:**
```javascript
const total = df.sum('sales');
console.log(total);  // 15000
```

### `df.mean(columnName): number`

Mean (average) of column values.

**Example:**
```javascript
const avgAge = df.mean('age');
console.log(avgAge);  // 28.5
```

### `df.min(columnName): number`

Minimum value.

**Example:**
```javascript
const minScore = df.min('score');
console.log(minScore);  // 72.3
```

### `df.max(columnName): number`

Maximum value.

**Example:**
```javascript
const maxScore = df.max('score');
console.log(maxScore);  // 98.5
```

### `df.std(columnName): number`

Standard deviation.

**Example:**
```javascript
const stdDev = df.std('age');
console.log(stdDev);  // 5.2
```

### `df.variance(columnName): number`

Variance.

**Example:**
```javascript
const variance = df.variance('score');
console.log(variance);  // 27.04
```

---

## Advanced Aggregations

### `df.median(columnName): number`

Median value (50th percentile).

**Example:**
```javascript
const medianAge = df.median('age');
console.log(medianAge);  // 30
```

### `df.quantile(columnName, q): number`

Quantile (percentile).

**Parameters:**
- `columnName: string` - Column name
- `q: number` - Quantile (0.0 to 1.0)

**Example:**
```javascript
const q25 = df.quantile('score', 0.25);  // 25th percentile
const q50 = df.quantile('score', 0.50);  // 50th percentile (median)
const q75 = df.quantile('score', 0.75);  // 75th percentile
const q90 = df.quantile('score', 0.90);  // 90th percentile
```

### `df.valueCounts(columnName): DataFrame`

Frequency distribution.

**Returns:** DataFrame with columns: `{columnName}`, `count`

**Example:**
```javascript
const counts = df.valueCounts('grade');
counts.show();
//   grade  count
// 0 A      5
// 1 B      3
// 2 C      2
```

### `df.corrMatrix(columnNames): DataFrame`

Correlation matrix.

**Parameters:**
- `columnNames: string[]` - Columns to correlate

**Returns:** Correlation matrix DataFrame

**Example:**
```javascript
const corr = df.corrMatrix(['math', 'science', 'english']);
corr.show();
//          math  science  english
// math     1.00     0.85     0.72
// science  0.85     1.00     0.68
// english  0.72     0.68     1.00
```

### `df.rank(columnName, method): DataFrame`

Rank values.

**Parameters:**
- `columnName: string` - Column to rank
- `method: 'average' | 'min' | 'max' | 'dense' | 'ordinal'` - Ranking method

**Returns:** New DataFrame with column `{columnName}_rank`

**Example:**
```javascript
const ranked = df.rank('score', 'average');
ranked.show();
//   name     score  score_rank
// 0 Alice    95     1.0
// 1 Bob      87     3.0
// 2 Charlie  95     1.0  (tied, average)
// 3 Diana    82     4.0
```

---

## Window Operations

### `df.rollingSum(columnName, windowSize): DataFrame`

Rolling sum.

**Parameters:**
- `columnName: string` - Column name
- `windowSize: number` - Window size

**Returns:** New DataFrame with column `{columnName}_rolling_sum`

**Example:**
```javascript
const df2 = df.rollingSum('sales', 3);
// [10, 20, 30, 40] → [null, null, 60, 90]
```

### `df.rollingMean(columnName, windowSize): DataFrame`

Rolling mean (moving average).

**Example:**
```javascript
const sma5 = df.rollingMean('price', 5);  // 5-day SMA
const sma10 = df.rollingMean('price', 10); // 10-day SMA
```

### `df.rollingMin(columnName, windowSize): DataFrame`

Rolling minimum.

**Example:**
```javascript
const df2 = df.rollingMin('price', 3);
```

### `df.rollingMax(columnName, windowSize): DataFrame`

Rolling maximum.

**Example:**
```javascript
const df2 = df.rollingMax('price', 3);
```

### `df.rollingStd(columnName, windowSize): DataFrame`

Rolling standard deviation (volatility).

**Example:**
```javascript
const volatility = df.rollingStd('price', 20);
```

### `df.expandingSum(columnName): DataFrame`

Cumulative sum.

**Example:**
```javascript
const cumSum = df.expandingSum('sales');
// [10, 20, 30] → [10, 30, 60]
```

### `df.expandingMean(columnName): DataFrame`

Cumulative mean.

**Example:**
```javascript
const cumMean = df.expandingMean('score');
// [90, 80, 85] → [90, 85, 85]
```

---

## Sorting

### `df.sortBy(columnNames, ascending?): DataFrame`

Sort by columns.

**Parameters:**
- `columnNames: string | string[]` - Column(s) to sort by
- `ascending?: boolean | boolean[]` - Sort order (default: true)

**Returns:** Sorted DataFrame

**Example:**
```javascript
// Sort by single column
const df2 = df.sortBy('age');               // ascending
const df3 = df.sortBy('age', false);        // descending

// Sort by multiple columns
const df4 = df.sortBy(['city', 'age']);     // both ascending

// Mixed sort order
const df5 = df.sortBy(['city', 'age'], [true, false]);
// city ascending, age descending
```

---

## Joins

### `df.join(other, on, how?): DataFrame`

Join DataFrames (inner join).

**Parameters:**
- `other: DataFrame` - DataFrame to join with
- `on: string` - Column name to join on
- `how?: 'inner'` - Join type (default: 'inner')

**Returns:** Joined DataFrame

**Example:**
```javascript
const customers = DataFrame.fromCSV(`id,name
1,Alice
2,Bob`);

const orders = DataFrame.fromCSV(`id,customer_id,total
101,1,100
102,2,200
103,1,150`);

const joined = orders.join(customers, 'id');
```

### `df.leftJoin(other, on): DataFrame`

Left outer join.

**Example:**
```javascript
const result = df.leftJoin(other, 'id');
// Keeps all rows from df, matching rows from other
```

### `df.rightJoin(other, on): DataFrame`

Right outer join.

**Example:**
```javascript
const result = df.rightJoin(other, 'id');
// Keeps all rows from other, matching rows from df
```

### `df.outerJoin(other, on): DataFrame`

Full outer join.

**Example:**
```javascript
const result = df.outerJoin(other, 'id');
// Keeps all rows from both DataFrames
```

### `df.crossJoin(other): DataFrame`

Cross join (Cartesian product).

**Example:**
```javascript
const result = df.crossJoin(other);
// Every row from df × every row from other
```

---

## Grouping

### `df.groupBy(columnName): GroupedDataFrame`

Group by column.

**Returns:** GroupedDataFrame for aggregation

**Example:**
```javascript
const grouped = df.groupBy('department');

// Aggregate
const result = grouped.agg({
  salary: 'mean',
  age: 'mean'
});

result.show();
//   department  salary_mean  age_mean
// 0 Engineering    95000     32.5
// 1 Marketing      82000     29.0
```

---

## Reshape Operations

### `df.pivot(index, columns, values, aggFunc): DataFrame`

Pivot table (long to wide).

**Parameters:**
- `index: string` - Row index column
- `columns: string` - Column to pivot
- `values: string` - Values to aggregate
- `aggFunc: 'sum' | 'mean' | 'min' | 'max' | 'count'` - Aggregation function

**Example:**
```javascript
const df = DataFrame.fromCSV(`store,product,sales
A,Widget,100
A,Gadget,80
B,Widget,110
B,Gadget,85`);

const pivoted = df.pivot('store', 'product', 'sales', 'sum');
pivoted.show();
//   store  Widget  Gadget
// 0 A      100     80
// 1 B      110     85
```

### `df.melt(idVars, valueVars, varName, valueName): DataFrame`

Unpivot table (wide to long).

**Parameters:**
- `idVars: string[]` - Columns to keep as identifiers
- `valueVars: string[]` - Columns to unpivot
- `varName: string` - Name for variable column
- `valueName: string` - Name for value column

**Example:**
```javascript
const df = DataFrame.fromCSV(`student,math,science
Alice,95,92
Bob,78,85`);

const melted = df.melt(['student'], ['math', 'science'], 'subject', 'score');
melted.show();
//   student  subject  score
// 0 Alice    math     95
// 1 Alice    science  92
// 2 Bob      math     78
// 3 Bob      science  85
```

### `df.transpose(): DataFrame`

Swap rows and columns.

**Example:**
```javascript
const df2 = df.transpose();
// Rows become columns, columns become rows
```

### `df.stack(): DataFrame`

Stack columns into rows.

**Example:**
```javascript
const stacked = df.stack();
```

### `df.unstack(): DataFrame`

Unstack rows into columns.

**Example:**
```javascript
const unstacked = df.unstack();
```

---

## Apache Arrow

⚠️ **Note**: MVP implementation (v1.3.0) - Schema-only export/import

### `df.toArrow(): ArrowSchema`

Export DataFrame schema to Arrow format.

**Returns:** Arrow schema object (JSON)

**Example:**
```javascript
const arrowSchema = df.toArrow();
console.log(arrowSchema);
// {
//   schema: {
//     fields: [
//       { name: 'name', type: { name: 'utf8' }, nullable: true },
//       { name: 'age', type: { name: 'int' }, nullable: false }
//     ]
//   }
// }
```

### `DataFrame.fromArrow(arrowSchema): DataFrame`

Import DataFrame from Arrow schema.

**Parameters:**
- `arrowSchema: ArrowSchema` - Arrow schema object

**Returns:** DataFrame

**Example:**
```javascript
const schema = {
  schema: {
    fields: [
      { name: 'id', type: { name: 'int' }, nullable: false },
      { name: 'value', type: { name: 'floatingpoint' }, nullable: false }
    ]
  }
};

const df = DataFrame.fromArrow(schema);
```

---

## Lazy Evaluation

⚠️ **Note**: MVP implementation (v1.3.0) - select() and limit() only

### `df.lazy(): LazyDataFrame`

Create lazy DataFrame for query optimization.

**Returns:** LazyDataFrame

**Example:**
```javascript
const lazyDf = df.lazy();
```

### `lazyDf.select(columnNames): LazyDataFrame`

Add column selection to query plan.

**Parameters:**
- `columnNames: string[]` - Columns to select

**Returns:** LazyDataFrame

**Example:**
```javascript
const lazy = df.lazy().select(['name', 'age']);
```

### `lazyDf.limit(n): LazyDataFrame`

Add row limit to query plan.

**Parameters:**
- `n: number` - Number of rows

**Returns:** LazyDataFrame

**Example:**
```javascript
const lazy = df.lazy().limit(100);
```

### `lazyDf.collect(): DataFrame`

Execute optimized query plan.

**Returns:** DataFrame with results

**Example:**
```javascript
const result = df.lazy()
  .select(['name', 'age'])
  .limit(10)
  .collect();  // Execute now!

result.show();
```

---

## Memory Management

### `df.free(): void`

Free DataFrame memory (C ABI required).

**Important**: Always call `free()` when done with a DataFrame to prevent memory leaks.

**Example:**
```javascript
const df = DataFrame.fromCSV(csv);

// Use DataFrame
df.show();

// Free memory
df.free();
```

**Pattern**: Use try/finally for cleanup

```javascript
let df;
try {
  df = DataFrame.fromCSV(csv);

  // Use DataFrame
  const result = df.filter(row => row.get('age') > 30);
  result.show();

  // Free intermediate results
  result.free();
} finally {
  // Always free, even if error
  if (df) df.free();
}
```

---

## TypeScript Support

All operations have full TypeScript definitions with JSDoc examples.

```typescript
import { Rozes, DataFrame, RowRef } from 'rozes';

const rozes = await Rozes.init();
const DataFrame = rozes.DataFrame;

const df: DataFrame = DataFrame.fromCSV(csvString);

// Filter with type safety
const filtered: DataFrame = df.filter((row: RowRef) => {
  const age = row.get('age');
  return typeof age === 'number' && age > 30;
});

// Cleanup
filtered.free();
df.free();
```

---

## Performance Tips

1. **Lazy evaluation**: Use for chained operations on large datasets
   ```javascript
   // Eager (slower)
   const result = df.select(['a', 'b']).head(10);

   // Lazy (faster)
   const result = df.lazy().select(['a', 'b']).limit(10).collect();
   ```

2. **Projection pushdown**: Select columns early
   ```javascript
   // Bad: Load all columns, then select
   const result = df.filter(pred).select(['a', 'b']);

   // Good: Select first (fewer columns to filter)
   const result = df.select(['a', 'b']).filter(pred);
   ```

3. **Batch operations**: Process in chunks for large datasets
   ```javascript
   const chunkSize = 10000;
   for (let i = 0; i < df.shape.rows; i += chunkSize) {
     const chunk = df.slice(i, i + chunkSize);
     // Process chunk
     chunk.free();
   }
   ```

4. **Memory management**: Free intermediate results
   ```javascript
   const df1 = df.filter(pred1);
   const df2 = df1.filter(pred2);
   df1.free();  // Free intermediate result

   // Use df2
   df2.free();
   ```

---

## Error Handling

```javascript
try {
  const df = DataFrame.fromCSV(csvString);

  // Operations that might fail
  const result = df.filter(row => {
    const age = row.get('age');
    if (typeof age !== 'number') {
      throw new Error('Invalid age type');
    }
    return age > 30;
  });

  result.show();
  result.free();
  df.free();

} catch (err) {
  console.error('DataFrame error:', err.message);
}
```

---

## See Also

- [README.md](../README.md) - Quick start guide
- [examples/js/](../examples/js/) - API showcase examples
- [examples/nodejs/](../examples/nodejs/) - Real-world examples
- [CHANGELOG.md](./CHANGELOG.md) - Version history

---

**Last Updated**: 2025-11-08 | **Version**: 1.3.0
