# Rozes Features Documentation

**Version**: 0.5.0 | **Last Updated**: 2025-10-30

This document provides comprehensive API documentation for all features in Rozes DataFrame Library.

---

## Table of Contents

1. [Window Functions](#window-functions)
2. [String Operations](#string-operations)
3. [Categorical Data Type](#categorical-data-type)
4. [Statistical Functions](#statistical-functions)
5. [Missing Value Handling](#missing-value-handling)
6. [JSON Support](#json-support)
7. [Rich Error Messages](#rich-error-messages)
8. [Manual Schema Specification](#manual-schema-specification)

---

## Window Functions

Window functions enable time-series analysis and rolling calculations over ordered data.

### Rolling Windows

Fixed-size windows that slide across the data.

#### Rolling Sum

Calculate the sum over a rolling window.

```javascript
// 7-day rolling sum
const rolling_sum = df.column("sales").rolling(7).sum();
```

**Parameters**:
- `window_size`: Size of the rolling window (u32)

**Returns**: Series with rolling sum values (NaN for insufficient window)

#### Rolling Mean

Calculate the average over a rolling window.

```javascript
// 30-day moving average
const moving_avg = df.column("stock_price").rolling(30).mean();
```

**Use Cases**:
- Stock price moving averages (SMA)
- Smoothing noisy sensor data
- Trend identification

#### Rolling Min/Max

Find minimum or maximum values in rolling windows.

```javascript
// 14-day high
const rolling_high = df.column("price").rolling(14).max();

// 14-day low
const rolling_low = df.column("price").rolling(14).min();
```

#### Rolling Standard Deviation

Measure volatility over rolling windows.

```javascript
// 20-day volatility
const volatility = df.column("returns").rolling(20).std();
```

**Use Cases**:
- Financial risk metrics (volatility)
- Quality control (detecting variance spikes)
- Anomaly detection

### Expanding Windows

Cumulative calculations from the start of the series.

#### Expanding Sum

Cumulative sum (running total).

```javascript
// Cumulative sales
const cumulative_sales = df.column("daily_sales").expanding().sum();
```

#### Expanding Mean

Cumulative average.

```javascript
// Running average
const running_avg = df.column("temperature").expanding().mean();
```

**Use Cases**:
- Running totals (sales, revenue)
- Cumulative averages (lifetime customer value)
- Growth tracking

### Shift Operations

Lag or lead operations for comparing with previous/next values.

#### Forward Shift (Lag)

```javascript
// Previous day's price
const prev_price = df.column("price").shift(1);

// Price change
const price_change = df.column("price") - prev_price;
```

**Parameters**:
- `periods`: Number of periods to shift (positive = lag, negative = lead)

#### Backward Shift (Lead)

```javascript
// Next day's price
const next_price = df.column("price").shift(-1);
```

**Use Cases**:
- Time-series differencing
- Lead/lag analysis
- Computing returns (price changes)

### Difference Operations

#### First Difference

```javascript
// Daily change
const daily_diff = df.column("value").diff();
```

**Formula**: `diff[i] = value[i] - value[i-1]`

#### Percentage Change

```javascript
// Daily return (%)
const daily_return = df.column("stock_price").pct_change();
```

**Formula**: `pct_change[i] = (value[i] - value[i-1]) / value[i-1] * 100`

**Use Cases**:
- Stock returns
- Growth rates
- Velocity metrics

---

## String Operations

Comprehensive string manipulation for text columns.

### Case Conversion

#### Lower Case

Convert all strings to lowercase.

```javascript
const lowercase = df.column("email").str.lower();
```

**Use Cases**:
- Email normalization
- Case-insensitive matching
- Data standardization

#### Upper Case

Convert all strings to uppercase.

```javascript
const uppercase = df.column("country_code").str.upper();
```

### Whitespace Handling

#### Trim

Remove leading and trailing whitespace.

```javascript
const clean = df.column("name").str.trim();
```

**Also available**: `strip()` (alias for trim)

**Use Cases**:
- Data cleaning
- Removing accidental spaces
- CSV import cleanup

### Pattern Matching

#### Contains

Check if string contains a substring.

```javascript
// Find emails with gmail
const gmail_users = df.filter(row =>
  row.getString("email").str.contains("gmail.com")
);
```

**Parameters**:
- `pattern`: Substring to search for (case-sensitive)

**Returns**: Boolean Series (true if contains pattern)

#### Starts With / Ends With

```javascript
// URLs starting with https
const secure = df.column("url").str.startsWith("https://");

// Files ending with .csv
const csv_files = df.column("filename").str.endsWith(".csv");
```

### String Transformation

#### Replace

Find and replace all occurrences.

```javascript
// Normalize phone numbers
const phones = df.column("phone").str.replace("-", "");
```

**Parameters**:
- `from`: String to find
- `to`: Replacement string

#### Split

Split strings into multiple columns.

```javascript
// Split "First Last" into two columns
const [first_names, last_names] = df.column("full_name").str.split(" ");

// Extract domain from email
const domains = df.column("email").str.split("@")[1];
```

**Parameters**:
- `delimiter`: Character(s) to split on

**Returns**: Array of Series (one per split part)

### String Extraction

#### Slice

Extract substring by position.

```javascript
// First 3 characters
const prefixes = df.column("code").str.slice(0, 3);

// Remove first character
const without_prefix = df.column("id").str.slice(1, null);
```

**Parameters**:
- `start`: Start index (inclusive)
- `end`: End index (exclusive, null = end of string)

#### Length

Get string length (UTF-8 character count).

```javascript
const name_lengths = df.column("name").str.len();
```

**Returns**: Int64 Series with character counts

**Note**: Correctly handles multi-byte UTF-8 characters (emoji, CJK, etc.)

---

## Categorical Data Type

Memory-efficient representation for low-cardinality string columns using dictionary encoding.

### Automatic Detection

Rozes automatically detects categorical columns during CSV parsing.

```javascript
const df = rozes.DataFrame.fromCSV(csv);

// Check if column is categorical
console.log(df.column("region").dtype); // "categorical"
console.log(df.column("region").categories); // ["East", "West", "South"]
```

**Detection Heuristic**:
- Column has ≥10 rows
- Unique values / total rows < 5% (cardinality threshold)

### Manual Specification

```javascript
const df = rozes.DataFrame.fromCSV(csv, {
  schema: {
    region: "categorical",
    country: "categorical",
    status: "categorical",
  },
});
```

### Memory Savings

Categorical encoding provides significant memory reduction for low-cardinality data.

```javascript
// Memory comparison
const string_size = df.column("region_as_string").memoryUsage(); // 4 MB
const cat_size = df.column("region_categorical").memoryUsage(); // 1 MB

console.log(`Memory saved: ${(string_size - cat_size) / 1024 / 1024} MB`);
// Output: Memory saved: 3 MB (4× reduction)
```

**Benefits**:
- **4-8× memory reduction** for low-cardinality columns
- **Faster filtering** (integer comparison vs string comparison)
- **Faster sorting** (integer sort, 10-20× faster)
- **Faster groupBy** (integer hash, 5-10× faster)

### API Methods

```javascript
// Get unique categories
const categories = df.column("status").categories;
// ["pending", "active", "completed"]

// Get category count
const count = df.column("status").categoryCount;
// 3

// Get cardinality ratio
const ratio = df.column("status").cardinality();
// 0.03 (3%)
```

### When to Use Categorical

**Good candidates**:
- Region/country columns (5-200 unique values)
- Status fields ("active", "pending", "completed")
- Category labels ("electronics", "clothing", "food")
- Product types (hundreds to thousands of SKUs)

**Poor candidates**:
- High-cardinality columns (>50% unique values)
- User IDs, transaction IDs (nearly 100% unique)
- Free-form text fields

### Deep Copy and Independent DataFrames (0.5.0)

Filtered, joined, or deduplicated DataFrames now create **independent categorical copies** with new dictionaries.

```zig
const df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
defer df.deinit();

// Filter creates independent categorical with own dictionary
const filtered = try df.filter(predicate);
defer filtered.deinit();

// Original and filtered DataFrames are independent
// filtered can be mutated without affecting df
```

**Operations with Deep Copy**:
- `filter()`: Creates new dictionary containing only categories in filtered rows
- `dropDuplicates()`: Rebuilds dictionary for unique rows
- `join()`: Combines dictionaries from both DataFrames

**Memory Implications**:
- **Shallow copy** (pre-0.5.0): Shared dictionary, less memory but no independence
- **Deep copy** (0.5.0+): Independent dictionaries, slightly more memory but full isolation

**Performance**:
- Deep copy is O(n) in filtered row count (rebuilds dictionary)
- Memory overhead proportional to category count (typically <1% of data size)

---

## Statistical Functions

Advanced statistical analysis beyond basic sum/mean/count.

### Standard Deviation & Variance

#### Standard Deviation

```javascript
const age_std = await df.std("age");
// 12.5
```

**Formula**: Sample standard deviation (n-1 denominator)

#### Variance

```javascript
const age_var = await df.variance("age");
// 156.25
```

**Formula**: Sample variance = std²

**Use Cases**:
- Measure data spread
- Risk metrics (portfolio volatility)
- Quality control (variance limits)

### Median & Quantiles

#### Median

```javascript
const median_salary = await df.median("salary");
// 75000
```

**Algorithm**: Full sort + linear interpolation

#### Quantiles

```javascript
// 25th, 50th (median), 75th percentiles
const q25 = await df.quantile("salary", 0.25);
const q50 = await df.quantile("salary", 0.50);
const q75 = await df.quantile("salary", 0.75);

// 90th percentile
const p90 = await df.quantile("salary", 0.90);
```

**Parameters**:
- `q`: Quantile value (0.0 to 1.0)

**Use Cases**:
- Percentile-based analysis
- Outlier detection (IQR method)
- SLA monitoring (p95, p99 latency)

### Correlation Matrix

Calculate Pearson correlation coefficients between multiple columns.

```javascript
const corr = await df.select(["age", "salary", "years_exp"]).corr();

// Returns 3×3 matrix:
// [
//   [1.00, 0.85, 0.92],  // age correlations
//   [0.85, 1.00, 0.78],  // salary correlations
//   [0.92, 0.78, 1.00],  // years_exp correlations
// ]
```

**Interpretation**:
- `1.0`: Perfect positive correlation
- `0.0`: No correlation
- `-1.0`: Perfect negative correlation

**Use Cases**:
- Feature selection (remove highly correlated features)
- Multicollinearity detection
- Relationship discovery

### Ranking

Assign ranks to values in a column with multiple tie-breaking methods (0.5.0).

```zig
// Basic ranking (First method - default)
const salary_rank = try stats.rank(&df.column("salary").?, allocator, .First);
// [10, 20, 20, 30] → [1, 2, 3, 4]

// Average method (pandas default)
const rank_avg = try stats.rank(&df.column("score").?, allocator, .Average);
// [10, 20, 20, 30] → [1, 2.5, 2.5, 4]

// Minimum method
const rank_min = try stats.rank(&df.column("points").?, allocator, .Min);
// [10, 20, 20, 30] → [1, 2, 2, 4]

// Maximum method
const rank_max = try stats.rank(&df.column("value").?, allocator, .Max);
// [10, 20, 20, 30] → [1, 3, 3, 4]
```

**Methods**:
- **First**: Order of appearance after sort (no tie adjustment)
- **Average**: Average rank for tied values (e.g., 2.5 for tied at ranks 2-3)
- **Min**: Minimum rank for tied values
- **Max**: Maximum rank for tied values

**Use Cases**:
- Leaderboards (First or Average)
- Competition scoring (Min for "gold medal position")
- Percentile calculations (Average)
- Sports rankings (various methods)

#### Percentile Rank

Convert ranks to 0-1 scale for percentile interpretation:

```zig
// Percentile rank (0.0 to 1.0)
const pct_rank = try stats.percentileRank(&df.column("score").?, allocator, .Average);
// [10, 20, 30, 40, 50] → [0.0, 0.25, 0.5, 0.75, 1.0]
```

**Formula**: `(rank - 1) / (n - 1)`

**Use Cases**:
- SAT/GRE percentiles
- Performance metrics (top 10% = >0.90)
- Z-score equivalents

### Value Counts

Count unique values and return frequency table (0.5.0).

```zig
// Basic value counts
const counts = try stats.valueCounts(&df.column("region").?, allocator, .{});
// Returns DataFrame: { value: ["East", "West", "South"], count: [523, 412, 301] }

// Normalized (percentages)
const pct = try stats.valueCounts(&df.column("category").?, allocator, .{ .normalize = true });
// Returns: { value: ["A", "B", "C"], count: [0.42, 0.33, 0.25] }

// Unsorted (preserves original order)
const unsorted = try stats.valueCounts(&df.column("status").?, allocator, .{ .sort = false });
```

**Options**:
- `normalize`: Return percentages instead of counts (default: false)
- `sort`: Sort by frequency descending (default: true)

**Supported Types**:
- Int64: Numeric value frequencies
- Bool: True/False counts
- String: Unique string frequencies
- Categorical: Category counts (efficient with dictionary encoding)

**Returns**: DataFrame with columns:
- `value`: Unique values from the original column
- `count`: Frequency (or percentage if normalized)

**Use Cases**:
- Category distribution analysis
- Data quality checks (finding rare values)
- Feature engineering (encoding by frequency)
- Report generation (top N categories)

**Performance**:
- Int64/Bool: O(n) with HashMap
- String: O(n) with string hashing
- Categorical: O(n) leveraging dictionary (fastest)

---

## Missing Value Handling

Handle NaN (Not a Number) and null values in data.

### Detecting Missing Values

#### isna() / notna()

Create boolean masks for missing detection.

```javascript
// Rows with missing age
const has_missing = await df.column("age").isna();

// Rows WITHOUT missing age
const no_missing = await df.column("age").notna();
```

**Returns**: Boolean Series (true for NaN/missing)

### Filling Missing Values

#### Fill with Constant

```javascript
// Fill missing ages with 0
const filled = await df.column("age").fillna({
  method: "constant",
  value: 0
});
```

**Use Cases**:
- Fill with default value (0, -1, "Unknown")
- Fill with median/mean for numeric columns

#### Forward Fill (ffill)

Use previous non-NaN value.

```javascript
// Carry forward last valid sensor reading
const filled = await df.column("sensor_reading").fillna({
  method: "ffill"
});
```

**Example**:
```
Before: [10, NaN, NaN, 15, NaN, 20]
After:  [10, 10,  10,  15, 15,  20]
```

**Use Cases**:
- Time-series data (assume value persists)
- Status fields (retain last known state)

#### Backward Fill (bfill)

Use next non-NaN value.

```javascript
const filled = await df.column("price").fillna({
  method: "bfill"
});
```

**Example**:
```
Before: [10, NaN, NaN, 15, NaN, 20]
After:  [10, 15,  15,  15, 20,  20]
```

#### Linear Interpolation

Estimate missing values using linear interpolation between neighbors.

```javascript
const interpolated = await df.column("temperature").fillna({
  method: "interpolate"
});
```

**Example**:
```
Before: [10, NaN, NaN, 16, NaN, 20]
After:  [10, 12,  14,  16, 18,  20]
```

**Formula**: `value = prev + (next - prev) * (pos - prev_pos) / (next_pos - prev_pos)`

**Use Cases**:
- Temperature readings
- Stock prices
- Smooth time-series data

### Removing Missing Values

#### Drop Any

Remove rows with ANY missing value (default).

```javascript
const clean = await df.dropna();
```

**Example**:
```
Before:
  age   salary  city
  30    50000   NYC
  NaN   60000   LA
  35    NaN     SF

After:
  age   salary  city
  30    50000   NYC
```

#### Drop All

Remove only rows with ALL values missing.

```javascript
const clean = await df.dropna({ how: "all" });
```

**Example**:
```
Before:
  age   salary  city
  30    50000   NYC
  NaN   NaN     NaN  ← removed
  35    NaN     SF

After:
  age   salary  city
  30    50000   NYC
  35    NaN     SF
```

#### Drop with Column Subset

Check only specific columns for missing values.

```javascript
// Drop only if age OR salary is missing
const clean = await df.dropna({
  subset: ["age", "salary"]
});
```

**Use Cases**:
- Require specific critical columns (age, salary)
- Allow missing in optional columns (notes, comments)

---

## JSON Support

Import and export DataFrames in JSON format. **Fully implemented in 0.5.0** with comprehensive parsing for all three formats.

### Supported Formats

#### 1. Line-Delimited JSON (NDJSON)

Most common format for streaming data.

```json
{"name": "Alice", "age": 30, "city": "NYC"}
{"name": "Bob", "age": 25, "city": "LA"}
{"name": "Charlie", "age": 35, "city": "SF"}
```

```javascript
const df = rozes.DataFrame.fromJSON(ndjson, { format: "ndjson" });
```

**Use Cases**:
- Log files (one event per line)
- Streaming APIs
- NoSQL database exports

#### 2. JSON Array of Objects

Standard JSON array format.

```json
[
  { "name": "Alice", "age": 30, "city": "NYC" },
  { "name": "Bob", "age": 25, "city": "LA" },
  { "name": "Charlie", "age": 35, "city": "SF" }
]
```

```javascript
const df = rozes.DataFrame.fromJSON(jsonArray, { format: "array" });
```

**Use Cases**:
- REST API responses
- Standard JSON exports
- Configuration files

#### 3. Columnar JSON

Most efficient for DataFrame-like data.

```json
{
  "name": ["Alice", "Bob", "Charlie"],
  "age": [30, 25, 35],
  "city": ["NYC", "LA", "SF"]
}
```

```javascript
const df = rozes.DataFrame.fromJSON(columnar, { format: "columnar" });
```

**Use Cases**:
- DataFrame serialization
- Efficient data transfer
- Column-oriented databases

### Export to JSON

```javascript
// Export as NDJSON (default)
const ndjson = df.toJSON({ format: "ndjson" });

// Export as array
const array = df.toJSON({ format: "array" });

// Export as columnar
const columnar = df.toJSON({ format: "columnar" });

// Pretty-print with indentation
const pretty = df.toJSON({
  format: "array",
  pretty: true,
  indent: 2
});
```

### Options

```javascript
const df = rozes.DataFrame.fromJSON(json, {
  format: "ndjson",          // or "array", "columnar"
  type_inference: true,      // Auto-detect Int64/Float64/String/Bool
  schema: {                  // Manual type specification
    age: "int64",
    salary: "float64",
    name: "string",
    active: "bool",
  },
});
```

### Implementation Details (0.5.0)

**Parsing**:
- Uses `std.json.parseFromSlice()` for all formats
- Automatic type inference (Int64, Float64, String, Bool, Null detection)
- Handles missing keys (fills with NaN/null/0/false)
- Validates JSON structure before parsing
- Schema validation for consistency

**Performance**:
- NDJSON: O(n) line-by-line parsing
- Array: O(n) object iteration
- Columnar: O(n × m) where m = column count (most efficient)

**Memory Management**:
- Arena allocators for DataFrame lifecycle
- Zero memory leaks (validated with 1000-iteration stress tests)
- Efficient string deduplication

**Test Coverage**:
- 40 comprehensive tests across all 3 formats
- Edge cases: empty data, missing keys, type mismatches
- Large datasets (1000+ rows)
- Memory leak validation

**Note**: JSON export deferred to 0.6.0 to prioritize production-ready parsing.

---

## Performance Characteristics

### Window Functions
- **Rolling operations**: O(n × w) where w = window size
- **Expanding operations**: O(n²) worst case, O(n) with optimization
- **Shift/diff/pct_change**: O(n) single pass

### String Operations
- **lower/upper/trim**: O(n × m) where m = avg string length
- **contains/replace**: O(n × m × p) where p = pattern length
- **split**: O(n × m) + memory for result arrays

### Categorical Type
- **Encoding**: O(n) first pass + O(1) HashMap lookups
- **Lookup**: O(1) via dictionary index
- **Memory**: ~u32 per row (4 bytes) vs 4-20 bytes per string

### Statistical Functions
- **std/var**: O(n) two-pass (mean, then squared differences)
- **median/quantile**: O(n log n) full sort
- **corr**: O(n × m²) where m = number of columns
- **rank**: O(n log n) sort + O(n) rank assignment

### Missing Value Operations
- **fillna (constant/ffill/bfill)**: O(n) single pass
- **fillna (interpolate)**: O(n) with forward/backward scans
- **dropna**: O(n) filter + O(n) copy

---

## Rich Error Messages

Detailed, actionable error messages for CSV parsing and DataFrame operations (0.5.0).

### CSV Parser Errors

All CSV parsing errors now include row, column, field value, and hints.

#### Field Size Error

```
RozesError: Field exceeds maximum size (1MB)
  at row 47823
  in column 'description'
  Field value: "Lorem ipsum dolor sit amet, consectetur..."
  Hint: Split large text fields or increase max_field_size
```

#### Invalid Quoting

```
RozesError: Invalid quoting - unescaped quote in quoted field
  at row 1203
  in column 'address'
  CSV context: ...123 Main "Street", Suite..."
  Hint: Escape quotes with double-quote ("") per RFC 4180
```

#### Type Mismatch

```
RozesError: Failed to parse value as Int64
  at row 5042
  in column 'age'
  Field value: "thirty-five"
  Hint: Expected numeric value (e.g., 35) or use String type
```

### DataFrame Operation Errors

#### Column Not Found

```
RozesError: Column not found
  Column: 'salary'
  Available columns: ['name', 'age', 'city', 'department']
  Hint: Check column name spelling or use df.columnNames()
```

#### Index Out of Bounds

```
RozesError: Row index out of bounds
  Index: 1500
  Valid range: 0..999 (1000 rows)
  Hint: Use df.len() to check row count
```

#### Type Cast Error

```
RozesError: Cannot cast Series to Int64
  Series: 'name'
  Expected type: Int64
  Actual type: String
  Hint: Use asString() instead of asInt64()
```

### Implementation (0.5.0)

24 high-priority error sites updated with rich context:
- CSV Parser: 10 error sites (field size, quoting, type inference, etc.)
- DataFrame Operations: 14 error sites (column lookup, index bounds, type casts)

All errors use temporary ArenaAllocator for formatting (zero memory overhead).

---

## Manual Schema Specification

Override auto-detection with manual type specification for CSV columns (0.5.0).

### Basic Usage

```zig
const allocator = std.heap.page_allocator;

// Create schema map
var schema = SchemaMap.init(allocator);
defer schema.deinit();

// Specify column types
try schema.put("region", .Categorical);
try schema.put("country", .Categorical);
try schema.put("age", .Int64);
try schema.put("salary", .Float64);

// Parse with manual schema
var opts = CSVOptions{};
opts.schema = &schema;

var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
defer df.deinit();
```

### Use Cases

#### Force Categorical Type

Useful when auto-detection would infer String:

```zig
// High cardinality data (100+ unique values) but still categorical
var schema = SchemaMap.init(allocator);
try schema.put("product_id", .Categorical);  // Override String → Categorical
try schema.put("category", .Categorical);    // Low cardinality, would auto-detect
```

**Memory Savings**: 4-8× reduction for categorical vs string storage.

#### Preserve Leading Zeros

Force Int64 or String for data like zip codes:

```zig
// Preserve "00123" as string (not parsed as 123)
var schema = SchemaMap.init(allocator);
try schema.put("zip_code", .String);
```

#### Override Float → Int

When decimals are formatting artifacts:

```zig
// "10.0" → 10 (Int64 instead of Float64)
var schema = SchemaMap.init(allocator);
try schema.put("quantity", .Int64);
```

### Mixed Specification

Combine manual schema with auto-detection:

```zig
// Only specify problematic columns
var schema = SchemaMap.init(allocator);
try schema.put("region", .Categorical);  // Manual
// age, salary, name will auto-detect

var opts = CSVOptions{};
opts.schema = &schema;
opts.infer_types = true;  // Auto-detect unspecified columns

var df = try DataFrame.fromCSVBuffer(allocator, csv, opts);
```

### Validation

Schema validation prevents common mistakes:

```zig
var empty_schema = SchemaMap.init(allocator);
// Empty schema returns error
try opts.validate(); // → error.EmptySchema
```

### Implementation (0.5.0)

- **SchemaMap**: `std.StringHashMap(ValueType)` for O(1) lookups
- **Integration**: Parser checks schema first, falls back to auto-detection
- **Flexibility**: Partial specification allowed
- **Test Coverage**: 12 comprehensive tests

### Performance

- **No overhead** when schema not provided
- **O(1) lookup** per column during type inference
- **Zero allocation** overhead (schema owned by caller)

---

## API Stability

Features in this document are part of Rozes 0.5.0 and follow semantic versioning:

- **Stable APIs**: Window functions, String operations, Categorical type, Statistical functions, Missing value handling, JSON parsing
- **New in 0.5.0**: Rich error messages, Manual schema specification, Value counts, Rank methods, Categorical deep copy

Breaking changes will only occur in major version bumps (1.0.0 → 2.0.0).

---

**Last Updated**: 2025-10-30
**Version**: 0.5.0
