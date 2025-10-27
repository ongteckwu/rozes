const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create exe for testing purposes (simplest approach)
    const exe = b.addExecutable(.{
        .name = "rejax",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/benchmark/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    // Tests
    const tests = b.addTest(.{
        .name = "rejax-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/regex.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
