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
    run_conformance.setCwd(b.path(".")); // Run from project root to access testdata/
    const conformance_step = b.step("conformance", "Run RFC 4180 conformance tests from testdata/");
    conformance_step.dependOn(&run_conformance.step);

    // Benchmark executable (ReleaseFast for accurate performance measurements)
    const benchmark = b.addExecutable(.{
        .name = "rozes-benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test/benchmark/main.zig"),
            .target = target,
            .optimize = .ReleaseFast, // Important: use ReleaseFast for benchmarks
        }),
    });
    // Add rozes module as dependency so benchmarks can import DataFrame, etc.
    benchmark.root_module.addImport("rozes", rozes_mod);

    const run_benchmark = b.addRunArtifact(benchmark);
    const benchmark_step = b.step("benchmark", "Run performance benchmarks");
    benchmark_step.dependOn(&run_benchmark.step);

    // Profile join phases executable
    const profile_join = b.addExecutable(.{
        .name = "profile-join",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/profiling_tools/profile_join_phases.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    profile_join.root_module.addImport("rozes", rozes_mod);

    const run_profile_join = b.addRunArtifact(profile_join);
    const profile_join_step = b.step("profile-join", "Profile join operation phases");
    profile_join_step.dependOn(&run_profile_join.step);

    // Note: benchmark-join has been integrated into main benchmark (zig build benchmark)
    // Note: benchmark-parallel-filter integrated into main benchmark (zig build benchmark)
    // Note: radix join benchmark has been integrated into main benchmark (zig build benchmark)
    // The main benchmark now includes both full pipeline join (with CSV overhead)
    // and pure join algorithm performance measurements.

    // Memory tests (Node.js with --expose-gc flag)
    // These are fast automated tests (<5 minutes total) for CI/CD
    const memory_test_step = b.step("memory-test", "Run fast memory leak tests (5 tests, ~5 minutes)");

    const memory_tests = [_][]const u8{
        "src/test/nodejs/memory/gc_verification_test.js",
        "src/test/nodejs/memory/wasm_memory_test.js",
        "src/test/nodejs/memory/error_recovery_test.js",
        "src/test/nodejs/memory/auto_vs_manual_test.js",
        "src/test/nodejs/memory/memory_pressure_test.js",
    };

    for (memory_tests) |test_file| {
        const run_memory_test = b.addSystemCommand(&[_][]const u8{
            "node",
            "--expose-gc", // Required for GC testing
            test_file,
        });
        run_memory_test.setCwd(b.path(".")); // Run from project root
        memory_test_step.dependOn(&run_memory_test.step);
    }

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
    wasm_prod.rdynamic = true; // Required for WASM to export all functions
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
        "--dce", // Dead code elimination
        "--vacuum", // Remove unused names
        "--inline-functions-with-loops", // Aggressive function inlining
        "--optimize-level=4", // Maximum optimization passes
        "--shrink-level=2", // Maximum code shrinking
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
