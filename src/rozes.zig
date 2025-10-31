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
pub const SortOrder = dataframe.SortOrder;
pub const SortSpec = dataframe.SortSpec;
pub const GroupBy = dataframe.GroupBy;
pub const AggFunc = dataframe.AggFunc;
pub const AggSpec = dataframe.AggSpec;
pub const Summary = dataframe.Summary;

// DataFrame operations
pub const sort = @import("core/sort.zig");
pub const operations = @import("core/operations.zig");
pub const reshape = @import("core/reshape.zig");
pub const PivotOptions = reshape.PivotOptions;
pub const MeltOptions = reshape.MeltOptions;
pub const StackOptions = reshape.StackOptions;
pub const UnstackOptions = reshape.UnstackOptions;

pub const combine = @import("core/combine.zig");
pub const ConcatOptions = combine.ConcatOptions;
pub const ConcatAxis = combine.ConcatAxis;
pub const MergeOptions = combine.MergeOptions;
pub const MergeHow = combine.MergeHow;
pub const AppendOptions = combine.AppendOptions;
pub const UpdateOptions = combine.UpdateOptions;

// Functional operations
pub const functional = @import("core/functional.zig");
pub const ApplyOptions = functional.ApplyOptions;
pub const ApplyAxis = functional.ApplyAxis;

// CSV parsing
pub const csv = @import("csv/parser.zig");
pub const CSVParser = csv.CSVParser;

// JSON parsing
pub const json = @import("json/parser.zig");
pub const JSONParser = json.JSONParser;
pub const JSONFormat = json.JSONFormat;
pub const JSONOptions = json.JSONOptions;

// SIMD utilities
pub const simd = @import("core/simd.zig");

// Error utilities
pub const error_utils = @import("core/error_utils.zig");

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
    _ = @import("core/sort.zig");
    _ = @import("core/simd.zig");
    _ = @import("core/reshape.zig");
    _ = @import("core/combine.zig");
    _ = @import("core/functional.zig");
    _ = @import("core/error_utils.zig");
    _ = @import("csv/parser.zig");
    _ = @import("csv/export.zig");
    _ = @import("json/parser.zig");

    // Include dedicated test files
    _ = @import("test/unit/core/sort_test.zig");
    _ = @import("test/unit/core/groupby_test.zig");
    _ = @import("test/unit/core/join_test.zig");
    _ = @import("test/unit/core/additional_ops_test.zig");
    _ = @import("test/unit/core/reshape_test.zig");
    _ = @import("test/unit/core/combine_test.zig");
    _ = @import("test/unit/core/append_update_test.zig");
    _ = @import("test/unit/core/functional_test.zig");

    // New comprehensive test files (added 2025-10-28)
    _ = @import("test/unit/core/operations_test.zig");
    _ = @import("test/unit/core/dataframe_test.zig");
    _ = @import("test/unit/core/column_index_test.zig"); // Column HashMap O(1) lookup tests
    _ = @import("test/unit/core/series_test.zig");
    _ = @import("test/unit/core/convenience_test.zig"); // Convenience methods (sample, info, unique, nunique) - added 2025-10-31

    // JSON parser tests (added 2025-10-30, Phase 1: NDJSON)
    _ = @import("test/unit/json/parser_test.zig");
    _ = @import("test/unit/json/parser_edge_cases_test.zig"); // Edge case tests (added 2025-10-30)

    // Stats module edge case tests (added 2025-10-30)
    _ = @import("test/unit/core/stats_edge_cases_test.zig");

    // NOTE: conformance_test.zig uses @embedFile which requires testdata/ to be
    // inside src/ or configured in build.zig. This is pending proper configuration.
    // For now, conformance tests are run manually in the test files themselves.
    // _ = @import("test/unit/csv/conformance_test.zig");
    // _ = @import("test/unit/csv/export_test.zig");  // Temporarily disabled to debug
}
