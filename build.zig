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

    // Conformance tests (reads files from testdata/)
    const conformance_module = b.createModule(.{
        .root_source_file = b.path("src/test/conformance_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Add rozes module as dependency so we can import DataFrame, CSVParser
    conformance_module.addImport("rozes", rozes_mod);

    const conformance = b.addExecutable(.{
        .name = "conformance-runner",
        .root_module = conformance_module,
    });

    const run_conformance = b.addRunArtifact(conformance);
    const conformance_step = b.step("conformance", "Run RFC 4180 conformance tests from testdata/");
    conformance_step.dependOn(&run_conformance.step);

    // Wasm build for browser
    // Using wasi instead of freestanding to get POSIX-like APIs (needed for ArenaAllocator)
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });

    // Development build: Debug mode, keep all assertions and logging
    const wasm_dev = b.addExecutable(.{
        .name = "rozes-dev",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm.zig"),
            .target = wasm_target,
            .optimize = .Debug,
        }),
    });
    wasm_dev.entry = .disabled;
    wasm_dev.rdynamic = true;
    wasm_dev.export_memory = true;
    wasm_dev.import_memory = false;

    const wasm_dev_install = b.addInstallArtifact(wasm_dev, .{});
    const wasm_dev_step = b.step("wasm-dev", "Build WebAssembly module (development)");
    wasm_dev_step.dependOn(&wasm_dev_install.step);

    // Production build: ReleaseSmall, with wasm-opt optimization
    const wasm_prod = b.addExecutable(.{
        .name = "rozes",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
        }),
    });
    wasm_prod.entry = .disabled;
    wasm_prod.rdynamic = true;
    wasm_prod.export_memory = true;
    wasm_prod.import_memory = false;

    const wasm_prod_install = b.addInstallArtifact(wasm_prod, .{});

    // Run wasm-opt for additional size optimization
    const wasm_opt = b.addSystemCommand(&[_][]const u8{
        "wasm-opt",
        "-Oz", // Maximum size optimization
        "--enable-bulk-memory", // Required for Zig WASM output
        "--strip-debug", // Remove debug sections
        "--strip-producers", // Remove producers section
        "--strip-dwarf", // Remove DWARF debug info
        "--converge", // Run optimization passes until no more gains
        "-o",
    });
    wasm_opt.addFileArg(b.path("zig-out/bin/rozes.wasm"));
    wasm_opt.addFileArg(b.path("zig-out/bin/rozes.wasm"));
    wasm_opt.step.dependOn(&wasm_prod_install.step);

    // Default "wasm" step builds production version
    const wasm_step = b.step("wasm", "Build WebAssembly module (production, optimized)");
    wasm_step.dependOn(&wasm_opt.step);

    // Install step (for compatibility)
    b.installArtifact(wasm_prod);
}
