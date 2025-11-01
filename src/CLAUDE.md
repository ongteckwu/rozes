# Rozes Source Code - Implementation Guide

**Purpose**: Implementation patterns, code organization, and Zig-specific guidelines for Rozes.

---

## ⚠️ CRITICAL: Milestone Documentation Updates

**At EVERY milestone (0.1.0, 0.2.0, 1.0.0, etc.), MUST update:**

1. **docs/CHANGELOG.md** - Point form (bullets), NOT paragraphs
2. **README.md** - Version numbers, test counts, benchmarks, features

**Why**: Users rely on CHANGELOG for migration, README is first impression

**Checklist**:

- [ ] CHANGELOG.md new version section
- [ ] README.md test count
- [ ] README.md benchmarks
- [ ] README.md features
- [ ] Verify all claims accurate

---

## Performance Optimization Strategy

> **See**: [docs/optimizations/](../docs/optimizations/) for detailed guides

### Core Principles

1. **Profile First** - Measure before optimizing. Join optimization revealed data copying (40-60%), NOT hashing
2. **Low-Hanging Fruit** - ① Algorithmic ② SIMD ③ Memory layout ④ Code elimination
3. **Benchmark Design** - Separate full pipeline vs pure algorithm (Join: 968ms full vs 1.42ms pure)
4. **Measure Everything** - Baseline → Expected → Actual → Correctness

### Critical Learnings (0.7.0)

- **String Interning**: 4-8× memory reduction for cardinality <5%
- **SIMD String Comparison**: 2-4× faster for >16 bytes, 7.5× on unequal lengths
- **Hash Caching**: Pre-compute hashes → 20-30% faster join/groupby (future)
- **Column HashMap**: O(n) → O(1) lookups → 30-50% faster (future)

### SIMD Integration

**Available** (`src/core/simd.zig`):

- `compareFloat64Batch()` - 2× throughput
- `compareInt64Batch()` - 2× throughput
- `findNextSpecialChar()` - 16× throughput

**Pattern**:

```zig
if (simd.simd_available and data.len >= simd_width) {
    return processWithSIMD(data);
}
return processScalar(data);
```

**When SIMD Helps**: ✅ Contiguous data, simple ops, >16 bytes  
**When NOT**: ❌ Random access, complex branching, <16 bytes

---

## Critical WebAssembly Pitfalls

**READ BEFORE writing Wasm code:**

- Never allocate >1KB on stack - use `@wasmMemoryGrow()`
- Use `u32` for all Wasm exports (not `usize`)
- Every function needs 2+ assertions (Wasm debugging harder)
- Log row/col/field for data errors
- No hardcoded memory offsets in JS - use `rozes_alloc`/`rozes_free_buffer`
- Post-loop assertions MANDATORY

**Wasm Size**: 74KB (40KB gzip) → Target: 32KB (10KB gzip)

---

## Tiger Style Patterns

### Bounded Loops

```zig
const MAX_ITERATIONS: u32 = 32;
var i: u32 = 0;
while (i < MAX_ITERATIONS and condition) : (i += 1) { }
std.debug.assert(i == expected or i == MAX_ITERATIONS);
```

### 2+ Assertions

```zig
pub fn isEmpty(self: Series) bool {
    std.debug.assert(self.length <= MAX_ROWS);
    std.debug.assert(@intFromPtr(self) != 0);
    return self.length == 0;
}
```

### Function Length

- > 70 lines → extract type-specific helpers

### Error Context

```zig
catch |err| {
    std.log.err("Parse failed at row {}, col '{}': field='{}' - {}",
        .{row_idx, col_name, field, err});
    return error.TypeMismatch;
}
```

### Data Processing

- **Type Inference**: Default to String (universal fallback)
- **NaN Handling**: Check before comparison/aggregation
- **Overflow Checks**: Check BEFORE arithmetic using wider type

### Violations

- ❌ NEVER use for-loops over runtime data (use bounded while loops)
- ❌ HashMap iterators need MAX_ITERATIONS bound
- ❌ Post-loop assertions MANDATORY
- ❌ Use u32 for indices/counters (not usize)

### Additional Learnings (Tiger Style Review 2025-11-01)

#### 1. Post-Loop Assertions Pattern

**Rule**: Every loop that iterates over data MUST have a post-loop assertion

```zig
// ✅ CORRECT - Post-loop assertion verifies loop completed correctly
var i: u32 = 0;
while (i < data.len and i < MAX) : (i += 1) {
    process(data[i]);
}
std.debug.assert(i == data.len or i == MAX); // ✅ Verify termination condition

// ❌ WRONG - Missing post-loop assertion
var i: u32 = 0;
while (i < data.len) : (i += 1) {
    process(data[i]);
}
// ❌ No assertion - cannot verify loop completed correctly
```

**Why**: Post-loop assertions catch off-by-one errors, infinite loops, and data corruption

#### 2. Helper Functions Need 2+ Assertions

**Rule**: Even small helper functions need input validation

```zig
// ✅ CORRECT - Helper with 2+ assertions
fn findPrevValid(data: []const f64, start_idx: u32) ?u32 {
    std.debug.assert(data.len > 0); // ✅ Assertion 1: Non-empty data
    std.debug.assert(start_idx <= data.len); // ✅ Assertion 2: Valid index

    var i: u32 = 0;
    while (i < start_idx) : (i += 1) {
        // ... search logic
    }
    std.debug.assert(i == start_idx); // ✅ Post-loop assertion
    return null;
}

// ❌ WRONG - Helper missing assertions
fn findPrevValid(data: []const f64, start_idx: u32) ?u32 {
    var i: u32 = 0;
    while (i < start_idx) : (i += 1) { }
    return null;
}
```

**Why**: Helpers are often called in tight loops - buffer overflows here cause segfaults

#### 3. JSON Parsing Bounded Loops

**Rule**: JSON parsing needs 2 MAX bounds (iterations + field length)

```zig
// ✅ CORRECT - Bounded JSON parsing
const MAX_PARSE_ITERATIONS: u32 = 10_000; // Max fields in array
const MAX_FIELD_LENGTH: u32 = 1_000_000; // Max single field

var i: u32 = 0;
var iterations: u32 = 0;
while (i < json.len and iterations < MAX_PARSE_ITERATIONS) : (iterations += 1) {
    // Inner loop: Bounded field search
    var field_len: u32 = 0;
    while (i < json.len and json[i] != '"' and field_len < MAX_FIELD_LENGTH) : ({
        i += 1;
        field_len += 1;
    }) {}

    if (field_len >= MAX_FIELD_LENGTH) {
        return error.FieldTooLarge;
    }
}
std.debug.assert(iterations <= MAX_PARSE_ITERATIONS); // ✅ Post-assertion

// ❌ WRONG - Unbounded JSON parsing (infinite loop risk)
while (i < json.len) : (i += 1) {
    while (i < json.len and json[i] != '"') : (i += 1) {}
}
```

**Why**: Malformed JSON can cause infinite loops - bound both outer AND inner loops

#### 4. Overflow Checks Before Arithmetic

**Rule**: Check for overflow BEFORE doing arithmetic using wider type

```zig
// ✅ CORRECT - Check overflow before calculation
const count_u64 = @as(u64, count);
const from_len_u64 = @as(u64, from.len);
const new_len_u64 = count_u64 * from_len_u64;

if (new_len_u64 > MAX_STRING_LENGTH) {
    return error.StringTooLong;
}

const new_len: usize = @intCast(new_len_u64);

// ❌ WRONG - Arithmetic first, overflow after (may already have crashed)
const new_len = count * from.len; // May overflow!
if (new_len > MAX_STRING_LENGTH) {
    return error.StringTooLong;
}
```

**Why**: Integer overflow is undefined behavior - widen BEFORE arithmetic

#### 5. Missing Value Representation

**Rule**: Document data representation limitations clearly

```zig
// ⚠️ CURRENT LIMITATION (v1.3.0):
// Int64: 0 represents missing (cannot distinguish from legitimate zero)
// Float64: NaN represents missing (correct - NaN has no other meaning)

// ✅ FUTURE FIX (v1.4.0): Null bitmap
pub const Series = struct {
    name: []const u8,
    value_type: ValueType,
    data: union(ValueType) { ... },
    length: u32,
    null_bitmap: ?[]bool, // ✅ true = null, false = valid
};
```

**Why**: Users need to know limitations - silently losing zeros causes data corruption

#### 6. Code Duplication - Extract Helper Functions

**Rule**: Extract repeated logic (>30 lines) to helper functions

```zig
// ✅ CORRECT - Extracted helper (see src/wasm.zig:parseJSONStringArray)
fn parseJSONStringArray(json: []const u8, allocator: Allocator) !ArrayList([]const u8) {
    // Shared implementation with proper Tiger Style
}

// Usage in multiple functions
var col_names = parseJSONStringArray(json, allocator) catch |err| {
    return @intFromEnum(ErrorCode.fromError(err));
};

// ❌ WRONG - Duplicated 50+ lines in 3 locations
// rozes_select() - lines 544-595 (duplicated)
// rozes_drop() - lines 644-695 (duplicated)
// rozes_join() - lines 1478-1507 (simplified, missing bounds!)
```

**Why**: Duplication leads to inconsistency - one location may be fixed, others not

---

## Source Organization

```
src/
├── core/              # DataFrame engine
│   ├── types.zig      # Core type definitions
│   ├── series.zig     # Series implementation
│   ├── dataframe.zig  # DataFrame implementation
│   └── operations.zig # DataFrame operations
├── csv/               # CSV parsing/export
│   ├── parser.zig     # RFC 4180 parser
│   └── export.zig     # CSV serialization
├── bindings/          # Platform bindings
│   └── wasm/          # WebAssembly
└── rozes.zig          # Public API
```

### Module Responsibilities

**types.zig**: ValueType, ColumnDesc, CSVOptions, ParseError  
**series.zig**: 1D homogeneous typed array  
**dataframe.zig**: 2D tabular data, CSV import/export  
**parser.zig**: RFC 4180 CSV parsing with state machine

---

## Node.js API Propagation

**CRITICAL**: All new features MUST be exposed to Node.js API.

### Propagation Checklist

1. **Implement in Zig** (`src/core/`) - Tiger Style, unit tests
2. **Export from Wasm** (`src/wasm.zig`) - C ABI, memory handling
3. **Wrap in JavaScript** (`js/rozes.js`) - User-friendly API, JSDoc
4. **Add TypeScript Types** (`dist/index.d.ts`) - Types, examples
5. **Add Node.js Tests** (`src/test/nodejs/`) - Correctness, edge cases
6. **Update Documentation** - README examples, performance notes

---

## Zig Implementation Patterns

### Pattern 1: Bounded Loops with Explicit Limits

```zig
const MAX_ROWS: u32 = 4_000_000_000;

pub fn parseCSV(buffer: []const u8) !DataFrame {
    std.debug.assert(buffer.len > 0);

    var row_count: u32 = 0;
    while (row_count < MAX_ROWS) : (row_count += 1) {
        if (is_end_of_file) break;
    }

    std.debug.assert(row_count <= MAX_ROWS);
    return dataframe;
}
```

### Pattern 2: Arena Allocator for Lifecycle

```zig
pub fn fromCSVBuffer(allocator: std.mem.Allocator, buffer: []const u8) !DataFrame {
    const arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer { arena.deinit(); allocator.destroy(arena); }

    const arena_alloc = arena.allocator();
    const columns = try arena_alloc.alloc(ColumnDesc, col_count);

    return DataFrame{ .arena = arena, /* ... */ };
}
```

### Pattern 3: Explicit Type Sizes

```zig
// ✅ Correct - consistent across platforms
const row_index: u32 = 0;
const col_count: u32 = @intCast(df.columns.len);

// ❌ Wrong - platform-dependent
const row_index: usize = 0;
```

### Pattern 4: Tagged Unions for Variant Types

```zig
pub const Value = union(ValueType) {
    Int64: i64,
    Float64: f64,
    String: []const u8,
    Bool: bool,
    Null: void,

    pub fn asFloat64(self: Value) ?f64 {
        return switch (self) {
            .Float64 => |val| val,
            .Int64 => |val| @floatFromInt(val),
            else => null,
        };
    }
};
```

---

## Error Handling

### Error Set Definitions

```zig
// src/csv/parser.zig
pub const CSVError = error{
    InvalidFormat,
    UnexpectedEndOfFile,
    TooManyColumns,
    TooManyRows,
    InvalidQuoting,
    OutOfMemory,
};

// src/core/dataframe.zig
pub const DataFrameError = error{
    ColumnNotFound,
    TypeMismatch,
    IndexOutOfBounds,
    EmptyDataFrame,
    OutOfMemory,
};
```

### Error Context

```zig
pub fn column(self: *const DataFrame, name: []const u8) !*const Series {
    for (self.series, 0..) |*series, i| {
        if (std.mem.eql(u8, self.columns[i].name, name)) {
            return series;
        }
    }

    std.log.err("Column not found: {s}", .{name});
    return error.ColumnNotFound;
}
```

### Never Silent Failures

```zig
// ❌ CRITICAL DATA LOSS
pub fn columnNames(self: *const DataFrame) []const []const u8 {
    const names = allocator.alloc([]const u8, self.columns.len) catch return &[_][]const u8{};
    // User has no idea allocation failed!
}

// ✅ CORRECT - Propagate error
pub fn columnNames(self: *const DataFrame, allocator: std.mem.Allocator) ![]const []const u8 {
    return try allocator.alloc([]const u8, self.columns.len);
}
```

---

## Memory Management

### Allocation Strategy

**DataFrame lifecycle**:

1. Create arena allocator
2. All DataFrame allocations use arena
3. Single `free()` call cleans up everything

```zig
pub const DataFrame = struct {
    arena: *std.heap.ArenaAllocator,

    pub fn free(self: DataFrame) void {
        self.arena.deinit();
        self.allocator.destroy(self.arena);
    }
};
```

---

## Testing Patterns

**CRITICAL**: Every code change MUST include tests.

### Test Coverage Requirements

1. **Unit Tests** - Every public function ≥1 test
2. **Error Case Tests** - Bounds, invalid input, parse failures
3. **Integration Tests** - CSV → DataFrame → operations workflows
4. **Memory Leak Tests** - 1000 iterations create/free cycles
5. **Conformance Tests** - RFC 4180 compliance via testdata files

**Test Location**: All tests in `src/test/`, NOT in source files

### Unit Test Template

```zig
test "Series.get checks bounds" {
    const allocator = std.testing.allocator;

    const data = try allocator.alloc(f64, 10);
    defer allocator.free(data);
    data[0] = 1.5;

    const series = Series{
        .valueType = .Float64,
        .data = .{ .Float64 = data },
        .length = 10,
    };

    const val = series.get(0);
    try std.testing.expectEqual(@as(f64, 1.5), val.?.Float64);
}
```

### Memory Leak Test Template

```zig
test "DataFrame.free releases all memory" {
    const allocator = std.testing.allocator;

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const df = try DataFrame.create(allocator, &columns, 100);
        df.free();
    }
    // testing.allocator reports leaks automatically
}
```

### Integration Test Template

```zig
test "CSV parse → DataFrame → CSV export round-trip" {
    const allocator = std.testing.allocator;

    const original_csv = "name,age\nAlice,30\nBob,25\n";

    const df = try DataFrame.fromCSVBuffer(allocator, original_csv, .{});
    defer df.free();

    const exported_csv = try df.toCSV(allocator, .{});
    defer allocator.free(exported_csv);

    try std.testing.expectEqualStrings(original_csv, exported_csv);
}
```

---

## CSV Parsing - RFC 4180 Compliance

### Checklist

**MUST HANDLE**:

1. ✅ Quoted fields with embedded delimiters
2. ✅ Quoted fields with embedded newlines
3. ✅ Escaped quotes (`""` → `"`)
4. ✅ CRLF line endings
5. ⚠️ CR-only line endings (old Mac)
6. ❌ UTF-8 BOM detection (0xEF 0xBB 0xBF)
7. ✅ Empty fields
8. ⚠️ Empty CSV with headers only

### Critical Issues

**1. BOM Detection**:

```zig
// ✅ CORRECT - Skip BOM if present
pub fn init(allocator: std.mem.Allocator, buffer: []const u8) !CSVParser {
    const start_pos: u32 = if (buffer.len >= 3 and
        buffer[0] == 0xEF and buffer[1] == 0xBB and buffer[2] == 0xBF)
        3
    else
        0;

    return CSVParser{ .pos = start_pos, /* ... */ };
}
```

**2. Line Ending Normalization**:

```zig
// ✅ CORRECT - Centralized
fn skipLineEnding(self: *CSVParser) void {
    if (self.buffer[self.pos] == '\r') {
        self.pos += 1;
        if (self.pos < self.buffer.len and self.buffer[self.pos] == '\n') {
            self.pos += 1;
        }
    } else if (self.buffer[self.pos] == '\n') {
        self.pos += 1;
    }
}
```

**3. Empty CSV Handling**:

```zig
// ✅ CORRECT - Allow empty DataFrames
if (data_rows.len == 0) {
    return try DataFrame.create(self.allocator, col_descs, 0);
}
```

---

## Conformance Testing

### Running Tests

```bash
zig build conformance  # Test all CSV files in testdata/
```

**What It Tests**:

- 10 RFC 4180 tests (`testdata/csv/rfc4180/`)
- 7 edge cases (`testdata/csv/edge_cases/`)
- 18 external suites (`testdata/external/`)

**Total**: 35 CSV files

### Current Results (MVP)

**0.1.0 Status**:

- ✅ 6/35 passing (numeric-only)
- ⏸️ 3 skipped (deferred to 0.2.0 - string support)
- ❌ 26 failing (contain strings - expected for MVP)

**Pass Rate**: 17% (expected for numeric-only MVP)

### Expected Results by Version

| Version | Target       | Reason                |
| ------- | ------------ | --------------------- |
| 0.1.0   | 17% (6/35)   | Numeric columns only  |
| 0.2.0   | 80% (28/35)  | Add string support    |
| 0.3.0   | 100% (35/35) | Handle all edge cases |

---

**Last Updated**: 2025-11-01  
**Related**: `../CLAUDE.md` (project), `../docs/optimizations/` (detailed guides)
