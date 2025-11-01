#!/usr/bin/env bash
#
# Run all Rozes tests
#
# This script runs the complete test suite:
# - Zig unit tests
# - Conformance tests (RFC 4180)
# - Benchmark tests
# - Memory leak tests
# - Node.js integration tests
#
# Usage:
#   ./scripts/run-all-tests.sh
#
# Options:
#   --quick    Skip memory tests (saves ~5 minutes)
#   --skip-benchmarks   Skip benchmark tests
#
# Requirements:
#   - Zig 0.15.1+
#   - Node.js 14+ (for integration tests)

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

# Parse arguments
SKIP_MEMORY=false
SKIP_BENCHMARKS=false

for arg in "$@"; do
    case $arg in
        --quick)
            SKIP_MEMORY=true
            shift
            ;;
        --skip-benchmarks)
            SKIP_BENCHMARKS=true
            shift
            ;;
    esac
done

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Rozes Complete Test Suite                              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

START_TIME=$(date +%s)

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Step 1: Zig unit tests
echo -e "${BLUE}[1/6]${NC} Running Zig unit tests..."
echo ""

if zig build test 2>&1 | tee /tmp/rozes_test.log; then
    # Parse test results
    UNIT_TESTS=$(grep -o '[0-9]\+ passed' /tmp/rozes_test.log | head -n1 | cut -d' ' -f1 || echo "0")
    TOTAL_TESTS=$((TOTAL_TESTS + UNIT_TESTS))
    PASSED_TESTS=$((PASSED_TESTS + UNIT_TESTS))
    echo ""
    echo -e "${GREEN}✓ Unit tests: ${UNIT_TESTS} passed${NC}"
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo ""
    echo -e "${RED}✗ Unit tests failed${NC}"
fi

echo ""

# Step 2: Conformance tests
echo -e "${BLUE}[2/6]${NC} Running RFC 4180 conformance tests..."
echo ""

if zig build conformance 2>&1 | tee /tmp/rozes_conformance.log; then
    CONFORMANCE_TESTS=$(grep -o '[0-9]\+ passed' /tmp/rozes_conformance.log | head -n1 | cut -d' ' -f1 || echo "0")
    TOTAL_TESTS=$((TOTAL_TESTS + CONFORMANCE_TESTS))
    PASSED_TESTS=$((PASSED_TESTS + CONFORMANCE_TESTS))
    echo ""
    echo -e "${GREEN}✓ Conformance tests: ${CONFORMANCE_TESTS} passed${NC}"
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo ""
    echo -e "${RED}✗ Conformance tests failed${NC}"
fi

echo ""

# Step 3: Benchmark tests
if [ "$SKIP_BENCHMARKS" = false ]; then
    echo -e "${BLUE}[3/6]${NC} Running benchmark tests..."
    echo ""

    if zig build benchmark 2>&1 | tee /tmp/rozes_benchmark.log; then
        BENCHMARK_TESTS=6  # Known number of benchmarks
        TOTAL_TESTS=$((TOTAL_TESTS + BENCHMARK_TESTS))
        PASSED_TESTS=$((PASSED_TESTS + BENCHMARK_TESTS))
        echo ""
        echo -e "${GREEN}✓ Benchmark tests: ${BENCHMARK_TESTS} passed${NC}"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo ""
        echo -e "${RED}✗ Benchmark tests failed${NC}"
    fi
else
    echo -e "${BLUE}[3/6]${NC} Skipping benchmark tests (--skip-benchmarks)"
fi

echo ""

# Step 4: Memory tests
if [ "$SKIP_MEMORY" = false ]; then
    echo -e "${BLUE}[4/6]${NC} Running memory leak tests (may take ~5 minutes)..."
    echo ""

    if zig build memory-test 2>&1 | tee /tmp/rozes_memory.log; then
        MEMORY_TESTS=5  # 5 test suites
        TOTAL_TESTS=$((TOTAL_TESTS + MEMORY_TESTS))
        PASSED_TESTS=$((PASSED_TESTS + MEMORY_TESTS))
        echo ""
        echo -e "${GREEN}✓ Memory tests: ${MEMORY_TESTS} suites passed${NC}"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo ""
        echo -e "${YELLOW}⚠ Memory tests: some failures (expected 4/5 suites passing)${NC}"
    fi
else
    echo -e "${BLUE}[4/6]${NC} Skipping memory tests (--quick mode)"
fi

echo ""

# Step 5: Build WASM for integration tests
echo -e "${BLUE}[5/6]${NC} Building WASM module for integration tests..."
echo ""

if zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall > /dev/null 2>&1; then
    echo -e "${GREEN}✓ WASM build successful${NC}"
else
    echo -e "${RED}✗ WASM build failed${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""

# Step 6: Node.js integration tests
echo -e "${BLUE}[6/6]${NC} Running Node.js integration tests..."
echo ""

if [ -f "examples/node/basic.js" ]; then
    echo -e "  ${YELLOW}Testing basic.js...${NC}"
    if node examples/node/basic.js > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ basic.js passed${NC}"
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "  ${RED}✗ basic.js failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo -e "  ${YELLOW}⚠ basic.js not found, skipping${NC}"
fi

if [ -f "examples/node/basic_esm.mjs" ]; then
    echo -e "  ${YELLOW}Testing basic_esm.mjs...${NC}"
    if node examples/node/basic_esm.mjs > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ basic_esm.mjs passed${NC}"
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "  ${RED}✗ basic_esm.mjs failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo -e "  ${YELLOW}⚠ basic_esm.mjs not found, skipping${NC}"
fi

echo ""

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

# Summary
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Test Summary                                            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Total tests:  ${TOTAL_TESTS}"
echo -e "  Passed:       ${GREEN}${PASSED_TESTS}${NC}"
echo -e "  Failed:       ${RED}${FAILED_TESTS}${NC}"
echo -e "  Duration:     ${DURATION_MIN}m ${DURATION_SEC}s"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo -e "${BLUE}Ready for release:${NC}"
    echo -e "  1. Build package:  ./scripts/build-npm-package.sh"
    echo -e "  2. Test package:   ./scripts/test-local-package.sh"
    echo -e "  3. Publish:        npm publish"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    echo -e "${YELLOW}Please fix failing tests before release.${NC}"
    echo ""
    exit 1
fi
