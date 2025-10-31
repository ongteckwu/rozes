//! Series - Single-column data structure with typed values
//!
//! A Series represents a single column of homogeneous data.
//! Data is stored in a columnar layout for efficient access.
//!
//! See docs/RFC.md Section 3.2 for Series specification.
//!
//! Example:
//! ```
//! const ages = try Series.init(allocator, "age", .Int64, 1000);
//! defer ages.deinit(allocator);
//!
//! const data = ages.asInt64().?;
//! data[0] = 30;
//! ```

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const ValueType = types.ValueType;
const CategoricalColumn = @import("categorical.zig").CategoricalColumn;

/// Log error only when not in test mode (suppresses error output during tests)
fn logError(comptime fmt: []const u8, args: anytype) void {
    if (!builtin.is_test) {
        std.log.err(fmt, args);
    }
}

/// A single column of typed data
pub const Series = struct {
    /// Column name
    name: []const u8,

    /// Data type of values
    value_type: ValueType,

    /// Actual data storage (typed union)
    data: SeriesData,

    /// Number of elements
    length: u32,

    /// Maximum number of rows (4 billion limit)
    const MAX_ROWS: u32 = std.math.maxInt(u32);

    /// Creates a new Series with allocated storage
    ///
    /// Args:
    ///   - allocator: Memory allocator
    ///   - name: Column name
    ///   - valueType: Type of values to store
    ///   - capacity: Initial capacity (number of rows)
    ///
    /// Returns: Initialized Series
    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        value_type: ValueType,
        capacity: u32,
    ) !Series {
        // Allow empty names - valid edge case in CSV (e.g., ",b,c" header)
        std.debug.assert(@intFromPtr(name.ptr) != 0); // Pointer must be valid
        std.debug.assert(capacity <= MAX_ROWS); // Within limits (0 is valid for empty)

        const data = try SeriesData.allocate(allocator, value_type, capacity);

        return Series{
            .name = name,
            .value_type = value_type,
            .data = data,
            .length = 0, // Start empty
        };
    }

    /// Creates a Series from existing data (takes ownership)
    pub fn fromSlice(
        name: []const u8,
        value_type: ValueType,
        data: SeriesData,
        length: u32,
    ) Series {
        std.debug.assert(name.len > 0); // Name required
        std.debug.assert(length <= MAX_ROWS); // Within limits

        return Series{
            .name = name,
            .value_type = value_type,
            .data = data,
            .length = length,
        };
    }

    /// Frees the Series memory
    pub fn deinit(self: *Series, allocator: std.mem.Allocator) void {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant check

        self.data.free(allocator);
        self.length = 0;
    }

    /// Returns the number of elements
    pub fn len(self: *const Series) u32 {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        return self.length;
    }

    /// Returns true if Series is empty
    pub fn isEmpty(self: *const Series) bool {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant check

        const result = self.length == 0;
        std.debug.assert(result == (self.length == 0)); // Post-condition
        return result;
    }

    /// Returns the value type
    pub fn getValueType(self: *const Series) ValueType {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant check
        std.debug.assert(@intFromEnum(self.value_type) >= 0); // Valid enum value

        return self.value_type;
    }

    /// Access as Int64 array (null if wrong type)
    /// Returns only the filled portion (0..length)
    pub fn asInt64(self: *const Series) ?[]i64 {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        return switch (self.data) {
            .Int64 => |slice| slice[0..self.length],
            else => null,
        };
    }

    /// Access full Int64 buffer including unused capacity
    pub fn asInt64Buffer(self: *Series) ?[]i64 {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        return switch (self.data) {
            .Int64 => |slice| slice,
            else => null,
        };
    }

    /// Access as Float64 array (null if wrong type)
    /// Returns only the filled portion (0..length)
    pub fn asFloat64(self: *const Series) ?[]f64 {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        return switch (self.data) {
            .Float64 => |slice| slice[0..self.length],
            else => null,
        };
    }

    /// Access full Float64 buffer including unused capacity
    pub fn asFloat64Buffer(self: *Series) ?[]f64 {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        return switch (self.data) {
            .Float64 => |slice| slice,
            else => null,
        };
    }

    /// Access as Bool array (null if wrong type)
    /// Returns only the filled portion (0..length)
    pub fn asBool(self: *const Series) ?[]bool {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        return switch (self.data) {
            .Bool => |slice| slice[0..self.length],
            else => null,
        };
    }

    /// Access as Bool buffer (full capacity, mutable)
    /// Returns the full allocated buffer
    pub fn asBoolBuffer(self: *Series) ?[]bool {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        return switch (self.data) {
            .Bool => |slice| slice,
            else => null,
        };
    }

    /// Access as StringColumn (null if wrong type)
    ///
    /// Returns a reference to the underlying StringColumn.
    /// Use this for direct access to string data.
    pub fn asStringColumn(self: *const Series) ?*const StringColumn {
        std.debug.assert(self.length <= MAX_ROWS); // Pre-condition #1: Invariant
        std.debug.assert(@sizeOf(@TypeOf(self.data)) > 0); // Pre-condition #2: Union size check

        return switch (self.data) {
            .String => |*col| col,
            else => null,
        };
    }

    /// Access as mutable StringColumn (null if wrong type)
    ///
    /// Returns a mutable reference to the underlying StringColumn.
    /// Use this when you need to append strings to the column.
    pub fn asStringColumnMut(self: *Series) ?*StringColumn {
        std.debug.assert(self.length <= MAX_ROWS); // Pre-condition #1: Invariant
        std.debug.assert(@sizeOf(@TypeOf(self.data)) > 0); // Pre-condition #2: Union size check

        return switch (self.data) {
            .String => |*col| col,
            else => null,
        };
    }

    /// Access as CategoricalColumn (null if wrong type)
    ///
    /// Returns a reference to the underlying CategoricalColumn.
    /// Use this for direct access to categorical data.
    pub fn asCategoricalColumn(self: *const Series) ?*const CategoricalColumn {
        std.debug.assert(self.length <= MAX_ROWS); // Pre-condition #1: Invariant
        std.debug.assert(@sizeOf(@TypeOf(self.data)) > 0); // Pre-condition #2: Union size check

        return switch (self.data) {
            .Categorical => |cat_ptr| cat_ptr,
            else => null,
        };
    }

    /// Access as mutable CategoricalColumn (null if wrong type)
    ///
    /// Returns a mutable reference to the underlying CategoricalColumn.
    /// Use this when you need to modify the categorical data (e.g., append).
    pub fn asCategoricalColumnMut(self: *Series) ?*CategoricalColumn {
        std.debug.assert(self.length <= MAX_ROWS); // Pre-condition #1: Invariant
        std.debug.assert(@sizeOf(@TypeOf(self.data)) > 0); // Pre-condition #2: Union size check

        return switch (self.data) {
            .Categorical => |cat_ptr| cat_ptr,
            else => null,
        };
    }

    /// Get a single string at index (null if wrong type or out of bounds)
    ///
    /// Convenience method for accessing individual strings.
    /// Returns a zero-copy slice into the string buffer.
    pub fn getString(self: *const Series, idx: u32) ?[]const u8 {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant
        std.debug.assert(idx < MAX_ROWS); // Index in range

        if (idx >= self.length) return null; // Out of bounds

        return switch (self.data) {
            .String => |*col| col.get(idx),
            .Categorical => |cat_ptr| cat_ptr.get(idx),
            else => null,
        };
    }

    /// Gets value at index as generic value
    pub fn get(self: *const Series, idx: u32) !SeriesValue {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        if (idx >= self.length) {
            // Only log errors when not in test mode
            if (!@import("builtin").is_test) {
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                const temp_allocator = arena.allocator();

                const hint = std.fmt.allocPrint(temp_allocator, "Index {} out of bounds for series '{s}' with length {}. Valid range: 0 to {}", .{ idx, self.name, self.length, self.length - 1 }) catch unreachable;

                const err_msg = types.RichError.init(.IndexOutOfBounds, "Series index out of bounds")
                    .withColumn(self.name)
                    .withHint(hint);

                if (err_msg.format(temp_allocator)) |formatted| {
                    logError("{s}", .{formatted});
                } else |_| {
                    logError("Index {} out of bounds for series '{s}' (length {})", .{ idx, self.name, self.length });
                }
            }
            return error.IndexOutOfBounds;
        }

        return switch (self.data) {
            .Int64 => |slice| SeriesValue{ .Int64 = slice[idx] },
            .Float64 => |slice| SeriesValue{ .Float64 = slice[idx] },
            .Bool => |slice| SeriesValue{ .Bool = slice[idx] },
            .String => |*col| SeriesValue{ .String = col.get(idx) },
            .Categorical => |cat_ptr| SeriesValue{ .Categorical = cat_ptr.get(idx) },
            .Null => SeriesValue.Null,
        };
    }

    /// Sets value at index
    ///
    /// Note: String values cannot be modified in place due to variable-length
    /// storage. Use append() to add new strings or create a new Series.
    pub fn set(self: *Series, idx: u32, value: SeriesValue) !void {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        if (idx >= self.length) {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const hint = try std.fmt.allocPrint(temp_allocator, "Index {} out of bounds for series '{s}' with length {}. Valid range: 0 to {}", .{ idx, self.name, self.length, self.length - 1 });

            const err_msg = types.RichError.init(.IndexOutOfBounds, "Series index out of bounds in set()")
                .withColumn(self.name)
                .withHint(hint);

            if (err_msg.format(temp_allocator)) |formatted| {
                logError("{s}", .{formatted});
            } else |_| {
                logError("Index {} out of bounds for series '{s}' (length {})", .{ idx, self.name, self.length });
            }

            return error.IndexOutOfBounds;
        }

        switch (self.data) {
            .Int64 => |slice| {
                if (value != .Int64) {
                    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                    defer arena.deinit();
                    const temp_allocator = arena.allocator();

                    const hint = try std.fmt.allocPrint(temp_allocator, "Series '{s}' has type Int64, but received {s}", .{ self.name, @tagName(value) });

                    const err_msg = types.RichError.init(.TypeMismatch, "Type mismatch in set()")
                        .withColumn(self.name)
                        .withHint(hint);

                    if (err_msg.format(temp_allocator)) |formatted| {
                        logError("{s}", .{formatted});
                    } else |_| {
                        logError("Type mismatch for series '{s}': expected Int64, got {s}", .{ self.name, @tagName(value) });
                    }

                    return error.TypeMismatch;
                }
                slice[idx] = value.Int64;
            },
            .Float64 => |slice| {
                if (value != .Float64) {
                    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                    defer arena.deinit();
                    const temp_allocator = arena.allocator();

                    const hint = try std.fmt.allocPrint(temp_allocator, "Series '{s}' has type Float64, but received {s}", .{ self.name, @tagName(value) });

                    const err_msg = types.RichError.init(.TypeMismatch, "Type mismatch in set()")
                        .withColumn(self.name)
                        .withHint(hint);

                    if (err_msg.format(temp_allocator)) |formatted| {
                        logError("{s}", .{formatted});
                    } else |_| {
                        logError("Type mismatch for series '{s}': expected Float64, got {s}", .{ self.name, @tagName(value) });
                    }

                    return error.TypeMismatch;
                }
                slice[idx] = value.Float64;
            },
            .Bool => |slice| {
                if (value != .Bool) {
                    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                    defer arena.deinit();
                    const temp_allocator = arena.allocator();

                    const hint = try std.fmt.allocPrint(temp_allocator, "Series '{s}' has type Bool, but received {s}", .{ self.name, @tagName(value) });

                    const err_msg = types.RichError.init(.TypeMismatch, "Type mismatch in set()")
                        .withColumn(self.name)
                        .withHint(hint);

                    if (err_msg.format(temp_allocator)) |formatted| {
                        logError("{s}", .{formatted});
                    } else |_| {
                        logError("Type mismatch for series '{s}': expected Bool, got {s}", .{ self.name, @tagName(value) });
                    }

                    return error.TypeMismatch;
                }
                slice[idx] = value.Bool;
            },
            .String => {
                // String modification not supported (variable-length storage)
                // Strings are immutable once added to StringColumn
                return error.OperationNotSupported;
            },
            else => {
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                const temp_allocator = arena.allocator();

                const hint = try std.fmt.allocPrint(temp_allocator, "Series '{s}' has type {s} which doesn't support set()", .{ self.name, @tagName(self.value_type) });

                const err_msg = types.RichError.init(.TypeMismatch, "Type mismatch in set()")
                    .withColumn(self.name)
                    .withHint(hint);

                if (err_msg.format(temp_allocator)) |formatted| {
                    logError("{s}", .{formatted});
                } else |_| {
                    logError("Type mismatch for series '{s}'", .{self.name});
                }

                return error.TypeMismatch;
            },
        }
    }

    /// Appends a value to the series (if capacity allows)
    ///
    /// Note: For string series, an allocator is required for buffer growth.
    /// Use appendString() for string series to provide allocator.
    pub fn append(self: *Series, value: SeriesValue) !void {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        const capacity = switch (self.data) {
            .Int64 => |slice| slice.len,
            .Float64 => |slice| slice.len,
            .Bool => |slice| slice.len,
            .String => |col| col.capacity,
            .Categorical => |cat_ptr| cat_ptr.capacity,
            .Null => 0,
        };

        if (self.length >= capacity) {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const hint = try std.fmt.allocPrint(temp_allocator, "Series '{s}' is at capacity {} with {} elements. Cannot append more elements. Consider pre-allocating larger capacity when creating Series.", .{ self.name, capacity, self.length });

            const err_msg = types.RichError.init(.InvalidOptions, "Series at capacity")
                .withColumn(self.name)
                .withHint(hint);

            if (err_msg.format(temp_allocator)) |formatted| {
                logError("{s}", .{formatted});
            } else |_| {
                logError("Series '{s}' at capacity {} with {} elements", .{ self.name, capacity, self.length });
            }

            return error.OutOfCapacity;
        }

        // Directly write to buffer (bypass bounds check in set)
        switch (self.data) {
            .Int64 => |slice| {
                if (value != .Int64) return error.TypeMismatch;
                slice[self.length] = value.Int64;
            },
            .Float64 => |slice| {
                if (value != .Float64) return error.TypeMismatch;
                slice[self.length] = value.Float64;
            },
            .Bool => |slice| {
                if (value != .Bool) return error.TypeMismatch;
                slice[self.length] = value.Bool;
            },
            .String => {
                // String append requires allocator (for buffer growth)
                // Use appendString() method instead
                return error.OperationNotSupported;
            },
            else => return error.TypeMismatch,
        }

        self.length += 1;
    }

    /// Appends a string value to a string series
    ///
    /// Requires allocator for potential buffer growth.
    /// Only works on String series.
    pub fn appendString(
        self: *Series,
        allocator: std.mem.Allocator,
        str: []const u8,
    ) !void {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant
        std.debug.assert(self.value_type == .String); // Must be string series

        switch (self.data) {
            .String => |*col| {
                var mutable_col = col.*;
                try mutable_col.append(allocator, str);
                self.data.String = mutable_col;
                self.length += 1;

                std.debug.assert(self.length == col.count); // Length matches
            },
            else => return error.TypeMismatch,
        }
    }

    /// Returns unique values from Series
    ///
    /// Args:
    ///   - allocator: Allocator for result array
    ///
    /// Returns: Array of unique values as strings (caller must free each string and the array)
    ///
    /// Performance: O(n) average case with hash map
    ///
    /// Example:
    /// ```zig
    /// const unique_vals = try series.unique(allocator);
    /// defer {
    ///     for (unique_vals) |val| allocator.free(val);
    ///     allocator.free(unique_vals);
    /// }
    /// ```
    pub fn unique(self: *const Series, allocator: std.mem.Allocator) ![]const []const u8 {
        std.debug.assert(self.length <= MAX_ROWS); // Pre-condition #1
        std.debug.assert(@intFromPtr(self) != 0); // Pre-condition #2

        if (self.length == 0) {
            return &[_][]const u8{};
        }

        var seen = std.StringHashMap(void).init(allocator);
        defer {
            var it = seen.keyIterator();
            while (it.next()) |key| {
                allocator.free(key.*);
            }
            seen.deinit();
        }

        var result = std.ArrayListUnmanaged([]const u8){};
        defer result.deinit(allocator);

        switch (self.value_type) {
            .Int64 => {
                const data = self.asInt64() orelse return error.TypeMismatch;
                var i: u32 = 0;
                while (i < MAX_ROWS and i < self.length) : (i += 1) {
                    const key = try std.fmt.allocPrint(allocator, "{}", .{data[i]});
                    if (!seen.contains(key)) {
                        try seen.put(key, {});
                        try result.append(allocator, try std.fmt.allocPrint(allocator, "{}", .{data[i]}));
                    } else {
                        allocator.free(key);
                    }
                }
                std.debug.assert(i == self.length); // Post-condition
            },
            .Float64 => {
                const data = self.asFloat64() orelse return error.TypeMismatch;
                var i: u32 = 0;
                while (i < MAX_ROWS and i < self.length) : (i += 1) {
                    const key = try std.fmt.allocPrint(allocator, "{d}", .{data[i]});
                    if (!seen.contains(key)) {
                        try seen.put(key, {});
                        try result.append(allocator, try std.fmt.allocPrint(allocator, "{d}", .{data[i]}));
                    } else {
                        allocator.free(key);
                    }
                }
                std.debug.assert(i == self.length); // Post-condition
            },
            .String => {
                const string_col = self.asStringColumn() orelse return error.TypeMismatch;
                var i: u32 = 0;
                while (i < MAX_ROWS and i < self.length) : (i += 1) {
                    const value = string_col.get(i);
                    if (!seen.contains(value)) {
                        const key = try allocator.dupe(u8, value);
                        try seen.put(key, {});
                        try result.append(allocator, try allocator.dupe(u8, value));
                    }
                }
                std.debug.assert(i == self.length); // Post-condition
            },
            .Bool => {
                const data = self.asBool() orelse return error.TypeMismatch;
                var has_true = false;
                var has_false = false;

                var i: u32 = 0;
                while (i < MAX_ROWS and i < self.length) : (i += 1) {
                    if (data[i]) {
                        has_true = true;
                    } else {
                        has_false = true;
                    }
                    if (has_true and has_false) break;
                }
                std.debug.assert(i <= self.length); // Post-condition

                if (has_true) try result.append(allocator, try allocator.dupe(u8, "true"));
                if (has_false) try result.append(allocator, try allocator.dupe(u8, "false"));
            },
            .Categorical => {
                const cat_col = self.asCategoricalColumn() orelse return error.TypeMismatch;
                var i: u32 = 0;
                while (i < MAX_ROWS and i < self.length) : (i += 1) {
                    const value = cat_col.get(i);
                    if (!seen.contains(value)) {
                        const key = try allocator.dupe(u8, value);
                        try seen.put(key, {});
                        try result.append(allocator, try allocator.dupe(u8, value));
                    }
                }
                std.debug.assert(i == self.length); // Post-condition
            },
            .Null => {
                try result.append(allocator, try allocator.dupe(u8, "null"));
            },
        }

        return try result.toOwnedSlice(allocator);
    }

    /// Returns count of unique values in Series
    ///
    /// Args:
    ///   - allocator: Allocator for temporary hash map
    ///
    /// Returns: Number of unique values
    ///
    /// Performance: O(n) average case with hash map
    ///
    /// Example:
    /// ```zig
    /// const count = try series.nunique(allocator);
    /// std.debug.print("Unique values: {}\n", .{count});
    /// ```
    pub fn nunique(self: *const Series, allocator: std.mem.Allocator) !u32 {
        std.debug.assert(self.length <= MAX_ROWS); // Pre-condition #1
        std.debug.assert(@intFromPtr(self) != 0); // Pre-condition #2

        if (self.length == 0) {
            return 0;
        }

        var seen = std.StringHashMap(void).init(allocator);
        defer {
            var it = seen.keyIterator();
            while (it.next()) |key| {
                allocator.free(key.*);
            }
            seen.deinit();
        }

        switch (self.value_type) {
            .Int64 => {
                const data = self.asInt64() orelse return error.TypeMismatch;
                var i: u32 = 0;
                while (i < MAX_ROWS and i < self.length) : (i += 1) {
                    const key = try std.fmt.allocPrint(allocator, "{}", .{data[i]});
                    if (!seen.contains(key)) {
                        try seen.put(key, {});
                    } else {
                        allocator.free(key);
                    }
                }
                std.debug.assert(i == self.length); // Post-condition
            },
            .Float64 => {
                const data = self.asFloat64() orelse return error.TypeMismatch;
                var i: u32 = 0;
                while (i < MAX_ROWS and i < self.length) : (i += 1) {
                    const key = try std.fmt.allocPrint(allocator, "{d}", .{data[i]});
                    if (!seen.contains(key)) {
                        try seen.put(key, {});
                    } else {
                        allocator.free(key);
                    }
                }
                std.debug.assert(i == self.length); // Post-condition
            },
            .String => {
                const string_col = self.asStringColumn() orelse return error.TypeMismatch;
                var i: u32 = 0;
                while (i < MAX_ROWS and i < self.length) : (i += 1) {
                    const value = string_col.get(i);
                    if (!seen.contains(value)) {
                        const key = try allocator.dupe(u8, value);
                        try seen.put(key, {});
                    }
                }
                std.debug.assert(i == self.length); // Post-condition
            },
            .Bool => {
                const data = self.asBool() orelse return error.TypeMismatch;
                var has_true = false;
                var has_false = false;

                var i: u32 = 0;
                while (i < MAX_ROWS and i < self.length) : (i += 1) {
                    if (data[i]) {
                        has_true = true;
                    } else {
                        has_false = true;
                    }
                    if (has_true and has_false) break;
                }
                std.debug.assert(i <= self.length); // Post-condition

                return @as(u32, @intFromBool(has_true)) + @as(u32, @intFromBool(has_false));
            },
            .Categorical => {
                const cat_col = self.asCategoricalColumn() orelse return error.TypeMismatch;
                var i: u32 = 0;
                while (i < MAX_ROWS and i < self.length) : (i += 1) {
                    const value = cat_col.get(i);
                    if (!seen.contains(value)) {
                        const key = try allocator.dupe(u8, value);
                        try seen.put(key, {});
                    }
                }
                std.debug.assert(i == self.length); // Post-condition
            },
            .Null => {
                return 1; // Only "null" is unique
            },
        }

        const count: u32 = @intCast(seen.count());
        std.debug.assert(count <= self.length); // Post-condition #3
        return count;
    }
};

/// String column with offset-based storage for efficient memory layout
///
/// Uses an offset table + contiguous buffer approach for optimal performance:
/// - Excellent cache locality (all strings stored contiguously)
/// - Zero-copy access via buffer slices
/// - Minimal per-string overhead (4 bytes vs 16 bytes for slice)
/// - Efficient serialization
///
/// Memory layout example:
///   Strings: ["Alice", "Bob", "Charlie"]
///   buffer:  [A,l,i,c,e,B,o,b,C,h,a,r,l,i,e]
///   offsets: [5, 8, 15]
///   String 0 = buffer[0..5] = "Alice"
///   String 1 = buffer[5..8] = "Bob"
///   String 2 = buffer[8..15] = "Charlie"
pub const StringColumn = struct {
    /// Offset table: offsets[i] = end position of string i in buffer
    /// String i spans buffer[start..end] where:
    ///   - start = if (i == 0) 0 else offsets[i-1]
    ///   - end = offsets[i]
    offsets: []u32,

    /// Contiguous UTF-8 buffer containing all strings
    buffer: []u8,

    /// Number of strings currently stored
    count: u32,

    /// Maximum number of strings (offsets.len)
    capacity: u32,

    /// Optional hash cache for fast join/groupby operations
    /// hash_cache[i] = pre-computed hash of string i
    ///
    /// **Trade-offs**:
    /// - Memory cost: 8 bytes per string
    /// - Performance gain: 20-30% faster join/groupby (skip rehashing)
    ///
    /// **When to enable**: Datasets with repeated join/groupby operations
    /// or string columns with avg length >16 bytes (hash computation expensive)
    hash_cache: ?[]u64,

    /// Maximum limits
    const MAX_STRINGS: u32 = std.math.maxInt(u32);
    const MAX_BUFFER_SIZE: u32 = 1_000_000_000; // 1GB max

    /// Creates a new StringColumn with specified capacity
    ///
    /// Args:
    ///   - allocator: Memory allocator
    ///   - capacity: Maximum number of strings
    ///   - initial_buffer_size: Initial buffer size in bytes
    ///
    /// Returns: Initialized StringColumn
    pub fn init(
        allocator: std.mem.Allocator,
        capacity: u32,
        initial_buffer_size: u32,
    ) !StringColumn {
        std.debug.assert(capacity <= MAX_STRINGS); // Within limits (0 is valid)
        std.debug.assert(initial_buffer_size <= MAX_BUFFER_SIZE); // Buffer not too large

        const offsets = try allocator.alloc(u32, capacity);
        errdefer allocator.free(offsets);

        const buffer = try allocator.alloc(u8, initial_buffer_size);

        return StringColumn{
            .offsets = offsets,
            .buffer = buffer,
            .count = 0,
            .capacity = capacity,
            .hash_cache = null, // Hash cache disabled by default
        };
    }

    /// Frees the StringColumn memory
    pub fn deinit(self: *StringColumn, allocator: std.mem.Allocator) void {
        std.debug.assert(self.count <= self.capacity); // Invariant
        std.debug.assert(self.buffer.len <= MAX_BUFFER_SIZE); // Invariant

        allocator.free(self.offsets);
        allocator.free(self.buffer);

        // Free hash cache if allocated
        if (self.hash_cache) |cache| {
            allocator.free(cache);
        }

        self.count = 0;
    }

    /// Gets string at index (zero-copy)
    ///
    /// Returns a slice into the internal buffer. This is a zero-copy operation.
    /// The returned slice is valid until the next append() or deinit().
    pub fn get(self: *const StringColumn, idx: u32) []const u8 {
        std.debug.assert(idx < self.count); // Bounds check
        std.debug.assert(self.count <= self.capacity); // Invariant

        const start = if (idx == 0) 0 else self.offsets[idx - 1];
        const end = self.offsets[idx];

        std.debug.assert(start <= end); // Valid range
        std.debug.assert(end <= self.buffer.len); // Within buffer

        return self.buffer[start..end];
    }

    /// Appends a string to the column
    ///
    /// May grow the buffer if needed (2x growth strategy).
    /// Will fail if capacity is reached or string is too large.
    pub fn append(
        self: *StringColumn,
        allocator: std.mem.Allocator,
        str: []const u8,
    ) !void {
        std.debug.assert(self.count < self.capacity); // Space available
        std.debug.assert(str.len <= MAX_BUFFER_SIZE); // String not too large

        // Calculate current buffer position and needed space
        const current_pos = if (self.count == 0) 0 else self.offsets[self.count - 1];
        const str_len: u32 = @intCast(str.len);
        const needed_size = current_pos + str_len;

        // Grow buffer if needed
        if (needed_size > self.buffer.len) {
            const current_size: u32 = @intCast(self.buffer.len);
            // Growth strategy: max(2x current, needed_size), capped at MAX_BUFFER_SIZE
            const doubled = current_size * 2;
            const new_size = @min(@max(doubled, needed_size), MAX_BUFFER_SIZE);

            std.debug.assert(new_size >= current_size); // Growth occurred or at max
            std.debug.assert(new_size >= needed_size or new_size == MAX_BUFFER_SIZE); // Sufficient or at limit

            if (new_size < needed_size) {
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                const temp_allocator = arena.allocator();

                const hint = try std.fmt.allocPrint(temp_allocator, "String buffer reached maximum size {} bytes but needs {} bytes. Consider splitting data across multiple columns or using external storage.", .{ MAX_BUFFER_SIZE, needed_size });

                const err_msg = types.RichError.init(.InvalidOptions, "String buffer too small")
                    .withHint(hint);

                if (err_msg.format(temp_allocator)) |formatted| {
                    logError("{s}", .{formatted});
                } else |_| {
                    logError("String buffer max size {} insufficient for {} bytes", .{ MAX_BUFFER_SIZE, needed_size });
                }

                return error.BufferTooSmall;
            }

            const new_buffer = try allocator.realloc(self.buffer, new_size);
            self.buffer = new_buffer;
        }

        // Copy string data
        const start = current_pos;
        const end = start + str_len;
        @memcpy(self.buffer[start..end], str);

        // Update offset table
        self.offsets[self.count] = end;
        self.count += 1;

        std.debug.assert(self.count <= self.capacity); // Post-condition
    }

    /// Returns total memory usage in bytes
    pub fn memoryUsage(self: *const StringColumn) usize {
        std.debug.assert(self.count <= self.capacity);

        const offset_bytes = self.offsets.len * @sizeOf(u32);
        const buffer_bytes = self.buffer.len;

        const total = offset_bytes + buffer_bytes;
        std.debug.assert(total > 0); // Non-zero usage

        return total;
    }

    /// Returns the number of strings stored
    pub fn len(self: *const StringColumn) u32 {
        std.debug.assert(self.count <= self.capacity);
        return self.count;
    }

    /// Returns true if empty
    pub fn isEmpty(self: *const StringColumn) bool {
        std.debug.assert(self.count <= self.capacity);
        const result = self.count == 0;
        std.debug.assert(result == (self.count == 0)); // Post-condition
        return result;
    }

    /// Enable hash caching for fast join/groupby operations
    ///
    /// Pre-computes hashes for all strings in the column.
    ///
    /// **Performance**:
    /// - Time: O(n) where n = number of strings
    /// - Space: O(n) - 8 bytes per string
    /// - Benefit: 20-30% faster join/groupby (skip rehashing)
    ///
    /// **When to use**:
    /// - Datasets with repeated join/groupby operations
    /// - String columns with avg length >16 bytes (hash computation expensive)
    ///
    /// **Example**:
    /// ```zig
    /// var col = try StringColumn.init(allocator, 1000, 50_000);
    /// // ... populate column
    /// try col.enableHashCache(allocator); // Pre-compute hashes
    /// // Now join/groupby operations will use cached hashes
    /// ```
    pub fn enableHashCache(self: *StringColumn, allocator: std.mem.Allocator) !void {
        std.debug.assert(self.count > 0); // Need data to cache
        std.debug.assert(self.count <= self.capacity); // Invariant

        // Import string_utils for fastHash function
        const string_utils = @import("string_utils.zig");

        // Allocate cache array
        const cache = try allocator.alloc(u64, self.count);
        errdefer allocator.free(cache);

        // Pre-compute hashes for all strings (bounded loop)
        var i: u32 = 0;
        while (i < MAX_STRINGS and i < self.count) : (i += 1) {
            const str = self.get(i);
            cache[i] = string_utils.fastHash(str);
        }

        std.debug.assert(i == self.count); // Post-condition: All hashes computed

        // Free old cache if exists
        if (self.hash_cache) |old_cache| {
            allocator.free(old_cache);
        }

        self.hash_cache = cache;
    }

    /// Get hash for string at index (O(1) if cached, otherwise computes)
    ///
    /// Returns the pre-computed hash if cache is enabled, otherwise computes the hash.
    ///
    /// **Performance**:
    /// - With cache: O(1) array lookup
    /// - Without cache: O(n) where n = string length
    ///
    /// **Example**:
    /// ```zig
    /// const hash = col.getHash(42); // Uses cache if enabled
    /// ```
    pub fn getHash(self: *const StringColumn, idx: u32) u64 {
        std.debug.assert(idx < self.count); // Bounds check
        std.debug.assert(self.count <= self.capacity); // Invariant

        const string_utils = @import("string_utils.zig");

        // Use cached hash if available
        if (self.hash_cache) |cache| {
            const hash = cache[idx];
            std.debug.assert(hash != 0); // Hash should never be zero for valid strings
            return hash;
        }

        // Fallback: compute hash on demand
        const str = self.get(idx);
        return string_utils.fastHash(str);
    }
};

/// Tagged union for Series data storage
pub const SeriesData = union(ValueType) {
    Int64: []i64,
    Float64: []f64,
    String: StringColumn, // ✅ Use StringColumn (0.2.0+)
    Bool: []bool,
    Categorical: *CategoricalColumn, // ✅ Mutable pointer to categorical column (0.4.0+)
    Null: void,

    /// Allocates storage for the given type
    fn allocate(allocator: std.mem.Allocator, valueType: ValueType, capacity: u32) !SeriesData {
        std.debug.assert(capacity <= Series.MAX_ROWS); // Within limits (0 is valid)

        return switch (valueType) {
            .Int64 => SeriesData{
                .Int64 = try allocator.alloc(i64, capacity),
            },
            .Float64 => SeriesData{
                .Float64 = try allocator.alloc(f64, capacity),
            },
            .Bool => SeriesData{
                .Bool = try allocator.alloc(bool, capacity),
            },
            .String => blk: {
                // Estimate initial buffer size: avg 50 chars per string
                // For empty DataFrames (capacity 0), use minimal buffer
                const avg_string_length: u32 = 50;
                const initial_buffer_size = if (capacity == 0) 1 else capacity * avg_string_length;
                const col = try StringColumn.init(allocator, capacity, initial_buffer_size);
                break :blk SeriesData{ .String = col };
            },
            .Categorical => blk: {
                const cat_ptr = try allocator.create(CategoricalColumn);
                cat_ptr.* = try CategoricalColumn.init(allocator, capacity);
                break :blk SeriesData{ .Categorical = cat_ptr };
            },
            .Null => SeriesData.Null,
        };
    }

    /// Frees the allocated storage
    fn free(self: SeriesData, allocator: std.mem.Allocator) void {
        // Pre-condition: Validate data structure based on type
        switch (self) {
            .Int64 => |slice| {
                if (slice.len > 0) {
                    std.debug.assert(slice.len <= Series.MAX_ROWS); // Within limits
                    allocator.free(slice);
                }
            },
            .Float64 => |slice| {
                if (slice.len > 0) {
                    std.debug.assert(slice.len <= Series.MAX_ROWS);
                    allocator.free(slice);
                }
            },
            .Bool => |slice| {
                if (slice.len > 0) {
                    std.debug.assert(slice.len <= Series.MAX_ROWS);
                    allocator.free(slice);
                }
            },
            .String => |*col| {
                // Free StringColumn (offsets + buffer)
                var mutable_col = col.*;
                mutable_col.deinit(allocator);
            },
            .Categorical => |cat_ptr| {
                var mutable_cat = @constCast(cat_ptr);
                mutable_cat.deinit(allocator);
                allocator.destroy(mutable_cat);
            },
            .Null => {},
        }
    }
};

/// Generic value type for Series elements
pub const SeriesValue = union(ValueType) {
    Int64: i64,
    Float64: f64,
    String: []const u8,
    Bool: bool,
    Categorical: []const u8,
    Null: void,
};

// Tests
test "Series.init creates empty series" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 100);
    defer series.deinit(allocator);

    try testing.expectEqualStrings("test", series.name);
    try testing.expectEqual(ValueType.Int64, series.value_type);
    try testing.expectEqual(@as(u32, 0), series.len());
    try testing.expect(series.isEmpty());
}

test "Series.asInt64 returns correct slice" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "numbers", .Int64, 10);
    defer series.deinit(allocator);

    // Use buffer to set data, then update length
    const buffer = series.asInt64Buffer().?;
    buffer[0] = 42;
    series.length = 1;

    // Now asInt64() should return 1 element
    const data = series.asInt64().?;
    try testing.expectEqual(@as(i64, 42), data[0]);
    try testing.expectEqual(@as(u32, 1), series.len());
}

test "Series.asFloat64 returns null for Int64 series" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "numbers", .Int64, 10);
    defer series.deinit(allocator);

    try testing.expect(series.asFloat64() == null);
}

test "Series.get returns correct value" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Float64, 10);
    defer series.deinit(allocator);

    const buffer = series.asFloat64Buffer().?;
    buffer[0] = 3.14;
    buffer[1] = 2.71;
    series.length = 2;

    const val0 = try series.get(0);
    const val1 = try series.get(1);

    try testing.expectEqual(@as(f64, 3.14), val0.Float64);
    try testing.expectEqual(@as(f64, 2.71), val1.Float64);
}

test "Series.get returns error for out of bounds" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    series.length = 5;

    try testing.expectError(error.IndexOutOfBounds, series.get(10));
    try testing.expectError(error.IndexOutOfBounds, series.get(5));
}

test "Series.set updates value correctly" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    series.length = 3;

    try series.set(0, SeriesValue{ .Int64 = 100 });
    try series.set(1, SeriesValue{ .Int64 = 200 });

    const buffer = series.asInt64Buffer().?;
    try testing.expectEqual(@as(i64, 100), buffer[0]);
    try testing.expectEqual(@as(i64, 200), buffer[1]);
}

test "Series.set returns error for type mismatch" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    series.length = 1;

    try testing.expectError(error.TypeMismatch, series.set(0, SeriesValue{ .Float64 = 3.14 }));
}

test "Series.append adds values correctly" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 10);
    defer series.deinit(allocator);

    try series.append(SeriesValue{ .Int64 = 10 });
    try series.append(SeriesValue{ .Int64 = 20 });
    try series.append(SeriesValue{ .Int64 = 30 });

    try testing.expectEqual(@as(u32, 3), series.len());

    const buffer = series.asInt64Buffer().?;
    try testing.expectEqual(@as(i64, 10), buffer[0]);
    try testing.expectEqual(@as(i64, 20), buffer[1]);
    try testing.expectEqual(@as(i64, 30), buffer[2]);
}

// ============================================================================
// StringColumn Tests
// ============================================================================

test "StringColumn.init creates empty column" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var col = try StringColumn.init(allocator, 10, 100);
    defer col.deinit(allocator);

    try testing.expectEqual(@as(u32, 0), col.count);
    try testing.expectEqual(@as(u32, 10), col.capacity);
    try testing.expect(col.isEmpty());
}

test "StringColumn.append and get basic strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var col = try StringColumn.init(allocator, 3, 100);
    defer col.deinit(allocator);

    try col.append(allocator, "Alice");
    try col.append(allocator, "Bob");
    try col.append(allocator, "Charlie");

    try testing.expectEqual(@as(u32, 3), col.count);
    try testing.expectEqual(@as(u32, 3), col.len());

    try testing.expectEqualStrings("Alice", col.get(0));
    try testing.expectEqualStrings("Bob", col.get(1));
    try testing.expectEqualStrings("Charlie", col.get(2));
}

test "StringColumn.append with buffer growth" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Start with small buffer (10 bytes)
    var col = try StringColumn.init(allocator, 10, 10);
    defer col.deinit(allocator);

    // Append string larger than initial buffer
    try col.append(allocator, "This is a very long string that exceeds initial buffer");

    try testing.expectEqual(@as(u32, 1), col.count);
    try testing.expectEqualStrings("This is a very long string that exceeds initial buffer", col.get(0));

    // Buffer should have grown
    try testing.expect(col.buffer.len > 10);
}

test "StringColumn.append with multiple growth cycles" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var col = try StringColumn.init(allocator, 100, 20); // Small initial buffer
    defer col.deinit(allocator);

    // Append many strings to trigger multiple buffer growths
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try col.append(allocator, "test string number");
    }

    try testing.expectEqual(@as(u32, 10), col.count);

    // Verify all strings are correct
    i = 0;
    while (i < 10) : (i += 1) {
        try testing.expectEqualStrings("test string number", col.get(i));
    }
}

test "StringColumn.append with empty strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var col = try StringColumn.init(allocator, 5, 100);
    defer col.deinit(allocator);

    try col.append(allocator, "");
    try col.append(allocator, "data");
    try col.append(allocator, "");
    try col.append(allocator, "more");
    try col.append(allocator, "");

    try testing.expectEqual(@as(u32, 5), col.count);

    try testing.expectEqualStrings("", col.get(0));
    try testing.expectEqualStrings("data", col.get(1));
    try testing.expectEqualStrings("", col.get(2));
    try testing.expectEqualStrings("more", col.get(3));
    try testing.expectEqualStrings("", col.get(4));
}

test "StringColumn.append with UTF-8 strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var col = try StringColumn.init(allocator, 5, 200);
    defer col.deinit(allocator);

    try col.append(allocator, "Hello 世界");
    try col.append(allocator, "Emoji: 🌹");
    try col.append(allocator, "Zig ❤️ UTF-8");
    try col.append(allocator, "Café");
    try col.append(allocator, "Привет");

    try testing.expectEqual(@as(u32, 5), col.count);

    try testing.expectEqualStrings("Hello 世界", col.get(0));
    try testing.expectEqualStrings("Emoji: 🌹", col.get(1));
    try testing.expectEqualStrings("Zig ❤️ UTF-8", col.get(2));
    try testing.expectEqualStrings("Café", col.get(3));
    try testing.expectEqualStrings("Привет", col.get(4));
}

test "StringColumn.memoryUsage calculates correctly" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var col = try StringColumn.init(allocator, 10, 100);
    defer col.deinit(allocator);

    const initial_usage = col.memoryUsage();

    // Expected: 10 offsets * 4 bytes + 100 bytes buffer = 140 bytes
    try testing.expectEqual(@as(usize, 140), initial_usage);

    try col.append(allocator, "test");

    // Memory usage should be the same (no buffer growth)
    const after_append = col.memoryUsage();
    try testing.expectEqual(initial_usage, after_append);
}

test "StringColumn.no memory leaks with 1000 cycles" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cycle: u32 = 0;
    while (cycle < 1000) : (cycle += 1) {
        var col = try StringColumn.init(allocator, 10, 100);
        defer col.deinit(allocator);

        var i: u32 = 0;
        while (i < 10) : (i += 1) {
            try col.append(allocator, "test string");
        }

        // Access strings to ensure full initialization
        i = 0;
        while (i < 10) : (i += 1) {
            _ = col.get(i);
        }
    }

    // testing.allocator reports leaks automatically
}

test "StringColumn.offset calculation for multiple strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var col = try StringColumn.init(allocator, 5, 100);
    defer col.deinit(allocator);

    try col.append(allocator, "A"); // offsets[0] = 1
    try col.append(allocator, "BB"); // offsets[1] = 3
    try col.append(allocator, "CCC"); // offsets[2] = 6
    try col.append(allocator, "DDDD"); // offsets[3] = 10
    try col.append(allocator, "EEEEE"); // offsets[4] = 15

    try testing.expectEqual(@as(u32, 1), col.offsets[0]);
    try testing.expectEqual(@as(u32, 3), col.offsets[1]);
    try testing.expectEqual(@as(u32, 6), col.offsets[2]);
    try testing.expectEqual(@as(u32, 10), col.offsets[3]);
    try testing.expectEqual(@as(u32, 15), col.offsets[4]);

    // Verify string retrieval
    try testing.expectEqualStrings("A", col.get(0));
    try testing.expectEqualStrings("BB", col.get(1));
    try testing.expectEqualStrings("CCC", col.get(2));
    try testing.expectEqualStrings("DDDD", col.get(3));
    try testing.expectEqualStrings("EEEEE", col.get(4));
}

// ============================================================================
// Series String Accessor Tests
// ============================================================================

test "Series.asStringColumn returns column for string series" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "names", .String, 10);
    defer series.deinit(allocator);

    const col = series.asStringColumn();
    try testing.expect(col != null);
    try testing.expectEqual(@as(u32, 10), col.?.capacity);
}

test "Series.asStringColumn returns null for non-string series" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "numbers", .Int64, 10);
    defer series.deinit(allocator);

    const col = series.asStringColumn();
    try testing.expect(col == null);
}

test "Series.getString retrieves string at index" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "names", .String, 10);
    defer series.deinit(allocator);

    try series.appendString(allocator, "Alice");
    try series.appendString(allocator, "Bob");
    try series.appendString(allocator, "Charlie");

    try testing.expectEqual(@as(u32, 3), series.len());

    const str0 = series.getString(0);
    try testing.expect(str0 != null);
    try testing.expectEqualStrings("Alice", str0.?);

    const str1 = series.getString(1);
    try testing.expect(str1 != null);
    try testing.expectEqualStrings("Bob", str1.?);

    const str2 = series.getString(2);
    try testing.expect(str2 != null);
    try testing.expectEqualStrings("Charlie", str2.?);
}

test "Series.getString returns null for out of bounds" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "names", .String, 10);
    defer series.deinit(allocator);

    try series.appendString(allocator, "Alice");

    const str0 = series.getString(0);
    try testing.expect(str0 != null);

    const str1 = series.getString(1); // Out of bounds
    try testing.expect(str1 == null);
}

test "Series.getString returns null for non-string series" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "numbers", .Int64, 10);
    defer series.deinit(allocator);

    try series.append(SeriesValue{ .Int64 = 42 });

    const str = series.getString(0);
    try testing.expect(str == null);
}

test "Series.appendString adds strings correctly" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "names", .String, 10);
    defer series.deinit(allocator);

    try series.appendString(allocator, "First");
    try series.appendString(allocator, "Second");
    try series.appendString(allocator, "Third");

    try testing.expectEqual(@as(u32, 3), series.len());

    try testing.expectEqualStrings("First", series.getString(0).?);
    try testing.expectEqualStrings("Second", series.getString(1).?);
    try testing.expectEqualStrings("Third", series.getString(2).?);
}

test "Series.get returns string value" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "names", .String, 10);
    defer series.deinit(allocator);

    try series.appendString(allocator, "Test String");

    const value = try series.get(0);
    try testing.expect(value == .String);
    try testing.expectEqualStrings("Test String", value.String);
}

test "Series.set returns error for string series" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "names", .String, 10);
    defer series.deinit(allocator);

    try series.appendString(allocator, "Original");

    // Attempting to set a string value should fail (immutable)
    try testing.expectError(
        error.OperationNotSupported,
        series.set(0, SeriesValue{ .String = "Modified" }),
    );

    // Original value should remain unchanged
    try testing.expectEqualStrings("Original", series.getString(0).?);
}

// Integration Tests for String Workflows

test "Integration: Create string series and access via multiple methods" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "cities", .String, 5);
    defer series.deinit(allocator);

    // Append strings
    try series.appendString(allocator, "New York");
    try series.appendString(allocator, "Los Angeles");
    try series.appendString(allocator, "Chicago");

    // Access via getString
    try testing.expectEqualStrings("New York", series.getString(0).?);
    try testing.expectEqualStrings("Los Angeles", series.getString(1).?);
    try testing.expectEqualStrings("Chicago", series.getString(2).?);

    // Access via asStringColumn
    const str_col = series.asStringColumn().?;
    try testing.expectEqual(@as(u32, 3), str_col.count);
    try testing.expectEqualStrings("New York", str_col.get(0));
    try testing.expectEqualStrings("Los Angeles", str_col.get(1));
    try testing.expectEqualStrings("Chicago", str_col.get(2));

    // Access via get() method
    const val0 = try series.get(0);
    try testing.expectEqualStrings("New York", val0.String);

    // Verify length
    try testing.expectEqual(@as(u32, 3), series.len());
}

test "Integration: String series with empty strings and UTF-8" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "messages", .String, 10);
    defer series.deinit(allocator);

    // Mix of regular, empty, and UTF-8 strings
    try series.appendString(allocator, "Hello");
    try series.appendString(allocator, "");
    try series.appendString(allocator, "世界");
    try series.appendString(allocator, "🌹");
    try series.appendString(allocator, "");

    // Verify all strings
    try testing.expectEqualStrings("Hello", series.getString(0).?);
    try testing.expectEqualStrings("", series.getString(1).?);
    try testing.expectEqualStrings("世界", series.getString(2).?);
    try testing.expectEqualStrings("🌹", series.getString(3).?);
    try testing.expectEqualStrings("", series.getString(4).?);

    // Verify empty string handling
    const empty_str = series.getString(1).?;
    try testing.expectEqual(@as(usize, 0), empty_str.len);
}

test "Integration: Large string series with buffer growth" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Start with small capacity to force buffer growth
    var series = try Series.init(allocator, "data", .String, 100);
    defer series.deinit(allocator);

    // Append 100 strings
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        var buf: [50]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "String_{d:0>3}", .{i});
        try series.appendString(allocator, str);
    }

    // Verify all strings were stored correctly
    try testing.expectEqual(@as(u32, 100), series.len());

    // Spot check a few
    try testing.expectEqualStrings("String_000", series.getString(0).?);
    try testing.expectEqualStrings("String_050", series.getString(50).?);
    try testing.expectEqualStrings("String_099", series.getString(99).?);
}

test "Series.append returns error for string series" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "names", .String, 10);
    defer series.deinit(allocator);

    // Regular append should fail for strings (need allocator)
    try testing.expectError(
        error.OperationNotSupported,
        series.append(SeriesValue{ .String = "test" }),
    );
}
