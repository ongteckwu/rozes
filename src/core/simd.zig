//! SIMD Utilities for High-Performance Data Processing
//!
//! This module provides SIMD-accelerated operations for:
//! - CSV field scanning (find delimiters, quotes)
//! - Numeric comparisons (sort operations)
//! - Aggregations (sum, mean, min, max)
//! - Hash computations (join operations)
//!
//! SIMD operations are available on:
//! - WebAssembly with SIMD support (Chrome 91+, Firefox 89+, Safari 16.4+)
//! - Native platforms with SSE2+ (x86_64), NEON (ARM64)
//!
//! See docs/TODO.md Phase 6C for performance targets

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
    start: usize,
    delimiter: u8,
    quote: u8,
) usize {
    std.debug.assert(start <= buffer.len); // Pre-condition #1
    std.debug.assert(delimiter != 0); // Pre-condition #2: Valid delimiter
    std.debug.assert(quote != 0); // Pre-condition #3: Valid quote

    if (!simd_available) {
        return findNextSpecialCharScalar(buffer, start, delimiter, quote);
    }

    var pos = start;

    // Process 16-byte chunks with SIMD
    const MAX_ITERATIONS: u32 = 1_000_000_000 / SIMD_WIDTH; // 1GB / 16 bytes
    var iterations: u32 = 0;

    while (pos + SIMD_WIDTH <= buffer.len and iterations < MAX_ITERATIONS) : (iterations += 1) {
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
    start: usize,
    delimiter: u8,
    quote: u8,
) usize {
    std.debug.assert(start <= buffer.len); // Pre-condition #1
    std.debug.assert(delimiter != 0); // Pre-condition #2

    const MAX_SCAN: u32 = 1_000_000; // Max 1MB field
    var pos = start;
    var iterations: u32 = 0;

    while (pos < buffer.len and iterations < MAX_SCAN) : (iterations += 1) {
        const char = buffer[pos];
        if (char == delimiter or char == quote) {
            std.debug.assert(pos < buffer.len); // Post-condition #1
            return pos;
        }
        pos += 1;
    }

    std.debug.assert(iterations <= MAX_SCAN); // Post-condition #2
    std.debug.assert(pos <= buffer.len); // Post-condition #3

    return buffer.len; // Not found
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

    var i: usize = 0;
    const simd_width = 2; // Process 2 f64 values per iteration (128 bits)

    // Process in pairs using SIMD
    const MAX_ITERATIONS: u32 = 500_000_000; // 1B / 2
    var iterations: u32 = 0;

    while (i + simd_width <= data_a.len and iterations < MAX_ITERATIONS) : (iterations += 1) {
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
    while (i < data_a.len) : (i += 1) {
        results[i] = std.math.order(data_a[i], data_b[i]);
    }

    std.debug.assert(i == data_a.len); // Post-condition #2
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

    var i: usize = 0;
    const simd_width = 2; // Process 2 i64 values per iteration (128 bits)

    const MAX_ITERATIONS: u32 = 500_000_000; // 1B / 2
    var iterations: u32 = 0;

    while (i + simd_width <= data_a.len and iterations < MAX_ITERATIONS) : (iterations += 1) {
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
    while (i < data_a.len) : (i += 1) {
        results[i] = std.math.order(data_a[i], data_b[i]);
    }

    std.debug.assert(i == data_a.len); // Post-condition #2
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

// ===== Tests =====

test "findNextSpecialChar finds delimiter in short string" {
    const buffer = "hello,world";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(usize, 5), pos);
}

test "findNextSpecialChar finds quote in short string" {
    const buffer = "hello\"world";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(usize, 5), pos);
}

test "findNextSpecialChar skips non-special characters" {
    const buffer = "abcdefghijklmnop,";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(usize, 16), pos);
}

test "findNextSpecialChar returns buffer.len when not found" {
    const buffer = "nospecialchars";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(buffer.len, pos);
}

test "findNextSpecialChar handles delimiter at exact 16-byte boundary" {
    // 16 bytes + delimiter
    const buffer = "0123456789abcdef,end";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(usize, 16), pos);
}

test "findNextSpecialChar handles quote in SIMD chunk" {
    // Delimiter at byte 10 (within first 16-byte chunk)
    const buffer = "0123456789,abcdef";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(usize, 10), pos);
}

test "findNextSpecialChar handles start offset" {
    const buffer = "abc,def,ghi";
    const pos1 = findNextSpecialChar(buffer, 0, ',', '"');
    try std.testing.expectEqual(@as(usize, 3), pos1);

    const pos2 = findNextSpecialChar(buffer, pos1 + 1, ',', '"');
    try std.testing.expectEqual(@as(usize, 7), pos2);
}

test "findNextSpecialChar handles long field (>16 bytes)" {
    const buffer = "this_is_a_very_long_field_with_no_special_chars_until_here,end";
    const pos = findNextSpecialChar(buffer, 0, ',', '"');
    // Buffer: "this_is_a_very_long_field_with_no_special_chars_until_here" = 58 chars
    // Delimiter "," is at index 58
    try std.testing.expectEqual(@as(usize, 58), pos);
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
