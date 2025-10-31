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
   * Get column data as typed array
   *
   * @param name - Column name
   * @returns Typed array (Float64Array, Int32Array, etc.) or null if not found
   *
   * @example
   * ```typescript
   * const ages = df.column('age'); // Float64Array [30, 25]
   * ```
   */
  column(name: string): Float64Array | Int32Array | BigInt64Array | null;

  // NOTE: toCSV() and toCSVFile() will be added in 1.1.0

  /**
   * Free DataFrame memory
   *
   * **IMPORTANT**: You must call this when done with the DataFrame
   * to release WebAssembly memory.
   *
   * @example
   * ```typescript
   * const df = DataFrame.fromCSV(csvText);
   * // ... use df
   * df.free(); // Release memory
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
