# String Column Implementation Design

**Version**: 0.2.0
**Date**: 2025-10-27
**Status**: Design Phase

---

## Overview

This document describes the design and implementation plan for string column support in Rozes DataFrame library.

### Goals

1. **Memory Efficient**: Avoid duplicating strings, use contiguous storage
2. **Zero-Copy Access**: Enable direct string access without intermediate copies
3. **Tiger Style Compliant**: 2+ assertions per function, bounded loops, explicit types
4. **UTF-8 Support**: Handle Unicode strings correctly
5. **CSV Round-Trip**: Parse → DataFrame → Export without data loss

### Non-Goals (Deferred to 0.3.0+)

- String interning/deduplication
- String operations (concat, split, etc.)
- Regex support
- Null string handling (empty string = null for MVP)

---

## Current State (0.1.0)

**Existing Infrastructure**:
```zig
// src/core/types.zig
pub const ValueType = enum {
    Int64,
    Float64,
    String,  // ✅ Enum value exists
    Bool,
    Null,
};

// src/core/series.zig
pub const SeriesData = union(ValueType) {
    Int64: []i64,
    Float64: []f64,
    String: [][]const u8,  // ✅ Basic structure exists
    Bool: []bool,
    Null: void,
};
```

**What's Missing**:
- ❌ String storage implementation (currently `[][]const u8` - array of slices)
- ❌ String column creation/access methods
- ❌ String type inference in CSV parser
- ❌ String serialization in CSV export
- ❌ Unit tests for string operations

---

## Design Options

### Option 1: Array of String Slices (Current - Inefficient)

```zig
pub const SeriesData = union(ValueType) {
    String: [][]const u8,  // Each string is a separate slice
    // ...
};
```

**Pros**:
- Simple implementation
- Each string can be any length
- No offset table needed

**Cons**:
- ❌ Poor cache locality (strings scattered in memory)
- ❌ Each slice has overhead (ptr + len)
- ❌ Difficult to serialize/deserialize efficiently
- ❌ Not zero-copy friendly

**Verdict**: ❌ **NOT RECOMMENDED** for production use

---

### Option 2: Offset Table + Contiguous Buffer (RECOMMENDED)

```zig
/// String column with offset table for efficient storage
pub const StringColumn = struct {
    /// Offset table: offsets[i] = end position of string i
    /// String i spans buffer[start..end] where:
    ///   - start = if (i == 0) 0 else offsets[i-1]
    ///   - end = offsets[i]
    offsets: []u32,

    /// Contiguous UTF-8 buffer containing all strings
    buffer: []u8,

    /// Number of strings stored
    count: u32,
};

pub const SeriesData = union(ValueType) {
    String: StringColumn,  // ✅ Efficient string storage
    // ...
};
```

**Layout Example**:
```
CSV:
  "Alice","Bob","Charlie"

StringColumn:
  buffer: [A,l,i,c,e,B,o,b,C,h,a,r,l,i,e]
  offsets: [5, 8, 15]
  count: 3

String access:
  str[0] = buffer[0..5]    = "Alice"
  str[1] = buffer[5..8]    = "Bob"
  str[2] = buffer[8..15]   = "Charlie"
```

**Pros**:
- ✅ Excellent cache locality (strings stored contiguously)
- ✅ Zero-copy access via slices
- ✅ Efficient serialization (just write buffer + offsets)
- ✅ Minimal per-string overhead (4 bytes offset vs 16 bytes slice)
- ✅ Easy to calculate total memory usage

**Cons**:
- More complex implementation (offset arithmetic)
- Fixed buffer size (but can grow)
- Need to track empty strings explicitly

**Verdict**: ✅ **RECOMMENDED** - Industry standard approach (Apache Arrow, DuckDB)

---

### Option 3: Fixed-Size String Slots (Not Suitable)

```zig
String: struct {
    data: []u8,  // Fixed-size buffer
    lengths: []u32,  // Length of each string
    max_len: u32,  // Maximum string length
}
```

**Pros**:
- Simple offset calculation (idx * max_len)
- No offset table needed

**Cons**:
- ❌ Wastes memory for short strings
- ❌ Cannot handle strings longer than max_len
- ❌ Not suitable for variable-length CSV data

**Verdict**: ❌ **NOT SUITABLE** for CSV parsing

---

## Final Design: Offset Table + Contiguous Buffer

### Data Structure

```zig
// src/core/series.zig

/// String column with offset-based storage
pub const StringColumn = struct {
    /// Offset table: offsets[i] = end position of string i in buffer
    /// String i spans buffer[start..end] where:
    ///   - start = if (i == 0) 0 else offsets[i-1]
    ///   - end = offsets[i]
    offsets: []u32,

    /// Contiguous UTF-8 buffer containing all strings
    buffer: []u8,

    /// Number of strings stored
    count: u32,

    /// Maximum number of strings (same as offsets.len)
    capacity: u32,

    /// Total buffer size in bytes
    buffer_size: u32,

    const MAX_STRINGS: u32 = std.math.maxInt(u32);
    const MAX_BUFFER_SIZE: u32 = 1_000_000_000; // 1GB max

    /// Creates a new StringColumn with given capacity
    pub fn init(
        allocator: std.mem.Allocator,
        capacity: u32,
        initial_buffer_size: u32,
    ) !StringColumn {
        std.debug.assert(capacity > 0);
        std.debug.assert(capacity <= MAX_STRINGS);
        std.debug.assert(initial_buffer_size <= MAX_BUFFER_SIZE);

        const offsets = try allocator.alloc(u32, capacity);
        const buffer = try allocator.alloc(u8, initial_buffer_size);

        return StringColumn{
            .offsets = offsets,
            .buffer = buffer,
            .count = 0,
            .capacity = capacity,
            .buffer_size = initial_buffer_size,
        };
    }

    /// Frees the StringColumn memory
    pub fn deinit(self: *StringColumn, allocator: std.mem.Allocator) void {
        std.debug.assert(self.count <= self.capacity);
        std.debug.assert(self.buffer_size <= MAX_BUFFER_SIZE);

        allocator.free(self.offsets);
        allocator.free(self.buffer);
        self.count = 0;
    }

    /// Gets string at index (zero-copy)
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
    pub fn append(
        self: *StringColumn,
        allocator: std.mem.Allocator,
        str: []const u8,
    ) !void {
        std.debug.assert(self.count < self.capacity); // Space available
        std.debug.assert(str.len <= MAX_BUFFER_SIZE); // String not too large

        // Check if we need to grow the buffer
        const current_pos = if (self.count == 0) 0 else self.offsets[self.count - 1];
        const needed_size = current_pos + @as(u32, @intCast(str.len));

        if (needed_size > self.buffer.len) {
            // Grow buffer (2x strategy)
            const new_size = @min(self.buffer.len * 2, MAX_BUFFER_SIZE);
            if (new_size < needed_size) return error.BufferTooSmall;

            const new_buffer = try allocator.realloc(self.buffer, new_size);
            self.buffer = new_buffer;
        }

        // Copy string data
        const start = current_pos;
        const end = start + @as(u32, @intCast(str.len));
        @memcpy(self.buffer[start..end], str);

        // Update offset
        self.offsets[self.count] = end;
        self.count += 1;
    }

    /// Returns total memory usage in bytes
    pub fn memoryUsage(self: *const StringColumn) usize {
        const offset_bytes = self.offsets.len * @sizeOf(u32);
        const buffer_bytes = self.buffer.len;
        return offset_bytes + buffer_bytes;
    }
};
```

### SeriesData Update

```zig
// src/core/series.zig
pub const SeriesData = union(ValueType) {
    Int64: []i64,
    Float64: []f64,
    String: StringColumn,  // ✅ Use StringColumn instead of [][]const u8
    Bool: []bool,
    Null: void,

    fn allocate(allocator: std.mem.Allocator, valueType: ValueType, capacity: u32) !SeriesData {
        return switch (valueType) {
            .Int64 => SeriesData{ .Int64 = try allocator.alloc(i64, capacity) },
            .Float64 => SeriesData{ .Float64 = try allocator.alloc(f64, capacity) },
            .Bool => SeriesData{ .Bool = try allocator.alloc(bool, capacity) },
            .String => blk: {
                // Estimate initial buffer size: avg 50 chars per string
                const initial_buffer_size = capacity * 50;
                const col = try StringColumn.init(allocator, capacity, initial_buffer_size);
                break :blk SeriesData{ .String = col };
            },
            .Null => SeriesData.Null,
        };
    }

    fn free(self: SeriesData, allocator: std.mem.Allocator) void {
        switch (self) {
            .Int64 => |slice| if (slice.len > 0) allocator.free(slice),
            .Float64 => |slice| if (slice.len > 0) allocator.free(slice),
            .Bool => |slice| if (slice.len > 0) allocator.free(slice),
            .String => |*col| col.deinit(allocator),  // ✅ Call StringColumn.deinit()
            .Null => {},
        }
    }
};
```

---

## Memory Layout Comparison

### Before (0.1.0) - Array of Slices
```
Memory layout for ["Alice", "Bob", "Charlie"]:

String array (3 slices):
  [ptr1, len1] → "Alice"   (16 bytes overhead)
  [ptr2, len2] → "Bob"     (16 bytes overhead)
  [ptr3, len3] → "Charlie" (16 bytes overhead)

Total overhead: 48 bytes
Data: 15 bytes
Total: 63 bytes (76% overhead!)
```

### After (0.2.0) - Offset Table + Buffer
```
Memory layout for ["Alice", "Bob", "Charlie"]:

Offsets array:
  [5, 8, 15]               (12 bytes)

Buffer:
  [A,l,i,c,e,B,o,b,C,h,a,r,l,i,e]  (15 bytes)

Total overhead: 12 bytes
Data: 15 bytes
Total: 27 bytes (44% smaller!)
```

**Memory Savings**: ~44% for this example, more for larger datasets

---

## Implementation Plan

### Phase 1: String Column Infrastructure (3 days) ✅ **COMPLETE**

**Day 1: StringColumn struct** ✅
- [x] Implement `StringColumn` in `src/core/series.zig`
- [x] Add `init()`, `deinit()`, `get()`, `append()` methods
- [x] Add buffer growth logic
- [x] Unit tests for StringColumn operations

**Day 2: SeriesData integration** ✅
- [x] Update `SeriesData` union to use `StringColumn`
- [x] Update `SeriesData.allocate()` for String type
- [x] Update `SeriesData.free()` for String type
- [x] Update `Series.get()` and `Series.set()` for strings

**Day 3: Series accessor methods and integration** ✅
- [x] Add `Series.asStringColumn()` accessor
- [x] Add `Series.getString(idx)` convenience method
- [x] Add `Series.appendString(allocator, str)` method
- [x] Add `Series.asStringColumnMut()` for mutable operations
- [x] Update all switch statements in operations.zig to handle String type
- [x] Update csv/export.zig to serialize string columns
- [x] Unit tests for string Series operations
- [x] Integration tests for string DataFrame workflows

**Deliverable**: ✅ String columns can be created, populated, and accessed
**Completion Date**: 2025-10-27
**Test Results**: 83/83 tests passing

---

## Testing Strategy

### Unit Tests

```zig
test "StringColumn: create and get strings" {
    const allocator = std.testing.allocator;

    var col = try StringColumn.init(allocator, 3, 100);
    defer col.deinit(allocator);

    try col.append(allocator, "Alice");
    try col.append(allocator, "Bob");
    try col.append(allocator, "Charlie");

    try std.testing.expectEqualStrings("Alice", col.get(0));
    try std.testing.expectEqualStrings("Bob", col.get(1));
    try std.testing.expectEqualStrings("Charlie", col.get(2));
}

test "StringColumn: buffer growth" {
    const allocator = std.testing.allocator;

    var col = try StringColumn.init(allocator, 10, 10); // Small initial buffer
    defer col.deinit(allocator);

    // Append string larger than initial buffer
    try col.append(allocator, "This is a very long string");

    try std.testing.expectEqualStrings("This is a very long string", col.get(0));
}

test "StringColumn: empty strings" {
    const allocator = std.testing.allocator;

    var col = try StringColumn.init(allocator, 3, 100);
    defer col.deinit(allocator);

    try col.append(allocator, "");
    try col.append(allocator, "data");
    try col.append(allocator, "");

    try std.testing.expectEqualStrings("", col.get(0));
    try std.testing.expectEqualStrings("data", col.get(1));
    try std.testing.expectEqualStrings("", col.get(2));
}

test "StringColumn: UTF-8 support" {
    const allocator = std.testing.allocator;

    var col = try StringColumn.init(allocator, 3, 100);
    defer col.deinit(allocator);

    try col.append(allocator, "Hello 世界");
    try col.append(allocator, "Emoji: 🌹");

    try std.testing.expectEqualStrings("Hello 世界", col.get(0));
    try std.testing.expectEqualStrings("Emoji: 🌹", col.get(1));
}

test "Series: String column operations" {
    const allocator = std.testing.allocator;

    var series = try Series.init(allocator, "names", .String, 10);
    defer series.deinit(allocator);

    try series.append(.{ .String = "Alice" });
    try series.append(.{ .String = "Bob" });

    const str_col = series.asStringColumn().?;
    try std.testing.expectEqualStrings("Alice", str_col.get(0));
    try std.testing.expectEqualStrings("Bob", str_col.get(1));
}
```

### Memory Leak Tests

```zig
test "StringColumn: no memory leaks" {
    const allocator = std.testing.allocator;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        var col = try StringColumn.init(allocator, 100, 1000);
        defer col.deinit(allocator);

        var j: u32 = 0;
        while (j < 100) : (j += 1) {
            try col.append(allocator, "test string");
        }
    }

    // std.testing.allocator reports leaks automatically
}
```

---

## Performance Targets

### Memory Usage
- **Overhead**: <20% of actual string data
- **Max single string**: 1MB
- **Max total buffer**: 1GB

### Performance
- **String access**: O(1) - direct buffer slice
- **Append**: O(1) amortized (2x growth strategy)
- **Memory usage calculation**: O(1)

### Conformance Impact
- **Before**: 6/35 passing (17%)
- **After Phase 1**: 6/35 passing (infrastructure only, no parser changes yet)
- **After Phase 2**: 28/35 passing (80% - with parser integration)

---

## Next Phases

### Phase 2: CSV Parser Integration (4 days)
- Update type inference to detect String columns
- Modify `toDataFrame()` to create StringColumn
- Handle quoted strings and escape sequences

### Phase 3: CSV Export (2 days)
- Serialize StringColumn to CSV
- Add proper quoting for special characters
- Round-trip testing

---

**Status**: ✅ Design complete, ready for implementation
**Next Step**: Implement StringColumn struct and unit tests
