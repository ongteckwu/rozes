const rozes = require('rozes');

console.log('=== Testing Reshaping Pipeline ===\n');

let passed = 0, total = 0;
function assert(cond, msg) { total++; if (cond) { console.log(`✓ ${msg}`); passed++; } else { console.error(`✗ ${msg}`); }}

const testCSV = 'product,region,sales\nA,North,100\nA,South,200\nB,North,150\nB,South,250';
const df = rozes.fromCSV(testCSV, { hasHeader: true, inferTypes: true });

// Test pivot
const pivoted = df.pivot('product', 'region', 'sales', 'sum');
assert(pivoted.shape()[0] === 2, 'Pivot created 2 product rows');
assert(pivoted.columns().includes('North'), 'Pivot has North column');
pivoted.free();

// Test melt
const wide = rozes.fromCSV('id,A,B\n1,10,20\n2,30,40', { hasHeader: true, inferTypes: true });
const melted = wide.melt('id', ['A', 'B'], 'variable', 'value');
assert(melted.shape()[0] === 4, 'Melt created 4 rows (2 × 2)');
assert(melted.columns().includes('variable'), 'Melt has variable column');
wide.free();
melted.free();

// Test transpose
const transposed = df.transpose();
assert(transposed.shape()[0] === df.shape()[1], 'Transpose swapped dimensions');
transposed.free();

df.free();

console.log(`\nTests passed: ${passed}/${total}`);
process.exit(passed === total ? 0 : 1);
