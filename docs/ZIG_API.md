# Rozes Zig API Reference

**Version**: 1.0.0
**Last Updated**: 2025-10-31

Comprehensive Zig API reference for embedding Rozes in Zig applications - high-performance columnar data processing.

**Note**: For Node.js/JavaScript API, see [NODEJS_API.md](./NODEJS_API.md)

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core Concepts](#core-concepts)
3. [Creating DataFrames](#creating-dataframes)
4. [DataFrame Operations](#dataframe-operations)
5. [Reshaping Operations](#reshaping-operations)
6. [Combining DataFrames](#combining-dataframes)
7. [Functional Operations](#functional-operations)
8. [Aggregation & Statistics](#aggregation--statistics)
9. [Window Operations](#window-operations)
10. [String Operations](#string-operations)
11. [Missing Data](#missing-data)
12. [Import/Export](#importexport)
13. [Performance Tips](#performance-tips)

---

## Quick Start

```zig
const std = @import("std");
const rozes = @import("rozes.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load CSV data
    const csv = "name,age,score\nAlice,30,95.5\nBob,25,87.3\nCharlie,35,91.0\n";
    var df = try rozes.DataFrame.fromCSVBuffer(allocator, csv, .{});
    defer df.deinit();

    // Display info
    try df.info(std.io.getStdOut().writer());

    // Filter rows
    const filtered = try df.filter(allocator, ageOver30);
    defer filtered.deinit();

    // Select columns
    const selected = try filtered.select(allocator, &[_][]const u8{"name", "score"});
    defer selected.deinit();

    // Group and aggregate
    const grouped = try df.groupBy(allocator, &[_][]const u8{"age"}, &[_]rozes.AggSpec{
        .{ .column = "score", .func = .mean },
    });
    defer grouped.deinit();
}

fn ageOver30(row: rozes.RowRef) bool {
    const age = row.getInt64("age") orelse return false;
    return age > 30;
}
```

---

## Core Concepts

### DataFrame

A two-dimensional table with labeled columns and rows. Data is stored in columnar format for efficient operations.

**Properties**:
- `row_count: u32` - Number of rows
- `columns: []Series` - Array of Series (columns)
- `column_descs: []ColumnDesc` - Column metadata

**Key Features**:
- Columnar memory layout (cache-friendly)
- Type-safe operations (compile-time type checking)
- Zero-copy where possible
- Arena allocator for efficient memory management

### Series

A one-dimensional array with a single data type (column).

**Supported Types**:
- `Int64` - 64-bit signed integers
- `Float64` - 64-bit floating point
- `String` - UTF-8 strings
- `Bool` - Booleans
- `Categorical` - Enum-like categories (memory-efficient for low-cardinality data)
- `Null` - Missing values

### ColumnDesc

Column metadata with name and type information.

```zig
const desc = rozes.ColumnDesc.init("age", .Int64, 0);
```

---

## Creating DataFrames

### From CSV

#### `fromCSVBuffer(allocator, buffer, options)`

Parse CSV data from a string buffer.

```zig
const csv = "name,age,score\nAlice,30,95.5\nBob,25,87.3\n";
var df = try rozes.DataFrame.fromCSVBuffer(allocator, csv, .{});
defer df.deinit();
```

**Options**:
```zig
const options = rozes.CSVOptions{
    .delimiter = ',',
    .quoteChar = '"',
    .hasHeader = true,
    .previewRows = 100,        // Type inference sample size
    .schema = null,            // Manual schema override
};
```

**Performance**:
- 1M rows: ~550ms (3-10× faster than Papa Parse)
- Memory: O(n) where n = data size

#### `fromCSVFile(allocator, path, options)`

Load CSV from file path.

```zig
var df = try rozes.DataFrame.fromCSVFile(allocator, "data.csv", .{});
defer df.deinit();
```

### From JSON

#### `fromJSONBuffer(allocator, buffer, format, options)`

Parse JSON data (NDJSON, Array, or Columnar formats).

```zig
// NDJSON format (newline-delimited JSON)
const json =
    \\{"name":"Alice","age":30,"score":95.5}
    \\{"name":"Bob","age":25,"score":87.3}
;
var df = try rozes.DataFrame.fromJSONBuffer(allocator, json, .NDJSON, .{});
defer df.deinit();
```

**Formats**:
- `.NDJSON` - One JSON object per line (streaming-friendly)
- `.Array` - Array of objects: `[{}, {}]`
- `.Columnar` - Column-oriented: `{"col1": [], "col2": []}`

### Manual Creation

#### `create(allocator, columnDescs, capacity)`

Create empty DataFrame with schema.

```zig
const descs = [_]rozes.ColumnDesc{
    rozes.ColumnDesc.init("name", .String, 0),
    rozes.ColumnDesc.init("age", .Int64, 1),
    rozes.ColumnDesc.init("score", .Float64, 2),
};

var df = try rozes.DataFrame.create(allocator, &descs, 1000);
defer df.deinit();

// Populate data...
```

---

## DataFrame Operations

### Querying

#### `head(n)` / `tail(n)`

Get first/last N rows.

```zig
const first_10 = try df.head(allocator, 10);
defer first_10.deinit();

const last_10 = try df.tail(allocator, 10);
defer last_10.deinit();
```

**Performance**: O(n) where n = rows to copy

#### `sample(n)`

Random sample of N rows.

```zig
const sample = try df.sample(allocator, 100);
defer sample.deinit();
```

**Use Case**: Exploratory analysis on large datasets

#### `column(name)`

Access column by name (O(1) with hash map).

```zig
const age_series = df.column("age").?;
const ages = age_series.asInt64().?;

std.debug.print("First age: {}\n", .{ages[0]});
```

### Filtering

#### `filter(allocator, predicate)`

Filter rows based on condition.

```zig
var filtered = try df.filter(allocator, ageOver30);
defer filtered.deinit();

fn ageOver30(row: rozes.RowRef) bool {
    const age = row.getInt64("age") orelse return false;
    return age > 30;
}
```

**Performance**: O(n) scan, ~14ms for 1M rows

**RowRef API**:
- `getInt64(column_name) ?i64`
- `getFloat64(column_name) ?f64`
- `getString(column_name) ?[]const u8`
- `getBool(column_name) ?bool`

### Selection

#### `select(allocator, column_names)`

Select subset of columns.

```zig
const selected = try df.select(allocator, &[_][]const u8{"name", "score"});
defer selected.deinit();
```

**Performance**: O(n) copy for selected columns

#### `drop(allocator, column_names)`

Drop specified columns.

```zig
const dropped = try df.drop(allocator, &[_][]const u8{"score"});
defer dropped.deinit();
```

### Sorting

#### `sort(allocator, specs)`

Sort by one or more columns.

```zig
const specs = [_]rozes.SortSpec{
    .{ .column = "age", .order = .Ascending },
    .{ .column = "score", .order = .Descending },  // Tiebreaker
};

var sorted = try df.sort(allocator, &specs);
defer sorted.deinit();
```

**Performance**:
- Single column: ~6.73ms for 100K rows (timsort)
- Multi-column: O(n log n) with stable sort

**Sort Order**:
- `.Ascending` - 1, 2, 3...
- `.Descending` - 3, 2, 1...

### Renaming

#### `rename(allocator, old_name, new_name)`

Rename a column.

```zig
var renamed = try df.rename(allocator, "age", "years");
defer renamed.deinit();
```

---

## Reshaping Operations

### Pivot Tables

#### `pivot(allocator, options)`

Transform from long to wide format.

```zig
// Input: name,year,metric,value
//        Alice,2023,sales,100
//        Alice,2023,profit,20
//        Alice,2024,sales,120
//        Bob,2023,sales,90

const pivoted = try df.pivot(allocator, .{
    .index = "name",          // Row labels
    .columns = "metric",      // Column labels
    .values = "value",        // Values to aggregate
    .aggfunc = .sum,          // Aggregation function
});
defer pivoted.deinit();

// Output: name,sales,profit
//         Alice,220,20
//         Bob,90,0
```

**Aggregation Functions**:
- `.sum` - Sum of values
- `.mean` - Average
- `.count` - Count of non-null values
- `.min` / `.max` - Minimum/maximum

**Performance**:
- Time: O(n × m) where n = rows, m = unique pivot values
- Space: O(i × c) where i = unique index values, c = unique column values
- Typical: 100K rows × 100 unique values → ~500ms

**Warning**: Avoid high-cardinality columns (>1000 unique values). Result size = (unique index) × (unique columns).

### Melt

#### `melt(allocator, options)`

Transform from wide to long format (unpivot).

```zig
// Input: name,sales_2023,sales_2024,profit_2023,profit_2024
//        Alice,100,120,20,25

const melted = try df.melt(allocator, .{
    .id_vars = &[_][]const u8{"name"},           // Columns to keep
    .value_vars = &[_][]const u8{                // Columns to melt
        "sales_2023", "sales_2024",
        "profit_2023", "profit_2024"
    },
    .var_name = "metric_year",                    // Name for variable column
    .value_name = "amount",                       // Name for value column
});
defer melted.deinit();

// Output: name,metric_year,amount
//         Alice,sales_2023,100
//         Alice,sales_2024,120
//         Alice,profit_2023,20
//         Alice,profit_2024,25
```

**Performance**: O(n × m) where m = columns to melt

**Overflow Protection**: Checks `row_count × melt_columns.len` before allocation

### Transpose

#### `transpose(allocator)`

Swap rows and columns.

```zig
// Input:  name,age,score
//         Alice,30,95
//         Bob,25,87

const transposed = try df.transpose(allocator);
defer transposed.deinit();

// Output: field,Alice,Bob
//         name,Alice,Bob
//         age,30,25
//         score,95,87
```

**Performance**: O(rows × columns)

**Limitation**: Result columns are String type (preserves mixed-type data)

### Stack / Unstack

#### `stack(allocator, options)`

Stack specified level from columns to index (compress columns).

```zig
const stacked = try df.stack(allocator, .{
    .level = -1,  // Last column level
});
defer stacked.deinit();
```

#### `unstack(allocator, options)`

Unstack specified level from rows to columns (expand rows).

```zig
const unstacked = try df.unstack(allocator, .{
    .level = -1,  // Last row level
    .fill_value = 0.0,
});
defer unstacked.deinit();
```

---

## Combining DataFrames

### Concatenation

#### `concat(allocator, dataframes, options)`

Concatenate DataFrames along an axis.

```zig
// Vertical concat (stack rows)
const dfs = [_]*rozes.DataFrame{ &df1, &df2, &df3 };
const concatenated = try rozes.combine.concat(allocator, &dfs, .{
    .axis = .Vertical,
    .ignore_index = true,  // Reset row indices
});
defer concatenated.deinit();

// Horizontal concat (join columns)
const concatenated = try rozes.combine.concat(allocator, &dfs, .{
    .axis = .Horizontal,
});
defer concatenated.deinit();
```

**Options**:
- `.axis` - `.Vertical` (rows) or `.Horizontal` (columns)
- `.ignore_index` - Reset row indices (vertical only)
- `.join` - `.Inner` or `.Outer` (horizontal only)

**Performance**: O(total_rows × columns)

### Merge/Join

#### `merge(allocator, right, options)`

SQL-style joins on common columns or specified keys.

```zig
// Inner join on 'id' column
const merged = try left.merge(allocator, &right, .{
    .how = .Inner,
    .on = &[_][]const u8{"id"},
});
defer merged.deinit();

// Left join with different key names
const merged = try left.merge(allocator, &right, .{
    .how = .Left,
    .left_on = &[_][]const u8{"user_id"},
    .right_on = &[_][]const u8{"id"},
    .suffixes = .{ .left = "_l", .right = "_r" },  // For duplicate column names
});
defer merged.deinit();
```

**Join Types**:
- `.Inner` - Intersection (only matching keys)
- `.Left` - All left + matching right (null-fill for non-matches)
- `.Right` - All right + matching left
- `.Outer` - Union (all keys from both)
- `.Cross` - Cartesian product (all combinations)

**Performance**:
- Hash join: O(n + m) average case
- Pure join algorithm: 1.42ms for 10K × 10K (85% faster than target)
- Full pipeline (CSV generation + parsing + join): ~700ms

**Optimizations**:
- String interning for low-cardinality keys (4-8× memory reduction)
- SIMD string comparisons (2-4× faster)
- Hash caching (20-30% faster, future enhancement)

#### `innerJoin(allocator, right, on)`

Shorthand for inner join.

```zig
const joined = try left.innerJoin(allocator, &right, &[_][]const u8{"id"});
defer joined.deinit();
```

### Append

#### `append(allocator, other, options)`

Add rows from another DataFrame (must have matching columns).

```zig
var updated = try df.append(allocator, &new_rows, .{
    .ignore_index = true,
    .verify_integrity = true,  // Check for duplicate indices
});
defer updated.deinit();
```

**Performance**: O(rows_to_add)

### Update

#### `update(allocator, other, options)`

Update values from another DataFrame (in-place value replacement).

```zig
const updated = try df.update(allocator, &updates, .{
    .overwrite = true,  // Replace existing values
});
defer updated.deinit();
```

**Use Case**: Patch existing data with corrections

---

## Functional Operations

### Apply

#### `apply(allocator, function, options)`

Apply function to rows or columns.

```zig
// Apply to each row
const results = try df.apply(allocator, calculateBonus, .{
    .axis = .Rows,
    .result_type = .Float64,
});
defer results.deinit();

fn calculateBonus(row: rozes.RowRef) f64 {
    const salary = row.getFloat64("salary") orelse return 0.0;
    const rating = row.getFloat64("rating") orelse return 0.0;
    return salary * rating * 0.1;
}

// Apply to each column
const results = try df.apply(allocator, columnSum, .{
    .axis = .Columns,
    .result_type = .Float64,
});
defer results.deinit();

fn columnSum(series: *const rozes.Series) f64 {
    return rozes.operations.sum(series);
}
```

**Performance**: O(n) or O(m) depending on axis

### Map

#### `mapFloat64(allocator, series, function)`

Transform Float64 values element-wise.

```zig
const doubled = try rozes.functional.mapFloat64(allocator, series, double);
defer doubled.deinit();

fn double(x: f64) f64 {
    return x * 2.0;
}
```

#### `mapInt64(allocator, series, function)`

Transform Int64 values.

```zig
const incremented = try rozes.functional.mapInt64(allocator, series, increment);
defer incremented.deinit();

fn increment(x: i64) i64 {
    return x + 1;
}
```

#### `mapBool(allocator, series, function)`

Transform Boolean values.

```zig
const negated = try rozes.functional.mapBool(allocator, series, negate);
defer negated.deinit();

fn negate(x: bool) bool {
    return !x;
}
```

### Type Conversion Maps

#### `mapInt64ToFloat64(allocator, series, function)`

Convert Int64 → Float64 with transformation.

```zig
const normalized = try rozes.functional.mapInt64ToFloat64(
    allocator,
    series,
    normalizeScore
);
defer normalized.deinit();

fn normalizeScore(score: i64) f64 {
    return @as(f64, @floatFromInt(score)) / 100.0;
}
```

#### `mapFloat64ToInt64(allocator, series, function)`

Convert Float64 → Int64 (truncates decimals).

```zig
const rounded = try rozes.functional.mapFloat64ToInt64(
    allocator,
    series,
    roundToNearest
);
defer rounded.deinit();

fn roundToNearest(x: f64) i64 {
    return @intFromFloat(@round(x));
}
```

#### `mapBoolToInt64(allocator, series, function)`

Convert Bool → Int64.

```zig
const binary = try rozes.functional.mapBoolToInt64(
    allocator,
    series,
    boolToInt
);
defer binary.deinit();

fn boolToInt(x: bool) i64 {
    return if (x) 1 else 0;
}
```

---

## Aggregation & Statistics

### GroupBy

#### `groupBy(allocator, by_columns, agg_specs)`

Group rows and apply aggregations.

```zig
const grouped = try df.groupBy(
    allocator,
    &[_][]const u8{"department"},        // Group by column
    &[_]rozes.AggSpec{
        .{ .column = "salary", .func = .mean },
        .{ .column = "salary", .func = .sum },
        .{ .column = "employee_id", .func = .count },
    }
);
defer grouped.deinit();
```

**Aggregation Functions**:
- `.sum` - Total
- `.mean` - Average
- `.count` - Count of non-null
- `.min` / `.max` - Minimum/maximum
- `.std` - Standard deviation
- `.var` - Variance

**Performance**:
- 1.92ms for 100K rows (optimized with hash-based grouping)
- Future: 30% faster with SIMD aggregations

### Statistics

#### `describe(allocator)`

Summary statistics for numeric columns.

```zig
const summary = try df.describe(allocator);
defer summary.deinit();

// Output: column,count,mean,std,min,25%,50%,75%,max
```

**Includes**: count, mean, std, min, quartiles, max

#### `valueCounts(allocator, column_name, options)`

Frequency distribution of unique values.

```zig
const counts = try df.valueCounts(allocator, "category", .{
    .sort = true,
    .ascending = false,  // Most frequent first
});
defer counts.deinit();
```

**Performance**:
- Current: 1987ms for 1M unique values
- Future: <500ms with string interning + pre-allocated HashMap

### Column Statistics

All return Float64 value or error.

```zig
const avg_age = try rozes.operations.mean(age_series);
const total = try rozes.operations.sum(sales_series);
const spread = try rozes.operations.std(scores_series);
const variance = try rozes.operations.variance(values_series);
const lowest = try rozes.operations.min(prices_series);
const highest = try rozes.operations.max(prices_series);
const mid = try rozes.operations.median(data_series);
```

**NaN Handling**:
- Comparisons (min/max) treat NaN as greater than all values
- Aggregations (sum/mean) skip NaN values
- Statistics report NaN count separately

---

## Window Operations

### Rolling Windows

#### `rolling(allocator, series, window_size, function)`

Apply function to sliding window.

```zig
// 7-day moving average
const ma7 = try rozes.window_ops.rolling(
    allocator,
    price_series,
    7,
    rozes.window_ops.mean
);
defer ma7.deinit();

// Custom window function
const custom = try rozes.window_ops.rolling(
    allocator,
    data_series,
    5,
    myWindowFunc
);
defer custom.deinit();

fn myWindowFunc(window: []const f64) f64 {
    // Compute custom statistic
    var sum: f64 = 0;
    for (window) |val| sum += val;
    return sum / @as(f64, @floatFromInt(window.len));
}
```

**Built-in Functions**:
- `rozes.window_ops.mean` - Average
- `rozes.window_ops.sum` - Total
- `rozes.window_ops.min` / `max` - Min/max
- `rozes.window_ops.std` - Standard deviation

**Edge Behavior**: Smaller windows at start/end (min_periods = 1)

### Expanding Windows

#### `expanding(allocator, series, function)`

Cumulative window from start to current position.

```zig
// Cumulative sum
const cumsum = try rozes.window_ops.expanding(
    allocator,
    sales_series,
    rozes.window_ops.sum
);
defer cumsum.deinit();

// Running average
const running_avg = try rozes.window_ops.expanding(
    allocator,
    scores_series,
    rozes.window_ops.mean
);
defer running_avg.deinit();
```

**Use Case**: Year-to-date totals, cumulative statistics

---

## String Operations

Operations on String-type columns.

### Case Conversion

```zig
const upper = try rozes.string_ops.toUpper(allocator, name_series);
defer upper.deinit();

const lower = try rozes.string_ops.toLower(allocator, email_series);
defer lower.deinit();
```

### String Predicates

```zig
// Check if starts with prefix
const is_mr = try rozes.string_ops.startsWith(allocator, title_series, "Mr.");
defer is_mr.deinit();

// Check if ends with suffix
const is_email = try rozes.string_ops.endsWith(allocator, contact_series, "@example.com");
defer is_email.deinit();

// Check if contains substring
const has_keyword = try rozes.string_ops.contains(allocator, description_series, "urgent");
defer has_keyword.deinit();
```

**Returns**: Boolean Series

### String Properties

```zig
// String length
const lengths = try rozes.string_ops.len(allocator, text_series);
defer lengths.deinit();
```

**Returns**: Int64 Series

---

## Missing Data

### Detection

#### `isNull(series)`

Check for null values in a Series.

```zig
const nulls = rozes.missing.isNull(series);
defer nulls.deinit();

// Count nulls
var null_count: u32 = 0;
for (nulls.data.Bool) |is_null| {
    if (is_null) null_count += 1;
}
```

### Filling

#### `fillna(allocator, series, fill_value)`

Replace null values with specified value.

```zig
// Fill with constant
const filled = try rozes.missing.fillna(allocator, series, .{ .Float64 = 0.0 });
defer filled.deinit();

// Fill with forward/backward propagation
const ffill = try rozes.missing.fillnaMethod(allocator, series, .ForwardFill);
defer ffill.deinit();

const bfill = try rozes.missing.fillnaMethod(allocator, series, .BackwardFill);
defer bfill.deinit();
```

**Fill Methods**:
- `.Constant` - Use provided value
- `.ForwardFill` - Propagate last valid value forward
- `.BackwardFill` - Propagate next valid value backward
- `.Mean` - Use column mean (numeric only)
- `.Median` - Use column median (numeric only)

### Dropping

#### `dropna(allocator, options)`

Remove rows with null values.

```zig
// Drop rows with any null
const cleaned = try df.dropna(allocator, .{ .how = .Any });
defer cleaned.deinit();

// Drop rows where all values are null
const cleaned = try df.dropna(allocator, .{ .how = .All });
defer cleaned.deinit();

// Drop only if specific columns have nulls
const cleaned = try df.dropna(allocator, .{
    .how = .Any,
    .subset = &[_][]const u8{"age", "score"},
});
defer cleaned.deinit();
```

---

## Import/Export

### CSV

#### Import

```zig
// From buffer
const csv_data = "name,age\nAlice,30\nBob,25\n";
var df = try rozes.DataFrame.fromCSVBuffer(allocator, csv_data, .{});
defer df.deinit();

// From file
var df = try rozes.DataFrame.fromCSVFile(allocator, "data.csv", .{});
defer df.deinit();

// Custom options
var df = try rozes.DataFrame.fromCSVBuffer(allocator, csv_data, .{
    .delimiter = '\t',         // Tab-separated
    .quoteChar = '\'',         // Single quote
    .hasHeader = false,        // No header row
    .previewRows = 1000,       // Larger type inference sample
});
defer df.deinit();
```

#### Export

```zig
const csv_output = try df.toCSV(allocator, .{});
defer allocator.free(csv_output);

std.debug.print("{s}\n", .{csv_output});
```

**Performance**:
- Parse: 570ms for 1M rows (37% faster than baseline with SIMD)
- Export: O(n) serialization

**RFC 4180 Compliance**: 100% (125/125 conformance tests passing)

### JSON

#### Import

```zig
// NDJSON (newline-delimited)
const ndjson =
    \\{"name":"Alice","age":30}
    \\{"name":"Bob","age":25}
;
var df = try rozes.DataFrame.fromJSONBuffer(allocator, ndjson, .NDJSON, .{});
defer df.deinit();

// Array of objects
const json_array =
    \\[{"name":"Alice","age":30},{"name":"Bob","age":25}]
;
var df = try rozes.DataFrame.fromJSONBuffer(allocator, json_array, .Array, .{});
defer df.deinit();

// Columnar format
const json_cols =
    \\{"name":["Alice","Bob"],"age":[30,25]}
;
var df = try rozes.DataFrame.fromJSONBuffer(allocator, json_cols, .Columnar, .{});
defer df.deinit();
```

#### Export

```zig
const json_output = try df.toJSON(allocator, .{
    .format = .NDJSON,
    .pretty = false,
});
defer allocator.free(json_output);
```

---

## Performance Tips

### Memory Management

**1. Use Arena Allocators**

DataFrames use arena allocators internally for efficient batch allocation/deallocation.

```zig
// Single deinit() frees all DataFrame memory
var df = try rozes.DataFrame.fromCSVBuffer(allocator, csv, .{});
defer df.deinit();  // Frees everything at once
```

**2. Avoid Intermediate Copies**

Chain operations to minimize copies:

```zig
// ❌ BAD - Creates 3 intermediate DataFrames
const filtered = try df.filter(allocator, predicate1);
defer filtered.deinit();
const filtered2 = try filtered.filter(allocator, predicate2);
defer filtered2.deinit();
const result = try filtered2.select(allocator, &cols);
defer result.deinit();

// ✅ BETTER - Combine predicates
const result = try df.filter(allocator, combinedPredicate)
    .select(allocator, &cols);
defer result.deinit();
```

### Type Optimization

**1. Use Categorical for Low-Cardinality Strings**

```zig
// For columns with <100 unique values, use Categorical
// Memory: 4 bytes per row vs 16+ bytes per string
// Join: 80-90% faster (740ms → 100ms for 10K×10K)

const csv = "user_id,country\n1,USA\n2,UK\n3,USA\n";
var df = try rozes.DataFrame.fromCSVBuffer(allocator, csv, .{
    .schema = &[_]rozes.ColumnDesc{
        rozes.ColumnDesc.init("user_id", .Int64, 0),
        rozes.ColumnDesc.init("country", .Categorical, 1),  // Low cardinality
    },
});
defer df.deinit();
```

**2. Use Int64 Instead of Float64 When Possible**

Integer operations are 2-3× faster than floating-point.

### Algorithm Selection

**1. Prefer Hash-Based Operations**

```zig
// ✅ FAST - Hash join O(n + m)
const joined = try left.merge(allocator, &right, .{ .how = .Inner, .on = &[_][]const u8{"id"} });

// ❌ SLOW - Nested loop join O(n × m)
// (Avoid manual nested iteration)
```

**2. Use SIMD-Accelerated Operations**

SIMD operations are 2-4× faster for large datasets:

- CSV parsing (SIMD delimiter detection)
- String comparisons (16-byte vectorization)
- Numeric aggregations (planned: SIMD sum/mean)

**3. Pre-filter Before Expensive Operations**

```zig
// ✅ FAST - Filter first (reduce data size)
const recent = try df.filter(allocator, isRecent);
defer recent.deinit();
const pivoted = try recent.pivot(allocator, pivot_opts);
defer pivoted.deinit();

// ❌ SLOW - Pivot entire dataset
const pivoted = try df.pivot(allocator, pivot_opts);
```

### Benchmarking

**Current Performance** (as of 0.7.0):

| Operation            | Dataset         | Time    | vs Target |
|----------------------|-----------------|---------|-----------|
| CSV Parse            | 1M rows         | 570ms   | 37% faster|
| Filter               | 1M rows         | 14ms    | Excellent |
| Sort (single col)    | 100K rows       | 6.73ms  | Good      |
| GroupBy              | 100K rows       | 1.92ms  | Excellent |
| Join (pure algorithm)| 10K × 10K       | 1.42ms  | 86% faster|
| Join (full pipeline) | 10K × 10K       | ~700ms  | (includes CSV overhead) |

**Memory**:
- Peak usage: <2× CSV size for numeric data
- Zero memory leaks (1000-iteration verified)

### Future Optimizations (1.0.0)

Planned improvements:

1. **SIMD CSV Parsing**: 23% faster (909ms → <700ms)
2. **SIMD Aggregations**: 30% faster GroupBy
3. **Hash Caching**: 20-30% faster join/groupby with String keys
4. **Column Name HashMap**: O(1) lookups (30-50% faster wide DataFrames)
5. **Bundle Size**: 62KB → <60KB (wasm-opt + dead code elimination)

See `docs/OPTIMIZATION_ROADMAP_1.0.0.md` for detailed roadmap.

---

## Error Handling

All operations return errors via Zig's error union type (`!ResultType`).

**Common Errors**:

- `error.OutOfMemory` - Allocation failed
- `error.ColumnNotFound` - Column name doesn't exist
- `error.TypeMismatch` - Incompatible column types
- `error.IndexOutOfBounds` - Row/column index out of range
- `error.InvalidFormat` - CSV/JSON parsing error

**Example**:

```zig
const df = rozes.DataFrame.fromCSVBuffer(allocator, csv, .{}) catch |err| {
    std.log.err("Failed to parse CSV: {}", .{err});
    return err;
};
```

**Best Practice**: Always handle errors explicitly (never use `catch null`).

---

## Type Reference

### ValueType

```zig
pub const ValueType = enum {
    Int64,      // 64-bit signed integer
    Float64,    // 64-bit floating point
    String,     // UTF-8 string
    Bool,       // Boolean
    Categorical,// Enum-like categories
    Null,       // Missing value marker
};
```

### AggFunc

```zig
pub const AggFunc = enum {
    sum,        // Total
    mean,       // Average
    count,      // Count of non-null
    min,        // Minimum
    max,        // Maximum
    std,        // Standard deviation
    var,        // Variance
};
```

### MergeHow

```zig
pub const MergeHow = enum {
    Inner,      // Intersection
    Left,       // All left + matching right
    Right,      // All right + matching left
    Outer,      // Union (all keys)
    Cross,      // Cartesian product
};
```

---

## Next Steps

- **Tutorials**: See `docs/TUTORIALS.md` (planned)
- **Migration Guide**: See `docs/MIGRATION.md` for pandas/Polars equivalents
- **Examples**: Browse `examples/` directory (planned)
- **Performance**: See `docs/OPTIMIZATION_ROADMAP_1.0.0.md`

---

**Version**: 0.7.0
**Last Updated**: 2025-10-31
**License**: MIT
