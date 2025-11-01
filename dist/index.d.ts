/**
 * Rozes DataFrame Library - TypeScript Type Definitions
 *
 * High-performance DataFrame library powered by WebAssembly.
 * 3-10× faster than Papa Parse and csv-parse.
 */

/**
 * CSV parsing options
 */
export interface CSVOptions {
  /** Field delimiter (default: ',') */
  delimiter?: string;

  /** Whether first row contains headers (default: true) */
  has_headers?: boolean;

  /** Skip blank lines (default: true) */
  skip_blank_lines?: boolean;

  /** Trim whitespace from fields (default: false) */
  trim_whitespace?: boolean;

  /**
   * Automatically free memory when DataFrame is garbage collected (default: true)
   *
   * **⚠️ Important Tradeoffs:**
   *
   * **When to use `autoCleanup: true` (default - convenient):**
   * - No need to call `df.free()`
   * - Memory freed automatically when DataFrame goes out of scope
   * - Convenient for scripts and exploration
   * - Can still call `df.free()` for immediate cleanup
   * - **BUT**: Non-deterministic cleanup timing (GC decides when)
   * - **BUT**: Memory can grow in loops (1000 DataFrames → wait for GC)
   * - **BUT**: GC pauses can be 10-100ms
   *
   * **When to use `autoCleanup: false` (opt-out for production):**
   * - Predictable memory usage (you control when memory is freed)
   * - No GC pauses from Wasm cleanup
   * - Better performance in tight loops (~3× faster)
   * - Easier to debug memory issues
   * - **Must call `df.free()` when done**
   *
   * @example
   * ```typescript
   * // Auto (default - convenient)
   * const df = DataFrame.fromCSV(csv);
   * // use df
   * // Memory freed automatically (eventually)
   * df.free(); // Optional but recommended for immediate cleanup
   * ```
   *
   * @example
   * ```typescript
   * // Manual (opt-out for production)
   * const df = DataFrame.fromCSV(csv, { autoCleanup: false });
   * try {
   *   // use df
   * } finally {
   *   df.free(); // Must call - deterministic cleanup
   * }
   * ```
   */
  autoCleanup?: boolean;
}

/**
 * DataFrame shape (dimensions)
 */
export interface DataFrameShape {
  /** Number of rows */
  rows: number;

  /** Number of columns */
  cols: number;
}

/**
 * Rozes error codes
 */
export enum ErrorCode {
  Success = 0,
  OutOfMemory = -1,
  InvalidFormat = -2,
  InvalidHandle = -3,
  ColumnNotFound = -4,
  TypeMismatch = -5,
  IndexOutOfBounds = -6,
  TooManyDataFrames = -7,
  InvalidOptions = -8,
}

/**
 * Rozes error class
 */
export class RozesError extends Error {
  /** Error code */
  readonly code: ErrorCode;

  constructor(code: ErrorCode, message?: string);
}

/**
 * DataFrame class - represents a 2D columnar data structure
 *
 * @example
 * ```typescript
 * const rozes = await Rozes.init();
 * const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n25,87.3");
 * console.log(df.shape); // { rows: 2, cols: 3 }
 * df.free(); // Release memory
 * ```
 */
export class DataFrame {
  /**
   * Parse CSV string into DataFrame
   *
   * @param csvText - CSV data as string
   * @param options - Parsing options
   * @returns New DataFrame instance
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("age,score\n30,95.5\n25,87.3");
   * ```
   */
  static fromCSV(csvText: string, options?: CSVOptions): DataFrame;

  /**
   * Load CSV from file (Node.js only)
   *
   * @param filePath - Path to CSV file
   * @param options - Parsing options
   * @returns New DataFrame instance
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSVFile('data.csv');
   * ```
   */
  static fromCSVFile(filePath: string, options?: CSVOptions): DataFrame;

  /**
   * Get DataFrame dimensions
   *
   * @example
   * ```typescript
   * console.log(df.shape); // { rows: 1000, cols: 5 }
   * ```
   */
  readonly shape: DataFrameShape;

  /**
   * Get column names
   *
   * @example
   * ```typescript
   * console.log(df.columns); // ['age', 'score', 'name']
   * ```
   */
  readonly columns: string[];

  /**
   * Get number of rows
   */
  readonly length: number;

  /**
   * Get column data as typed array or string array (zero-copy for numeric types)
   *
   * @param name - Column name
   * @returns Typed array, string array, or null if not found
   *   - Float64Array for Float64 columns
   *   - BigInt64Array for Int64 columns
   *   - Uint8Array for Bool columns (0 = false, 1 = true)
   *   - string[] for String columns
   *
   * @example
   * ```typescript
   * const ages = df.column('age'); // Float64Array or BigInt64Array
   * const names = df.column('name'); // string[]
   * const active = df.column('active'); // Uint8Array
   * ```
   */
  column(name: string): Float64Array | Int32Array | BigInt64Array | Uint8Array | string[] | null;

  /**
   * Select specific columns from DataFrame
   *
   * @param columnNames - Array of column names to select
   * @returns New DataFrame with selected columns only
   *
   * @example
   * ```typescript
   * const selected = df.select(['name', 'age']);
   * selected.free(); // Don't forget to free!
   * ```
   */
  select(columnNames: string[]): DataFrame;

  /**
   * Get first n rows of DataFrame
   *
   * @param n - Number of rows to return
   * @returns New DataFrame with first n rows
   *
   * @example
   * ```typescript
   * const top10 = df.head(10);
   * top10.free();
   * ```
   */
  head(n: number): DataFrame;

  /**
   * Get last n rows of DataFrame
   *
   * @param n - Number of rows to return
   * @returns New DataFrame with last n rows
   *
   * @example
   * ```typescript
   * const bottom10 = df.tail(10);
   * bottom10.free();
   * ```
   */
  tail(n: number): DataFrame;

  /**
   * Sort DataFrame by column
   *
   * @param columnName - Column to sort by
   * @param descending - Sort in descending order (default: false)
   * @returns New sorted DataFrame
   *
   * @example
   * ```typescript
   * const sorted = df.sort('age'); // ascending
   * const sortedDesc = df.sort('age', true); // descending
   * sorted.free();
   * sortedDesc.free();
   * ```
   */
  sort(columnName: string, descending?: boolean): DataFrame;

  /**
   * Filter DataFrame by numeric condition
   *
   * @param columnName - Column to filter on
   * @param operator - Comparison operator: '==', '!=', '>', '<', '>=', '<='
   * @param value - Value to compare against
   * @returns New filtered DataFrame
   *
   * @example
   * ```typescript
   * const adults = df.filter('age', '>=', 18);
   * const seniors = df.filter('age', '>', 65);
   * adults.free();
   * seniors.free();
   * ```
   */
  filter(columnName: string, operator: '==' | '!=' | '>' | '<' | '>=' | '<=', value: number): DataFrame;

  /**
   * Group DataFrame by column and apply aggregation function
   *
   * Groups rows by unique values in the specified column and applies
   * an aggregation function to another column. Returns a new DataFrame
   * with two columns: [groupColumn, aggregatedValue].
   *
   * **Available aggregation functions:**
   * - `'sum'` - Sum of values in each group
   * - `'mean'` - Average of values in each group
   * - `'count'` - Number of rows in each group
   * - `'min'` - Minimum value in each group
   * - `'max'` - Maximum value in each group
   *
   * **Performance:** O(n) where n = number of rows
   *
   * @param groupColumn - Column to group by
   * @param valueColumn - Column to aggregate
   * @param aggFunc - Aggregation function: 'sum' | 'mean' | 'count' | 'min' | 'max'
   * @returns New DataFrame with grouped and aggregated data
   *
   * @example
   * ```typescript
   * // Group by city and calculate average age
   * const avgAgeByCity = df.groupBy('city', 'age', 'mean');
   * console.log(avgAgeByCity.shape); // { rows: num_unique_cities, cols: 2 }
   * avgAgeByCity.free();
   * ```
   *
   * @example
   * ```typescript
   * // Group by region and sum sales
   * const salesByRegion = df.groupBy('region', 'sales', 'sum');
   * salesByRegion.free();
   * ```
   *
   * @example
   * ```typescript
   * // Count items per category
   * const itemsPerCategory = df.groupBy('category', 'id', 'count');
   * itemsPerCategory.free();
   * ```
   */
  groupBy(
    groupColumn: string,
    valueColumn: string,
    aggFunc: 'sum' | 'mean' | 'count' | 'min' | 'max'
  ): DataFrame;

  /**
   * Join this DataFrame with another DataFrame
   *
   * Combines rows from two DataFrames based on matching values in specified columns.
   * Supports inner join (only matching rows) and left join (all left rows + matching right).
   *
   * **Join types:**
   * - `'inner'` (default) - Only rows where join columns match in both DataFrames
   * - `'left'` - All rows from left DataFrame + matching rows from right
   *
   * **Column naming:**
   * - Columns from left DataFrame keep original names
   * - Columns from right DataFrame are suffixed with `_right` if name conflicts exist
   * - Join columns appear only once in result
   *
   * **Performance:** O(n + m) where n = left rows, m = right rows (hash join algorithm)
   *
   * @param other - DataFrame to join with
   * @param on - Column name(s) to join on (must exist in both DataFrames)
   * @param how - Join type: 'inner' | 'left' (default: 'inner')
   * @returns New DataFrame with joined data
   *
   * @example
   * ```typescript
   * // Inner join on single column
   * const joined = users.join(orders, 'user_id');
   * // Result: Only users who have orders
   * joined.free();
   * ```
   *
   * @example
   * ```typescript
   * // Left join on single column
   * const joined = users.join(orders, 'user_id', 'left');
   * // Result: All users, with null values for users without orders
   * joined.free();
   * ```
   *
   * @example
   * ```typescript
   * // Inner join on multiple columns
   * const joined = sales.join(regions, ['city', 'state'], 'inner');
   * joined.free();
   * ```
   *
   * @example
   * ```typescript
   * // Complete join workflow
   * const customers = DataFrame.fromCSV(customersCSV);
   * const orders = DataFrame.fromCSV(ordersCSV);
   *
   * try {
   *   const joined = customers.join(orders, 'customer_id', 'left');
   *   console.log(joined.shape);
   *   joined.free();
   * } finally {
   *   customers.free();
   *   orders.free();
   * }
   * ```
   */
  join(
    other: DataFrame,
    on: string | string[],
    how?: 'inner' | 'left'
  ): DataFrame;

  /**
   * Export DataFrame to CSV format
   *
   * @param options - CSV formatting options
   * @returns CSV string
   *
   * @example
   * ```typescript
   * // Default options (comma-separated with headers)
   * const csv = df.toCSV();
   * console.log(csv);
   * // Output:
   * // name,age,score
   * // Alice,30,95.5
   * // Bob,25,87.3
   * ```
   *
   * @example
   * ```typescript
   * // Custom delimiter (tab-separated)
   * const tsv = df.toCSV({ delimiter: '\t' });
   * ```
   *
   * @example
   * ```typescript
   * // Without headers
   * const dataOnly = df.toCSV({ has_headers: false });
   * ```
   *
   * @example
   * ```typescript
   * // Save to file (Node.js)
   * import * as fs from 'fs';
   * const csv = df.toCSV();
   * fs.writeFileSync('output.csv', csv, 'utf-8');
   * ```
   */
  toCSV(options?: {
    /** Field delimiter (default: ',') */
    delimiter?: string;
    /** Include header row (default: true) */
    has_headers?: boolean;
  }): string;

  /**
   * Compute sum of a numeric column (SIMD-accelerated)
   *
   * **Performance**: SIMD vectorization provides 30%+ speedup over scalar implementation
   *
   * @param columnName - Name of the column to sum
   * @returns Sum of all values in the column, or NaN if column not found
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV('price,quantity\n10.5,2\n20.0,3\n15.75,1\n');
   * const totalPrice = df.sum('price'); // 46.25 (SIMD-accelerated)
   * ```
   */
  sum(columnName: string): number;

  /**
   * Compute mean (average) of a numeric column (SIMD-accelerated)
   *
   * **Performance**: SIMD vectorization provides 30%+ speedup over scalar implementation
   *
   * @param columnName - Name of the column to average
   * @returns Mean of all values, or NaN if column not found
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV('price\n10\n20\n30\n');
   * const avgPrice = df.mean('price'); // 20.0
   * ```
   */
  mean(columnName: string): number;

  /**
   * Find minimum value in a numeric column (SIMD-accelerated)
   *
   * **Performance**: SIMD vectorization provides 30%+ speedup over scalar implementation
   *
   * @param columnName - Name of the column
   * @returns Minimum value, or NaN if column not found
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV('price\n10.5\n20.0\n5.75\n');
   * const minPrice = df.min('price'); // 5.75
   * ```
   */
  min(columnName: string): number;

  /**
   * Find maximum value in a numeric column (SIMD-accelerated)
   *
   * **Performance**: SIMD vectorization provides 30%+ speedup over scalar implementation
   *
   * @param columnName - Name of the column
   * @returns Maximum value, or NaN if column not found
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV('price\n10.5\n20.0\n5.75\n');
   * const maxPrice = df.max('price'); // 20.0
   * ```
   */
  max(columnName: string): number;

  /**
   * Compute variance of a numeric column (SIMD-accelerated)
   *
   * Uses sample variance formula (n-1 denominator) for unbiased estimation.
   * **Performance**: SIMD vectorization provides 30%+ speedup over scalar implementation
   *
   * @param columnName - Name of the column
   * @returns Sample variance, or NaN if column not found
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV('price\n10\n20\n30\n');
   * const variance = df.variance('price'); // 100.0
   * ```
   */
  variance(columnName: string): number;

  /**
   * Compute standard deviation of a numeric column (SIMD-accelerated)
   *
   * Uses sample standard deviation formula (sqrt of sample variance).
   * **Performance**: SIMD vectorization provides 30%+ speedup over scalar implementation
   *
   * @param columnName - Name of the column
   * @returns Sample standard deviation, or NaN if column not found
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV('price\n10\n20\n30\n');
   * const stddev = df.stddev('price'); // 10.0
   * ```
   */
  stddev(columnName: string): number;

  /**
   * Free DataFrame memory
   *
   * **Automatic memory management (autoCleanup: true, default):**
   * This is optional, but still recommended for deterministic cleanup.
   *
   * **Manual memory management (autoCleanup: false):**
   * You MUST call this when done to prevent memory leaks.
   *
   * **Why call free() even with autoCleanup enabled?**
   * - Immediate memory release (no waiting for GC)
   * - Predictable performance in tight loops (~3× faster)
   * - Better control over memory usage
   *
   * @example
   * ```typescript
   * // Auto cleanup (default - optional free)
   * const df = DataFrame.fromCSV(csvText);
   * // ... use df
   * df.free(); // Optional but recommended for immediate cleanup
   * // If not called, memory freed automatically on GC
   * ```
   *
   * @example
   * ```typescript
   * // Manual cleanup (production - required free)
   * const df = DataFrame.fromCSV(csvText, { autoCleanup: false });
   * try {
   *   // ... use df
   * } finally {
   *   df.free(); // MUST call - deterministic cleanup
   * }
   * ```
   */
  free(): void;

  /**
   * Drop columns from DataFrame
   *
   * @param columnNames - Array of column names to drop
   * @returns New DataFrame without the specified columns
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("name,age,score\nAlice,30,95.5\n");
   * const reduced = df.drop(['score']); // Keep only 'name' and 'age'
   * reduced.free();
   * ```
   */
  drop(columnNames: string[]): DataFrame;

  /**
   * Rename a column in the DataFrame
   *
   * @param oldName - Current column name
   * @param newName - New column name
   * @returns New DataFrame with renamed column
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("age,score\n30,95.5\n25,87.3\n");
   * const renamed = df.rename('age', 'years');
   * console.log(renamed.columns); // ['years', 'score']
   * renamed.free();
   * ```
   */
  rename(oldName: string, newName: string): DataFrame;

  /**
   * Get unique values from a column
   *
   * @param columnName - Column name
   * @returns Array of unique values (all as strings)
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("category\nA\nB\nA\nC\nB\n");
   * const unique = df.unique('category');
   * console.log(unique); // ['A', 'B', 'C']
   * ```
   */
  unique(columnName: string): string[];

  /**
   * Remove duplicate rows based on subset of columns
   *
   * @param subset - Column names to check for duplicates (null = all columns)
   * @returns New DataFrame with duplicates removed
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("name,age\nAlice,30\nBob,25\nAlice,30\n");
   * const unique = df.dropDuplicates();
   * console.log(unique.shape); // { rows: 2, cols: 2 } - removed 1 duplicate
   * unique.free();
   * ```
   *
   * @example
   * ```typescript
   * // Only check 'name' column for duplicates
   * const uniqueNames = df.dropDuplicates(['name']);
   * uniqueNames.free();
   * ```
   */
  dropDuplicates(subset?: string[] | null): DataFrame;

  /**
   * Summary statistics for all numeric columns
   */
  interface SummaryStats {
    /** Number of non-null values */
    count?: number;
    /** Mean/average value */
    mean?: number;
    /** Standard deviation */
    std?: number;
    /** Minimum value */
    min?: number;
    /** Maximum value */
    max?: number;
  }

  /**
   * Get summary statistics for all numeric columns
   *
   * @returns Object mapping column names to summary stats
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("age,score\n30,95.5\n25,87.3\n35,91.0\n");
   * const stats = df.describe();
   * console.log(stats);
   * // Output:
   * // {
   * //   age: { count: 3, mean: 30, std: 5, min: 25, max: 35 },
   * //   score: { count: 3, mean: 91.27, std: 4.11, min: 87.3, max: 95.5 }
   * // }
   * ```
   */
  describe(): Record<string, SummaryStats>;

  /**
   * Random sample of n rows (with replacement)
   *
   * @param n - Number of rows to sample
   * @returns New DataFrame with sampled rows
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("name,age\nAlice,30\nBob,25\nCharlie,35\n");
   * const sample = df.sample(5); // Sample 5 rows with replacement
   * console.log(sample.shape); // { rows: 5, cols: 2 }
   * sample.free();
   * ```
   */
  sample(n: number): DataFrame;

  /**
   * Drop rows with any missing (null/NaN) values
   *
   * @returns New DataFrame with missing values removed
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("age,score\n30,95.5\n25,NaN\n35,91.0\n");
   * const clean = df.dropna();
   * console.log(clean.shape); // { rows: 2, cols: 2 } - row with NaN removed
   * ```
   */
  dropna(): DataFrame;

  /**
   * Check for missing values in a column
   *
   * Returns a boolean array where 1 indicates a missing value (null/NaN)
   *
   * @param columnName - Name of the column to check
   * @returns Boolean array (1 = missing, 0 = present)
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("age,score\n30,95.5\n25,NaN\n35,91.0\n");
   * const mask = df.isna('score');
   * console.log(mask); // Uint8Array [0, 1, 0] - second value is missing
   * ```
   */
  isna(columnName: string): Uint8Array;

  /**
   * Check for non-missing values in a column
   *
   * Returns a boolean array where 1 indicates a present (non-null/non-NaN) value
   *
   * @param columnName - Name of the column to check
   * @returns Boolean array (1 = present, 0 = missing)
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("age,score\n30,95.5\n25,NaN\n35,91.0\n");
   * const mask = df.notna('score');
   * console.log(mask); // Uint8Array [1, 0, 1] - second value is missing
   * ```
   */
  notna(columnName: string): Uint8Array;

  /**
   * Export DataFrame to CSV string
   *
   * @param options - CSV formatting options
   * @returns CSV string
   *
   * @example
   * ```typescript
   * const csv = df.toCSV();
   * console.log(csv);
   * // Output:
   * // name,age,score
   * // Alice,30,95.5
   * // Bob,25,87.3
   * ```
   *
   * @example
   * ```typescript
   * // Custom delimiter (tab-separated)
   * const tsv = df.toCSV({ delimiter: '\t' });
   * ```
   *
   * @example
   * ```typescript
   * // Without headers
   * const dataOnly = df.toCSV({ has_headers: false });
   * ```
   */
  toCSV(options?: CSVOptions): string;

  /**
   * Access string operations on DataFrame columns
   *
   * @returns StringAccessor - Namespace for string operations
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("text\nHELLO\nWorld\nMiXeD\n");
   * const lower = df.str.lower('text');
   * console.log(lower.at(0, 'text')); // 'hello'
   * ```
   */
  readonly str: StringAccessor;
}

/**
 * StringAccessor - String operations on DataFrame columns
 *
 * Provides pandas-like string operations for text data manipulation.
 */
export interface StringAccessor {
  /**
   * Convert strings to lowercase
   *
   * @param columnName - Name of the column to convert
   * @returns New DataFrame with lowercase strings
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("text\nHELLO\nWorld\n");
   * const lower = df.str.lower('text');
   * console.log(lower.at(0, 'text')); // 'hello'
   * console.log(lower.at(1, 'text')); // 'world'
   * ```
   */
  lower(columnName: string): DataFrame;

  /**
   * Convert strings to uppercase
   *
   * @param columnName - Name of the column to convert
   * @returns New DataFrame with uppercase strings
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("text\nhello\nworld\n");
   * const upper = df.str.upper('text');
   * console.log(upper.at(0, 'text')); // 'HELLO'
   * ```
   */
  upper(columnName: string): DataFrame;

  /**
   * Trim whitespace from strings
   *
   * @param columnName - Name of the column to trim
   * @returns New DataFrame with trimmed strings
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("text\n  hello  \n  world  \n");
   * const trimmed = df.str.trim('text');
   * console.log(trimmed.at(0, 'text')); // 'hello'
   * ```
   */
  trim(columnName: string): DataFrame;

  /**
   * Check if strings contain a substring
   *
   * @param columnName - Name of the column to check
   * @param pattern - Substring to search for
   * @returns New DataFrame with boolean column
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("text\nhello world\ngoodbye world\nfoo bar\n");
   * const contains = df.str.contains('text', 'world');
   * console.log(contains.at(0, 'text')); // true
   * console.log(contains.at(2, 'text')); // false
   * ```
   */
  contains(columnName: string, pattern: string): DataFrame;

  /**
   * Replace substring in strings
   *
   * @param columnName - Name of the column to modify
   * @param from - Substring to replace
   * @param to - Replacement substring
   * @returns New DataFrame with replaced strings
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("text\nhello world\nhello there\n");
   * const replaced = df.str.replace('text', 'hello', 'hi');
   * console.log(replaced.at(0, 'text')); // 'hi world'
   * ```
   */
  replace(columnName: string, from: string, to: string): DataFrame;

  /**
   * Extract substring from strings
   *
   * @param columnName - Name of the column to slice
   * @param start - Start index (inclusive)
   * @param end - End index (exclusive)
   * @returns New DataFrame with sliced strings
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("text\nhello\nworld\n");
   * const sliced = df.str.slice('text', 0, 3);
   * console.log(sliced.at(0, 'text')); // 'hel'
   * console.log(sliced.at(1, 'text')); // 'wor'
   * ```
   */
  slice(columnName: string, start: number, end: number): DataFrame;

  /**
   * Get length of strings
   *
   * @param columnName - Name of the column
   * @returns New DataFrame with integer column containing string lengths
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("text\na\nab\nabc\n");
   * const lengths = df.str.len('text');
   * console.log(lengths.at(0, 'text')); // 1
   * console.log(lengths.at(2, 'text')); // 3
   * ```
   */
  len(columnName: string): DataFrame;

  /**
   * Check if strings start with a prefix
   *
   * @param columnName - Name of the column to check
   * @param prefix - Prefix to check for
   * @returns New DataFrame with boolean column
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("text\nhello world\nhello there\ngoodbye\n");
   * const starts = df.str.startsWith('text', 'hello');
   * console.log(starts.at(0, 'text')); // true
   * console.log(starts.at(2, 'text')); // false
   * ```
   */
  startsWith(columnName: string, prefix: string): DataFrame;

  /**
   * Check if strings end with a suffix
   *
   * @param columnName - Name of the column to check
   * @param suffix - Suffix to check for
   * @returns New DataFrame with boolean column
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV("text\nhello world\ngoodbye world\nfoo bar\n");
   * const ends = df.str.endsWith('text', 'world');
   * console.log(ends.at(0, 'text')); // true
   * console.log(ends.at(2, 'text')); // false
   * ```
   */
  endsWith(columnName: string, suffix: string): DataFrame;
}

/**
 * Main Rozes class
 *
 * @example
 * ```typescript
 * const rozes = await Rozes.init();
 * console.log(rozes.version); // "1.0.0"
 * const df = rozes.DataFrame.fromCSV(csvText);
 * ```
 */
export class Rozes {
  /**
   * Initialize Rozes library
   *
   * Loads the WebAssembly module. Call this before using any DataFrame operations.
   *
   * @param wasmPath - Optional custom path to WASM file (defaults to bundled)
   * @returns Initialized Rozes instance
   *
   * @example
   * ```typescript
   * const rozes = await Rozes.init();
   * const df = rozes.DataFrame.fromCSV("age,score\n30,95.5");
   * ```
   */
  static init(wasmPath?: string): Promise<Rozes>;

  /**
   * DataFrame class reference
   */
  readonly DataFrame: typeof DataFrame;

  /**
   * Library version
   */
  readonly version: string;
}

// Default export
export default Rozes;
