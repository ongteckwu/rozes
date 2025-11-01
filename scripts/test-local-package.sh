#!/usr/bin/env bash
#
# Test script for locally built Rozes npm package
#
# This script tests the npm package in a clean environment to verify:
# - Installation works correctly
# - WASM module loads
# - All APIs function properly
# - No missing dependencies
#
# Usage:
#   ./scripts/test-local-package.sh [tarball]
#
# Arguments:
#   tarball - Optional path to .tgz file (default: rozes-*.tgz)
#
# Requirements:
#   - Node.js 14+
#   - Built package tarball (run ./scripts/build-npm-package.sh first)

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
echo -e "${BLUE}║  Rozes Local Package Test                               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Find tarball
if [ $# -eq 1 ]; then
    TARBALL="$1"
else
    TARBALL=$(ls rozes-*.tgz 2>/dev/null | head -n1)
fi

if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
    echo -e "${RED}✗ Package tarball not found${NC}"
    echo ""
    echo "  Please build the package first:"
    echo "  ./scripts/build-npm-package.sh"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Found package: ${TARBALL}${NC}"
echo ""

# Create temporary test directory
TEST_DIR=$(mktemp -d)
trap "rm -rf ${TEST_DIR}" EXIT

echo -e "${BLUE}Test directory: ${TEST_DIR}${NC}"
echo ""

cd "$TEST_DIR"

# Step 1: Initialize test package
echo -e "${BLUE}[1/5]${NC} Initializing test package..."

npm init -y > /dev/null 2>&1

echo -e "${GREEN}✓ Test package initialized${NC}"
echo ""

# Step 2: Install package
echo -e "${BLUE}[2/5]${NC} Installing package from tarball..."

npm install "$PROJECT_ROOT/$TARBALL" --quiet

if [ ! -d "node_modules/rozes" ]; then
    echo -e "${RED}✗ Installation failed - rozes not in node_modules${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Package installed${NC}"
echo ""

# Step 3: Verify package structure
echo -e "${BLUE}[3/5]${NC} Verifying package structure..."

REQUIRED_FILES=(
    "node_modules/rozes/package.json"
    "node_modules/rozes/dist/index.js"
    "node_modules/rozes/dist/index.mjs"
    "node_modules/rozes/dist/index.d.ts"
    "node_modules/rozes/zig-out/bin/rozes.wasm"
)

ALL_PRESENT=true

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓ ${file}${NC}"
    else
        echo -e "${RED}✗ Missing: ${file}${NC}"
        ALL_PRESENT=false
    fi
done

if [ "$ALL_PRESENT" = false ]; then
    echo -e "${RED}✗ Package structure verification failed${NC}"
    exit 1
fi

echo ""

# Step 4: Run smoke tests
echo -e "${BLUE}[4/5]${NC} Running smoke tests..."
echo ""

# Test 4.1: CommonJS import
echo -e "  ${YELLOW}Test 4.1: CommonJS import${NC}"
node -e "
const { Rozes } = require('rozes');
Rozes.init().then(rozes => {
  const df = rozes.DataFrame.fromCSV('name,age\\nAlice,30\\nBob,25');
  console.log('    Shape:', df.shape);
  if (df.shape.rows === 2 && df.shape.cols === 2) {
    console.log('    ✓ CommonJS import works');
  } else {
    console.log('    ✗ Incorrect shape');
    process.exit(1);
  }
}).catch(err => {
  console.error('    ✗ CommonJS import failed:', err.message);
  process.exit(1);
});
"

echo ""

# Test 4.2: ESM import
echo -e "  ${YELLOW}Test 4.2: ESM import${NC}"
node -e "
import('rozes').then(({ Rozes }) => {
  return Rozes.init();
}).then(rozes => {
  const df = rozes.DataFrame.fromCSV('name,age\\nAlice,30\\nBob,25');
  console.log('    Shape:', df.shape);
  if (df.shape.rows === 2 && df.shape.cols === 2) {
    console.log('    ✓ ESM import works');
  } else {
    console.log('    ✗ Incorrect shape');
    process.exit(1);
  }
}).catch(err => {
  console.error('    ✗ ESM import failed:', err.message);
  process.exit(1);
});
"

echo ""

# Test 4.3: Zero-copy access
echo -e "  ${YELLOW}Test 4.3: Zero-copy TypedArray access${NC}"
node -e "
const { Rozes } = require('rozes');
Rozes.init().then(rozes => {
  const df = rozes.DataFrame.fromCSV('name,age,score\\nAlice,30,95.5\\nBob,25,87.3');
  const ages = df.column('age');
  const isTypedArray = ages instanceof Float64Array || ages instanceof Int32Array || ages instanceof BigInt64Array;
  console.log('    Age column type:', ages.constructor.name);
  if (isTypedArray) {
    console.log('    ✓ Zero-copy TypedArray access works');
  } else {
    console.log('    ✗ Not a TypedArray');
    process.exit(1);
  }
}).catch(err => {
  console.error('    ✗ Zero-copy test failed:', err.message);
  process.exit(1);
});
"

echo ""

# Step 5: Run comprehensive test suite (if available)
echo -e "${BLUE}[5/5]${NC} Running comprehensive test suite..."
echo ""

if [ -f "$PROJECT_ROOT/examples/node/test_bundled_package.js" ]; then
    cp "$PROJECT_ROOT/examples/node/test_bundled_package.js" .

    echo -e "  ${YELLOW}Running test_bundled_package.js...${NC}"
    echo ""

    if node test_bundled_package.js; then
        echo ""
        echo -e "${GREEN}✓ Comprehensive tests passed${NC}"
    else
        echo ""
        echo -e "${RED}✗ Comprehensive tests failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ Comprehensive test suite not found, skipping${NC}"
fi

echo ""

# Summary
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Test Summary                                            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Package:   ${TARBALL}"
echo -e "  Test dir:  ${TEST_DIR}"
echo ""
echo -e "${GREEN}✓ All tests passed!${NC}"
echo ""
echo -e "${BLUE}The package is ready for publishing.${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Publish to npm (test): npm publish --tag beta"
echo -e "  2. Publish to npm (prod): npm publish"
echo ""
