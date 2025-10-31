//! Error Utilities - Rich error messages with context and suggestions
//!
//! Provides enhanced error reporting for DataFrame operations including:
//! - Column name suggestions using Levenshtein distance
//! - Formatted error messages with DataFrame context
//! - Available column listings for ColumnNotFound errors
//!
//! This module follows Tiger Style: bounded loops, 2+ assertions per function.

const std = @import("std");
const DataFrame = @import("dataframe.zig").DataFrame;

const MAX_COLUMN_NAME_LENGTH: u32 = 256;
const MAX_SUGGESTION_DISTANCE: u32 = 3; // Maximum edit distance for suggestions
const MAX_DISPLAYED_COLUMNS: u32 = 10; // Maximum columns to show in error message

/// Compute Levenshtein distance between two strings (edit distance)
///
/// **Performance**: O(m × n) where m, n are string lengths
/// **Memory**: O(n) using row optimization
///
/// Returns edit distance: number of insertions, deletions, or substitutions needed
/// to transform str1 into str2. Lower distance = more similar strings.
///
/// Example:
/// ```zig
/// const dist = levenshteinDistance("naem", "name"); // Returns 2
/// ```
pub fn levenshteinDistance(str1: []const u8, str2: []const u8) u32 {
    std.debug.assert(str1.len <= MAX_COLUMN_NAME_LENGTH); // Pre-condition #1
    std.debug.assert(str2.len <= MAX_COLUMN_NAME_LENGTH); // Pre-condition #2

    const m: u32 = @intCast(str1.len);
    const n: u32 = @intCast(str2.len);

    // Early exit for identical strings
    if (std.mem.eql(u8, str1, str2)) return 0;

    // Empty string cases
    if (m == 0) return n;
    if (n == 0) return m;

    // Use two rows to save memory (instead of full m×n matrix)
    var prev_row: [MAX_COLUMN_NAME_LENGTH + 1]u32 = undefined;
    var curr_row: [MAX_COLUMN_NAME_LENGTH + 1]u32 = undefined;

    // Initialize first row: distance from empty string
    var j: u32 = 0;
    while (j <= n and j <= MAX_COLUMN_NAME_LENGTH) : (j += 1) {
        prev_row[j] = j;
    }
    std.debug.assert(j == n + 1 or j == MAX_COLUMN_NAME_LENGTH + 1); // Post-condition #1

    // Fill remaining rows
    var i: u32 = 0;
    while (i < m and i < MAX_COLUMN_NAME_LENGTH) : (i += 1) {
        curr_row[0] = i + 1;

        j = 0;
        while (j < n and j < MAX_COLUMN_NAME_LENGTH) : (j += 1) {
            const cost: u32 = if (str1[i] == str2[j]) 0 else 1;

            const deletion = prev_row[j + 1] + 1;
            const insertion = curr_row[j] + 1;
            const substitution = prev_row[j] + cost;

            curr_row[j + 1] = @min(@min(deletion, insertion), substitution);
        }
        std.debug.assert(j == n or j == MAX_COLUMN_NAME_LENGTH); // Post-condition #2

        // Swap rows
        const temp = prev_row;
        prev_row = curr_row;
        curr_row = temp;
    }
    std.debug.assert(i == m or i == MAX_COLUMN_NAME_LENGTH); // Post-condition #3

    const result = prev_row[n];
    std.debug.assert(result <= m + n); // Post-condition #4: Max distance is sum of lengths
    return result;
}

/// Find the best column name suggestion for a typo
///
/// Returns the closest column name if distance ≤ MAX_SUGGESTION_DISTANCE,
/// otherwise returns null.
///
/// Example:
/// ```zig
/// const cols = [_][]const u8{ "name", "age", "city" };
/// const suggestion = findBestColumnSuggestion("naem", &cols); // Returns "name"
/// ```
pub fn findBestColumnSuggestion(
    typo: []const u8,
    available_columns: []const []const u8,
) ?[]const u8 {
    std.debug.assert(typo.len > 0); // Pre-condition #1
    std.debug.assert(available_columns.len > 0); // Pre-condition #2

    var best_match: ?[]const u8 = null;
    var best_distance: u32 = MAX_SUGGESTION_DISTANCE + 1;

    var i: u32 = 0;
    while (i < available_columns.len and i < 10000) : (i += 1) {
        const col_name = available_columns[i];
        const dist = levenshteinDistance(typo, col_name);

        if (dist < best_distance) {
            best_distance = dist;
            best_match = col_name;
        }
    }
    std.debug.assert(i == available_columns.len or i == 10000); // Post-condition

    // Only return if distance is within acceptable threshold
    if (best_distance <= MAX_SUGGESTION_DISTANCE) {
        return best_match;
    }

    return null;
}

/// Format a ColumnNotFound error with helpful context
///
/// Generates a message like:
/// "Column 'naem' not found. Did you mean 'name'? Available: [name, age, city]"
///
/// **Memory**: Allocates string, caller must free
///
/// NOTE: This is a simplified version that formats the first 3 columns only
/// to avoid ArrayList API complications in Zig 0.15
pub fn formatColumnNotFoundError(
    allocator: std.mem.Allocator,
    column_name: []const u8,
    available_columns: []const []const u8,
) ![]const u8 {
    std.debug.assert(column_name.len > 0); // Pre-condition #1
    std.debug.assert(available_columns.len > 0); // Pre-condition #2

    const suggestion = findBestColumnSuggestion(column_name, available_columns);

    // Build column list (show first 3 columns)
    const col_count = @min(available_columns.len, 3);

    if (suggestion) |sug| {
        if (col_count == 1) {
            return try std.fmt.allocPrint(
                allocator,
                "Column '{s}' not found. Did you mean '{s}'? Available: [{s}]",
                .{ column_name, sug, available_columns[0] },
            );
        } else if (col_count == 2) {
            return try std.fmt.allocPrint(
                allocator,
                "Column '{s}' not found. Did you mean '{s}'? Available: [{s}, {s}]",
                .{ column_name, sug, available_columns[0], available_columns[1] },
            );
        } else {
            const more_count = if (available_columns.len > 3) available_columns.len - 3 else 0;
            if (more_count > 0) {
                return try std.fmt.allocPrint(
                    allocator,
                    "Column '{s}' not found. Did you mean '{s}'? Available: [{s}, {s}, {s}, ... and {} more]",
                    .{ column_name, sug, available_columns[0], available_columns[1], available_columns[2], more_count },
                );
            } else {
                return try std.fmt.allocPrint(
                    allocator,
                    "Column '{s}' not found. Did you mean '{s}'? Available: [{s}, {s}, {s}]",
                    .{ column_name, sug, available_columns[0], available_columns[1], available_columns[2] },
                );
            }
        }
    } else {
        if (col_count == 1) {
            return try std.fmt.allocPrint(
                allocator,
                "Column '{s}' not found. Available: [{s}]",
                .{ column_name, available_columns[0] },
            );
        } else if (col_count == 2) {
            return try std.fmt.allocPrint(
                allocator,
                "Column '{s}' not found. Available: [{s}, {s}]",
                .{ column_name, available_columns[0], available_columns[1] },
            );
        } else {
            const more_count = if (available_columns.len > 3) available_columns.len - 3 else 0;
            if (more_count > 0) {
                return try std.fmt.allocPrint(
                    allocator,
                    "Column '{s}' not found. Available: [{s}, {s}, {s}, ... and {} more]",
                    .{ column_name, available_columns[0], available_columns[1], available_columns[2], more_count },
                );
            } else {
                return try std.fmt.allocPrint(
                    allocator,
                    "Column '{s}' not found. Available: [{s}, {s}, {s}]",
                    .{ column_name, available_columns[0], available_columns[1], available_columns[2] },
                );
            }
        }
    }
}

/// Error context for DataFrame operations
///
/// Contains all relevant information for debugging errors:
/// - Operation name
/// - DataFrame shape (rows × columns)
/// - Column names involved
/// - Suggested fix
pub const ErrorContext = struct {
    operation: []const u8,
    dataframe_shape: struct {
        rows: u32,
        columns: u32,
    },
    column_names: ?[]const []const u8 = null,
    suggestion: ?[]const u8 = null,

    /// Create error context from DataFrame
    pub fn fromDataFrame(
        operation: []const u8,
        df: *const DataFrame,
    ) ErrorContext {
        std.debug.assert(operation.len > 0); // Pre-condition #1
        std.debug.assert(df.row_count <= 4_000_000_000); // Pre-condition #2

        return ErrorContext{
            .operation = operation,
            .dataframe_shape = .{
                .rows = df.row_count,
                .columns = @intCast(df.columnCount()),
            },
            .column_names = null,
            .suggestion = null,
        };
    }

    /// Format error context as human-readable string
    ///
    /// Example output:
    /// "Operation: join | DataFrame shape: 1000 rows × 5 columns | Suggestion: ..."
    pub fn format(
        self: *const ErrorContext,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        std.debug.assert(self.operation.len > 0); // Pre-condition

        if (self.suggestion) |suggestion| {
            return try std.fmt.allocPrint(
                allocator,
                "Operation: {s} | DataFrame shape: {} rows × {} columns | Suggestion: {s}",
                .{ self.operation, self.dataframe_shape.rows, self.dataframe_shape.columns, suggestion },
            );
        } else {
            return try std.fmt.allocPrint(
                allocator,
                "Operation: {s} | DataFrame shape: {} rows × {} columns",
                .{ self.operation, self.dataframe_shape.rows, self.dataframe_shape.columns },
            );
        }
    }
};

// Tests
const testing = std.testing;

test "levenshteinDistance: identical strings" {
    const dist = levenshteinDistance("hello", "hello");
    try testing.expectEqual(@as(u32, 0), dist);
}

test "levenshteinDistance: single character substitution" {
    const dist = levenshteinDistance("hello", "hallo");
    try testing.expectEqual(@as(u32, 1), dist);
}

test "levenshteinDistance: transposition (2 edits)" {
    const dist = levenshteinDistance("naem", "name");
    try testing.expectEqual(@as(u32, 2), dist);
}

test "levenshteinDistance: insertion" {
    const dist = levenshteinDistance("cat", "cart");
    try testing.expectEqual(@as(u32, 1), dist);
}

test "levenshteinDistance: deletion" {
    const dist = levenshteinDistance("cart", "cat");
    try testing.expectEqual(@as(u32, 1), dist);
}

test "levenshteinDistance: empty strings" {
    const dist1 = levenshteinDistance("", "hello");
    const dist2 = levenshteinDistance("hello", "");

    try testing.expectEqual(@as(u32, 5), dist1);
    try testing.expectEqual(@as(u32, 5), dist2);
}

test "findBestColumnSuggestion: finds close match" {
    const cols = [_][]const u8{ "name", "age", "city" };
    const suggestion = findBestColumnSuggestion("naem", &cols);

    try testing.expect(suggestion != null);
    try testing.expectEqualStrings("name", suggestion.?);
}

test "findBestColumnSuggestion: rejects distant match" {
    const cols = [_][]const u8{ "name", "age", "city" };
    const suggestion = findBestColumnSuggestion("qwerty", &cols);

    try testing.expect(suggestion == null);
}

test "findBestColumnSuggestion: finds best among multiple" {
    const cols = [_][]const u8{ "username", "user_name", "age" };
    const suggestion = findBestColumnSuggestion("usrname", &cols);

    try testing.expect(suggestion != null);
    // Should suggest "username" (dist=1) over "user_name" (dist=2)
    try testing.expectEqualStrings("username", suggestion.?);
}

test "formatColumnNotFoundError: with suggestion" {
    const allocator = testing.allocator;
    const cols = [_][]const u8{ "name", "age", "city" };

    const msg = try formatColumnNotFoundError(allocator, "naem", &cols);
    defer allocator.free(msg);

    // Should contain: column name, suggestion, and available list
    try testing.expect(std.mem.indexOf(u8, msg, "naem") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "Did you mean 'name'?") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "Available:") != null);
}

test "formatColumnNotFoundError: without suggestion" {
    const allocator = testing.allocator;
    const cols = [_][]const u8{ "name", "age", "city" };

    const msg = try formatColumnNotFoundError(allocator, "qwerty", &cols);
    defer allocator.free(msg);

    // Should NOT contain suggestion
    try testing.expect(std.mem.indexOf(u8, msg, "Did you mean") == null);
    // Should contain available list
    try testing.expect(std.mem.indexOf(u8, msg, "Available:") != null);
}

test "formatColumnNotFoundError: many columns truncated" {
    const allocator = testing.allocator;
    const cols = [_][]const u8{
        "col1",  "col2",  "col3",  "col4",  "col5",
        "col6",  "col7",  "col8",  "col9",  "col10",
        "col11", "col12", "col13",
    };

    const msg = try formatColumnNotFoundError(allocator, "qwerty", &cols);
    defer allocator.free(msg);

    // Should show first 3 and indicate 10 more (13 total - 3 shown = 10 remaining)
    try testing.expect(std.mem.indexOf(u8, msg, "and 10 more") != null);
}

test "ErrorContext: format" {
    const allocator = testing.allocator;

    const ctx = ErrorContext{
        .operation = "join",
        .dataframe_shape = .{ .rows = 1000, .columns = 5 },
        .suggestion = "Check column names match",
    };

    const formatted = try ctx.format(allocator);
    defer allocator.free(formatted);

    try testing.expect(std.mem.indexOf(u8, formatted, "Operation: join") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "1000 rows × 5 columns") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "Check column names match") != null);
}
