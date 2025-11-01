//! Parallel CSV Parser - Multi-threaded Type Inference
//!
//! This module implements parallel CSV parsing with:
//! - Work-stealing thread pool (max 8 threads)
//! - Chunking strategy (64KB-1MB adaptive chunks)
//! - Quote/escape boundary handling
//! - Parallel type inference with conflict resolution
//!
//! **Performance Targets**:
//! - 2-4× speedup on 4+ cores
//! - Correct handling of chunk boundaries
//! - Graceful degradation on single-core systems
//!
//! See docs/TODO.md Milestone 1.2.0 Phase 3

const std = @import("std");
const core_types = @import("../core/types.zig");
const DataFrame = @import("../core/dataframe.zig").DataFrame;
const CSVParser = @import("parser.zig").CSVParser;
const simd = @import("../core/simd.zig");

const ValueType = core_types.ValueType;
const CSVOptions = core_types.CSVOptions;

/// Maximum number of worker threads
const MAX_THREADS: u32 = 8;

/// Chunk size limits (adaptive based on file size)
const MIN_CHUNK_SIZE: usize = 64 * 1024;      // 64KB
const MAX_CHUNK_SIZE: usize = 1024 * 1024;    // 1MB
const TARGET_CHUNKS_PER_THREAD: u32 = 4;      // Each thread processes 4 chunks

/// Maximum CSV file size for parallel parsing
const MAX_CSV_SIZE: u32 = 1024 * 1024 * 1024; // 1GB

/// Chunk descriptor for parallel processing
const Chunk = struct {
    start: usize,           // Start offset in buffer
    end: usize,             // End offset in buffer
    row_start: u32,         // First row index in this chunk
    row_count: u32,         // Number of rows in chunk
    col_count: u32,         // Number of columns detected
    types: []ValueType,     // Inferred types for each column

    /// Pre-condition assertions
    pub fn validate(self: *const Chunk) void {
        std.debug.assert(self.start < self.end); // Valid range
        std.debug.assert(self.end - self.start <= MAX_CHUNK_SIZE); // Size limit
        std.debug.assert(self.col_count > 0); // Has columns
        std.debug.assert(self.types.len == self.col_count); // Type array matches
    }
};

/// Type inference result from a chunk
const ChunkInferenceResult = struct {
    chunk_id: u32,
    col_types: []ValueType,
    confidence: []f32,      // Confidence score for each type (0.0-1.0)
    row_count: u32,         // Rows processed in this chunk

    pub fn init(allocator: std.mem.Allocator, col_count: u32) !ChunkInferenceResult {
        std.debug.assert(col_count > 0); // Pre-condition #1
        std.debug.assert(col_count <= 10_000); // Pre-condition #2: Reasonable limit

        const col_types = try allocator.alloc(ValueType, col_count);
        const confidence = try allocator.alloc(f32, col_count);

        // Initialize to unknown
        var i: u32 = 0;
        while (i < col_count) : (i += 1) {
            col_types[i] = .String; // Default to most permissive
            confidence[i] = 0.0;
        }

        std.debug.assert(i == col_count); // Post-condition

        return ChunkInferenceResult{
            .chunk_id = 0,
            .col_types = col_types,
            .confidence = confidence,
            .row_count = 0,
        };
    }

    pub fn deinit(self: *ChunkInferenceResult, allocator: std.mem.Allocator) void {
        std.debug.assert(self.col_types.len > 0); // Pre-condition #1
        std.debug.assert(self.col_types.len == self.confidence.len); // Pre-condition #2

        allocator.free(self.col_types);
        allocator.free(self.confidence);
    }
};

/// Parallel CSV Parser
pub const ParallelCSVParser = struct {
    allocator: std.mem.Allocator,
    buffer: []const u8,
    opts: CSVOptions,
    thread_count: u32,
    chunks: []Chunk,

    /// Initialize parallel CSV parser
    pub fn init(
        allocator: std.mem.Allocator,
        buffer: []const u8,
        opts: CSVOptions,
    ) !ParallelCSVParser {
        std.debug.assert(buffer.len > 0); // Pre-condition #1
        std.debug.assert(buffer.len <= MAX_CSV_SIZE); // Pre-condition #2

        // Determine optimal thread count based on CPU and file size
        const cpu_count = try std.Thread.getCpuCount();
        std.debug.assert(cpu_count > 0); // Pre-condition: Valid CPU count
        std.debug.assert(cpu_count <= 1024); // Pre-condition: Reasonable upper bound

        const optimal_threads = @min(@as(u32, @intCast(cpu_count)), MAX_THREADS);
        std.debug.assert(optimal_threads > 0); // Post-condition: Valid thread count

        // For small files, use single thread (overhead not worth it)
        const thread_count = if (buffer.len < MIN_CHUNK_SIZE * 2)
            1
        else
            optimal_threads;

        std.debug.assert(thread_count > 0); // Post-condition #1
        std.debug.assert(thread_count <= MAX_THREADS); // Post-condition #2

        return ParallelCSVParser{
            .allocator = allocator,
            .buffer = buffer,
            .opts = opts,
            .thread_count = thread_count,
            .chunks = &[_]Chunk{},
        };
    }

    /// Parse CSV to DataFrame using parallel type inference
    pub fn toDataFrame(self: *ParallelCSVParser) !DataFrame {
        std.debug.assert(self.buffer.len > 0); // Pre-condition #1
        std.debug.assert(self.thread_count > 0); // Pre-condition #2

        // For single-threaded mode, fall back to sequential parser
        if (self.thread_count == 1) {
            var sequential_parser = try CSVParser.init(
                self.allocator,
                self.buffer,
                self.opts,
            );
            defer sequential_parser.deinit();

            return try sequential_parser.toDataFrame();
        }

        // Step 1: Split buffer into chunks
        try self.createChunks();
        defer self.cleanupChunks();

        // Step 2: Parallel type inference across chunks
        const chunk_results = try self.inferTypesParallel();
        defer self.cleanupResults(chunk_results);

        // Step 3: Merge type inference results
        const final_types = try self.mergeTypeInference(chunk_results);
        defer self.allocator.free(final_types);

        // Step 4: Parse full CSV with inferred types
        // TODO: Implement parallel DataFrame construction
        return error.NotImplemented;
    }

    /// Create chunks with proper boundary handling
    fn createChunks(self: *ParallelCSVParser) !void {
        std.debug.assert(self.buffer.len > 0); // Pre-condition #1
        std.debug.assert(self.thread_count > 0); // Pre-condition #2

        const total_chunks = self.thread_count * TARGET_CHUNKS_PER_THREAD;
        const target_chunk_size = self.buffer.len / total_chunks;

        // Clamp to reasonable range
        const chunk_size = std.math.clamp(
            target_chunk_size,
            MIN_CHUNK_SIZE,
            MAX_CHUNK_SIZE,
        );

        var chunks_list = std.ArrayList(Chunk).init(self.allocator);
        defer chunks_list.deinit();

        var current_pos: usize = 0;
        var chunk_id: u32 = 0;

        while (current_pos < self.buffer.len and chunk_id < total_chunks) : (chunk_id += 1) {
            const chunk_end = @min(current_pos + chunk_size, self.buffer.len);

            // Find safe chunk boundary (end of line)
            const safe_end = try self.findChunkBoundary(current_pos, chunk_end);

            if (safe_end <= current_pos) {
                // Couldn't find boundary, this chunk is done
                break;
            }

            // Create chunk descriptor
            const chunk = Chunk{
                .start = current_pos,
                .end = safe_end,
                .row_start = 0, // Will be set during parsing
                .row_count = 0,
                .col_count = 0,
                .types = &[_]ValueType{},
            };

            try chunks_list.append(chunk);
            current_pos = safe_end;
        }

        std.debug.assert(chunk_id <= total_chunks); // Post-condition

        self.chunks = try chunks_list.toOwnedSlice();
    }

    /// Find safe chunk boundary (end of complete row)
    ///
    /// **Algorithm**:
    /// 1. Start from target_end and scan backwards
    /// 2. Find nearest newline that's NOT inside quotes
    /// 3. Handle CRLF, LF, CR line endings
    /// 4. If no boundary found within 1KB, extend chunk
    ///
    /// **Tiger Style**:
    /// - Bounded scan (MAX_BOUNDARY_SCAN = 1024 bytes)
    /// - Quote tracking to avoid splitting quoted fields
    fn findChunkBoundary(self: *const ParallelCSVParser, start: usize, target_end: usize) !usize {
        std.debug.assert(start < target_end); // Pre-condition #1
        std.debug.assert(target_end <= self.buffer.len); // Pre-condition #2

        const MAX_BOUNDARY_SCAN: usize = 1024; // Don't scan >1KB backwards

        // Special case: If target_end is at EOF, that's a valid boundary
        if (target_end >= self.buffer.len) {
            return self.buffer.len;
        }

        // Scan backwards from target_end to find newline outside quotes
        var pos = target_end;
        var scan_distance: u32 = 0;
        var in_quotes = false;

        while (pos > start and scan_distance < MAX_BOUNDARY_SCAN) : (scan_distance += 1) {
            pos -= 1;
            const char = self.buffer[pos];

            // Track quote state (simplified - assumes no escaped quotes in scan)
            if (char == '"') {
                in_quotes = !in_quotes;
            }

            // Found newline outside quotes?
            if (!in_quotes and (char == '\n' or char == '\r')) {
                // Move past the newline
                var boundary = pos + 1;

                // Handle CRLF: If '\r\n', skip the '\n' too
                if (char == '\r' and boundary < self.buffer.len and
                    self.buffer[boundary] == '\n')
                {
                    boundary += 1;
                }

                std.debug.assert(boundary > start); // Post-condition #1
                std.debug.assert(boundary <= self.buffer.len); // Post-condition #2

                return boundary;
            }
        }

        std.debug.assert(scan_distance <= MAX_BOUNDARY_SCAN); // Post-condition #3

        // Couldn't find boundary within scan window - extend chunk to next newline
        // This handles edge case of very long lines (>1KB)
        pos = target_end;
        var forward_scan: u32 = 0;
        const MAX_FORWARD_SCAN: u32 = 10_000; // Max 10KB forward

        while (pos < self.buffer.len and forward_scan < MAX_FORWARD_SCAN) : (forward_scan += 1) {
            const char = self.buffer[pos];
            pos += 1;

            if (char == '"') {
                in_quotes = !in_quotes;
            }

            if (!in_quotes and (char == '\n' or char == '\r')) {
                var boundary = pos;

                // Handle CRLF
                if (char == '\r' and boundary < self.buffer.len and
                    self.buffer[boundary] == '\n')
                {
                    boundary += 1;
                }

                return boundary;
            }
        }

        std.debug.assert(forward_scan <= MAX_FORWARD_SCAN); // Post-condition #4

        // Still no boundary - return end of buffer (last chunk)
        return self.buffer.len;
    }

    /// Perform type inference on all chunks in parallel
    fn inferTypesParallel(self: *ParallelCSVParser) ![]ChunkInferenceResult {
        std.debug.assert(self.chunks.len > 0); // Pre-condition #1
        std.debug.assert(self.thread_count > 0); // Pre-condition #2

        // Allocate results array
        const results = try self.allocator.alloc(ChunkInferenceResult, self.chunks.len);
        errdefer self.allocator.free(results);

        // Initialize results
        var i: u32 = 0;
        while (i < results.len) : (i += 1) {
            // Get first chunk to determine column count
            // Note: All chunks should have same column count
            const col_count = if (i == 0) blk: {
                // Parse first line of first chunk to get col count
                const first_line_end = std.mem.indexOfScalar(u8, self.buffer, '\n') orelse self.buffer.len;
                const first_line = self.buffer[0..first_line_end];

                var col_count_calc: u32 = 1; // At least 1 column
                var j: u32 = 0;
                const max_scan: u32 = @min(@as(u32, @intCast(first_line.len)), 10_000);
                while (j < max_scan) : (j += 1) {
                    if (first_line[j] == self.opts.delimiter) {
                        col_count_calc += 1;
                    }
                }
                std.debug.assert(j == max_scan); // Post-condition: Scanned entire line or hit limit
                break :blk col_count_calc;
            } else results[0].col_types.len;

            results[i] = try ChunkInferenceResult.init(self.allocator, @intCast(col_count));
            results[i].chunk_id = i;
        }
        std.debug.assert(i == results.len); // Post-condition

        // Process chunks in parallel using thread pool
        if (self.thread_count > 1) {
            // Context for worker threads (process a range of chunks)
            const WorkerContext = struct {
                parser: *const ParallelCSVParser,
                results: []ChunkInferenceResult,
                chunk_start: u32,
                chunk_end: u32,
            };

            // Spawn threads for parallel processing
            var threads = try self.allocator.alloc(std.Thread, self.thread_count);
            defer self.allocator.free(threads);

            var contexts = try self.allocator.alloc(WorkerContext, self.thread_count);
            defer self.allocator.free(contexts);

            // Divide chunks among threads
            const chunks_per_thread = (self.chunks.len + self.thread_count - 1) / self.thread_count;

            var thread_idx: u32 = 0;
            while (thread_idx < self.thread_count and thread_idx < self.chunks.len) : (thread_idx += 1) {
                const thread_start = thread_idx * chunks_per_thread;
                const thread_end = @min((thread_idx + 1) * chunks_per_thread, @as(u32, @intCast(self.chunks.len)));

                if (thread_start >= self.chunks.len) break;

                // Worker function that processes all chunks in its range
                const worker_fn = struct {
                    fn work(ctx: WorkerContext) void {
                        var idx = ctx.chunk_start;
                        while (idx < ctx.chunk_end and idx < ctx.parser.chunks.len) : (idx += 1) {
                            ctx.parser.inferChunkType(
                                &ctx.parser.chunks[idx],
                                &ctx.results[idx],
                            ) catch {
                                // Error in type inference - mark all columns as String
                                var type_idx: u32 = 0;
                                while (type_idx < ctx.results[idx].col_types.len and type_idx < 10_000) : (type_idx += 1) {
                                    ctx.results[idx].col_types[type_idx] = .String;
                                }
                            };
                        }
                    }
                }.work;

                // Create context for this thread
                contexts[thread_idx] = WorkerContext{
                    .parser = self,
                    .results = results,
                    .chunk_start = thread_start,
                    .chunk_end = thread_end,
                };

                threads[thread_idx] = try std.Thread.spawn(.{}, worker_fn, .{contexts[thread_idx]});
            }

            // Wait for all threads to complete
            var join_idx: u32 = 0;
            while (join_idx < thread_idx) : (join_idx += 1) {
                threads[join_idx].join();
            }
            std.debug.assert(join_idx == thread_idx); // Post-condition
        } else {
            // Single-threaded fallback
            var chunk_idx: u32 = 0;
            while (chunk_idx < self.chunks.len) : (chunk_idx += 1) {
                try self.inferChunkType(&self.chunks[chunk_idx], &results[chunk_idx]);
            }
            std.debug.assert(chunk_idx == self.chunks.len); // Post-condition
        }

        return results;
    }

    /// Infer types for a single chunk
    fn inferChunkType(self: *const ParallelCSVParser, chunk: *const Chunk, result: *ChunkInferenceResult) !void {
        std.debug.assert(chunk.start < chunk.end); // Pre-condition #1
        std.debug.assert(chunk.end <= self.buffer.len); // Pre-condition #2

        const chunk_buffer = self.buffer[chunk.start..chunk.end];

        // Parse chunk into rows (simplified - assumes well-formed CSV)
        var rows = std.ArrayList([]const u8).init(self.allocator);
        defer rows.deinit();

        var start: usize = 0;
        var scan_pos: u32 = 0;
        const MAX_SCAN: u32 = @intCast(chunk_buffer.len);

        while (scan_pos < MAX_SCAN) : (scan_pos += 1) {
            if (scan_pos >= chunk_buffer.len) break;

            const char = chunk_buffer[scan_pos];
            if (char == '\n') {
                const line = chunk_buffer[start..scan_pos];
                if (line.len > 0) {
                    try rows.append(line);
                }
                start = scan_pos + 1;
            }
        }
        std.debug.assert(scan_pos <= MAX_SCAN); // Post-condition

        // Skip if no rows
        if (rows.items.len == 0) {
            result.row_count = 0;
            return;
        }

        result.row_count = @intCast(rows.items.len);

        // Infer types for each column (simplified version)
        // In full implementation, this would parse each field and check types
        var col_idx: u32 = 0;
        while (col_idx < result.col_types.len) : (col_idx += 1) {
            // For MVP, default to String for safety
            // TODO: Implement actual type inference per column
            result.col_types[col_idx] = .String;
            result.confidence[col_idx] = 1.0; // 100% confident it's String
        }
        std.debug.assert(col_idx == result.col_types.len); // Post-condition
    }

    /// Merge type inference results from all chunks
    ///
    /// **Conflict Resolution**:
    /// - If all chunks agree → use that type
    /// - If mixed Int64/Float64 → use Float64 (Float64 ⊃ Int64)
    /// - If mixed Bool/Int64 → use Int64 (Bool ⊂ Int64)
    /// - If any String → use String (most permissive)
    ///
    /// **Confidence Weighting**:
    /// - Weight each chunk by row_count / total_rows
    /// - Higher confidence = more rows supporting that type
    fn mergeTypeInference(
        self: *ParallelCSVParser,
        chunk_results: []ChunkInferenceResult,
    ) ![]ValueType {
        std.debug.assert(chunk_results.len > 0); // Pre-condition #1
        std.debug.assert(chunk_results.len == self.chunks.len); // Pre-condition #2

        // Get column count from first chunk
        const col_count = chunk_results[0].col_types.len;

        // Allocate final types
        const final_types = try self.allocator.alloc(ValueType, col_count);

        // For each column, merge types across chunks
        var col_idx: u32 = 0;
        while (col_idx < col_count) : (col_idx += 1) {
            final_types[col_idx] = try self.mergeColumnType(chunk_results, col_idx);
        }

        std.debug.assert(col_idx == col_count); // Post-condition

        return final_types;
    }

    /// Merge type inference for a single column
    fn mergeColumnType(
        self: *ParallelCSVParser,
        chunk_results: []ChunkInferenceResult,
        col_idx: u32,
    ) !ValueType {
        std.debug.assert(chunk_results.len > 0); // Pre-condition #1
        std.debug.assert(col_idx < chunk_results[0].col_types.len); // Pre-condition #2

        // Count occurrences of each type
        var int_count: u32 = 0;
        var float_count: u32 = 0;
        var bool_count: u32 = 0;
        var string_count: u32 = 0;

        var chunk_idx: u32 = 0;
        while (chunk_idx < chunk_results.len) : (chunk_idx += 1) {
            const chunk_type = chunk_results[chunk_idx].col_types[col_idx];

            switch (chunk_type) {
                .Int64 => int_count += 1,
                .Float64 => float_count += 1,
                .Bool => bool_count += 1,
                .String => string_count += 1,
                else => {},
            }
        }

        std.debug.assert(chunk_idx == chunk_results.len); // Post-condition

        // Resolution rules (most permissive wins)
        if (string_count > 0) return .String;
        if (float_count > 0) return .Float64; // Float64 ⊃ Int64
        if (int_count > 0) return .Int64;
        if (bool_count > 0) return .Bool;

        // Default to String for safety
        return .String;
    }

    /// Cleanup chunks
    fn cleanupChunks(self: *ParallelCSVParser) void {
        std.debug.assert(self.chunks.len > 0); // Pre-condition

        // Chunks are owned by self.allocator
        self.allocator.free(self.chunks);
        self.chunks = &[_]Chunk{};
    }

    /// Cleanup inference results
    fn cleanupResults(self: *ParallelCSVParser, results: []ChunkInferenceResult) void {
        std.debug.assert(results.len > 0); // Pre-condition #1
        std.debug.assert(results.len == self.chunks.len); // Pre-condition #2

        var i: u32 = 0;
        const max_results: u32 = @min(@as(u32, @intCast(results.len)), MAX_THREADS * TARGET_CHUNKS_PER_THREAD);
        while (i < max_results) : (i += 1) {
            results[i].deinit(self.allocator);
        }

        std.debug.assert(i == results.len or i == max_results); // Post-condition

        self.allocator.free(results);
    }
};

// Tests
test "ParallelCSVParser.init determines correct thread count" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Small CSV → single thread
    const small_csv = "name,age\nAlice,30\n";
    var small_parser = try ParallelCSVParser.init(allocator, small_csv, .{});
    try testing.expectEqual(@as(u32, 1), small_parser.thread_count);

    // Large CSV → multiple threads
    const large_csv = try allocator.alloc(u8, MIN_CHUNK_SIZE * 4);
    defer allocator.free(large_csv);
    @memset(large_csv, 'x');

    var large_parser = try ParallelCSVParser.init(allocator, large_csv, .{});
    try testing.expect(large_parser.thread_count > 1);
    try testing.expect(large_parser.thread_count <= MAX_THREADS);
}

test "findChunkBoundary finds newline outside quotes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,bio\nAlice,\"Line 1\nLine 2\"\nBob,Simple\n";
    var parser = try ParallelCSVParser.init(allocator, csv, .{});

    // Find boundary after first row (should skip embedded newline in quotes)
    const boundary = try parser.findChunkBoundary(0, 30);

    // Should find the newline after "Line 2" (row boundary), not the one inside quotes
    try testing.expect(boundary > 0);
    try testing.expect(boundary < csv.len);

    // Verify it's at a valid row boundary
    const char_before = csv[boundary - 1];
    try testing.expect(char_before == '\n' or char_before == '\r');
}

test "mergeColumnType resolves type conflicts correctly" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "dummy\n";
    var parser = try ParallelCSVParser.init(allocator, csv, .{});

    // Create mock chunk results
    var result1 = try ChunkInferenceResult.init(allocator, 1);
    defer result1.deinit(allocator);
    result1.col_types[0] = .Int64;

    var result2 = try ChunkInferenceResult.init(allocator, 1);
    defer result2.deinit(allocator);
    result2.col_types[0] = .Float64;

    const results = [_]ChunkInferenceResult{ result1, result2 };

    // Int64 + Float64 → Float64 (more permissive)
    const merged_type = try parser.mergeColumnType(&results, 0);
    try testing.expectEqual(ValueType.Float64, merged_type);
}
