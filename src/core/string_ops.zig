//! String column operations for data cleaning and transformation
//!
//! This module provides string manipulation functions for Series with String columns.
//! These are essential for data cleaning, text normalization, and feature extraction.
//!
//! Supported operations:
//! - Case conversion: lower, upper
//! - Whitespace handling: trim, strip
//! - Pattern matching: contains
//! - Replacement: replace
//! - Extraction: slice, len
//! - Splitting: split (returns array of Series)
//!
//! Tiger Style:
//! - 2+ assertions per function
//! - Bounded loops with explicit MAX constants
//! - Functions ≤70 lines
//! - Explicit types (u32, not usize)
//! - UTF-8 aware

const std = @import("std");
const Allocator = std.mem.Allocator;
const Series = @import("series.zig").Series;
const StringColumn = @import("series.zig").StringColumn;
const ValueType = @import("types.zig").ValueType;

/// Maximum string length for operations
pub const MAX_STRING_LENGTH: u32 = 1_000_000;

/// Helper function: Convert array of strings to StringColumn
fn stringsToColumn(allocator: Allocator, strings: [][]const u8) !StringColumn {
    std.debug.assert(strings.len > 0);
    std.debug.assert(strings.len <= MAX_STRING_LENGTH);

    // Calculate total buffer size needed
    var total_len: u32 = 0;
    for (strings) |str| {
        total_len += @intCast(str.len);
    }

    // Create StringColumn with appropriate capacity
    var col = try StringColumn.init(allocator, @intCast(strings.len), total_len);
    errdefer col.deinit(allocator);

    // Append each string
    var i: u32 = 0;
    while (i < MAX_STRING_LENGTH and i < strings.len) : (i += 1) {
        try col.append(allocator, strings[i]);
    }
    std.debug.assert(i == strings.len); // Appended all strings

    return col;
}

/// Convert all characters to lowercase
///
/// **UTF-8 Support**: Currently only handles ASCII (A-Z → a-z).
/// Non-ASCII characters (emoji, CJK, accents) are preserved unchanged.
///
/// **Limitation**: Full Unicode case conversion requires ICU library or Unicode tables.
/// For MVP, we validate UTF-8 and handle ASCII. Full Unicode support deferred to 1.0.0.
///
/// **Complexity**: O(n) where n = total string length
pub fn lower(series: *const Series, allocator: Allocator) !Series {
    // Tiger Style: Assertions
    std.debug.assert(series.value_type == .String);
    std.debug.assert(series.length > 0);

    if (series.value_type != .String) return error.InvalidType;

    const strings = series.data.String;

    // Calculate total buffer size needed
    var total_len: u32 = 0;
    var i: u32 = 0;
    while (i < series.length) : (i += 1) {
        const str = strings.get(i);
        total_len += @intCast(str.len);
    }

    // Create output StringColumn
    var result_col = try StringColumn.init(allocator, series.length, total_len);
    errdefer result_col.deinit(allocator);

    // Process each string
    i = 0;
    while (i < series.length) : (i += 1) {
        const str = strings.get(i);
        if (str.len > MAX_STRING_LENGTH) return error.StringTooLong;

        // ✅ Validate UTF-8
        if (!std.unicode.utf8ValidateSlice(str)) {
            return error.InvalidUtf8;
        }

        const lower_str = try allocator.alloc(u8, str.len);
        defer allocator.free(lower_str);

        // Bounded character iteration (ASCII lowercasing only)
        var j: u32 = 0;
        while (j < MAX_STRING_LENGTH and j < str.len) : (j += 1) {
            lower_str[j] = std.ascii.toLower(str[j]);
        }
        std.debug.assert(j == str.len); // Post-condition: processed all characters

        try result_col.append(allocator, lower_str);
    }

    return Series{
        .name = series.name,
        .value_type = .String,
        .data = .{ .String = result_col },
        .length = series.length,
    };
}

/// Convert all characters to uppercase
///
/// **UTF-8 Support**: Currently only handles ASCII (a-z → A-Z).
/// Non-ASCII characters (emoji, CJK, accents) are preserved unchanged.
///
/// **Limitation**: Full Unicode case conversion requires ICU library or Unicode tables.
/// For MVP, we validate UTF-8 and handle ASCII. Full Unicode support deferred to 1.0.0.
///
/// **Complexity**: O(n) where n = total string length
pub fn upper(series: *const Series, allocator: Allocator) !Series {
    // Tiger Style: Assertions
    std.debug.assert(series.value_type == .String);
    std.debug.assert(series.length > 0);

    if (series.value_type != .String) return error.InvalidType;

    const strings = series.data.String;

    // Calculate total buffer size needed
    var total_len: u32 = 0;
    var i: u32 = 0;
    while (i < series.length) : (i += 1) {
        const str = strings.get(i);
        total_len += @intCast(str.len);
    }

    // Create output StringColumn
    var result_col = try StringColumn.init(allocator, series.length, total_len);
    errdefer result_col.deinit(allocator);

    // Process each string
    i = 0;
    while (i < series.length) : (i += 1) {
        const str = strings.get(i);
        if (str.len > MAX_STRING_LENGTH) return error.StringTooLong;

        // ✅ Validate UTF-8
        if (!std.unicode.utf8ValidateSlice(str)) {
            return error.InvalidUtf8;
        }

        const upper_str = try allocator.alloc(u8, str.len);
        defer allocator.free(upper_str);

        // Bounded character iteration (ASCII uppercasing only)
        var j: u32 = 0;
        while (j < MAX_STRING_LENGTH and j < str.len) : (j += 1) {
            upper_str[j] = std.ascii.toUpper(str[j]);
        }
        std.debug.assert(j == str.len); // Post-condition: processed all characters

        try result_col.append(allocator, upper_str);
    }

    return Series{
        .name = series.name,
        .value_type = .String,
        .data = .{ .String = result_col },
        .length = series.length,
    };
}

/// Remove leading and trailing whitespace
pub fn trim(series: *const Series, allocator: Allocator) !Series {
    // Tiger Style: Assertions
    std.debug.assert(series.value_type == .String);
    std.debug.assert(series.length > 0);

    if (series.value_type != .String) return error.InvalidType;

    const strings = series.data.String;

    // Calculate approximate buffer size (trimmed strings will be ≤ original)
    var total_len: u32 = 0;
    var i: u32 = 0;
    while (i < series.length) : (i += 1) {
        const str = strings.get(i);
        total_len += @intCast(str.len);
    }

    // Create output StringColumn
    var result_col = try StringColumn.init(allocator, series.length, total_len);
    errdefer result_col.deinit(allocator);

    // Process each string
    i = 0;
    while (i < series.length) : (i += 1) {
        const str = strings.get(i);
        const trimmed = std.mem.trim(u8, str, &std.ascii.whitespace);
        try result_col.append(allocator, trimmed);
    }
    std.debug.assert(i == series.length); // Post-condition: Processed all strings

    return Series{
        .name = series.name,
        .value_type = .String,
        .data = .{ .String = result_col },
        .length = series.length,
    };
}

/// Alias for trim (pandas compatibility)
pub fn strip(series: *const Series, allocator: Allocator) !Series {
    return trim(series, allocator);
}

/// Check if string contains a substring
pub fn contains(series: *const Series, allocator: Allocator, pattern: []const u8) !Series {
    // Tiger Style: Assertions
    std.debug.assert(series.value_type == .String);
    std.debug.assert(series.length > 0);

    if (series.value_type != .String) return error.InvalidType;

    const strings = series.data.String;
    const result = try allocator.alloc(bool, series.length);

    // Empty pattern always matches (standard behavior)
    if (pattern.len == 0) {
        var i: u32 = 0;
        while (i < series.length) : (i += 1) {
            result[i] = true;
        }
        std.debug.assert(i == series.length); // Post-condition: All values set to true
    } else {
        var i: u32 = 0;
        while (i < series.length) : (i += 1) {
            const str = strings.get(i);
            result[i] = std.mem.indexOf(u8, str, pattern) != null;
        }
        std.debug.assert(i == series.length); // Post-condition: Checked all strings
    }

    return Series{
        .name = series.name,
        .value_type = .Bool,
        .data = .{ .Bool = result },
        .length = series.length,
    };
}

/// Replace all occurrences of a substring
pub fn replace(series: *const Series, allocator: Allocator, from: []const u8, to: []const u8) !Series {
    // Tiger Style: Assertions
    std.debug.assert(series.value_type == .String);
    std.debug.assert(series.length > 0);
    std.debug.assert(from.len > 0);

    if (series.value_type != .String) return error.InvalidType;
    if (from.len == 0) return error.EmptyPattern;

    const strings = series.data.String;

    // Calculate approximate buffer size
    var total_len: u32 = 0;
    var i: u32 = 0;
    while (i < series.length) : (i += 1) {
        const str = strings.get(i);
        // Assume worst case: replacement might be longer
        total_len += @intCast(str.len + to.len * 10); // Generous estimate
    }

    // Create output StringColumn
    var result_col = try StringColumn.init(allocator, series.length, total_len);
    errdefer result_col.deinit(allocator);

    // Process each string
    i = 0;
    while (i < series.length) : (i += 1) {
        const str = strings.get(i);

        // Count occurrences to allocate result
        var count: u32 = 0;
        var pos: usize = 0;
        while (pos < str.len) {
            if (std.mem.indexOf(u8, str[pos..], from)) |idx| {
                count += 1;
                pos += idx + from.len;
            } else {
                break;
            }
        }

        if (count == 0) {
            // No matches, append original
            try result_col.append(allocator, str);
            continue;
        }

        // Allocate new string with replacements
        // Tiger Style: Overflow check with wider type
        const count_u64 = @as(u64, count);
        const from_len_u64 = @as(u64, from.len);
        const to_len_u64 = @as(u64, to.len);
        const str_len_u64 = @as(u64, str.len);

        const removed_bytes = count_u64 * from_len_u64;
        const added_bytes = count_u64 * to_len_u64;

        // Check for underflow
        if (str_len_u64 < removed_bytes) {
            return error.InvalidCalculation; // Should never happen
        }

        const new_len_u64 = str_len_u64 - removed_bytes + added_bytes;

        // Check against max string length
        if (new_len_u64 > MAX_STRING_LENGTH) {
            return error.StringTooLong;
        }

        const new_len: usize = @intCast(new_len_u64);
        const replaced = try allocator.alloc(u8, new_len);
        defer allocator.free(replaced);

        var write_pos: usize = 0;
        var read_pos: usize = 0;
        while (read_pos < str.len) {
            if (std.mem.indexOf(u8, str[read_pos..], from)) |idx| {
                // Copy before match
                @memcpy(replaced[write_pos .. write_pos + idx], str[read_pos .. read_pos + idx]);
                write_pos += idx;

                // Copy replacement
                @memcpy(replaced[write_pos .. write_pos + to.len], to);
                write_pos += to.len;

                read_pos += idx + from.len;
            } else {
                // Copy remaining
                @memcpy(replaced[write_pos..], str[read_pos..]);
                break;
            }
        }

        try result_col.append(allocator, replaced);
    }

    return Series{
        .name = series.name,
        .value_type = .String,
        .data = .{ .String = result_col },
        .length = series.length,
    };
}

/// Extract substring by slice
pub fn slice(series: *const Series, allocator: Allocator, start: u32, end: u32) !Series {
    // Tiger Style: Error checks FIRST (before assertions)
    if (series.value_type != .String) return error.InvalidType;
    if (start > end) return error.InvalidSlice;

    // Tiger Style: Assertions AFTER error checks
    std.debug.assert(series.value_type == .String);
    std.debug.assert(series.length > 0);
    std.debug.assert(start <= end); // Post-condition from error check

    const strings = series.data.String;

    // Calculate buffer size (safe now that we know start <= end)
    const slice_len = end - start;
    const total_len = series.length * slice_len;

    // Create output StringColumn
    var result_col = try StringColumn.init(allocator, series.length, total_len);
    errdefer result_col.deinit(allocator);

    // Process each string
    var i: u32 = 0;
    while (i < series.length) : (i += 1) {
        const str = strings.get(i);
        const actual_start = @min(start, @as(u32, @intCast(str.len)));
        const actual_end = @min(end, @as(u32, @intCast(str.len)));

        const sliced = str[actual_start..actual_end];
        try result_col.append(allocator, sliced);
    }
    std.debug.assert(i == series.length); // Post-condition: Processed all strings

    return Series{
        .name = series.name,
        .value_type = .String,
        .data = .{ .String = result_col },
        .length = series.length,
    };
}

/// Get string length for each element
pub fn len(series: *const Series, allocator: Allocator) !Series {
    // Tiger Style: Assertions
    std.debug.assert(series.value_type == .String);
    std.debug.assert(series.length > 0);

    if (series.value_type != .String) return error.InvalidType;

    const strings = series.data.String;
    const result = try allocator.alloc(i64, series.length);

    var i: u32 = 0;
    while (i < series.length) : (i += 1) {
        const str_len = strings.get(i).len;

        // Tiger Style: Bounds check (unlikely but safer)
        if (str_len > std.math.maxInt(i64)) {
            allocator.free(result);
            return error.StringTooLong;
        }

        result[i] = @intCast(str_len);
    }
    std.debug.assert(i == series.length); // Post-condition: Processed all strings

    return Series{
        .name = series.name,
        .value_type = .Int64,
        .data = .{ .Int64 = result },
        .length = series.length,
    };
}

/// Split result - array of Series (one per split part)
pub const SplitResult = struct {
    parts: []Series,
    num_parts: u32,

    pub fn free(self: *SplitResult, allocator: Allocator) void {
        std.debug.assert(self.num_parts > 0);
        std.debug.assert(self.parts.len == self.num_parts);

        // Bounded iteration over parts
        var part_idx: u32 = 0;
        while (part_idx < MAX_STRING_LENGTH and part_idx < self.parts.len) : (part_idx += 1) {
            const part = &self.parts[part_idx];
            if (part.valueType == .String) {
                const strings = part.data.String;

                // Bounded iteration over strings
                var str_idx: u32 = 0;
                while (str_idx < MAX_STRING_LENGTH and str_idx < strings.len) : (str_idx += 1) {
                    allocator.free(strings[str_idx]);
                }
                std.debug.assert(str_idx == strings.len); // Post-condition

                allocator.free(strings);
            }
        }
        std.debug.assert(part_idx == self.parts.len); // Post-condition

        allocator.free(self.parts);
    }
};

/// Split string by delimiter (returns array of Series)
pub fn split(series: *const Series, allocator: Allocator, delimiter: []const u8) !SplitResult {
    // Tiger Style: Assertions
    std.debug.assert(series.value_type == .String);
    std.debug.assert(series.length > 0);
    std.debug.assert(delimiter.len > 0);

    if (series.value_type != .String) return error.InvalidType;
    if (delimiter.len == 0) return error.EmptyDelimiter;

    const strings = series.data.String;

    // First pass: determine max number of parts
    var max_parts: u32 = 0;
    var i: u32 = 0;
    while (i < series.length) : (i += 1) {
        const str = strings.get(i);
        var count: u32 = 1;
        var pos: usize = 0;
        while (pos < str.len) {
            if (std.mem.indexOf(u8, str[pos..], delimiter)) |idx| {
                count += 1;
                pos += idx + delimiter.len;
            } else {
                break;
            }
        }
        if (count > max_parts) max_parts = count;
    }

    // Allocate Series array
    const parts = try allocator.alloc(Series, max_parts);

    // Initialize each part Series
    var part_idx: u32 = 0;
    while (part_idx < max_parts) : (part_idx += 1) {
        const part_data = try allocator.alloc([]const u8, series.length);
        parts[part_idx] = Series{
            .name = series.name,
            .value_type = .String,
            .data = .{ .String = part_data },
            .length = series.length,
        };
    }

    // Second pass: split and populate
    i = 0;
    while (i < series.length) : (i += 1) {
        const str = strings.get(i);
        var current_part: u32 = 0;
        var start_pos: usize = 0;

        while (start_pos < str.len and current_part < max_parts) {
            if (std.mem.indexOf(u8, str[start_pos..], delimiter)) |idx| {
                const part_str = str[start_pos .. start_pos + idx];
                const part_copy = try allocator.alloc(u8, part_str.len);
                @memcpy(part_copy, part_str);
                parts[current_part].data.String[i] = part_copy;

                start_pos += idx + delimiter.len;
                current_part += 1;
            } else {
                // Last part
                const part_str = str[start_pos..];
                const part_copy = try allocator.alloc(u8, part_str.len);
                @memcpy(part_copy, part_str);
                parts[current_part].data.String[i] = part_copy;
                current_part += 1;
                break;
            }
        }

        // Fill remaining parts with empty strings
        while (current_part < max_parts) : (current_part += 1) {
            const empty = try allocator.alloc(u8, 0);
            parts[current_part].data.String[i] = empty;
        }
    }

    return SplitResult{
        .parts = parts,
        .num_parts = max_parts,
    };
}

/// Check if string starts with a prefix
pub fn startsWith(series: *const Series, allocator: Allocator, prefix: []const u8) !Series {
    // Tiger Style: Assertions
    std.debug.assert(series.value_type == .String);
    std.debug.assert(series.length > 0);

    if (series.value_type != .String) return error.InvalidType;

    const strings = series.data.String;
    const result = try allocator.alloc(bool, series.length);

    // Empty prefix always matches (standard behavior)
    if (prefix.len == 0) {
        var i: u32 = 0;
        while (i < series.length) : (i += 1) {
            result[i] = true;
        }
    } else {
        var i: u32 = 0;
        while (i < series.length) : (i += 1) {
            const str = strings.get(i);
            result[i] = std.mem.startsWith(u8, str, prefix);
        }
    }

    return Series{
        .name = series.name,
        .value_type = .Bool,
        .data = .{ .Bool = result },
        .length = series.length,
    };
}

/// Check if string ends with a suffix
pub fn endsWith(series: *const Series, allocator: Allocator, suffix: []const u8) !Series {
    // Tiger Style: Assertions
    std.debug.assert(series.value_type == .String);
    std.debug.assert(series.length > 0);

    if (series.value_type != .String) return error.InvalidType;

    const strings = series.data.String;
    const result = try allocator.alloc(bool, series.length);

    // Empty suffix always matches (standard behavior)
    if (suffix.len == 0) {
        var i: u32 = 0;
        while (i < series.length) : (i += 1) {
            result[i] = true;
        }
    } else {
        var i: u32 = 0;
        while (i < series.length) : (i += 1) {
            const str = strings.get(i);
            result[i] = std.mem.endsWith(u8, str, suffix);
        }
    }

    return Series{
        .name = series.name,
        .value_type = .Bool,
        .data = .{ .Bool = result },
        .length = series.length,
    };
}
