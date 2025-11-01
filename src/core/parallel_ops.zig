const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Atomic = std.atomic.Value;
const DataFrame = @import("dataframe.zig").DataFrame;
const Row = @import("types.zig").Row;

/// Maximum number of worker threads for parallel operations
pub const MAX_THREADS: u32 = 8;

/// Minimum dataset size to justify parallel execution overhead
pub const MIN_PARALLEL_SIZE: u32 = 100_000;

/// Task represents a unit of work for parallel execution
pub const Task = struct {
    start_row: u32,
    end_row: u32,
    thread_id: u32,
};

/// ThreadPool manages worker threads for parallel DataFrame operations
pub const ThreadPool = struct {
    allocator: Allocator,
    threads: []Thread,
    num_threads: u32,

    /// Initialize thread pool with specified number of threads
    pub fn init(allocator: Allocator, num_threads: u32) !ThreadPool {
        std.debug.assert(num_threads > 0);
        std.debug.assert(num_threads <= MAX_THREADS);

        const threads = try allocator.alloc(Thread, num_threads);

        return ThreadPool{
            .allocator = allocator,
            .threads = threads,
            .num_threads = num_threads,
        };
    }

    /// Free thread pool resources
    pub fn deinit(self: *ThreadPool) void {
        self.allocator.free(self.threads);
    }

    /// Calculate optimal number of threads based on dataset size
    pub fn optimalThreadCount(row_count: u32) u32 {
        std.debug.assert(row_count > 0);

        // Use single thread for small datasets
        if (row_count < MIN_PARALLEL_SIZE) {
            return 1;
        }

        // Get CPU count (capped at MAX_THREADS)
        const cpu_count = @min(std.Thread.getCpuCount() catch 4, MAX_THREADS);

        // Use fewer threads for medium datasets
        if (row_count < 1_000_000) {
            return @min(cpu_count / 2, 4);
        }

        return @intCast(cpu_count);
    }

    /// Partition rows into chunks for parallel processing
    pub fn partitionRows(
        row_count: u32,
        num_threads: u32,
        tasks: []Task,
    ) void {
        std.debug.assert(row_count > 0);
        std.debug.assert(num_threads > 0);
        std.debug.assert(num_threads <= MAX_THREADS);
        std.debug.assert(tasks.len == num_threads);

        const chunk_size = row_count / num_threads;
        const remainder = row_count % num_threads;

        var start: u32 = 0;
        var i: u32 = 0;
        while (i < num_threads and i < MAX_THREADS) : (i += 1) {
            const extra: u32 = if (i < remainder) 1 else 0;
            const end = start + chunk_size + extra;

            tasks[i] = Task{
                .start_row = start,
                .end_row = end,
                .thread_id = i,
            };

            start = end;
        }
        std.debug.assert(i == num_threads); // Post-condition: All tasks partitioned
    }
};

/// FilterContext contains data needed for parallel filtering
pub const FilterContext = struct {
    // Predicate function to apply
    predicate_fn: *const fn (row_index: u32, context: *anyopaque) bool,
    predicate_context: *anyopaque,

    // Input data
    row_count: u32,

    // Output buffers (one per thread)
    output_indices: [][]u32,
    output_counts: []Atomic(u32),

    allocator: Allocator,

    pub fn init(
        allocator: Allocator,
        row_count: u32,
        num_threads: u32,
        predicate_fn: *const fn (row_index: u32, context: *anyopaque) bool,
        predicate_context: *anyopaque,
    ) !FilterContext {
        std.debug.assert(row_count > 0);
        std.debug.assert(num_threads > 0);
        std.debug.assert(num_threads <= MAX_THREADS);

        // Allocate output buffers
        const output_indices = try allocator.alloc([]u32, num_threads);
        errdefer allocator.free(output_indices);

        const output_counts = try allocator.alloc(Atomic(u32), num_threads);
        errdefer allocator.free(output_counts);

        // Estimate buffer size per thread
        const rows_per_thread = (row_count + num_threads - 1) / num_threads;

        var i: u32 = 0;
        while (i < num_threads and i < MAX_THREADS) : (i += 1) {
            output_indices[i] = try allocator.alloc(u32, rows_per_thread);
            output_counts[i] = Atomic(u32).init(0);
        }
        std.debug.assert(i == num_threads); // Post-condition: All buffers initialized

        return FilterContext{
            .predicate_fn = predicate_fn,
            .predicate_context = predicate_context,
            .row_count = row_count,
            .output_indices = output_indices,
            .output_counts = output_counts,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FilterContext) void {
        var i: u32 = 0;
        while (i < self.output_indices.len and i < MAX_THREADS) : (i += 1) {
            self.allocator.free(self.output_indices[i]);
        }
        std.debug.assert(i == self.output_indices.len); // Post-condition: All indices freed
        self.allocator.free(self.output_indices);
        self.allocator.free(self.output_counts);
    }
};

/// Worker function for parallel filter operation
fn filterWorker(task: Task, context: *FilterContext) void {
    var count: u32 = 0;
    const indices = context.output_indices[task.thread_id];

    // Apply predicate to each row in partition
    for (task.start_row..task.end_row) |row| {
        const row_u32: u32 = @intCast(row);
        if (context.predicate_fn(row_u32, context.predicate_context)) {
            indices[count] = row_u32;
            count += 1;
        }
    }

    // Store count atomically
    context.output_counts[task.thread_id].store(count, .monotonic);
}

/// Execute parallel filter operation
pub fn parallelFilter(
    allocator: Allocator,
    row_count: u32,
    predicate_fn: *const fn (row_index: u32, context: *anyopaque) bool,
    predicate_context: *anyopaque,
) ![]u32 {
    std.debug.assert(row_count > 0);

    // Determine thread count
    const num_threads = ThreadPool.optimalThreadCount(row_count);

    // Initialize context
    var context = try FilterContext.init(
        allocator,
        row_count,
        num_threads,
        predicate_fn,
        predicate_context,
    );
    defer context.deinit();

    // Create thread pool
    var pool = try ThreadPool.init(allocator, num_threads);
    defer pool.deinit();

    // Partition work
    const tasks = try allocator.alloc(Task, num_threads);
    defer allocator.free(tasks);
    ThreadPool.partitionRows(row_count, num_threads, tasks);

    // Spawn worker threads
    var spawn_idx: u32 = 0;
    while (spawn_idx < num_threads and spawn_idx < MAX_THREADS) : (spawn_idx += 1) {
        const task = tasks[spawn_idx];
        pool.threads[spawn_idx] = try Thread.spawn(.{}, filterWorker, .{ task, &context });
    }
    std.debug.assert(spawn_idx == num_threads); // Post-condition: All threads spawned

    // Wait for completion
    var join_idx: u32 = 0;
    while (join_idx < pool.threads.len and join_idx < MAX_THREADS) : (join_idx += 1) {
        pool.threads[join_idx].join();
    }
    std.debug.assert(join_idx == pool.threads.len); // Post-condition: All threads joined

    // Merge results
    return try mergeFilterResults(&context);
}

/// Merge filter results from all threads
fn mergeFilterResults(context: *FilterContext) ![]u32 {
    // Calculate total count
    var total_count: u32 = 0;
    var count_idx: u32 = 0;
    while (count_idx < context.output_counts.len and count_idx < MAX_THREADS) : (count_idx += 1) {
        total_count += context.output_counts[count_idx].load(.monotonic);
    }
    std.debug.assert(count_idx == context.output_counts.len); // Post-condition: All counts summed

    // Allocate output buffer
    const result = try context.allocator.alloc(u32, total_count);
    errdefer context.allocator.free(result);

    // Copy indices from each thread
    var offset: u32 = 0;
    for (context.output_indices, context.output_counts) |indices, count_atomic| {
        const count = count_atomic.load(.monotonic);
        @memcpy(result[offset .. offset + count], indices[0..count]);
        offset += count;
    }

    std.debug.assert(offset == total_count);
    return result;
}

test "ThreadPool.optimalThreadCount" {
    const testing = std.testing;

    // Small dataset -> 1 thread
    try testing.expectEqual(@as(u32, 1), ThreadPool.optimalThreadCount(1000));
    try testing.expectEqual(@as(u32, 1), ThreadPool.optimalThreadCount(50_000));

    // Medium dataset -> fewer threads
    const medium_threads = ThreadPool.optimalThreadCount(500_000);
    try testing.expect(medium_threads >= 1 and medium_threads <= 4);

    // Large dataset -> more threads
    const large_threads = ThreadPool.optimalThreadCount(10_000_000);
    try testing.expect(large_threads >= 1 and large_threads <= MAX_THREADS);
}

test "ThreadPool.partitionRows" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const row_count: u32 = 1000;
    const num_threads: u32 = 4;

    const tasks = try allocator.alloc(Task, num_threads);
    defer allocator.free(tasks);

    ThreadPool.partitionRows(row_count, num_threads, tasks);

    // Verify each task has valid range
    var i: u32 = 0;
    while (i < tasks.len and i < MAX_THREADS) : (i += 1) {
        const task = tasks[i];
        try testing.expectEqual(@as(u32, @intCast(i)), task.thread_id);
        try testing.expect(task.start_row < task.end_row);
    }
    std.debug.assert(i == tasks.len); // Post-condition: All tasks verified

    // Verify contiguous coverage
    try testing.expectEqual(@as(u32, 0), tasks[0].start_row);
    var check_idx: u32 = 1;
    while (check_idx < num_threads and check_idx < MAX_THREADS) : (check_idx += 1) {
        try testing.expectEqual(tasks[check_idx - 1].end_row, tasks[check_idx].start_row);
    }
    std.debug.assert(check_idx == num_threads); // Post-condition: All boundaries checked
    try testing.expectEqual(row_count, tasks[num_threads - 1].end_row);
}

test "parallelFilter: basic filtering" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test data: filter even numbers
    const Context = struct {
        fn predicate(row_index: u32, ctx: *anyopaque) bool {
            _ = ctx;
            return row_index % 2 == 0;
        }
    };

    const row_count: u32 = 100_000;
    var dummy_context: u8 = 0;

    const result = try parallelFilter(
        allocator,
        row_count,
        Context.predicate,
        &dummy_context,
    );
    defer allocator.free(result);

    // Should have 50,000 even numbers
    try testing.expectEqual(@as(usize, 50_000), result.len);

    // Verify all results are even
    var verify_idx: u32 = 0;
    while (verify_idx < result.len and verify_idx < 100_000) : (verify_idx += 1) {
        try testing.expect(result[verify_idx] % 2 == 0);
        try testing.expect(result[verify_idx] < row_count);
    }
    std.debug.assert(verify_idx == result.len); // Post-condition: All results verified
}

test "parallelFilter: small dataset single thread" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Small dataset should use single thread
    const Context = struct {
        fn predicate(row_index: u32, ctx: *anyopaque) bool {
            _ = ctx;
            return row_index < 50;
        }
    };

    const row_count: u32 = 1000;
    var dummy_context: u8 = 0;

    const result = try parallelFilter(
        allocator,
        row_count,
        Context.predicate,
        &dummy_context,
    );
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 50), result.len);
}

// ============================================================================
// DataFrame-Specific Parallel Operations
// ============================================================================

/// Context for parallel DataFrame filter operation
pub const DataFrameFilterContext = struct {
    df: *const DataFrame,
    predicate: *const fn (row: Row) bool,
    output_indices: [][]u32,
    output_counts: []Atomic(u32),
    allocator: Allocator,

    pub fn init(
        allocator: Allocator,
        df: *const DataFrame,
        num_threads: u32,
        predicate: *const fn (row: Row) bool,
    ) !DataFrameFilterContext {
        std.debug.assert(df.len() > 0);
        std.debug.assert(num_threads > 0);
        std.debug.assert(num_threads <= MAX_THREADS);

        // Allocate output buffers
        const output_indices = try allocator.alloc([]u32, num_threads);
        errdefer allocator.free(output_indices);

        const output_counts = try allocator.alloc(Atomic(u32), num_threads);
        errdefer allocator.free(output_counts);

        // Estimate buffer size per thread
        const rows_per_thread = (df.len() + num_threads - 1) / num_threads;

        var i: u32 = 0;
        while (i < num_threads and i < MAX_THREADS) : (i += 1) {
            output_indices[i] = try allocator.alloc(u32, rows_per_thread);
            output_counts[i] = Atomic(u32).init(0);
        }
        std.debug.assert(i == num_threads); // Post-condition: All buffers initialized

        return DataFrameFilterContext{
            .df = df,
            .predicate = predicate,
            .output_indices = output_indices,
            .output_counts = output_counts,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DataFrameFilterContext) void {
        var i: u32 = 0;
        while (i < self.output_indices.len and i < MAX_THREADS) : (i += 1) {
            self.allocator.free(self.output_indices[i]);
        }
        std.debug.assert(i == self.output_indices.len); // Post-condition: All indices freed
        self.allocator.free(self.output_indices);
        self.allocator.free(self.output_counts);
    }
};

/// Worker function for parallel DataFrame filter
fn dataFrameFilterWorker(task: Task, context: *DataFrameFilterContext) void {
    var count: u32 = 0;
    const indices = context.output_indices[task.thread_id];

    // Apply predicate to each row in partition
    for (task.start_row..task.end_row) |row_idx| {
        const row_u32: u32 = @intCast(row_idx);
        // Get row (error handling: skip row if error)
        const row = context.df.row(row_u32) catch continue;

        if (context.predicate(row)) {
            indices[count] = row_u32;
            count += 1;
        }
    }

    // Store count atomically
    context.output_counts[task.thread_id].store(count, .monotonic);
}

/// Execute parallel DataFrame filter operation
/// Returns list of matching row indices
pub fn parallelDataFrameFilter(
    allocator: Allocator,
    df: *const DataFrame,
    predicate: *const fn (row: Row) bool,
) ![]u32 {
    std.debug.assert(df.len() > 0);

    const row_count = df.len();

    // Determine thread count
    const num_threads = ThreadPool.optimalThreadCount(row_count);

    // Initialize context
    var context = try DataFrameFilterContext.init(
        allocator,
        df,
        num_threads,
        predicate,
    );
    defer context.deinit();

    // Create thread pool
    var pool = try ThreadPool.init(allocator, num_threads);
    defer pool.deinit();

    // Partition work
    const tasks = try allocator.alloc(Task, num_threads);
    defer allocator.free(tasks);
    ThreadPool.partitionRows(row_count, num_threads, tasks);

    // Spawn worker threads
    var spawn_idx: u32 = 0;
    while (spawn_idx < num_threads and spawn_idx < MAX_THREADS) : (spawn_idx += 1) {
        const task = tasks[spawn_idx];
        pool.threads[spawn_idx] = try Thread.spawn(.{}, dataFrameFilterWorker, .{ task, &context });
    }
    std.debug.assert(spawn_idx == num_threads); // Post-condition: All threads spawned

    // Wait for completion
    var join_idx: u32 = 0;
    while (join_idx < pool.threads.len and join_idx < MAX_THREADS) : (join_idx += 1) {
        pool.threads[join_idx].join();
    }
    std.debug.assert(join_idx == pool.threads.len); // Post-condition: All threads joined

    // Merge results
    return try mergeDataFrameFilterResults(&context);
}

/// Merge DataFrame filter results from all threads
fn mergeDataFrameFilterResults(context: *DataFrameFilterContext) ![]u32 {
    // Calculate total count
    var total_count: u32 = 0;
    var count_idx: u32 = 0;
    while (count_idx < context.output_counts.len and count_idx < MAX_THREADS) : (count_idx += 1) {
        total_count += context.output_counts[count_idx].load(.monotonic);
    }
    std.debug.assert(count_idx == context.output_counts.len); // Post-condition: All counts summed

    // Allocate output buffer
    const result = try context.allocator.alloc(u32, total_count);
    errdefer context.allocator.free(result);

    // Copy indices from each thread
    var offset: u32 = 0;
    for (context.output_indices, context.output_counts) |indices, count_atomic| {
        const count = count_atomic.load(.monotonic);
        @memcpy(result[offset .. offset + count], indices[0..count]);
        offset += count;
    }

    std.debug.assert(offset == total_count);
    return result;
}
