const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create Rozes module
    const rozes_mod = b.addModule("rozes", .{
        .root_source_file = b.path("src/rozes.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Tests for the main module
    const tests = b.addTest(.{
        .name = "rozes-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/rozes.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_tests.step);

    // Wasm build for browser
    const wasm = b.addExecutable(.{
        .name = "rozes",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/rozes.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            }),
            .optimize = .ReleaseSmall,
        }),
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;

    const wasm_install = b.addInstallArtifact(wasm, .{});
    const wasm_step = b.step("wasm", "Build WebAssembly module");
    wasm_step.dependOn(&wasm_install.step);

    // Install step
    b.installArtifact(wasm);

    _ = rozes_mod;
}
