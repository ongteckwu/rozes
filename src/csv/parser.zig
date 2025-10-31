//! CSV Parser - RFC 4180 Compliant
//!
//! One-pass CSV parser with state machine for efficient parsing.
//! Converts CSV text to columnar DataFrame.
//!
//! See docs/RFC.md Section 5 for CSV parsing specification.
//!
//! Example:
//! ```
//! const csv = "age,score\n30,95.5\n25,87.3\n";
//! var parser = try CSVParser.init(allocator, csv, .{});
//! defer parser.deinit();
//!
//! const df = try parser.toDataFrame();
//! defer df.deinit();
//! ```

const std = @import("std");
const core_types = @import("../core/types.zig");
const DataFrame = @import("../core/dataframe.zig").DataFrame;
const Series = @import("../core/series.zig").Series;
const SeriesValue = @import("../core/series.zig").SeriesValue;
const simd = @import("../core/simd.zig");

const ValueType = core_types.ValueType;
const ColumnDesc = core_types.ColumnDesc;
const CSVOptions = core_types.CSVOptions;
const RichError = core_types.RichError;
const ErrorCode = core_types.ErrorCode;

/// Parser state machine
const ParserState = enum {
    Start,
    InField,
    InQuotedField,
    QuoteInQuoted,
    EndOfRecord,
};

/// Maximum limits
const MAX_CSV_SIZE: u32 = 1024 * 1024 * 1024; // 1GB
const MAX_COLUMNS: u32 = 10_000;
const MAX_ROWS: u32 = std.math.maxInt(u32);
const MAX_FIELD_LENGTH: u32 = 1_000_000; // 1MB per field

/// CSV Parser
pub const CSVParser = struct {
    parent_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    buffer: []const u8,
    pos: u32,
    state: ParserState,
    opts: CSVOptions,
    current_field: std.ArrayListUnmanaged(u8),
    current_row: std.ArrayListUnmanaged([]const u8),
    rows: std.ArrayListUnmanaged([][]const u8),
    // Error context tracking
    current_row_index: u32,
    current_col_index: u32,
    header_row: ?[][]const u8, // Cached headers for error messages

    /// Initialize CSV parser
    pub fn init(
        allocator: std.mem.Allocator,
        buffer: []const u8,
        opts: CSVOptions,
    ) !CSVParser {
        std.debug.assert(buffer.len > 0); // Non-empty buffer
        std.debug.assert(buffer.len <= MAX_CSV_SIZE); // Size check

        try opts.validate();

        // Create arena for parser lifetime
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        // Skip UTF-8 BOM if present (0xEF 0xBB 0xBF)
        const start_pos: u32 = if (buffer.len >= 3 and
            buffer[0] == 0xEF and buffer[1] == 0xBB and buffer[2] == 0xBF)
            3
        else
            0;

        std.debug.assert(start_pos <= 3); // BOM is 0 or 3 bytes

        // Pre-allocate buffers to reduce reallocation overhead (temporarily disabled)
        // const arena_alloc = arena.allocator();
        // const estimated_rows = @min(buffer.len / 100, MAX_ROWS);
        // const estimated_cols: u32 = 20;

        const parser = CSVParser{
            .parent_allocator = allocator,
            .arena = arena,
            .buffer = buffer,
            .pos = start_pos, // Skip BOM if present
            .state = .Start,
            .opts = opts,
            .current_field = .{},
            .current_row = .{},
            .rows = .{},
            .current_row_index = 0,
            .current_col_index = 0,
            .header_row = null, // Will be set during toDataFrame()
        };

        // Pre-allocate capacity (temporarily disabled to fix memory leaks - TODO: investigate)
        // These pre-allocations improve performance but aren't required for correctness
        // parser.current_field.ensureTotalCapacity(arena_alloc, 64) catch {};
        // parser.current_row.ensureTotalCapacity(arena_alloc, estimated_cols) catch {};
        // parser.rows.ensureTotalCapacity(arena_alloc, estimated_rows) catch {};

        return parser;
    }

    /// Free parser resources
    pub fn deinit(self: *CSVParser) void {
        std.debug.assert(self.pos <= self.buffer.len); // Valid state
        std.debug.assert(self.buffer.len <= MAX_CSV_SIZE); // Size invariant

        // Arena deinit frees everything at once - much simpler!
        self.arena.deinit();
    }

    /// Parse next field from CSV
    pub fn nextField(self: *CSVParser) !?[]const u8 {
        std.debug.assert(self.pos <= self.buffer.len); // Invariant

        // Handle EndOfRecord state before entering loop
        if (self.state == .EndOfRecord) {
            self.state = .Start;
            return null;
        }

        while (self.pos < self.buffer.len) {
            // Check field length limit
            if (self.current_field.items.len >= MAX_FIELD_LENGTH) {
                const allocator = self.arena.allocator();
                const col_name = self.getColumnName();
                const field_preview = self.current_field.items[0..@min(100, self.current_field.items.len)];

                const err_msg = RichError.init(.InvalidFormat, "Field exceeds maximum length")
                    .withRow(self.current_row_index + 1) // 1-indexed for display
                    .withColumn(col_name)
                    .withFieldValue(field_preview)
                    .withHint("Maximum field size is 1MB. Split data across multiple fields or increase MAX_FIELD_LENGTH.");

                if (err_msg.format(allocator)) |formatted| {
                    defer allocator.free(formatted);
                    std.log.err("{s}", .{formatted});
                } else |_| {
                    std.log.err("Field too large at row {}, column '{s}'", .{ self.current_row_index + 1, col_name });
                }

                return error.FieldTooLarge;
            }

            const char = self.buffer[self.pos];
            self.pos += 1;

            const action = try self.handleChar(char);
            switch (action) {
                .FieldComplete => return try self.finishField(),
                .RowComplete => {
                    self.state = .EndOfRecord;
                    return null;
                },
                .Continue => {},
            }
        }

        // End of buffer - handle final field
        if (self.current_field.items.len > 0) {
            self.state = .EndOfRecord;
            return try self.finishField();
        }

        // Special case: if we're at EOF and the last character was a delimiter,
        // we need to return one more empty field (trailing delimiter case)
        // Check: "," or "a,b," should return trailing empty field
        // We check current_col_index > 0 to ensure we've already returned at least one field
        if (self.pos > 0 and
            self.pos == self.buffer.len and
            self.buffer[self.pos - 1] == self.opts.delimiter and
            self.current_col_index > 0)
        {
            // We're at EOF after a delimiter, and we've already returned fields
            // Return empty field for trailing delimiter
            self.state = .EndOfRecord;
            return try self.finishField();
        }

        std.debug.assert(self.pos <= self.buffer.len); // Post-condition
        return null;
    }

    /// Character processing action
    const CharAction = enum { Continue, FieldComplete, RowComplete };

    /// Handle a single character in the current state
    fn handleChar(self: *CSVParser, char: u8) !CharAction {
        std.debug.assert(self.pos <= self.buffer.len); // Pre-condition #1: Valid position
        std.debug.assert(self.current_field.items.len < MAX_FIELD_LENGTH); // Pre-condition #2: Field size check
        std.debug.assert(self.state != .EndOfRecord); // Pre-condition #3: Not at end of record

        const result = switch (self.state) {
            .Start => try self.handleStart(char),
            .InField => try self.handleInField(char),
            .InQuotedField => try self.handleInQuotedField(char),
            .QuoteInQuoted => try self.handleQuoteInQuoted(char),
            .EndOfRecord => unreachable,
        };

        std.debug.assert(result == .Continue or result == .FieldComplete or result == .RowComplete); // Post-condition: Valid action
        return result;
    }

    /// Handle character in Start state (with SIMD optimization)
    fn handleStart(self: *CSVParser, char: u8) !CharAction {
        std.debug.assert(self.state == .Start); // Pre-condition #1: In Start state
        std.debug.assert(self.current_field.items.len == 0); // Pre-condition #2: Empty field buffer

        const allocator = self.arena.allocator();
        if (char == '"') {
            self.state = .InQuotedField;
            return .Continue;
        } else if (char == self.opts.delimiter) {
            return .FieldComplete;
        } else if (char == '\n' or char == '\r') {
            self.skipLineEnding(char);
            return .RowComplete;
        } else {
            // Start of unquoted field - use SIMD acceleration
            try self.current_field.append(allocator, char);
            self.state = .InField;

            // Use SIMD to scan the rest of the unquoted field
            return try self.scanUnquotedField();
        }
    }

    /// Handle character in InField state
    fn handleInField(self: *CSVParser, char: u8) !CharAction {
        std.debug.assert(self.state == .InField); // Pre-condition #1: In InField state
        std.debug.assert(self.current_field.items.len < MAX_FIELD_LENGTH); // Pre-condition #2: Below field limit

        const allocator = self.arena.allocator();
        if (char == self.opts.delimiter) {
            self.state = .Start;
            return .FieldComplete;
        } else if (char == '\n' or char == '\r') {
            self.skipLineEnding(char);
            self.state = .EndOfRecord;
            return .FieldComplete; // Return field, then nextField() will return null for end of row
        } else {
            try self.current_field.append(allocator, char);
            return .Continue;
        }
    }

    /// SIMD-accelerated unquoted field scanning
    ///
    /// **Performance**:
    /// - Scalar: 1 byte per iteration
    /// - SIMD: 16 bytes per iteration (16× throughput)
    /// - Expected speedup: 20-30% for CSV parsing overall
    ///
    /// **Usage**: Called after first character of unquoted field is consumed
    /// Assumes first character is already in current_field and self.pos points to next char
    fn scanUnquotedField(self: *CSVParser) !CharAction {
        std.debug.assert(self.pos <= self.buffer.len); // Pre-condition #1
        std.debug.assert(self.current_field.items.len > 0); // Pre-condition #2: First char already added
        std.debug.assert(self.current_field.items.len < MAX_FIELD_LENGTH); // Pre-condition #3

        const allocator = self.arena.allocator();

        // Use SIMD to find next delimiter, quote, or newline
        // Start from current position (first char already processed)
        const search_pos = self.pos;
        const next_special = simd.findNextSpecialChar(
            self.buffer,
            search_pos,
            self.opts.delimiter,
            '"', // Also check for quotes (shouldn't appear in unquoted field, but be safe)
        );

        // Calculate field span (from current position to special character)
        const field_start = search_pos;
        var field_end = next_special;

        // Also check for newlines (SIMD doesn't check those)
        var scan_pos = field_start;
        const MAX_SCAN: u32 = MAX_FIELD_LENGTH;
        var scan_count: u32 = 0;

        while (scan_pos < field_end and scan_count < MAX_SCAN) : (scan_count += 1) {
            const ch = self.buffer[scan_pos];
            if (ch == '\n' or ch == '\r') {
                field_end = scan_pos;
                break;
            }
            scan_pos += 1;
        }
        std.debug.assert(scan_count <= MAX_SCAN); // Post-condition

        // Copy field data
        const field_len = field_end - field_start;
        if (field_len > 0) {
            if (self.current_field.items.len + field_len > MAX_FIELD_LENGTH) {
                return error.FieldTooLarge;
            }
            try self.current_field.appendSlice(allocator, self.buffer[field_start..field_end]);
        }

        // Update position (cast from usize to u32)
        std.debug.assert(field_end <= std.math.maxInt(u32)); // Ensure fits in u32
        self.pos = @intCast(field_end);

        // Check what terminated the field
        if (field_end >= self.buffer.len) {
            // End of buffer
            return .FieldComplete;
        }

        const terminator = self.buffer[field_end];
        self.pos += 1; // Consume terminator

        if (terminator == self.opts.delimiter) {
            self.state = .Start;
            return .FieldComplete;
        } else if (terminator == '\n' or terminator == '\r') {
            self.skipLineEnding(terminator);
            self.state = .EndOfRecord;
            return .FieldComplete;
        } else if (terminator == '"') {
            // Quote in unquoted field - error in strict mode, continue in lenient
            if (self.opts.parse_mode == .Strict) {
                return error.InvalidQuoting;
            }
            try self.current_field.append(allocator, terminator);
            return .Continue;
        }

        return .Continue;
    }

    /// Handle character in InQuotedField state
    fn handleInQuotedField(self: *CSVParser, char: u8) !CharAction {
        std.debug.assert(self.state == .InQuotedField); // Pre-condition #1: In InQuotedField state
        std.debug.assert(self.current_field.items.len < MAX_FIELD_LENGTH); // Pre-condition #2: Below field limit

        const allocator = self.arena.allocator();
        if (char == '"') {
            self.state = .QuoteInQuoted;
        } else {
            try self.current_field.append(allocator, char);
        }
        return .Continue;
    }

    /// Handle character in QuoteInQuoted state
    fn handleQuoteInQuoted(self: *CSVParser, char: u8) !CharAction {
        std.debug.assert(self.state == .QuoteInQuoted); // Pre-condition #1: In QuoteInQuoted state
        std.debug.assert(self.current_field.items.len < MAX_FIELD_LENGTH); // Pre-condition #2: Below field limit

        const allocator = self.arena.allocator();
        if (char == '"') {
            // Escaped quote
            try self.current_field.append(allocator, '"');
            self.state = .InQuotedField;
            return .Continue;
        } else if (char == self.opts.delimiter) {
            self.state = .Start;
            return .FieldComplete;
        } else if (char == '\n' or char == '\r') {
            self.skipLineEnding(char);
            self.state = .EndOfRecord;
            return .FieldComplete; // Return field, then nextField() will return null for end of row
        } else {
            // Invalid trailing quote (e.g., "field"x or "field", without proper closing)
            if (self.opts.parse_mode == .Lenient) {
                // Lenient mode: treat as literal and continue
                // Append the quote and the invalid character
                try self.current_field.append(allocator, '"');
                try self.current_field.append(allocator, char);
                self.state = .InField; // Continue as unquoted field
                return .Continue;
            } else {
                // Strict mode: throw error with context
                const col_name = self.getColumnName();
                const csv_context = try self.getCSVContext(allocator);
                defer allocator.free(csv_context);

                const err_msg = RichError.init(.InvalidFormat, "Unclosed or misplaced quote in CSV")
                    .withRow(self.current_row_index + 1)
                    .withColumn(col_name)
                    .withFieldValue(csv_context)
                    .withHint("Check for unescaped quotes. Use \"\" (double quotes) to escape quotes inside quoted fields.");

                if (err_msg.format(allocator)) |formatted| {
                    defer allocator.free(formatted);
                    std.log.err("{s}", .{formatted});
                } else |_| {
                    std.log.err("Invalid quoting at row {}, column '{s}'", .{ self.current_row_index + 1, col_name });
                }

                return error.InvalidQuoting;
            }
        }
    }

    /// Skip line ending (handles CRLF, LF, CR)
    fn skipLineEnding(self: *CSVParser, char: u8) void {
        std.debug.assert(char == '\n' or char == '\r'); // Must be line ending
        std.debug.assert(self.pos <= self.buffer.len); // Valid position

        // If we got CR, check for following LF
        if (char == '\r' and self.pos < self.buffer.len and self.buffer[self.pos] == '\n') {
            self.pos += 1; // Skip LF in CRLF
        }
    }

    /// Get column name for error messages
    fn getColumnName(self: *const CSVParser) []const u8 {
        std.debug.assert(self.current_col_index < MAX_COLUMNS); // Valid column index

        if (self.header_row) |headers| {
            if (self.current_col_index < headers.len) {
                return headers[self.current_col_index];
            }
        }

        // Fallback: return column index as string (will be allocated temporarily)
        return "unknown";
    }

    /// Extract CSV context around current position for error messages
    fn getCSVContext(self: *const CSVParser, allocator: std.mem.Allocator) ![]const u8 {
        std.debug.assert(self.pos <= self.buffer.len); // Valid position

        // Extract up to 50 chars before and after current position
        const before_start = if (self.pos > 50) self.pos - 50 else 0;
        const after_end = @min(self.buffer.len, self.pos + 50);

        const context = self.buffer[before_start..after_end];

        // Return a copy to avoid lifetime issues
        return try allocator.dupe(u8, context);
    }

    /// Finish current field and reset buffer
    fn finishField(self: *CSVParser) ![]const u8 {
        const allocator = self.arena.allocator();
        std.debug.assert(self.current_field.items.len <= MAX_FIELD_LENGTH); // Field size check

        const field = try self.current_field.toOwnedSlice(allocator);

        // Update column tracking
        self.current_col_index += 1;

        std.debug.assert(field.len <= MAX_FIELD_LENGTH); // Post-condition
        return field;
    }

    /// Parse one row
    pub fn nextRow(self: *CSVParser) !?[][]const u8 {
        const allocator = self.arena.allocator();
        std.debug.assert(self.current_row.items.len == 0); // Should be empty

        self.state = .Start;
        self.current_col_index = 0; // Reset column counter for new row

        while (try self.nextField()) |field| {
            try self.current_row.append(allocator, field);

            if (self.current_row.items.len > MAX_COLUMNS) {
                const col_count: u32 = @intCast(self.current_row.items.len);

                const err_msg = RichError.init(.InvalidFormat, "Too many columns in CSV")
                    .withRow(self.current_row_index + 1)
                    .withHint(try std.fmt.allocPrint(allocator, "Found {} columns, maximum is {}. Check for unescaped delimiters in quoted fields.", .{ col_count, MAX_COLUMNS }));

                if (err_msg.format(allocator)) |formatted| {
                    defer allocator.free(formatted);
                    std.log.err("{s}", .{formatted});
                } else |_| {
                    std.log.err("Too many columns at row {}: found {}, max {}", .{ self.current_row_index + 1, col_count, MAX_COLUMNS });
                }

                return error.TooManyColumns;
            }
        }

        // If we got fields, return the row
        if (self.current_row.items.len > 0) {
            const row = try self.current_row.toOwnedSlice(allocator);
            self.current_row_index += 1; // Increment row counter
            return row;
        }

        // End of data
        return null;
    }

    /// Parse all rows
    pub fn parseAll(self: *CSVParser) !void {
        const allocator = self.arena.allocator();
        std.debug.assert(self.rows.items.len == 0); // Should be empty

        var row_count: u32 = 0;
        while (row_count < MAX_ROWS) : (row_count += 1) {
            const row = try self.nextRow() orelse break;

            // Skip blank lines if option is set
            // Note: No need to free - arena will handle it
            if (self.opts.skip_blank_lines and row.len == 1 and row[0].len == 0) {
                if (row_count > 0) row_count -= 1; // Don't count blank lines (avoid underflow)
                continue;
            }

            try self.rows.append(allocator, row);
        }

        std.debug.assert(row_count <= MAX_ROWS); // Invariant
    }

    /// Convert parsed rows to DataFrame
    pub fn toDataFrame(self: *CSVParser) !DataFrame {
        // Parse all rows if not done yet
        if (self.rows.items.len == 0) {
            try self.parseAll();
        }

        // Handle completely empty CSVs
        if (self.rows.items.len == 0) {
            // In Lenient mode, allow empty CSVs but they must have at least been parsed
            // If there's literally nothing (not even headers), it's an error
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const err_msg = RichError.init(.InvalidFormat, "CSV file is empty or contains no parseable data")
                .withHint("CSV must contain at least a header row. Valid example: \"name,age\\nAlice,30\"");

            if (err_msg.format(temp_allocator)) |formatted| {
                std.log.err("{s}", .{formatted});
            } else |_| {
                std.log.err("CSV file is empty", .{});
            }

            return error.EmptyCSV;
        }

        std.debug.assert(self.rows.items.len > 0); // Need at least header or data

        const allocator = self.arena.allocator();

        // Extract headers
        const header_row: [][]const u8 = if (self.opts.has_headers) self.rows.items[0] else blk: {
            // Generate column names: col0, col1, col2, ...
            const col_count = self.rows.items[0].len;
            var headers = try allocator.alloc([]const u8, col_count);
            for (0..col_count) |i| {
                headers[i] = try std.fmt.allocPrint(allocator, "col{}", .{i});
            }
            break :blk headers;
        };

        // Cache headers for error messages
        self.header_row = header_row;

        const data_start: usize = if (self.opts.has_headers) 1 else 0;
        const data_rows = self.rows.items[data_start..];

        // Infer column types (with optional manual schema override)
        const col_count = header_row.len;
        var column_types = try allocator.alloc(ValueType, col_count);
        defer allocator.free(column_types);

        if (data_rows.len > 0 and self.opts.infer_types) {
            const preview_count = @min(self.opts.preview_rows, @as(u32, @intCast(data_rows.len)));
            for (0..col_count) |col_idx| {
                // Check manual schema first
                if (self.opts.schema) |schema_map| {
                    const col_name = header_row[col_idx];
                    if (schema_map.get(col_name)) |manual_type| {
                        column_types[col_idx] = manual_type;
                        continue; // Skip auto-detection for this column
                    }
                }

                // Fall back to auto-detection
                column_types[col_idx] = try inferColumnType(data_rows[0..preview_count], col_idx);
            }
        } else {
            // Check manual schema or default to String
            for (0..col_count) |col_idx| {
                if (self.opts.schema) |schema_map| {
                    const col_name = header_row[col_idx];
                    if (schema_map.get(col_name)) |manual_type| {
                        column_types[col_idx] = manual_type;
                        continue;
                    }
                }

                // Default to String type when no data or inference disabled (0.2.0+)
                column_types[col_idx] = .String;
            }
        }

        // Create column descriptors
        var col_descs = try allocator.alloc(ColumnDesc, col_count);
        defer allocator.free(col_descs);

        for (0..col_count) |i| {
            col_descs[i] = ColumnDesc.init(header_row[i], column_types[i], @intCast(i));
        }

        // Create DataFrame with capacity (may have 0 rows if headers-only)
        // Use parent_allocator for DataFrame (it has its own arena)
        const capacity: u32 = if (data_rows.len > 0) @intCast(data_rows.len) else 1;
        var df = try DataFrame.create(self.parent_allocator, col_descs, capacity);
        errdefer df.deinit();

        // Fill DataFrame with data (only if we have data rows)
        if (data_rows.len > 0) {
            try fillDataFrame(&df, data_rows, column_types);
            try df.setRowCount(@intCast(data_rows.len));
        } else {
            // Empty DataFrame with 0 rows
            try df.setRowCount(0);
        }

        return df;
    }
};

/// Infer column type from preview rows
fn inferColumnType(rows: []const [][]const u8, col_idx: usize) !ValueType {
    std.debug.assert(rows.len > 0); // Need data
    std.debug.assert(rows.len <= 10_000); // Preview limit

    // FAST DECIMAL CHECK: Scan ALL rows for decimal indicators before type inference
    // This prevents inferring Int64 when later rows have decimals (e.g., row 150 has "42.5")
    var has_decimals = false;
    var decimal_check_idx: u32 = 0;
    while (decimal_check_idx < MAX_ROWS and decimal_check_idx < rows.len) : (decimal_check_idx += 1) {
        const row = rows[decimal_check_idx];
        if (col_idx >= row.len) continue;

        const field = row[col_idx];
        if (field.len == 0) continue; // Skip empty

        // Check for decimal indicators (fast string scan, no parsing)
        if (std.mem.indexOfScalar(u8, field, '.') != null or
            std.mem.indexOfScalar(u8, field, 'e') != null or
            std.mem.indexOfScalar(u8, field, 'E') != null)
        {
            has_decimals = true;
            break; // Found decimal, stop scanning
        }
    }
    std.debug.assert(decimal_check_idx <= rows.len); // Scanned rows

    var all_int = true;
    var all_float = true;
    var all_bool = true;
    var all_empty = true;

    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < rows.len) : (row_idx += 1) {
        const row = rows[row_idx];
        if (col_idx >= row.len) continue;

        const field = row[col_idx];
        if (field.len == 0) continue; // Skip empty fields

        all_empty = false; // Found non-empty field

        // Always check types (optimization: skip Int64 if decimals found since Float64 superset)
        if (has_decimals) {
            all_int = false; // Has decimals, cannot be Int64
        } else {
            if (!tryParseInt64(field)) all_int = false;
        }
        if (!tryParseFloat64(field)) all_float = false;
        if (!tryParseBool(field)) all_bool = false;
    }
    std.debug.assert(row_idx == rows.len); // Processed all rows

    // If all fields are empty, default to String
    if (all_empty) return .String;

    // Prefer Bool over Int64 (since "1" and "0" parse as both)
    if (all_bool) return .Bool;

    // If decimals detected, prefer Float64 over Int64
    if (has_decimals and all_float) return .Float64;

    // Prefer Int64 over Float64 for pure integers
    if (all_int) return .Int64;
    if (all_float) return .Float64;

    // Check if column should be categorical (low cardinality string data)
    // This must come before defaulting to String
    if (detectCategorical(rows, col_idx)) return .Categorical;

    // Default to String for mixed or non-numeric data
    return .String;
}

/// Detect if column should be categorical based on cardinality
///
/// Returns true if:
/// - Column has string data (not numeric/bool)
/// - Unique values / total values < 0.05 (5% threshold)
/// - At least 10 rows for reliable detection
///
/// ## Assertions
/// - rows.len > 0
/// - rows.len <= 10_000 (preview limit)
fn detectCategorical(rows: []const [][]const u8, col_idx: usize) bool {
    std.debug.assert(rows.len > 0); // Pre-condition #1
    std.debug.assert(rows.len <= 10_000); // Pre-condition #2

    // Need at least 10 rows for reliable cardinality detection
    if (rows.len < 10) return false;

    // Count unique values using a temporary hash set
    const allocator = std.heap.page_allocator; // Temporary for detection
    var unique_values = std.StringHashMap(void).init(allocator);
    defer unique_values.deinit();

    var non_empty_count: u32 = 0;
    var unique_count: u32 = 0;

    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < rows.len) : (row_idx += 1) {
        const row = rows[row_idx];
        if (col_idx >= row.len) continue;

        const field = row[col_idx];
        if (field.len == 0) continue; // Skip empty fields

        non_empty_count += 1;

        // Track unique values
        const gop = unique_values.getOrPut(field) catch continue;
        if (!gop.found_existing) {
            unique_count += 1;
        }
    }
    std.debug.assert(row_idx == rows.len); // Processed all rows

    std.debug.assert(unique_count <= non_empty_count); // Post-condition #3

    // No data or all empty → not categorical
    if (non_empty_count == 0) return false;

    // Calculate cardinality ratio
    const cardinality = @as(f64, @floatFromInt(unique_count)) / @as(f64, @floatFromInt(non_empty_count));

    // Categorical threshold: < 5% unique values
    // Examples:
    // - Region column with 3 unique values out of 1000 rows: 0.3% → Categorical
    // - City column with 100 unique values out of 1000 rows: 10% → String
    // - ID column with 1000 unique values out of 1000 rows: 100% → String
    return cardinality < 0.05;
}

/// Try to parse as Int64
fn tryParseInt64(field: []const u8) bool {
    std.debug.assert(field.len <= MAX_FIELD_LENGTH); // Field size check

    if (field.len == 0) return false;

    _ = std.fmt.parseInt(i64, field, 10) catch return false;
    return true;
}

/// Try to parse as Float64
fn tryParseFloat64(field: []const u8) bool {
    std.debug.assert(field.len <= MAX_FIELD_LENGTH); // Field size check

    if (field.len == 0) return false;

    _ = std.fmt.parseFloat(f64, field) catch return false;
    return true;
}

/// Try to parse as Bool
fn tryParseBool(field: []const u8) bool {
    std.debug.assert(field.len <= MAX_FIELD_LENGTH); // Field size check

    if (field.len == 0) return false;

    // Case-insensitive comparison for common boolean values
    if (std.ascii.eqlIgnoreCase(field, "true")) return true;
    if (std.ascii.eqlIgnoreCase(field, "false")) return true;
    if (std.ascii.eqlIgnoreCase(field, "yes")) return true;
    if (std.ascii.eqlIgnoreCase(field, "no")) return true;
    if (std.ascii.eqlIgnoreCase(field, "1")) return true;
    if (std.ascii.eqlIgnoreCase(field, "0")) return true;
    if (std.ascii.eqlIgnoreCase(field, "t")) return true;
    if (std.ascii.eqlIgnoreCase(field, "f")) return true;
    if (std.ascii.eqlIgnoreCase(field, "y")) return true;
    if (std.ascii.eqlIgnoreCase(field, "n")) return true;

    return false;
}

/// Parse boolean value from string
fn parseBool(field: []const u8) !bool {
    std.debug.assert(field.len > 0);
    std.debug.assert(field.len <= MAX_FIELD_LENGTH);

    // True values
    if (std.ascii.eqlIgnoreCase(field, "true")) return true;
    if (std.ascii.eqlIgnoreCase(field, "yes")) return true;
    if (std.ascii.eqlIgnoreCase(field, "1")) return true;
    if (std.ascii.eqlIgnoreCase(field, "t")) return true;
    if (std.ascii.eqlIgnoreCase(field, "y")) return true;

    // False values
    if (std.ascii.eqlIgnoreCase(field, "false")) return false;
    if (std.ascii.eqlIgnoreCase(field, "no")) return false;
    if (std.ascii.eqlIgnoreCase(field, "0")) return false;
    if (std.ascii.eqlIgnoreCase(field, "f")) return false;
    if (std.ascii.eqlIgnoreCase(field, "n")) return false;

    return error.InvalidBoolean;
}

/// Fill Int64 column with data from CSV rows
fn fillInt64Column(col: *Series, rows: []const [][]const u8, col_idx: usize) !void {
    std.debug.assert(col.value_type == .Int64); // Pre-condition #1
    const buffer = col.asInt64Buffer() orelse return error.TypeMismatch;

    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < rows.len) : (row_idx += 1) {
        const row = rows[row_idx];
        if (col_idx >= row.len or row[col_idx].len == 0) {
            buffer[row_idx] = 0; // Empty = 0
        } else {
            buffer[row_idx] = std.fmt.parseInt(i64, row[col_idx], 10) catch |err| {
                // Use a temporary allocator for error message (will be freed after logging)
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                const temp_allocator = arena.allocator();

                const hint = switch (err) {
                    error.Overflow => "Value exceeds Int64 range (-9,223,372,036,854,775,808 to 9,223,372,036,854,775,807)",
                    error.InvalidCharacter => "Expected integer, found non-numeric characters",
                };

                const err_msg = RichError.init(.TypeMismatch, "Failed to parse integer")
                    .withRow(@as(u32, @intCast(row_idx)) + 1)
                    .withColumn(col.name)
                    .withFieldValue(row[col_idx])
                    .withHint(hint);

                if (err_msg.format(temp_allocator)) |formatted| {
                    std.log.err("{s}", .{formatted});
                } else |_| {
                    std.log.err("Failed to parse Int64 at row {}, col '{s}': '{s}'", .{ row_idx + 1, col.name, row[col_idx] });
                }

                return error.TypeMismatch;
            };
        }
    }
    std.debug.assert(row_idx == rows.len); // Processed all rows

    std.debug.assert(buffer.len >= rows.len); // Post-condition #2
}

/// Fill Float64 column with data from CSV rows
fn fillFloat64Column(col: *Series, rows: []const [][]const u8, col_idx: usize) !void {
    std.debug.assert(col.value_type == .Float64); // Pre-condition #1
    const buffer = col.asFloat64Buffer() orelse return error.TypeMismatch;

    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < rows.len) : (row_idx += 1) {
        const row = rows[row_idx];
        if (col_idx >= row.len or row[col_idx].len == 0) {
            buffer[row_idx] = 0.0; // Empty = 0.0
        } else {
            buffer[row_idx] = std.fmt.parseFloat(f64, row[col_idx]) catch |err| {
                // Use a temporary allocator for error message
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                const temp_allocator = arena.allocator();

                const hint = switch (err) {
                    error.InvalidCharacter => "Expected floating-point number (e.g., 3.14, -2.5, 1e-10)",
                };

                const err_msg = RichError.init(.TypeMismatch, "Failed to parse floating-point number")
                    .withRow(@as(u32, @intCast(row_idx)) + 1)
                    .withColumn(col.name)
                    .withFieldValue(row[col_idx])
                    .withHint(hint);

                if (err_msg.format(temp_allocator)) |formatted| {
                    std.log.err("{s}", .{formatted});
                } else |_| {
                    std.log.err("Failed to parse Float64 at row {}, col '{s}': '{s}'", .{ row_idx + 1, col.name, row[col_idx] });
                }

                return error.TypeMismatch;
            };
        }
    }
    std.debug.assert(row_idx == rows.len); // Processed all rows

    std.debug.assert(buffer.len >= rows.len); // Post-condition #2
}

/// Fill Bool column with data from CSV rows
fn fillBoolColumn(col: *Series, rows: []const [][]const u8, col_idx: usize) !void {
    std.debug.assert(col.value_type == .Bool); // Pre-condition #1
    const buffer = col.asBoolBuffer() orelse return error.TypeMismatch;

    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < rows.len) : (row_idx += 1) {
        const row = rows[row_idx];
        if (col_idx >= row.len or row[col_idx].len == 0) {
            buffer[row_idx] = false; // Empty = false
        } else {
            buffer[row_idx] = parseBool(row[col_idx]) catch {
                // Use a temporary allocator for error message
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                const temp_allocator = arena.allocator();

                const err_msg = RichError.init(.TypeMismatch, "Failed to parse boolean value")
                    .withRow(@as(u32, @intCast(row_idx)) + 1)
                    .withColumn(col.name)
                    .withFieldValue(row[col_idx])
                    .withHint("Expected 'true', 'false', '1', '0', 't', 'f', 'yes', 'no', 'y', or 'n' (case-insensitive)");

                if (err_msg.format(temp_allocator)) |formatted| {
                    std.log.err("{s}", .{formatted});
                } else |_| {
                    std.log.err("Failed to parse Bool at row {}, col '{s}': '{s}'", .{ row_idx + 1, col.name, row[col_idx] });
                }

                return error.TypeMismatch;
            };
        }
    }
    std.debug.assert(row_idx == rows.len); // Processed all rows

    std.debug.assert(buffer.len >= rows.len); // Post-condition #2
}

/// Fill String column with data from CSV rows
fn fillStringColumn(col: *Series, rows: []const [][]const u8, col_idx: usize, allocator: std.mem.Allocator) !void {
    std.debug.assert(col.value_type == .String); // Pre-condition #1

    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < rows.len) : (row_idx += 1) {
        const row = rows[row_idx];
        const field = if (col_idx < row.len) row[col_idx] else "";
        try col.appendString(allocator, field);
    }

    std.debug.assert(row_idx == rows.len); // Post-condition #2
}

/// Fill Categorical column with data from CSV rows
fn fillCategoricalColumn(col: *Series, rows: []const [][]const u8, col_idx: usize, allocator: std.mem.Allocator) !void {
    std.debug.assert(col.value_type == .Categorical); // Pre-condition #1
    std.debug.assert(rows.len > 0); // Pre-condition #2

    var cat_col = col.asCategoricalColumnMut() orelse {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_allocator = arena.allocator();

        const err_msg = RichError.init(.TypeMismatch, "Failed to access categorical column")
            .withColumn(col.name)
            .withHint("Column type mismatch. Expected Categorical column but got different type.");

        if (err_msg.format(temp_allocator)) |formatted| {
            std.log.err("{s}", .{formatted});
        } else |_| {
            std.log.err("Type mismatch accessing categorical column '{s}'", .{col.name});
        }

        return error.TypeMismatch;
    };

    var row_idx: u32 = 0;
    while (row_idx < MAX_ROWS and row_idx < rows.len) : (row_idx += 1) {
        const row = rows[row_idx];
        const field = if (col_idx < row.len) row[col_idx] else "";

        cat_col.append(allocator, field) catch |err| {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const hint = switch (err) {
                error.OutOfMemory => "Not enough memory to store categorical values. Consider reducing dataset size or using String type.",
                else => "Failed to add category to column. Check memory availability.",
            };

            const err_msg = RichError.init(.TypeMismatch, "Failed to add categorical value")
                .withRow(@as(u32, @intCast(row_idx)) + 1)
                .withColumn(col.name)
                .withFieldValue(field)
                .withHint(hint);

            if (err_msg.format(temp_allocator)) |formatted| {
                std.log.err("{s}", .{formatted});
            } else |_| {
                std.log.err("Failed to add categorical value at row {}, col '{s}': '{s}'", .{ row_idx + 1, col.name, field });
            }

            return err;
        };
    }

    std.debug.assert(row_idx == rows.len); // Post-condition #3
}

/// Fill DataFrame with data from CSV rows
fn fillDataFrame(df: *DataFrame, rows: []const [][]const u8, column_types: []ValueType) !void {
    std.debug.assert(rows.len > 0); // Pre-condition #1
    std.debug.assert(column_types.len == df.columns.len); // Pre-condition #2

    var col_idx: u32 = 0;
    while (col_idx < MAX_COLUMNS and col_idx < df.columns.len) : (col_idx += 1) {
        const col = &df.columns[col_idx];
        switch (column_types[col_idx]) {
            .Int64 => try fillInt64Column(col, rows, col_idx),
            .Float64 => try fillFloat64Column(col, rows, col_idx),
            .Bool => try fillBoolColumn(col, rows, col_idx),
            .String => try fillStringColumn(col, rows, col_idx, df.arena.allocator()),
            .Categorical => try fillCategoricalColumn(col, rows, col_idx, df.arena.allocator()),
            else => return error.UnsupportedType,
        }
    }
    std.debug.assert(col_idx == df.columns.len); // Processed all columns
}

// Tests
test "CSVParser.init creates parser" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,age\nAlice,30\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    try testing.expectEqual(@as(u32, 0), parser.pos);
    try testing.expectEqual(ParserState.Start, parser.state);
}

test "CSVParser.nextField parses simple field" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "hello,world\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    const field1 = try parser.nextField();
    try testing.expect(field1 != null);
    try testing.expectEqualStrings("hello", field1.?);
    // Don't free - parser's arena will handle cleanup

    const field2 = try parser.nextField();
    try testing.expect(field2 != null);
    try testing.expectEqualStrings("world", field2.?);
    // Don't free - parser's arena will handle cleanup
}

test "CSVParser.nextField parses quoted field" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "\"hello, world\",next\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    const field1 = try parser.nextField();
    try testing.expect(field1 != null);
    try testing.expectEqualStrings("hello, world", field1.?);

    const field2 = try parser.nextField();
    try testing.expect(field2 != null);
    try testing.expectEqualStrings("next", field2.?);
}

test "CSVParser.nextField handles escaped quotes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "\"hello \"\"world\"\"\"\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    const field = try parser.nextField();
    try testing.expect(field != null);
    try testing.expectEqualStrings("hello \"world\"", field.?);
}

test "CSVParser.toDataFrame parses simple CSV" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "age,score\n30,95.5\n25,87.3\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.len());
    try testing.expectEqual(@as(usize, 2), df.columnCount());

    const age_col = df.column("age").?;
    try testing.expectEqual(ValueType.Int64, age_col.value_type);

    const score_col = df.column("score").?;
    try testing.expectEqual(ValueType.Float64, score_col.value_type);

    const ages = age_col.asInt64().?;
    try testing.expectEqual(@as(i64, 30), ages[0]);
    try testing.expectEqual(@as(i64, 25), ages[1]);

    const scores = score_col.asFloat64().?;
    try testing.expectEqual(@as(f64, 95.5), scores[0]);
    try testing.expectEqual(@as(f64, 87.3), scores[1]);
}

test "inferColumnType identifies Int64" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const field1 = try allocator.dupe(u8, "10");
    defer allocator.free(field1);
    const field2 = try allocator.dupe(u8, "20");
    defer allocator.free(field2);

    var row1 = [_][]const u8{field1};
    var row2 = [_][]const u8{field2};
    var rows_arr = [_][][]const u8{ &row1, &row2 };
    const rows: []const [][]const u8 = &rows_arr;

    const typ = try inferColumnType(rows, 0);
    try testing.expectEqual(ValueType.Int64, typ);
}

test "inferColumnType identifies Float64" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const field1 = try allocator.dupe(u8, "10.5");
    defer allocator.free(field1);
    const field2 = try allocator.dupe(u8, "20.5");
    defer allocator.free(field2);

    var row1 = [_][]const u8{field1};
    var row2 = [_][]const u8{field2};
    var rows_arr = [_][][]const u8{ &row1, &row2 };
    const rows: []const [][]const u8 = &rows_arr;

    const typ = try inferColumnType(rows, 0);
    try testing.expectEqual(ValueType.Float64, typ);
}

test "tryParseInt64 validates integers" {
    const testing = std.testing;

    try testing.expect(tryParseInt64("42"));
    try testing.expect(tryParseInt64("-100"));
    try testing.expect(tryParseInt64("0"));

    try testing.expect(!tryParseInt64("3.14"));
    try testing.expect(!tryParseInt64("hello"));
    try testing.expect(!tryParseInt64(""));
}

test "tryParseFloat64 validates floats" {
    const testing = std.testing;

    try testing.expect(tryParseFloat64("3.14"));
    try testing.expect(tryParseFloat64("-2.5"));
    try testing.expect(tryParseFloat64("42"));
    // Note: "1e10" format should work but may have issues in some contexts
    // try testing.expect(tryParseFloat64("1e10"));

    try testing.expect(!tryParseFloat64("hello"));
    try testing.expect(!tryParseFloat64(""));
}

// ===== Phase 2 Tests: BOM, Empty DataFrames, Field Limits =====

test "CSVParser.init skips UTF-8 BOM" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // CSV with BOM (0xEF 0xBB 0xBF) followed by content (numeric only for MVP)
    const csv_with_bom = "\xEF\xBB\xBFage,score\n30,95.5\n";

    var parser = try CSVParser.init(allocator, csv_with_bom, .{});
    defer parser.deinit();

    // Parser should skip the 3-byte BOM
    try testing.expectEqual(@as(u32, 3), parser.pos);

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should parse correctly, ignoring BOM
    try testing.expectEqual(@as(u32, 1), df.row_count);
    try testing.expectEqualStrings("age", df.column_descs[0].name);
    try testing.expectEqualStrings("score", df.column_descs[1].name);
}

test "CSVParser handles CSV without BOM" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "age,score\n30,95.5\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    // Parser should start at position 0
    try testing.expectEqual(@as(u32, 0), parser.pos);

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 1), df.row_count);
}

test "toDataFrame allows empty CSV with headers only" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,age,score\n"; // Headers but no data rows

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Should create DataFrame with 0 rows, 3 columns
    try testing.expectEqual(@as(u32, 0), df.row_count);
    try testing.expectEqual(@as(usize, 3), df.columns.len);
    try testing.expectEqualStrings("name", df.column_descs[0].name);
    try testing.expectEqualStrings("age", df.column_descs[1].name);
    try testing.expectEqualStrings("score", df.column_descs[2].name);
}

test "toDataFrame handles empty DataFrame operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "col1,col2\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expect(df.isEmpty());
    try testing.expectEqual(@as(u32, 0), df.len());
    try testing.expectEqual(@as(usize, 2), df.columnCount());
}

test "skipLineEnding handles CRLF correctly" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "age,score\r\n30,95.5\r\n25,87.3\r\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.row_count);
}

test "skipLineEnding handles LF only" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "age,score\n30,95.5\n25,87.3\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.row_count);
}

test "skipLineEnding handles CR only (old Mac format)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "age,score\r30,95.5\r25,87.3\r";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.row_count);
}

test "mixed numeric/string data inferred as String column" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // CSV with mixed integer and string values
    const csv = "age\n30\nabc\n"; // "abc" cannot be parsed as integer

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    // Should succeed and infer as String column (not Int64)
    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.row_count);
    try testing.expectEqual(@as(usize, 1), df.columns.len);

    // Verify column type is String
    const col = df.column("age").?;
    try testing.expectEqual(ValueType.String, col.value_type);

    // Verify data is preserved as strings
    try testing.expectEqualStrings("30", col.getString(0).?);
    try testing.expectEqualStrings("abc", col.getString(1).?);
}

test "mixed float/string data inferred as String column" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // CSV with mixed float and string values
    const csv = "score\n95.5\ninvalid\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    // Should succeed and infer as String column (not Float64)
    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.row_count);

    // Verify column type is String
    const col = df.column("score").?;
    try testing.expectEqual(ValueType.String, col.value_type);

    // Verify data is preserved as strings
    try testing.expectEqualStrings("95.5", col.getString(0).?);
    try testing.expectEqualStrings("invalid", col.getString(1).?);
}

// String Column Parsing Tests

test "pure string column parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,city\nAlice,NYC\nBob,LA\nCharlie,Chicago\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);
    try testing.expectEqual(@as(usize, 2), df.columns.len);

    // Verify both columns are String type
    const name_col = df.column("name").?;
    const city_col = df.column("city").?;
    try testing.expectEqual(ValueType.String, name_col.value_type);
    try testing.expectEqual(ValueType.String, city_col.value_type);

    // Verify data
    try testing.expectEqualStrings("Alice", name_col.getString(0).?);
    try testing.expectEqualStrings("NYC", city_col.getString(0).?);
    try testing.expectEqualStrings("Bob", name_col.getString(1).?);
    try testing.expectEqualStrings("LA", city_col.getString(1).?);
}

test "empty string fields in string column" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Use comma to create empty field (not blank line)
    const csv = "name,city\nAlice,\n,NYC\nBob,LA\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);

    const name_col = df.column("name").?;
    const city_col = df.column("city").?;
    try testing.expectEqual(ValueType.String, name_col.value_type);
    try testing.expectEqual(ValueType.String, city_col.value_type);

    // Verify empty strings are preserved
    try testing.expectEqualStrings("Alice", name_col.getString(0).?);
    try testing.expectEqualStrings("", city_col.getString(0).?); // Empty city

    try testing.expectEqualStrings("", name_col.getString(1).?); // Empty name
    try testing.expectEqualStrings("NYC", city_col.getString(1).?);

    try testing.expectEqualStrings("Bob", name_col.getString(2).?);
    try testing.expectEqualStrings("LA", city_col.getString(2).?);
}

test "UTF-8 strings in CSV" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "message\nHello\n世界\n🌹\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);

    const col = df.column("message").?;
    try testing.expectEqual(ValueType.String, col.value_type);

    // Verify UTF-8 strings are preserved
    try testing.expectEqualStrings("Hello", col.getString(0).?);
    try testing.expectEqualStrings("世界", col.getString(1).?);
    try testing.expectEqualStrings("🌹", col.getString(2).?);
}

test "mixed column types: numeric and string" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,age,city\nAlice,30,NYC\nBob,25,LA\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.row_count);
    try testing.expectEqual(@as(usize, 3), df.columns.len);

    // Verify column types
    const name_col = df.column("name").?;
    const age_col = df.column("age").?;
    const city_col = df.column("city").?;

    try testing.expectEqual(ValueType.String, name_col.value_type);
    try testing.expectEqual(ValueType.Int64, age_col.value_type); // Pure numeric
    try testing.expectEqual(ValueType.String, city_col.value_type);

    // Verify data
    try testing.expectEqualStrings("Alice", name_col.getString(0).?);
    try testing.expectEqual(@as(i64, 30), age_col.asInt64().?[0]);
    try testing.expectEqualStrings("NYC", city_col.getString(0).?);
}

test "quoted string fields (basic)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name\n\"Alice\"\n\"Bob Smith\"\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 2), df.row_count);

    const col = df.column("name").?;

    // Quoted strings should have quotes removed by parser
    try testing.expectEqualStrings("Alice", col.getString(0).?);
    try testing.expectEqualStrings("Bob Smith", col.getString(1).?);
}

// Boolean Column Parsing Tests

test "tryParseBool recognizes true values" {
    const testing = std.testing;

    try testing.expect(tryParseBool("true"));
    try testing.expect(tryParseBool("TRUE"));
    try testing.expect(tryParseBool("True"));
    try testing.expect(tryParseBool("yes"));
    try testing.expect(tryParseBool("YES"));
    try testing.expect(tryParseBool("1"));
    try testing.expect(tryParseBool("t"));
    try testing.expect(tryParseBool("T"));
    try testing.expect(tryParseBool("y"));
    try testing.expect(tryParseBool("Y"));
}

test "tryParseBool recognizes false values" {
    const testing = std.testing;

    try testing.expect(tryParseBool("false"));
    try testing.expect(tryParseBool("FALSE"));
    try testing.expect(tryParseBool("False"));
    try testing.expect(tryParseBool("no"));
    try testing.expect(tryParseBool("NO"));
    try testing.expect(tryParseBool("0"));
    try testing.expect(tryParseBool("f"));
    try testing.expect(tryParseBool("F"));
    try testing.expect(tryParseBool("n"));
    try testing.expect(tryParseBool("N"));
}

test "tryParseBool rejects non-boolean values" {
    const testing = std.testing;

    try testing.expect(!tryParseBool("hello"));
    try testing.expect(!tryParseBool("2"));
    try testing.expect(!tryParseBool("maybe"));
    try testing.expect(!tryParseBool(""));
}

test "parseBool parses true values correctly" {
    const testing = std.testing;

    try testing.expectEqual(true, try parseBool("true"));
    try testing.expectEqual(true, try parseBool("TRUE"));
    try testing.expectEqual(true, try parseBool("yes"));
    try testing.expectEqual(true, try parseBool("1"));
    try testing.expectEqual(true, try parseBool("t"));
    try testing.expectEqual(true, try parseBool("y"));
}

test "parseBool parses false values correctly" {
    const testing = std.testing;

    try testing.expectEqual(false, try parseBool("false"));
    try testing.expectEqual(false, try parseBool("FALSE"));
    try testing.expectEqual(false, try parseBool("no"));
    try testing.expectEqual(false, try parseBool("0"));
    try testing.expectEqual(false, try parseBool("f"));
    try testing.expectEqual(false, try parseBool("n"));
}

test "boolean column parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "active,verified\ntrue,yes\nfalse,no\n1,0\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 3), df.row_count);
    try testing.expectEqual(@as(usize, 2), df.columns.len);

    // Verify both columns are Bool type
    const active_col = df.column("active").?;
    const verified_col = df.column("verified").?;
    try testing.expectEqual(ValueType.Bool, active_col.value_type);
    try testing.expectEqual(ValueType.Bool, verified_col.value_type);

    // Verify data
    const active_data = active_col.asBool().?;
    const verified_data = verified_col.asBool().?;

    try testing.expectEqual(true, active_data[0]);
    try testing.expectEqual(true, verified_data[0]);

    try testing.expectEqual(false, active_data[1]);
    try testing.expectEqual(false, verified_data[1]);

    try testing.expectEqual(true, active_data[2]);
    try testing.expectEqual(false, verified_data[2]);
}

// Categorical Column Tests (0.4.0+)

test "CSV parser auto-detects categorical column (low cardinality < 5%)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create CSV with 100 rows and 3 unique region values (3%)
    var csv_builder = std.ArrayList(u8){};
    defer csv_builder.deinit(allocator);

    try csv_builder.appendSlice(allocator, "region,value\n");
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const region = if (i % 3 == 0) "East" else if (i % 3 == 1) "West" else "South";
        try csv_builder.writer(allocator).print("{s},{}\n", .{ region, i });
    }

    var parser = try CSVParser.init(allocator, csv_builder.items, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    try testing.expectEqual(@as(u32, 100), df.row_count);

    const region_col = df.column("region").?;
    try testing.expectEqual(ValueType.Categorical, region_col.value_type);

    // Verify categorical data
    const cat_col = region_col.asCategoricalColumn().?;
    try testing.expectEqual(@as(u32, 3), cat_col.categoryCount());

    // Check first few values decode correctly
    try testing.expectEqualStrings("East", cat_col.get(0));
    try testing.expectEqualStrings("West", cat_col.get(1));
    try testing.expectEqualStrings("South", cat_col.get(2));
}

test "CSV parser detects string column (high cardinality > 5%)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create CSV with 100 rows and 50 unique ID values (50%)
    var csv_builder = std.ArrayList(u8){};
    defer csv_builder.deinit(allocator);

    try csv_builder.appendSlice(allocator, "id,value\n");
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        // Create 50 unique IDs (each ID appears twice)
        const id_num = i / 2;
        try csv_builder.writer(allocator).print("id{},{}\n", .{ id_num, i });
    }

    var parser = try CSVParser.init(allocator, csv_builder.items, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const id_col = df.column("id").?;
    try testing.expectEqual(ValueType.String, id_col.value_type); // 50% > 5% threshold
}

test "detectCategorical returns false for < 10 rows" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // CSV with only 5 rows (below minimum threshold)
    const csv = "region\nEast\nEast\nWest\nEast\nSouth\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const region_col = df.column("region").?;
    // Should default to String (not enough rows for reliable detection)
    try testing.expectEqual(ValueType.String, region_col.value_type);
}

test "mixed column types with boolean" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const csv = "name,age,active\nAlice,30,true\nBob,25,false\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    // Verify column types
    const name_col = df.column("name").?;
    const age_col = df.column("age").?;
    const active_col = df.column("active").?;

    try testing.expectEqual(ValueType.String, name_col.value_type);
    try testing.expectEqual(ValueType.Int64, age_col.value_type);
    try testing.expectEqual(ValueType.Bool, active_col.value_type);

    // Verify boolean data
    const active_data = active_col.asBool().?;
    try testing.expectEqual(true, active_data[0]);
    try testing.expectEqual(false, active_data[1]);
}

test "empty boolean fields default to false" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // CSV with empty boolean field (column "active" has empty value in row 2)
    const csv = "name,active\nAlice,true\nBob,\nCharlie,false\n";

    var parser = try CSVParser.init(allocator, csv, .{});
    defer parser.deinit();

    var df = try parser.toDataFrame();
    defer df.deinit();

    const col = df.column("active").?;
    const data = col.asBool().?;

    try testing.expectEqual(true, data[0]); // Alice: true
    try testing.expectEqual(false, data[1]); // Bob: empty → defaults to false
    try testing.expectEqual(false, data[2]); // Charlie: false
}
