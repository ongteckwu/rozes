# Rozes Build & Test Scripts

This directory contains automated scripts for building, testing, and releasing Rozes.

---

## Build Scripts

### `build-npm-package.sh`

**Purpose**: Build optimized npm package ready for publishing

**What it does**:
1. Checks prerequisites (Zig, Node.js, wasm-opt)
2. Cleans previous builds
3. Builds WASM module with `ReleaseSmall` optimization
4. Optimizes with wasm-opt (if available)
5. Verifies bundle sizes (WASM + gzipped)
6. Creates npm package tarball (`rozes-{version}.tgz`)
7. Verifies package contents

**Usage**:
```bash
./scripts/build-npm-package.sh
```

**Output**:
- `zig-out/bin/rozes.wasm` - Optimized WASM module (~62KB)
- `rozes-{version}.tgz` - npm package tarball

**Requirements**:
- Zig 0.15.1+
- Node.js 14+
- wasm-opt (optional, for further optimization)

**Example output**:
```
╔══════════════════════════════════════════════════════════╗
║  Build Summary                                           ║
╚══════════════════════════════════════════════════════════╝

  Package:      rozes-1.0.0.tgz
  Version:      1.0.0
  WASM size:    62 KB (35 KB gzipped)
  Package size: 85 KB

✓ Build successful!
```

---

## Test Scripts

### `test-local-package.sh`

**Purpose**: Test npm package in clean environment

**What it does**:
1. Creates temporary test directory
2. Installs package from tarball
3. Verifies package structure (dist/, WASM, etc.)
4. Runs smoke tests (CommonJS, ESM, zero-copy)
5. Runs comprehensive test suite (11 tests)
6. Reports results

**Usage**:
```bash
./scripts/test-local-package.sh [tarball]

# Auto-detect tarball
./scripts/test-local-package.sh

# Explicit tarball
./scripts/test-local-package.sh rozes-1.0.0.tgz
```

**Tests run**:
- CommonJS import (`require('rozes')`)
- ESM import (`import { Rozes }`)
- TypedArray zero-copy access
- RFC 4180 compliance
- Type inference
- Performance (10K rows)
- Memory stress (100 iterations)
- Error handling

**Requirements**:
- Node.js 14+
- Built package tarball

**Example output**:
```
╔══════════════════════════════════════════════════════════╗
║  Test Summary                                            ║
╚══════════════════════════════════════════════════════════╝

  Package:   rozes-1.0.0.tgz
  Test dir:  /tmp/tmp.xyz

✓ All tests passed!
```

---

### `run-all-tests.sh`

**Purpose**: Run complete Rozes test suite

**What it does**:
1. Zig unit tests (461 tests)
2. RFC 4180 conformance tests (125 tests)
3. Benchmark tests (6 benchmarks)
4. Memory leak tests (5 suites, ~5 minutes)
5. WASM build for integration
6. Node.js integration tests

**Usage**:
```bash
# Full test suite
./scripts/run-all-tests.sh

# Quick mode (skip memory tests, saves ~5 min)
./scripts/run-all-tests.sh --quick

# Skip benchmarks
./scripts/run-all-tests.sh --skip-benchmarks
```

**Options**:
- `--quick` - Skip memory tests (saves ~5 minutes)
- `--skip-benchmarks` - Skip benchmark tests

**Requirements**:
- Zig 0.15.1+
- Node.js 14+ (for integration tests)

**Example output**:
```
╔══════════════════════════════════════════════════════════╗
║  Test Summary                                            ║
╚══════════════════════════════════════════════════════════╝

  Total tests:  498
  Passed:       496
  Failed:       2
  Duration:     2m 15s

✓ All tests passed!
```

---

### `verify-bundle-size.sh`

**Purpose**: Verify bundle sizes meet targets

**What it does**:
1. Checks WASM module size (target: 62KB, max: 70KB)
2. Checks gzipped size (target: 35KB, max: 40KB)
3. Checks npm package size (max: 150KB)
4. Reports compliance status

**Usage**:
```bash
./scripts/verify-bundle-size.sh
```

**Targets**:
- WASM uncompressed: 62KB (max 70KB)
- WASM gzipped: 35KB (max 40KB)
- npm package: <150KB

**Requirements**:
- Built WASM module (`zig-out/bin/rozes.wasm`)
- npm package tarball (optional)

**Example output**:
```
WASM Module (uncompressed):
  Size:    62 KB
  Target:  62 KB
  Max:     70 KB
  ✓ At or below target

WASM Module (gzipped):
  Size:    35 KB
  Target:  35 KB
  Max:     40 KB
  ✓ At or below target

npm Package:
  File:    rozes-1.0.0.tgz
  Size:    85 KB
  Max:     150 KB
  ✓ Within maximum

✓ All bundle sizes within targets
```

---

## Workflow Examples

### Full Release Workflow

```bash
# 1. Run complete test suite
./scripts/run-all-tests.sh

# 2. Build npm package
./scripts/build-npm-package.sh

# 3. Verify bundle sizes
./scripts/verify-bundle-size.sh

# 4. Test package locally
./scripts/test-local-package.sh

# 5. Publish (see docs/RELEASE.md)
npm publish
```

### Quick Development Workflow

```bash
# Quick tests + build
./scripts/run-all-tests.sh --quick
./scripts/build-npm-package.sh
./scripts/test-local-package.sh
```

### Pre-Commit Workflow

```bash
# Verify tests pass and bundle size is good
./scripts/run-all-tests.sh --quick --skip-benchmarks
./scripts/verify-bundle-size.sh
```

---

## Exit Codes

All scripts follow standard exit code conventions:

- `0` - Success
- `1` - Failure (tests failed, build error, size exceeded, etc.)

This allows scripts to be used in CI/CD pipelines:

```bash
# Example CI script
./scripts/run-all-tests.sh || exit 1
./scripts/build-npm-package.sh || exit 1
./scripts/verify-bundle-size.sh || exit 1
./scripts/test-local-package.sh || exit 1
```

---

## Troubleshooting

### "Zig not found"
```bash
# Install Zig 0.15.1+
# macOS: brew install zig
# Or download from https://ziglang.org/
```

### "wasm-opt not found"
```bash
# Optional but recommended
npm install -g wasm-opt
```

### "WASM size exceeds target"
```bash
# 1. Check recent code changes
git log --oneline -5

# 2. Try wasm-opt manually
wasm-opt -Oz zig-out/bin/rozes.wasm -o rozes_opt.wasm

# 3. Review build.zig for dead code
```

### "Tests fail in clean environment"
```bash
# Ensure package.json exports are correct
cat package.json | grep exports

# Verify WASM is in tarball
tar -tzf rozes-*.tgz | grep wasm
```

---

## Script Maintenance

When modifying scripts:

1. **Keep exit codes consistent** - Always exit 0 on success, 1 on failure
2. **Add color output** - Use existing color variables for consistency
3. **Test on clean system** - Verify scripts work without local dependencies
4. **Update this README** - Document any new scripts or options
5. **Follow existing patterns** - Match style of existing scripts

---

## Related Documentation

- **[docs/RELEASE.md](../docs/RELEASE.md)** - Complete release process
- **[CLAUDE.md](../CLAUDE.md)** - Project guidelines
- **[docs/TODO.md](../docs/TODO.md)** - Development roadmap
- **[README.md](../README.md)** - Project overview

---

**Last Updated**: 2025-11-01
