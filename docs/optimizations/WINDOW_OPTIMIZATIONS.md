# WINDOW OPTIMIZATIONS

## Rolling Windows: From O(n×w) to O(n)

- Before
  - Naive rolling implementations recompute window sums/min/max per position, yielding O(n×w) time.
- After
  - Roadmap: slide accumulators (sum) in O(1) per step; maintain deque for min/max to achieve O(n). Current code documents the upgrade path.
- Impact
  - Expected 10–100× speedups for large windows once sliding variants land; current behavior is correct and bounded with `MAX_WINDOW_SIZE`.
- Code anchors (current behavior)

```47:97:src/core/window_ops.zig
pub fn sum(self: *const RollingWindow, allocator: Allocator) !Series {
    const len = self.series.length;
    const result_data = try allocator.alloc(f64, len);
    switch (self.series.valueType) {
        .Int64 => { /* nested loop: start..i */ },
        .Float64 => { /* nested loop: start..i */ },
        else => return error.UnsupportedType,
    }
    return Series{ .valueType = .Float64, .data = .{ .Float64 = result_data }, .length = len };
}
```

## Guardrails & Limits

- Before
  - Implicit assumptions about window sizes and series length.
- After
  - Explicit `MAX_WINDOW_SIZE`, strict assertions, and early errors for invalid windows; functions ≤70 lines to keep logic cache-friendly.
- Impact
  - Predictable failure modes; easier future optimization without changing external behavior.
