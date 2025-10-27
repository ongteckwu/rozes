# Rozes Browser Test Suite

**Purpose**: Interactive browser-based conformance and performance testing for the Rozes DataFrame library.

---

## Quick Start

1. **Build the WASM module** (when implementation is ready):
   ```bash
   zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall
   ```

2. **Start a local server**:
   ```bash
   # From project root
   python3 -m http.server 8080

   # Or use Node.js
   npx http-server -p 8080
   ```

3. **Open the test suite**:
   ```
   http://localhost:8080/test/browser/
   ```

4. **Run tests**:
   - Click "▶ Run All Tests" to execute the full suite
   - Or run individual test categories
   - View real-time results and console output

---

## Test Categories

### 1. RFC 4180 Compliance (10 tests)

Validates strict compliance with the CSV specification:

- ✅ Basic CSV parsing
- ✅ Quoted fields with embedded commas
- ✅ Quoted fields with embedded newlines
- ✅ Double-quote escaping (`""` → `"`)
- ✅ CRLF and LF line endings
- ✅ Empty/null fields
- ✅ No header row handling
- ✅ Trailing commas
- ✅ Unicode content (emoji, CJK, Arabic)

### 2. Edge Cases (7 tests)

Tests for uncommon but valid scenarios:

- Single column/row CSVs
- Blank lines (with skip option)
- Mixed data types (int, float, bool, string)
- Special characters and symbols
- Very long fields (>500 chars)
- Numbers as strings (zip codes with leading zeros)

### 3. Performance Benchmarks

Measures parsing speed and throughput:

- Small: 1K rows × 10 columns
- Medium: 10K rows × 10 columns
- Large: 100K rows × 10 columns

**Target Performance**:
- 1M rows in <3 seconds (browser)
- Throughput: >300K cells/second
- Memory: <2× raw CSV size

---

## Test Data Structure

```
testdata/csv/
├── rfc4180/           # RFC 4180 compliance tests
│   ├── 01_simple.csv
│   ├── 02_quoted_fields.csv
│   ├── 03_embedded_commas.csv
│   ├── 04_embedded_newlines.csv
│   ├── 05_escaped_quotes.csv
│   ├── 06_crlf_endings.csv
│   ├── 07_empty_fields.csv
│   ├── 08_no_header.csv
│   ├── 09_trailing_comma.csv
│   └── 10_unicode_content.csv
├── edge_cases/        # Edge case tests
│   ├── 01_single_column.csv
│   ├── 02_single_row.csv
│   ├── 03_blank_lines.csv
│   ├── 04_mixed_types.csv
│   ├── 05_special_characters.csv
│   ├── 06_very_long_field.csv
│   └── 07_numbers_as_strings.csv
└── CONFORMANCE_TESTS.md  # Detailed test specifications
```

---

## Features

### Interactive UI
- **Real-time progress**: See tests executing live
- **Visual results**: Color-coded pass/fail indicators
- **Console output**: Detailed logging of test execution
- **Filtering**: View all tests, passed only, or failed only

### Test Controls
- **Run All**: Execute complete test suite
- **RFC 4180 Only**: Run compliance tests
- **Edge Cases Only**: Run edge case tests
- **Benchmark**: Run performance tests
- **Clear**: Reset all results

### Statistics Dashboard
- Total tests executed
- Pass/fail counts
- Execution duration
- Progress bar

---

## Expected Results

All test expectations are documented in:
- `expected/rfc4180_results.json` - Detailed expected outputs
- `../../testdata/csv/CONFORMANCE_TESTS.md` - Test specifications

### Success Criteria

**Conformance**:
- ✅ 100% pass on RFC 4180 tests (10/10)
- ✅ 100% pass on edge cases (7/7)
- ✅ No crashes or memory errors

**Performance**:
- ✅ Parse 100K rows in <1 second
- ✅ Parse 1M rows in <3 seconds
- ✅ Memory usage <2× CSV size (numeric data)

---

## Browser Compatibility

### Tier 1 (Fully Tested)
- ✅ Chrome 90+ (V8)
- ✅ Firefox 88+ (SpiderMonkey)
- ✅ Safari 14+ (JavaScriptCore)
- ✅ Edge 90+ (Chromium)

### Tier 2 (Manual Testing)
- Chrome Android 90+
- Safari iOS 14+
- Samsung Internet 14+

### Not Supported
- ❌ Internet Explorer (no WebAssembly)
- ❌ Opera Mini (no WebAssembly)

---

## Adding New Tests

### 1. Create Test Data File

Add a new CSV file to the appropriate directory:

```bash
# For RFC 4180 compliance
testdata/csv/rfc4180/11_new_test.csv

# For edge cases
testdata/csv/edge_cases/08_new_edge_case.csv
```

### 2. Update Test Suite

Edit `tests.js` and add the test definition:

```javascript
testSuites.rfc4180.tests.push({
    file: 'rfc4180/11_new_test.csv',
    name: 'New test case',
    description: 'Description of what this tests',
    expected: {
        rowCount: 5,
        columnCount: 3,
        validate: (df) => {
            // Custom validation logic
            return true;
        }
    }
});
```

### 3. Document Expected Results

Update `expected/rfc4180_results.json`:

```json
{
  "11_new_test.csv": {
    "rowCount": 5,
    "columnCount": 3,
    "notes": "Description of expected behavior"
  }
}
```

---

## Integrating Rozes WASM Module

**Current Status**: The test suite uses a mock DataFrame implementation for demonstration.

**To integrate actual Rozes**:

1. **Build the WASM module**:
   ```bash
   zig build -Dtarget=wasm32-freestanding
   # Output: zig-out/lib/rozes.wasm
   ```

2. **Update `tests.js`**:
   ```javascript
   // Replace mock implementation
   import init, { DataFrame } from '../../zig-out/lib/rozes.js';

   // Initialize WASM
   await init();

   // Use real DataFrame
   const df = await DataFrame.fromCSV(csvText, options);
   ```

3. **Ensure WASM exports match API**:
   - `DataFrame.fromCSV(text, options)`
   - `df.rowCount`
   - `df.columnCount`
   - `df.columns`
   - `df.column(name).get(index)`

---

## Troubleshooting

### Tests not loading
- **Check server**: Ensure HTTP server is running
- **Check paths**: Verify CSV files exist in `testdata/csv/`
- **CORS errors**: Use a local server, not `file://` protocol

### WASM module fails to load
- **Build errors**: Check `zig build` output
- **Module path**: Verify WASM file location
- **Memory limits**: Increase WASM memory if needed

### Tests failing unexpectedly
- **Check browser console**: Look for JavaScript errors
- **Verify test data**: Ensure CSV files match expected format
- **Check encoding**: Files should be UTF-8

---

## Performance Testing

### Memory Profiling

Use browser DevTools:

1. Open Chrome DevTools → Memory
2. Take heap snapshot before tests
3. Run "Benchmark" tests
4. Take heap snapshot after tests
5. Compare memory usage

**Expected**:
- Minimal retained memory after tests
- No memory leaks on repeated runs
- Peak usage <2× CSV file size

### CPU Profiling

1. Open Chrome DevTools → Performance
2. Start recording
3. Run "Run All Tests"
4. Stop recording
5. Analyze flame graph

**Look for**:
- CSV parsing hot paths
- Type inference overhead
- Memory allocation patterns

---

## CI/CD Integration

### Headless Browser Testing

```bash
# Using Playwright
npx playwright test test/browser/playwright.spec.js

# Using Puppeteer
node test/browser/puppeteer-runner.js
```

### Automated Benchmarks

```bash
# Run benchmarks and save results
node test/browser/benchmark-runner.js > benchmarks.json

# Compare with baseline
node scripts/compare-benchmarks.js benchmarks.json baseline.json
```

---

## Contributing

When adding tests:

1. Follow RFC 4180 specification strictly
2. Document expected behavior clearly
3. Include edge cases for new features
4. Add performance benchmarks for large datasets
5. Test across all supported browsers

---

## Resources

- [RFC 4180 Specification](https://www.rfc-editor.org/rfc/rfc4180)
- [CSV Test Spectrum](https://github.com/maxogden/csv-spectrum)
- [Papa Parse Tests](https://github.com/mholt/PapaParse/tree/master/tests)
- [Rozes RFC](../../RFC.md)

---

**Last Updated**: 2025-10-27
**Test Suite Version**: 1.0
**Rozes Version**: 0.1.0 (MVP)
