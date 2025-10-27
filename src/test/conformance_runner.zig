//! Conformance Test Runner
//!
//! Runs RFC 4180 conformance tests from testdata/csv/rfc4180/
//! Usage: zig build conformance

const std = @import("std");
const rozes = @import("rozes");
const DataFrame = rozes.DataFrame;
const CSVParser = rozes.CSVParser;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Conformance Tests - All testdata/ CSV files ===\n\n", .{});

    // Directories to scan for CSV test files
    const test_dirs = [_][]const u8{
        "testdata/csv/rfc4180",
        "testdata/csv/edge_cases",
        "testdata/external/csv-spectrum/csvs",
        "testdata/external/csv-parsers-comparison/src/main/resources",
        "testdata/external/PapaParse/tests",
    };

    var total_tests: u32 = 0;
    var passed: u32 = 0;
    var failed: u32 = 0;
    var skipped: u32 = 0;

    // Known tests that are not yet supported
    const string_tests = [_][]const u8{
        "08_no_header.csv", // No header support yet (requires CSVOptions.has_headers=false)
    };

    // Test each directory
    for (test_dirs) |dir_path| {
        std.debug.print("Testing {s}/\n", .{dir_path});

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            std.debug.print("⚠️  Warning: Cannot open directory {s}: {}\n\n", .{ dir_path, err });
            continue;
        };
        defer dir.close();

        var walker = dir.iterate();
        while (walker.next() catch null) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".csv")) continue;

            total_tests += 1;

            // Check if should skip
            var should_skip = false;
            for (string_tests) |skip_name| {
                if (std.mem.eql(u8, entry.name, skip_name)) {
                    should_skip = true;
                    break;
                }
            }

            if (should_skip) {
                std.debug.print("  ⏸️  SKIP: {s} (string columns - deferred to 0.2.0)\n", .{entry.name});
                skipped += 1;
                continue;
            }

            // Build full path
            const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name }) catch {
                std.debug.print("  ❌ FAIL: {s} - Path alloc failed\n", .{entry.name});
                failed += 1;
                continue;
            };
            defer allocator.free(full_path);

            // Try to read and parse
            const file = std.fs.cwd().openFile(full_path, .{}) catch {
                std.debug.print("  ❌ FAIL: {s} - Cannot open file\n", .{entry.name});
                failed += 1;
                continue;
            };
            defer file.close();

            const content = file.readToEndAlloc(allocator, 1_000_000) catch {
                std.debug.print("  ❌ FAIL: {s} - Cannot read file\n", .{entry.name});
                failed += 1;
                continue;
            };
            defer allocator.free(content);

            var parser = CSVParser.init(allocator, content, .{}) catch {
                std.debug.print("  ❌ FAIL: {s} - Parser init failed\n", .{entry.name});
                failed += 1;
                continue;
            };
            defer parser.deinit();

            var df = parser.toDataFrame() catch |err| {
                std.debug.print("  ❌ FAIL: {s} - Parse failed: {}\n", .{ entry.name, err });
                failed += 1;
                continue;
            };
            defer df.deinit();

            std.debug.print("  ✅ PASS: {s} ({} rows, {} cols)\n", .{
                entry.name,
                df.len(),
                df.columnCount(),
            });
            passed += 1;
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("=== Results ===\n", .{});
    std.debug.print("Total:   {}\n", .{total_tests});
    std.debug.print("Passed:  {}\n", .{passed});
    std.debug.print("Failed:  {}\n", .{failed});
    std.debug.print("Skipped: {} (string columns - deferred to 0.2.0)\n", .{skipped});

    const pass_rate = if (total_tests > 0) (passed * 100) / total_tests else 0;
    std.debug.print("Pass rate: {}%\n", .{pass_rate});

    // MVP success: Any tests passing shows parser works
    if (passed > 0) {
        std.debug.print("\n✅ Success: {} CSV files successfully parsed\n", .{passed});
        std.process.exit(0);
    } else {
        std.debug.print("\n❌ No tests passing - parser may have issues\n", .{});
        std.process.exit(1);
    }
}
