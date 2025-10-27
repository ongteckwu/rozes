//! Rozes - High-Performance DataFrame Library for the Web
//!
//! Main API entry point for the Rozes DataFrame library.
//! This module exports all public types and functions.
//!
//! Example usage:
//! ```
//! const rozes = @import("rozes.zig");
//!
//! const csv = "name,age,score\nAlice,30,95.5\nBob,25,87.3\n";
//! const df = try rozes.DataFrame.fromCSVBuffer(allocator, csv, .{});
//! defer df.deinit();
//!
//! const age_col = df.column("age").?;
//! const mean_age = try rozes.operations.mean(df, "age");
//! ```

const std = @import("std");

// Core types
pub const types = @import("core/types.zig");
pub const ValueType = types.ValueType;
pub const ColumnDesc = types.ColumnDesc;
pub const CSVOptions = types.CSVOptions;
pub const ParseMode = types.ParseMode;
pub const ParseError = types.ParseError;
pub const ParseErrorType = types.ParseErrorType;
pub const RozesError = types.RozesError;

// Core data structures
pub const series = @import("core/series.zig");
pub const Series = series.Series;
pub const SeriesData = series.SeriesData;
pub const SeriesValue = series.SeriesValue;

pub const dataframe = @import("core/dataframe.zig");
pub const DataFrame = dataframe.DataFrame;
pub const RowRef = dataframe.RowRef;

// CSV parsing
pub const csv = @import("csv/parser.zig");
pub const CSVParser = csv.CSVParser;

// DataFrame operations (to be implemented)
// pub const operations = @import("core/operations.zig");

/// Library version
pub const VERSION = "0.1.0-dev";

/// Prints library information
pub fn printVersion(writer: anytype) !void {
    try writer.print("Rozes DataFrame Library v{s}\n", .{VERSION});
    try writer.print("High-performance columnar data for the web\n", .{});
}

test {
    // Include all module tests
    std.testing.refAllDecls(@This());
    _ = @import("core/types.zig");
    _ = @import("core/series.zig");
    _ = @import("core/dataframe.zig");
    _ = @import("core/operations.zig");
    _ = @import("csv/parser.zig");
    _ = @import("csv/export.zig");

    // Include dedicated test files
    // NOTE: conformance_test.zig uses @embedFile which requires testdata/ to be
    // inside src/ or configured in build.zig. This is pending proper configuration.
    // For now, conformance tests are run manually in the test files themselves.
    // _ = @import("test/unit/csv/conformance_test.zig");
    // _ = @import("test/unit/csv/export_test.zig");  // Temporarily disabled to debug
}
