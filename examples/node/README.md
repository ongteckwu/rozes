# Rozes Node.js Examples

This directory contains example programs demonstrating how to use Rozes in Node.js.

## Prerequisites

1. Build the WASM module:
   ```bash
   cd /Users/ongteckwu/rozes
   zig build
   ```

2. The WASM file should be at `zig-out/bin/rozes.wasm`

## Running Examples

### Basic Example

Demonstrates basic DataFrame operations:

```bash
node examples/node/basic.js
```

**What it does:**
- Parses a CSV string
- Accesses column data
- Displays DataFrame information

### File I/O Example

Demonstrates reading and writing CSV files:

```bash
node examples/node/file-io.js
```

**What it does:**
- Writes a CSV file
- Loads it using `DataFrame.fromCSVFile()`
- Performs calculations on the data
- Writes output using `toCSVFile()`

## Using Rozes in Your Project

### Installation (once published to npm)

```bash
npm install rozes
```

### CommonJS

```javascript
const { Rozes } = require('rozes');

async function main() {
  const rozes = await Rozes.init();
  const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n25,87.3");

  console.log(df.shape); // { rows: 2, cols: 2 }
  df.free();
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

console.log(df.shape); // { rows: 2, cols: 2 }
df.free();
```

## API Reference

See the full API documentation at `docs/API.md`.

## Performance

Rozes is **3-10× faster** than popular JavaScript CSV libraries:
- vs Papa Parse: 3.67× faster on 100K rows
- vs csv-parse: 7.55× faster on 100K rows

See `docs/BENCHMARK_BASELINE_REPORT.md` for detailed benchmarks.
