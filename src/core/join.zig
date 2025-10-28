//! Join - Combine two DataFrames based on common column values
//!
//! This module implements SQL-style join operations for DataFrames.
//! It allows data enrichment by combining rows from two tables.
//!
//! See docs/TODO.md Phase 4 for Join specification.
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

/// Maximum number of join columns (reasonable limit)
const MAX_JOIN_COLUMNS: u32 = 10;

/// Maximum number of matches per key in hash join
const MAX_MATCHES_PER_KEY: u32 = 10_000;

/// Join type enumeration
pub const JoinType = enum {
    Inner, // Only matching rows
    Left, // All left rows + matching right
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

    /// Computes hash for join key based on column values
    pub fn compute(
        df: *const DataFrame,
        row_idx: u32,
        join_cols: []const []const u8,
    ) !JoinKey {
        std.debug.assert(join_cols.len > 0); // Pre-condition #1
        std.debug.assert(join_cols.len <= MAX_JOIN_COLUMNS); // Pre-condition #2
        std.debug.assert(row_idx < df.row_count); // Pre-condition #3

        var hasher = std.hash.Wyhash.init(0);

        var col_idx: u32 = 0;
        while (col_idx < MAX_JOIN_COLUMNS and col_idx < join_cols.len) : (col_idx += 1) {
            const col_name = join_cols[col_idx];
            const col = df.column(col_name) orelse return error.ColumnNotFound;

            // Hash the value from this column
            switch (col.value_type) {
                .Int64 => {
                    const data = col.asInt64() orelse return error.TypeMismatch;
                    const val = data[row_idx];
                    hasher.update(std.mem.asBytes(&val));
                },
                .Float64 => {
                    const data = col.asFloat64() orelse return error.TypeMismatch;
                    const val = data[row_idx];
                    hasher.update(std.mem.asBytes(&val));
                },
                .Bool => {
                    const data = col.asBool() orelse return error.TypeMismatch;
                    const val = data[row_idx];
                    hasher.update(std.mem.asBytes(&val));
                },
                .String => {
                    const string_col = col.asStringColumn() orelse return error.TypeMismatch;
                    const str = string_col.get(row_idx);
                    hasher.update(str);
                },
                .Null => {},
            }
        }

        std.debug.assert(col_idx == join_cols.len); // Post-condition

        return JoinKey{
            .hash = hasher.final(),
            .row_idx = row_idx,
        };
    }

    /// Checks if two keys are equal by comparing actual values
    pub fn equals(
        self: JoinKey,
        other: JoinKey,
        df1: *const DataFrame,
        df2: *const DataFrame,
        join_cols: []const []const u8,
    ) !bool {
        std.debug.assert(join_cols.len > 0); // Pre-condition #1
        std.debug.assert(self.row_idx < df1.row_count); // Pre-condition #2
        std.debug.assert(other.row_idx < df2.row_count); // Pre-condition #3

        // Quick hash check first
        if (self.hash != other.hash) return false;

        // Compare actual values
        var col_idx: u32 = 0;
        while (col_idx < MAX_JOIN_COLUMNS and col_idx < join_cols.len) : (col_idx += 1) {
            const col_name = join_cols[col_idx];

            const col1 = df1.column(col_name) orelse return error.ColumnNotFound;
            const col2 = df2.column(col_name) orelse return error.ColumnNotFound;

            if (col1.value_type != col2.value_type) return error.TypeMismatch;

            const values_equal = switch (col1.value_type) {
                .Int64 => blk: {
                    const data1 = col1.asInt64() orelse return error.TypeMismatch;
                    const data2 = col2.asInt64() orelse return error.TypeMismatch;
                    break :blk data1[self.row_idx] == data2[other.row_idx];
                },
                .Float64 => blk: {
                    const data1 = col1.asFloat64() orelse return error.TypeMismatch;
                    const data2 = col2.asFloat64() orelse return error.TypeMismatch;
                    break :blk data1[self.row_idx] == data2[other.row_idx];
                },
                .Bool => blk: {
                    const data1 = col1.asBool() orelse return error.TypeMismatch;
                    const data2 = col2.asBool() orelse return error.TypeMismatch;
                    break :blk data1[self.row_idx] == data2[other.row_idx];
                },
                .String => blk: {
                    const str_col1 = col1.asStringColumn() orelse return error.TypeMismatch;
                    const str_col2 = col2.asStringColumn() orelse return error.TypeMismatch;
                    const str1 = str_col1.get(self.row_idx);
                    const str2 = str_col2.get(other.row_idx);
                    break :blk std.mem.eql(u8, str1, str2);
                },
                .Null => true,
            };

            if (!values_equal) return false;
        }

        std.debug.assert(col_idx == join_cols.len); // Post-condition
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
fn performJoin(
    left: *const DataFrame,
    right: *const DataFrame,
    allocator: std.mem.Allocator,
    join_cols: []const []const u8,
    join_type: JoinType,
) !DataFrame {
    std.debug.assert(join_cols.len > 0); // Pre-condition #1
    std.debug.assert(left.row_count > 0 or join_type == .Left); // Pre-condition #2

    // Build hash table from right DataFrame (probe left)
    var hash_map = std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(*HashEntry)){};
    defer {
        var iter = hash_map.valueIterator();
        while (iter.next()) |list| {
            for (list.items) |entry| {
                allocator.destroy(entry);
            }
            list.deinit(allocator);
        }
        hash_map.deinit(allocator);
    }

    // Phase 1: Build hash table from right DataFrame
    try buildHashTable(&hash_map, right, allocator, join_cols);

    // Phase 2: Probe with left DataFrame and collect matches
    var matches = std.ArrayListUnmanaged(MatchResult){};
    defer matches.deinit(allocator);

    try probeHashTable(&hash_map, left, right, allocator, join_cols, join_type, &matches);

    // Phase 3: Build result DataFrame
    const result = try buildJoinResult(left, right, allocator, join_cols, &matches);

    std.debug.assert(result.row_count == matches.items.len); // Post-condition
    return result;
}

/// Builds hash table from DataFrame for join
fn buildHashTable(
    hash_map: *std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(*HashEntry)),
    df: *const DataFrame,
    allocator: std.mem.Allocator,
    join_cols: []const []const u8,
) !void {
    std.debug.assert(join_cols.len > 0); // Pre-condition

    var row_idx: u32 = 0;
    const max_rows = df.row_count;

    while (row_idx < max_rows) : (row_idx += 1) {
        const key = try JoinKey.compute(df, row_idx, join_cols);

        // Create entry
        const entry = try allocator.create(HashEntry);
        entry.* = HashEntry{
            .key = key,
            .next = null,
        };

        // Add to hash map
        const gop = try hash_map.getOrPut(allocator, key.hash);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }
        try gop.value_ptr.append(allocator, entry);
    }

    std.debug.assert(row_idx == max_rows); // Post-condition
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

    var left_idx: u32 = 0;
    const max_rows = left.row_count;

    while (left_idx < max_rows) : (left_idx += 1) {
        const key = try JoinKey.compute(left, left_idx, join_cols);

        if (hash_map.get(key.hash)) |entries| {
            var found_match = false;

            for (entries.items) |entry| {
                if (try key.equals(entry.key, left, right, join_cols)) {
                    try matches.append(allocator, .{
                        .left_idx = left_idx,
                        .right_idx = entry.key.row_idx,
                    });
                    found_match = true;
                }
            }

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
    for (left.column_descs) |desc| {
        try result_cols.append(allocator, desc);
    }

    // Add right columns (with _right suffix for conflicts including join columns)
    for (right.column_descs) |desc| {
        // Check for name conflict (including join columns)
        const has_conflict = blk: {
            for (left.column_descs) |left_desc| {
                if (std.mem.eql(u8, left_desc.name, desc.name)) break :blk true;
            }
            break :blk false;
        };

        const result_name = if (has_conflict)
            try std.fmt.allocPrint(allocator, "{s}_right", .{desc.name})
        else
            try allocator.dupe(u8, desc.name);

        try result_cols.append(allocator, ColumnDesc.init(result_name, desc.value_type, @intCast(result_cols.items.len)));
    }

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

/// Copies data from source column to destination based on match indices
fn copyColumnData(
    dst_col: *Series,
    src_col: *const Series,
    matches: *std.ArrayListUnmanaged(MatchResult),
    from_left: bool,
    allocator: std.mem.Allocator,
) !void {
    std.debug.assert(matches.items.len > 0); // Pre-condition
    std.debug.assert(dst_col.value_type == src_col.value_type); // Types must match

    switch (src_col.value_type) {
        .Int64 => {
            const src_data = src_col.asInt64() orelse return error.TypeMismatch;
            const dst_data = dst_col.asInt64Buffer() orelse return error.TypeMismatch;

            for (matches.items, 0..) |match, i| {
                const src_idx = if (from_left) match.left_idx else match.right_idx orelse {
                    dst_data[i] = 0; // Null value for unmatched left join
                    continue;
                };
                dst_data[i] = src_data[src_idx];
            }
            dst_col.length = @intCast(matches.items.len);
        },
        .Float64 => {
            const src_data = src_col.asFloat64() orelse return error.TypeMismatch;
            const dst_data = dst_col.asFloat64Buffer() orelse return error.TypeMismatch;

            for (matches.items, 0..) |match, i| {
                const src_idx = if (from_left) match.left_idx else match.right_idx orelse {
                    dst_data[i] = 0.0; // Null value
                    continue;
                };
                dst_data[i] = src_data[src_idx];
            }
            dst_col.length = @intCast(matches.items.len);
        },
        .Bool => {
            const src_data = src_col.asBool() orelse return error.TypeMismatch;
            const dst_data = dst_col.asBoolBuffer() orelse return error.TypeMismatch;

            for (matches.items, 0..) |match, i| {
                const src_idx = if (from_left) match.left_idx else match.right_idx orelse {
                    dst_data[i] = false; // Null value
                    continue;
                };
                dst_data[i] = src_data[src_idx];
            }
            dst_col.length = @intCast(matches.items.len);
        },
        .String => {
            const src_string_col = src_col.asStringColumn() orelse return error.TypeMismatch;
            const dst_string_col = dst_col.asStringColumnMut() orelse return error.TypeMismatch;

            for (matches.items) |match| {
                const src_idx = if (from_left) match.left_idx else match.right_idx orelse {
                    try dst_string_col.append(allocator, ""); // Empty string for null
                    continue;
                };
                const str = src_string_col.get(src_idx);
                try dst_string_col.append(allocator, str);
            }
        },
        .Null => {},
    }
}
