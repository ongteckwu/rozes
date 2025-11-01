# EXECUTION OPTIMIZATIONS

## Concat & Append: Preallocated Copy

- Before
  - Row-wise appends with repeated reallocations and type surprises during promotion.
- After
  - Schema union + deterministic promotion first; allocate full destination; block copy per column; fill-missing with defaults.
- Impact
  - Stable throughput; predictable memory growth; fewer allocator calls.
- Code anchors

```121:129:src/core/combine.zig
fn concatVertical(
    allocator: Allocator,
    dataframes: []*const DataFrame,
    options: ConcatOptions,
) !DataFrame {
    _ = options; // schema union, total_rows, pre-alloc, then copy
}
```

```434:483:src/core/combine.zig
fn fillSeriesWithDefault(series: *Series, start: u32, count: u32) !void {
    // Type-specific defaults: 0, NaN, false, etc.
}
```

## Merge/Join: Hash Indexing

- Before
  - Nested-loop joins with O(n×m) scans and string concatenation per probe.
- After
  - Build right-side hash index (`StringHashMap` → rows); probe left; bounded linear probing; post-fill unmatched with defaults.
- Impact
  - O(n+m) behavior for common cases; bounded memory via `MAX_MATCHES_PER_KEY`.
- Code anchors

```565:633:src/core/combine.zig
fn buildHashKey(allocator: Allocator, df: *const DataFrame, row_idx: u32, key_columns: []const []const u8) ![]u8 { /* ... */ }
```

```646:675:src/core/combine.zig
// Right index build with cleanup and duplicate-key handling
var right_index = std.StringHashMap(std.ArrayList(u32)).init(allocator);
```

## Unique/DropDuplicates: Hash-first

- Before
  - Sort/dedup flows and repeated string work; poor cache behavior.
- After
  - Hash seen-values/rows; free duplicate keys immediately; stream results once.
- Impact
  - O(n) average behavior; lower peak memory via early frees.
- Code anchors

```55:86:src/core/additional_ops.zig
var seen = std.StringHashMap(void).init(allocator);
// Put once, free duplicates immediately
```
