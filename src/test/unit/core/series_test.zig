//! Comprehensive tests for Series functionality
//!
//! This test suite covers:
//! - init() / deinit() - Series construction and destruction
//! - len() / isEmpty() / getValueType() - Basic queries
//! - asInt64() / asFloat64() / asBool() / asStringColumn() - Type accessors
//! - asInt64Buffer() / asFloat64Buffer() / asBoolBuffer() - Full buffer access
//! - getString() - String value access
//! - get() / set() - Generic value access
//! - appendString() - String column operations
//!
//! Tests follow Tiger Style: 2+ assertions per test, explicit error handling,
//! memory leak detection.

const std = @import("std");
const testing = std.testing;
const Series = @import("../../../core/series.zig").Series;
const SeriesData = @import("../../../core/series.zig").SeriesData;
const SeriesValue = @import("../../../core/series.zig").SeriesValue;
const ValueType = @import("../../../core/types.zig").ValueType;

// =============================================================================
// INIT & DEINIT TESTS (5 tests)
// =============================================================================

test "Series.init: Int64 type" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test_col", .Int64, 100);
    defer series.deinit(allocator);

    try testing.expectEqualStrings("test_col", series.name);
    try testing.expectEqual(ValueType.Int64, series.value_type);
    try testing.expectEqual(@as(u32, 0), series.len());
}

test "Series.init: Float64 type" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "price", .Float64, 50);
    defer series.deinit(allocator);

    try testing.expectEqualStrings("price", series.name);
    try testing.expectEqual(ValueType.Float64, series.value_type);
    try testing.expectEqual(@as(u32, 0), series.len());
}

test "Series.init: Bool type" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "active", .Bool, 200);
    defer series.deinit(allocator);

    try testing.expectEqualStrings("active", series.name);
    try testing.expectEqual(ValueType.Bool, series.value_type);
    try testing.expectEqual(@as(u32, 0), series.len());
}

test "Series.init: String type" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "name", .String, 100);
    defer series.deinit(allocator);

    try testing.expectEqualStrings("name", series.name);
    try testing.expectEqual(ValueType.String, series.value_type);
    try testing.expectEqual(@as(u32, 0), series.len());
}

test "Series.deinit: memory leak check (1000 iterations)" {
    const allocator = testing.allocator;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        var series = try Series.init(allocator, "test", .Int64, 1000);
        series.deinit(allocator);
    }

    // testing.allocator will report leaks automatically
}

// =============================================================================
// BASIC QUERY TESTS (3 tests)
// =============================================================================

test "Series.len: returns current length" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 100);
    defer series.deinit(allocator);

    try testing.expectEqual(@as(u32, 0), series.len());

    series.length = 50;
    try testing.expectEqual(@as(u32, 50), series.len());
}

test "Series.isEmpty: true when length is zero" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Float64, 10);
    defer series.deinit(allocator);

    try testing.expect(series.isEmpty());

    series.length = 1;
    try testing.expect(!series.isEmpty());
}

test "Series.getValueType: returns correct type" {
    const allocator = testing.allocator;

    var int_series = try Series.init(allocator, "ints", .Int64, 10);
    defer int_series.deinit(allocator);

    try testing.expectEqual(ValueType.Int64, int_series.getValueType());

    var float_series = try Series.init(allocator, "floats", .Float64, 10);
    defer float_series.deinit(allocator);

    try testing.expectEqual(ValueType.Float64, float_series.getValueType());
}

// =============================================================================
// TYPE ACCESSOR TESTS - INT64 (4 tests)
// =============================================================================

test "Series.asInt64: returns slice for Int64 Series" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    const buffer = series.asInt64Buffer().?;
    buffer[0] = 100;
    buffer[1] = 200;
    buffer[2] = 300;

    series.length = 3;

    const data = series.asInt64().?;
    try testing.expectEqual(@as(usize, 3), data.len);
    try testing.expectEqual(@as(i64, 100), data[0]);
    try testing.expectEqual(@as(i64, 200), data[1]);
    try testing.expectEqual(@as(i64, 300), data[2]);
}

test "Series.asInt64: returns null for wrong type" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Float64, 10);
    defer series.deinit(allocator);

    try testing.expect(series.asInt64() == null);
}

test "Series.asInt64Buffer: returns full capacity buffer" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 100);
    defer series.deinit(allocator);

    series.length = 10;

    const buffer = series.asInt64Buffer().?;
    try testing.expectEqual(@as(usize, 100), buffer.len);
}

test "Series.asInt64Buffer: allows mutation" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    const buffer = series.asInt64Buffer().?;
    buffer[0] = 42;
    buffer[1] = 84;

    series.length = 2;

    const data = series.asInt64().?;
    try testing.expectEqual(@as(i64, 42), data[0]);
    try testing.expectEqual(@as(i64, 84), data[1]);
}

// =============================================================================
// TYPE ACCESSOR TESTS - FLOAT64 (4 tests)
// =============================================================================

test "Series.asFloat64: returns slice for Float64 Series" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Float64, 10);
    defer series.deinit(allocator);

    const buffer = series.asFloat64Buffer().?;
    buffer[0] = 1.5;
    buffer[1] = 2.5;
    buffer[2] = 3.5;

    series.length = 3;

    const data = series.asFloat64().?;
    try testing.expectEqual(@as(usize, 3), data.len);
    try testing.expectEqual(@as(f64, 1.5), data[0]);
    try testing.expectEqual(@as(f64, 2.5), data[1]);
    try testing.expectEqual(@as(f64, 3.5), data[2]);
}

test "Series.asFloat64: returns null for wrong type" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    try testing.expect(series.asFloat64() == null);
}

test "Series.asFloat64Buffer: returns full capacity buffer" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Float64, 50);
    defer series.deinit(allocator);

    series.length = 10;

    const buffer = series.asFloat64Buffer().?;
    try testing.expectEqual(@as(usize, 50), buffer.len);
}

test "Series.asFloat64Buffer: allows mutation" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Float64, 10);
    defer series.deinit(allocator);

    const buffer = series.asFloat64Buffer().?;
    buffer[0] = 3.14159;
    buffer[1] = 2.71828;

    series.length = 2;

    const data = series.asFloat64().?;
    try testing.expectApproxEqRel(@as(f64, 3.14159), data[0], 0.00001);
    try testing.expectApproxEqRel(@as(f64, 2.71828), data[1], 0.00001);
}

// =============================================================================
// TYPE ACCESSOR TESTS - BOOL (4 tests)
// =============================================================================

test "Series.asBool: returns slice for Bool Series" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Bool, 10);
    defer series.deinit(allocator);

    const buffer = series.asBoolBuffer().?;
    buffer[0] = true;
    buffer[1] = false;
    buffer[2] = true;

    series.length = 3;

    const data = series.asBool().?;
    try testing.expectEqual(@as(usize, 3), data.len);
    try testing.expectEqual(true, data[0]);
    try testing.expectEqual(false, data[1]);
    try testing.expectEqual(true, data[2]);
}

test "Series.asBool: returns null for wrong type" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Float64, 10);
    defer series.deinit(allocator);

    try testing.expect(series.asBool() == null);
}

test "Series.asBoolBuffer: returns full capacity buffer" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Bool, 30);
    defer series.deinit(allocator);

    series.length = 10;

    const buffer = series.asBoolBuffer().?;
    try testing.expectEqual(@as(usize, 30), buffer.len);
}

test "Series.asBoolBuffer: allows mutation" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Bool, 10);
    defer series.deinit(allocator);

    const buffer = series.asBoolBuffer().?;
    buffer[0] = false;
    buffer[1] = false;
    buffer[2] = true;

    series.length = 3;

    const data = series.asBool().?;
    try testing.expectEqual(false, data[0]);
    try testing.expectEqual(false, data[1]);
    try testing.expectEqual(true, data[2]);
}

// =============================================================================
// TYPE ACCESSOR TESTS - STRING (5 tests)
// =============================================================================

test "Series.asStringColumn: returns StringColumn for String Series" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .String, 10);
    defer series.deinit(allocator);

    const col = series.asStringColumn();
    try testing.expect(col != null);
}

test "Series.asStringColumn: returns null for wrong type" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    try testing.expect(series.asStringColumn() == null);
}

test "Series.asStringColumnMut: returns mutable StringColumn" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .String, 10);
    defer series.deinit(allocator);

    const col = series.asStringColumnMut();
    try testing.expect(col != null);
}

test "Series.getString: retrieves individual strings" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .String, 10);
    defer series.deinit(allocator);

    try series.appendString(allocator, "Hello");
    try series.appendString(allocator, "World");

    const str0 = series.getString(0);
    const str1 = series.getString(1);

    try testing.expect(str0 != null);
    try testing.expect(str1 != null);
    try testing.expectEqualStrings("Hello", str0.?);
    try testing.expectEqualStrings("World", str1.?);
}

test "Series.getString: returns null for out of bounds index" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .String, 10);
    defer series.deinit(allocator);

    try series.appendString(allocator, "Test");

    try testing.expect(series.getString(0) != null);
    try testing.expect(series.getString(1) == null); // Out of bounds
    try testing.expect(series.getString(100) == null);
}

// =============================================================================
// GENERIC VALUE ACCESS TESTS (6 tests)
// =============================================================================

test "Series.get: Int64 value access" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    const buffer = series.asInt64Buffer().?;
    buffer[0] = 42;
    buffer[1] = 84;

    series.length = 2;

    const val0 = try series.get(0);
    const val1 = try series.get(1);

    try testing.expectEqual(@as(i64, 42), val0.Int64);
    try testing.expectEqual(@as(i64, 84), val1.Int64);
}

test "Series.get: Float64 value access" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Float64, 10);
    defer series.deinit(allocator);

    const buffer = series.asFloat64Buffer().?;
    buffer[0] = 3.14;
    buffer[1] = 2.71;

    series.length = 2;

    const val0 = try series.get(0);
    const val1 = try series.get(1);

    try testing.expectApproxEqRel(@as(f64, 3.14), val0.Float64, 0.01);
    try testing.expectApproxEqRel(@as(f64, 2.71), val1.Float64, 0.01);
}

test "Series.get: Bool value access" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Bool, 10);
    defer series.deinit(allocator);

    const buffer = series.asBoolBuffer().?;
    buffer[0] = true;
    buffer[1] = false;

    series.length = 2;

    const val0 = try series.get(0);
    const val1 = try series.get(1);

    try testing.expectEqual(true, val0.Bool);
    try testing.expectEqual(false, val1.Bool);
}

test "Series.get: String value access" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .String, 10);
    defer series.deinit(allocator);

    try series.appendString(allocator, "Alpha");
    try series.appendString(allocator, "Beta");

    const val0 = try series.get(0);
    const val1 = try series.get(1);

    try testing.expectEqualStrings("Alpha", val0.String);
    try testing.expectEqualStrings("Beta", val1.String);
}

test "Series.get: error on out of bounds" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    series.length = 5;

    // Valid access
    _ = try series.get(0);
    _ = try series.get(4);

    // Out of bounds
    try testing.expectError(error.IndexOutOfBounds, series.get(5));
    try testing.expectError(error.IndexOutOfBounds, series.get(100));
}

test "Series.set: modifies numeric values" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    series.length = 3;

    try series.set(0, SeriesValue{ .Int64 = 100 });
    try series.set(1, SeriesValue{ .Int64 = 200 });
    try series.set(2, SeriesValue{ .Int64 = 300 });

    const val0 = try series.get(0);
    const val1 = try series.get(1);
    const val2 = try series.get(2);

    try testing.expectEqual(@as(i64, 100), val0.Int64);
    try testing.expectEqual(@as(i64, 200), val1.Int64);
    try testing.expectEqual(@as(i64, 300), val2.Int64);
}

// =============================================================================
// INTEGRATION TESTS (3 tests)
// =============================================================================

test "Integration: create and populate Int64 Series" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "ages", .Int64, 5);
    defer series.deinit(allocator);

    const buffer = series.asInt64Buffer().?;
    buffer[0] = 25;
    buffer[1] = 30;
    buffer[2] = 35;
    buffer[3] = 40;
    buffer[4] = 45;

    series.length = 5;

    try testing.expectEqualStrings("ages", series.name);
    try testing.expectEqual(@as(u32, 5), series.len());
    try testing.expect(!series.isEmpty());

    const data = series.asInt64().?;
    try testing.expectEqual(@as(i64, 25), data[0]);
    try testing.expectEqual(@as(i64, 30), data[1]);
    try testing.expectEqual(@as(i64, 35), data[2]);
    try testing.expectEqual(@as(i64, 40), data[3]);
    try testing.expectEqual(@as(i64, 45), data[4]);
}

test "Integration: create and populate String Series" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "names", .String, 3);
    defer series.deinit(allocator);

    try series.appendString(allocator, "Alice");
    try series.appendString(allocator, "Bob");
    try series.appendString(allocator, "Charlie");

    try testing.expectEqualStrings("names", series.name);
    try testing.expectEqual(@as(u32, 3), series.len());

    try testing.expectEqualStrings("Alice", series.getString(0).?);
    try testing.expectEqualStrings("Bob", series.getString(1).?);
    try testing.expectEqualStrings("Charlie", series.getString(2).?);
}

test "Integration: type mismatch returns null (no crashes)" {
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    // Try to access as wrong types - should return null
    try testing.expect(series.asFloat64() == null);
    try testing.expect(series.asBool() == null);
    try testing.expect(series.asStringColumn() == null);

    // Try to get string from Int64 series
    try testing.expect(series.getString(0) == null);
}

// =============================================================================
// HASH CACHING TESTS (6 tests)
// =============================================================================

test "StringColumn hash cache: enableHashCache pre-computes hashes" {
    const allocator = testing.allocator;
    const StringColumn = @import("../../../core/series.zig").StringColumn;

    // Create string column with 5 strings
    var col = try StringColumn.init(allocator, 10, 100);
    defer col.deinit(allocator);

    try col.append(allocator, "hello");
    try col.append(allocator, "world");
    try col.append(allocator, "test");
    try col.append(allocator, "data");
    try col.append(allocator, "frame");

    try testing.expectEqual(@as(u32, 5), col.count);
    try testing.expect(col.hash_cache == null); // Cache disabled by default

    // Enable hash cache
    try col.enableHashCache(allocator);

    try testing.expect(col.hash_cache != null); // Cache enabled
    if (col.hash_cache) |cache| {
        try testing.expectEqual(@as(usize, 5), cache.len); // All hashes pre-computed
        // Verify hashes are non-zero
        try testing.expect(cache[0] != 0);
        try testing.expect(cache[4] != 0);
    }
}

test "StringColumn hash cache: getHash returns cached value when enabled" {
    const allocator = testing.allocator;
    const StringColumn = @import("../../../core/series.zig").StringColumn;
    const string_utils = @import("../../../core/string_utils.zig");

    var col = try StringColumn.init(allocator, 10, 100);
    defer col.deinit(allocator);

    try col.append(allocator, "hello");
    try col.append(allocator, "world");

    // Without cache: getHash computes hash
    const hash_no_cache = col.getHash(0);
    try testing.expect(hash_no_cache != 0);
    try testing.expectEqual(string_utils.fastHash("hello"), hash_no_cache);

    // Enable cache
    try col.enableHashCache(allocator);

    // With cache: getHash returns cached value
    const hash_with_cache = col.getHash(0);
    try testing.expect(hash_with_cache != 0);
    try testing.expectEqual(hash_no_cache, hash_with_cache); // Same hash value
    try testing.expectEqual(string_utils.fastHash("hello"), hash_with_cache);
}

test "StringColumn hash cache: getHash computes on demand when disabled" {
    const allocator = testing.allocator;
    const StringColumn = @import("../../../core/series.zig").StringColumn;
    const string_utils = @import("../../../core/string_utils.zig");

    var col = try StringColumn.init(allocator, 10, 100);
    defer col.deinit(allocator);

    try col.append(allocator, "test");
    try col.append(allocator, "data");

    try testing.expect(col.hash_cache == null); // Cache disabled

    // getHash should still work (compute on demand)
    const hash1 = col.getHash(0);
    const hash2 = col.getHash(1);

    try testing.expect(hash1 != 0);
    try testing.expect(hash2 != 0);
    try testing.expect(hash1 != hash2); // Different strings → different hashes
    try testing.expectEqual(string_utils.fastHash("test"), hash1);
    try testing.expectEqual(string_utils.fastHash("data"), hash2);
}

test "StringColumn hash cache: deinit frees cache memory" {
    const allocator = testing.allocator;
    const StringColumn = @import("../../../core/series.zig").StringColumn;

    var col = try StringColumn.init(allocator, 10, 100);

    try col.append(allocator, "hello");
    try col.append(allocator, "world");
    try col.append(allocator, "test");

    // Enable cache (allocates memory)
    try col.enableHashCache(allocator);
    try testing.expect(col.hash_cache != null);

    // deinit should free cache without leaks
    col.deinit(allocator);

    // Test passes if testing.allocator doesn't report leaks
}

test "StringColumn hash cache: enableHashCache replaces old cache" {
    const allocator = testing.allocator;
    const StringColumn = @import("../../../core/series.zig").StringColumn;

    var col = try StringColumn.init(allocator, 10, 100);
    defer col.deinit(allocator);

    try col.append(allocator, "first");
    try col.append(allocator, "second");

    // Enable cache first time
    try col.enableHashCache(allocator);
    try testing.expect(col.hash_cache != null);
    const first_hash = col.getHash(0);

    // Enable cache second time (should replace old cache)
    try col.enableHashCache(allocator);
    try testing.expect(col.hash_cache != null);
    const second_hash = col.getHash(0);

    // Hash values should be the same (same data)
    try testing.expectEqual(first_hash, second_hash);

    // Test passes if no memory leaks (testing.allocator validates)
}

test "StringColumn hash cache: hash consistency across cache enable/disable" {
    const allocator = testing.allocator;
    const StringColumn = @import("../../../core/series.zig").StringColumn;

    var col = try StringColumn.init(allocator, 10, 100);
    defer col.deinit(allocator);

    try col.append(allocator, "consistency");
    try col.append(allocator, "test");
    try col.append(allocator, "data");

    // Get hashes without cache
    const hash0_no_cache = col.getHash(0);
    const hash1_no_cache = col.getHash(1);
    const hash2_no_cache = col.getHash(2);

    // Enable cache
    try col.enableHashCache(allocator);

    // Get hashes with cache
    const hash0_with_cache = col.getHash(0);
    const hash1_with_cache = col.getHash(1);
    const hash2_with_cache = col.getHash(2);

    // Hashes should be identical (same algorithm)
    try testing.expectEqual(hash0_no_cache, hash0_with_cache);
    try testing.expectEqual(hash1_no_cache, hash1_with_cache);
    try testing.expectEqual(hash2_no_cache, hash2_with_cache);

    // Different strings should have different hashes
    try testing.expect(hash0_no_cache != hash1_no_cache);
    try testing.expect(hash1_no_cache != hash2_no_cache);
}
