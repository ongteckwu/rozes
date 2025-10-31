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
