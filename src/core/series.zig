//! Series - Single-column data structure with typed values
//!
//! A Series represents a single column of homogeneous data.
//! Data is stored in a columnar layout for efficient access.
//!
//! See RFC.md Section 3.2 for Series specification.
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
const types = @import("types.zig");
const ValueType = types.ValueType;

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
        std.debug.assert(name.len > 0); // Name required
        std.debug.assert(capacity > 0); // Need some capacity
        std.debug.assert(capacity <= MAX_ROWS); // Within limits

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
    pub fn asBool(self: *const Series) ?[]bool {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        return switch (self.data) {
            .Bool => |slice| slice[0..self.length],
            else => null,
        };
    }

    /// Gets value at index as generic value
    pub fn get(self: *const Series, idx: u32) !SeriesValue {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        if (idx >= self.length) return error.IndexOutOfBounds;

        return switch (self.data) {
            .Int64 => |slice| SeriesValue{ .Int64 = slice[idx] },
            .Float64 => |slice| SeriesValue{ .Float64 = slice[idx] },
            .Bool => |slice| SeriesValue{ .Bool = slice[idx] },
            .String => |_| SeriesValue.Null, // TODO: String support
            .Null => SeriesValue.Null,
        };
    }

    /// Sets value at index
    pub fn set(self: *Series, idx: u32, value: SeriesValue) !void {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        if (idx >= self.length) return error.IndexOutOfBounds;

        switch (self.data) {
            .Int64 => |slice| {
                if (value != .Int64) return error.TypeMismatch;
                slice[idx] = value.Int64;
            },
            .Float64 => |slice| {
                if (value != .Float64) return error.TypeMismatch;
                slice[idx] = value.Float64;
            },
            .Bool => |slice| {
                if (value != .Bool) return error.TypeMismatch;
                slice[idx] = value.Bool;
            },
            else => return error.TypeMismatch,
        }
    }

    /// Appends a value to the series (if capacity allows)
    pub fn append(self: *Series, value: SeriesValue) !void {
        std.debug.assert(self.length <= MAX_ROWS); // Invariant

        const capacity = switch (self.data) {
            .Int64 => |slice| slice.len,
            .Float64 => |slice| slice.len,
            .Bool => |slice| slice.len,
            .String => |slice| slice.len,
            .Null => 0,
        };

        if (self.length >= capacity) return error.OutOfCapacity;

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
            else => return error.TypeMismatch,
        }

        self.length += 1;
    }
};

/// Tagged union for Series data storage
pub const SeriesData = union(ValueType) {
    Int64: []i64,
    Float64: []f64,
    String: [][]const u8, // Array of strings (0.2.0+)
    Bool: []bool,
    Null: void,

    /// Allocates storage for the given type
    fn allocate(allocator: std.mem.Allocator, valueType: ValueType, capacity: u32) !SeriesData {
        std.debug.assert(capacity > 0); // Need capacity
        std.debug.assert(capacity <= Series.MAX_ROWS); // Within limits

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
            .String => SeriesData{
                .String = try allocator.alloc([]const u8, capacity),
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
            .String => |slice| {
                // TODO: Free individual strings
                if (slice.len > 0) {
                    std.debug.assert(slice.len <= Series.MAX_ROWS);
                    allocator.free(slice);
                }
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
    Null: void,
};

// Tests
test "Series.init creates empty series" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var series = try Series.init(allocator, "test", .Int64, 100);
    defer series.deinit(allocator);

    try testing.expectEqualStrings("test", series.name);
    try testing.expectEqual(ValueType.Int64, series.valueType);
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
