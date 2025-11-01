# CORE OPTIMIZATIONS

## Arena Lifetime Management

- Before
  - Scattered heap allocations per descriptor, series, and string made cloning and teardown expensive and fragmented memory.
- After
  - Single arena per `DataFrame` owns descriptors, series buffers, and duplicated names; deinit is O(1), clones copy schema predictably.
- Impact
  - Lower allocation count per frame; predictable frees; enables bulk operations without GC-like pauses.
- Code anchors

```92:140:src/core/dataframe.zig
pub fn create(
    allocator: std.mem.Allocator,
    columnDescs: []const ColumnDesc,
    capacity: u32,
) !DataFrame {
    // Arena init, descriptor/name dupes, column allocation
    var arena = std.heap.ArenaAllocator.init(allocator);
    const arena_allocator = arena.allocator();
    const descs = try arena_allocator.alloc(ColumnDesc, columnDescs.len);
    const cols = try arena_allocator.alloc(Series, columnDescs.len);
    // ...
}
```

## O(1) Column Lookup

- Before
  - Linear scans to find columns by name; repeated lookups in hot paths.
- After
  - `StringHashMapUnmanaged(u32)` caches name→index; helpers (`column`, `hasColumn`) resolve in O(1).
- Impact
  - Removes per-operator schema scan overhead; consistent across platforms.
- Code anchors

```211:220:src/core/dataframe.zig
pub fn columnIndex(self: *const DataFrame, name: []const u8) ?usize {
    const idx = self.column_index.get(name) orelse return null; // O(1) hash lookup
    return idx;
}
```

## Defensive Bounds (Tiger Style)

- Before
  - Ad-hoc checks; inconsistent limits across modules.
- After
  - Uniform `MAX_ROWS`/`MAX_COLS` invariants with pre/post assertions and bounded loops in all hot paths.
- Impact
  - Safer release builds; easier reasoning about worst-case behavior.
- Code anchors

```256:279:src/core/dataframe.zig
pub fn setRowCount(self: *DataFrame, count: u32) !void {
    if (count > MAX_ROWS) return error.TooManyRows;
    // Validate capacities and set lengths
}
```
