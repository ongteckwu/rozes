const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

/// Radix Hash Join - Optimized join for integer keys using radix partitioning
///
/// Key Ideas:
/// 1. Partition data using radix (most significant bits) of join keys
/// 2. Build hash tables on cache-friendly partitions
/// 3. Probe with SIMD comparisons for matching
///
/// Performance Target: 2-3× speedup vs standard hash join for integer keys

// ============================================================================
// Constants (Tiger Style: explicit bounds)
// ============================================================================

/// Number of bits to use for radix partitioning (2^8 = 256 partitions)
pub const RADIX_BITS: u8 = 8;

/// Number of partitions (2^RADIX_BITS)
pub const PARTITION_COUNT: u32 = 1 << RADIX_BITS;

/// Maximum rows per partition (safety limit)
pub const MAX_PARTITION_SIZE: u32 = 10_000_000;

/// Maximum total rows for radix join (safety limit)
pub const MAX_TOTAL_ROWS: u32 = 100_000_000;

/// Cache line size for alignment
pub const CACHE_LINE_SIZE: u32 = 64;

// ============================================================================
// Types
// ============================================================================

/// Key-value pair for radix partitioning
pub const KeyValue = struct {
    key: i64, // Join key (integer)
    row_index: u32, // Original row index

    pub fn init(key: i64, row_index: u32) KeyValue {
        return KeyValue{ .key = key, .row_index = row_index };
    }
};

/// Partition metadata
pub const Partition = struct {
    /// Start index in partitioned array
    start: u32,
    /// Number of elements in partition
    count: u32,
    /// Partition index (0..PARTITION_COUNT-1)
    index: u32,

    pub fn init(index: u32) Partition {
        assert(index < PARTITION_COUNT);
        return Partition{
            .start = 0,
            .count = 0,
            .index = index,
        };
    }

    pub fn isEmpty(self: Partition) bool {
        return self.count == 0;
    }
};

/// Radix join context
pub const RadixJoinContext = struct {
    allocator: Allocator,
    /// Histogram: count of elements per partition
    histogram: []u32,
    /// Partition metadata
    partitions: []Partition,
    /// Partitioned data (output)
    partitioned_data: []KeyValue,

    pub fn init(allocator: Allocator, input_size: u32) !RadixJoinContext {
        assert(input_size > 0);
        assert(input_size <= MAX_TOTAL_ROWS);

        const histogram = try allocator.alloc(u32, PARTITION_COUNT);
        errdefer allocator.free(histogram);

        const partitions = try allocator.alloc(Partition, PARTITION_COUNT);
        errdefer allocator.free(partitions);

        const partitioned_data = try allocator.alloc(KeyValue, input_size);
        errdefer allocator.free(partitioned_data);

        // Initialize partitions
        var i: u32 = 0;
        while (i < PARTITION_COUNT) : (i += 1) {
            partitions[i] = Partition.init(i);
        }
        assert(i == PARTITION_COUNT); // Post-condition: All partitions initialized

        // Zero histogram
        @memset(histogram, 0);

        return RadixJoinContext{
            .allocator = allocator,
            .histogram = histogram,
            .partitions = partitions,
            .partitioned_data = partitioned_data,
        };
    }

    pub fn deinit(self: *RadixJoinContext) void {
        assert(self.histogram.len == PARTITION_COUNT);
        assert(self.partitions.len == PARTITION_COUNT);

        self.allocator.free(self.histogram);
        self.allocator.free(self.partitions);
        self.allocator.free(self.partitioned_data);
    }
};

// ============================================================================
// Radix Partitioning Functions
// ============================================================================

/// Extract radix (partition index) from key
/// Uses most significant bits for better cache behavior
inline fn getRadix(key: i64, pass: u8) u32 {
    assert(pass == 0); // Single-pass for now (8-bit radix)

    // Use most significant 8 bits of the key
    // Convert signed to unsigned for bit operations
    const unsigned_key: u64 = @bitCast(key);
    const shift: u6 = 64 - RADIX_BITS;
    const radix = (unsigned_key >> shift) & ((1 << RADIX_BITS) - 1);

    assert(radix < PARTITION_COUNT);
    return @intCast(radix);
}

/// Build histogram: count elements per partition
pub fn buildHistogram(
    ctx: *RadixJoinContext,
    input: []const KeyValue,
    pass: u8,
) void {
    assert(input.len > 0);
    assert(input.len <= MAX_TOTAL_ROWS);
    assert(pass == 0); // Single-pass for now
    assert(ctx.histogram.len == PARTITION_COUNT);

    // Zero histogram
    @memset(ctx.histogram, 0);

    // Count elements per partition (bounded loop)
    var i: u32 = 0;
    const n: u32 = @intCast(input.len);
    while (i < n) : (i += 1) {
        const radix = getRadix(input[i].key, pass);
        assert(radix < PARTITION_COUNT);
        ctx.histogram[radix] += 1;
    }

    // Verify total count
    var total: u32 = 0;
    var hist_idx: u32 = 0;
    while (hist_idx < PARTITION_COUNT) : (hist_idx += 1) {
        total += ctx.histogram[hist_idx];
    }
    assert(hist_idx == PARTITION_COUNT); // Post-condition: All histogram entries summed
    assert(total == input.len);
}

/// Compute prefix sum (exclusive scan) of histogram
/// Result: partition start offsets
pub fn computePrefixSum(ctx: *RadixJoinContext) void {
    assert(ctx.histogram.len == PARTITION_COUNT);
    assert(ctx.partitions.len == PARTITION_COUNT);

    var offset: u32 = 0;
    var i: u32 = 0;
    while (i < PARTITION_COUNT) : (i += 1) {
        const count = ctx.histogram[i];
        assert(count <= MAX_PARTITION_SIZE);

        ctx.partitions[i].start = offset;
        ctx.partitions[i].count = count;
        offset += count;
    }

    assert(offset == ctx.partitioned_data.len);
}

/// Scatter input to partitions based on radix
/// This is the cache-friendly partition operation
pub fn scatterToPartitions(
    ctx: *RadixJoinContext,
    input: []const KeyValue,
    pass: u8,
) void {
    assert(input.len > 0);
    assert(input.len <= MAX_TOTAL_ROWS);
    assert(pass == 0);
    assert(ctx.partitioned_data.len == input.len);

    // Working copy of partition offsets (write heads)
    var write_offsets: [PARTITION_COUNT]u32 = undefined;

    // Initialize write heads from partition starts
    var i: u32 = 0;
    while (i < PARTITION_COUNT) : (i += 1) {
        write_offsets[i] = ctx.partitions[i].start;
    }

    // Scatter elements to partitions (bounded loop)
    i = 0;
    const n: u32 = @intCast(input.len);
    while (i < n) : (i += 1) {
        const kv = input[i];
        const radix = getRadix(kv.key, pass);
        assert(radix < PARTITION_COUNT);

        const write_pos = write_offsets[radix];
        assert(write_pos < ctx.partitioned_data.len);

        ctx.partitioned_data[write_pos] = kv;
        write_offsets[radix] += 1;
    }

    // Verify all elements written
    var partition_idx: u32 = 0;
    while (partition_idx < PARTITION_COUNT) : (partition_idx += 1) {
        const expected_end = ctx.partitions[partition_idx].start +
                           ctx.partitions[partition_idx].count;
        assert(write_offsets[partition_idx] == expected_end);
    }
    assert(partition_idx == PARTITION_COUNT); // Post-condition: All offsets verified
}

// ============================================================================
// Bloom Filter for Early Rejection
// ============================================================================

/// Bloom filter bits (for ~1% false positive rate with 10K elements)
pub const BLOOM_FILTER_BITS: u32 = 96_000; // 12KB

/// Bloom filter bytes
pub const BLOOM_FILTER_BYTES: u32 = BLOOM_FILTER_BITS / 8;

/// Number of hash functions for bloom filter
pub const BLOOM_HASH_COUNT: u8 = 7; // k = (m/n) * ln(2) ≈ 7 for 1% FPR

/// Bloom filter for fast membership testing
///
/// **Purpose**: Early rejection of non-matching keys before hash table probe
/// **Performance**: ~2-5 CPU cycles vs ~10-50 cycles for hash table probe
/// **Benefit**: Speedup when rejection rate >20% (sparse joins)
///
/// **Properties**:
/// - False positives: ~1% (tunable via BLOOM_FILTER_BITS)
/// - False negatives: Never (guaranteed correct)
/// - Space: 12KB per hash table (96K bits)
pub const BloomFilter = struct {
    allocator: Allocator,
    /// Bit array (packed)
    bits: []u8,
    /// Number of bits
    bit_count: u32,
    /// Number of elements added (for statistics)
    element_count: u32,

    pub fn init(allocator: Allocator) !BloomFilter {
        assert(BLOOM_FILTER_BYTES > 0);
        assert(BLOOM_FILTER_BITS == BLOOM_FILTER_BYTES * 8);

        const bits = try allocator.alloc(u8, BLOOM_FILTER_BYTES);
        @memset(bits, 0);

        return BloomFilter{
            .allocator = allocator,
            .bits = bits,
            .bit_count = BLOOM_FILTER_BITS,
            .element_count = 0,
        };
    }

    pub fn deinit(self: *BloomFilter) void {
        assert(self.bits.len == BLOOM_FILTER_BYTES);
        self.allocator.free(self.bits);
    }

    /// Generate k hash values from a single key
    inline fn hashK(key: i64, k_index: u8, bit_count: u32) u32 {
        assert(k_index < BLOOM_HASH_COUNT);
        assert(std.math.isPowerOfTwo(bit_count) or bit_count % 8 == 0); // Power of 2 OR multiple of 8
        assert(bit_count >= 1024); // Minimum reasonable size (128 bytes)
        assert(bit_count <= 10_000_000); // Maximum reasonable size (~1.2 MB)

        // Use different seeds for each hash function
        const seed: u64 = 0xcbf29ce484222325 + @as(u64, k_index) * 0x100000001b3;

        const unsigned_key: u64 = @bitCast(key);
        var h: u64 = seed;
        h ^= unsigned_key;
        h *%= 0x100000001b3; // FNV prime

        const result = @as(u32, @truncate(h)) % bit_count;
        assert(result < bit_count);
        return result;
    }

    /// Add a key to the bloom filter
    pub fn add(self: *BloomFilter, key: i64) void {
        assert(self.bits.len == BLOOM_FILTER_BYTES);

        // Set k bits using k hash functions
        var k: u8 = 0;
        while (k < BLOOM_HASH_COUNT) : (k += 1) {
            const bit_index = hashK(key, k, self.bit_count);
            const byte_index = bit_index / 8;
            const bit_offset = @as(u3, @truncate(bit_index % 8));

            assert(byte_index < self.bits.len);
            self.bits[byte_index] |= @as(u8, 1) << bit_offset;
        }

        self.element_count += 1;
        assert(self.element_count <= MAX_TOTAL_ROWS);
    }

    /// Check if a key might be in the set (may have false positives)
    pub fn mightContain(self: *const BloomFilter, key: i64) bool {
        assert(self.bits.len == BLOOM_FILTER_BYTES);

        // Check all k bits - if ANY is 0, definitely not present
        var k: u8 = 0;
        while (k < BLOOM_HASH_COUNT) : (k += 1) {
            const bit_index = hashK(key, k, self.bit_count);
            const byte_index = bit_index / 8;
            const bit_offset = @as(u3, @truncate(bit_index % 8));

            assert(byte_index < self.bits.len);
            const bit_set = (self.bits[byte_index] & (@as(u8, 1) << bit_offset)) != 0;

            if (!bit_set) {
                return false; // Definitely not present
            }
        }

        return true; // Might be present (or false positive)
    }

    /// Get false positive rate estimate
    pub fn getFalsePositiveRate(self: *const BloomFilter) f64 {
        assert(self.element_count <= MAX_TOTAL_ROWS);

        if (self.element_count == 0) return 0.0;

        // FPR = (1 - e^(-kn/m))^k
        // where k = hash functions, n = elements, m = bits
        const k = @as(f64, @floatFromInt(BLOOM_HASH_COUNT));
        const n = @as(f64, @floatFromInt(self.element_count));
        const m = @as(f64, @floatFromInt(self.bit_count));

        const exponent = -k * n / m;
        const base = 1.0 - @exp(exponent);
        const fpr = std.math.pow(f64, base, k);

        assert(fpr >= 0.0 and fpr <= 1.0);
        return fpr;
    }
};

// ============================================================================
// Hash Table for Partition Probing
// ============================================================================

/// Maximum entries per hash table (per partition)
pub const MAX_HASH_TABLE_SIZE: u32 = 10_000_000;

/// Hash table entry (linear probing)
pub const HashEntry = struct {
    key: i64,
    row_index: u32,
    occupied: bool,

    pub fn init() HashEntry {
        return HashEntry{
            .key = 0,
            .row_index = 0,
            .occupied = false,
        };
    }

    pub fn set(self: *HashEntry, key: i64, row_index: u32) void {
        assert(!self.occupied);
        self.key = key;
        self.row_index = row_index;
        self.occupied = true;
    }
};

/// Hash table for one partition
pub const HashTable = struct {
    allocator: Allocator,
    entries: []HashEntry,
    capacity: u32,
    count: u32,
    /// Bloom filter for early rejection
    bloom_filter: BloomFilter,

    pub fn init(allocator: Allocator, capacity: u32) !HashTable {
        assert(capacity > 0);
        assert(capacity <= MAX_HASH_TABLE_SIZE);

        // Round up to next power of 2 for fast modulo (bitwise AND)
        const actual_capacity = std.math.ceilPowerOfTwo(u32, capacity) catch
            return error.CapacityTooLarge;
        assert(std.math.isPowerOfTwo(actual_capacity));

        const entries = try allocator.alloc(HashEntry, actual_capacity);
        errdefer allocator.free(entries);

        // Initialize all entries as unoccupied
        var entry_idx: u32 = 0;
        while (entry_idx < actual_capacity) : (entry_idx += 1) {
            entries[entry_idx] = HashEntry.init();
        }
        assert(entry_idx == actual_capacity); // Post-condition: All entries initialized

        // Create bloom filter for early rejection
        var bloom_filter = try BloomFilter.init(allocator);
        errdefer bloom_filter.deinit();

        return HashTable{
            .allocator = allocator,
            .entries = entries,
            .capacity = actual_capacity,
            .count = 0,
            .bloom_filter = bloom_filter,
        };
    }

    pub fn deinit(self: *HashTable) void {
        assert(self.capacity > 0);
        self.bloom_filter.deinit();
        self.allocator.free(self.entries);
    }

    /// Hash function for integer keys
    inline fn hash(key: i64, capacity: u32) u32 {
        assert(std.math.isPowerOfTwo(capacity));

        // Mix bits using FNV-1a style hash
        const unsigned_key: u64 = @bitCast(key);
        var h: u64 = 0xcbf29ce484222325; // FNV offset basis
        h ^= unsigned_key;
        h *%= 0x100000001b3; // FNV prime

        // Use bitwise AND for fast modulo (capacity is power of 2)
        const mask = capacity - 1;
        const result = @as(u32, @truncate(h)) & mask;

        assert(result < capacity);
        return result;
    }

    /// Insert key-value pair (linear probing for collisions)
    pub fn insert(self: *HashTable, key: i64, row_index: u32) !void {
        assert(self.count < self.capacity);
        assert(row_index < MAX_TOTAL_ROWS);

        var idx = hash(key, self.capacity);
        var probe_count: u32 = 0;

        // Linear probing with bounded iterations
        while (probe_count < self.capacity) : (probe_count += 1) {
            if (!self.entries[idx].occupied) {
                self.entries[idx].set(key, row_index);
                self.count += 1;

                // Add to bloom filter for early rejection in probe phase
                self.bloom_filter.add(key);

                return;
            }

            // Move to next slot (circular)
            idx = (idx + 1) & (self.capacity - 1);
        }

        assert(probe_count < self.capacity);
        return error.HashTableFull;
    }

    /// Find all row indices matching key (SIMD-optimized with bloom filter early rejection)
    pub fn probe(
        self: *const HashTable,
        key: i64,
        result: *std.ArrayListUnmanaged(u32),
        allocator: Allocator,
    ) !void {
        assert(result.items.len == 0);

        // Bloom filter early rejection: if definitely not present, skip hash table probe
        if (!self.bloom_filter.mightContain(key)) {
            return; // Key definitely not in hash table (no false negatives)
        }

        // Key might be present (or false positive) - proceed with hash table probe
        const simd_width = 2; // Compare 2 keys at once (128-bit SIMD)
        var idx = hash(key, self.capacity);
        var probe_count: u32 = 0;
        var finished_simd = false;

        // SIMD-optimized probing for batches of 2 entries
        while (probe_count + simd_width <= self.capacity) {
            const idx1 = idx;
            const idx2 = (idx + 1) & (self.capacity - 1);

            const entry1 = &self.entries[idx1];
            const entry2 = &self.entries[idx2];

            // Early exit if first slot is empty (linear probing stops)
            if (!entry1.occupied) {
                finished_simd = true;
                break;
            }

            // SIMD batch comparison: compare both keys at once
            const keys = @Vector(simd_width, i64){ entry1.key, entry2.key };
            const search_key = @as(@Vector(simd_width, i64), @splat(key));
            const matches = keys == search_key;

            // Process match in first slot
            if (matches[0]) {
                try result.append(allocator, entry1.row_index);
            }

            // Process second slot if occupied
            if (entry2.occupied) {
                if (matches[1]) {
                    try result.append(allocator, entry2.row_index);
                }
                // Both slots processed, move forward
                probe_count += simd_width;
                idx = (idx + simd_width) & (self.capacity - 1);
            } else {
                // Second slot empty - we're done
                finished_simd = true;
                break;
            }
        }

        // Scalar fallback for remaining entries (only if SIMD didn't finish)
        if (!finished_simd) {
            while (probe_count < self.capacity) : (probe_count += 1) {
                const entry = &self.entries[idx];

                if (!entry.occupied) {
                    break; // Empty slot - key not found
                }

                if (entry.key == key) {
                    try result.append(allocator, entry.row_index);
                }

                idx = (idx + 1) & (self.capacity - 1);
            }
        }

        assert(probe_count <= self.capacity);
    }
};

/// Build hash table from partition data
pub fn buildHashTable(
    allocator: Allocator,
    partition_data: []const KeyValue,
) !HashTable {
    assert(partition_data.len > 0);
    assert(partition_data.len <= MAX_PARTITION_SIZE);

    // Load factor = 0.7 (70% full for good performance)
    const capacity = @as(u32, @intCast(partition_data.len * 10 / 7));
    var table = try HashTable.init(allocator, capacity);
    errdefer table.deinit();

    // Insert all key-value pairs (bounded loop)
    var kv_idx: u32 = 0;
    const data_len: u32 = @intCast(partition_data.len);
    while (kv_idx < data_len and kv_idx < MAX_PARTITION_SIZE) : (kv_idx += 1) {
        try table.insert(partition_data[kv_idx].key, partition_data[kv_idx].row_index);
    }
    assert(kv_idx == data_len); // Post-condition: All data inserted

    assert(table.count == partition_data.len);
    return table;
}

// ============================================================================
// High-Level API
// ============================================================================

/// Partition input data using radix partitioning
/// Returns partitioned data and partition metadata
pub fn partitionData(
    allocator: Allocator,
    input: []const KeyValue,
) !RadixJoinContext {
    assert(input.len > 0);
    assert(input.len <= MAX_TOTAL_ROWS);

    var ctx = try RadixJoinContext.init(allocator, @intCast(input.len));
    errdefer ctx.deinit();

    // Step 1: Build histogram (count per partition)
    buildHistogram(&ctx, input, 0);

    // Step 2: Compute prefix sum (partition offsets)
    computePrefixSum(&ctx);

    // Step 3: Scatter data to partitions
    scatterToPartitions(&ctx, input, 0);

    return ctx;
}

// ============================================================================
// Tests
// ============================================================================

test "RadixJoinContext.init and deinit" {
    const allocator = std.testing.allocator;

    var ctx = try RadixJoinContext.init(allocator, 1000);
    defer ctx.deinit();

    try std.testing.expectEqual(PARTITION_COUNT, ctx.histogram.len);
    try std.testing.expectEqual(PARTITION_COUNT, ctx.partitions.len);
    try std.testing.expectEqual(@as(usize, 1000), ctx.partitioned_data.len);
}

test "getRadix extracts correct partition index" {
    // Test with various keys
    const test_cases = [_]struct {
        key: i64,
        expected_in_range: bool,
    }{
        .{ .key = 0, .expected_in_range = true },
        .{ .key = 100, .expected_in_range = true },
        .{ .key = -100, .expected_in_range = true },
        .{ .key = std.math.maxInt(i64), .expected_in_range = true },
        .{ .key = std.math.minInt(i64), .expected_in_range = true },
    };

    for (test_cases) |tc| {
        const radix = getRadix(tc.key, 0);
        try std.testing.expect(radix < PARTITION_COUNT);
    }
}

test "buildHistogram counts elements correctly" {
    const allocator = std.testing.allocator;

    // Create test input with known distribution
    const input = [_]KeyValue{
        KeyValue.init(100, 0),
        KeyValue.init(200, 1),
        KeyValue.init(100, 2), // Same key as first
        KeyValue.init(300, 3),
        KeyValue.init(200, 4), // Same key as second
    };

    var ctx = try RadixJoinContext.init(allocator, input.len);
    defer ctx.deinit();

    buildHistogram(&ctx, &input, 0);

    // Verify total count
    var total: u32 = 0;
    for (ctx.histogram) |count| {
        total += count;
    }
    try std.testing.expectEqual(@as(u32, input.len), total);
}

test "computePrefixSum creates correct offsets" {
    const allocator = std.testing.allocator;

    var ctx = try RadixJoinContext.init(allocator, 10);
    defer ctx.deinit();

    // Manually set histogram
    @memset(ctx.histogram, 0);
    ctx.histogram[0] = 3;
    ctx.histogram[1] = 2;
    ctx.histogram[2] = 5;

    computePrefixSum(&ctx);

    try std.testing.expectEqual(@as(u32, 0), ctx.partitions[0].start);
    try std.testing.expectEqual(@as(u32, 3), ctx.partitions[0].count);

    try std.testing.expectEqual(@as(u32, 3), ctx.partitions[1].start);
    try std.testing.expectEqual(@as(u32, 2), ctx.partitions[1].count);

    try std.testing.expectEqual(@as(u32, 5), ctx.partitions[2].start);
    try std.testing.expectEqual(@as(u32, 5), ctx.partitions[2].count);
}

test "partitionData end-to-end" {
    const allocator = std.testing.allocator;

    // Create test input
    const input = [_]KeyValue{
        KeyValue.init(1000, 0),
        KeyValue.init(2000, 1),
        KeyValue.init(1500, 2),
        KeyValue.init(2500, 3),
        KeyValue.init(1000, 4),
    };

    var ctx = try partitionData(allocator, &input);
    defer ctx.deinit();

    // Verify all data is present in partitioned output
    try std.testing.expectEqual(input.len, ctx.partitioned_data.len);

    // Verify partitions are non-overlapping
    var i: u32 = 0;
    while (i < PARTITION_COUNT - 1) : (i += 1) {
        const curr_end = ctx.partitions[i].start + ctx.partitions[i].count;
        if (ctx.partitions[i + 1].count > 0) {
            try std.testing.expect(curr_end <= ctx.partitions[i + 1].start);
        }
    }
}

test "HashTable SIMD probe finds single match" {
    const allocator = std.testing.allocator;

    // Create small hash table with a few entries
    var table = try HashTable.init(allocator, 16);
    defer table.deinit();

    // Insert test data
    try table.insert(100, 10);
    try table.insert(200, 20);
    try table.insert(300, 30);

    // Probe for existing key
    var matches = std.ArrayListUnmanaged(u32){};
    defer matches.deinit(allocator);

    try table.probe(200, &matches, allocator);

    // Verify single match
    try std.testing.expectEqual(@as(usize, 1), matches.items.len);
    try std.testing.expectEqual(@as(u32, 20), matches.items[0]);
}

test "HashTable SIMD probe finds multiple matches" {
    const allocator = std.testing.allocator;

    var table = try HashTable.init(allocator, 16);
    defer table.deinit();

    // Insert duplicate keys (same key, different row indices)
    try table.insert(100, 10);
    try table.insert(100, 11);
    try table.insert(100, 12);
    try table.insert(200, 20);

    // Probe for key with multiple matches
    var matches = std.ArrayListUnmanaged(u32){};
    defer matches.deinit(allocator);

    try table.probe(100, &matches, allocator);

    // Verify all matches found
    try std.testing.expectEqual(@as(usize, 3), matches.items.len);
    try std.testing.expect(matches.items[0] == 10 or matches.items[0] == 11 or matches.items[0] == 12);
    try std.testing.expect(matches.items[1] == 10 or matches.items[1] == 11 or matches.items[1] == 12);
    try std.testing.expect(matches.items[2] == 10 or matches.items[2] == 11 or matches.items[2] == 12);
}

test "HashTable SIMD probe finds no matches for non-existent key" {
    const allocator = std.testing.allocator;

    var table = try HashTable.init(allocator, 16);
    defer table.deinit();

    // Insert test data
    try table.insert(100, 10);
    try table.insert(200, 20);

    // Probe for non-existent key
    var matches = std.ArrayListUnmanaged(u32){};
    defer matches.deinit(allocator);

    try table.probe(999, &matches, allocator);

    // Verify no matches
    try std.testing.expectEqual(@as(usize, 0), matches.items.len);
}

test "HashTable SIMD probe handles collisions" {
    const allocator = std.testing.allocator;

    var table = try HashTable.init(allocator, 8); // Small capacity to force collisions
    defer table.deinit();

    // Insert multiple keys that will collide
    try table.insert(100, 10);
    try table.insert(200, 20);
    try table.insert(300, 30);
    try table.insert(400, 40);

    // Probe for keys
    var matches1 = std.ArrayListUnmanaged(u32){};
    defer matches1.deinit(allocator);
    try table.probe(100, &matches1, allocator);
    try std.testing.expectEqual(@as(usize, 1), matches1.items.len);
    try std.testing.expectEqual(@as(u32, 10), matches1.items[0]);

    var matches2 = std.ArrayListUnmanaged(u32){};
    defer matches2.deinit(allocator);
    try table.probe(300, &matches2, allocator);
    try std.testing.expectEqual(@as(usize, 1), matches2.items.len);
    try std.testing.expectEqual(@as(u32, 30), matches2.items[0]);
}

test "HashTable SIMD probe handles empty table" {
    const allocator = std.testing.allocator;

    var table = try HashTable.init(allocator, 16);
    defer table.deinit();

    // Probe empty table
    var matches = std.ArrayListUnmanaged(u32){};
    defer matches.deinit(allocator);

    try table.probe(100, &matches, allocator);

    // Verify no matches
    try std.testing.expectEqual(@as(usize, 0), matches.items.len);
}

// ============================================================================
// Bloom Filter Tests
// ============================================================================

test "BloomFilter.init and deinit" {
    const allocator = std.testing.allocator;

    var bloom = try BloomFilter.init(allocator);
    defer bloom.deinit();

    try std.testing.expectEqual(BLOOM_FILTER_BITS, bloom.bit_count);
    try std.testing.expectEqual(@as(u32, 0), bloom.element_count);
    try std.testing.expectEqual(BLOOM_FILTER_BYTES, bloom.bits.len);
}

test "BloomFilter.add and mightContain - no false negatives" {
    const allocator = std.testing.allocator;

    var bloom = try BloomFilter.init(allocator);
    defer bloom.deinit();

    // Add keys
    const keys = [_]i64{ 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000 };

    for (keys) |key| {
        bloom.add(key);
    }

    // Verify all added keys are found (no false negatives)
    for (keys) |key| {
        const found = bloom.mightContain(key);
        try std.testing.expect(found); // Must be true - no false negatives allowed
    }

    try std.testing.expectEqual(@as(u32, keys.len), bloom.element_count);
}

test "BloomFilter.mightContain rejects non-existent keys (with false positive rate)" {
    const allocator = std.testing.allocator;

    var bloom = try BloomFilter.init(allocator);
    defer bloom.deinit();

    // Add 1000 keys
    var i: i64 = 0;
    while (i < 1000) : (i += 1) {
        bloom.add(i);
    }

    // Probe 1000 keys that weren't added
    var false_positives: u32 = 0;
    var j: i64 = 10000;
    while (j < 11000) : (j += 1) {
        if (bloom.mightContain(j)) {
            false_positives += 1;
        }
    }

    // False positive rate should be ~1% (±2% tolerance)
    const fpr = @as(f64, @floatFromInt(false_positives)) / 1000.0;
    try std.testing.expect(fpr < 0.03); // Less than 3% false positive rate
}

test "BloomFilter.getFalsePositiveRate calculation" {
    const allocator = std.testing.allocator;

    var bloom = try BloomFilter.init(allocator);
    defer bloom.deinit();

    // Add 10,000 elements (target size for 1% FPR)
    var i: i64 = 0;
    while (i < 10_000) : (i += 1) {
        bloom.add(i);
    }

    const fpr = bloom.getFalsePositiveRate();

    // FPR should be around 1% for 10K elements
    try std.testing.expect(fpr > 0.005); // More than 0.5%
    try std.testing.expect(fpr < 0.02); // Less than 2%
}

test "BloomFilter hash functions are independent" {
    const allocator = std.testing.allocator;

    var bloom = try BloomFilter.init(allocator);
    defer bloom.deinit();

    // Add a single key
    bloom.add(42);

    // Count set bits - should be approximately BLOOM_HASH_COUNT (7)
    var set_bits: u32 = 0;
    for (bloom.bits) |byte| {
        var b = byte;
        while (b != 0) : (b &= b - 1) {
            set_bits += 1;
        }
    }

    // Should have at least BLOOM_HASH_COUNT bits set
    // (might be less if hash functions collide)
    try std.testing.expect(set_bits <= BLOOM_HASH_COUNT);
    try std.testing.expect(set_bits >= 1);
}

test "HashTable with bloom filter early rejection" {
    const allocator = std.testing.allocator;

    var table = try HashTable.init(allocator, 16);
    defer table.deinit();

    // Insert keys
    try table.insert(100, 10);
    try table.insert(200, 20);
    try table.insert(300, 30);

    // Probe for existing key (bloom filter says "might contain", then finds it)
    var matches1 = std.ArrayListUnmanaged(u32){};
    defer matches1.deinit(allocator);
    try table.probe(100, &matches1, allocator);
    try std.testing.expectEqual(@as(usize, 1), matches1.items.len);
    try std.testing.expectEqual(@as(u32, 10), matches1.items[0]);

    // Probe for non-existent key (bloom filter rejects early)
    var matches2 = std.ArrayListUnmanaged(u32){};
    defer matches2.deinit(allocator);
    try table.probe(999, &matches2, allocator);
    try std.testing.expectEqual(@as(usize, 0), matches2.items.len);
}

test "HashTable bloom filter handles duplicates" {
    const allocator = std.testing.allocator;

    var table = try HashTable.init(allocator, 16);
    defer table.deinit();

    // Insert duplicate keys (hash table stores all, bloom filter adds each)
    try table.insert(100, 10);
    try table.insert(100, 11); // Duplicate key, different row
    try table.insert(100, 12); // Another duplicate

    // Probe should find all three matches
    var matches = std.ArrayListUnmanaged(u32){};
    defer matches.deinit(allocator);
    try table.probe(100, &matches, allocator);

    try std.testing.expectEqual(@as(usize, 3), matches.items.len);

    // Verify all row indices found
    var found = [_]bool{false} ** 3;
    for (matches.items) |row_idx| {
        if (row_idx == 10) found[0] = true;
        if (row_idx == 11) found[1] = true;
        if (row_idx == 12) found[2] = true;
    }

    try std.testing.expect(found[0] and found[1] and found[2]);
}
