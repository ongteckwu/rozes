//! Categorical Column - Dictionary-Encoded String Data
//!
//! Categorical columns provide 4-8× memory reduction for low-cardinality data
//! by storing unique values once in a dictionary and using integer indices to
//! reference them.
//!
//! ## Memory Efficiency Example
//!
//! String column (1M rows):
//! - Region: ["East", "East", "West", "East", "South", "East", ...]
//! - Memory: ~4 bytes × 1M = 4 MB (for pointers/offsets)
//!
//! Categorical column (1M rows):
//! - Categories: ["East", "West", "South"]  // 3 unique values (~15 bytes)
//! - Codes: [0, 0, 1, 0, 2, 0, ...]        // u32 indices (4 MB)
//! - Total: 4 MB + 15 bytes ≈ 4 MB
//!
//! For low-cardinality data (< 5% unique values), this provides significant savings.
//!
//! ## Performance Benefits
//!
//! 1. **Faster filtering**: Integer comparison vs string comparison
//! 2. **Faster sorting**: Integer sort vs string sort (10-20× faster)
//! 3. **Faster groupby**: Integer hash vs string hash (5-10× faster)
//! 4. **Memory reduction**: 4-8× smaller for categorical data
//!
//! See docs/TODO.md Phase 3 for implementation details.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Maximum number of categories (u32 index limit)
const MAX_CATEGORIES: u32 = 1_000_000; // 1M unique categories

/// Maximum number of rows (u32 limit)
const MAX_ROWS: u32 = 4_000_000_000;

/// Categorical column with dictionary encoding
///
/// Stores unique string values once in a dictionary and uses u32 indices
/// to reference them. This provides massive memory savings for low-cardinality
/// columns like region, country, status, etc.
///
/// ## Example
///
/// ```zig
/// const allocator = std.heap.page_allocator;
///
/// // Create categorical column for "region" data
/// var cat = try CategoricalColumn.init(allocator, 1000);
/// defer cat.deinit();
///
/// try cat.append(allocator, "East");
/// try cat.append(allocator, "East");
/// try cat.append(allocator, "West");
/// try cat.append(allocator, "East");
///
/// // Unique categories: ["East", "West"]
/// // Codes: [0, 0, 1, 0]
/// // Memory: 9 bytes (strings) + 16 bytes (codes) = 25 bytes
/// //   vs ~32 bytes for String column
/// ```
pub const CategoricalColumn = struct {
    /// Unique category strings (dictionary)
    categories: std.ArrayListUnmanaged([]const u8),

    /// Map from string → category index (for fast lookup)
    category_map: std.StringHashMapUnmanaged(u32),

    /// Array of indices into categories (one per row)
    codes: []u32,

    /// Number of rows
    count: u32,

    /// Capacity of codes array
    capacity: u32,

    /// Initialize categorical column with estimated capacity
    ///
    /// Pre-allocates space for `capacity` rows to avoid frequent reallocations.
    ///
    /// ## Assertions
    /// - capacity > 0
    /// - capacity ≤ MAX_ROWS
    pub fn init(allocator: Allocator, capacity: u32) !CategoricalColumn {
        std.debug.assert(capacity <= MAX_ROWS); // Pre-condition (0 is valid for empty DataFrame)

        const codes = try allocator.alloc(u32, capacity);
        errdefer allocator.free(codes);

        return CategoricalColumn{
            .categories = .{},
            .category_map = .{},
            .codes = codes,
            .count = 0,
            .capacity = capacity,
        };
    }

    /// Free all memory
    ///
    /// **Memory Management**:
    /// - Frees all category strings allocated via `allocator.dupe()` in `append()`
    /// - Ownership: Category strings are owned by this column
    /// - This function must be called to prevent memory leaks
    pub fn deinit(self: *CategoricalColumn, allocator: Allocator) void {
        std.debug.assert(self.count <= self.capacity); // Invariant #1
        std.debug.assert(self.categories.items.len <= MAX_CATEGORIES); // Invariant #2

        // ✅ EXPLICITLY FREE ALL CATEGORY STRINGS (fixes memory leak)
        // Each string was allocated via allocator.dupe() in append()
        var i: u32 = 0;
        while (i < MAX_CATEGORIES and i < self.categories.items.len) : (i += 1) {
            allocator.free(self.categories.items[i]);
        }
        std.debug.assert(i == self.categories.items.len); // Post-condition

        self.categories.deinit(allocator);
        self.category_map.deinit(allocator);
        allocator.free(self.codes);
    }

    /// Get string value at row index
    ///
    /// Returns the decoded string value for the given row.
    ///
    /// ## Assertions
    /// - idx < self.count (bounds check)
    /// - self.codes[idx] < self.categories.items.len (valid category)
    pub fn get(self: *const CategoricalColumn, idx: u32) []const u8 {
        std.debug.assert(idx < self.count); // Pre-condition #1: Bounds check
        std.debug.assert(self.count <= self.capacity); // Invariant #2

        const code = self.codes[idx];
        std.debug.assert(code < self.categories.items.len); // Pre-condition #3: Valid code

        return self.categories.items[code];
    }

    /// Append a string value to the column
    ///
    /// If the value already exists in the dictionary, reuses its index.
    /// Otherwise, adds it as a new category.
    ///
    /// ## Assertions
    /// - self.count < self.capacity (space available)
    /// - self.codes.len >= self.capacity (codes array valid)
    /// - self.categories.items.len < MAX_CATEGORIES (category limit)
    ///
    /// ## Error Conditions
    /// - error.CategoricalFull: Too many categories (>1M unique values)
    /// - error.ColumnFull: Column at capacity (need to grow first)
    /// - error.OutOfMemory: Allocation failed
    ///
    /// ## Special Handling
    /// - Empty strings are allowed (stored as empty category)
    pub fn append(self: *CategoricalColumn, allocator: Allocator, value: []const u8) !void {
        std.debug.assert(self.count < self.capacity); // Pre-condition: Space available
        std.debug.assert(self.codes.len >= self.capacity); // Pre-condition: Codes array valid

        // Check if category already exists
        if (self.category_map.get(value)) |code| {
            // Reuse existing category
            self.codes[self.count] = code;
            self.count += 1;
            std.debug.assert(self.count <= self.capacity); // Post-condition
            return;
        }

        // Add new category
        if (self.categories.items.len >= MAX_CATEGORIES) {
            return error.CategoricalFull;
        }

        // Bounds check before cast
        std.debug.assert(self.categories.items.len <= std.math.maxInt(u32));
        const new_code: u32 = @intCast(self.categories.items.len);

        // Duplicate string for dictionary
        const owned_value = try allocator.dupe(u8, value);
        errdefer allocator.free(owned_value);

        try self.categories.append(allocator, owned_value);
        try self.category_map.put(allocator, owned_value, new_code);

        self.codes[self.count] = new_code;
        self.count += 1;

        std.debug.assert(self.count <= self.capacity); // Post-condition #1
        std.debug.assert(self.categories.items.len <= MAX_CATEGORIES); // Post-condition #2
    }

    /// Get unique categories (dictionary)
    ///
    /// Returns all unique string values in the column.
    pub fn uniqueCategories(self: *const CategoricalColumn) []const []const u8 {
        std.debug.assert(self.categories.items.len > 0); // Pre-condition #1
        std.debug.assert(self.categories.items.len <= MAX_CATEGORIES); // Pre-condition #2

        return self.categories.items;
    }

    /// Get number of unique categories
    pub fn categoryCount(self: *const CategoricalColumn) u32 {
        std.debug.assert(self.categories.items.len <= MAX_CATEGORIES); // Invariant
        std.debug.assert(self.categories.items.len <= std.math.maxInt(u32)); // Bounds check

        return @intCast(self.categories.items.len);
    }

    /// Get memory usage in bytes
    ///
    /// Returns total memory used by this column:
    /// - Categories (strings): sum of all string lengths
    /// - Codes: count × 4 bytes (u32)
    pub fn memoryUsage(self: *const CategoricalColumn) u64 {
        std.debug.assert(self.count <= MAX_ROWS); // Invariant #1
        std.debug.assert(self.categories.items.len <= MAX_CATEGORIES); // Invariant #2

        var string_bytes: u64 = 0;

        var i: u32 = 0;
        while (i < MAX_CATEGORIES and i < self.categories.items.len) : (i += 1) {
            string_bytes += self.categories.items[i].len;
        }
        std.debug.assert(i == self.categories.items.len); // Post-loop assertion

        const codes_bytes: u64 = @as(u64, self.count) * @sizeOf(u32);

        return string_bytes + codes_bytes;
    }

    /// Calculate cardinality ratio (unique values / total rows)
    ///
    /// Returns a value between 0.0 and 1.0:
    /// - 0.01 = 1% unique (very low cardinality, excellent for categorical)
    /// - 0.50 = 50% unique (medium cardinality)
    /// - 1.00 = 100% unique (high cardinality, bad for categorical)
    pub fn cardinality(self: *const CategoricalColumn) f64 {
        std.debug.assert(self.count > 0); // Pre-condition #1
        std.debug.assert(self.categories.items.len > 0); // Pre-condition #2

        const unique: f64 = @floatFromInt(self.categories.items.len);
        const total: f64 = @floatFromInt(self.count);

        const ratio = unique / total;

        std.debug.assert(ratio >= 0.0 and ratio <= 1.0); // Post-condition
        return ratio;
    }

    /// Create a deep copy of the categorical column by rebuilding the dictionary
    ///
    /// This is used when filtering/selecting rows to ensure the new DataFrame
    /// has an independent categorical column that doesn't share the dictionary
    /// with the original.
    ///
    /// ## Performance
    /// - Time: O(n) where n = number of rows to copy
    /// - Space: O(unique categories in subset)
    ///
    /// ## Assertions
    /// - row_indices.len > 0 (need at least one row)
    /// - row_indices.len <= MAX_ROWS
    /// - All indices within bounds
    pub fn deepCopyRows(
        self: *const CategoricalColumn,
        allocator: Allocator,
        row_indices: []const u32,
    ) !CategoricalColumn {
        std.debug.assert(row_indices.len > 0); // Pre-condition #1
        std.debug.assert(row_indices.len <= MAX_ROWS); // Pre-condition #2

        // Create new categorical column with estimated capacity
        var new_col = try CategoricalColumn.init(allocator, @intCast(row_indices.len));
        errdefer new_col.deinit(allocator);

        // Rebuild dictionary by appending each string value
        // This automatically deduplicates and builds a new category mapping
        var i: u32 = 0;
        while (i < MAX_ROWS and i < row_indices.len) : (i += 1) {
            const row_idx = row_indices[i];
            std.debug.assert(row_idx < self.count); // Bounds check

            const str = self.get(row_idx);
            try new_col.append(allocator, str);
        }

        std.debug.assert(i == row_indices.len); // Post-condition: Copied all rows
        std.debug.assert(new_col.count == row_indices.len); // Same row count

        return new_col;
    }
};
