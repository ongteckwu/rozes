//! SIMD Utilities for High-Performance Data Processing
//!
//! This module provides SIMD-accelerated operations for:
//! - CSV field scanning (find delimiters, quotes)
//! - Numeric comparisons (sort operations)
//! - Aggregations (sum, mean, min, max, variance, stddev)
//! - Hash computations (join operations)
//!
//! ## SIMD Availability
//!
//! SIMD operations are available on:
//! - WebAssembly with SIMD support (Chrome 91+, Firefox 89+, Safari 16.4+, Node.js 16+)
//! - Native platforms with SSE2+ (x86_64), NEON (ARM64)
//!
//! ## Automatic Fallback Mechanism
//!
//! **All functions in this module have built-in fallback to scalar implementations.**
//!
//! Fallback occurs when:
//! 1. SIMD is not available on the platform (`simd_available = false`)
//! 2. Data size is too small (overhead > benefit, typically < 4-16 elements)
//! 3. Empty data (len = 0)
//!
//! Example fallback pattern (used in all functions):
//! ```zig
//! pub fn sumFloat64(data: []const f64) f64 {
//!     // Automatic fallback check
//!     if (!simd_available or data.len == 0) {
//!         return sumFloat64Scalar(data); // ✅ Fallback to scalar
//!     }
//!
//!     if (data.len < simd_width) {
//!         return sumFloat64Scalar(data); // ✅ Too small, use scalar
//!     }
//!
//!     // SIMD processing...
//! }
//! ```
//!
//! **Users do not need to check SIMD availability** - functions handle it internally.
//!
//! ## Performance Characteristics
//!
//! - SIMD speedup: 30-40% for aggregations, 2-4× for string operations
//! - Breakeven point: ~16-64 elements (varies by operation)
//! - Overhead: <1% on scalar fallback path
//!
//! See docs/TODO.md Phase 1 (Milestone 1.2.0) for benchmarks

const std = @import("std");
const builtin = @import("builtin");

/// SIMD vector size for byte operations (16 bytes = 128 bits)
pub const SIMD_WIDTH = 16;

/// Check if SIMD is available at compile time
pub const simd_available = blk: {
    // WebAssembly SIMD
    if (builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64) {
        // For WASM, assume SIMD support (browsers from 2021+)
        // WASM SIMD is optional in Zig, but widely supported
        // TODO: Add runtime feature detection if needed
        break :blk true;
    }
    // x86_64 with SSE2 (standard since 2003)
    if (builtin.cpu.arch == .x86_64) {
        break :blk true;
    }
    // ARM64 with NEON (standard)
    if (builtin.cpu.arch == .aarch64) {
        break :blk true;
    }
    // Fallback for other architectures
    break :blk false;
};

/// CSV Field Scanner - Find next delimiter or quote using SIMD
///
/// **Performance**:
/// - Scalar: 1 character per iteration
/// - SIMD: 16 characters per iteration (16× throughput)
/// - Expected speedup: 8-12× for fields >32 bytes (due to loop overhead)
///
/// **Algorithm**:
/// 1. Load 16 bytes from buffer
/// 2. Compare against delimiter vector (16 copies of ',')
/// 3. Compare against quote vector (16 copies of '"')
/// 4. Check if any byte matches using @reduce(.Or, ...)
/// 5. If match found, fall back to scalar to find exact position
/// 6. If no match, skip 16 bytes and repeat
///
/// **Usage**:
/// ```zig
/// const buffer = "hello,world,\"quoted\",end";
/// const start = 0;
/// const delimiter = ',';
/// const quote = '"';
///
/// const next_special = findNextSpecialChar(buffer, start, delimiter, quote);
/// // Returns index of next ',' or '"', or buffer.len if none found
/// ```
pub fn findNextSpecialChar(
    buffer: []const u8,
    start: u32,
    delimiter: u8,
    quote: u8,
) u32 {
    std.debug.assert(start <= buffer.len); // Pre-condition #1
    std.debug.assert(delimiter != 0); // Pre-condition #2: Valid delimiter
    std.debug.assert(quote != 0); // Pre-condition #3: Valid quote

    if (!simd_available) {
        return findNextSpecialCharScalar(buffer, start, delimiter, quote);
    }

    const buffer_len: u32 = @intCast(buffer.len);
    std.debug.assert(start <= buffer_len); // Pre-condition #4: Valid start

    var pos = start;

    // Process 16-byte chunks with SIMD
    const MAX_ITERATIONS: u32 = 1_000_000_000 / SIMD_WIDTH; // 1GB / 16 bytes
    var iterations: u32 = 0;

    while (pos + SIMD_WIDTH <= buffer_len and iterations < MAX_ITERATIONS) : (iterations += 1) {
        // Load 16 bytes
        const chunk: @Vector(SIMD_WIDTH, u8) = buffer[pos..][0..SIMD_WIDTH].*;

        // Create comparison vectors
        const delimiters = @as(@Vector(SIMD_WIDTH, u8), @splat(delimiter));
        const quotes = @as(@Vector(SIMD_WIDTH, u8), @splat(quote));

        // Compare all 16 bytes at once
        const is_delimiter = chunk == delimiters;
        const is_quote = chunk == quotes;

        // Check if any byte matches
        const has_delimiter = @reduce(.Or, is_delimiter);
        const has_quote = @reduce(.Or, is_quote);

        if (has_delimiter or has_quote) {
            // Found a match - use scalar to find exact position
            std.debug.assert(pos + SIMD_WIDTH <= buffer.len); // Invariant
            return findNextSpecialCharScalar(buffer, pos, delimiter, quote);
        }

        pos += SIMD_WIDTH;
    }

    std.debug.assert(iterations <= MAX_ITERATIONS); // Post-condition

    // Process remaining bytes (< 16) with scalar
    return findNextSpecialCharScalar(buffer, pos, delimiter, quote);
}

/// Scalar fallback for finding next delimiter or quote
///
/// Used when:
/// - SIMD not available
/// - Remaining bytes < 16
/// - SIMD found a match in chunk (need exact position)
fn findNextSpecialCharScalar(
    buffer: []const u8,
    start: u32,
    delimiter: u8,
    quote: u8,
) u32 {
    std.debug.assert(start <= buffer.len); // Pre-condition #1
    std.debug.assert(delimiter != 0); // Pre-condition #2

    const buffer_len: u32 = @intCast(buffer.len);
    std.debug.assert(start <= buffer_len); // Pre-condition #3: Valid start

    const MAX_SCAN: u32 = 1_000_000; // Max 1MB field
    var pos = start;
    var iterations: u32 = 0;

    while (pos < buffer_len and iterations < MAX_SCAN) : (iterations += 1) {
        const char = buffer[pos];
        if (char == delimiter or char == quote) {
            std.debug.assert(pos < buffer_len); // Post-condition #1
            return pos;
        }
        pos += 1;
    }

    std.debug.assert(iterations <= MAX_SCAN); // Post-condition #2
    std.debug.assert(pos <= buffer_len); // Post-condition #3

    return buffer_len; // Not found
}

/// SIMD Float64 Comparisons for Sort Operations
///
/// **Performance**:
/// - Scalar: 1 comparison per iteration
/// - SIMD: 2-4 comparisons per iteration (2-4× throughput)
/// - Expected speedup: 2-3× for sort operations (due to loop overhead and branching)
///
/// **Algorithm**:
/// 1. Load 2 Float64 values (128 bits) into SIMD vector
/// 2. Compare using vector comparison (`<`, `>`, `==`)
/// 3. Extract comparison results
/// 4. Fall back to scalar for remaining elements
///
/// **Usage**: Used by sort module for comparing Float64 columns
pub fn compareFloat64Batch(
    data_a: []const f64,
    data_b: []const f64,
    results: []std.math.Order,
) void {
    std.debug.assert(data_a.len == data_b.len); // Pre-condition #1
    std.debug.assert(data_a.len == results.len); // Pre-condition #2
    std.debug.assert(data_a.len <= 1_000_000_000); // Pre-condition #3: Reasonable limit

    if (!simd_available) {
        return compareFloat64BatchScalar(data_a, data_b, results);
    }

    var i: u32 = 0;
    const simd_width: u32 = 2; // Process 2 f64 values per iteration (128 bits)
    const data_len: u32 = @intCast(data_a.len);

    std.debug.assert(data_len <= 1_000_000_000); // Pre-condition: Reasonable limit

    // Process in pairs using SIMD
    const MAX_ITERATIONS: u32 = 500_000_000; // 1B / 2
    var iterations: u32 = 0;

    while (i + simd_width <= data_len and iterations < MAX_ITERATIONS) : (iterations += 1) {
        const vec_a = @Vector(simd_width, f64){ data_a[i], data_a[i + 1] };
        const vec_b = @Vector(simd_width, f64){ data_b[i], data_b[i + 1] };

        // SIMD comparison
        const lt = vec_a < vec_b;
        const gt = vec_a > vec_b;

        // Extract results
        results[i] = if (lt[0]) .lt else if (gt[0]) .gt else .eq;
        results[i + 1] = if (lt[1]) .lt else if (gt[1]) .gt else .eq;

        i += simd_width;
    }

    std.debug.assert(iterations <= MAX_ITERATIONS); // Post-condition #1

    // Process remaining elements with scalar
    while (i < data_len) : (i += 1) {
        results[i] = std.math.order(data_a[i], data_b[i]);
    }

    std.debug.assert(i == data_len); // Post-condition #2
}

/// Scalar fallback for Float64 batch comparison
fn compareFloat64BatchScalar(
    data_a: []const f64,
    data_b: []const f64,
    results: []std.math.Order,
) void {
    std.debug.assert(data_a.len == data_b.len); // Pre-condition #1
    std.debug.assert(data_a.len == results.len); // Pre-condition #2

    const MAX_COMPARISONS: u32 = 1_000_000_000; // 1B comparisons max
    var i: u32 = 0;

    while (i < data_a.len and i < MAX_COMPARISONS) : (i += 1) {
        results[i] = std.math.order(data_a[i], data_b[i]);
    }

    std.debug.assert(i == data_a.len or i == MAX_COMPARISONS); // Post-condition
}

/// SIMD Int64 Comparisons for Sort Operations
///
/// **Performance**: Same as Float64 (2-4× throughput)
///
/// **Usage**: Used by sort module for comparing Int64 columns
pub fn compareInt64Batch(
    data_a: []const i64,
    data_b: []const i64,
    results: []std.math.Order,
) void {
    std.debug.assert(data_a.len == data_b.len); // Pre-condition #1
    std.debug.assert(data_a.len == results.len); // Pre-condition #2
    std.debug.assert(data_a.len <= 1_000_000_000); // Pre-condition #3

    if (!simd_available) {
        return compareInt64BatchScalar(data_a, data_b, results);
    }

    var i: u32 = 0;
    const simd_width: u32 = 2; // Process 2 i64 values per iteration (128 bits)
    const data_len: u32 = @intCast(data_a.len);

    std.debug.assert(data_len <= 1_000_000_000); // Pre-condition: Reasonable limit

    const MAX_ITERATIONS: u32 = 500_000_000; // 1B / 2
    var iterations: u32 = 0;

    while (i + simd_width <= data_len and iterations < MAX_ITERATIONS) : (iterations += 1) {
        const vec_a = @Vector(simd_width, i64){ data_a[i], data_a[i + 1] };
        const vec_b = @Vector(simd_width, i64){ data_b[i], data_b[i + 1] };

        // SIMD comparison
        const lt = vec_a < vec_b;
        const gt = vec_a > vec_b;

        // Extract results
        results[i] = if (lt[0]) .lt else if (gt[0]) .gt else .eq;
        results[i + 1] = if (lt[1]) .lt else if (gt[1]) .gt else .eq;

        i += simd_width;
    }

    std.debug.assert(iterations <= MAX_ITERATIONS); // Post-condition #1

    // Process remaining elements with scalar
    while (i < data_len) : (i += 1) {
        results[i] = std.math.order(data_a[i], data_b[i]);
    }

    std.debug.assert(i == data_len); // Post-condition #2
}

/// Scalar fallback for Int64 batch comparison
fn compareInt64BatchScalar(
    data_a: []const i64,
    data_b: []const i64,
    results: []std.math.Order,
) void {
    std.debug.assert(data_a.len == data_b.len); // Pre-condition #1
    std.debug.assert(data_a.len == results.len); // Pre-condition #2

    const MAX_COMPARISONS: u32 = 1_000_000_000; // 1B comparisons max
    var i: u32 = 0;

    while (i < data_a.len and i < MAX_COMPARISONS) : (i += 1) {
        results[i] = std.math.order(data_a[i], data_b[i]);
    }

    std.debug.assert(i == data_a.len or i == MAX_COMPARISONS); // Post-condition
}

/// SIMD Float64 Sum with Horizontal Reduction
///
/// **Performance**:
/// - Scalar: 1 addition per iteration
/// - SIMD: 2-4 additions per iteration (2-4× throughput)
/// - Expected speedup: 30-40% for arrays >100 elements (due to horizontal reduction overhead)
///
/// **Algorithm**:
/// 1. **Automatic fallback**: Checks `simd_available`, returns scalar if unavailable or data < 4 elements
/// 2. Process 4 f64 values per iteration using SIMD vectors (256 bits / AVX)
/// 3. Accumulate in SIMD registers
/// 4. Horizontal reduction to combine vector lanes
/// 5. Handle remaining elements with scalar
///
/// **Fallback**: Automatically falls back to `sumFloat64Scalar()` if SIMD unavailable or data too small.
/// Users do not need to check SIMD availability.
///
/// **Usage**: Used for DataFrame aggregations (sum, mean)
pub fn sumFloat64(data: []const f64) f64 {
    std.debug.assert(data.len <= 4_000_000_000); // Pre-condition: Reasonable limit

    if (!simd_available or data.len == 0) {
        return sumFloat64Scalar(data);
    }

    // Use 4-wide SIMD vectors for better performance
    const simd_width: u32 = 4;
    const data_len: u32 = @intCast(data.len);

    std.debug.assert(data_len <= 4_000_000_000); // Pre-condition: Reasonable limit

    if (data_len < simd_width) {
        return sumFloat64Scalar(data);
    }

    var vec_sum = @Vector(simd_width, f64){ 0.0, 0.0, 0.0, 0.0 };
    var i: u32 = 0;

    const MAX_ITERATIONS: u32 = 1_000_000_000; // 4B / 4
    var iterations: u32 = 0;

    // Process 4 f64 values per iteration
    while (i + simd_width <= data_len and iterations < MAX_ITERATIONS) : (iterations += 1) {
        const vec = @Vector(simd_width, f64){
            data[i],
            data[i + 1],
            data[i + 2],
            data[i + 3],
        };
        vec_sum += vec;
        i += simd_width;
    }

    std.debug.assert(iterations <= MAX_ITERATIONS); // Post-condition #1

    // Horizontal reduction: sum all lanes
    var sum = vec_sum[0] + vec_sum[1] + vec_sum[2] + vec_sum[3];

    // Process remaining elements with scalar
    while (i < data_len) : (i += 1) {
        sum += data[i];
    }

    std.debug.assert(i == data_len); // Post-condition #2

    return sum;
}

/// Scalar fallback for Float64 sum
fn sumFloat64Scalar(data: []const f64) f64 {
    std.debug.assert(data.len <= 4_000_000_000); // Pre-condition

    var sum: f64 = 0.0;
    const MAX_ITERATIONS: u32 = 4_000_000_000;
    var i: u32 = 0;

    while (i < data.len and i < MAX_ITERATIONS) : (i += 1) {
        sum += data[i];
    }

    std.debug.assert(i == data.len or i == MAX_ITERATIONS); // Post-condition
    return sum;
}

/// SIMD Int64 Sum with Horizontal Reduction
///
/// **Performance**: Same as Float64 (30-40% speedup)
///
/// **Usage**: Used for DataFrame aggregations (sum, mean) on integer columns
pub fn sumInt64(data: []const i64) i64 {
    std.debug.assert(data.len <= 4_000_000_000); // Pre-condition: Reasonable limit

    if (!simd_available or data.len == 0) {
        return sumInt64Scalar(data);
    }

    const simd_width: u32 = 4;
    const data_len: u32 = @intCast(data.len);

    std.debug.assert(data_len <= 4_000_000_000); // Pre-condition: Reasonable limit

    if (data_len < simd_width) {
        return sumInt64Scalar(data);
    }

    var vec_sum = @Vector(simd_width, i64){ 0, 0, 0, 0 };
    var i: u32 = 0;

    const MAX_ITERATIONS: u32 = 1_000_000_000; // 4B / 4
    var iterations: u32 = 0;

    // Process 4 i64 values per iteration
    while (i + simd_width <= data_len and iterations < MAX_ITERATIONS) : (iterations += 1) {
        const vec = @Vector(simd_width, i64){
            data[i],
            data[i + 1],
            data[i + 2],
            data[i + 3],
        };
        vec_sum += vec;
        i += simd_width;
    }

    std.debug.assert(iterations <= MAX_ITERATIONS); // Post-condition #1

    // Horizontal reduction: sum all lanes
    var sum = vec_sum[0] + vec_sum[1] + vec_sum[2] + vec_sum[3];

    // Process remaining elements with scalar
    while (i < data_len) : (i += 1) {
        sum += data[i];
    }

    std.debug.assert(i == data_len); // Post-condition #2

    return sum;
}

/// Scalar fallback for Int64 sum
fn sumInt64Scalar(data: []const i64) i64 {
    std.debug.assert(data.len <= 4_000_000_000); // Pre-condition

    var sum: i64 = 0;
    const MAX_ITERATIONS: u32 = 4_000_000_000;
    var i: u32 = 0;

    while (i < data.len and i < MAX_ITERATIONS) : (i += 1) {
        sum += data[i];
    }

    std.debug.assert(i == data.len or i == MAX_ITERATIONS); // Post-condition
    return sum;
}

/// SIMD Float64 Mean (uses sumFloat64)
///
/// **Performance**: Same as sumFloat64 (30-40% speedup)
///
/// **Usage**: DataFrame.mean() operation
pub fn meanFloat64(data: []const f64) ?f64 {
    std.debug.assert(data.len <= 4_000_000_000); // Pre-condition

    if (data.len == 0) return null;

    const sum = sumFloat64(data);
    return sum / @as(f64, @floatFromInt(data.len));
}

/// SIMD Int64 Mean (uses sumInt64)
///
/// **Performance**: Same as sumInt64 (30-40% speedup)
///
/// **Usage**: DataFrame.mean() operation on integer columns
pub fn meanInt64(data: []const i64) ?f64 {
    std.debug.assert(data.len <= 4_000_000_000); // Pre-condition

    if (data.len == 0) return null;

    const sum = sumInt64(data);
    return @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(data.len));
}

/// SIMD Float64 Min with Vector Comparisons
///
/// **Performance**:
/// - Scalar: 1 comparison per iteration
/// - SIMD: 4 comparisons per iteration (4× throughput)
/// - Expected speedup: 30-40% for arrays >100 elements
///
/// **Algorithm**:
/// 1. **Automatic fallback**: Checks `simd_available`, returns scalar if unavailable
/// 2. Process 4 f64 values per iteration
/// 3. Use SIMD min operation
/// 4. Horizontal reduction to find minimum
///
/// **Fallback**: Automatically falls back to `minFloat64Scalar()` if SIMD unavailable.
///
/// **Usage**: DataFrame.min() operation
pub fn minFloat64(data: []const f64) ?f64 {
    std.debug.assert(data.len <= 4_000_000_000); // Pre-condition

    if (data.len == 0) return null;

    if (!simd_available) {
        return minFloat64Scalar(data);
    }

    const simd_width: u32 = 4;
    const data_len: u32 = @intCast(data.len);

    std.debug.assert(data_len <= 4_000_000_000); // Pre-condition: Reasonable limit

    if (data_len < simd_width) {
        return minFloat64Scalar(data);
    }

    // Initialize with first 4 values
    var vec_min = @Vector(simd_width, f64){
        data[0],
        data[1],
        data[2],
        data[3],
    };

    var i: u32 = simd_width;
    const MAX_ITERATIONS: u32 = 1_000_000_000;
    var iterations: u32 = 0;

    // Process remaining values
    while (i + simd_width <= data_len and iterations < MAX_ITERATIONS) : (iterations += 1) {
        const vec = @Vector(simd_width, f64){
            data[i],
            data[i + 1],
            data[i + 2],
            data[i + 3],
        };
        vec_min = @min(vec_min, vec);
        i += simd_width;
    }

    std.debug.assert(iterations <= MAX_ITERATIONS); // Post-condition #1

    // Horizontal reduction: find minimum across lanes
    var min_val = @min(@min(vec_min[0], vec_min[1]), @min(vec_min[2], vec_min[3]));

    // Process remaining elements
    while (i < data_len) : (i += 1) {
        min_val = @min(min_val, data[i]);
    }

    std.debug.assert(i == data_len); // Post-condition #2

    return min_val;
}

/// Scalar fallback for Float64 min
fn minFloat64Scalar(data: []const f64) ?f64 {
    std.debug.assert(data.len > 0); // Pre-condition
    std.debug.assert(data.len <= 4_000_000_000);

    var min_val = data[0];
    const MAX_ITERATIONS: u32 = 4_000_000_000;
    var i: u32 = 1;

    while (i < data.len and i < MAX_ITERATIONS) : (i += 1) {
        min_val = @min(min_val, data[i]);
    }

    std.debug.assert(i == data.len or i == MAX_ITERATIONS); // Post-condition
    return min_val;
}

/// SIMD Float64 Max with Vector Comparisons
///
/// **Performance**: Same as minFloat64 (30-40% speedup)
///
/// **Fallback**: Automatically falls back to `maxFloat64Scalar()` if SIMD unavailable.
///
/// **Usage**: DataFrame.max() operation
pub fn maxFloat64(data: []const f64) ?f64 {
    std.debug.assert(data.len <= 4_000_000_000); // Pre-condition

    if (data.len == 0) return null;

    if (!simd_available) {
        return maxFloat64Scalar(data);
    }

    const simd_width: u32 = 4;
    const data_len: u32 = @intCast(data.len);

    std.debug.assert(data_len <= 4_000_000_000); // Pre-condition: Reasonable limit

    if (data_len < simd_width) {
        return maxFloat64Scalar(data);
    }

    // Initialize with first 4 values
    var vec_max = @Vector(simd_width, f64){
        data[0],
        data[1],
        data[2],
        data[3],
    };

    var i: u32 = simd_width;
    const MAX_ITERATIONS: u32 = 1_000_000_000;
    var iterations: u32 = 0;

    // Process remaining values
    while (i + simd_width <= data_len and iterations < MAX_ITERATIONS) : (iterations += 1) {
        const vec = @Vector(simd_width, f64){
            data[i],
            data[i + 1],
            data[i + 2],
            data[i + 3],
        };
        vec_max = @max(vec_max, vec);
        i += simd_width;
    }

    std.debug.assert(iterations <= MAX_ITERATIONS); // Post-condition #1

    // Horizontal reduction: find maximum across lanes
    var max_val = @max(@max(vec_max[0], vec_max[1]), @max(vec_max[2], vec_max[3]));

    // Process remaining elements
    while (i < data_len) : (i += 1) {
        max_val = @max(max_val, data[i]);
    }

    std.debug.assert(i == data_len); // Post-condition #2

    return max_val;
}

/// Scalar fallback for Float64 max
fn maxFloat64Scalar(data: []const f64) ?f64 {
    std.debug.assert(data.len > 0); // Pre-condition
    std.debug.assert(data.len <= 4_000_000_000);

    var max_val = data[0];
    const MAX_ITERATIONS: u32 = 4_000_000_000;
    var i: u32 = 1;

    while (i < data.len and i < MAX_ITERATIONS) : (i += 1) {
        max_val = @max(max_val, data[i]);
    }

    std.debug.assert(i == data.len or i == MAX_ITERATIONS); // Post-condition
    return max_val;
}

/// SIMD Float64 Variance (Sample Variance with n-1)
///
/// **Performance**:
/// - Scalar: 2 passes (mean + squared differences)
/// - SIMD: 2 passes with 4-wide vectors (30-40% speedup)
/// - Expected speedup: 30-40% for arrays >100 elements
///
/// **Algorithm**:
/// 1. Compute mean using SIMD (first pass) - delegates to `meanFloat64()`
/// 2. Compute sum of squared differences using SIMD (second pass)
/// 3. Divide by n-1 (sample variance, unbiased estimator)
///
/// **Fallback**: Automatically falls back to scalar implementation if SIMD unavailable
/// (via `meanFloat64()` which checks `simd_available`).
///
/// **Usage**: DataFrame.variance() operation
pub fn varianceFloat64(data: []const f64) ?f64 {
    std.debug.assert(data.len <= 4_000_000_000); // Pre-condition

    if (data.len == 0) return null;
    if (data.len == 1) return 0.0; // Single value has zero variance

    // Step 1: Compute mean using SIMD
    const mean = meanFloat64(data) orelse return null;

    // Step 2: Compute sum of squared differences using SIMD
    if (!simd_available) {
        return varianceFloat64Scalar(data, mean);
    }

    const simd_width: u32 = 4;
    const data_len: u32 = @intCast(data.len);

    std.debug.assert(data_len <= 4_000_000_000); // Pre-condition: Reasonable limit

    if (data_len < simd_width) {
        return varianceFloat64Scalar(data, mean);
    }

    var vec_sum_sq_diff = @Vector(simd_width, f64){ 0.0, 0.0, 0.0, 0.0 };
    const vec_mean = @Vector(simd_width, f64){ mean, mean, mean, mean };

    var i: u32 = 0;
    const MAX_ITERATIONS: u32 = 1_000_000_000;
    var iterations: u32 = 0;

    // Process 4 f64 values per iteration
    while (i + simd_width <= data_len and iterations < MAX_ITERATIONS) : (iterations += 1) {
        const vec = @Vector(simd_width, f64){
            data[i],
            data[i + 1],
            data[i + 2],
            data[i + 3],
        };

        const diff = vec - vec_mean;
        vec_sum_sq_diff += diff * diff;
        i += simd_width;
    }

    std.debug.assert(iterations <= MAX_ITERATIONS); // Post-condition #1

    // Horizontal reduction: sum all lanes
    var sum_sq_diff = vec_sum_sq_diff[0] + vec_sum_sq_diff[1] + vec_sum_sq_diff[2] + vec_sum_sq_diff[3];

    // Process remaining elements with scalar
    while (i < data_len) : (i += 1) {
        const diff = data[i] - mean;
        sum_sq_diff += diff * diff;
    }

    std.debug.assert(i == data_len); // Post-condition #2

    // Sample variance: divide by (n-1) for unbiased estimator
    return sum_sq_diff / @as(f64, @floatFromInt(data_len - 1));
}

/// Scalar fallback for Float64 variance
fn varianceFloat64Scalar(data: []const f64, mean: f64) f64 {
    std.debug.assert(data.len > 1); // Pre-condition (checked in caller)
    std.debug.assert(data.len <= 4_000_000_000);

    var sum_sq_diff: f64 = 0.0;
    const MAX_ITERATIONS: u32 = 4_000_000_000;
    var i: u32 = 0;

    while (i < data.len and i < MAX_ITERATIONS) : (i += 1) {
        const diff = data[i] - mean;
        sum_sq_diff += diff * diff;
    }

    std.debug.assert(i == data.len or i == MAX_ITERATIONS); // Post-condition
    return sum_sq_diff / @as(f64, @floatFromInt(data.len - 1));
}

/// SIMD Float64 Standard Deviation (uses varianceFloat64)
///
/// **Performance**: Same as varianceFloat64 (30-40% speedup)
///
/// **Usage**: DataFrame.stddev() operation
pub fn stdDevFloat64(data: []const f64) ?f64 {
    std.debug.assert(data.len <= 4_000_000_000); // Pre-condition

    const variance = varianceFloat64(data) orelse return null;
    std.debug.assert(variance >= 0.0); // Variance is non-negative

    return @sqrt(variance);
}

// ===== Tests =====

test "findNextSpecialChar finds delimiter in short string" {
    const buffer = "hello,world";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(u32, 5), pos);
}

test "findNextSpecialChar finds quote in short string" {
    const buffer = "hello\"world";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(u32, 5), pos);
}

test "findNextSpecialChar skips non-special characters" {
    const buffer = "abcdefghijklmnop,";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(u32, 16), pos);
}

test "findNextSpecialChar returns buffer.len when not found" {
    const buffer = "nospecialchars";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(u32, @intCast(buffer.len)), pos);
}

test "findNextSpecialChar handles delimiter at exact 16-byte boundary" {
    // 16 bytes + delimiter
    const buffer = "0123456789abcdef,end";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(u32, 16), pos);
}

test "findNextSpecialChar handles quote in SIMD chunk" {
    // Delimiter at byte 10 (within first 16-byte chunk)
    const buffer = "0123456789,abcdef";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(u32, 10), pos);
}

test "findNextSpecialChar handles start offset" {
    const buffer = "abc,def,ghi";
    const pos1 = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(u32, 3), pos1);

    const pos2 = findNextSpecialChar(buffer, pos1 + 1, ',', '"');
    try std.testing.expectEqual(@as(u32, 7), pos2);
}

test "findNextSpecialChar handles long field (>16 bytes)" {
    const buffer = "this_is_a_very_long_field_with_no_special_chars_until_here,end";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    // Buffer: "this_is_a_very_long_field_with_no_special_chars_until_here" = 58 chars
    // Delimiter "," is at index 58
    try std.testing.expectEqual(@as(u32, 58), pos);
}

test "compareFloat64Batch compares pairs correctly" {
    const allocator = std.testing.allocator;

    const data_a = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const data_b = [_]f64{ 2.0, 2.0, 1.0, 5.0, 4.0 };

    const results = try allocator.alloc(std.math.Order, data_a.len);
    defer allocator.free(results);

    compareFloat64Batch(&data_a, &data_b, results);

    // Verify results
    try std.testing.expectEqual(std.math.Order.lt, results[0]); // 1.0 < 2.0
    try std.testing.expectEqual(std.math.Order.eq, results[1]); // 2.0 == 2.0
    try std.testing.expectEqual(std.math.Order.gt, results[2]); // 3.0 > 1.0
    try std.testing.expectEqual(std.math.Order.lt, results[3]); // 4.0 < 5.0
    try std.testing.expectEqual(std.math.Order.gt, results[4]); // 5.0 > 4.0
}

test "compareInt64Batch compares pairs correctly" {
    const allocator = std.testing.allocator;

    const data_a = [_]i64{ 10, 20, 30, 40, 50 };
    const data_b = [_]i64{ 20, 20, 10, 50, 40 };

    const results = try allocator.alloc(std.math.Order, data_a.len);
    defer allocator.free(results);

    compareInt64Batch(&data_a, &data_b, results);

    // Verify results
    try std.testing.expectEqual(std.math.Order.lt, results[0]); // 10 < 20
    try std.testing.expectEqual(std.math.Order.eq, results[1]); // 20 == 20
    try std.testing.expectEqual(std.math.Order.gt, results[2]); // 30 > 10
    try std.testing.expectEqual(std.math.Order.lt, results[3]); // 40 < 50
    try std.testing.expectEqual(std.math.Order.gt, results[4]); // 50 > 40
}

test "compareFloat64Batch handles odd-length arrays" {
    const allocator = std.testing.allocator;

    const data_a = [_]f64{ 1.0, 2.0, 3.0 }; // Odd length
    const data_b = [_]f64{ 2.0, 1.0, 3.0 };

    const results = try allocator.alloc(std.math.Order, data_a.len);
    defer allocator.free(results);

    compareFloat64Batch(&data_a, &data_b, results);

    try std.testing.expectEqual(std.math.Order.lt, results[0]); // 1.0 < 2.0
    try std.testing.expectEqual(std.math.Order.gt, results[1]); // 2.0 > 1.0
    try std.testing.expectEqual(std.math.Order.eq, results[2]); // 3.0 == 3.0
}

