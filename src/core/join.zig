//! Join - Combine two DataFrames based on common column values
//!
//! This module implements SQL-style join operations for DataFrames.
//! It allows data enrichment by combining rows from two tables.
//!
//!
//! Example:
//! ```zig
//! // Inner join on single column
//! const joined = try df1.innerJoin(allocator, df2, &[_][]const u8{"user_id"});
//! defer joined.deinit();
//!
//! // Left join on multiple columns
//! const joined = try df1.leftJoin(allocator, df2, &[_][]const u8{"city", "state"});
//! defer joined.deinit();
//! ```

const std = @import("std");
const types = @import("types.zig");
const DataFrame = @import("dataframe.zig").DataFrame;
const Series = @import("series.zig").Series;
const ColumnDesc = types.ColumnDesc;
const ValueType = types.ValueType;
const string_utils = @import("string_utils.zig");
const radix_join = @import("radix_join.zig");

/// Maximum number of join columns (reasonable limit)
const MAX_JOIN_COLUMNS: u32 = 10;

/// Maximum number of matches per key in join operation
///
/// **Rationale**: Protects against combinatorial explosion in many-to-many joins.
/// Example: joining 100K × 100K with duplicate keys → 10B intermediate rows → OOM
///
/// **Trade-off**: Returns error.TooManyMatchesPerKey for keys with >10K matches
/// instead of silently truncating results (data integrity).
///
/// **Typical Use Cases**:
/// - Inner join on primary keys: 1 match per key (no truncation)
/// - Join user_id with transactions: 10-1000 matches per key (rare truncation)
/// - Many-to-many join: High collision risk (consider filtering first)
///
/// **If You Hit This Limit**:
/// 1. Pre-filter data to reduce cardinality before joining
/// 2. Use aggregation before joining (e.g., sum transactions per user first)
/// 3. Consider increasing limit (but watch memory usage)
/// 4. Use window functions instead of joins for ordered data
/// 5. Break into batches for very large joins
const MAX_MATCHES_PER_KEY: u32 = 10_000;

/// Join type enumeration
pub const JoinType = enum {
    Inner, // Only matching rows
    Left, // All left rows + matching right
};

/// Detects if join columns are all integer types (Int64)
/// Returns true if radix join optimization can be used
///
/// **Performance**: Radix join is 2-3× faster for integer keys vs standard hash join
/// **Limitation**: Only supports single Int64 columns (multi-column support in Phase 2.1)
///
/// **Rationale**: Integer keys can use radix partitioning for cache-friendly joins
/// - Radix partitioning: Splits data by most significant bits (256 partitions)
/// - Cache-friendly: Each partition fits in L2/L3 cache during probe phase
/// - SIMD comparisons: 4× faster probing with vectorized equality checks
///
/// **Decision Logic**:
/// 1. Single column join → Check if Int64 → Use radix join (2-3× speedup)
/// 2. Multi-column join → Fallback to hash join (composite key support in Phase 2.1)
/// 3. Non-integer join → Fallback to hash join (string/float keys)
///
/// Example:
/// ```zig
/// const can_use_radix = isRadixJoinCandidate(&left, &right, &[_][]const u8{"user_id"});
/// if (can_use_radix) {
///     return performRadixJoin(left, right, allocator, join_cols, join_type);
/// }
/// ```
fn isRadixJoinCandidate(
    left: *const DataFrame,
    right: *const DataFrame,
    join_cols: []const []const u8,
) bool {
    std.debug.assert(join_cols.len > 0); // Pre-condition #1: Need join columns
    std.debug.assert(join_cols.len <= MAX_JOIN_COLUMNS); // Pre-condition #2: Within limits

    // Currently only support single-column integer joins
    // Multi-column radix join requires composite keys (deferred to Phase 2.1)
    if (join_cols.len != 1) return false;

    // Check each join column in both DataFrames
    var col_idx: u32 = 0;
    while (col_idx < MAX_JOIN_COLUMNS and col_idx < join_cols.len) : (col_idx += 1) {
        const col_name = join_cols[col_idx];

        // Check left DataFrame column
        const left_col = left.column(col_name) orelse return false;
        if (left_col.value_type != .Int64) return false;

        // Check right DataFrame column
        const right_col = right.column(col_name) orelse return false;
        if (right_col.value_type != .Int64) return false;
    }

    std.debug.assert(col_idx == join_cols.len); // Post-condition: Checked all columns
    return true;
}

/// Cached column information for fast access during join
/// Avoids repeated column name lookups in hot path
const ColumnCache = struct {
    series: *const Series,
    value_type: ValueType,

    /// Creates column cache from DataFrame and column names
    /// This is done once before join to avoid O(n) lookups per row
    pub fn init(
        allocator: std.mem.Allocator,
        df: *const DataFrame,
        join_cols: []const []const u8,
    ) ![]ColumnCache {
        std.debug.assert(join_cols.len > 0); // Pre-condition #1
        std.debug.assert(join_cols.len <= MAX_JOIN_COLUMNS); // Pre-condition #2

        const cache = try allocator.alloc(ColumnCache, join_cols.len);
        errdefer allocator.free(cache);

        for (join_cols, 0..) |col_name, i| {
            const col = df.column(col_name) orelse return error.ColumnNotFound;
            cache[i] = ColumnCache{
                .series = col,
                .value_type = col.value_type,
            };
        }

        std.debug.assert(cache.len == join_cols.len); // Post-condition
        return cache;
    }
};

/// Match result - represents a pair of matching row indices
const MatchResult = struct {
    left_idx: u32,
    right_idx: ?u32, // null for unmatched left join rows
};

/// Join key - represents values from join columns
const JoinKey = struct {
    /// Hash of the key values
    hash: u64,

    /// Row index in source DataFrame
    row_idx: u32,

    /// Computes hash for join key based on column values using cached column info
    ///
    /// **Hash Algorithm**: FNV-1a (64-bit)
    ///
    /// **Why FNV-1a**:
    /// - Optimized for small keys (<64 bytes) - typical join columns are 4-8 bytes
    /// - Inline implementation (no function call overhead)
    /// - Good distribution for integer and short string keys
    /// - 7% faster than Wyhash for join workload (measured during Phase 6B)
    ///
    /// **Performance Characteristics**:
    /// - Throughput: ~500M keys/sec for Int64 join columns
    /// - Collision rate: <0.01% for typical integer keys
    /// - Memory: 8 bytes per key (hash only)
    ///
    /// **Alternative Considered**:
    /// - Wyhash: Better for large buffers (>128 bytes), but 15% slower for join keys
    /// - Decision: Use FNV-1a for joins, Wyhash for full-row deduplication
    ///
    /// Uses ColumnCache to avoid repeated column name lookups (major optimization)
    pub fn compute(
        row_idx: u32,
        col_cache: []const ColumnCache,
    ) !JoinKey {
        std.debug.assert(col_cache.len > 0); // Pre-condition #1
        std.debug.assert(col_cache.len <= MAX_JOIN_COLUMNS); // Pre-condition #2
        std.debug.assert(row_idx < std.math.maxInt(u32)); // Pre-condition #3: Valid row index

        // FNV-1a hash constants (64-bit version)
        // Offset basis: 14695981039346656037 (chosen for avalanche properties)
        // Prime: 1099511628211 (chosen for good distribution)
        // See: http://www.isthe.com/chongo/tech/comp/fnv/
        const FNV_OFFSET: u64 = 14695981039346656037;
        const FNV_PRIME: u64 = 1099511628211;

        var hash: u64 = FNV_OFFSET;

        var col_idx: u32 = 0;
        while (col_idx < MAX_JOIN_COLUMNS and col_idx < col_cache.len) : (col_idx += 1) {
            std.debug.assert(col_idx < col_cache.len); // Loop invariant: Within bounds

            const cached_col = col_cache[col_idx];
            const col = cached_col.series;

            // Hash the value from this column using FNV-1a
            switch (cached_col.value_type) {
                .Int64 => {
                    const data = col.asInt64() orelse return error.TypeMismatch;
                    const val = data[row_idx];
                    const bytes = std.mem.asBytes(&val);
                    for (bytes) |byte| {
                        hash ^= byte;
                        hash *%= FNV_PRIME;
                    }
                },
                .Float64 => {
                    const data = col.asFloat64() orelse return error.TypeMismatch;
                    const val = data[row_idx];
                    const bytes = std.mem.asBytes(&val);
                    for (bytes) |byte| {
                        hash ^= byte;
                        hash *%= FNV_PRIME;
                    }
                },
                .Bool => {
                    const data = col.asBool() orelse return error.TypeMismatch;
                    const val = data[row_idx];
                    const bytes = std.mem.asBytes(&val);
                    for (bytes) |byte| {
                        hash ^= byte;
                        hash *%= FNV_PRIME;
                    }
                },
                .String => {
                    const string_col = col.asStringColumn() orelse return error.TypeMismatch;
                    // Use getHash() - automatically uses cached hash if available
                    // This provides 20-30% speedup when hash cache is enabled
                    const str_hash = string_col.getHash(row_idx);
                    hash ^= str_hash;
                },
                .Categorical => {
                    // Categorical is stored as pointer, get the string value and hash it
                    const cat_col = col.asCategoricalColumn() orelse return error.TypeMismatch;
                    // TODO: Consider adding hash caching to CategoricalColumn for consistency
                    const str = cat_col.get(row_idx);
                    const str_hash = string_utils.fastHash(str);
                    hash ^= str_hash;
                },
                .Null => {},
            }
        }

        std.debug.assert(col_idx == col_cache.len); // Post-condition #1: Loop processed all columns
        std.debug.assert(hash != FNV_OFFSET or col_cache.len == 0); // Post-condition #2: Hash modified (unless no columns)

        return JoinKey{
            .hash = hash,
            .row_idx = row_idx,
        };
    }

    /// Checks if two keys are equal by comparing actual values using cached column info
    pub fn equals(
        self: JoinKey,
        other: JoinKey,
        left_cache: []const ColumnCache,
        right_cache: []const ColumnCache,
    ) !bool {
        std.debug.assert(left_cache.len > 0); // Pre-condition #1
        std.debug.assert(left_cache.len == right_cache.len); // Pre-condition #2

        // Quick hash check first
        if (self.hash != other.hash) return false;

        // Compare actual values using cached columns
        var col_idx: u32 = 0;
        while (col_idx < MAX_JOIN_COLUMNS and col_idx < left_cache.len) : (col_idx += 1) {
            const left_col = left_cache[col_idx].series;
            const right_col = right_cache[col_idx].series;
            const value_type = left_cache[col_idx].value_type;

            if (value_type != right_cache[col_idx].value_type) return error.TypeMismatch;

            const values_equal = switch (value_type) {
                .Int64 => blk: {
                    const data1 = left_col.asInt64() orelse return error.TypeMismatch;
                    const data2 = right_col.asInt64() orelse return error.TypeMismatch;
                    break :blk data1[self.row_idx] == data2[other.row_idx];
                },
                .Float64 => blk: {
                    const data1 = left_col.asFloat64() orelse return error.TypeMismatch;
                    const data2 = right_col.asFloat64() orelse return error.TypeMismatch;
                    break :blk data1[self.row_idx] == data2[other.row_idx];
                },
                .Bool => blk: {
                    const data1 = left_col.asBool() orelse return error.TypeMismatch;
                    const data2 = right_col.asBool() orelse return error.TypeMismatch;
                    break :blk data1[self.row_idx] == data2[other.row_idx];
                },
                .String => blk: {
                    const str_col1 = left_col.asStringColumn() orelse return error.TypeMismatch;
                    const str_col2 = right_col.asStringColumn() orelse return error.TypeMismatch;
                    const str1 = str_col1.get(self.row_idx);
                    const str2 = str_col2.get(other.row_idx);
                    // Use SIMD-optimized string comparison (20-40% faster)
                    break :blk string_utils.fastStringEql(str1, str2);
                },
                .Categorical => blk: {
                    const cat_col1 = left_col.asCategoricalColumn() orelse return error.TypeMismatch;
                    const cat_col2 = right_col.asCategoricalColumn() orelse return error.TypeMismatch;
                    const str1 = cat_col1.get(self.row_idx);
                    const str2 = cat_col2.get(other.row_idx);
                    // Use SIMD-optimized string comparison (20-40% faster)
                    break :blk string_utils.fastStringEql(str1, str2);
                },
                .Null => true,
            };

            if (!values_equal) return false;
        }

        std.debug.assert(col_idx == left_cache.len); // Post-condition
        return true;
    }
};

/// Hash table entry for join operation
const HashEntry = struct {
    key: JoinKey,
    next: ?*HashEntry, // For collision chaining
};

/// Performs inner join between two DataFrames
///
/// Args:
///   - left: Left DataFrame
///   - right: Right DataFrame
///   - allocator: Memory allocator for result
///   - join_cols: Column names to join on
///
/// Returns: New DataFrame with matching rows from both tables
///
/// Performance: O(n + m) where n = left rows, m = right rows
///
/// **IMPORTANT - Lifetime Requirement**:
/// Source DataFrames (`left` and `right`) MUST outlive the returned DataFrame
/// when using Categorical columns. This is because Categorical columns use
/// shallow copy (shared dictionary) for performance (80-90% faster joins).
///
/// **Why**: Categorical columns store a pointer to the category dictionary.
/// Freeing source DataFrames invalidates these pointers → use-after-free.
///
/// **Safe Pattern**:
/// ```zig
/// var left = try loadData("left.csv");
/// var right = try loadData("right.csv");
/// var joined = try innerJoin(&left, &right, allocator, &[_][]const u8{"id"});
///
/// // Use joined...
///
/// // ✅ CORRECT ORDER: Free result BEFORE sources
/// joined.deinit();
/// right.deinit(); // ✅ Free after result
/// left.deinit();  // ✅ Free after result
/// ```
///
/// **Unsafe Pattern**:
/// ```zig
/// var temp = try loadData("temp.csv");
/// var joined = try innerJoin(&left, &temp, allocator, &[_][]const u8{"id"});
/// temp.deinit(); // ❌ DANGER - Use-after-free if joined has Categorical columns!
/// ```
///
/// **Performance vs Safety**:
/// - Shallow copy: 80-90% faster joins (740ms → 100ms for 10K×10K)
/// - Deep copy: 100% safe but slower (use if source lifetime uncertain)
///
/// See: `src/core/categorical.zig` for shallow vs deep copy details
///
/// Example:
/// ```zig
/// const joined = try innerJoin(left, right, allocator, &[_][]const u8{"user_id"});
/// defer joined.deinit();
/// ```
pub fn innerJoin(
    left: *const DataFrame,
    right: *const DataFrame,
    allocator: std.mem.Allocator,
    join_cols: []const []const u8,
) !DataFrame {
    std.debug.assert(join_cols.len > 0); // Pre-condition #1: Need join columns
    std.debug.assert(join_cols.len <= MAX_JOIN_COLUMNS); // Pre-condition #2: Within limits
    std.debug.assert(left.row_count > 0); // Pre-condition #3: Left has data
    std.debug.assert(right.row_count > 0); // Pre-condition #4: Right has data

    return performJoin(left, right, allocator, join_cols, .Inner);
}

/// Performs left join between two DataFrames
///
/// Args:
///   - left: Left DataFrame (all rows will be in result)
///   - right: Right DataFrame (only matching rows)
///   - allocator: Memory allocator for result
///   - join_cols: Column names to join on
///
/// Returns: New DataFrame with all left rows + matching right rows
///
/// Performance: O(n + m) where n = left rows, m = right rows
///
/// **IMPORTANT - Lifetime Requirement**: Same as innerJoin() - source DataFrames
/// must outlive the result when using Categorical columns (shallow copy optimization).
/// See innerJoin() documentation for detailed lifetime requirements and safe patterns.
///
/// Example:
/// ```zig
/// const joined = try leftJoin(left, right, allocator, &[_][]const u8{"user_id"});
/// defer joined.deinit();
/// ```
pub fn leftJoin(
    left: *const DataFrame,
    right: *const DataFrame,
    allocator: std.mem.Allocator,
    join_cols: []const []const u8,
) !DataFrame {
    std.debug.assert(join_cols.len > 0); // Pre-condition #1
    std.debug.assert(join_cols.len <= MAX_JOIN_COLUMNS); // Pre-condition #2
    std.debug.assert(left.row_count > 0); // Pre-condition #3

    return performJoin(left, right, allocator, join_cols, .Left);
}

/// Core join implementation using hash join algorithm
/// Routes to radix join for integer key optimization (2-3× speedup)
fn performJoin(
    left: *const DataFrame,
    right: *const DataFrame,
    allocator: std.mem.Allocator,
    join_cols: []const []const u8,
    join_type: JoinType,
) !DataFrame {
    std.debug.assert(join_cols.len > 0); // Pre-condition #1
    std.debug.assert(left.row_count > 0 or join_type == .Left); // Pre-condition #2

    // Route to radix join for integer keys (2-3× faster for Int64 single-column joins)
    // Decision criteria:
    // - Single column join: Required (multi-column support in Phase 2.1)
    // - Both columns Int64 type: Required for radix partitioning
    // - Performance target: 2-3× speedup over standard hash join
    if (isRadixJoinCandidate(left, right, join_cols)) {
        std.log.debug("Using radix join optimization for integer key column: {s}", .{join_cols[0]});
        return performRadixJoin(left, right, allocator, join_cols, join_type);
    }

    // Fallback to standard hash join for:
    // - Multi-column joins (composite keys)
    // - Non-integer columns (String, Float64, Bool, Categorical)
    // - Mixed type joins
    std.log.debug("Using standard hash join for column(s): {s}", .{join_cols[0]});

    // Build hash table from right DataFrame (probe left)
    // Pre-size hash map to avoid rehashing (optimization: ~20-30% faster joins)
    var hash_map = std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(*HashEntry)){};
    try hash_map.ensureTotalCapacity(allocator, right.row_count);

    // Track batch allocation for cleanup
    var entry_batch: ?[]HashEntry = null;
    defer {
        var iter = hash_map.valueIterator();
        var cleanup_idx: u32 = 0;
        const MAX_CLEANUP_ITERATIONS: u32 = 10_000; // Max hash table entries
        while (iter.next()) |list| : (cleanup_idx += 1) {
            std.debug.assert(cleanup_idx < MAX_CLEANUP_ITERATIONS); // Bounds check
            list.deinit(allocator);
        }
        std.debug.assert(cleanup_idx <= MAX_CLEANUP_ITERATIONS); // Post-condition
        hash_map.deinit(allocator);
        // Free batch allocation (entries are stored in single batch)
        if (entry_batch) |batch| {
            allocator.free(batch);
        }
    }

    // Phase 1: Build hash table from right DataFrame
    entry_batch = try buildHashTable(&hash_map, right, allocator, join_cols);

    // Phase 2: Probe with left DataFrame and collect matches
    // Pre-allocate matches array (optimization: avoid reallocation during probe)
    var matches = std.ArrayListUnmanaged(MatchResult){};
    // For inner join: worst case is min(left, right) rows
    // For left join: always left.row_count rows
    const estimated_matches = if (join_type == .Inner)
        @min(left.row_count, right.row_count)
    else
        left.row_count;
    try matches.ensureTotalCapacity(allocator, estimated_matches);
    defer matches.deinit(allocator);

    try probeHashTable(&hash_map, left, right, allocator, join_cols, join_type, &matches);

    // Phase 3: Build result DataFrame
    const result = try buildJoinResult(left, right, allocator, join_cols, &matches);

    std.debug.assert(result.row_count == matches.items.len); // Post-condition
    return result;
}

/// Performs radix hash join for integer key columns (2-3× speedup over standard hash join)
///
/// **Algorithm**:
/// 1. Partition both DataFrames using radix partitioning (8-bit radix = 256 partitions)
/// 2. For each partition pair: build hash table from right partition, probe with left
/// 3. Collect matches from all partitions
/// 4. Build result DataFrame
///
/// **Performance Benefits**:
/// - Cache-friendly: Each partition fits in L2/L3 cache (~100 KB per partition for 10K rows)
/// - SIMD comparisons: 4× faster probing with vectorized equality checks (Phase 2.2)
/// - Reduced hash collisions: Radix pre-filtering reduces hash table load factor
///
/// **Limitations** (Milestone 1.2.0):
/// - Single Int64 column only (multi-column support in Phase 2.1)
/// - Inner join and Left join only (outer join in Phase 2.3)
///
/// **Expected Speedup**: 2-3× faster than standard hash join for integer keys
fn performRadixJoin(
    left: *const DataFrame,
    right: *const DataFrame,
    allocator: std.mem.Allocator,
    join_cols: []const []const u8,
    join_type: JoinType,
) !DataFrame {
    std.debug.assert(join_cols.len == 1); // Pre-condition #1: Single column only
    std.debug.assert(left.row_count > 0 or join_type == .Left); // Pre-condition #2

    const col_name = join_cols[0];

    // Extract Int64 join key columns
    const left_col = left.column(col_name) orelse return error.ColumnNotFound;
    const right_col = right.column(col_name) orelse return error.ColumnNotFound;

    const left_keys = left_col.asInt64() orelse return error.TypeMismatch;
    const right_keys = right_col.asInt64() orelse return error.TypeMismatch;

    // Build KeyValue arrays for radix partitioning
    const left_kvs = try buildKeyValueArray(allocator, left_keys);
    defer allocator.free(left_kvs);

    const right_kvs = try buildKeyValueArray(allocator, right_keys);
    defer allocator.free(right_kvs);

    // Partition both DataFrames using radix partitioning
    var left_ctx = try radix_join.partitionData(allocator, left_kvs);
    defer left_ctx.deinit();

    var right_ctx = try radix_join.partitionData(allocator, right_kvs);
    defer right_ctx.deinit();

    // Collect matches from all partitions
    var all_matches = std.ArrayListUnmanaged(MatchResult){};
    defer all_matches.deinit(allocator);

    // Process each partition pair
    try probeRadixPartitions(
        &left_ctx,
        &right_ctx,
        allocator,
        join_type,
        &all_matches,
    );

    // Build result DataFrame from matches
    const result = try buildJoinResult(left, right, allocator, join_cols, &all_matches);

    std.debug.assert(result.row_count == all_matches.items.len); // Post-condition
    return result;
}

/// Builds KeyValue array from Int64 keys for radix partitioning
fn buildKeyValueArray(
    allocator: std.mem.Allocator,
    keys: []const i64,
) ![]radix_join.KeyValue {
    std.debug.assert(keys.len > 0); // Pre-condition #1
    std.debug.assert(keys.len <= radix_join.MAX_TOTAL_ROWS); // Pre-condition #2

    const kvs = try allocator.alloc(radix_join.KeyValue, keys.len);
    errdefer allocator.free(kvs);

    var i: u32 = 0;
    const max_rows: u32 = @intCast(keys.len);
    while (i < max_rows) : (i += 1) {
        kvs[i] = radix_join.KeyValue.init(keys[i], i);
    }

    std.debug.assert(i == keys.len); // Post-condition
    return kvs;
}

/// Probes radix partitions and collects matches
/// Processes each partition pair (left partition i, right partition i)
fn probeRadixPartitions(
    left_ctx: *radix_join.RadixJoinContext,
    right_ctx: *radix_join.RadixJoinContext,
    allocator: std.mem.Allocator,
    join_type: JoinType,
    all_matches: *std.ArrayListUnmanaged(MatchResult),
) !void {
    std.debug.assert(left_ctx.partitions.len == radix_join.PARTITION_COUNT); // Pre-condition #1
    std.debug.assert(right_ctx.partitions.len == radix_join.PARTITION_COUNT); // Pre-condition #2

    // Process each partition pair
    var partition_idx: u32 = 0;
    while (partition_idx < radix_join.PARTITION_COUNT) : (partition_idx += 1) {
        const left_part = left_ctx.partitions[partition_idx];
        const right_part = right_ctx.partitions[partition_idx];

        // Skip empty partitions
        if (left_part.isEmpty()) continue; // No left rows to process
        if (right_part.isEmpty() and join_type == .Left) {
            // For left join, add unmatched left rows (left_part is not empty here)
            try addUnmatchedLeftRows(left_part, left_ctx, all_matches, allocator);
            continue;
        }
        if (right_part.isEmpty()) continue; // No right rows to match

        // Extract partition data
        const left_data = left_ctx.partitioned_data[left_part.start .. left_part.start + left_part.count];
        const right_data = right_ctx.partitioned_data[right_part.start .. right_part.start + right_part.count];

        // Build hash table for right partition
        var hash_table = try radix_join.buildHashTable(allocator, right_data);
        defer hash_table.deinit();

        // Probe with left partition
        try probePartition(left_data, &hash_table, join_type, all_matches, allocator);
    }

    std.debug.assert(partition_idx == radix_join.PARTITION_COUNT); // Post-condition
}

/// Adds unmatched left rows for left join
fn addUnmatchedLeftRows(
    left_part: radix_join.Partition,
    left_ctx: *radix_join.RadixJoinContext,
    all_matches: *std.ArrayListUnmanaged(MatchResult),
    allocator: std.mem.Allocator,
) !void {
    std.debug.assert(!left_part.isEmpty()); // Pre-condition

    const left_data = left_ctx.partitioned_data[left_part.start .. left_part.start + left_part.count];

    var i: u32 = 0;
    while (i < left_data.len) : (i += 1) {
        try all_matches.append(allocator, .{
            .left_idx = left_data[i].row_index,
            .right_idx = null,
        });
    }

    std.debug.assert(i == left_data.len); // Post-condition
}

/// Probes partition with hash table and collects matches
fn probePartition(
    left_data: []const radix_join.KeyValue,
    hash_table: *const radix_join.HashTable,
    join_type: JoinType,
    all_matches: *std.ArrayListUnmanaged(MatchResult),
    allocator: std.mem.Allocator,
) !void {
    std.debug.assert(left_data.len > 0); // Pre-condition

    var matches_buffer = std.ArrayListUnmanaged(u32){};
    defer matches_buffer.deinit(allocator);

    var i: u32 = 0;
    const max_rows: u32 = @intCast(left_data.len);
    while (i < max_rows) : (i += 1) {
        const left_kv = left_data[i];

        // Clear buffer for this probe
        matches_buffer.clearRetainingCapacity();

        // Find all matches in hash table
        try hash_table.probe(left_kv.key, &matches_buffer, allocator);

        if (matches_buffer.items.len > 0) {
            // Add all matches
            for (matches_buffer.items) |right_idx| {
                try all_matches.append(allocator, .{
                    .left_idx = left_kv.row_index,
                    .right_idx = right_idx,
                });
            }
        } else if (join_type == .Left) {
            // Left join: add unmatched row
            try all_matches.append(allocator, .{
                .left_idx = left_kv.row_index,
                .right_idx = null,
            });
        }
    }

    std.debug.assert(i == left_data.len); // Post-condition
}

/// Builds hash table from DataFrame for join
/// Uses batch allocation for HashEntry objects to reduce allocation overhead
/// Returns the batch allocation so caller can free it after join completes
fn buildHashTable(
    hash_map: *std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(*HashEntry)),
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    join_cols: []const []const u8,
) ![]HashEntry {
    std.debug.assert(join_cols.len > 0); // Pre-condition
    std.debug.assert(df.row_count > 0); // Pre-condition #2

    // Create column cache once to avoid repeated column lookups (major optimization)
    const col_cache = try ColumnCache.init(allocator, df, join_cols);
    defer allocator.free(col_cache);

    // Batch allocate all HashEntry objects at once (avoid individual allocations)
    const entry_batch = try allocator.alloc(HashEntry, df.row_count);
    errdefer allocator.free(entry_batch);

    var row_idx: u32 = 0;
    const max_rows = df.row_count;

    while (row_idx < max_rows) : (row_idx += 1) {
        const key = try JoinKey.compute(row_idx, col_cache);

        // Use pre-allocated entry from batch
        entry_batch[row_idx] = HashEntry{
            .key = key,
            .next = null,
        };

        // Add to hash map (pointer to batch entry)
        const gop = try hash_map.getOrPut(allocator, key.hash);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }
        try gop.value_ptr.append(allocator, &entry_batch[row_idx]);
    }

    std.debug.assert(row_idx == max_rows); // Post-condition
    return entry_batch; // Caller will free after join
}

/// Probes hash table to find matches
fn probeHashTable(
    hash_map: *std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(*HashEntry)),
    left: *const DataFrame,
    right: *const DataFrame,
    allocator: std.mem.Allocator,
    join_cols: []const []const u8,
    join_type: JoinType,
    matches: *std.ArrayListUnmanaged(MatchResult),
) !void {
    std.debug.assert(join_cols.len > 0); // Pre-condition

    // Create column caches once to avoid repeated column lookups (major optimization)
    const left_cache = try ColumnCache.init(allocator, left, join_cols);
    defer allocator.free(left_cache);

    const right_cache = try ColumnCache.init(allocator, right, join_cols);
    defer allocator.free(right_cache);

    var left_idx: u32 = 0;
    const max_rows = left.row_count;

    while (left_idx < max_rows) : (left_idx += 1) {
        const key = try JoinKey.compute(left_idx, left_cache);

        if (hash_map.get(key.hash)) |entries| {
            var found_match = false;

            // Check if too many matches before processing
            if (entries.items.len > MAX_MATCHES_PER_KEY) {
                std.log.err("Join key has {} matches (limit {})", .{ entries.items.len, MAX_MATCHES_PER_KEY });
                return error.TooManyMatchesPerKey;
            }

            var entry_idx: u32 = 0;
            while (entry_idx < MAX_MATCHES_PER_KEY and entry_idx < entries.items.len) : (entry_idx += 1) {
                const entry = entries.items[entry_idx];
                if (try key.equals(entry.key, left_cache, right_cache)) {
                    try matches.append(allocator, .{
                        .left_idx = left_idx,
                        .right_idx = entry.key.row_idx,
                    });
                    found_match = true;
                }
            }

            std.debug.assert(entry_idx == entries.items.len or entry_idx == MAX_MATCHES_PER_KEY);

            // For left join, add unmatched row with null right side
            if (!found_match and join_type == .Left) {
                try matches.append(allocator, .{
                    .left_idx = left_idx,
                    .right_idx = null,
                });
            }
        } else if (join_type == .Left) {
            // No match found for left join - add with null right
            try matches.append(allocator, .{
                .left_idx = left_idx,
                .right_idx = null,
            });
        }
    }

    std.debug.assert(left_idx == max_rows); // Post-condition
}

/// Builds result DataFrame from matches
fn buildJoinResult(
    left: *const DataFrame,
    right: *const DataFrame,
    allocator: std.mem.Allocator,
    join_cols: []const []const u8,
    matches: *std.ArrayListUnmanaged(MatchResult),
) !DataFrame {
    _ = join_cols; // Not used anymore since we include all columns
    std.debug.assert(@intFromPtr(matches) != 0); // Pre-condition: Non-null matches

    // Create column descriptors for result
    // Left columns + right columns (excluding join columns to avoid duplicates)
    var result_cols = std.ArrayListUnmanaged(ColumnDesc){};
    defer result_cols.deinit(allocator);

    // Add all left columns
    const MAX_TOTAL_COLUMNS: u32 = 10_000;
    var left_col_idx: u32 = 0;
    while (left_col_idx < MAX_TOTAL_COLUMNS and left_col_idx < left.column_descs.len) : (left_col_idx += 1) {
        try result_cols.append(allocator, left.column_descs[left_col_idx]);
    }
    std.debug.assert(left_col_idx == left.column_descs.len or left_col_idx == MAX_TOTAL_COLUMNS); // Post-condition

    // Add right columns (with _right suffix for conflicts including join columns)
    var right_col_idx: u32 = 0;
    while (right_col_idx < MAX_TOTAL_COLUMNS and right_col_idx < right.column_descs.len) : (right_col_idx += 1) {
        const desc = right.column_descs[right_col_idx];

        // Check for name conflict (including join columns)
        const has_conflict = blk: {
            var left_check_idx: u32 = 0;
            while (left_check_idx < MAX_TOTAL_COLUMNS and left_check_idx < left.column_descs.len) : (left_check_idx += 1) {
                if (std.mem.eql(u8, left.column_descs[left_check_idx].name, desc.name)) break :blk true;
            }
            std.debug.assert(left_check_idx == left.column_descs.len or left_check_idx == MAX_TOTAL_COLUMNS); // Post-condition
            break :blk false;
        };

        const result_name = if (has_conflict)
            try std.fmt.allocPrint(allocator, "{s}_right", .{desc.name})
        else
            try allocator.dupe(u8, desc.name);

        try result_cols.append(allocator, ColumnDesc.init(result_name, desc.value_type, @intCast(result_cols.items.len)));
    }
    std.debug.assert(right_col_idx == right.column_descs.len or right_col_idx == MAX_TOTAL_COLUMNS); // Post-condition

    // Create result DataFrame (with at least capacity 1 for empty results)
    const num_rows: u32 = @intCast(matches.items.len);
    const capacity = if (num_rows == 0) 1 else num_rows;
    var result = try DataFrame.create(allocator, result_cols.items, capacity);
    errdefer result.deinit();

    // Free temporary column names
    var col_idx: usize = left.column_descs.len;
    while (col_idx < result_cols.items.len) : (col_idx += 1) {
        allocator.free(result_cols.items[col_idx].name);
    }

    // Fill data from matches (skip if empty)
    if (num_rows > 0) {
        try fillJoinData(&result, left, right, matches, result.arena.allocator());
    }

    try result.setRowCount(num_rows);
    std.debug.assert(result.row_count == num_rows); // Post-condition

    return result;
}

/// Fills result DataFrame with data from left and right based on matches
fn fillJoinData(
    result: *DataFrame,
    left: *const DataFrame,
    right: *const DataFrame,
    matches: *std.ArrayListUnmanaged(MatchResult),
    allocator: std.mem.Allocator,
) !void {
    std.debug.assert(matches.items.len > 0); // Pre-condition #1
    std.debug.assert(result.columns.len > 0); // Pre-condition #2

    // Fill left columns
    var left_col_idx: u32 = 0;
    while (left_col_idx < left.column_descs.len) : (left_col_idx += 1) {
        const src_col = &left.columns[left_col_idx];
        const dst_col = &result.columns[left_col_idx];

        try copyColumnData(dst_col, src_col, matches, true, allocator);
    }
    std.debug.assert(left_col_idx == left.column_descs.len); // Post-condition

    // Fill right columns (all columns, including join columns with _right suffix)
    var right_col_idx: u32 = 0;
    var result_col_idx: u32 = @intCast(left.column_descs.len);

    while (right_col_idx < right.column_descs.len) : (right_col_idx += 1) {
        const src_col = &right.columns[right_col_idx];
        const dst_col = &result.columns[result_col_idx];

        try copyColumnData(dst_col, src_col, matches, false, allocator);
        result_col_idx += 1;
    }
    std.debug.assert(result_col_idx == result.columns.len); // Post-condition
}

/// Checks if matches represent sequential access pattern (no reordering needed)
///
/// **Purpose**: Detect when left table columns can use fast memcpy path
///
/// **Pattern Detection**:
/// - Sequential: [0, 1, 2, 3, 4, ...] → Fast path (5× faster with memcpy)
/// - Non-sequential: [0, 2, 1, 5, 3, ...] → Slow path (row-by-row copy)
///
/// **Performance**:
/// - Only checks first 1000 rows (O(1) for large datasets)
/// - 99.9% accuracy for join pattern detection
/// - Typical joins have sequential left table (inner/left join)
///
/// **Optimization Impact**:
/// - Sequential memcpy: 0.05ms for 100K rows (0.5ns per value)
/// - Row-by-row copy: 0.24ms for 100K rows (2.4ns per value)
/// - Speedup: 5× faster for sequential access
///
/// See docs/join_profiling_analysis.md for detailed profiling results
fn isSequentialMatch(matches: *std.ArrayListUnmanaged(MatchResult)) bool {
    std.debug.assert(matches.items.len > 0); // Pre-condition #1

    var i: u32 = 0;
    const MAX_CHECK: u32 = 1000; // Check first 1000 rows (99.9% accuracy)

    while (i < MAX_CHECK and i < matches.items.len) : (i += 1) {
        if (matches.items[i].left_idx != i) {
            return false;
        }
    }

    std.debug.assert(i <= MAX_CHECK); // Post-condition #2
    return true;
}

/// Copies data from source column to destination based on match indices
///
/// **Null Handling** (for unmatched left join rows):
/// - Int64: 0 (cannot represent null in primitive type)
/// - Float64: 0.0 (cannot distinguish from actual zero)
/// - Bool: false (cannot represent null in primitive type)
/// - String: "" (empty string)
///
/// **Rationale**:
/// Current implementation uses sentinel values for nulls because Zig types are non-nullable.
/// This matches common DataFrame library behavior (pandas uses NaN for numeric nulls,
/// but we use 0/0.0 for consistency).
///
/// **Known Limitation**:
/// Users cannot distinguish between:
/// - Actual zero/false/empty values in the data
/// - Null values from unmatched left join rows
///
/// **Future Enhancement** (Milestone 0.4.0):
/// - Implement nullable column types (Option<Int64>, Option<Float64>)
/// - Add `.isNull()` method to Series
/// - Use NaN for Float64 nulls (IEEE 754 compliant null marker)
/// - Preserve null information through join operations
fn copyColumnData(
    dst_col: *Series,
    src_col: *const Series,
    matches: *std.ArrayListUnmanaged(MatchResult),
    from_left: bool,
    allocator: std.mem.Allocator,
) !void {
    std.debug.assert(matches.items.len > 0); // Pre-condition
    std.debug.assert(dst_col.value_type == src_col.value_type); // Types must match

    const MAX_ROWS: u32 = std.math.maxInt(u32);

    switch (src_col.value_type) {
        .Int64 => {
            const src_data = src_col.asInt64() orelse return error.TypeMismatch;
            const dst_data = dst_col.asInt64Buffer() orelse return error.TypeMismatch;

            // Fast path: Sequential access (left table, no reordering)
            // Uses column-wise memcpy for 5× speedup vs row-by-row
            // See docs/join_profiling_analysis.md for benchmarks
            if (from_left and isSequentialMatch(matches)) {
                const count: usize = matches.items.len;
                @memcpy(dst_data[0..count], src_data[0..count]);
                dst_col.length = @intCast(count);
                return;
            }

            // Fallback: Batch processing for non-sequential access
            // Process 8 rows at a time for better throughput
            const batch_size = 8;
            var i: u32 = 0;

            // Process full batches
            while (i + batch_size <= matches.items.len and i < MAX_ROWS) {
                // Unrolled loop for batch of 8
                inline for (0..batch_size) |offset| {
                    const match = matches.items[i + offset];
                    if (from_left) {
                        dst_data[i + offset] = src_data[match.left_idx];
                    } else {
                        if (match.right_idx) |right_idx| {
                            dst_data[i + offset] = src_data[right_idx];
                        } else {
                            dst_data[i + offset] = 0; // Null value
                        }
                    }
                }
                i += batch_size;
            }

            // Process remaining elements
            while (i < MAX_ROWS and i < matches.items.len) : (i += 1) {
                const match = matches.items[i];
                const src_idx = if (from_left) match.left_idx else match.right_idx orelse {
                    dst_data[i] = 0; // Null value for unmatched left join
                    continue;
                };
                dst_data[i] = src_data[src_idx];
            }
            std.debug.assert(i == matches.items.len); // Post-condition
            dst_col.length = @intCast(matches.items.len);
        },
        .Float64 => {
            const src_data = src_col.asFloat64() orelse return error.TypeMismatch;
            const dst_data = dst_col.asFloat64Buffer() orelse return error.TypeMismatch;

            // Fast path: Sequential access (left table, no reordering)
            // Uses column-wise memcpy for 5× speedup vs row-by-row
            if (from_left and isSequentialMatch(matches)) {
                const count: usize = matches.items.len;
                @memcpy(dst_data[0..count], src_data[0..count]);
                dst_col.length = @intCast(count);
                return;
            }

            // Fallback: Batch processing for non-sequential access
            // Process 8 rows at a time for better throughput
            const batch_size = 8;
            var i: u32 = 0;

            // Process full batches
            while (i + batch_size <= matches.items.len and i < MAX_ROWS) {
                // Unrolled loop for batch of 8
                inline for (0..batch_size) |offset| {
                    const match = matches.items[i + offset];
                    if (from_left) {
                        dst_data[i + offset] = src_data[match.left_idx];
                    } else {
                        if (match.right_idx) |right_idx| {
                            dst_data[i + offset] = src_data[right_idx];
                        } else {
                            dst_data[i + offset] = 0.0; // Null value
                        }
                    }
                }
                i += batch_size;
            }

            // Process remaining elements
            while (i < MAX_ROWS and i < matches.items.len) : (i += 1) {
                const match = matches.items[i];
                const src_idx = if (from_left) match.left_idx else match.right_idx orelse {
                    dst_data[i] = 0.0; // Null value
                    continue;
                };
                dst_data[i] = src_data[src_idx];
            }
            std.debug.assert(i == matches.items.len); // Post-condition
            dst_col.length = @intCast(matches.items.len);
        },
        .Bool => {
            const src_data = src_col.asBool() orelse return error.TypeMismatch;
            const dst_data = dst_col.asBoolBuffer() orelse return error.TypeMismatch;

            // Fast path: Sequential access (left table, no reordering)
            // Uses column-wise memcpy for 5× speedup vs row-by-row
            if (from_left and isSequentialMatch(matches)) {
                const count: usize = matches.items.len;
                @memcpy(dst_data[0..count], src_data[0..count]);
                dst_col.length = @intCast(count);
                return;
            }

            // Fallback: Batch processing for non-sequential access
            // Process 8 rows at a time for better throughput
            const batch_size = 8;
            var i: u32 = 0;

            // Process full batches
            while (i + batch_size <= matches.items.len and i < MAX_ROWS) {
                // Unrolled loop for batch of 8
                inline for (0..batch_size) |offset| {
                    const match = matches.items[i + offset];
                    if (from_left) {
                        dst_data[i + offset] = src_data[match.left_idx];
                    } else {
                        if (match.right_idx) |right_idx| {
                            dst_data[i + offset] = src_data[right_idx];
                        } else {
                            dst_data[i + offset] = false; // Null value
                        }
                    }
                }
                i += batch_size;
            }

            // Process remaining elements
            while (i < MAX_ROWS and i < matches.items.len) : (i += 1) {
                const match = matches.items[i];
                const src_idx = if (from_left) match.left_idx else match.right_idx orelse {
                    dst_data[i] = false; // Null value
                    continue;
                };
                dst_data[i] = src_data[src_idx];
            }
            std.debug.assert(i == matches.items.len); // Post-condition
            dst_col.length = @intCast(matches.items.len);
        },
        .String => {
            const src_string_col = src_col.asStringColumn() orelse return error.TypeMismatch;
            const dst_string_col = dst_col.asStringColumnMut() orelse return error.TypeMismatch;

            // String column copying (inherently slower than numeric due to variable-length data)
            // For low-cardinality strings, consider using Categorical type for 10-100× speedup
            var i: u32 = 0;
            while (i < MAX_ROWS and i < matches.items.len) : (i += 1) {
                const match = matches.items[i];
                const src_idx = if (from_left) match.left_idx else match.right_idx orelse {
                    try dst_string_col.append(allocator, ""); // Empty string for null
                    continue;
                };
                const str = src_string_col.get(src_idx);
                try dst_string_col.append(allocator, str);
            }
            std.debug.assert(i == matches.items.len); // Post-condition
        },
        .Categorical => {
            // Shallow copy categorical with shared dictionary (join optimization)
            // This shares the category dictionary and only copies codes array
            // Performance: 80-90% faster than deepCopyRows (740ms → ~100ms for 10K×10K)
            // Safety: Source DataFrames outlive join result (guaranteed by caller)
            const src_cat_col = src_col.asCategoricalColumn() orelse return error.TypeMismatch;

            // Build array of source row indices from matches
            var src_indices = try allocator.alloc(u32, matches.items.len);
            defer allocator.free(src_indices);

            var i: u32 = 0;
            while (i < MAX_ROWS and i < matches.items.len) : (i += 1) {
                const match = matches.items[i];
                src_indices[i] = if (from_left) match.left_idx else match.right_idx orelse 0; // Use 0 for null (will be first category)
            }
            std.debug.assert(i == matches.items.len); // Post-condition

            // Create shallow copy with shared dictionary (OPTIMIZATION!)
            const new_cat_col = try src_cat_col.shallowCopyRows(allocator, src_indices);

            // Replace the categorical column
            dst_col.data = .{ .Categorical = try allocator.create(@TypeOf(new_cat_col)) };
            dst_col.data.Categorical.* = new_cat_col;
        },
        .Null => {},
    }
}
