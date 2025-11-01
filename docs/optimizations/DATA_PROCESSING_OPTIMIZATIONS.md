# DATA PROCESSING OPTIMIZATIONS

## NaN Handling: Early Detection

- Before
  - NaN values propagated through aggregations causing incorrect results; comparisons failed silently.
- After
  - Check `std.math.isNan()` before comparison/aggregation; skip NaN values in sum/mean; explicit NaN handling in sort.
- Impact
  - Correct statistics and deterministic results; no silent failures.
- Code anchors

```zig
// Example: NaN-aware comparison
if (std.math.isNan(a) or std.math.isNan(b)) {
    // Handle NaN explicitly (push to end for sort, skip for aggregation)
}
```

## Type Inference: Safe Defaults

- Before
  - Parser errors on ambiguous types; no fallback for mixed columns.
- After
  - Default to String type (universal fallback); never error on type inference; explicit type conversion API for strictness.
- Impact
  - Robust CSV parsing; users can override with explicit schema if needed.
- Code anchors

```zig
// Always succeed with String fallback
if (all_int) return .Int64;
if (all_float) return .Float64;
if (all_bool) return .Bool;
return .String; // Universal fallback
```

## Overflow Checks: Wider Type Pattern

- Before
  - Arithmetic overflow caused silent wrapping or runtime panics.
- After
  - Check BEFORE arithmetic using wider type (u64 for u32 ops, i128 for i64 ops); return error on overflow.
- Impact
  - Explicit overflow errors instead of silent data corruption.
- Code anchors

```zig
// Safe multiplication with overflow check
const result_u64: u64 = @as(u64, a) * @as(u64, b);
if (result_u64 > std.math.maxInt(u32)) return error.Overflow;
const result: u32 = @intCast(result_u64);
```

## Silent Error Prevention

- Before
  - `catch return default_value` patterns silently hid allocation failures and parse errors.
- After
  - All errors propagate to caller; no default values on failure; document error conditions in API.
- Impact
  - Users aware of failures; no silent data loss or corruption.
- Code anchors

```zig
// ❌ WRONG - Silent failure
const names = allocator.alloc([]const u8, n) catch return &[_][]const u8{};

// ✅ CORRECT - Propagate error
pub fn columnNames(allocator: Allocator) ![]const []const u8 {
    return try allocator.alloc([]const u8, n);
}
```
