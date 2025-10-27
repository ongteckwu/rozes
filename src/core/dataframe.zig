//! DataFrame - Columnar data structure with multiple typed columns
//!
//! A DataFrame is a table of data organized in columns (Series).
//! Each column has a uniform type, but different columns can have different types.
//!
//! Memory is managed using an Arena allocator for the DataFrame lifecycle.
//! When the DataFrame is freed, all associated memory is released at once.
//!
//! See RFC.md Section 3.3 for DataFrame specification.
//!
//! Example:
//! ```
//! const df = try DataFrame.create(allocator, &cols, 1000);
//! defer df.deinit();
//!
//! const age_col = df.column("age").?;
//! const ages = age_col.asInt64().?;
//! ```

const std = @import("std");
const types = @import("types.zig");
const series_mod = @import("series.zig");

const ValueType = types.ValueType;
const ColumnDesc = types.ColumnDesc;
const Series = series_mod.Series;

/// Multi-column table with typed data
pub const DataFrame = struct {
    /// Arena allocator for DataFrame lifetime
    arena: std.heap.ArenaAllocator,

    /// Column metadata
    column_descs: []ColumnDesc,

    /// Column data (array of Series)
    columns: []Series,

    /// Number of rows
    row_count: u32,

    /// Maximum number of rows (4 billion limit)
    const MAX_ROWS: u32 = std.math.maxInt(u32);

    /// Maximum number of columns (reasonable limit)
    const MAX_COLS: u32 = 10_000;

    /// Creates a new DataFrame with specified columns
    ///
    /// Args:
    ///   - allocator: Parent allocator (will create arena from this)
    ///   - columnDescs: Column metadata descriptors
    ///   - capacity: Initial row capacity
    ///
    /// Returns: Initialized DataFrame with empty columns
    pub fn create(
        allocator: std.mem.Allocator,
        columnDescs: []const ColumnDesc,
        capacity: u32,
    ) !DataFrame {
        std.debug.assert(columnDescs.len > 0); // Need at least one column
        std.debug.assert(columnDescs.len <= MAX_COLS); // Reasonable limit
        std.debug.assert(capacity > 0); // Need some capacity
        std.debug.assert(capacity <= MAX_ROWS); // Within row limit

        // Create arena for DataFrame lifetime
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        const arena_allocator = arena.allocator();

        // Copy column descriptors
        const descs = try arena_allocator.alloc(ColumnDesc, columnDescs.len);
        for (columnDescs, 0..) |desc, i| {
            // Duplicate column name in arena
            const name = try arena_allocator.dupe(u8, desc.name);
            descs[i] = ColumnDesc.init(name, desc.valueType, @intCast(i));
        }

        // Allocate columns
        const cols = try arena_allocator.alloc(Series, columnDescs.len);
        for (columnDescs, 0..) |desc, i| {
            const name = try arena_allocator.dupe(u8, desc.name);
            cols[i] = try Series.init(arena_allocator, name, desc.valueType, capacity);
        }

        return DataFrame{
            .arena = arena,
            .columnDescs = descs,
            .columns = cols,
            .rowCount = 0,
        };
    }

    /// Frees all DataFrame memory (via arena)
    pub fn deinit(self: *DataFrame) void {
        std.debug.assert(self.rowCount <= MAX_ROWS); // Invariant check
        std.debug.assert(self.columns.len <= MAX_COLS); // Invariant check

        // Arena deinit frees everything at once
        self.arena.deinit();

        // Clear pointers (safety)
        self.columnDescs = &[_]ColumnDesc{};
        self.columns = &[_]Series{};
        self.rowCount = 0;
    }

    /// Returns the number of rows
    pub fn len(self: *const DataFrame) u32 {
        std.debug.assert(self.rowCount <= MAX_ROWS); // Invariant

        return self.rowCount;
    }

    /// Returns the number of columns
    pub fn columnCount(self: *const DataFrame) usize {
        std.debug.assert(self.columns.len <= MAX_COLS); // Invariant

        return self.columns.len;
    }

    /// Returns true if DataFrame is empty (no rows)
    pub fn isEmpty(self: *const DataFrame) bool {
        std.debug.assert(self.rowCount <= MAX_ROWS); // Invariant check

        const result = self.rowCount == 0;
        std.debug.assert(result == (self.rowCount == 0)); // Post-condition
        return result;
    }

    /// Gets column by name (returns null if not found)
    pub fn column(self: *const DataFrame, name: []const u8) ?*const Series {
        std.debug.assert(name.len > 0); // Name required
        std.debug.assert(self.columns.len <= MAX_COLS); // Invariant

        const idx = self.columnIndex(name) orelse return null;
        return &self.columns[idx];
    }

    /// Gets mutable column by name (returns null if not found)
    pub fn columnMut(self: *DataFrame, name: []const u8) ?*Series {
        std.debug.assert(name.len > 0); // Name required
        std.debug.assert(self.columns.len <= MAX_COLS); // Invariant

        const idx = self.columnIndex(name) orelse return null;
        return &self.columns[idx];
    }

    /// Finds column index by name
    pub fn columnIndex(self: *const DataFrame, name: []const u8) ?usize {
        std.debug.assert(name.len > 0); // Name required
        std.debug.assert(self.columnDescs.len <= MAX_COLS); // Invariant

        var i: u32 = 0;
        while (i < MAX_COLS and i < self.columnDescs.len) : (i += 1) {
            if (std.mem.eql(u8, self.columnDescs[i].name, name)) {
                return i;
            }
        }

        std.debug.assert(i <= MAX_COLS); // Post-condition
        return null;
    }

    /// Gets column by index
    pub fn columnAt(self: *const DataFrame, idx: usize) !*const Series {
        std.debug.assert(self.columns.len <= MAX_COLS); // Invariant

        if (idx >= self.columns.len) return error.IndexOutOfBounds;
        return &self.columns[idx];
    }

    /// Checks if column exists
    pub fn hasColumn(self: *const DataFrame, name: []const u8) bool {
        std.debug.assert(name.len > 0); // Name required
        std.debug.assert(self.columns.len <= MAX_COLS); // Invariant

        const result = self.columnIndex(name) != null;
        return result;
    }

    /// Returns column names as slice
    pub fn columnNames(self: *const DataFrame, allocator: std.mem.Allocator) ![]const []const u8 {
        std.debug.assert(self.columns.len > 0); // Must have columns
        std.debug.assert(self.columns.len <= MAX_COLS); // Within limits

        var names = try allocator.alloc([]const u8, self.columns.len);

        var i: u32 = 0;
        while (i < MAX_COLS and i < self.columnDescs.len) : (i += 1) {
            names[i] = self.columnDescs[i].name;
        }

        std.debug.assert(i == self.columnDescs.len); // Processed all columns
        std.debug.assert(names.len == self.columns.len); // Post-condition
        return names;
    }

    /// Sets the row count (updates all columns)
    pub fn setRowCount(self: *DataFrame, count: u32) !void {
        std.debug.assert(count <= MAX_ROWS); // Within limit

        if (count > MAX_ROWS) return error.TooManyRows;

        // Validate all columns have sufficient capacity
        for (self.columns) |*col| {
            const capacity = switch (col.data) {
                .Int64 => |slice| slice.len,
                .Float64 => |slice| slice.len,
                .Bool => |slice| slice.len,
                .String => |slice| slice.len,
                .Null => 0,
            };

            if (count > capacity) return error.InsufficientCapacity;

            col.length = count;
        }

        self.rowCount = count;
    }

    /// Creates a row reference for accessing row data
    pub fn row(self: *const DataFrame, idx: u32) !RowRef {
        std.debug.assert(self.rowCount <= MAX_ROWS); // Invariant

        if (idx >= self.rowCount) return error.IndexOutOfBounds;

        return RowRef{
            .dataframe = self,
            .rowIndex = idx,
        };
    }

    /// Prints DataFrame info (for debugging)
    pub fn print(self: *const DataFrame, writer: anytype) !void {
        try writer.print("DataFrame({} rows × {} cols)\n", .{ self.rowCount, self.columns.len });
        try writer.print("Columns:\n", .{});

        for (self.columnDescs) |desc| {
            try writer.print("  - {s}: {s}\n", .{ desc.name, @tagName(desc.valueType) });
        }
    }
};

/// Reference to a single row in a DataFrame
pub const RowRef = struct {
    dataframe: *const DataFrame,
    rowIndex: u32,

    /// Gets value from column as Int64
    pub fn getInt64(self: RowRef, colName: []const u8) ?i64 {
        std.debug.assert(colName.len > 0); // Name required
        std.debug.assert(self.rowIndex < self.dataframe.rowCount); // Valid row index

        const col = self.dataframe.column(colName) orelse return null;
        const data = col.asInt64() orelse return null;

        if (self.rowIndex >= data.len) return null;
        return data[self.rowIndex];
    }

    /// Gets value from column as Float64
    pub fn getFloat64(self: RowRef, colName: []const u8) ?f64 {
        std.debug.assert(colName.len > 0); // Name required
        std.debug.assert(self.rowIndex < self.dataframe.rowCount); // Valid row index

        const col = self.dataframe.column(colName) orelse return null;
        const data = col.asFloat64() orelse return null;

        if (self.rowIndex >= data.len) return null;
        return data[self.rowIndex];
    }

    /// Gets value from column as Bool
    pub fn getBool(self: RowRef, colName: []const u8) ?bool {
        std.debug.assert(colName.len > 0); // Name required
        std.debug.assert(self.rowIndex < self.dataframe.rowCount); // Valid row index

        const col = self.dataframe.column(colName) orelse return null;
        const data = col.asBool() orelse return null;

        if (self.rowIndex >= data.len) return null;
        return data[self.rowIndex];
    }
};

// Tests
test "DataFrame.create initializes empty DataFrame" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("name", .String, 0),
        ColumnDesc.init("age", .Int64, 1),
        ColumnDesc.init("score", .Float64, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    try testing.expectEqual(@as(u32, 0), df.len());
    try testing.expectEqual(@as(usize, 3), df.columnCount());
    try testing.expect(df.isEmpty());
}

test "DataFrame.column finds column by name" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
        ColumnDesc.init("score", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    const age_col = df.column("age").?;
    try testing.expectEqualStrings("age", age_col.name);
    try testing.expectEqual(ValueType.Int64, age_col.valueType);

    const score_col = df.column("score").?;
    try testing.expectEqualStrings("score", score_col.name);
    try testing.expectEqual(ValueType.Float64, score_col.valueType);
}

test "DataFrame.column returns null for non-existent column" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    try testing.expect(df.column("nonexistent") == null);
}

test "DataFrame.columnIndex finds correct index" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("a", .Int64, 0),
        ColumnDesc.init("b", .Int64, 1),
        ColumnDesc.init("c", .Int64, 2),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    try testing.expectEqual(@as(?usize, 0), df.columnIndex("a"));
    try testing.expectEqual(@as(?usize, 1), df.columnIndex("b"));
    try testing.expectEqual(@as(?usize, 2), df.columnIndex("c"));
    try testing.expectEqual(@as(?usize, null), df.columnIndex("d"));
}

test "DataFrame.hasColumn checks existence" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    try testing.expect(df.hasColumn("age"));
    try testing.expect(!df.hasColumn("name"));
}

test "DataFrame.setRowCount updates all columns" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("a", .Int64, 0),
        ColumnDesc.init("b", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    try df.setRowCount(50);

    try testing.expectEqual(@as(u32, 50), df.len());
    try testing.expectEqual(@as(u32, 50), df.columns[0].len());
    try testing.expectEqual(@as(u32, 50), df.columns[1].len());
}

test "DataFrame.row returns valid RowRef" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
        ColumnDesc.init("score", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    try df.setRowCount(10);

    // Set some data
    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64().?;
    ages[0] = 30;
    ages[1] = 25;

    const score_col = df.columnMut("score").?;
    const scores = score_col.asFloat64().?;
    scores[0] = 95.5;
    scores[1] = 87.3;

    // Access via RowRef
    const row0 = try df.row(0);
    try testing.expectEqual(@as(?i64, 30), row0.getInt64("age"));
    try testing.expectEqual(@as(?f64, 95.5), row0.getFloat64("score"));

    const row1 = try df.row(1);
    try testing.expectEqual(@as(?i64, 25), row1.getInt64("age"));
    try testing.expectEqual(@as(?f64, 87.3), row1.getFloat64("score"));
}

test "DataFrame.row returns error for out of bounds" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
    };

    var df = try DataFrame.create(allocator, &cols, 100);
    defer df.deinit();

    try df.setRowCount(5);

    try testing.expectError(error.IndexOutOfBounds, df.row(5));
    try testing.expectError(error.IndexOutOfBounds, df.row(100));
}
