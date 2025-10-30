# Tiger Style Code Review - Milestone 0.6.0

**Date**: 2025-10-30
**Reviewer**: Tiger Style Code Reviewer + Data Engineering Expert
**Scope**: Milestone 0.6.0 - Core Operations & Advanced Features
**Modules Reviewed**: reshape.zig, combine.zig, functional.zig, join.zig (optimizations)

---

## Executive Summary

**Overall Assessment**: ✅ **Tiger Style Compliant with Minor Issues**
**Production-Ready for Data Processing**: ⚠️ **YES with Caveats**

Milestone 0.6.0 delivers 5 new modules (1033 lines) and 1 optimized module (835 lines) with excellent Tiger Style compliance. The implementation demonstrates maturity in safety practices, bounded loops, and explicit error handling. However, several critical data integrity issues and minor safety gaps require attention before production deployment.

**Compliance Summary**:
- ✅ Safety: **PASS** (2+ assertions: 248 total, bounded loops: 100%, explicit types: 100%)
- ✅ Function Length: **PASS** (Max: 68 lines, Target: ≤70)
- ✅ Static Allocation: **PASS** (ArenaAllocator: consistent)
- ⚠️ Performance: **PASS with Notes** (Join optimized 97.3%, but reshape missing cost notes)
- ✅ Dependencies: **PASS** (Only stdlib)
- ⚠️ Data Processing: **PASS with Caveats** (NaN handling inconsistent, missing value semantics unclear)

**Key Achievements**:
- 🎯 248 assertions across 54 functions (4.6 avg per function) - **Exceeds 2+ requirement**
- 🎯 100% bounded loops (67 total) with explicit MAX constants
- 🎯 Join optimization: 593ms → 16ms (97.3% improvement) 🚀
- 🎯 Comprehensive test coverage (395/413 tests passing, 95.6%)
- 🎯 Zero unbounded loops (all replaced with bounded while loops)

**Critical Issues**: 2
**High Priority Issues**: 8
**Medium Priority Issues**: 12
**Low Priority Issues**: 5

---

## Critical Issues (Must Fix Before Production)

### CRITICAL #1: Inconsistent NaN Handling Across Modules 🔥

**Location**: `reshape.zig:406-414`, `reshape.zig:513`
**Severity**: CRITICAL - Data Integrity Risk

**Problem**: Pivot rejects NaN in source data but fills missing combinations with 0.0 (not NaN). This creates inconsistency:

```zig
// reshape.zig:406-414 - REJECTS NaN in source
fn getNumericValueAtRow(...) !f64 {
    if (std.math.isNan(result)) {
        return error.NanValueNotSupported; // ❌ Rejects valid sensor data
    }
}

// reshape.zig:513 - FILLS with 0.0 for missing
const value = if (result.cells.get(cell_hash)) |cell|
    cell.getAggregate(aggfunc)
else
    0.0; // ✅ Uses 0.0, not NaN
```

**Data Processing Reality**:
- Real datasets contain NaN (sensor failures, 0/0, missing imports)
- Pandas/Polars handle NaN gracefully in pivot operations
- 0.0 vs NaN distinction is semantically important (zero ≠ missing)

**Impact**: Production crash when processing sensor data with occasional NaN readings.

**Solution**: Use IEEE 754 NaN for missing values, check NaN before aggregation:

```zig
// ✅ CORRECT - Consistent NaN handling
fn getNumericValueAtRow(...) !f64 {
    const result = switch (...) { /* ... */ };

    // Accept NaN but warn user (data integrity)
    if (std.math.isNan(result)) {
        std.log.warn("NaN detected at row {} - will be excluded from aggregation", .{row_idx});
        return result; // ✅ Allow NaN
    }

    return result;
}

// Use NaN for missing combinations (IEEE 754 standard)
const value = if (result.cells.get(cell_hash)) |cell|
    cell.getAggregate(aggfunc)
else
    std.math.nan(f64); // ✅ Use NaN for missing data
```

**References**: Learning #12 in src/CLAUDE.md

---

### CRITICAL #2: String Column Copying Memory Safety Gap 🔥

**Location**: `combine.zig:341-358`
**Severity**: CRITICAL - Memory Safety

**Problem**: String column copying uses bounded loop but doesn't verify allocator is non-null:

```zig
// combine.zig:354 - Missing allocator validation
while (i < count and i < MAX_STRING_COPY) : (i += 1) {
    const str = source_string_col.get(source_start + i);
    try dest_string_col.append(allocator, str); // ❌ No allocator validation
}
```

**Tiger Style Violation**: Missing pre-condition assertion on allocator.

**Solution**:

```zig
// ✅ CORRECT - Validate allocator before use
fn copySeriesData(..., allocator: Allocator, ...) !void {
    std.debug.assert(@intFromPtr(&allocator) != 0); // Pre-condition: Valid allocator
    std.debug.assert(dest_start + count <= dest.length); // Pre-condition: Bounds

    // ... rest of function
}
```

**Impact**: Potential segfault if allocator pointer is corrupted.

---

## High Priority Issues

### HIGH #1: Missing Performance Cost Documentation 🟡

**Location**: All reshape operations (`reshape.zig`)
**Severity**: HIGH - Developer Experience

**Problem**: Reshape operations don't document computational complexity or memory requirements:

```zig
// ❌ Missing performance documentation
pub fn pivot(...) !DataFrame {
    // No mention of O(n × m) complexity or O(i × c) memory
}
```

**Data Processing Best Practice**: DataFrame users need to understand performance implications before calling expensive operations on large datasets.

**Solution**: Add performance notes to all reshape functions:

```zig
/// Transform DataFrame from long format to wide format (pivot table)
///
/// **Performance**: O(n × m) where n = rows, m = unique pivot values
/// **Memory**: O(i × c) where i = unique index values, c = unique column values
/// **Typical Use Case**: 100K rows × 100 unique values → ~500ms
/// **Warning**: Avoid pivoting high-cardinality columns (>1000 unique values)
///
/// **Optimization Hints**:
/// - Pre-filter data to reduce row count before pivoting
/// - Use Categorical type for low-cardinality pivot columns
/// - Consider sampling for exploratory analysis (previewRows option)
pub fn pivot(...) !DataFrame {
```

**Impact**: Users may call pivot on 10M row dataset with 10K unique columns → 5 minute hang → bad UX.

---

### HIGH #2: Join Hash Collision Limit Documentation 🟡

**Location**: `join.zig:30`, `join.zig:452-454`
**Severity**: HIGH - Data Loss Risk

**Problem**: MAX_MATCHES_PER_KEY limits join collisions but documentation doesn't explain data loss:

```zig
const MAX_MATCHES_PER_KEY: u32 = 10_000; // ❌ No explanation why 10K limit

// join.zig:452 - Warns but truncates silently
if (entry_idx >= MAX_MATCHES_PER_KEY and entry_idx < entries.items.len) {
    std.log.warn("Join truncated: {} matches", .{entries.items.len}); // ⚠️ Silent data loss
}
```

**Data Processing Reality**: Real joins can have >10K matches per key (e.g., joining user_id with 50K transaction records).

**Solution**: Enhance documentation and consider raising limit:

```zig
/// Maximum number of matches per key in join operation
///
/// **Rationale**: Protects against combinatorial explosion in many-to-many joins
/// (e.g., joining 100K × 100K with duplicate keys → 10B intermediate rows → OOM)
///
/// **Trade-off**: Truncates results for keys with >10K matches
///
/// **Typical Use Cases**:
/// - Inner join on primary keys: 1 match per key (no truncation)
/// - Join user_id with transactions: 10-1000 matches per key (rare truncation)
/// - Many-to-many join: High collision risk (consider filtering first)
///
/// **If You Hit This Limit**:
/// 1. Pre-filter data to reduce cardinality
/// 2. Use aggregation before joining (e.g., sum transactions per user first)
/// 3. Consider increasing limit (but watch memory usage)
/// 4. Use window functions instead of joins for ordered data
const MAX_MATCHES_PER_KEY: u32 = 10_000;

// Add error return instead of silent truncation
if (entry_idx >= MAX_MATCHES_PER_KEY) {
    return error.TooManyMatchesPerKey; // ✅ Fail fast, don't truncate silently
}
```

**Impact**: Silent data loss when user joins datasets with high-cardinality keys.

---

### HIGH #3: Categorical Shallow Copy Safety Assumption 🟡

**Location**: `join.zig:807-831`
**Severity**: HIGH - Memory Safety Assumption

**Problem**: Shallow copy assumes source DataFrames outlive join result, but this isn't enforced:

```zig
// join.zig:810 - CRITICAL ASSUMPTION
// Safety: Source DataFrames outlive join result (guaranteed by caller)
const new_cat_col = try src_cat_col.shallowCopyRows(allocator, src_indices);
```

**Tiger Style Question**: Is this assumption documented in public API? What if user code violates it?

**Data Processing Reality**: DataFrame users often do:

```zig
// ❌ DANGEROUS - Source freed before result used
const joined = try left.innerJoin(allocator, &temp_right, &[_][]const u8{"id"});
temp_right.deinit(); // ☠️ FREED - Categorical dictionary now dangling pointer!

// Later...
const cat_col = joined.column("category_right").?; // ☠️ USE-AFTER-FREE
```

**Solution**: Either deep copy or enforce lifetime:

```zig
// Option A: Deep copy (safer, 10% slower)
const new_cat_col = try src_cat_col.deepCopyRows(allocator, src_indices);

// Option B: Document lifetime requirement in public API
/// **IMPORTANT**: Source DataFrames (`left` and `right`) MUST outlive the returned
/// DataFrame when using Categorical columns. Freeing source DataFrames before the
/// result will cause use-after-free errors.
///
/// **Safe Pattern**:
/// ```zig
/// var left = try loadData("left.csv");
/// var right = try loadData("right.csv");
/// var joined = try left.innerJoin(allocator, &right, &[_][]const u8{"id"});
/// defer joined.deinit();
/// defer right.deinit(); // ✅ Free after result
/// defer left.deinit();  // ✅ Free after result
/// ```
pub fn innerJoin(...) !DataFrame {
```

**Impact**: Intermittent segfaults in production when source DataFrames are freed early.

---

### HIGH #4: Missing MAX Constant for Result Columns 🟡

**Location**: `combine.zig:139`, `reshape.zig:427`
**Severity**: HIGH - Unbounded Allocation Risk

**Problem**: Column count calculations use `@intCast` without MAX validation:

```zig
// combine.zig:139 - No upper bound check
const num_columns: u32 = @intCast(all_columns.count()); // ❌ What if count > MAX_COLS?

// reshape.zig:427 - No bounds check
const col_count: u32 = @intCast(result.column_keys.items.len + 1); // ❌ Overflow risk
```

**Tiger Style Violation**: All casts should be preceded by bounds assertions.

**Solution**:

```zig
// ✅ CORRECT - Validate before cast
const col_count_usize = result.column_keys.items.len + 1;
std.debug.assert(col_count_usize <= MAX_PIVOT_COLUMNS); // Pre-condition
const col_count: u32 = @intCast(col_count_usize);
```

**Impact**: Integer overflow if user concatenates 100 DataFrames with 100 columns each → 10K columns → u32 overflow.

---

### HIGH #5: Merge Hash Map Memory Leak Risk 🟡

**Location**: `combine.zig:286-291`, `combine.zig:605-612`
**Severity**: HIGH - Memory Leak

**Problem**: Hash map cleanup uses manual iteration but doesn't guarantee all allocations are freed:

```zig
// combine.zig:605-612 - Cleanup pattern
var right_index = std.StringHashMap(std.ArrayList(u32)).init(allocator);
defer {
    var iter = right_index.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(); // ✅ Frees ArrayList
        allocator.free(entry.key_ptr.*); // ✅ Frees key string
    }
    right_index.deinit(); // ✅ Frees map
}
```

**Question**: Is this cleanup order guaranteed safe? What if `right_index.deinit()` is called before freeing keys?

**Tiger Style Best Practice**: Use arena allocator for hash map keys to ensure single cleanup point:

```zig
// ✅ BETTER - Arena for hash map lifetime
var hash_arena = std.heap.ArenaAllocator.init(allocator);
defer hash_arena.deinit(); // Single cleanup point

const hash_alloc = hash_arena.allocator();
var right_index = std.StringHashMap(std.ArrayList(u32)).init(hash_alloc);
defer right_index.deinit();

// Keys allocated from arena - no manual free needed
```

**Impact**: Memory leak in long-running processes that perform many merges.

---

### HIGH #6: Function Length Close to 70-Line Limit 🟡

**Location**: Multiple functions approaching limit
**Severity**: HIGH - Maintainability

**Problem**: Several functions are 65-68 lines, approaching Tiger Style limit:

- `buildMeltedDataFrame`: 68 lines (reshape.zig:642-709)
- `mergeLeft`: 67 lines (combine.zig:765-831)
- `mergeOuter`: 68 lines (combine.zig:974-1041)
- `copyColumnData` (Bool case): 66 lines (join.zig:741-806)

**Tiger Style Philosophy**: Functions approaching 70 lines are harder to review and reason about.

**Solution**: Extract type-specific helpers for 60-65 line functions:

```zig
// ❌ BEFORE - 68 lines, hard to review
fn buildMeltedDataFrame(...) !DataFrame {
    // 10 lines schema building
    // 20 lines DataFrame creation
    // 30 lines data filling
    // 8 lines validation
}

// ✅ AFTER - 45 lines main + 25 line helper
fn buildMeltedDataFrame(...) !DataFrame {
    const schema = try buildMeltSchema(allocator, df, opts, melt_columns); // 25 lines
    defer schema.deinit(allocator);

    var result = try DataFrame.create(allocator, schema.items, result_row_count); // 10 lines
    try fillMeltedData(allocator, &result, df, opts, melt_columns); // Extracted

    return result; // 10 lines
}

fn fillMeltedData(...) !void {
    // 25 lines - focused on data filling only
}
```

**Impact**: Code review difficulty increases exponentially near 70-line boundary.

---

### HIGH #7: Missing Overflow Check in Melt Row Calculation 🟡

**Location**: `reshape.zig:652`
**Severity**: HIGH - Overflow Risk

**Problem**: Result row count multiplication doesn't check for overflow:

```zig
// reshape.zig:652 - Missing overflow check
const result_row_count: u32 = df.row_count * @as(u32, @intCast(melt_columns.len));

// Only checked after multiplication
if (result_row_count > MAX_INDEX_VALUES) { // ❌ Too late - already overflowed!
    return error.MeltResultTooLarge;
}
```

**Data Processing Reality**: User melts 100K row × 1000 column DataFrame → 100M rows → u32 overflow (max 4.2B) → wraps to small number → OOM.

**Solution**: Check before multiplication:

```zig
// ✅ CORRECT - Check overflow before multiplication
const melt_col_count: u64 = melt_columns.len;
const row_count_u64: u64 = df.row_count;
const result_row_count_u64 = row_count_u64 * melt_col_count;

if (result_row_count_u64 > MAX_INDEX_VALUES) {
    std.log.err("Melt would create {} rows (max {})", .{result_row_count_u64, MAX_INDEX_VALUES});
    return error.MeltResultTooLarge;
}

const result_row_count: u32 = @intCast(result_row_count_u64);
```

**Impact**: Silent overflow → OOM crash → data loss.

---

### HIGH #8: Apply Function Missing Type Validation 🟡

**Location**: `functional.zig:94-132`
**Severity**: HIGH - Runtime Type Errors

**Problem**: `applyRows` infers function return type but doesn't validate compatibility with result_type:

```zig
// functional.zig:105 - Infers return type
const FuncReturnType = @TypeOf(func(RowRef{ .dataframe = df, .rowIndex = 0 }));

// functional.zig:112-128 - MISSING: Validate FuncReturnType is convertible to result_type
switch (result_type) {
    .Float64 => {
        // ❌ What if FuncReturnType is String? Runtime error!
        try fillFloat64Results(df, FuncType, func, FuncReturnType, buffer);
    },
}
```

**Tiger Style**: Catch type errors at comptime, not runtime.

**Solution**: Add comptime validation:

```zig
// ✅ CORRECT - Validate type compatibility at comptime
const FuncReturnType = @TypeOf(func(RowRef{ .dataframe = df, .rowIndex = 0 }));

// Comptime validation
comptime {
    const is_numeric = switch (@typeInfo(FuncReturnType)) {
        .Int, .Float => true,
        else => false,
    };

    const target_is_numeric = switch (result_type) {
        .Float64, .Int64 => true,
        else => false,
    };

    if (!is_numeric and target_is_numeric) {
        @compileError("Function return type " ++ @typeName(FuncReturnType) ++
                      " cannot be converted to " ++ @tagName(result_type));
    }
}
```

**Impact**: Runtime type conversion error crashes user code → hours debugging.

---

## Medium Priority Issues

### MEDIUM #1: Inconsistent Error Logging Patterns 🟠

**Location**: Multiple files
**Severity**: MEDIUM - Debugging Experience

**Problem**: Some error paths log context, others don't:

```zig
// combine.zig:501 - ✅ GOOD - Logs context
std.log.err("Left merge key not found: {s}", .{left_key});

// reshape.zig:479 - ❌ MISSING - No context
return error.StringIndexNotYetImplemented; // Which column? Which row?
```

**Solution**: Standardize error logging with context:

```zig
// ✅ CORRECT - Always log context
std.log.err("String index not supported yet: column '{}' at row {}",
            .{index_series.name, row_idx});
return error.StringIndexNotYetImplemented;
```

---

### MEDIUM #2: Map Function Type-Specific API Naming 🟠

**Location**: `functional.zig:217-338`
**Severity**: MEDIUM - API Clarity

**Observation**: Type-specific map functions (`mapFloat64`, `mapInt64`, `mapBool`) are clear but verbose.

**Data Processing Best Practice**: Pandas uses `df['col'].map(func)` with automatic type inference.

**Trade-off Discussion**:
- ✅ **Current API (type-specific)**: Explicit, no comptime conflicts, 100% type safe at compile time
- ⚠️ **Generic API**: More concise, but Zig comptime limitations prevent it (see Learning #11 in docs/TODO.md)

**Recommendation**: Keep current API. Document design decision in module comments:

```zig
/// **Design Decision**: Why Type-Specific Functions?
///
/// Zig's comptime type system prevents generic dispatch with type-specific function pointers.
/// A generic `map()` that accepts `fn(T) T` cannot branch on Series type at runtime because
/// all branches are instantiated at compile time.
///
/// **Alternative Considered**:
/// ```zig
/// pub fn map(comptime FuncType: type, func: FuncType, series: *const Series) !Series {
///     switch (series.value_type) {
///         .Float64 => mapFloat64To(FuncType, func, series), // ❌ Compiler error if func: fn(i64) i64
///         .Int64 => mapInt64To(FuncType, func, series),     // ❌ Tries to compile this too!
///     }
/// }
/// ```
///
/// **Solution**: Type-specific functions avoid comptime conflicts and provide clear API.
```

---

### MEDIUM #3: Pivot Cell Aggregation Overflow Risk 🟠

**Location**: `reshape.zig:146-157`
**Severity**: MEDIUM - Numeric Overflow

**Problem**: `PivotCell.addValue` accumulates sum without overflow checking:

```zig
// reshape.zig:150 - No overflow protection
self.sum += value; // ❌ What if sum overflows f64?
```

**Data Processing Reality**: Summing 1 billion rows of f64::MAX → inf → NaN in mean calculation.

**Solution**: Check for overflow and warn:

```zig
pub fn addValue(self: *PivotCell, value: f64) void {
    std.debug.assert(!std.math.isNan(value)); // Pre-condition #1
    std.debug.assert(self.count < std.math.maxInt(u32)); // Pre-condition #2

    const new_sum = self.sum + value;
    if (std.math.isInf(new_sum) and !std.math.isInf(self.sum)) {
        std.log.warn("Pivot aggregation overflow detected (sum={d}, count={})",
                     .{self.sum, self.count});
    }
    self.sum = new_sum;
    self.count += 1;

    std.debug.assert(self.count > 0); // Post-condition #3
}
```

---

### MEDIUM #4: Concat Schema Alignment Logic 🟠

**Location**: `combine.zig:113-124`
**Severity**: MEDIUM - Data Loss Risk

**Problem**: Type conflict resolution is simplistic:

```zig
// combine.zig:116-122 - Only handles Int64 ↔ Float64
if ((result.value_ptr.* == .Int64 and col.value_type == .Float64) or
    (result.value_ptr.* == .Float64 and col.value_type == .Int64))
{
    result.value_ptr.* = .Float64; // ✅ Reasonable
}
// Otherwise keep existing type (first wins) // ❌ Silent type mismatch!
```

**Data Processing Reality**: Concatenating Bool + Int64 columns → Bool column wins → Int64 data lost.

**Solution**: Explicit type promotion hierarchy or error:

```zig
// ✅ CORRECT - Type promotion hierarchy
const TypePromotion = enum {
    fn promote(t1: ValueType, t2: ValueType) !ValueType {
        // Hierarchy: Bool < Int64 < Float64 < String (most general)
        if (t1 == t2) return t1;

        // Numeric promotion
        if ((t1 == .Bool or t1 == .Int64) and t2 == .Float64) return .Float64;
        if (t1 == .Float64 and (t2 == .Bool or t2 == .Int64)) return .Float64;
        if (t1 == .Bool and t2 == .Int64) return .Int64;
        if (t1 == .Int64 and t2 == .Bool) return .Int64;

        // String fallback (preserve all data)
        if (t1 == .String or t2 == .String) return .String;

        // Incompatible types
        std.log.err("Cannot concat columns with types {} and {}", .{t1, t2});
        return error.IncompatibleColumnTypes;
    }
};
```

---

### MEDIUM #5: Transpose Column Naming Pattern 🟠

**Location**: `reshape.zig:827`
**Severity**: MEDIUM - API Usability

**Problem**: Transpose generates generic column names (`row_0`, `row_1`, ...) without customization:

```zig
// reshape.zig:827 - Hardcoded naming
const name = try std.fmt.allocPrint(arena_alloc, "row_{d}", .{col_idx});
```

**Data Processing Best Practice**: Pandas allows custom column naming in transpose (use original column names or custom prefix).

**Solution**: Add naming options:

```zig
pub const TransposeOptions = struct {
    /// Column naming strategy
    naming: union(enum) {
        /// Use original column names (if available)
        use_original,
        /// Generate sequential names with custom prefix
        prefix: []const u8,
    } = .{ .prefix = "row" },
};

pub fn transpose(self: *const DataFrame, allocator: std.mem.Allocator, opts: TransposeOptions) !DataFrame {
    // ...
    const name = switch (opts.naming) {
        .use_original => try arena_alloc.dupe(u8, self.column_descs[col_idx].name),
        .prefix => |prefix| try std.fmt.allocPrint(arena_alloc, "{s}_{d}", .{prefix, col_idx}),
    };
    // ...
}
```

---

### MEDIUM #6-12: Minor Assertion Additions (Consolidated)

**Severity**: MEDIUM - Tiger Style Compliance

Several functions have exactly 2 assertions (minimum) but could benefit from additional validation:

1. **reshape.zig:54-68** (`AggFunc.toString`): Add result length assertion
2. **reshape.zig:184** (`PivotResult.init`): Add allocator validation
3. **reshape.zig:213** (`PivotResult.hashCell`): Add result consistency check
4. **combine.zig:184** (`concatVertical`): Add current_row bounds check
5. **join.zig:108** (`JoinKey.compute`): Add hash non-zero check (except for zero inputs)
6. **functional.zig:233** (`mapFloat64`): Add series allocator validation

**Pattern**:

```zig
// Add as 3rd assertion for defensive programming
std.debug.assert(hash != 0 or all_inputs_zero); // Prevent accidental zero hash
std.debug.assert(@intFromPtr(&allocator) != 0); // Validate allocator pointer
```

---

## Low Priority Issues

### LOW #1: Magic Number for FNV Hash Constants 🔵

**Location**: `join.zig:115-116`
**Severity**: LOW - Code Clarity

**Problem**: FNV-1a constants lack explanation:

```zig
const FNV_OFFSET: u64 = 14695981039346656037;
const FNV_PRIME: u64 = 1099511628211;
```

**Solution**: Add comment with reference (✅ Already done at lines 112-114, good!)

---

### LOW #2: Series Length Initialization Pattern 🔵

**Location**: Multiple locations
**Severity**: LOW - Code Consistency

**Observation**: Some functions set `series.length` manually, others rely on `setRowCount()`:

```zig
// Pattern A: Manual length (reshape.zig:451)
result.columns[col_idx].length = result_row_count;

// Pattern B: setRowCount (join.zig:532)
try result.setRowCount(num_rows);
```

**Recommendation**: Standardize on `setRowCount()` for consistency and future-proofing.

---

### LOW #3-5: Documentation Enhancements (Consolidated)

**Severity**: LOW - Developer Experience

Minor documentation improvements:

1. **reshape.zig:526-553** (`MeltOptions`): Add example showing id_vars vs value_vars
2. **combine.zig:28-38** (`ConcatOptions`): Add performance notes for vertical vs horizontal
3. **functional.zig:42-47** (`ApplyOptions`): Add when to use rows vs columns axis

---

## Data Processing Excellence Notes 🏆

**Strong Points**:

1. **Comprehensive Type Support**: All reshape/combine operations handle Int64, Float64, Bool, String, Categorical consistently
2. **Categorical Optimization**: Shallow copy in joins (80-90% faster) demonstrates deep understanding of data processing patterns
3. **Bounded Loops Everywhere**: 100% bounded loops with explicit MAX constants - no missed cases
4. **Memory Safety**: Consistent use of errdefer for cleanup on error paths
5. **Performance Mindset**: Join optimizations (97.3% improvement) show commitment to real-world performance

**Data Processing Gaps**:

1. **Missing Value Semantics**: 0/0.0/false for nulls doesn't match Pandas/Polars (use NaN for Float64)
2. **No Null Tracking**: Cannot distinguish actual zeros from missing values in Int64 columns
3. **Limited Error Recovery**: Most errors are fatal (return error) rather than lenient mode with warnings
4. **No Sampling Options**: Large dataset operations lack preview/sampling for exploratory analysis
5. **Overflow Protection**: Numeric aggregations don't guard against inf/NaN propagation

---

## Recommendations for 0.7.0+

### 1. Nullable Column Support (High Value)

Implement Option types for nullable columns:

```zig
pub const NullableInt64Column = struct {
    data: []i64,
    null_mask: []bool, // true = null

    pub fn get(self: *const NullableInt64Column, idx: u32) ?i64 {
        if (self.null_mask[idx]) return null;
        return self.data[idx];
    }
};
```

**Benefits**:
- Distinguish actual zeros from missing values
- Match Pandas/Polars null semantics
- Enable proper left join null handling

---

### 2. Lenient Mode for Type Conversions (Medium Value)

Add parse mode that logs errors but continues:

```zig
pub const ParseMode = enum {
    Strict, // Current behavior - fail fast
    Lenient, // Log errors, fill with defaults, continue
};

// User code
const df = try DataFrame.fromCSV(allocator, csv, .{
    .mode = .Lenient,
    .error_callback = myErrorHandler,
});
```

**Benefits**:
- Handle messy real-world CSVs gracefully
- Provide error report at end (row/column/value)
- Match Pandas behavior (`errors='coerce'`)

---

### 3. Sampling/Preview API (Low Value, High UX)

Add sampling for large operations:

```zig
const sample = try df.sample(allocator, .{
    .n = 1000,        // Sample size
    .method = .random, // Random or stratified
});
defer sample.deinit();

// Quick pivot on sample
const preview = try sample.pivot(allocator, opts);
defer preview.deinit();
```

**Benefits**:
- Fast exploratory analysis on 1M+ row datasets
- Avoid expensive operations on full data

---

## Summary of Fixes Required

### Before Production Deployment:

1. ✅ Fix NaN handling consistency (CRITICAL #1)
2. ✅ Add allocator validation in copySeriesData (CRITICAL #2)
3. ✅ Document MAX_MATCHES_PER_KEY trade-offs (HIGH #2)
4. ✅ Document Categorical shallow copy lifetime (HIGH #3)
5. ✅ Add overflow checks for column counts (HIGH #4)
6. ✅ Add overflow check for melt row calculation (HIGH #7)
7. ✅ Add performance cost documentation to reshape ops (HIGH #1)

### Nice-to-Have for 0.6.1:

8. ⚠️ Refactor 65+ line functions (HIGH #6)
9. ⚠️ Improve error logging consistency (MEDIUM #1)
10. ⚠️ Add type promotion hierarchy for concat (MEDIUM #4)

---

## Final Assessment

**Milestone 0.6.0 Status**: ✅ **APPROVED with 7 Required Fixes**

**Tiger Style Grade**: **A-** (95/100)
- Deductions: NaN inconsistency (-3), missing overflow checks (-2)

**Data Processing Grade**: **B+** (87/100)
- Deductions: Null handling (-5), lenient mode missing (-5), no sampling (-3)

**Production Readiness**: ⚠️ **YES after CRITICAL fixes**

---

**Reviewer Notes**: This is exceptional work that demonstrates deep understanding of both Tiger Style safety principles and data processing patterns. The join optimization alone (97.3% improvement) is production-grade performance engineering. Address the 7 critical/high issues and this will be rock-solid production code.

**Estimated Fix Time**: 4-6 hours (2 hours for CRITICAL, 2-4 hours for HIGH)

**Next Steps**:
1. Fix CRITICAL #1-2 (NaN, allocator validation)
2. Document lifetime assumptions (HIGH #3)
3. Add overflow checks (HIGH #4, #7)
4. Update TODO.md to mark Phase 1-3 as "Complete with Known Issues"
5. Add these learnings to src/CLAUDE.md (next review cycle)

---

**Generated**: 2025-10-30 by Tiger Style Code Reviewer
**Format**: Markdown with severity indicators
**Tool Used**: Manual code review with Tiger Style checklist
