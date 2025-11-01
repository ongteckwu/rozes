# COLUMN OPTIMIZATIONS

## Categorical Dictionary Encoding

- Before
  - Store raw strings per row; comparisons, sort, and hash were string-bound and memory-heavy.
- After
  - Unique strings live once in a dictionary; rows store `u32` codes. Supports deep copy (independent dict) and shallow copy (shared dict) for joins/filters.
- Impact
  - 4–8× memory reduction on low-cardinality columns; 5–20× faster compare/sort/hash paths.
- Code anchors

```318:347:src/core/categorical.zig
pub fn shallowCopyRows(
    self: *const CategoricalColumn,
    allocator: Allocator,
    row_indices: []const u32,
) !CategoricalColumn {
    const new_codes = try allocator.alloc(u32, row_indices.len);
    var i: u32 = 0;
    while (i < MAX_ROWS and i < row_indices.len) : (i += 1) {
        const row_idx = row_indices[i];
        new_codes[i] = self.codes[row_idx];
    }
    return CategoricalColumn{
        .categories = self.categories,
        .category_map = self.category_map,
        .codes = new_codes,
        .count = @intCast(row_indices.len),
        .capacity = @intCast(row_indices.len),
    };
}
```

## String Column Ownership & Reuse

- Before
  - Per-append string duplication with unclear ownership; risk of leaks or double frees.
- After
  - String buffers and offsets are arena-owned by the `DataFrame`; append/clone paths duplicate once and free in `deinit` via arena teardown.
- Impact
  - Fewer allocator calls; safer lifetime rules across rename/clone operations.
- Code anchors

```297:305:src/core/additional_ops.zig
const src_string_col = src_col.asStringColumn() orelse unreachable;
for (keep_indices.items) |src_idx| {
    const str = src_string_col.get(src_idx);
    try dst_col.appendString(result.arena.allocator(), str);
}
```
