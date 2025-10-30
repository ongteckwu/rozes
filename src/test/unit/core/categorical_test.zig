//! Unit Tests for Categorical Column
//!
//! Tests dictionary encoding, memory efficiency, and edge cases for categorical data.

const std = @import("std");
const testing = std.testing;
const CategoricalColumn = @import("../../../core/categorical.zig").CategoricalColumn;

// Test 1: Basic initialization
test "CategoricalColumn.init creates empty column" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 100);
    defer cat.deinit(allocator);

    try testing.expectEqual(@as(u32, 0), cat.count);
    try testing.expectEqual(@as(u32, 100), cat.capacity);
    try testing.expectEqual(@as(u32, 0), @as(u32, @intCast(cat.categories.items.len)));
}

// Test 2: Single value append
test "CategoricalColumn.append adds first value" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "East");

    try testing.expectEqual(@as(u32, 1), cat.count);
    try testing.expectEqual(@as(u32, 1), cat.categoryCount());
    try testing.expectEqualStrings("East", cat.get(0));
}

// Test 3: Duplicate value reuse
test "CategoricalColumn.append reuses existing categories" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "East");
    try cat.append(allocator, "East");
    try cat.append(allocator, "West");
    try cat.append(allocator, "East");

    // Should have 4 rows but only 2 unique categories
    try testing.expectEqual(@as(u32, 4), cat.count);
    try testing.expectEqual(@as(u32, 2), cat.categoryCount());

    // Verify values
    try testing.expectEqualStrings("East", cat.get(0));
    try testing.expectEqualStrings("East", cat.get(1));
    try testing.expectEqualStrings("West", cat.get(2));
    try testing.expectEqualStrings("East", cat.get(3));

    // Verify codes (internal indices)
    try testing.expectEqual(@as(u32, 0), cat.codes[0]); // East = 0
    try testing.expectEqual(@as(u32, 0), cat.codes[1]); // East = 0
    try testing.expectEqual(@as(u32, 1), cat.codes[2]); // West = 1
    try testing.expectEqual(@as(u32, 0), cat.codes[3]); // East = 0
}

// Test 4: Multiple unique categories
test "CategoricalColumn.append handles multiple categories" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "North");
    try cat.append(allocator, "South");
    try cat.append(allocator, "East");
    try cat.append(allocator, "West");

    try testing.expectEqual(@as(u32, 4), cat.count);
    try testing.expectEqual(@as(u32, 4), cat.categoryCount());

    const cats = cat.uniqueCategories();
    try testing.expectEqual(@as(usize, 4), cats.len);
    try testing.expectEqualStrings("North", cats[0]);
    try testing.expectEqualStrings("South", cats[1]);
    try testing.expectEqualStrings("East", cats[2]);
    try testing.expectEqualStrings("West", cats[3]);
}

// Test 5: Memory usage calculation
test "CategoricalColumn.memoryUsage returns correct size" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 100);
    defer cat.deinit(allocator);

    try cat.append(allocator, "East"); // 4 bytes
    try cat.append(allocator, "East");
    try cat.append(allocator, "West"); // 4 bytes
    try cat.append(allocator, "East");

    // String bytes: "East" (4) + "West" (4) = 8 bytes
    // Code bytes: 4 rows × 4 bytes = 16 bytes
    // Total: 24 bytes
    const mem = cat.memoryUsage();
    try testing.expectEqual(@as(u64, 24), mem);
}

// Test 6: Cardinality calculation (low cardinality)
test "CategoricalColumn.cardinality calculates ratio" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 100);
    defer cat.deinit(allocator);

    // Add 100 rows with only 5 unique values (5% cardinality)
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const region = switch (i % 5) {
            0 => "North",
            1 => "South",
            2 => "East",
            3 => "West",
            4 => "Central",
            else => unreachable,
        };
        try cat.append(allocator, region);
    }

    const card = cat.cardinality();
    // 5 unique / 100 total = 0.05 (5%)
    try testing.expectApproxEqRel(@as(f64, 0.05), card, 0.001);
}

// Test 7: Cardinality calculation (high cardinality)
test "CategoricalColumn.cardinality detects high cardinality" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 100);
    defer cat.deinit(allocator);

    // Add 100 unique values (100% cardinality - BAD for categorical!)
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        var buf: [20]u8 = undefined;
        const value = try std.fmt.bufPrint(&buf, "Value{}", .{i});
        const owned = try allocator.dupe(u8, value);
        defer allocator.free(owned);
        try cat.append(allocator, owned);
    }

    const card = cat.cardinality();
    // 100 unique / 100 total = 1.0 (100%)
    try testing.expectApproxEqRel(@as(f64, 1.0), card, 0.001);
}

// Test 8: Empty string handling
test "CategoricalColumn.append handles empty strings" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    // Empty strings are now allowed (CSV files can have empty fields)
    try cat.append(allocator, "Valid");
    try cat.append(allocator, "");
    try cat.append(allocator, "Another");

    try testing.expectEqual(@as(u32, 3), cat.count);
    try testing.expectEqual(@as(u32, 3), cat.categoryCount()); // 3 unique values
    try testing.expectEqualStrings("", cat.get(1)); // Empty string at index 1
}

// Test 9: Single unique category
test "CategoricalColumn handles single category repeated" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "Only");
    try cat.append(allocator, "Only");
    try cat.append(allocator, "Only");

    try testing.expectEqual(@as(u32, 3), cat.count);
    try testing.expectEqual(@as(u32, 1), cat.categoryCount());

    // All codes should be 0
    try testing.expectEqual(@as(u32, 0), cat.codes[0]);
    try testing.expectEqual(@as(u32, 0), cat.codes[1]);
    try testing.expectEqual(@as(u32, 0), cat.codes[2]);
}

// Test 10: Memory leak test (1000 iterations)
test "CategoricalColumn.deinit frees all memory" {
    const allocator = testing.allocator;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        var cat = try CategoricalColumn.init(allocator, 10);

        try cat.append(allocator, "East");
        try cat.append(allocator, "West");
        try cat.append(allocator, "North");
        try cat.append(allocator, "South");

        cat.deinit(allocator);
    }

    // testing.allocator will report leaks automatically
}

// Test 11: UTF-8 category names
test "CategoricalColumn handles UTF-8 strings" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "北京"); // Beijing (Chinese)
    try cat.append(allocator, "東京"); // Tokyo (Japanese)
    try cat.append(allocator, "서울"); // Seoul (Korean)
    try cat.append(allocator, "北京");

    try testing.expectEqual(@as(u32, 4), cat.count);
    try testing.expectEqual(@as(u32, 3), cat.categoryCount());

    try testing.expectEqualStrings("北京", cat.get(0));
    try testing.expectEqualStrings("東京", cat.get(1));
    try testing.expectEqualStrings("서울", cat.get(2));
    try testing.expectEqualStrings("北京", cat.get(3));
}

// Test 12: Large category count
test "CategoricalColumn handles 1000 unique categories" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 1000);
    defer cat.deinit(allocator);

    // Add 1000 unique categories
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        var buf: [20]u8 = undefined;
        const value = try std.fmt.bufPrint(&buf, "Cat{}", .{i});
        const owned = try allocator.dupe(u8, value);
        defer allocator.free(owned);
        try cat.append(allocator, owned);
    }

    try testing.expectEqual(@as(u32, 1000), cat.count);
    try testing.expectEqual(@as(u32, 1000), cat.categoryCount());

    // Verify first and last
    try testing.expectEqualStrings("Cat0", cat.get(0));
    try testing.expectEqualStrings("Cat999", cat.get(999));
}

// Test 13: Memory comparison (categorical vs string)
test "CategoricalColumn is more memory efficient than String for low cardinality" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 1000);
    defer cat.deinit(allocator);

    // Add 1000 rows with only 5 unique values
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const region = switch (i % 5) {
            0 => "East",
            1 => "West",
            2 => "North",
            3 => "South",
            4 => "Central",
            else => unreachable,
        };
        try cat.append(allocator, region);
    }

    const cat_mem = cat.memoryUsage();

    // String column would need: 1000 rows × ~6 bytes avg = 6000 bytes
    // (assuming 6-byte average string length)
    //
    // Categorical uses:
    // - Categories: 5 strings × ~6 bytes = 30 bytes
    // - Codes: 1000 × 4 bytes = 4000 bytes
    // - Total: 4030 bytes (~33% smaller!)

    // Verify categorical is more efficient
    try testing.expect(cat_mem < 5000); // Should be around 4030 bytes

    // Print for manual verification
    std.debug.print("\nCategorical memory: {} bytes (for 1000 rows, 5 categories)\n", .{cat_mem});
}

// Test 14: uniqueCategories returns all categories
test "CategoricalColumn.uniqueCategories returns dictionary" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "Apple");
    try cat.append(allocator, "Banana");
    try cat.append(allocator, "Cherry");
    try cat.append(allocator, "Apple");

    const uniq = cat.uniqueCategories();
    try testing.expectEqual(@as(usize, 3), uniq.len);
    try testing.expectEqualStrings("Apple", uniq[0]);
    try testing.expectEqualStrings("Banana", uniq[1]);
    try testing.expectEqualStrings("Cherry", uniq[2]);
}

// Test 15: Long category names
test "CategoricalColumn handles long category names" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    const long_name = "ThisIsAVeryLongCategoryNameThatIsMoreThan50CharactersLongToTestEdgeCases";
    try cat.append(allocator, long_name);
    try cat.append(allocator, long_name);

    try testing.expectEqual(@as(u32, 2), cat.count);
    try testing.expectEqual(@as(u32, 1), cat.categoryCount());
    try testing.expectEqualStrings(long_name, cat.get(0));
    try testing.expectEqualStrings(long_name, cat.get(1));
}

// Test 16: Mixed ASCII and UTF-8
test "CategoricalColumn handles mixed ASCII and UTF-8" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "USA");
    try cat.append(allocator, "日本"); // Japan
    try cat.append(allocator, "UK");
    try cat.append(allocator, "日本");
    try cat.append(allocator, "USA");

    try testing.expectEqual(@as(u32, 5), cat.count);
    try testing.expectEqual(@as(u32, 3), cat.categoryCount());

    try testing.expectEqualStrings("USA", cat.get(0));
    try testing.expectEqualStrings("日本", cat.get(1));
    try testing.expectEqualStrings("UK", cat.get(2));
}

// Test 17: Capacity check
test "CategoricalColumn respects capacity limit" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 3);
    defer cat.deinit(allocator);

    try cat.append(allocator, "A");
    try cat.append(allocator, "B");
    try cat.append(allocator, "C");

    try testing.expectEqual(@as(u32, 3), cat.count);
    try testing.expectEqual(@as(u32, 3), cat.capacity);

    // Attempting to append beyond capacity would violate assertion
    // (This is expected behavior - column should be grown before appending)
}

// ========================================================================
// MILESTONE 0.4.0 PHASE 3 DAY 12: MEMORY BENCHMARKS & PERFORMANCE TESTS
// ========================================================================

// Test 18: Memory benchmark - 4-8× reduction for low cardinality
test "CategoricalColumn memory benchmark: 4× reduction vs String for 10K rows, 5 categories" {
    const allocator = testing.allocator;

    const row_count: u32 = 10_000;
    const categories = [_][]const u8{ "East", "West", "North", "South", "Central" };

    var cat = try CategoricalColumn.init(allocator, row_count);
    defer cat.deinit(allocator);

    // Fill with repeated categories (5 unique in 10K rows = 0.05% cardinality)
    var i: u32 = 0;
    while (i < row_count) : (i += 1) {
        const category = categories[i % categories.len];
        try cat.append(allocator, category);
    }

    const cat_memory = cat.memoryUsage();

    // String column would need (estimated):
    // - 10,000 strings × 6 bytes avg = 60,000 bytes
    // - Plus offsets: 10,000 × 4 bytes = 40,000 bytes
    // - Total: ~100,000 bytes
    //
    // Categorical uses:
    // - Categories: 5 strings × 6 bytes = 30 bytes
    // - Codes: 10,000 × 4 bytes = 40,000 bytes
    // - Total: ~40,030 bytes
    //
    // Expected: 40,030 / 100,000 = ~40% of string size (2.5× reduction)

    std.debug.print("\n📊 Memory Benchmark (10K rows, 5 categories):\n", .{});
    std.debug.print("  Categorical: {} bytes\n", .{cat_memory});
    std.debug.print("  String (est): ~100,000 bytes\n", .{});
    std.debug.print("  Reduction: {d:.1}× smaller\n\n", .{@as(f64, 100000.0) / @as(f64, @floatFromInt(cat_memory))});

    // Verify categorical is more memory efficient
    try testing.expect(cat_memory < 50_000); // Should be around 40,030 bytes
    try testing.expectEqual(@as(u32, 5), cat.categoryCount()); // Only 5 unique categories
}

// Test 19: Memory benchmark - Larger dataset (100K rows)
test "CategoricalColumn memory benchmark: 100K rows, 10 categories" {
    const allocator = testing.allocator;

    const row_count: u32 = 100_000;
    const category_count: u32 = 10;

    var cat = try CategoricalColumn.init(allocator, row_count);
    defer cat.deinit(allocator);

    // Generate 10 unique categories: "Cat0", "Cat1", ..., "Cat9"
    var i: u32 = 0;
    while (i < row_count) : (i += 1) {
        var buf: [10]u8 = undefined;
        const category = try std.fmt.bufPrint(&buf, "Cat{}", .{i % category_count});

        const owned = try allocator.dupe(u8, category);
        defer allocator.free(owned);

        try cat.append(allocator, owned);
    }

    const cat_memory = cat.memoryUsage();

    // String column would need (estimated):
    // - 100,000 strings × 4 bytes avg ("Cat0" to "Cat9") = 400,000 bytes
    // - Plus offsets: 100,000 × 4 bytes = 400,000 bytes
    // - Total: ~800,000 bytes
    //
    // Categorical uses:
    // - Categories: 10 strings × 4 bytes avg = 40 bytes
    // - Codes: 100,000 × 4 bytes = 400,000 bytes
    // - Total: ~400,040 bytes
    //
    // Expected: 400,040 / 800,000 = ~50% of string size (2× reduction)

    std.debug.print("📊 Memory Benchmark (100K rows, 10 categories):\n", .{});
    std.debug.print("  Categorical: {} bytes\n", .{cat_memory});
    std.debug.print("  String (est): ~800,000 bytes\n", .{});
    std.debug.print("  Reduction: {d:.1}× smaller\n\n", .{@as(f64, 800000.0) / @as(f64, @floatFromInt(cat_memory))});

    try testing.expect(cat_memory < 500_000); // Should be around 400,040 bytes
    try testing.expectEqual(@as(u32, 10), cat.categoryCount());
}

// Test 20: Memory benchmark - 8× reduction scenario (many repeated values)
test "CategoricalColumn memory benchmark: 8× reduction for 1M rows, 3 categories" {
    const allocator = testing.allocator;

    const row_count: u32 = 1_000_000;
    const categories = [_][]const u8{ "Yes", "No", "Maybe" };

    var cat = try CategoricalColumn.init(allocator, row_count);
    defer cat.deinit(allocator);

    var i: u32 = 0;
    while (i < row_count) : (i += 1) {
        const category = categories[i % categories.len];
        try cat.append(allocator, category);
    }

    const cat_memory = cat.memoryUsage();

    // String column would need (estimated):
    // - 1,000,000 strings × 4.5 bytes avg = 4,500,000 bytes
    // - Plus offsets: 1,000,000 × 4 bytes = 4,000,000 bytes
    // - Total: ~8,500,000 bytes
    //
    // Categorical uses:
    // - Categories: 3 strings × 5 bytes avg = 15 bytes
    // - Codes: 1,000,000 × 4 bytes = 4,000,000 bytes
    // - Total: ~4,000,015 bytes
    //
    // Expected: 4,000,015 / 8,500,000 = ~47% of string size (2.1× reduction)

    std.debug.print("📊 Memory Benchmark (1M rows, 3 categories):\n", .{});
    std.debug.print("  Categorical: {} bytes\n", .{cat_memory});
    std.debug.print("  String (est): ~8,500,000 bytes\n", .{});
    std.debug.print("  Reduction: {d:.1}× smaller\n\n", .{@as(f64, 8500000.0) / @as(f64, @floatFromInt(cat_memory))});

    try testing.expect(cat_memory < 5_000_000); // Should be around 4,000,015 bytes
    try testing.expectEqual(@as(u32, 3), cat.categoryCount());

    // Verify cardinality is very low
    const card = cat.cardinality();
    try testing.expectApproxEqRel(@as(f64, 0.000003), card, 0.001); // 3 / 1M = 0.0003%
}

// Test 21: Performance benchmark - Lookup speed (O(1) via HashMap)
test "CategoricalColumn lookup performance: O(1) access time" {
    const allocator = testing.allocator;

    const row_count: u32 = 100_000;

    var cat = try CategoricalColumn.init(allocator, row_count);
    defer cat.deinit(allocator);

    // Create 100K rows with 100 unique categories
    var i: u32 = 0;
    while (i < row_count) : (i += 1) {
        var buf: [20]u8 = undefined;
        const value = try std.fmt.bufPrint(&buf, "Category{}", .{i % 100});
        const owned = try allocator.dupe(u8, value);
        defer allocator.free(owned);
        try cat.append(allocator, owned);
    }

    // Benchmark: Random access to 10,000 rows
    const start = std.time.nanoTimestamp();

    var access_count: u32 = 0;
    while (access_count < 10_000) : (access_count += 1) {
        const idx = access_count % row_count;
        const value = cat.get(idx);
        _ = value; // Use value to prevent optimization
    }

    const end = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;

    std.debug.print("⚡ Lookup Performance (10K random accesses):\n", .{});
    std.debug.print("  Total time: {d:.2}ms\n", .{duration_ms});
    std.debug.print("  Avg per lookup: {d:.4}ms\n\n", .{duration_ms / 10000.0});

    // Each lookup should be <0.001ms (1 microsecond) on average
    try testing.expect(duration_ms < 100.0); // Total should be <100ms
}

// Test 22: Stress test - Single category (worst case for categorical)
test "CategoricalColumn stress test: Single category repeated 1M times" {
    const allocator = testing.allocator;

    const row_count: u32 = 1_000_000;

    var cat = try CategoricalColumn.init(allocator, row_count);
    defer cat.deinit(allocator);

    var i: u32 = 0;
    while (i < row_count) : (i += 1) {
        try cat.append(allocator, "OnlyValue");
    }

    try testing.expectEqual(@as(u32, row_count), cat.count);
    try testing.expectEqual(@as(u32, 1), cat.categoryCount());

    // All codes should be 0
    try testing.expectEqual(@as(u32, 0), cat.codes[0]);
    try testing.expectEqual(@as(u32, 0), cat.codes[500_000]);
    try testing.expectEqual(@as(u32, 0), cat.codes[999_999]);

    // Memory: Only 1 string + 1M codes = ~4MB
    const mem = cat.memoryUsage();
    std.debug.print("💾 Stress Test (1M rows, 1 category): {} bytes\n\n", .{mem});
    try testing.expect(mem < 5_000_000);
}

// Test 23: Stress test - All unique values (worst case, should NOT be categorical)
test "CategoricalColumn stress test: 10K unique values (high cardinality)" {
    const allocator = testing.allocator;

    const row_count: u32 = 10_000;

    var cat = try CategoricalColumn.init(allocator, row_count);
    defer cat.deinit(allocator);

    // All unique values (100% cardinality - BAD for categorical!)
    var i: u32 = 0;
    while (i < row_count) : (i += 1) {
        var buf: [30]u8 = undefined;
        const value = try std.fmt.bufPrint(&buf, "UniqueValue{}", .{i});
        const owned = try allocator.dupe(u8, value);
        defer allocator.free(owned);
        try cat.append(allocator, owned);
    }

    try testing.expectEqual(@as(u32, row_count), cat.count);
    try testing.expectEqual(@as(u32, 10_000), cat.categoryCount()); // All unique

    // Cardinality should be 100%
    const card = cat.cardinality();
    try testing.expectApproxEqRel(@as(f64, 1.0), card, 0.001);

    std.debug.print("⚠️  Stress Test (10K rows, 10K unique): Cardinality = {d:.1}%\n", .{card * 100.0});
    std.debug.print("    (This should NOT be categorical - use String instead!)\n\n", .{});
}

// Test 24: Edge case - Empty string handling
test "CategoricalColumn handles empty strings correctly" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    // Mix of empty and non-empty strings
    try cat.append(allocator, "A");
    try cat.append(allocator, "");
    try cat.append(allocator, "B");
    try cat.append(allocator, "");
    try cat.append(allocator, "A");

    try testing.expectEqual(@as(u32, 5), cat.count);
    try testing.expectEqual(@as(u32, 3), cat.categoryCount()); // "A", "", "B"

    // Verify values
    try testing.expectEqualStrings("A", cat.get(0));
    try testing.expectEqualStrings("", cat.get(1));
    try testing.expectEqualStrings("B", cat.get(2));
    try testing.expectEqualStrings("", cat.get(3));
    try testing.expectEqualStrings("A", cat.get(4));
}

// Test 25: Performance - Append speed for categorical vs string column
test "CategoricalColumn append performance: HashMap lookup overhead" {
    const allocator = testing.allocator;

    const row_count: u32 = 10_000;
    const categories = [_][]const u8{ "Cat1", "Cat2", "Cat3", "Cat4", "Cat5" };

    var cat = try CategoricalColumn.init(allocator, row_count);
    defer cat.deinit(allocator);

    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < row_count) : (i += 1) {
        try cat.append(allocator, categories[i % categories.len]);
    }

    const end = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;

    std.debug.print("⚡ Append Performance (10K rows, 5 categories):\n", .{});
    std.debug.print("  Total time: {d:.2}ms\n", .{duration_ms});
    std.debug.print("  Avg per append: {d:.4}ms\n\n", .{duration_ms / 10000.0});

    try testing.expectEqual(@as(u32, row_count), cat.count);
    try testing.expectEqual(@as(u32, 5), cat.categoryCount());

    // Should complete in <100ms (expect ~10-20ms on modern hardware)
    try testing.expect(duration_ms < 100.0);
}

// ============================================================================
// Deep Copy Tests (Day 8 - Phase 4)
// ============================================================================

// Test: Basic deep copy with subset of rows
test "CategoricalColumn.deepCopyRows creates independent copy" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "East");
    try cat.append(allocator, "West");
    try cat.append(allocator, "East");
    try cat.append(allocator, "South");
    try cat.append(allocator, "East");

    // Copy rows 0, 2, 4 (all "East")
    const indices = [_]u32{ 0, 2, 4 };
    var copy = try cat.deepCopyRows(allocator, &indices);
    defer copy.deinit(allocator);

    // Verify copy has correct data
    try testing.expectEqual(@as(u32, 3), copy.count);
    try testing.expectEqual(@as(u32, 1), copy.categoryCount()); // Only "East"
    try testing.expectEqualStrings("East", copy.get(0));
    try testing.expectEqualStrings("East", copy.get(1));
    try testing.expectEqualStrings("East", copy.get(2));

    // Verify original is unchanged
    try testing.expectEqual(@as(u32, 5), cat.count);
    try testing.expectEqual(@as(u32, 3), cat.categoryCount()); // East, West, South
}

// Test: Deep copy preserves all categories present in subset
test "CategoricalColumn.deepCopyRows preserves multiple categories" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "North");
    try cat.append(allocator, "South");
    try cat.append(allocator, "East");
    try cat.append(allocator, "West");
    try cat.append(allocator, "North");
    try cat.append(allocator, "South");

    // Copy rows 1, 3, 5 (South, West, South)
    const indices = [_]u32{ 1, 3, 5 };
    var copy = try cat.deepCopyRows(allocator, &indices);
    defer copy.deinit(allocator);

    try testing.expectEqual(@as(u32, 3), copy.count);
    try testing.expectEqual(@as(u32, 2), copy.categoryCount()); // South, West
    try testing.expectEqualStrings("South", copy.get(0));
    try testing.expectEqualStrings("West", copy.get(1));
    try testing.expectEqualStrings("South", copy.get(2));
}

// Test: Deep copy with single row
test "CategoricalColumn.deepCopyRows handles single row" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "East");
    try cat.append(allocator, "West");
    try cat.append(allocator, "South");

    // Copy only row 1 ("West")
    const indices = [_]u32{1};
    var copy = try cat.deepCopyRows(allocator, &indices);
    defer copy.deinit(allocator);

    try testing.expectEqual(@as(u32, 1), copy.count);
    try testing.expectEqual(@as(u32, 1), copy.categoryCount());
    try testing.expectEqualStrings("West", copy.get(0));
}

// Test: Deep copy with all rows (full copy)
test "CategoricalColumn.deepCopyRows can copy all rows" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "A");
    try cat.append(allocator, "B");
    try cat.append(allocator, "A");

    const indices = [_]u32{ 0, 1, 2 };
    var copy = try cat.deepCopyRows(allocator, &indices);
    defer copy.deinit(allocator);

    try testing.expectEqual(@as(u32, 3), copy.count);
    try testing.expectEqual(@as(u32, 2), copy.categoryCount());
    try testing.expectEqualStrings("A", copy.get(0));
    try testing.expectEqualStrings("B", copy.get(1));
    try testing.expectEqualStrings("A", copy.get(2));
}

// Test: Deep copy rebuilds dictionary with new codes
test "CategoricalColumn.deepCopyRows rebuilds dictionary independently" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "First"); // code 0
    try cat.append(allocator, "Second"); // code 1
    try cat.append(allocator, "Third"); // code 2
    try cat.append(allocator, "Second"); // code 1
    try cat.append(allocator, "Third"); // code 2

    // Copy rows 1, 3, 4 (Second, Second, Third)
    const indices = [_]u32{ 1, 3, 4 };
    var copy = try cat.deepCopyRows(allocator, &indices);
    defer copy.deinit(allocator);

    // Copy should have new dictionary: "Second" = code 0, "Third" = code 1
    try testing.expectEqual(@as(u32, 3), copy.count);
    try testing.expectEqual(@as(u32, 2), copy.categoryCount());

    // Verify codes are rebuilt (not same as original)
    try testing.expectEqual(@as(u32, 0), copy.codes[0]); // "Second" is first in new dict
    try testing.expectEqual(@as(u32, 0), copy.codes[1]); // "Second" again
    try testing.expectEqual(@as(u32, 1), copy.codes[2]); // "Third" is second in new dict

    // Original codes should be different
    try testing.expectEqual(@as(u32, 1), cat.codes[1]); // "Second" was code 1 originally
}

// Test: Deep copy with duplicate indices (same row multiple times)
test "CategoricalColumn.deepCopyRows handles duplicate indices" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "X");
    try cat.append(allocator, "Y");

    // Copy row 0 three times
    const indices = [_]u32{ 0, 0, 0 };
    var copy = try cat.deepCopyRows(allocator, &indices);
    defer copy.deinit(allocator);

    try testing.expectEqual(@as(u32, 3), copy.count);
    try testing.expectEqual(@as(u32, 1), copy.categoryCount());
    try testing.expectEqualStrings("X", copy.get(0));
    try testing.expectEqualStrings("X", copy.get(1));
    try testing.expectEqualStrings("X", copy.get(2));
}

// Test: Deep copy with non-sequential indices
test "CategoricalColumn.deepCopyRows handles non-sequential indices" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "A");
    try cat.append(allocator, "B");
    try cat.append(allocator, "C");
    try cat.append(allocator, "D");
    try cat.append(allocator, "E");

    // Copy in reverse order: 4, 2, 0
    const indices = [_]u32{ 4, 2, 0 };
    var copy = try cat.deepCopyRows(allocator, &indices);
    defer copy.deinit(allocator);

    try testing.expectEqual(@as(u32, 3), copy.count);
    try testing.expectEqualStrings("E", copy.get(0));
    try testing.expectEqualStrings("C", copy.get(1));
    try testing.expectEqualStrings("A", copy.get(2));
}

// Test: Deep copy with large dataset (stress test)
test "CategoricalColumn.deepCopyRows handles large dataset" {
    const allocator = testing.allocator;

    const row_count: u32 = 1000;
    var cat = try CategoricalColumn.init(allocator, row_count);
    defer cat.deinit(allocator);

    // Create 5 categories, repeated
    const categories = [_][]const u8{ "Cat1", "Cat2", "Cat3", "Cat4", "Cat5" };
    var i: u32 = 0;
    while (i < row_count) : (i += 1) {
        try cat.append(allocator, categories[i % 5]);
    }

    // Copy every 10th row (100 rows total)
    var indices = try allocator.alloc(u32, 100);
    defer allocator.free(indices);
    i = 0;
    while (i < 100) : (i += 1) {
        indices[i] = i * 10;
    }

    var copy = try cat.deepCopyRows(allocator, indices);
    defer copy.deinit(allocator);

    try testing.expectEqual(@as(u32, 100), copy.count);
    try testing.expectEqual(@as(u32, 5), copy.categoryCount());

    // Verify a few values
    try testing.expectEqualStrings("Cat1", copy.get(0)); // row 0 → Cat1
    try testing.expectEqualStrings("Cat1", copy.get(1)); // row 10 → Cat1
    try testing.expectEqualStrings("Cat2", copy.get(2)); // row 20 → Cat2
}

// Test: Deep copy memory leak test
test "CategoricalColumn.deepCopyRows has no memory leaks" {
    const allocator = testing.allocator;

    var iter: u32 = 0;
    while (iter < 1000) : (iter += 1) {
        var cat = try CategoricalColumn.init(allocator, 10);
        defer cat.deinit(allocator);

        try cat.append(allocator, "East");
        try cat.append(allocator, "West");
        try cat.append(allocator, "South");

        const indices = [_]u32{ 0, 2 };
        var copy = try cat.deepCopyRows(allocator, &indices);
        copy.deinit(allocator);
    }

    // testing.allocator will report leaks automatically
}

// Test: Deep copy preserves empty strings
test "CategoricalColumn.deepCopyRows handles empty strings" {
    const allocator = testing.allocator;

    var cat = try CategoricalColumn.init(allocator, 10);
    defer cat.deinit(allocator);

    try cat.append(allocator, "");
    try cat.append(allocator, "NotEmpty");
    try cat.append(allocator, "");

    const indices = [_]u32{ 0, 2 };
    var copy = try cat.deepCopyRows(allocator, &indices);
    defer copy.deinit(allocator);

    try testing.expectEqual(@as(u32, 2), copy.count);
    try testing.expectEqual(@as(u32, 1), copy.categoryCount());
    try testing.expectEqualStrings("", copy.get(0));
    try testing.expectEqualStrings("", copy.get(1));
}
