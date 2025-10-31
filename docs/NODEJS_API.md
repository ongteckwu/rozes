# Rozes Node.js API Reference

**Version**: 1.0.0
**Last Updated**: 2025-10-31

High-performance DataFrame library for Node.js powered by WebAssembly. 3-10× faster than Papa Parse and csv-parse.

---

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [Initialization](#initialization)
4. [DataFrame Creation](#dataframe-creation)
5. [DataFrame Properties](#dataframe-properties)
6. [DataFrame Methods](#dataframe-methods)
7. [CSV Options](#csv-options)
8. [TypeScript Types](#typescript-types)
9. [Error Handling](#error-handling)
10. [Memory Management](#memory-management)
11. [Performance Tips](#performance-tips)
12. [Complete Examples](#complete-examples)

---

## Installation

```bash
npm install rozes
```

**Requirements**:
- Node.js 14+ (LTS versions recommended)
- No native dependencies (pure WASM)

---

## Quick Start

### CommonJS

```javascript
const { Rozes } = require('rozes');

async function main() {
  const rozes = await Rozes.init();
  const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n25,87.3");

  console.log(df.shape); // { rows: 2, cols: 2 }
  console.log(df.columns); // ['age', 'score']

  const ages = df.column('age'); // Float64Array [30, 25]
  console.log(Array.from(ages));

  df.free(); // Always free when done!
}

main();
```

### ES Modules

```javascript
import { Rozes } from 'rozes';

const rozes = await Rozes.init();
const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n25,87.3");

console.log(df.shape); // { rows: 2, cols: 2 }
df.free();
```

### TypeScript

```typescript
import { Rozes, DataFrame } from 'rozes';

const rozes: Rozes = await Rozes.init();
const df: DataFrame = rozes.DataFrame.fromCSV("age,score\n30,95.5\n25,87.3");

// Full autocomplete support
const shape = df.shape; // { rows: number, cols: number }
const columns = df.columns; // string[]
const ages = df.column('age'); // Float64Array | Int32Array | BigInt64Array | null

df.free();
```

---

## Initialization

### `Rozes.init(wasmPath?: string): Promise<Rozes>`

Initialize the Rozes library by loading the WebAssembly module.

**Parameters**:
- `wasmPath` (optional): Custom path to WASM file. Defaults to bundled `rozes.wasm`.

**Returns**: Promise resolving to initialized `Rozes` instance

**Example**:

```javascript
// Use bundled WASM (default)
const rozes = await Rozes.init();

// Use custom WASM path
const rozes = await Rozes.init('./custom-path/rozes.wasm');

// Access version
console.log(rozes.version); // "1.0.0"
```

**Notes**:
- Must be called before any DataFrame operations
- Only needs to be called once per application
- WASM module is ~62KB (35KB gzipped)

---

## DataFrame Creation

### `DataFrame.fromCSV(csvText: string, options?: CSVOptions): DataFrame`

Parse CSV string into DataFrame.

**Parameters**:
- `csvText`: CSV data as string
- `options` (optional): Parsing options (see [CSV Options](#csv-options))

**Returns**: New `DataFrame` instance

**Example**:

```javascript
const csv = `name,age,score
Alice,30,95.5
Bob,25,87.3
Charlie,35,91.0`;

const df = rozes.DataFrame.fromCSV(csv);
console.log(df.shape); // { rows: 3, cols: 3 }
```

**Performance**: Parses 1M rows in ~570ms (1.75M rows/sec)

---

### `DataFrame.fromCSVFile(filePath: string, options?: CSVOptions): DataFrame`

Load CSV from file (Node.js only).

**Parameters**:
- `filePath`: Path to CSV file (absolute or relative)
- `options` (optional): Parsing options (see [CSV Options](#csv-options))

**Returns**: New `DataFrame` instance

**Example**:

```javascript
const df = rozes.DataFrame.fromCSVFile('data.csv');
console.log(`Loaded ${df.shape.rows} rows`);
df.free();
```

**Notes**:
- File is read synchronously (async version planned for 1.1.0)
- Works with relative and absolute paths
- Supports large files (tested up to 1M rows)

---

## DataFrame Properties

### `df.shape: DataFrameShape`

Get DataFrame dimensions.

```javascript
const df = rozes.DataFrame.fromCSV(csvText);
console.log(df.shape); // { rows: 1000, cols: 5 }
```

**Type**:
```typescript
interface DataFrameShape {
  rows: number; // Number of rows
  cols: number; // Number of columns
}
```

---

### `df.columns: string[]`

Get column names.

```javascript
const df = rozes.DataFrame.fromCSV(csvText);
console.log(df.columns); // ['name', 'age', 'score']
```

**Returns**: Array of column names in order

---

### `df.length: number`

Get number of rows (same as `df.shape.rows`).

```javascript
const df = rozes.DataFrame.fromCSV(csvText);
console.log(df.length); // 1000
```

---

## DataFrame Methods

### `df.column(name: string): TypedArray | null`

Get column data as typed array (zero-copy access).

**Parameters**:
- `name`: Column name

**Returns**:
- `Float64Array` for Float64 columns
- `Int32Array` for Int32 columns
- `BigInt64Array` for Int64 columns
- `null` if column not found

**Example**:

```javascript
const df = rozes.DataFrame.fromCSV(csvText);

// Numeric columns
const ages = df.column('age'); // Float64Array
const ids = df.column('id');   // BigInt64Array

// Check if column exists
if (ages) {
  const avgAge = ages.reduce((a, b) => a + b) / ages.length;
  console.log(`Average age: ${avgAge}`);
}

// Handle BigInt columns
if (ids) {
  for (const id of ids) {
    console.log(Number(id)); // Convert BigInt to Number if needed
  }
}
```

**Performance**: Zero-copy access - no data copying, just TypedArray view

**Notes**:
- Returns reference to internal data (modifications affect DataFrame)
- String columns not yet supported in 1.0.0 (planned for 1.1.0)
- Boolean columns not yet supported in 1.0.0 (planned for 1.1.0)

---

### `df.free(): void`

Release DataFrame memory.

**IMPORTANT**: You **must** call `free()` when done with a DataFrame to release WebAssembly memory. JavaScript garbage collection does not automatically free WASM memory.

**Example**:

```javascript
const df = rozes.DataFrame.fromCSV(csvText);
// ... use df
df.free(); // Release memory
```

**Best Practice**: Use try/finally for guaranteed cleanup

```javascript
const df = rozes.DataFrame.fromCSV(csvText);
try {
  // Use df
  const ages = df.column('age');
  console.log(ages);
} finally {
  df.free(); // Always runs, even if error
}
```

---

## CSV Options

Configure CSV parsing behavior:

```typescript
interface CSVOptions {
  delimiter?: string;           // Field delimiter (default: ',')
  has_headers?: boolean;        // First row contains headers (default: true)
  skip_blank_lines?: boolean;   // Skip blank lines (default: true)
  trim_whitespace?: boolean;    // Trim whitespace from fields (default: false)
}
```

### Examples

**Tab-separated values (TSV)**:

```javascript
const tsv = "name\tage\tscorer\nAlice\t30\t95.5";
const df = rozes.DataFrame.fromCSV(tsv, { delimiter: '\t' });
```

**No headers**:

```javascript
const noHeaders = "30,95.5\n25,87.3";
const df = rozes.DataFrame.fromCSV(noHeaders, { has_headers: false });
console.log(df.columns); // ['column_0', 'column_1']
```

**Trim whitespace**:

```javascript
const csv = "name, age, score\nAlice , 30 , 95.5";
const df = rozes.DataFrame.fromCSV(csv, { trim_whitespace: true });
// Fields trimmed: "Alice ", " 30 " → "Alice", "30"
```

**Custom delimiter**:

```javascript
const pipeSeparated = "name|age|score\nAlice|30|95.5";
const df = rozes.DataFrame.fromCSV(pipeSeparated, { delimiter: '|' });
```

---

## TypeScript Types

Full TypeScript support with autocomplete:

### Rozes Class

```typescript
class Rozes {
  static init(wasmPath?: string): Promise<Rozes>;
  readonly DataFrame: typeof DataFrame;
  readonly version: string;
}
```

### DataFrame Class

```typescript
class DataFrame {
  static fromCSV(csvText: string, options?: CSVOptions): DataFrame;
  static fromCSVFile(filePath: string, options?: CSVOptions): DataFrame;

  readonly shape: DataFrameShape;
  readonly columns: string[];
  readonly length: number;

  column(name: string): Float64Array | Int32Array | BigInt64Array | null;
  free(): void;
}
```

### Interfaces

```typescript
interface CSVOptions {
  delimiter?: string;
  has_headers?: boolean;
  skip_blank_lines?: boolean;
  trim_whitespace?: boolean;
}

interface DataFrameShape {
  rows: number;
  cols: number;
}
```

### Error Types

```typescript
enum ErrorCode {
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

class RozesError extends Error {
  readonly code: ErrorCode;
}
```

---

## Error Handling

All operations can throw `RozesError`:

```javascript
const { Rozes, RozesError, ErrorCode } = require('rozes');

try {
  const rozes = await Rozes.init();
  const df = rozes.DataFrame.fromCSV(malformedCSV);
  df.free();
} catch (err) {
  if (err instanceof RozesError) {
    console.error(`Rozes error ${err.code}: ${err.message}`);

    switch (err.code) {
      case ErrorCode.InvalidFormat:
        console.error('CSV format is invalid');
        break;
      case ErrorCode.OutOfMemory:
        console.error('Out of memory');
        break;
      default:
        console.error('Unknown error');
    }
  } else {
    console.error('Unexpected error:', err);
  }
}
```

**Common Errors**:
- `InvalidFormat` (-2): Malformed CSV
- `OutOfMemory` (-1): Allocation failed
- `ColumnNotFound` (-4): Column name doesn't exist
- `TypeMismatch` (-5): Incompatible types

---

## Memory Management

### Why Manual Memory Management?

Rozes uses WebAssembly, which has separate memory from JavaScript. You must explicitly call `df.free()` to release WASM memory.

### Best Practices

**1. Always use try/finally**:

```javascript
const df = rozes.DataFrame.fromCSV(csvText);
try {
  // Use df
  const result = processData(df);
  return result;
} finally {
  df.free(); // Always runs
}
```

**2. Free DataFrames in reverse order**:

```javascript
const df1 = rozes.DataFrame.fromCSV(csv1);
const df2 = rozes.DataFrame.fromCSV(csv2);

try {
  // Use df1, df2
} finally {
  df2.free(); // Free in reverse order
  df1.free();
}
```

**3. Extract data before freeing**:

```javascript
const df = rozes.DataFrame.fromCSV(csvText);
const ages = df.column('age');

// Copy if you need to keep data after free
const agesCopy = new Float64Array(ages);

df.free(); // Safe - agesCopy is independent

console.log(agesCopy); // Still works
```

**4. Don't use after free**:

```javascript
const df = rozes.DataFrame.fromCSV(csvText);
df.free();

// ❌ BAD - df is invalid after free
console.log(df.shape); // May crash or return garbage
```

---

## Performance Tips

### 1. Zero-Copy Access

Use `column()` for maximum performance:

```javascript
const df = rozes.DataFrame.fromCSV(csvText);

// ✅ FAST - Zero-copy TypedArray access
const ages = df.column('age'); // Direct memory view
const sum = ages.reduce((a, b) => a + b, 0);

// ❌ SLOW - Would require serialization
// (Not available in 1.0.0 anyway)
```

### 2. Batch Operations

Process data in bulk:

```javascript
const df = rozes.DataFrame.fromCSV(largeCSV);

// ✅ FAST - Single TypedArray access
const prices = df.column('price');
const quantities = df.column('quantity');

let total = 0;
for (let i = 0; i < prices.length; i++) {
  total += prices[i] * Number(quantities[i]);
}

df.free();
```

### 3. Reuse Rozes Instance

Initialize once, use many times:

```javascript
// ✅ GOOD - Initialize once
const rozes = await Rozes.init();

function processFile(path) {
  const df = rozes.DataFrame.fromCSVFile(path);
  // ... process
  df.free();
}

// ❌ BAD - Re-initializing is wasteful
async function processFile(path) {
  const rozes = await Rozes.init(); // Loads WASM every time
  // ...
}
```

### 4. Large Files

For large files, consider chunking (stream API coming in 1.1.0):

```javascript
// Current: Load entire file at once
const df = rozes.DataFrame.fromCSVFile('large.csv'); // ~570ms for 1M rows

// Future (1.1.0): Stream processing
// const stream = rozes.DataFrame.fromCSVStream('large.csv', { chunkSize: 10000 });
```

---

## Complete Examples

### Basic Usage

```javascript
const { Rozes } = require('rozes');

async function main() {
  const rozes = await Rozes.init();

  const csv = `name,age,score
Alice,30,95.5
Bob,25,87.3
Charlie,35,91.0`;

  const df = rozes.DataFrame.fromCSV(csv);

  console.log(df.shape); // { rows: 3, cols: 3 }
  console.log(df.columns); // ['name', 'age', 'score']

  const ages = df.column('age');
  console.log(Array.from(ages)); // [30, 25, 35]

  df.free();
}

main();
```

### File I/O

```javascript
const { Rozes } = require('rozes');
const fs = require('fs');

async function main() {
  const rozes = await Rozes.init();

  // Load from file
  const df = rozes.DataFrame.fromCSVFile('data.csv');

  // Access data
  const prices = df.column('price');
  const quantities = df.column('quantity');

  // Calculate total value
  let totalValue = 0;
  for (let i = 0; i < prices.length; i++) {
    totalValue += prices[i] * Number(quantities[i]);
  }

  console.log(`Total: $${totalValue.toFixed(2)}`);

  df.free();
}

main();
```

### Error Handling

```javascript
const { Rozes, RozesError, ErrorCode } = require('rozes');

async function safeParseCSV(csvText) {
  const rozes = await Rozes.init();

  try {
    const df = rozes.DataFrame.fromCSV(csvText);

    // Process data
    const result = {
      rows: df.shape.rows,
      cols: df.shape.cols,
      columns: df.columns
    };

    df.free();
    return { success: true, data: result };

  } catch (err) {
    if (err instanceof RozesError) {
      return {
        success: false,
        error: {
          code: err.code,
          message: err.message
        }
      };
    }
    throw err; // Re-throw unexpected errors
  }
}
```

### TypeScript

```typescript
import { Rozes, DataFrame, CSVOptions, DataFrameShape } from 'rozes';

async function analyzeCSV(filePath: string): Promise<DataFrameShape> {
  const rozes: Rozes = await Rozes.init();

  const options: CSVOptions = {
    delimiter: ',',
    has_headers: true,
    trim_whitespace: true
  };

  const df: DataFrame = rozes.DataFrame.fromCSVFile(filePath, options);

  try {
    const shape: DataFrameShape = df.shape;

    // TypeScript knows column() can return null
    const ages = df.column('age');
    if (ages) {
      const avgAge = ages.reduce((a, b) => a + b) / ages.length;
      console.log(`Average age: ${avgAge}`);
    }

    return shape;
  } finally {
    df.free();
  }
}
```

---

## Known Limitations (1.0.0)

**Features Deferred to 1.1.0**:
- CSV export (`toCSV()`, `toCSVFile()`) - WASM export not yet implemented
- String column access - only numeric columns via `column()`
- Boolean column access - only numeric columns via `column()`
- DataFrame operations (filter, select, sort, etc.) - Use Zig API for now
- Stream API for large files (>1GB)

**Workarounds**:
- For string data: Use Zig API (see [ZIG_API.md](./ZIG_API.md))
- For DataFrame operations: Use Zig API or wait for 1.1.0
- For CSV export: Manually reconstruct from column data

---

## Next Steps

- **Migration Guide**: See [MIGRATION.md](./MIGRATION.md) for migrating from Papa Parse, csv-parse, Danfo.js
- **Zig API**: See [ZIG_API.md](./ZIG_API.md) for full DataFrame operations
- **Performance**: See [BENCHMARK_BASELINE_REPORT.md](./BENCHMARK_BASELINE_REPORT.md) for detailed benchmarks
- **Examples**: Browse `examples/node/` directory

---

**Version**: 1.0.0
**Last Updated**: 2025-10-31
**License**: MIT
