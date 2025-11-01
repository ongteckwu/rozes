#!/usr/bin/env bash
#
# Verify Rozes bundle sizes meet targets
#
# This script checks that the WASM bundle and npm package
# meet the size targets:
# - WASM uncompressed: <70KB (target: 62KB)
# - WASM gzipped: <40KB (target: 35KB)
# - npm package: <150KB
#
# Usage:
#   ./scripts/verify-bundle-size.sh
#
# Exit codes:
#   0 - All sizes within targets
#   1 - One or more sizes exceed targets

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$PROJECT_ROOT"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Rozes Bundle Size Verification                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Targets
WASM_TARGET_KB=62
WASM_MAX_KB=70
GZIP_TARGET_KB=35
GZIP_MAX_KB=40
NPM_MAX_KB=150

ALL_OK=true

# Check WASM module
if [ ! -f "zig-out/bin/rozes.wasm" ]; then
    echo -e "${RED}✗ WASM module not found${NC}"
    echo "  Please build first: zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall"
    echo ""
    exit 1
fi

WASM_SIZE=$(stat -f%z "zig-out/bin/rozes.wasm" 2>/dev/null || stat -c%s "zig-out/bin/rozes.wasm" 2>/dev/null)
WASM_SIZE_KB=$((WASM_SIZE / 1024))

echo -e "${BLUE}WASM Module (uncompressed):${NC}"
echo -e "  Size:    ${WASM_SIZE_KB} KB"
echo -e "  Target:  ${WASM_TARGET_KB} KB"
echo -e "  Max:     ${WASM_MAX_KB} KB"

if [ $WASM_SIZE_KB -le $WASM_TARGET_KB ]; then
    echo -e "  ${GREEN}✓ At or below target${NC}"
elif [ $WASM_SIZE_KB -le $WASM_MAX_KB ]; then
    echo -e "  ${YELLOW}⚠ Above target but within max${NC}"
else
    echo -e "  ${RED}✗ EXCEEDS maximum${NC}"
    ALL_OK=false
fi

echo ""

# Check gzipped size
GZIP_SIZE=$(gzip -c zig-out/bin/rozes.wasm | wc -c | tr -d ' ')
GZIP_SIZE_KB=$((GZIP_SIZE / 1024))

echo -e "${BLUE}WASM Module (gzipped):${NC}"
echo -e "  Size:    ${GZIP_SIZE_KB} KB"
echo -e "  Target:  ${GZIP_TARGET_KB} KB"
echo -e "  Max:     ${GZIP_MAX_KB} KB"

if [ $GZIP_SIZE_KB -le $GZIP_TARGET_KB ]; then
    echo -e "  ${GREEN}✓ At or below target${NC}"
elif [ $GZIP_SIZE_KB -le $GZIP_MAX_KB ]; then
    echo -e "  ${YELLOW}⚠ Above target but within max${NC}"
else
    echo -e "  ${RED}✗ EXCEEDS maximum${NC}"
    ALL_OK=false
fi

echo ""

# Check npm package (if exists)
TARBALL=$(ls rozes-*.tgz 2>/dev/null | head -n1)

if [ -n "$TARBALL" ] && [ -f "$TARBALL" ]; then
    NPM_SIZE=$(stat -f%z "$TARBALL" 2>/dev/null || stat -c%s "$TARBALL" 2>/dev/null)
    NPM_SIZE_KB=$((NPM_SIZE / 1024))

    echo -e "${BLUE}npm Package:${NC}"
    echo -e "  File:    ${TARBALL}"
    echo -e "  Size:    ${NPM_SIZE_KB} KB"
    echo -e "  Max:     ${NPM_MAX_KB} KB"

    if [ $NPM_SIZE_KB -le $NPM_MAX_KB ]; then
        echo -e "  ${GREEN}✓ Within maximum${NC}"
    else
        echo -e "  ${RED}✗ EXCEEDS maximum${NC}"
        ALL_OK=false
    fi
else
    echo -e "${YELLOW}⚠ npm package not found (skipping)${NC}"
    echo -e "  Build with: ./scripts/build-npm-package.sh"
fi

echo ""

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

if [ "$ALL_OK" = true ]; then
    echo -e "${GREEN}✓ All bundle sizes within targets${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ One or more bundle sizes exceed targets${NC}"
    echo ""
    echo -e "${YELLOW}Recommendations:${NC}"
    echo ""
    echo "  1. Run wasm-opt for further optimization:"
    echo "     wasm-opt -Oz zig-out/bin/rozes.wasm -o rozes_opt.wasm"
    echo ""
    echo "  2. Check for dead code in build.zig"
    echo ""
    echo "  3. Review recent changes that may have increased size"
    echo ""
    exit 1
fi
