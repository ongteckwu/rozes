#!/usr/bin/env bash
#
# Build script for Rozes npm package
#
# This script builds the WASM module and creates a tarball ready for npm publish.
# The package includes:
# - Optimized WASM module (rozes.wasm)
# - JavaScript wrappers (CommonJS + ESM)
# - TypeScript definitions
# - Documentation
#
# Usage:
#   ./scripts/build-npm-package.sh
#
# Output:
#   rozes-{version}.tgz in project root
#
# Requirements:
#   - Zig 0.15.1+
#   - Node.js 14+ (for npm pack)
#   - wasm-opt (optional, for further optimization)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$PROJECT_ROOT"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Rozes npm Package Build Script                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Check prerequisites
echo -e "${BLUE}[1/6]${NC} Checking prerequisites..."

# Check Zig version
if ! command -v zig &> /dev/null; then
    echo -e "${RED}✗ Zig not found${NC}"
    echo "  Please install Zig 0.15.1+ from https://ziglang.org/"
    exit 1
fi

ZIG_VERSION=$(zig version)
echo -e "${GREEN}✓ Zig version: ${ZIG_VERSION}${NC}"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Node.js not found${NC}"
    echo "  Please install Node.js 14+ from https://nodejs.org/"
    exit 1
fi

NODE_VERSION=$(node --version)
echo -e "${GREEN}✓ Node.js version: ${NODE_VERSION}${NC}"

# Check for wasm-opt (optional)
if command -v wasm-opt &> /dev/null; then
    WASM_OPT_VERSION=$(wasm-opt --version | head -n1)
    echo -e "${GREEN}✓ wasm-opt available: ${WASM_OPT_VERSION}${NC}"
    HAS_WASM_OPT=true
else
    echo -e "${YELLOW}⚠ wasm-opt not found (optional optimization will be skipped)${NC}"
    echo -e "${YELLOW}  Install via: npm install -g wasm-opt${NC}"
    HAS_WASM_OPT=false
fi

echo ""

# Step 2: Clean previous builds
echo -e "${BLUE}[2/6]${NC} Cleaning previous builds..."

rm -rf zig-out zig-cache
rm -f rozes-*.tgz

echo -e "${GREEN}✓ Clean complete${NC}"
echo ""

# Step 3: Build WASM module
echo -e "${BLUE}[3/6]${NC} Building WASM module..."

zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall

if [ ! -f "zig-out/bin/rozes.wasm" ]; then
    echo -e "${RED}✗ WASM build failed - rozes.wasm not found${NC}"
    exit 1
fi

WASM_SIZE=$(stat -f%z "zig-out/bin/rozes.wasm" 2>/dev/null || stat -c%s "zig-out/bin/rozes.wasm" 2>/dev/null)
WASM_SIZE_KB=$((WASM_SIZE / 1024))

echo -e "${GREEN}✓ WASM module built: ${WASM_SIZE_KB} KB${NC}"

# Check if size exceeds target
if [ $WASM_SIZE_KB -gt 70 ]; then
    echo -e "${YELLOW}⚠ Warning: WASM size (${WASM_SIZE_KB} KB) exceeds target (62 KB)${NC}"
fi

echo ""

# Step 4: Optimize WASM (optional)
if [ "$HAS_WASM_OPT" = true ]; then
    echo -e "${BLUE}[4/6]${NC} Optimizing WASM with wasm-opt..."

    ORIGINAL_SIZE=$WASM_SIZE_KB

    wasm-opt -Oz zig-out/bin/rozes.wasm -o zig-out/bin/rozes_opt.wasm

    # Replace original with optimized
    mv zig-out/bin/rozes_opt.wasm zig-out/bin/rozes.wasm

    WASM_SIZE=$(stat -f%z "zig-out/bin/rozes.wasm" 2>/dev/null || stat -c%s "zig-out/bin/rozes.wasm" 2>/dev/null)
    WASM_SIZE_KB=$((WASM_SIZE / 1024))

    REDUCTION=$((ORIGINAL_SIZE - WASM_SIZE_KB))
    REDUCTION_PCT=$((REDUCTION * 100 / ORIGINAL_SIZE))

    echo -e "${GREEN}✓ Optimized: ${ORIGINAL_SIZE} KB → ${WASM_SIZE_KB} KB (${REDUCTION_PCT}% reduction)${NC}"
else
    echo -e "${BLUE}[4/6]${NC} Skipping wasm-opt optimization (not installed)"
fi

echo ""

# Step 5: Verify gzipped size
echo -e "${BLUE}[5/6]${NC} Checking gzipped size..."

GZIP_SIZE=$(gzip -c zig-out/bin/rozes.wasm | wc -c | tr -d ' ')
GZIP_SIZE_KB=$((GZIP_SIZE / 1024))

echo -e "${GREEN}✓ Gzipped size: ${GZIP_SIZE_KB} KB${NC}"

if [ $GZIP_SIZE_KB -gt 40 ]; then
    echo -e "${YELLOW}⚠ Warning: Gzipped size (${GZIP_SIZE_KB} KB) exceeds target (35 KB)${NC}"
fi

echo ""

# Step 6: Create npm package tarball
echo -e "${BLUE}[6/6]${NC} Creating npm package tarball..."

# Get version from package.json
VERSION=$(node -p "require('./package.json').version")

# Create tarball
npm pack

TARBALL="rozes-${VERSION}.tgz"

if [ ! -f "$TARBALL" ]; then
    echo -e "${RED}✗ Failed to create tarball${NC}"
    exit 1
fi

TARBALL_SIZE=$(stat -f%z "$TARBALL" 2>/dev/null || stat -c%s "$TARBALL" 2>/dev/null)
TARBALL_SIZE_KB=$((TARBALL_SIZE / 1024))

echo -e "${GREEN}✓ Package created: ${TARBALL} (${TARBALL_SIZE_KB} KB)${NC}"
echo ""

# Step 7: Verify package contents
echo -e "${BLUE}[7/7]${NC} Verifying package contents..."

# List critical files
CRITICAL_FILES=(
    "package/dist/index.js"
    "package/dist/index.mjs"
    "package/dist/index.d.ts"
    "package/zig-out/bin/rozes.wasm"
    "package/README.md"
    "package/LICENSE"
)

ALL_PRESENT=true

for file in "${CRITICAL_FILES[@]}"; do
    if tar -tzf "$TARBALL" | grep -q "^${file}$"; then
        echo -e "${GREEN}✓ ${file}${NC}"
    else
        echo -e "${RED}✗ Missing: ${file}${NC}"
        ALL_PRESENT=false
    fi
done

echo ""

if [ "$ALL_PRESENT" = false ]; then
    echo -e "${RED}✗ Package verification failed - missing files${NC}"
    exit 1
fi

# Summary
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Build Summary                                           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Package:      ${TARBALL}"
echo -e "  Version:      ${VERSION}"
echo -e "  WASM size:    ${WASM_SIZE_KB} KB (${GZIP_SIZE_KB} KB gzipped)"
echo -e "  Package size: ${TARBALL_SIZE_KB} KB"
echo ""
echo -e "${GREEN}✓ Build successful!${NC}"
echo ""

# Next steps
echo -e "${BLUE}Next steps:${NC}"
echo ""
echo -e "  ${YELLOW}1. Test the package locally:${NC}"
echo -e "     npm install ./${TARBALL}"
echo -e "     node examples/node/test_bundled_package.js"
echo ""
echo -e "  ${YELLOW}2. Publish to npm (test):${NC}"
echo -e "     npm publish --tag beta"
echo ""
echo -e "  ${YELLOW}3. Publish to npm (production):${NC}"
echo -e "     npm publish"
echo ""
echo -e "  ${YELLOW}4. Run comprehensive verification:${NC}"
echo -e "     See docs/RELEASE.md for full testing checklist"
echo ""
