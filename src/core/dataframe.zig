//! DataFrame - Columnar data structure with multiple typed columns
//!
//! A DataFrame is a table of data organized in columns (Series).
//! Each column has a uniform type, but different columns can have different types.
//!
//! Memory is managed using an Arena allocator for the DataFrame lifecycle.
//! When the DataFrame is freed, all associated memory is released at once.
//!
//! See docs/RFC.md Section 3.3 for DataFrame specification.
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
const builtin = @import("builtin");
const types = @import("types.zig");
const series_mod = @import("series.zig");

const ValueType = types.ValueType;
pub const ColumnDesc = types.ColumnDesc;
const Series = series_mod.Series;

/// Log error only when not in test mode (suppresses error output during tests)
fn logError(comptime fmt: []const u8, args: anytype) void {
    if (!builtin.is_test) {
        std.log.err(fmt, args);
    }
}

/// Result of tolerant CSV parsing with error recovery
pub const ParseResult = struct {
    /// The parsed DataFrame (may be partial if errors occurred)
    dataframe: *DataFrame,

    /// List of parse errors encountered (empty if no errors)
    errors: std.ArrayListUnmanaged(types.ParseError),

    /// Number of rows successfully parsed
    rows_parsed: u32,

    /// Number of rows skipped due to errors
    rows_skipped: u32,

    /// Free all resources
    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        std.debug.assert(self.rows_parsed <= std.math.maxInt(u32)); // Valid count
        std.debug.assert(self.rows_skipped <= std.math.maxInt(u32)); // Valid count

        self.dataframe.deinit();
        allocator.destroy(self.dataframe);
        self.errors.deinit(allocator);
    }
};

/// Multi-column table with typed data
pub const DataFrame = struct {
    /// Arena allocator for DataFrame lifetime
    arena: std.heap.ArenaAllocator,

    /// Column metadata
    column_descs: []ColumnDesc,

    /// Column data (array of Series)
    columns: []Series,

    /// Column name to index mapping for O(1) lookups
    column_index: std.StringHashMapUnmanaged(u32),

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
        std.debug.assert(capacity <= MAX_ROWS); // Within row limit (0 is valid for empty DataFrame)

        // Create arena for DataFrame lifetime
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        const arena_allocator = arena.allocator();

        // Copy column descriptors
        const descs = try arena_allocator.alloc(ColumnDesc, columnDescs.len);
        for (columnDescs, 0..) |desc, i| {
            // Duplicate column name in arena
            const name = try arena_allocator.dupe(u8, desc.name);
            descs[i] = ColumnDesc.init(name, desc.value_type, @intCast(i));
        }

        // Allocate columns
        const cols = try arena_allocator.alloc(Series, columnDescs.len);
        for (columnDescs, 0..) |desc, i| {
            const name = try arena_allocator.dupe(u8, desc.name);
            cols[i] = try Series.init(arena_allocator, name, desc.value_type, capacity);
        }

        // Build column name index for O(1) lookups
        var column_index = std.StringHashMapUnmanaged(u32){};
        for (descs, 0..) |desc, i| {
            try column_index.put(arena_allocator, desc.name, @intCast(i));
        }

        // Note: column_index.count() may be less than descs.len if there are duplicate column names
        // (e.g., from transpose where row values become column names)
        std.debug.assert(column_index.count() <= descs.len); // Index count <= column count
        std.debug.assert(descs.len == columnDescs.len); // Correct column count

        return DataFrame{
            .arena = arena,
            .column_descs = descs,
            .columns = cols,
            .column_index = column_index,
            .row_count = 0,
        };
    }

    /// Frees all DataFrame memory (via arena)
    pub fn deinit(self: *DataFrame) void {
        std.debug.assert(self.row_count <= MAX_ROWS); // Invariant check
        std.debug.assert(self.columns.len <= MAX_COLS); // Invariant check

        // Arena deinit frees everything at once
        self.arena.deinit();

        // Clear pointers (safety)
        self.column_descs = &[_]ColumnDesc{};
        self.columns = &[_]Series{};
        self.row_count = 0;
    }

    /// Gets the allocator for this DataFrame
    ///
    /// This is a convenience method to avoid @constCast hacks throughout the codebase.
    /// The arena allocator is owned by the DataFrame and all allocations from it
    /// are freed when deinit() is called.
    ///
    /// Returns: Allocator for DataFrame operations
    pub fn getAllocator(self: *const DataFrame) std.mem.Allocator {
        std.debug.assert(self.columns.len > 0); // DataFrame should be initialized
        std.debug.assert(self.columns.len <= MAX_COLS); // Invariant check

        return @constCast(&self.arena).allocator();
    }

    /// Returns the number of rows
    pub fn len(self: *const DataFrame) u32 {
        std.debug.assert(self.row_count <= MAX_ROWS); // Invariant

        return self.row_count;
    }

    /// Returns the number of columns
    pub fn columnCount(self: *const DataFrame) usize {
        std.debug.assert(self.columns.len <= MAX_COLS); // Invariant

        return self.columns.len;
    }

    /// Returns true if DataFrame is empty (no rows)
    pub fn isEmpty(self: *const DataFrame) bool {
        std.debug.assert(self.row_count <= MAX_ROWS); // Invariant check

        const result = self.row_count == 0;
        std.debug.assert(result == (self.row_count == 0)); // Post-condition
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

    /// Finds column index by name using O(1) hash map lookup
    pub fn columnIndex(self: *const DataFrame, name: []const u8) ?usize {
        std.debug.assert(name.len > 0); // Name required
        std.debug.assert(self.column_descs.len <= MAX_COLS); // Invariant

        const idx = self.column_index.get(name) orelse return null; // O(1) hash lookup

        std.debug.assert(idx < self.column_descs.len); // Valid index
        return idx;
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
        while (i < MAX_COLS and i < self.column_descs.len) : (i += 1) {
            names[i] = self.column_descs[i].name;
        }

        std.debug.assert(i == self.column_descs.len); // Processed all columns
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
                .String => |string_col| string_col.capacity,
                .Categorical => |cat_ptr| cat_ptr.capacity,
                .Null => 0,
            };

            if (count > capacity) return error.InsufficientCapacity;

            col.length = count;
        }

        self.row_count = count;
    }

    /// Creates a row reference for accessing row data
    pub fn row(self: *const DataFrame, idx: u32) !RowRef {
        std.debug.assert(self.row_count <= MAX_ROWS); // Invariant

        if (idx >= self.row_count) return error.IndexOutOfBounds;

        return RowRef{
            .dataframe = self,
            .rowIndex = idx,
        };
    }

    /// Prints DataFrame info (for debugging)
    pub fn print(self: *const DataFrame, writer: anytype) !void {
        try writer.print("DataFrame({} rows × {} cols)\n", .{ self.row_count, self.columns.len });
        try writer.print("Columns:\n", .{});

        for (self.column_descs) |desc| {
            try writer.print("  - {s}: {s}\n", .{ desc.name, @tagName(desc.value_type) });
        }
    }

    /// Exports DataFrame to CSV format
    ///
    /// Args:
    ///   - allocator: Memory allocator for output buffer
    ///   - opts: CSV formatting options
    ///
    /// Returns: Allocated CSV string (caller must free)
    pub fn toCSV(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        opts: types.CSVOptions,
    ) ![]u8 {
        std.debug.assert(self.columns.len > 0); // Need columns
        std.debug.assert(self.columns.len <= MAX_COLS); // Within limits

        const export_mod = @import("../csv/export.zig");
        return export_mod.toCSV(self, allocator, opts);
    }

    /// Selects a subset of columns
    ///
    /// Returns: New DataFrame with selected columns
    pub fn select(self: *const DataFrame, column_names: []const []const u8) !DataFrame {
        const ops = @import("operations.zig");
        return ops.select(self, column_names);
    }

    /// Drops specified columns
    ///
    /// Returns: New DataFrame without dropped columns
    pub fn drop(self: *const DataFrame, column_names: []const []const u8) !DataFrame {
        const ops = @import("operations.zig");
        return ops.drop(self, column_names);
    }

    /// Filters rows based on a predicate
    ///
    /// Returns: New DataFrame with filtered rows
    pub fn filter(self: *const DataFrame, predicate: anytype) !DataFrame {
        const ops = @import("operations.zig");
        return ops.filter(self, predicate);
    }

    /// Computes sum of a numeric column
    ///
    /// Returns: Sum as f64, or null if empty
    pub fn sum(self: *const DataFrame, column_name: []const u8) !?f64 {
        const ops = @import("operations.zig");
        return ops.sum(self, column_name);
    }

    /// Computes mean of a numeric column
    ///
    /// Returns: Mean as f64, or null if empty
    pub fn mean(self: *const DataFrame, column_name: []const u8) !?f64 {
        const ops = @import("operations.zig");
        return ops.mean(self, column_name);
    }

    /// Sorts DataFrame by a single column
    ///
    /// Args:
    ///   - allocator: Allocator for new DataFrame
    ///   - column_name: Name of column to sort by
    ///   - order: Ascending or Descending
    ///
    /// Returns: New sorted DataFrame (caller owns, must call deinit())
    ///
    /// Performance: O(n log n) where n is number of rows
    ///
    /// Example:
    /// ```zig
    /// var sorted = try df.sort(allocator, "age", .Ascending);
    /// defer sorted.deinit();
    /// ```
    pub fn sort(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        column_name: []const u8,
        order: SortOrder,
    ) !DataFrame {
        const sort_mod = @import("sort.zig");
        return sort_mod.sort(self, allocator, column_name, order);
    }

    /// Sorts DataFrame by multiple columns
    ///
    /// Args:
    ///   - allocator: Allocator for new DataFrame
    ///   - specs: Array of SortSpec (column name + order)
    ///
    /// Returns: New sorted DataFrame (caller owns, must call deinit())
    ///
    /// Performance: O(n log n * k) where n is rows, k is number of sort columns
    ///
    /// Example:
    /// ```zig
    /// const specs = [_]SortSpec{
    ///     .{ .column = "city", .order = .Ascending },
    ///     .{ .column = "age", .order = .Descending },
    /// };
    /// var sorted = try df.sortBy(allocator, &specs);
    /// defer sorted.deinit();
    /// ```
    pub fn sortBy(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        specs: []const SortSpec,
    ) !DataFrame {
        const sort_mod = @import("sort.zig");
        return sort_mod.sortBy(self, allocator, specs);
    }

    /// Groups DataFrame by a column for aggregation
    ///
    /// Args:
    ///   - allocator: Allocator for GroupBy structure
    ///   - column_name: Name of column to group by
    ///
    /// Returns: GroupBy object ready for aggregation (caller must call deinit())
    ///
    /// Performance: O(n) where n is number of rows
    ///
    /// Example:
    /// ```zig
    /// var grouped = try df.groupBy(allocator, "city");
    /// defer grouped.deinit();
    ///
    /// const result = try grouped.agg(allocator, &[_]AggSpec{
    ///     .{ .column = "age", .func = .Mean },
    ///     .{ .column = "score", .func = .Sum },
    /// });
    /// defer result.deinit();
    /// ```
    pub fn groupBy(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        column_name: []const u8,
    ) !GroupBy {
        const groupby_mod = @import("groupby.zig");
        return groupby_mod.GroupBy.init(allocator, self, column_name);
    }

    /// Performs inner join with another DataFrame
    ///
    /// Args:
    ///   - allocator: Allocator for result DataFrame
    ///   - other: Right DataFrame to join with
    ///   - join_cols: Column names to join on
    ///
    /// Returns: New DataFrame with matching rows (caller owns, must call deinit())
    ///
    /// Performance: O(n + m) where n, m are row counts
    ///
    /// Example:
    /// ```zig
    /// const joined = try df1.innerJoin(allocator, &df2, &[_][]const u8{"user_id"});
    /// defer joined.deinit();
    /// ```
    pub fn innerJoin(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        other: *const DataFrame,
        join_cols: []const []const u8,
    ) !DataFrame {
        const join_mod = @import("join.zig");
        return join_mod.innerJoin(self, other, allocator, join_cols);
    }

    /// Performs left join with another DataFrame
    ///
    /// Args:
    ///   - allocator: Allocator for result DataFrame
    ///   - other: Right DataFrame to join with
    ///   - join_cols: Column names to join on
    ///
    /// Returns: New DataFrame with all left rows + matching right (caller owns, must call deinit())
    ///
    /// Performance: O(n + m) where n, m are row counts
    ///
    /// Example:
    /// ```zig
    /// const joined = try df1.leftJoin(allocator, &df2, &[_][]const u8{"user_id"});
    /// defer joined.deinit();
    /// ```
    pub fn leftJoin(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        other: *const DataFrame,
        join_cols: []const []const u8,
    ) !DataFrame {
        const join_mod = @import("join.zig");
        return join_mod.leftJoin(self, other, allocator, join_cols);
    }

    /// Returns unique values from a column
    ///
    /// Args:
    ///   - allocator: Allocator for result array
    ///   - column_name: Name of column to get unique values from
    ///
    /// Returns: Array of unique values (caller must free)
    ///
    /// Performance: O(n) average case with hash map
    ///
    /// Example:
    /// ```zig
    /// const unique_cities = try df.unique(allocator, "city");
    /// defer allocator.free(unique_cities);
    /// ```
    pub fn unique(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        column_name: []const u8,
    ) ![]const []const u8 {
        const ops = @import("additional_ops.zig");
        return ops.unique(self, allocator, column_name);
    }

    /// Removes duplicate rows from DataFrame
    ///
    /// Args:
    ///   - allocator: Allocator for new DataFrame
    ///   - subset: Columns to consider for duplicates (all if null)
    ///
    /// Returns: New DataFrame without duplicates (caller owns, must call deinit())
    ///
    /// Performance: O(n * k) where n is rows, k is columns in subset
    ///
    /// Example:
    /// ```zig
    /// const no_dupes = try df.dropDuplicates(allocator, &[_][]const u8{"name", "age"});
    /// defer no_dupes.deinit();
    /// ```
    pub fn dropDuplicates(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        subset: ?[]const []const u8,
    ) !DataFrame {
        const ops = @import("additional_ops.zig");
        return ops.dropDuplicates(self, allocator, subset);
    }

    /// Renames columns in DataFrame
    ///
    /// Args:
    ///   - allocator: Allocator for new DataFrame
    ///   - rename_map: Map of old name -> new name
    ///
    /// Returns: New DataFrame with renamed columns (caller owns, must call deinit())
    ///
    /// Performance: O(n * m) where n is rows, m is columns
    ///
    /// Example:
    /// ```zig
    /// var rename_map = std.StringHashMap([]const u8).init(allocator);
    /// try rename_map.put("old_name", "new_name");
    /// const renamed = try df.rename(allocator, &rename_map);
    /// defer renamed.deinit();
    /// ```
    pub fn rename(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        rename_map: *const std.StringHashMap([]const u8),
    ) !DataFrame {
        const ops = @import("additional_ops.zig");
        return ops.rename(self, allocator, rename_map);
    }

    /// Returns first n rows of DataFrame
    ///
    /// Args:
    ///   - allocator: Allocator for new DataFrame
    ///   - n: Number of rows to return
    ///
    /// Returns: New DataFrame with first n rows (caller owns, must call deinit())
    ///
    /// Performance: O(n * m) where n is rows, m is columns
    ///
    /// Example:
    /// ```zig
    /// const preview = try df.head(allocator, 10);
    /// defer preview.deinit();
    /// ```
    pub fn head(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        n: u32,
    ) !DataFrame {
        const ops = @import("additional_ops.zig");
        return ops.head(self, allocator, n);
    }

    /// Returns last n rows of DataFrame
    ///
    /// Args:
    ///   - allocator: Allocator for new DataFrame
    ///   - n: Number of rows to return
    ///
    /// Returns: New DataFrame with last n rows (caller owns, must call deinit())
    ///
    /// Performance: O(n * m) where n is rows, m is columns
    ///
    /// Example:
    /// ```zig
    /// const last_rows = try df.tail(allocator, 10);
    /// defer last_rows.deinit();
    /// ```
    pub fn tail(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        n: u32,
    ) !DataFrame {
        const ops = @import("additional_ops.zig");
        return ops.tail(self, allocator, n);
    }

    /// Returns statistical summary of DataFrame
    ///
    /// Args:
    ///   - allocator: Allocator for result map
    ///
    /// Returns: Map of column name -> Summary (caller must deinit)
    ///
    /// Performance: O(n * m) where n is rows, m is numeric columns
    ///
    /// Example:
    /// ```zig
    /// const summary = try df.describe(allocator);
    /// defer summary.deinit();
    ///
    /// const age_summary = summary.get("age").?;
    /// std.debug.print("Age - mean: {d}, std: {d}\n", .{age_summary.mean.?, age_summary.std.?});
    /// ```
    pub fn describe(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
    ) !std.StringHashMap(Summary) {
        const ops = @import("additional_ops.zig");
        return ops.describe(self, allocator);
    }

    /// Returns random sample of n rows from DataFrame
    ///
    /// Args:
    ///   - allocator: Allocator for new DataFrame
    ///   - n: Number of rows to sample (with replacement)
    ///
    /// Returns: New DataFrame with n random rows (caller owns, must call deinit())
    ///
    /// Performance: O(n * m) where n is sample size, m is columns
    ///
    /// Example:
    /// ```zig
    /// const sample_df = try df.sample(allocator, 100);
    /// defer sample_df.deinit();
    /// ```
    pub fn sample(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
        n: u32,
    ) !DataFrame {
        const ops = @import("additional_ops.zig");
        return ops.sample(self, allocator, n);
    }

    /// Returns schema information for DataFrame
    ///
    /// Prints column names, types, null counts, and memory usage
    /// Useful for quick DataFrame inspection
    ///
    /// Args:
    ///   - writer: Output writer (e.g., stdout, stderr, or string buffer)
    ///
    /// Performance: O(m) where m is number of columns
    ///
    /// Example:
    /// ```zig
    /// const stdout = std.io.getStdOut().writer();
    /// try df.info(stdout);
    /// ```
    pub fn info(self: *const DataFrame, writer: anytype) !void {
        std.debug.assert(self.columns.len > 0); // Pre-condition #1
        std.debug.assert(self.columns.len <= MAX_COLS); // Pre-condition #2

        try writer.print("DataFrame Info:\n", .{});
        try writer.print("Rows: {}\n", .{self.row_count});
        try writer.print("Columns: {}\n\n", .{self.columns.len});
        try writer.print("Column Details:\n", .{});
        try writer.print("{s:<20} {s:<15} {s:<10} {s:<15}\n", .{ "Name", "Type", "Null Count", "Memory (bytes)" });
        try writer.print("{s}\n", .{"-" ** 65});

        var total_memory: usize = 0;
        var col_idx: u32 = 0;
        while (col_idx < MAX_COLS and col_idx < self.columns.len) : (col_idx += 1) {
            const col = &self.columns[col_idx];
            const col_name = self.column_descs[col_idx].name;

            // Count nulls (for now, all columns are non-null)
            const null_count: u32 = 0;

            // Estimate memory usage
            const memory: usize = switch (col.value_type) {
                .Int64 => self.row_count * @sizeOf(i64),
                .Float64 => self.row_count * @sizeOf(f64),
                .Bool => self.row_count * @sizeOf(bool),
                .String => blk: {
                    const string_col = col.asStringColumn() orelse break :blk 0;
                    break :blk string_col.memoryUsage();
                },
                .Categorical => blk: {
                    const cat_col = col.asCategoricalColumn() orelse break :blk 0;
                    break :blk cat_col.memoryUsage();
                },
                .Null => 0,
            };

            total_memory += memory;

            try writer.print("{s:<20} {s:<15} {d:<10} {d:<15}\n", .{
                col_name,
                @tagName(col.value_type),
                null_count,
                memory,
            });
        }
        std.debug.assert(col_idx == self.columns.len); // Post-condition #3

        try writer.print("\nTotal Memory: {} bytes ({d:.2} MB)\n", .{
            total_memory,
            @as(f64, @floatFromInt(total_memory)) / (1024.0 * 1024.0),
        });
    }

    /// Convert DataFrame to Apache Arrow RecordBatch (zero-copy where possible)
    ///
    /// **Performance**: Zero-copy for numeric types (Int64, Float64, Bool)
    /// **Memory**: O(1) additional memory for schema + buffer metadata
    ///
    /// **Apache Arrow Interop**:
    /// - Compatible with PyArrow 10.0+ and Arrow JS 10.0+
    /// - Numeric columns use zero-copy (shared memory)
    /// - String columns require copying (variable-length encoding)
    ///
    /// Example:
    /// ```zig
    /// const batch = try df.toArrow(allocator);
    /// defer batch.deinit();
    /// defer batch.schema.deinit();
    ///
    /// // Use with PyArrow or Arrow JS
    /// ```
    pub fn toArrow(
        self: *const DataFrame,
        allocator: std.mem.Allocator,
    ) !@import("../arrow/ipc.zig").RecordBatch {
        const arrow_ipc = @import("../arrow/ipc.zig");
        return try arrow_ipc.dataFrameToArrow(allocator, self);
    }

    /// Create DataFrame from Apache Arrow RecordBatch
    ///
    /// **Performance**: Zero-copy where possible, allocates for safety
    /// **Memory**: O(n × m) for data (MVP allocates new memory for safety)
    ///
    /// **Apache Arrow Interop**:
    /// - Compatible with PyArrow 10.0+ and Arrow JS 10.0+
    /// - Future optimization: zero-copy via shared memory
    ///
    /// Example:
    /// ```zig
    /// const batch = // ... from PyArrow or Arrow JS
    /// const df = try DataFrame.fromArrow(allocator, &batch);
    /// defer df.free();
    /// ```
    pub fn fromArrow(
        allocator: std.mem.Allocator,
        batch: *const @import("../arrow/ipc.zig").RecordBatch,
    ) !DataFrame {
        const arrow_ipc = @import("../arrow/ipc.zig");
        return try arrow_ipc.arrowToDataFrame(allocator, batch);
    }
};

// Re-export sort types for convenience
pub const SortOrder = @import("sort.zig").SortOrder;
pub const SortSpec = @import("sort.zig").SortSpec;

// Re-export groupby types for convenience
pub const GroupBy = @import("groupby.zig").GroupBy;
pub const AggFunc = @import("groupby.zig").AggFunc;
pub const AggSpec = @import("groupby.zig").AggSpec;

// Re-export additional operations types for convenience
pub const Summary = @import("additional_ops.zig").Summary;

/// Reference to a single row in a DataFrame
pub const RowRef = struct {
    dataframe: *const DataFrame,
    rowIndex: u32,

    /// Gets value from column as Int64
    pub fn getInt64(self: RowRef, colName: []const u8) ?i64 {
        std.debug.assert(colName.len > 0); // Name required
        std.debug.assert(self.rowIndex < self.dataframe.row_count); // Valid row index

        const col = self.dataframe.column(colName) orelse return null;
        const data = col.asInt64() orelse return null;

        if (self.rowIndex >= data.len) return null;
        return data[self.rowIndex];
    }

    /// Gets value from column as Float64
    pub fn getFloat64(self: RowRef, colName: []const u8) ?f64 {
        std.debug.assert(colName.len > 0); // Name required
        std.debug.assert(self.rowIndex < self.dataframe.row_count); // Valid row index

        const col = self.dataframe.column(colName) orelse return null;
        const data = col.asFloat64() orelse return null;

        if (self.rowIndex >= data.len) return null;
        return data[self.rowIndex];
    }

    /// Gets value from column as Bool
    pub fn getBool(self: RowRef, colName: []const u8) ?bool {
        std.debug.assert(colName.len > 0); // Name required
        std.debug.assert(self.rowIndex < self.dataframe.row_count); // Valid row index

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
    try testing.expectEqual(ValueType.Int64, age_col.value_type);

    const score_col = df.column("score").?;
    try testing.expectEqualStrings("score", score_col.name);
    try testing.expectEqual(ValueType.Float64, score_col.value_type);
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

test "DataFrame.toCSV exports DataFrame correctly" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cols = [_]ColumnDesc{
        ColumnDesc.init("age", .Int64, 0),
        ColumnDesc.init("score", .Float64, 1),
    };

    var df = try DataFrame.create(allocator, &cols, 10);
    defer df.deinit();

    // Set data
    const age_col = df.columnMut("age").?;
    const ages = age_col.asInt64Buffer().?;
    ages[0] = 30;
    ages[1] = 25;

    const score_col = df.columnMut("score").?;
    const scores = score_col.asFloat64Buffer().?;
    scores[0] = 95.5;
    scores[1] = 87.3;

    try df.setRowCount(2);

    // Export to CSV
    const csv = try df.toCSV(allocator, .{});
    defer allocator.free(csv);

    // Verify output
    try testing.expect(std.mem.indexOf(u8, csv, "age,score") != null);
    try testing.expect(std.mem.indexOf(u8, csv, "30,") != null);
    try testing.expect(std.mem.indexOf(u8, csv, "25,") != null);
}
