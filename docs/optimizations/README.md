# Optimization Guide Overview

Roze's performance work is spread across multiple subsystems. Use this index to jump to the brief that explains why an optimization exists, how it works, and when to reach for it.

| Subsystem                | Primary Goals                        | Highlights                                                  | Deep Dive                                                              |
| ------------------------ | ------------------------------------ | ----------------------------------------------------------- | ---------------------------------------------------------------------- |
| DataFrame Core           | predictable memory, O(1) lookups     | arena-backed frames, column index cache, bounded invariants | [CORE_OPTIMIZATIONS.md](./CORE_OPTIMIZATIONS.md)                       |
| Column Implementations   | compressed storage, fast cloning     | categorical dictionary sharing, string arena reuse          | [COLUMN_OPTIMIZATIONS.md](./COLUMN_OPTIMIZATIONS.md)                   |
| Execution & Scheduling   | stable semantics, linear scalability | hash-based joins, copy-on-write helpers, schema promotion   | [EXECUTION_OPTIMIZATIONS.md](./EXECUTION_OPTIMIZATIONS.md)             |
| SIMD & Low-Level Kernels | CPU throughput                       | 4-wide reductions, SIMD-aware fallbacks, delimiter scanners | [SIMD_OPTIMIZATIONS.md](./SIMD_OPTIMIZATIONS.md)                       |
| String & Error Utilities | UX, hashing                          | fast hash + equality, guided error messages                 | [STRING_OPTIMIZATIONS.md](./STRING_OPTIMIZATIONS.md)                   |
| Window & Time-Series     | time-local analytics                 | capped window sizes, eager validation, future O(n) roadmap  | [WINDOW_OPTIMIZATIONS.md](./WINDOW_OPTIMIZATIONS.md)                   |
| Data Processing          | correctness, safe defaults           | NaN handling, type inference fallback, overflow checks      | [DATA_PROCESSING_OPTIMIZATIONS.md](./DATA_PROCESSING_OPTIMIZATIONS.md) |

## How to use this folder

- Each brief starts with a one-screen synopsis, then drills into the exact functions and constants that enforce the behavior.
- "Operational Guidance" sections explain how to enable or extend an optimization without violating invariants.
- When a change introduces new tuning knobs or benchmarks, record it in [CHANGELOG.md](./CHANGELOG.md).

## Core Optimization Principles

1. **Profile First** - Always measure before optimizing. Join optimization revealed data copying (40-60% of time), NOT hash operations
2. **Low-Hanging Fruit Priority** - ① Algorithmic improvements ② SIMD integration ③ Memory layout ④ Code elimination
3. **Benchmark Design** - Separate full pipeline (real-world) vs pure algorithm (optimization target). Example: Join 968ms (with CSV) vs 1.42ms (pure)
4. **Measure Everything** - Baseline → Expected → Actual → Correctness

## When to Optimize

**✅ DO optimize when:**

- Performance target missed (benchmark failing)
- Profiling identifies clear bottleneck
- Have time budget allocated

**❌ DON'T optimize when:**

- Tests failing (fix correctness first)
- No profiling data (would be guessing)
- Target already met (premature optimization)

## Legacy docs

`PERFORMANCE.md`, `QUERY_OPTIMIZATION.md`, and `STRING_OPTIMIZATIONS.md` remain for historical context. All new work should cite the subsystem briefs above and, if needed, link back to the legacy reports for the original data.
