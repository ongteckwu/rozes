# Rozes - High-Performance DataFrame Library for the Web

**Project**: Rozes - A high-performance DataFrame library with CSV focus
**Language**: Zig (0.15+)
**Targets**: Browser (WebAssembly), Node.js (native addon or Wasm)
**Status**: Initial Development Phase

---

## Project Overview

Rozes is a DataFrame library written in Zig that provides:

- **Near-Native Performance**: Optimized for web and server environments
- **CSV First**: Highly-optimized CSV parsing and export as priority
- **Columnar Memory Layout**: Efficient data operations with minimal copying
- **Cross-Platform**: WebAssembly for browsers, native addons for Node.js
- **Type Safety**: Tiger Style methodology with extensive assertions and bounds checking
- **Zero-Copy Operations**: Efficient JS/Wasm memory bridging

---

## ⚠️ CRITICAL: Milestone Documentation Updates

**At EVERY milestone completion (0.1.0, 0.2.0, 1.0.0, 1.1.0, etc.), you MUST update:**

1. **docs/CHANGELOG.md**: Add new section with version number, date, and complete list of changes
   - **Format**: Point form (bullet points), NOT paragraphs
   - Keep it concise and scannable
2. **README.md**: Update version numbers, test counts, performance benchmarks, and feature lists

**Why this is critical:**
- Users rely on CHANGELOG.md for migration and version history
- README.md is the first impression - outdated stats hurt credibility
- Inconsistent documentation confuses contributors

**Example mistakes to avoid:**
- ❌ Claiming "428/430 tests passing" when actual is 461/463
- ❌ Showing outdated performance numbers (Filter: 10ms vs 21ms actual)
- ❌ Missing new features in the changelog

**Checklist for every milestone:**
- [ ] Update CHANGELOG.md with new version section
- [ ] Update README.md test count
- [ ] Update README.md performance benchmarks
- [ ] Update README.md feature list
- [ ] Verify all claims are accurate

---

## Documentation Map

### Core Documentation

1. **[README.md](./README.md)** - Getting started guide
2. **[CLAUDE.md](./CLAUDE.md)** - This file: Project guidelines, testing, and patterns
3. **[docs/RFC.md](./docs/RFC.md)** - Complete specification (RFC format)
4. **[docs/TODO.md](./docs/TODO.md)** - Detailed project roadmap and task tracking
5. **[docs/TIGER_STYLE_APPLICATION.md](./docs/TIGER_STYLE_APPLICATION.md)** - Tiger Style methodology applied to Rozes

### Implementation Guides

- **[src/CLAUDE.md](./src/CLAUDE.md)** - Source code organization and implementation patterns
- **docs/ARCHITECTURE.md** (to be created) - System design and module structure
- **docs/CONTRIBUTING.md** (to be created) - Development workflow and PR process

### Quality Assurance

- **docs/BENCHMARKING.md** (to be created) - Performance metrics and optimization
- **docs/TESTING_STRATEGY.md** (to be created) - Unit, integration, and benchmark testing

---

## Quick Reference

### For Implementation

👉 See **[src/CLAUDE.md](./src/CLAUDE.md)** for:

- Source code organization
- Zig implementation patterns
- Common code patterns
- Memory management strategies

### For Testing

👉 This document covers:

- Test organization and location
- Test patterns and templates
- Conformance test suites
- Browser testing

### For Development

👉 See **[docs/TODO.md](./docs/TODO.md)** for:

- Current milestone tasks
- Phase breakdown
- Acceptance criteria
- Development workflow

---

## Coding Standards

### Tiger Style for DataFrame Engine

**Core Principles:**

1. **Safety First**: 2+ assertions per function, bounded loops, explicit error handling
2. **Predictable Performance**: Static allocation, back-of-envelope calculations, batching
3. **Developer Experience**: ≤70 lines per function, descriptive names, 100-column limit
4. **Zero Dependencies**: Only Zig stdlib (no external dependencies)

**See [src/CLAUDE.md](./src/CLAUDE.md) for detailed implementation patterns**

### Project-Specific Standards

#### Type Conventions

```zig
// Use explicit types (not usize)
const row_index: u32 = 0;        // ✅ Consistent across platforms
const col_count: u32 = df.columns.len;  // ✅ 4GB limit is acceptable

// Avoid architecture-dependent sizes
const pos: usize = 0;         // ❌ Changes between 32/64 bit
```

#### Error Handling

```zig
// Always handle errors explicitly
const df = try DataFrame.fromCSVBuffer(allocator, buffer, opts); // ✅ Propagate
const result = DataFrame.fromCSVFile(allocator, path, opts) catch |err| {
    log.err("CSV parsing failed: {}", .{err});
    return error.InvalidCSV;
}; // ✅ Explicit handling

const ignored = DataFrame.create(allocator, cols, 0) catch unreachable; // ⚠️ Only with proof
const bad = parseCsv(buffer) catch null; // ❌ Never ignore silently
```

---

## File Organization

### Project Structure

```
rozes/
├── src/                       # Source code AND tests
│   ├── core/                  # DataFrame engine
│   ├── csv/                   # CSV parsing
│   ├── bindings/              # Wasm/Node bindings
│   ├── rozes.zig              # Main API
│   └── test/                  # ALL TESTS GO HERE
│       ├── unit/              # Zig unit tests
│       │   ├── core/          # Tests for src/core/
│       │   └── csv/           # Tests for src/csv/
│       ├── integration/       # Integration tests
│       ├── browser/           # Browser-specific tests
│       │   ├── index.html     # Interactive test runner
│       │   ├── tests.js       # Browser test suite
│       │   └── README.md      # Browser testing guide
│       └── benchmark/         # Performance benchmarks
│           ├── csv_parse.zig  # CSV parsing benchmarks
│           ├── operations.zig # DataFrame operation benchmarks
│           └── compare.js     # vs Papa Parse, etc.
├── testdata/                  # Test fixtures (NOT tests)
│   ├── csv/                   # CSV test files
│   │   ├── rfc4180/           # RFC 4180 compliance (10 files)
│   │   ├── edge_cases/        # Edge cases (7 files)
│   │   ├── large/             # Large files (100K, 1M rows)
│   │   └── malformed/         # Invalid CSVs
│   └── external/              # External test suites
│       ├── csv-spectrum/      # 15 official tests
│       ├── PapaParse/         # 100+ Papa Parse tests
│       └── csv-parsers-comparison/  # 50+ uniVocity tests
├── js/                        # JavaScript wrapper
├── scripts/                   # Build and utility scripts
└── docs/                      # Documentation (future)
```

### Key Principles

1. **All tests go in `src/test/`** - Tests live alongside source code
2. **Test data goes in `testdata/`** - Separate from test code
3. **One test file per source file** - Mirror source structure
4. **Browser tests in `src/test/browser/`** - Separate from Zig tests

---

## Testing Infrastructure

### Test Organization

#### Unit Tests (`src/test/unit/`)

**Location**: Mirror source structure

```
src/test/unit/
├── core/
│   ├── types_test.zig          # Tests for src/core/types.zig
│   ├── series_test.zig         # Tests for src/core/series.zig
│   ├── dataframe_test.zig      # Tests for src/core/dataframe.zig
│   └── operations_test.zig     # Tests for src/core/operations.zig
└── csv/
    ├── parser_test.zig         # Tests for src/csv/parser.zig
    ├── export_test.zig         # Tests for src/csv/export.zig
    ├── inference_test.zig      # Tests for src/csv/inference.zig
    ├── bom_test.zig            # Tests for src/csv/bom.zig
    └── conformance_test.zig    # RFC 4180 conformance tests
```

**Naming Convention**:

- Source file: `src/core/series.zig`
- Test file: `src/test/unit/core/series_test.zig`

**Import Pattern**:

```zig
// src/test/unit/core/series_test.zig
const std = @import("std");
const testing = std.testing;
const Series = @import("../../../core/series.zig").Series;

test "Series.len returns correct length" {
    // Test implementation
}
```

#### Integration Tests (`src/test/integration/`)

**Purpose**: Test multiple modules working together

```
src/test/integration/
├── csv_to_dataframe_test.zig   # CSV → DataFrame flow
├── dataframe_ops_test.zig      # Chained DataFrame operations
└── wasm_bindings_test.zig      # Wasm ↔ JS integration
```

**Example**:

```zig
// src/test/integration/csv_to_dataframe_test.zig
test "CSV parse → filter → export round-trip" {
    const allocator = testing.allocator;

    // Parse CSV
    const csv_in = "name,age\nAlice,30\nBob,25\nCharlie,35\n";
    var df = try DataFrame.fromCSVBuffer(allocator, csv_in, .{});
    defer df.free();

    // Filter
    const filtered = try df.filter(filterAgeOver30);
    defer filtered.free();

    // Export
    const csv_out = try filtered.toCSV(allocator, .{});
    defer allocator.free(csv_out);

    // Validate
    try testing.expectEqualStrings("name,age\nAlice,30\nCharlie,35\n", csv_out);
}
```

#### Browser Tests (`src/test/browser/`)

**Interactive Test Runner**: `src/test/browser/index.html`

**Features**:

- 17 custom tests (10 RFC 4180 + 7 edge cases)
- Real-time execution with progress bar
- Performance benchmarks (1K, 10K, 100K rows)
- Filter results (all, passed, failed)
- Console output with color-coded logging

**Test Suite**: `src/test/browser/tests.js`

```javascript
// Example test definition
const testSuites = {
  rfc4180: {
    name: "RFC 4180 Compliance",
    tests: [
      {
        file: "rfc4180/01_simple.csv",
        name: "Simple CSV with headers",
        expected: {
          rowCount: 3,
          columnCount: 3,
          columns: ["name", "age", "city"],
        },
      },
      // ... more tests
    ],
  },
};
```

**Running Browser Tests**:

```bash
# Build WASM
zig build -Dtarget=wasm32-freestanding

# Serve tests
python3 -m http.server 8080

# Open browser
open http://localhost:8080/src/test/browser/
```

#### Benchmark Tests (`src/test/benchmark/`)

**CSV Parsing Benchmarks**:

```zig
// src/test/benchmark/csv_parse.zig
const std = @import("std");
const DataFrame = @import("../../core/dataframe.zig").DataFrame;

pub fn benchmarkCSVParse(allocator: std.mem.Allocator) !void {
    const sizes = [_]usize{ 1_000, 10_000, 100_000 };

    for (sizes) |size| {
        const csv = try generateCSV(allocator, size, 10);
        defer allocator.free(csv);

        const start = std.time.nanoTimestamp();
        const df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
        const end = std.time.nanoTimestamp();
        df.free();

        const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
        std.debug.print("{} rows: {d:.2}ms\n", .{ size, duration_ms });
    }
}
```

**DataFrame Operations Benchmarks**:

```zig
// src/test/benchmark/operations.zig
pub fn benchmarkFilter(allocator: std.mem.Allocator) !void {
    const df = try createTestDataFrame(allocator, 1_000_000);
    defer df.free();

    const start = std.time.nanoTimestamp();
    const filtered = try df.filter(someFilterFn);
    const end = std.time.nanoTimestamp();
    filtered.free();

    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    std.debug.print("Filter 1M rows: {d:.2}ms\n", .{duration_ms});
}
```

---

## Test Patterns and Templates

### Pattern 1: Basic Unit Test

```zig
// src/test/unit/core/series_test.zig
const std = @import("std");
const testing = std.testing;
const Series = @import("../../../core/series.zig").Series;

test "Series.len returns correct length" {
    const allocator = testing.allocator;

    const data = try allocator.alloc(f64, 100);
    defer allocator.free(data);

    const series = Series{
        .name = "test",
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 100,
    };

    try testing.expectEqual(@as(u32, 100), series.len());
}
```

### Pattern 2: Memory Leak Test

```zig
test "DataFrame.free releases all memory" {
    const allocator = testing.allocator;

    // Parse and free 1000 times
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const csv = "name,age\nAlice,30\nBob,25\n";
        const df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
        df.free();
    }

    // testing.allocator will report leaks automatically
}
```

### Pattern 3: Conformance Test

```zig
// src/test/unit/csv/conformance_test.zig
test "RFC 4180: 01_simple.csv" {
    const allocator = testing.allocator;
    const csv = @embedFile("../../../testdata/csv/rfc4180/01_simple.csv");

    const df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
    defer df.free();

    // Validate structure
    try testing.expectEqual(@as(u32, 3), df.rowCount);
    try testing.expectEqual(@as(usize, 3), df.columns.len);
    try testing.expectEqualStrings("name", df.columns[0].name);

    // Validate data
    const age_col = df.column("age").?;
    const ages = age_col.asInt64().?;
    try testing.expectEqual(@as(i64, 30), ages[0]);
    try testing.expectEqual(@as(i64, 25), ages[1]);
    try testing.expectEqual(@as(i64, 35), ages[2]);
}
```

### Pattern 4: Error Case Test

```zig
test "DataFrame.column returns error for non-existent column" {
    const allocator = testing.allocator;
    const csv = "name,age\nAlice,30\n";

    const df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
    defer df.free();

    // Should return null for non-existent column
    const result = df.column("nonexistent");
    try testing.expect(result == null);
}
```

### Pattern 5: Integration Test

```zig
// src/test/integration/csv_to_dataframe_test.zig
test "CSV → DataFrame → Operations → CSV round-trip" {
    const allocator = testing.allocator;

    const csv_in = "name,age,score\nAlice,30,95.5\nBob,25,87.3\nCharlie,35,91.0\n";

    // Parse
    var df = try DataFrame.fromCSVBuffer(allocator, csv_in, .{});
    defer df.free();

    // Select columns
    const selected = try df.select(&[_][]const u8{ "name", "age" });
    defer selected.free();

    // Filter rows
    const filtered = try selected.filter(ageOver30);
    defer filtered.free();

    // Export
    const csv_out = try filtered.toCSV(allocator, .{});
    defer allocator.free(csv_out);

    // Validate
    try testing.expectEqualStrings("name,age\nAlice,30\nCharlie,35\n", csv_out);
}

fn ageOver30(row: RowRef) bool {
    const age = row.getInt64("age") orelse return false;
    return age > 30;
}
```

---

## Conformance Test Suites

### Custom Test Suites

#### RFC 4180 Compliance Tests (10 files)

Located in `testdata/csv/rfc4180/`:

1. **01_simple.csv** - Basic CSV with headers, no special chars
2. **02_quoted_fields.csv** - Fields enclosed in quotes
3. **03_embedded_commas.csv** - Commas inside quoted fields
4. **04_embedded_newlines.csv** - Newlines inside quoted fields
5. **05_escaped_quotes.csv** - Double-quote escape (`""`)
6. **06_crlf_endings.csv** - CRLF line endings
7. **07_empty_fields.csv** - Empty/null values
8. **08_no_header.csv** - CSV without header row
9. **09_trailing_comma.csv** - Trailing comma (empty column)
10. **10_unicode_content.csv** - UTF-8 (emoji, CJK, Arabic)

**Test Runner**: `src/test/unit/csv/conformance_test.zig`

**MVP Target**: Pass 7/10 tests (defer string/unicode to 0.2.0)

#### Edge Case Tests (7 files)

Located in `testdata/csv/edge_cases/`:

1. **01_single_column.csv** - Only one column
2. **02_single_row.csv** - Header + 1 data row
3. **03_blank_lines.csv** - Blank lines to skip
4. **04_mixed_types.csv** - Int, float, bool, string
5. **05_special_characters.csv** - Special symbols, unicode math
6. **06_very_long_field.csv** - Fields >500 characters
7. **07_numbers_as_strings.csv** - Preserve leading zeros (zip codes)

### External Test Suites (Downloaded)

#### csv-spectrum (15 tests)

- **Source**: https://github.com/maxogden/csv-spectrum
- **License**: MIT
- **Location**: `testdata/external/csv-spectrum/`
- **Status**: ✅ Downloaded
- **Coverage**: Empty fields, quotes, newlines, UTF-8, JSON in CSV

#### Papa Parse (100+ tests)

- **Source**: https://github.com/mholt/PapaParse
- **License**: MIT
- **Location**: `testdata/external/PapaParse/tests/`
- **Status**: ✅ Downloaded
- **Coverage**: Streaming, encoding, type detection, error handling

#### uniVocity (50+ tests)

- **Source**: https://github.com/uniVocity/csv-parsers-comparison
- **License**: Apache 2.0
- **Location**: `testdata/external/csv-parsers-comparison/src/main/resources/`
- **Status**: ✅ Downloaded
- **Coverage**: Malformed CSVs, unusual delimiters, encoding issues

**Total**: **182+ test cases** available

**Quick Download** (already run):

```bash
./scripts/download_conformance_tests.sh
```

---

## Browser Testing

### Interactive Test Runner

**Location**: `src/test/browser/index.html`

**Features**:

- 17 custom tests (10 RFC 4180 + 7 edge cases)
- Real-time execution with progress bar
- Performance benchmarks (1K, 10K, 100K rows)
- Filter results (all, passed, failed)
- Console output with color-coded logging
- Expected results documented in `src/test/browser/expected/rfc4180_results.json`

### Running Browser Tests

```bash
# 1. Build WASM module
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall

# 2. Serve tests
python3 -m http.server 8080

# 3. Open browser
open http://localhost:8080/test/browser/

# 4. Click "Run All Tests"
```

### Browser Compatibility Matrix

| Browser        | Version | Status           | Notes                    |
| -------------- | ------- | ---------------- | ------------------------ |
| Chrome         | 90+     | ✅ Tier 1        | Full WebAssembly support |
| Firefox        | 88+     | ✅ Tier 1        | Full WebAssembly support |
| Safari         | 14+     | ✅ Tier 1        | Full WebAssembly support |
| Edge           | 90+     | ✅ Tier 1        | Chromium-based           |
| Chrome Android | 90+     | ⚠️ Tier 2        | Manual testing           |
| Safari iOS     | 14+     | ⚠️ Tier 2        | Manual testing           |
| IE 11          | N/A     | ❌ Not Supported | No WebAssembly           |

---

## Conformance Success Criteria

### RFC 4180 Compliance

- ✅ 100% pass rate on custom RFC 4180 tests (10/10 or 7/10 for MVP)
- ✅ 100% pass rate on custom edge cases (7/7)
- ✅ 100% pass rate on csv-spectrum (15/15)

### Performance

- ✅ Parse 100K rows in <1 second (browser)
- ✅ Parse 1M rows in <3 seconds (browser)
- ✅ Peak memory <2× CSV size (numeric data)
- ✅ No memory leaks (1000 parse/free cycles)

### Cross-Browser

- ✅ Pass all tests on Chrome 90+, Firefox 88+, Safari 14+, Edge 90+
- ✅ No crashes or hangs on large datasets
- ✅ Consistent results across browsers

---

## Development Workflow

### Before Writing Code

1. Read the relevant section in [docs/RFC.md](./docs/RFC.md)
2. Check [docs/TODO.md](./docs/TODO.md) for current tasks
3. Review [src/CLAUDE.md](./src/CLAUDE.md) for implementation patterns
4. Check performance targets for the feature

### While Writing Code

1. Write assertions first (pre-conditions, post-conditions, invariants)
2. Use explicit types (u32, not usize)
3. Keep functions under 70 lines
4. Add comments explaining WHY, not WHAT
5. Run `zig fmt` continuously
6. Consider WASM memory implications

### After Writing Code

1. Verify Tiger Style compliance (2+ assertions, bounded loops)
2. **Write unit tests** in `src/test/unit/` mirroring source structure
3. Run `zig build test` - **all tests must pass**
4. Test in browser environment (if JS-facing changes)
5. Benchmark against performance targets
6. Update documentation if API changed
7. Update docs/TODO.md to check off completed tasks

### Testing Requirements

- **Unit Tests**: Every public function in `src/test/unit/`
- **Integration Tests**: End-to-end DataFrame workflows in `src/test/integration/`
- **Conformance Tests**: RFC 4180 compliance in `src/test/unit/csv/conformance_test.zig`
- **Benchmark Tests**: Performance vs existing libraries in `src/test/benchmark/`
- **Browser Tests**: Real browser environments in `src/test/browser/`

**Test Coverage Target**: >80%

---

## Quick Commands

```bash
# Format code
zig fmt src/

# Build WASM module
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall

# Build native
zig build

# Run ALL tests (unit + integration)
zig build test

# Run specific test
zig build test -Dtest-filter=csv

# Run benchmarks
zig build benchmark

# Serve browser tests
python3 -m http.server 8080
# Navigate to http://localhost:8080/src/test/browser/

# Compare performance vs Papa Parse
node src/test/benchmark/compare.js
```

---

## Key Patterns to Note

### 1. Test Organization Pattern

**Source file**: `src/core/series.zig`
**Test file**: `src/test/unit/core/series_test.zig`

**Always** mirror the source structure in tests.

### 2. Test Data Pattern

**Test code**: Lives in `src/test/`
**Test data**: Lives in `testdata/`

**Never** put CSV files in `src/test/`, they go in `testdata/csv/`

### 3. Import Pattern for Tests

```zig
// src/test/unit/core/series_test.zig
const Series = @import("../../../core/series.zig").Series;
//                   ^^^^^^^^^ relative path from src/test/unit/core/ to src/core/
```

### 4. Fixture Loading Pattern

```zig
// Use @embedFile for test fixtures
const csv = @embedFile("../../../testdata/csv/rfc4180/01_simple.csv");
```

### 5. Arena Allocator Pattern

**Always use arena for DataFrame lifecycle** (see [src/CLAUDE.md](./src/CLAUDE.md))

### 6. Bounded Loop Pattern

**Always set explicit limits** (see [src/CLAUDE.md](./src/CLAUDE.md))

### 7. Assertion Pattern

**Every function needs 2+ assertions** (see [src/CLAUDE.md](./src/CLAUDE.md))

---

## Resources

### Zig Documentation

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- [Zig Build System](https://ziglang.org/learn/build-system/)
- [Zig Testing](https://ziglang.org/documentation/master/#Testing)

### CSV Specifications

- [RFC 4180 - CSV Format](https://www.rfc-editor.org/rfc/rfc4180) - Official CSV specification
- [CSV Parsing Benchmarks](https://leanylabs.com/blog/js-csv-parsers-benchmarks/) - Performance comparison

### WebAssembly

- [MDN WebAssembly](https://developer.mozilla.org/en-US/docs/WebAssembly)
- [Zig and WebAssembly](https://ziglang.org/learn/overview/#webassembly-support)

### Tiger Style

- [Tiger Style Guide](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md) - Safety-first Zig patterns

---

## Contact & Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/rozes/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/rozes/discussions)
- **PRs**: Follow [docs/CONTRIBUTING.md](./docs/CONTRIBUTING.md)

---

**Last Updated**: 2025-10-27
**Next Review**: When Milestone 0.1.0 is complete (see docs/TODO.md)

- all new docs should be written in /docs
- dont update RFC.md
- all document creation should be in docs/
- whenever a todo is done, update @docs/TODO.md
- add a src/profiling_tools and keep the tools there
- when finishing a TODO task, please update @docs/TODO.md
- whenever finishing a task, update @docs/TODO.md
- all new docs should go into /docs
- all benchmarks should be put into zig build benchmark
- all benchmarks should be placed in zig build benchmark, dont create separate zig build benchmark-xxx commands