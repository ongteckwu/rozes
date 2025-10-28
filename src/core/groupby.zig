//! GroupBy - Group DataFrame rows by column values and perform aggregations
//!
//! This module implements SQL-style GROUP BY operations for DataFrames.
//! It allows segmented analysis (e.g., sales by region, revenue by product).
//!
//! See docs/TODO.md Phase 3 for GroupBy specification.
//!
//! Example:
//! ```zig
//! // Group by city and aggregate
//! const result = try df.groupBy(allocator, "city").agg(allocator, .{
//!     .age_mean = .{ .column = "age", .func = .Mean },
//!     .score_sum = .{ .column = "score", .func = .Sum },
//!     .count = .{ .column = "city", .func = .Count },
//! });
//! defer result.deinit();
//! ```

const std = @import("std");
const types = @import("types.zig");
const DataFrame = @import("dataframe.zig").DataFrame;
const Series = @import("series.zig").Series;
const ColumnDesc = types.ColumnDesc;
const ValueType = types.ValueType;

/// Maximum number of unique groups (reasonable limit)
const MAX_GROUPS: u32 = 100_000;

/// Maximum key buffer size (for String keys)
const MAX_KEY_BUFFER_SIZE: u32 = 10_000_000; // 10MB

/// Aggregation function types
pub const AggFunc = enum {
    Sum,
    Mean,
    Count,
    Min,
    Max,
};

/// Aggregation specification for a column
pub const AggSpec = struct {
    column: []const u8,
    func: AggFunc,
};

/// Group key - represents a single unique value in the grouping column
const GroupKey = union(ValueType) {
    Int64: i64,
    Float64: f64,
    String: []const u8,
    Bool: bool,
    Null: void,

    /// Hash function for group keys
    pub fn hash(self: GroupKey) u64 {
        return switch (self) {
            .Int64 => |val| @as(u64, @bitCast(val)),
            .Float64 => |val| @as(u64, @bitCast(val)),
            .Bool => |val| if (val) @as(u64, 1) else @as(u64, 0),
            .String => |str| std.hash.Wyhash.hash(0, str),
            .Null => 0,
        };
    }

    /// Equality check for group keys
    pub fn eql(self: GroupKey, other: GroupKey) bool {
        if (@intFromEnum(self) != @intFromEnum(other)) return false;

        return switch (self) {
            .Int64 => |val| val == other.Int64,
            .Float64 => |val| val == other.Float64,
            .Bool => |val| val == other.Bool,
            .String => |str| std.mem.eql(u8, str, other.String),
            .Null => true,
        };
    }
};

/// Group information - tracks row indices for a specific group
const Group = struct {
    key: GroupKey,
    row_indices: std.ArrayListUnmanaged(u32),

    pub fn init(key: GroupKey) Group {
        return Group{
            .key = key,
            .row_indices = .{},
        };
    }

    pub fn deinit(self: *Group, allocator: std.mem.Allocator) void {
        self.row_indices.deinit(allocator);
    }
};

/// GroupBy - Intermediate structure for grouped DataFrame operations
pub const GroupBy = struct {
    allocator: std.mem.Allocator,
    source_df: *const DataFrame,
    group_column: []const u8,
    groups: std.ArrayListUnmanaged(Group),
    group_map: std.AutoHashMapUnmanaged(u64, u32), // hash -> group index

    /// Maximum number of iterations for hash collision resolution
    const MAX_HASH_COLLISIONS: u32 = 100;

    /// Creates a GroupBy from a DataFrame
    ///
    /// Args:
    ///   - allocator: Memory allocator for group storage
    ///   - source_df: DataFrame to group
    ///   - group_column: Name of column to group by
    ///
    /// Returns: Initialized GroupBy ready for aggregation
    pub fn init(
        allocator: std.mem.Allocator,
        source_df: *const DataFrame,
        group_column: []const u8,
    ) !GroupBy {
        std.debug.assert(group_column.len > 0); // Pre-condition #1: Column name required
        std.debug.assert(source_df.row_count > 0); // Pre-condition #2: DataFrame not empty

        var gb = GroupBy{
            .allocator = allocator,
            .source_df = source_df,
            .group_column = group_column,
            .groups = .{},
            .group_map = .{},
        };

        // Build groups
        try gb.buildGroups();

        std.debug.assert(gb.groups.items.len > 0); // Post-condition #1: At least one group
        std.debug.assert(gb.groups.items.len <= MAX_GROUPS); // Post-condition #2: Within limits

        return gb;
    }

    /// Frees GroupBy memory
    pub fn deinit(self: *GroupBy) void {
        std.debug.assert(self.groups.items.len <= MAX_GROUPS); // Invariant

        for (self.groups.items) |*group| {
            group.deinit(self.allocator);
        }
        self.groups.deinit(self.allocator);
        self.group_map.deinit(self.allocator);
    }

    /// Builds group structure by scanning DataFrame rows
    fn buildGroups(self: *GroupBy) !void {
        std.debug.assert(self.source_df.row_count > 0); // Pre-condition #1
        std.debug.assert(self.groups.items.len == 0); // Pre-condition #2: Start empty

        // Get grouping column
        const col = self.source_df.column(self.group_column) orelse return error.ColumnNotFound;

        // Iterate through rows and assign to groups
        var row_idx: u32 = 0;
        const max_rows = self.source_df.row_count;

        while (row_idx < max_rows) : (row_idx += 1) {
            // Extract group key from column value
            const key = try self.extractKey(col, row_idx);
            const key_hash = key.hash();

            // Find or create group
            const group_idx = try self.findOrCreateGroup(key, key_hash);

            // Add row to group
            try self.groups.items[group_idx].row_indices.append(self.allocator, row_idx);

            if (self.groups.items.len >= MAX_GROUPS) {
                return error.TooManyGroups;
            }
        }

        std.debug.assert(row_idx == self.source_df.row_count); // Post-condition #1
        std.debug.assert(self.groups.items.len > 0); // Post-condition #2
    }

    /// Extracts group key from column at given row index
    fn extractKey(_: *GroupBy, col: *const Series, row_idx: u32) !GroupKey {
        std.debug.assert(row_idx < col.length); // Pre-condition #1: Valid index
        std.debug.assert(@intFromPtr(col) != 0); // Pre-condition #2: Non-null column

        return switch (col.value_type) {
            .Int64 => blk: {
                const data = col.asInt64() orelse return error.TypeMismatch;
                break :blk GroupKey{ .Int64 = data[row_idx] };
            },
            .Float64 => blk: {
                const data = col.asFloat64() orelse return error.TypeMismatch;
                break :blk GroupKey{ .Float64 = data[row_idx] };
            },
            .Bool => blk: {
                const data = col.asBool() orelse return error.TypeMismatch;
                break :blk GroupKey{ .Bool = data[row_idx] };
            },
            .String => blk: {
                const string_col = col.asStringColumn() orelse return error.TypeMismatch;
                const str = string_col.get(row_idx);
                break :blk GroupKey{ .String = str };
            },
            .Null => GroupKey{ .Null = {} },
        };
    }

    /// Finds existing group or creates new one
    fn findOrCreateGroup(self: *GroupBy, key: GroupKey, key_hash: u64) !u32 {
        std.debug.assert(self.groups.items.len <= MAX_GROUPS); // Pre-condition #1

        // Check if group already exists
        if (self.group_map.get(key_hash)) |existing_idx| {
            // Verify key match (handle hash collisions)
            if (self.groups.items[existing_idx].key.eql(key)) {
                std.debug.assert(existing_idx < self.groups.items.len); // Post-condition
                return existing_idx;
            }

            // Hash collision - linear probe
            var probe_count: u32 = 0;
            while (probe_count < MAX_HASH_COLLISIONS) : (probe_count += 1) {
                const probe_hash = key_hash +% probe_count;
                if (self.group_map.get(probe_hash)) |probe_idx| {
                    if (self.groups.items[probe_idx].key.eql(key)) {
                        return probe_idx;
                    }
                } else {
                    // Found empty slot
                    break;
                }
            }
            std.debug.assert(probe_count < MAX_HASH_COLLISIONS); // Collision limit check
        }

        // Create new group
        const group_idx: u32 = @intCast(self.groups.items.len);
        const new_group = Group.init(key);
        try self.groups.append(self.allocator, new_group);
        try self.group_map.put(self.allocator, key_hash, group_idx);

        std.debug.assert(group_idx < self.groups.items.len); // Post-condition
        return group_idx;
    }

    /// Performs aggregation on grouped data
    ///
    /// Args:
    ///   - allocator: Allocator for result DataFrame
    ///   - specs: Array of aggregation specifications
    ///
    /// Returns: New DataFrame with aggregated results
    pub fn agg(
        self: *GroupBy,
        allocator: std.mem.Allocator,
        specs: []const AggSpec,
    ) !DataFrame {
        std.debug.assert(specs.len > 0); // Pre-condition #1: Need at least one aggregation
        std.debug.assert(self.groups.items.len > 0); // Pre-condition #2: Have groups

        const num_groups = self.groups.items.len;
        const num_agg_cols = specs.len;

        // Create column descriptors: [group_column, agg1, agg2, ...]
        var col_descs = try allocator.alloc(ColumnDesc, num_agg_cols + 1);
        defer allocator.free(col_descs);

        // Group column (preserve type from source)
        const group_col = self.source_df.column(self.group_column) orelse return error.ColumnNotFound;
        col_descs[0] = ColumnDesc.init(self.group_column, group_col.value_type, 0);

        // Aggregation columns (results are always numeric)
        // Note: Column names are temporary - DataFrame.create() will duplicate them in its arena
        for (specs, 0..) |spec, i| {
            const result_name = try std.fmt.allocPrint(
                allocator,
                "{s}_{s}",
                .{ spec.column, @tagName(spec.func) },
            );
            // Store temporary name - will be freed after DataFrame.create()
            col_descs[i + 1] = ColumnDesc.init(result_name, .Float64, @intCast(i + 1));
        }

        // Create result DataFrame (it will duplicate column names in its arena)
        var result = try DataFrame.create(allocator, col_descs, @intCast(num_groups));
        errdefer result.deinit();

        // Free temporary column names immediately (DataFrame has made its own copies)
        // Do this before any operations that might fail
        for (specs, 0..) |_, i| {
            allocator.free(col_descs[i + 1].name);
        }

        // Fill group keys
        try self.fillGroupKeys(&result, group_col);

        // Fill aggregated values
        for (specs, 0..) |spec, agg_idx| {
            try self.fillAggregation(&result, spec, @intCast(agg_idx + 1));
        }

        try result.setRowCount(@intCast(num_groups));

        std.debug.assert(result.row_count == num_groups); // Post-condition
        return result;
    }

    /// Fills group key column in result DataFrame
    fn fillGroupKeys(self: *GroupBy, result: *DataFrame, source_col: *const Series) !void {
        std.debug.assert(result.columns.len > 0); // Pre-condition #1
        std.debug.assert(@intFromPtr(source_col) != 0); // Pre-condition #2: Non-null column

        var group_idx: u32 = 0;
        while (group_idx < MAX_GROUPS and group_idx < self.groups.items.len) : (group_idx += 1) {
            const group = &self.groups.items[group_idx];
            const key = group.key;

            // Write key to result column
            switch (source_col.value_type) {
                .Int64 => {
                    const buffer = result.columns[0].asInt64Buffer() orelse return error.TypeMismatch;
                    buffer[group_idx] = key.Int64;
                },
                .Float64 => {
                    const buffer = result.columns[0].asFloat64Buffer() orelse return error.TypeMismatch;
                    buffer[group_idx] = key.Float64;
                },
                .Bool => {
                    const buffer = result.columns[0].asBoolBuffer() orelse return error.TypeMismatch;
                    buffer[group_idx] = key.Bool;
                },
                .String => {
                    // String handling requires special care
                    const string_col = result.columns[0].asStringColumnMut() orelse return error.TypeMismatch;
                    try string_col.append(result.arena.allocator(), key.String);
                },
                .Null => {},
            }
        }

        std.debug.assert(group_idx == self.groups.items.len); // Post-condition
    }

    /// Fills aggregation column in result DataFrame
    fn fillAggregation(self: *GroupBy, result: *DataFrame, spec: AggSpec, col_idx: u32) !void {
        std.debug.assert(col_idx < result.columns.len); // Pre-condition #1
        std.debug.assert(self.groups.items.len > 0); // Pre-condition #2

        // Get source column to aggregate
        const source_col = self.source_df.column(spec.column) orelse return error.ColumnNotFound;

        // Get result buffer
        const result_buffer = result.columns[col_idx].asFloat64Buffer() orelse return error.TypeMismatch;

        // Compute aggregation for each group
        var group_idx: u32 = 0;
        while (group_idx < MAX_GROUPS and group_idx < self.groups.items.len) : (group_idx += 1) {
            const group = &self.groups.items[group_idx];
            const value = try self.computeAggregation(source_col, group, spec.func);
            result_buffer[group_idx] = value;
        }

        std.debug.assert(group_idx == self.groups.items.len); // Post-condition
    }

    /// Computes aggregation value for a single group
    fn computeAggregation(
        self: *GroupBy,
        col: *const Series,
        group: *const Group,
        func: AggFunc,
    ) !f64 {
        std.debug.assert(group.row_indices.items.len > 0); // Pre-condition #1
        std.debug.assert(col.length > 0); // Pre-condition #2

        return switch (func) {
            .Count => @as(f64, @floatFromInt(group.row_indices.items.len)),
            .Sum => try self.computeSum(col, group),
            .Mean => try self.computeMean(col, group),
            .Min => try self.computeMin(col, group),
            .Max => try self.computeMax(col, group),
        };
    }

    /// Computes sum for a group
    fn computeSum(self: *GroupBy, col: *const Series, group: *const Group) !f64 {
        std.debug.assert(group.row_indices.items.len > 0); // Pre-condition

        _ = self;

        var sum: f64 = 0.0;

        switch (col.value_type) {
            .Int64 => {
                const data = col.asInt64() orelse return error.TypeMismatch;
                for (group.row_indices.items) |row_idx| {
                    sum += @as(f64, @floatFromInt(data[row_idx]));
                }
            },
            .Float64 => {
                const data = col.asFloat64() orelse return error.TypeMismatch;
                for (group.row_indices.items) |row_idx| {
                    sum += data[row_idx];
                }
            },
            else => return error.TypeMismatch,
        }

        return sum;
    }

    /// Computes mean for a group
    fn computeMean(self: *GroupBy, col: *const Series, group: *const Group) !f64 {
        std.debug.assert(group.row_indices.items.len > 0); // Pre-condition

        const sum_val = try self.computeSum(col, group);
        const count: f64 = @floatFromInt(group.row_indices.items.len);

        std.debug.assert(count > 0.0); // Post-condition
        return sum_val / count;
    }

    /// Computes minimum for a group
    fn computeMin(self: *GroupBy, col: *const Series, group: *const Group) !f64 {
        std.debug.assert(group.row_indices.items.len > 0); // Pre-condition

        _ = self;

        var min_val: f64 = std.math.floatMax(f64);

        switch (col.value_type) {
            .Int64 => {
                const data = col.asInt64() orelse return error.TypeMismatch;
                for (group.row_indices.items) |row_idx| {
                    const val = @as(f64, @floatFromInt(data[row_idx]));
                    min_val = @min(min_val, val);
                }
            },
            .Float64 => {
                const data = col.asFloat64() orelse return error.TypeMismatch;
                for (group.row_indices.items) |row_idx| {
                    min_val = @min(min_val, data[row_idx]);
                }
            },
            else => return error.TypeMismatch,
        }

        std.debug.assert(min_val != std.math.floatMax(f64)); // Post-condition
        return min_val;
    }

    /// Computes maximum for a group
    fn computeMax(self: *GroupBy, col: *const Series, group: *const Group) !f64 {
        std.debug.assert(group.row_indices.items.len > 0); // Pre-condition

        _ = self;

        var max_val: f64 = -std.math.floatMax(f64);

        switch (col.value_type) {
            .Int64 => {
                const data = col.asInt64() orelse return error.TypeMismatch;
                for (group.row_indices.items) |row_idx| {
                    const val = @as(f64, @floatFromInt(data[row_idx]));
                    max_val = @max(max_val, val);
                }
            },
            .Float64 => {
                const data = col.asFloat64() orelse return error.TypeMismatch;
                for (group.row_indices.items) |row_idx| {
                    max_val = @max(max_val, data[row_idx]);
                }
            },
            else => return error.TypeMismatch,
        }

        std.debug.assert(max_val != -std.math.floatMax(f64)); // Post-condition
        return max_val;
    }
};
