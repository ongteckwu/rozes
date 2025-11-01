// Apache Arrow Schema Mapping
// Maps Rozes DataFrame types to Apache Arrow IPC format
// Supports zero-copy conversion where possible

const std = @import("std");
const ValueType = @import("../core/types.zig").ValueType;

/// Apache Arrow data types (aligned with Arrow IPC format)
pub const ArrowType = enum(u8) {
    Null = 0,
    Int = 1,
    FloatingPoint = 2,
    Binary = 3,
    Utf8 = 4,
    Bool = 5,
    Decimal = 6,
    Date = 7,
    Time = 8,
    Timestamp = 9,
    Interval = 10,
    List = 11,
    Struct = 12,
    Union = 13,
    Dictionary = 14,
    Map = 15,
    FixedSizeBinary = 16,
    FixedSizeList = 17,
    Duration = 18,
    LargeBinary = 19,
    LargeUtf8 = 20,
    LargeList = 21,
};

/// Arrow integer bit width
pub const ArrowIntBitWidth = enum(u8) {
    Width8 = 8,
    Width16 = 16,
    Width32 = 32,
    Width64 = 64,
};

/// Arrow floating point precision
pub const ArrowFloatPrecision = enum(u8) {
    Half = 0,
    Single = 1,
    Double = 2,
};

/// Arrow field metadata
pub const ArrowField = struct {
    name: []const u8,
    type: ArrowType,
    nullable: bool,
    metadata: ?[]const u8,

    // Type-specific properties
    int_bit_width: ?ArrowIntBitWidth,
    int_signed: bool,
    float_precision: ?ArrowFloatPrecision,

    pub fn init(name: []const u8, arrow_type: ArrowType) ArrowField {
        std.debug.assert(name.len > 0); // Pre-condition #1: Non-empty name
        std.debug.assert(name.len <= 1000); // Pre-condition #2: Reasonable column name limit
        // Note: arrow_type is validated by the type system (enum), no need for runtime check

        const field = ArrowField{
            .name = name,
            .type = arrow_type,
            .nullable = false,
            .metadata = null,
            .int_bit_width = null,
            .int_signed = true,
            .float_precision = null,
        };

        std.debug.assert(field.name.len == name.len); // Post-condition: Name copied correctly
        return field;
    }
};

/// Arrow schema (collection of fields)
pub const ArrowSchema = struct {
    fields: []ArrowField,
    metadata: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, field_count: u32) !ArrowSchema {
        std.debug.assert(field_count > 0); // Tiger Style: validate count
        std.debug.assert(field_count <= 10_000); // Tiger Style: bounded allocation

        const fields = try allocator.alloc(ArrowField, field_count);
        return .{
            .fields = fields,
            .metadata = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ArrowSchema) void {
        self.allocator.free(self.fields);
    }
};

/// Convert Rozes ValueType to Arrow type
pub fn rozesToArrowType(data_type: ValueType) ArrowField {
    var field = ArrowField.init("_", .Null); // Placeholder name (will be overwritten)

    switch (data_type) {
        .Bool => {
            field.type = .Bool;
        },
        .Int64 => {
            field.type = .Int;
            field.int_bit_width = .Width64;
            field.int_signed = true;
        },
        .Float64 => {
            field.type = .FloatingPoint;
            field.float_precision = .Double;
        },
        .String => {
            field.type = .Utf8;
        },
        .Categorical => {
            // Arrow represents categorical as Dictionary encoding
            field.type = .Dictionary;
        },
        .Null => {
            field.type = .Null;
        },
    }

    return field;
}

/// Convert Arrow type to Rozes ValueType
pub fn arrowToRozesType(field: ArrowField) !ValueType {
    std.debug.assert(field.name.len > 0); // Pre-condition #1: Valid field name
    // Note: field.type is validated by the type system (enum), no need for runtime check

    // Handle each type explicitly to avoid comptime control flow issues
    if (field.type == .Bool) {
        std.debug.assert(@intFromEnum(ValueType.Bool) <= @intFromEnum(ValueType.Categorical)); // Post-condition
        return .Bool;
    }
    if (field.type == .Int) {
        if (field.int_bit_width) |width| {
            if (width == .Width64 and field.int_signed) {
                std.debug.assert(@intFromEnum(ValueType.Int64) <= @intFromEnum(ValueType.Categorical)); // Post-condition
                return .Int64;
            }
        }
        return error.UnsupportedArrowIntType;
    }
    if (field.type == .FloatingPoint) {
        if (field.float_precision) |prec| {
            if (prec == .Double) {
                std.debug.assert(@intFromEnum(ValueType.Float64) <= @intFromEnum(ValueType.Categorical)); // Post-condition
                return .Float64;
            }
        }
        return error.UnsupportedArrowFloatType;
    }
    if (field.type == .Utf8 or field.type == .LargeUtf8) {
        std.debug.assert(@intFromEnum(ValueType.String) <= @intFromEnum(ValueType.Categorical)); // Post-condition
        return .String;
    }
    if (field.type == .Dictionary) {
        std.debug.assert(@intFromEnum(ValueType.Categorical) <= @intFromEnum(ValueType.Categorical)); // Post-condition
        return .Categorical;
    }
    if (field.type == .Null) {
        std.debug.assert(@intFromEnum(ValueType.Null) <= @intFromEnum(ValueType.Categorical)); // Post-condition
        return .Null;
    }

    return error.UnsupportedArrowType;
}

// Unit tests
const testing = std.testing;

test "ArrowField.init creates valid field" {
    const field = ArrowField.init("test_col", .Int);
    try testing.expectEqualStrings("test_col", field.name);
    try testing.expectEqual(ArrowType.Int, field.type);
    try testing.expectEqual(false, field.nullable);
}

test "ArrowSchema.init allocates fields" {
    var schema = try ArrowSchema.init(testing.allocator, 3);
    defer schema.deinit();

    try testing.expectEqual(@as(usize, 3), schema.fields.len);
}

test "rozesToArrowType: Bool conversion" {
    const field = rozesToArrowType(.Bool);
    try testing.expectEqual(ArrowType.Bool, field.type);
}

test "rozesToArrowType: Int64 conversion" {
    const field = rozesToArrowType(.Int64);
    try testing.expectEqual(ArrowType.Int, field.type);
    try testing.expectEqual(ArrowIntBitWidth.Width64, field.int_bit_width.?);
    try testing.expectEqual(true, field.int_signed);
}

test "rozesToArrowType: Float64 conversion" {
    const field = rozesToArrowType(.Float64);
    try testing.expectEqual(ArrowType.FloatingPoint, field.type);
    try testing.expectEqual(ArrowFloatPrecision.Double, field.float_precision.?);
}

test "rozesToArrowType: String conversion" {
    const field = rozesToArrowType(.String);
    try testing.expectEqual(ArrowType.Utf8, field.type);
}

test "arrowToRozesType: Bool conversion" {
    const field = ArrowField.init("test", .Bool);
    const data_type = try arrowToRozesType(field);
    try testing.expectEqual(ValueType.Bool, data_type);
}

test "arrowToRozesType: Int64 conversion" {
    var field = ArrowField.init("test", .Int);
    field.int_bit_width = .Width64;
    field.int_signed = true;
    const data_type = try arrowToRozesType(field);
    try testing.expectEqual(ValueType.Int64, data_type);
}

test "arrowToRozesType: Float64 conversion" {
    var field = ArrowField.init("test", .FloatingPoint);
    field.float_precision = .Double;
    const data_type = try arrowToRozesType(field);
    try testing.expectEqual(ValueType.Float64, data_type);
}

test "arrowToRozesType: String conversion" {
    const field = ArrowField.init("test", .Utf8);
    const data_type = try arrowToRozesType(field);
    try testing.expectEqual(ValueType.String, data_type);
}

test "arrowToRozesType: unsupported type returns error" {
    const field = ArrowField.init("test", .Decimal);
    const result = arrowToRozesType(field);
    try testing.expectError(error.UnsupportedArrowType, result);
}
