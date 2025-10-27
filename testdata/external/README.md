# External Conformance Test Suites

This directory contains official CSV conformance test suites from external sources.

## Test Suites

### 1. csv-spectrum (MIT License)

**Source**: https://github.com/maxogden/csv-spectrum
**Tests**: 15 CSV edge cases with expected JSON outputs
**Location**: `csv-spectrum/`

Tests include:
- Empty fields
- Escaped quotes
- JSON data in CSV
- Newlines in quoted fields
- Quotes and newlines
- Simple CSV
- UTF-8 encoding

**Usage**:
```bash
# Run csv-spectrum conformance tests
cd csv-spectrum
ls *.csv | while read file; do
    echo "Testing: $file"
    # Parse CSV and compare with expected JSON
done
```

### 2. Papa Parse Tests

**Source**: https://github.com/mholt/PapaParse
**Tests**: 100+ unit test cases
**Location**: `PapaParse/tests/`

**Usage**:
Extract test cases from `test-cases.js` and convert to CSV fixtures.

### 3. uniVocity CSV Parser Comparison

**Source**: https://github.com/uniVocity/csv-parsers-comparison
**Tests**: 50+ real-world CSV files
**Location**: `csv-parsers-comparison/src/main/resources/`

**Usage**:
Use CSV files from `src/main/resources/` for edge case testing.

## Integration with Rozes

### Automated Testing

Create a Zig test that runs all external conformance tests:

```zig
// test/unit/csv/external_conformance_test.zig

test "csv-spectrum conformance" {
    const test_dir = "testdata/external/csv-spectrum/";
    var dir = try std.fs.cwd().openIterableDir(test_dir, .{});
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".csv")) continue;

        const csv_path = try std.fmt.allocPrint(
            allocator,
            "{s}{s}",
            .{ test_dir, entry.name }
        );
        defer allocator.free(csv_path);

        // Load CSV
        const csv_data = try std.fs.cwd().readFileAlloc(
            allocator,
            csv_path,
            1024 * 1024
        );
        defer allocator.free(csv_data);

        // Parse with Rozes
        const df = try DataFrame.fromCSVBuffer(allocator, csv_data, .{});
        defer df.free();

        // Load expected JSON
        const json_path = try std.fmt.allocPrint(
            allocator,
            "{s}{s}.json",
            .{ test_dir, entry.name[0..entry.name.len - 4] }
        );
        defer allocator.free(json_path);

        // Compare results
        // ... validation logic ...
    }
}
```

### Browser Testing

Update `test/browser/tests.js` to include external tests:

```javascript
// Add csv-spectrum tests
const csvSpectrumTests = await loadCsvSpectrumTests();
testSuites.csvSpectrum = {
    name: 'CSV Spectrum (External)',
    description: 'Official CSV edge case tests',
    tests: csvSpectrumTests
};
```

## License Compliance

All test suites are under permissive licenses (MIT):
- ✅ csv-spectrum: MIT License
- ✅ Papa Parse: MIT License
- ✅ uniVocity: Apache License 2.0

Ensure attribution when using these tests in documentation.

## Updating Test Suites

To update to the latest versions:

```bash
cd testdata/external/csv-spectrum
git pull origin master

cd ../PapaParse
git pull origin master

cd ../csv-parsers-comparison
git pull origin master
```

---

**Last Updated**: 2025-10-27
