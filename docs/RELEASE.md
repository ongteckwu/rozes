# Rozes Release Process

**Last Updated**: 2025-11-01
**Current Version**: 1.1.x (in development)
**Target Version**: 1.2.0

This document outlines the human-intervention steps required to publish Rozes to npm after automated builds complete.

---

## Quick Reference: Build & Test Scripts

| Task                       | Script                                  | Output                    |
| -------------------------- | --------------------------------------- | ------------------------- |
| **Build npm package**      | `./scripts/build-npm-package.sh`        | `rozes-{version}.tgz`     |
| **Test local package**     | `./scripts/test-local-package.sh`       | Comprehensive verification|
| **Run all tests**          | `./scripts/run-all-tests.sh`            | Complete test suite       |
| **Verify bundle size**     | `./scripts/verify-bundle-size.sh`       | Size compliance check     |
| Build WASM module          | `zig build -Doptimize=ReleaseSmall`     | `zig-out/bin/rozes.wasm`  |
| Run Zig tests              | `zig build test`                        | 461/463 tests             |
| Run conformance tests      | `zig build conformance`                 | 125/125 RFC 4180 tests    |
| Run benchmarks             | `zig build benchmark`                   | 6/6 benchmarks            |
| Run memory tests           | `zig build memory-test`                 | 5 test suites             |
| Test Node.js integration   | `node examples/node/test_bundled_package.js` | 11 comprehensive tests |
| Compare vs competitors     | `node src/test/benchmark/compare_js.js` | Papa Parse comparison     |

**Test Files Included**:

**Node.js**:
- `examples/node/basic.js` - Basic usage example (CommonJS)
- `examples/node/basic_esm.mjs` - Basic usage example (ESM)
- `examples/node/auto_cleanup_examples.js` - Automatic cleanup demos
- `examples/node/operations.js` - DataFrame operations demo
- `src/test/benchmark/compare_js.js` - Performance comparison vs Papa Parse

**Browser**:
- `src/test/browser/index.html` - Interactive test runner
- `src/test/browser/tests.js` - Browser test suite (17 tests)

---

## Prerequisites

Before starting the release process, ensure:

- ✅ All tests pass (`zig build test` - 461/463 tests, 99.6%)
- ✅ Conformance tests pass (`zig build conformance` - 125/125, 100%)
- ✅ Benchmarks pass (`zig build benchmark` - 6/6 passing)
- ✅ Memory tests pass (`zig build memory-test` - 4/5 suites passing)
- ✅ Documentation updated (README, CHANGELOG, TODO)
- ✅ Version numbers bumped in all relevant files
- ✅ **Local testing complete** (Node.js + browser)

**Pre-Release Checklist**:

```bash
# 1. Run complete test suite
./scripts/run-all-tests.sh

# 2. Build npm package
./scripts/build-npm-package.sh

# 3. Verify bundle sizes
./scripts/verify-bundle-size.sh

# 4. Test package locally
./scripts/test-local-package.sh

# 5. Check version consistency
grep -r "version" package.json README.md docs/CHANGELOG.md
```

---

## Phase 1: npm Distribution

### 1.0 Build Package Locally

Use the automated build script:

```bash
# Build npm package with automatic verification
./scripts/build-npm-package.sh

# This script automatically:
# 1. Checks prerequisites (Zig, Node.js, wasm-opt)
# 2. Cleans previous builds
# 3. Builds optimized WASM module
# 4. Optimizes with wasm-opt (if available)
# 5. Verifies gzipped size
# 6. Creates npm package tarball
# 7. Verifies package contents

# Expected output:
# - WASM size: ~62KB (target: <70KB)
# - Gzipped: ~35KB (target: <40KB)
# - Package: rozes-{version}.tgz
```

**Output**: Tarball `rozes-{version}.tgz` in project root

**Manual Build** (if script unavailable):

```bash
zig build -Doptimize=ReleaseSmall
npm pack
```

### 1.1 Test Package Locally

**CRITICAL**: Test the package in a clean environment to verify bundled WASM works.

**Automated Testing** (recommended):

```bash
# Run comprehensive package verification
./scripts/test-local-package.sh

# This script automatically:
# 1. Creates clean test environment
# 2. Installs package from tarball
# 3. Verifies package structure
# 4. Runs smoke tests (CommonJS, ESM, zero-copy)
# 5. Runs comprehensive test suite
# 6. Reports results

# Expected: All tests pass (11/11 in comprehensive suite)
```

**Manual Testing** (if script unavailable):

```bash
# Create test directory
mkdir -p /tmp/rozes-test
cd /tmp/rozes-test

# Install from local tarball
npm init -y
npm install /path/to/rozes/rozes-*.tgz

# Run basic smoke test
node -e "
const { Rozes } = require('rozes');
Rozes.init().then(rozes => {
  const df = rozes.DataFrame.fromCSV('name,age\\nAlice,30\\nBob,25');
  console.log('Shape:', df.shape);
  console.log('Columns:', df.columns);
  console.log('✅ Basic test passed');
});
"

# Test ESM import
node -e "
import('rozes').then(({ Rozes }) => {
  return Rozes.init();
}).then(rozes => {
  const df = rozes.DataFrame.fromCSV('name,age\\nAlice,30\\nBob,25');
  console.log('Shape:', df.shape);
  console.log('✅ ESM test passed');
});
"

# Test TypeScript definitions
cat > test.ts << EOF
import { Rozes, DataFrame } from 'rozes';

async function test() {
  const rozes = await Rozes.init();
  const df: DataFrame = rozes.DataFrame.fromCSV('name,age\nAlice,30');
  const shape = df.shape;
  const ages = df.column('age');
  // Memory automatically managed
}
test();
EOF

# Compile TypeScript (if tsc installed)
npx tsc --noEmit test.ts
# Should compile without errors

# Cleanup
cd /path/to/rozes
rm -rf /tmp/rozes-test
```

**What to verify**:
- ✅ Installation completes without errors
- ✅ CommonJS `require('rozes')` works
- ✅ ESM `import { Rozes } from 'rozes'` works
- ✅ TypeScript definitions load correctly
- ✅ WASM module loads and executes
- ✅ No "module not found" errors

**If tests fail**: Check `dist/` directory structure and `package.json` exports

### 1.2 Publish to npm (Test Run)

First, publish with a beta tag to verify the process:

```bash
# Login to npm
npm login

# Publish with beta tag
npm publish --tag beta

# Test installation from npm
mkdir -p /tmp/npm-test
cd /tmp/npm-test
npm init -y
npm install rozes@beta

# Run smoke test
node -e "
const { Rozes } = require('rozes');
Rozes.init().then(rozes => {
  const df = rozes.DataFrame.fromCSV('name,age\\nAlice,30');
  console.log('✅ npm beta test passed');
});
"

# Cleanup
cd /path/to/rozes
rm -rf /tmp/npm-test
```

### 1.3 Publish to npm (Production)

**⚠️ WARNING**: This step is irreversible. Once published, versions cannot be deleted.

```bash
# Final pre-publish checklist
# 1. All tests pass (zig build test)
# 2. Benchmarks pass (zig build benchmark)
# 3. README.md updated with correct version
# 4. CHANGELOG.md has release notes
# 5. package.json version bumped

# Publish to production
npm publish

# Verify installation
npm view rozes

# Test installation
npm install rozes
node -e "
const { Rozes } = require('rozes');
Rozes.init().then(rozes => {
  console.log('✅ Production package works');
});
"
```

### 1.4 Add npm Tags

Set appropriate dist-tags:

```bash
# Mark as latest stable release
npm dist-tag add rozes@{version} latest

# For pre-releases (optional)
# npm dist-tag add rozes@{version} next

# Verify tags
npm dist-tag ls rozes
```

---

## Phase 2: GitHub Release

### 2.1 Create Git Tag

```bash
# Create annotated tag
git tag -a v{version} -m "Release {version} - {Brief Description}"

# Example:
git tag -a v1.2.0 -m "Release 1.2.0 - Advanced Optimizations (SIMD, Radix Join, Parallel Processing)"

# Push tag to remote
git push origin v{version}
```

### 2.2 Create GitHub Release

Go to https://github.com/yourusername/rozes/releases/new and:

1. **Tag**: Select `v{version}`
2. **Title**: `v{version} - {Brief Description}`
3. **Description**: Include the following sections:

```markdown
## 🌹 Rozes {version} - {Brief Description}

After [X weeks] of development, Rozes {version} brings [key highlights]!

### ✨ Highlights

- **Feature 1**: Description (e.g., 2-5× speedup)
- **Feature 2**: Description
- **Feature 3**: Description
- **[X] new optimizations** across [Y] categories

### 📦 Installation

**npm**:
```bash
npm install rozes
```

**Zig** (build.zig.zon):
```zig
.dependencies = .{
    .rozes = .{
        .url = "https://github.com/yourusername/rozes/archive/v{version}.tar.gz",
        .hash = "...",
    },
},
```

### 🚀 Quick Start

**Node.js**:
```javascript
const { Rozes } = require('rozes');

const rozes = await Rozes.init();
const df = rozes.DataFrame.fromCSV("name,age\nAlice,30\nBob,25");

console.log(df.shape);  // { rows: 2, cols: 2 }
const ages = df.column('age');  // Float64Array [30, 25]
// Memory automatically managed
```

**Zig**:
```zig
const DataFrame = @import("rozes").DataFrame;

var df = try DataFrame.fromCSVBuffer(allocator, csv, .{});
defer df.free();

std.debug.print("Rows: {}\n", .{df.rowCount});
```

### 📊 What's New

- Feature 1 implementation details
- Feature 2 implementation details
- Performance improvements: X% faster on Y operation
- Bundle size: XKB → YKB (Z% reduction/increase)
- Test coverage: X/Y tests (Z%)

### 📈 Performance Benchmarks

| Operation       | Dataset   | Time    | vs Previous | vs Target |
|-----------------|-----------|---------|-------------|-----------|
| CSV Parse       | 1M rows   | XXXms   | +X%         | -Y%       |
| Filter          | 1M rows   | XXms    | +X%         | -Y%       |
| Sort            | 100K rows | XXms    | +X%         | -Y%       |
| GroupBy         | 100K rows | Xms     | +X%         | -Y%       |
| Join            | 10K×10K   | XXms    | +X%         | -Y%       |

### 🔗 Links

- [Changelog](https://github.com/yourusername/rozes/blob/main/docs/CHANGELOG.md)
- [API Documentation](https://github.com/yourusername/rozes/blob/main/docs/NODEJS_API.md)
- [Migration Guide](https://github.com/yourusername/rozes/blob/main/docs/MIGRATION.md)
- [TODO & Roadmap](https://github.com/yourusername/rozes/blob/main/docs/TODO.md)

### 🙏 Acknowledgments

Built with Zig 0.15.1+ following Tiger Style principles.

---

**Full Changelog**: https://github.com/yourusername/rozes/compare/v{prev_version}...v{version}
```

4. **Attach Binaries**: Upload the following artifacts:
   - `rozes-{version}.tgz` - npm package
   - `rozes.wasm` - Standalone WASM module
   - `SHA256SUMS.txt` - Checksums file

5. **Publish Release**

---

## Phase 3: Post-Release Tasks

### 3.1 Update Documentation Sites

If you have a documentation site (e.g., GitHub Pages):

1. Trigger documentation rebuild for new version
2. Update "latest" symlink to point to new version
3. Verify all examples work with new version
4. Update API reference if changes were made

### 3.2 Announce Release

Post announcements on:

- [ ] Project README (update version badge)
- [ ] GitHub Discussions (release announcement thread)
- [ ] Twitter/X (if applicable)
- [ ] Reddit (r/programming, r/javascript, r/zig - if applicable)
- [ ] Hacker News (Show HN: if applicable)
- [ ] Dev.to / Hashnode (blog post if applicable)

**Example Announcement Template**:

```
🌹 Rozes {version} is out!

{Brief description of key features}

🚀 Performance:
- [Key benchmark improvement]

📦 Bundle size: {size}KB ({compressed}KB gzipped)

✅ Tests: {passing}/{total} ({percentage}%)

Try it: npm install rozes

Docs: {link}
Changelog: {link}
```

### 3.3 Monitor Initial Feedback

For the first 48 hours after release:

- [ ] Monitor npm download stats: https://www.npmjs.com/package/rozes
- [ ] Watch GitHub issues for installation problems
- [ ] Check CI/CD for any platform-specific failures
- [ ] Respond to user questions promptly
- [ ] Monitor bundle size in the wild (bundlephobia.com)

### 3.4 Prepare Hotfix Plan

If critical bugs are discovered:

1. **Severity Assessment**: Determine if hotfix release ({version}.1) is needed
2. **Branch Strategy**: Create `hotfix/{version}.1` branch from `v{version}` tag
3. **Fix & Test**: Apply minimal fix, verify all tests pass
4. **Release**: Follow abbreviated release process (no major announcement needed)

---

## Troubleshooting

### Common Issues During Testing

#### npm Package Issues

**Problem**: `Error: Cannot find module 'rozes'` after installing package

**Solution**:
```bash
# Check if package was installed correctly
npm list rozes

# Verify package structure
tar -tzf rozes-*.tgz | grep -E "(dist/|wasm)"
# Should see:
# - package/dist/index.js
# - package/dist/index.mjs
# - package/dist/index.d.ts
# - package/zig-out/bin/rozes.wasm

# Reinstall package
npm uninstall rozes
npm install rozes
```

**Problem**: `TypeError: Rozes.init is not a function`

**Solution**:
```bash
# Check if you're using the correct import syntax
# CommonJS:
const { Rozes } = require('rozes');

# ESM:
import { Rozes } from 'rozes';

# Verify dist/ files exist
ls -lh node_modules/rozes/dist/
```

**Problem**: `RuntimeError: Aborted(CompileError: WebAssembly.compile(): expected magic word)`

**Solution**:
```bash
# WASM file may be corrupted
# Verify WASM file integrity
file zig-out/bin/rozes.wasm
# Should show: WebAssembly (wasm) binary module

# Check WASM file size
ls -lh zig-out/bin/rozes.wasm
# Should be ~62KB

# Rebuild WASM
zig build -Doptimize=ReleaseSmall
npm pack
```

#### TypeScript Issues

**Problem**: `Cannot find module 'rozes' or its corresponding type declarations`

**Solution**:
```bash
# Verify TypeScript definitions exist
ls -lh node_modules/rozes/dist/index.d.ts

# Check package.json exports
cat node_modules/rozes/package.json | grep types
# Should show: "types": "./dist/index.d.ts"

# Reinstall with types
npm install rozes
```

### Build Issues

**Problem**: `zig build` fails with "out of memory"

**Solution**:
```bash
# Use release build (less memory)
zig build -Doptimize=ReleaseSmall

# Or increase memory limit (if using Node.js build tools)
NODE_OPTIONS="--max-old-space-size=4096" zig build
```

**Problem**: Bundle size exceeds 70KB target

**Solution**:
```bash
# Apply wasm-opt optimization
wasm-opt -Oz zig-out/bin/rozes.wasm -o zig-out/bin/rozes_opt.wasm

# Verify size reduction
ls -lh zig-out/bin/rozes*.wasm

# Check for dead code
zig build -Doptimize=ReleaseSmall --verbose
```

### Platform-Specific Issues

**macOS**: If package build includes Homebrew paths:

```bash
# Rozes uses only Zig stdlib (no external deps)
# Should not reference Homebrew

# Verify no Homebrew dependencies
otool -L zig-out/bin/rozes.wasm
# (Not applicable to WASM, but useful for native builds)
```

**Linux**: If WASM build fails:

```bash
# Ensure Zig 0.15.1+ is installed
zig version
# Should be 0.15.1 or higher

# Clean build
rm -rf zig-out zig-cache
zig build -Doptimize=ReleaseSmall
```

**Windows**: If Node.js tests fail:

```bash
# Use WSL or Git Bash for testing
# Rozes WASM works cross-platform, but test scripts may need adjustment
```

---

## Rollback Plan

If catastrophic issues are discovered immediately after release:

### npm Rollback (Limited)

⚠️ **npm does not allow deleting releases**. Instead:

1. **Deprecate Release**: Mark version as deprecated (prevents new installs)
   ```bash
   npm deprecate rozes@{version} "Critical bug, use {version+1} instead"
   ```

2. **Publish Hotfix**: Release {version}.1 with fixes ASAP
   ```bash
   # Fix bug, bump version to {version}.1
   npm publish
   npm dist-tag add rozes@{version}.1 latest
   ```

3. **Unpublish** (only within 72 hours):
   ```bash
   # Only works within 72 hours of publish
   npm unpublish rozes@{version}
   ```

### GitHub Release Rollback

1. Mark release as "Pre-release" or delete it
2. Delete git tag locally and remotely:
   ```bash
   git tag -d v{version}
   git push origin :refs/tags/v{version}
   ```

---

## Checklist: Pre-Release

Before starting the release process, verify:

- [ ] All tests pass (`zig build test` - target 99%+)
- [ ] Conformance tests pass (`zig build conformance` - target 100%)
- [ ] Benchmarks pass (`zig build benchmark` - all green)
- [ ] Memory tests pass (`zig build memory-test` - 4/5 suites)
- [ ] Documentation updated (README, CHANGELOG, TODO)
- [ ] Version bumped in all files (package.json, README.md, CHANGELOG.md)
- [ ] CHANGELOG.md has {version} entry with release notes
- [ ] Migration guide updated (if API changed)
- [ ] Examples tested with new version
- [ ] Bundle size verified (<70KB target)
- [ ] CI/CD pipeline green
- [ ] Clean git status (all changes committed)

---

## Checklist: Post-Release

After publishing to npm and GitHub:

- [ ] npm release published
- [ ] GitHub release created with tag v{version}
- [ ] Release notes written
- [ ] Binaries attached to GitHub release
- [ ] Documentation site updated (if applicable)
- [ ] Announcement posts published
- [ ] npm download stats monitored
- [ ] GitHub issues monitored
- [ ] Initial feedback reviewed
- [ ] Hotfix plan ready (if needed)

---

## Notes

- **Irreversible Actions**: npm releases cannot be deleted (only deprecated)
- **Timing**: Plan release during business hours for monitoring
- **Communication**: Have social media/blog posts ready before release
- **Support**: Be available for 48 hours post-release to handle issues
- **Bundle Size**: Keep WASM module <70KB (target: 62KB)
- **Performance**: Maintain 3-10× speedup vs JavaScript libraries

---

## Summary: Testing Commands Cheat Sheet

For quick reference, here are all the key testing commands:

### Automated Scripts (Recommended)

```bash
# Complete workflow (build → test → verify)
./scripts/run-all-tests.sh           # Run all tests (6 phases)
./scripts/build-npm-package.sh       # Build optimized package
./scripts/verify-bundle-size.sh      # Check size compliance
./scripts/test-local-package.sh      # Test installed package

# Quick mode (skip memory tests, saves ~5 min)
./scripts/run-all-tests.sh --quick
```

### Manual Testing (Individual Commands)

```bash
# Build & verify
zig build -Doptimize=ReleaseSmall    # Build WASM
ls -lh zig-out/bin/rozes.wasm        # ~62KB
gzip -c zig-out/bin/rozes.wasm | wc -c  # ~35KB

# Run tests
zig build test                       # 461/463 unit tests
zig build conformance                # 125/125 RFC 4180
zig build benchmark                  # 6/6 benchmarks
zig build memory-test                # 5 test suites

# Node.js integration
node examples/node/test_bundled_package.js  # 11 comprehensive tests
node examples/node/basic.js                 # Basic smoke test
node examples/node/basic_esm.mjs            # ESM smoke test
```

### Package Verification

```bash
# Build and test workflow
./scripts/build-npm-package.sh       # Creates rozes-{version}.tgz
./scripts/test-local-package.sh      # Tests in clean environment

# Manual verification
npm pack                             # Create tarball
tar -tzf rozes-*.tgz | grep wasm     # Verify WASM included
npm install ./rozes-*.tgz            # Install locally
node -e "require('rozes')"           # Quick import test
```

### Browser Testing

```bash
# Build WASM
zig build -Doptimize=ReleaseSmall

# Serve test page
python3 -m http.server 8080

# Open browser
open http://localhost:8080/src/test/browser/

# Click "Run All Tests" - expect 17/17 passing
```

### Performance Comparison

```bash
# Compare vs Papa Parse
node src/test/benchmark/compare_js.js

# Expected results:
# - Rozes: 3-10× faster
# - Bundle: 62KB vs 206KB Papa Parse
```

---

**Questions?** See [docs/CLAUDE.md](../CLAUDE.md) or open a discussion.

**Last Updated**: 2025-11-01
