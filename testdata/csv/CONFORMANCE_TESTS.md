# CSV Conformance Test Suite

**Purpose**: Validate RFC 4180 compliance and handle edge cases for the Rozes CSV parser

**Test Suite Version**: 1.0
**Last Updated**: 2025-10-27

---

## Test Categories

### 1. RFC 4180 Compliance Tests (`rfc4180/`)

These tests validate strict compliance with [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180).

| Test File | Description | Expected Behavior |
|-----------|-------------|-------------------|
| `01_simple.csv` | Basic CSV with headers, no quotes | Parse 3 rows × 3 columns, infer types |
| `02_quoted_fields.csv` | Fields enclosed in quotes | Handle quoted strings correctly |
| `03_embedded_commas.csv` | Commas inside quoted fields | Parse commas as data, not delimiters |
| `04_embedded_newlines.csv` | Newlines inside quoted fields | Parse multi-line fields correctly |
| `05_escaped_quotes.csv` | Double-quote escape (`""`) | Convert `""` to `"` in output |
| `06_crlf_endings.csv` | CRLF line endings (`\r\n`) | Handle both CRLF and LF |
| `07_empty_fields.csv` | Empty/missing values | Represent as null or empty string |
| `08_no_header.csv` | CSV without header row | Generate column names (col0, col1, ...) |
| `09_trailing_comma.csv` | Trailing comma creates empty column | Add empty 4th column |
| `10_unicode_content.csv` | UTF-8 characters (emoji, CJK) | Preserve Unicode correctly |

**Expected Results** (sample for `01_simple.csv`):
```json
{
  "columns": ["name", "age", "city"],
  "types": ["String", "Int64", "String"],
  "rowCount": 3,
  "data": {
    "name": ["Alice", "Bob", "Charlie"],
    "age": [30, 25, 35],
    "city": ["New York", "Los Angeles", "Chicago"]
  }
}
```

---

### 2. Edge Cases (`edge_cases/`)

Tests for uncommon but valid scenarios.

| Test File | Description | Expected Behavior |
|-----------|-------------|-------------------|
| `01_single_column.csv` | Only one column | Valid DataFrame with 1 column |
| `02_single_row.csv` | Only header + 1 data row | Valid DataFrame with 1 row |
| `03_blank_lines.csv` | Blank lines between rows | Skip blank lines if `skipBlankLines=true` |
| `04_mixed_types.csv` | Multiple data types per column | Infer correct types (int, float, bool, string) |
| `05_special_characters.csv` | Special symbols, unicode math | Preserve all characters |
| `06_very_long_field.csv` | Field >500 characters | Handle without truncation |
| `07_numbers_as_strings.csv` | Numeric-looking strings (zip codes) | Preserve as strings (leading zeros) |

**Expected Results** (sample for `04_mixed_types.csv`):
```json
{
  "types": {
    "id": "Int64",
    "name": "String",
    "score": "Float64",
    "is_active": "Bool",
    "price": "Float64",
    "date": "String"
  }
}
```

---

### 3. Malformed/Invalid CSVs (`malformed/`)

Tests for graceful error handling.

| Test File | Description | Expected Behavior (Strict Mode) | Expected Behavior (Lenient Mode) |
|-----------|-------------|---------------------------------|----------------------------------|
| `01_unmatched_quote.csv` | Opening quote without closing | `Error: UnexpectedEndOfFile` | Skip row, log error |
| `02_column_mismatch.csv` | Varying column counts per row | `Error: ColumnCountMismatch` | Use max columns, fill with nulls |
| `03_invalid_utf8.csv` | Invalid UTF-8 byte sequences | `Error: InvalidEncoding` | Replace with � (U+FFFD) |
| `04_mixed_line_endings.csv` | CR, LF, CRLF mixed | Parse correctly (auto-detect) | Parse correctly |
| `05_tab_delimiter.csv` | Tab-separated instead of comma | Fail unless delimiter='\t' | Auto-detect delimiter |

**To Create**: Add these malformed test files with expected error messages.

---

### 4. Large Files (`large/`)

Performance and stress tests.

| Test File | Size | Rows | Columns | Description |
|-----------|------|------|---------|-------------|
| `100k_rows.csv` | ~10MB | 100,000 | 10 | Medium dataset |
| `1m_rows.csv` | ~100MB | 1,000,000 | 10 | Large dataset |
| `wide_100cols.csv` | ~50MB | 10,000 | 100 | Many columns |
| `string_heavy.csv` | ~50MB | 100,000 | 5 | Long string fields |

**Performance Targets**:
- `100k_rows.csv`: Parse in <500ms (browser), <200ms (Node)
- `1m_rows.csv`: Parse in <3s (browser), <1s (Node)
- `wide_100cols.csv`: Parse in <1s (browser)
- `string_heavy.csv`: Parse in <1s (browser)

**Memory Targets**:
- Peak memory < 2× file size for numeric data
- Peak memory < 3× file size for string-heavy data

---

## Type Inference Test Cases

### Integer Detection
```csv
id,count,year
1,100,2024
2,200,2023
3,300,2022
```
**Expected**: All three columns as `Int64`

### Float Detection
```csv
price,weight,ratio
19.99,1.5,0.75
29.99,2.3,0.85
```
**Expected**: All columns as `Float64`

### Boolean Detection
```csv
is_active,has_discount
true,false
false,true
TRUE,FALSE
```
**Expected**: Both columns as `Bool` (case-insensitive)

### Mixed Type (Fallback to String)
```csv
value
123
45.6
hello
true
```
**Expected**: Column as `String` (mixed types)

---

## BOM (Byte Order Mark) Tests

### UTF-8 BOM
```
File hex: EF BB BF 6E 61 6D 65 2C ...
         (UTF-8 BOM) (n a m e ,)
```
**Expected**: Detect and strip BOM, parse normally

### UTF-16LE BOM
```
File hex: FF FE 6E 00 61 00 6D 00 ...
         (UTF-16LE BOM) (n a m e)
```
**Expected**: Detect encoding, transcode to UTF-8, parse

### No BOM
```
File hex: 6E 61 6D 65 2C ...
         (n a m e ,)
```
**Expected**: Assume UTF-8, parse normally

---

## Delimiter Auto-Detection Tests

### Common Delimiters
- `,` (comma) - default
- `;` (semicolon) - European CSV
- `\t` (tab) - TSV
- `|` (pipe) - database exports

**Algorithm**:
1. Read first 5 rows
2. Count occurrences of each delimiter
3. Choose delimiter with most consistent count per row
4. Fallback to `,` if ambiguous

**Test Cases**:
```csv
# Comma (default)
a,b,c
1,2,3

# Semicolon
a;b;c
1;2;3

# Tab
a\tb\tc
1\t2\t3

# Pipe
a|b|c
1|2|3
```

---

## CSV Options Test Matrix

| Option | Value | Test File | Expected Behavior |
|--------|-------|-----------|-------------------|
| `delimiter` | `,` | All | Standard parsing |
| `delimiter` | `;` | `semicolon.csv` | Parse semicolon-separated |
| `delimiter` | `\t` | `tab.csv` | Parse TSV |
| `hasHeaders` | `true` | Standard files | Use first row as column names |
| `hasHeaders` | `false` | `08_no_header.csv` | Generate col0, col1, ... |
| `skipBlankLines` | `true` | `03_blank_lines.csv` | Skip empty rows |
| `skipBlankLines` | `false` | `03_blank_lines.csv` | Include as rows with nulls |
| `trimWhitespace` | `true` | `whitespace.csv` | Trim leading/trailing spaces |
| `trimWhitespace` | `false` | `whitespace.csv` | Preserve spaces |
| `inferTypes` | `true` | `04_mixed_types.csv` | Auto-detect types |
| `inferTypes` | `false` | `04_mixed_types.csv` | All columns as String |

---

## Browser-Specific Tests

### Web Worker Integration
- Load CSV in Web Worker (non-blocking)
- Transfer DataFrame back to main thread
- Validate zero-copy TypedArray access

### Memory Management
- Parse large file, measure peak memory
- Free DataFrame, validate memory released
- Repeated parse/free cycles (no leak)

### Blob/File API
- Parse from `File` object (user upload)
- Parse from `Blob` (fetch response)
- Stream large file in chunks

---

## Conformance Test Suite Sources

### External Test Suites to Integrate

1. **csv-spectrum** (MIT License)
   - URL: https://github.com/maxogden/csv-spectrum
   - Tests: 15 CSV edge cases
   - Download: `git clone https://github.com/maxogden/csv-spectrum.git testdata/external/csv-spectrum`

2. **uniVocity CSV Parser Tests**
   - URL: https://github.com/uniVocity/csv-parsers-comparison
   - Tests: 50+ real-world CSV files
   - Download: Manual selection from `/src/main/resources/`

3. **Papa Parse Test Suite**
   - URL: https://github.com/mholt/PapaParse
   - Tests: `tests/test-cases.js` (100+ unit tests)
   - Extract: Convert JS test cases to CSV fixtures

### Real-World Dataset Sources

1. **NYC Taxi Dataset** (sample)
   - URL: https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page
   - Use: January 2024 Yellow Taxi data (~2.9M rows)

2. **Kaggle Datasets** (CC0/Public Domain)
   - URL: https://www.kaggle.com/datasets
   - Examples: Stack Overflow posts, COVID-19 data

3. **data.gov** (US Government Open Data)
   - URL: https://data.gov
   - Various CSV datasets for testing

---

## Test Automation

### Zig Unit Tests
```zig
// test/unit/csv/conformance_test.zig
test "RFC 4180: simple CSV" {
    const csv = @embedFile("../../testdata/csv/rfc4180/01_simple.csv");
    const df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
    defer df.free();

    try testing.expectEqual(@as(u32, 3), df.rowCount);
    try testing.expectEqual(@as(u32, 3), df.columns.len);
    try testing.expectEqualStrings("name", df.columns[0].name);
}
```

### Browser Test Runner
```javascript
// test/browser/conformance.js
const tests = [
  { file: 'rfc4180/01_simple.csv', expected: { rows: 3, cols: 3 } },
  { file: 'rfc4180/02_quoted_fields.csv', expected: { rows: 3, cols: 3 } },
  // ... all tests
];

for (const test of tests) {
  const csv = await fetch(`/testdata/csv/${test.file}`).then(r => r.text());
  const df = await DataFrame.fromCSV(csv);
  assert.equal(df.rowCount, test.expected.rows);
  assert.equal(df.columns.length, test.expected.cols);
}
```

---

## Success Criteria

### Conformance
- ✅ 100% pass rate on RFC 4180 tests (10/10)
- ✅ 100% pass rate on edge cases (7/7)
- ✅ Graceful failure on malformed CSVs (no crashes)

### Performance
- ✅ Parse 1M rows in <3s (browser)
- ✅ Peak memory <2× file size (numeric data)
- ✅ No memory leaks (1000 parse/free cycles)

### Compatibility
- ✅ Chrome 90+, Firefox 88+, Safari 14+
- ✅ Match Papa Parse behavior on ambiguous cases
- ✅ Support all common CSV dialects

---

## Next Steps

1. Generate large test files programmatically
2. Create malformed CSV test files
3. Implement browser test runner HTML page
4. Integrate external test suites
5. Set up automated conformance CI pipeline

---

**References**:
- [RFC 4180 Specification](https://www.rfc-editor.org/rfc/rfc4180)
- [CSV Spectrum Tests](https://github.com/maxogden/csv-spectrum)
- [Papa Parse Tests](https://github.com/mholt/PapaParse/tree/master/tests)
