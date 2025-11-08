const rozes = require('rozes');

console.log('=== Testing Text Processing Pipeline ===\n');

let passed = 0, total = 0;
function assert(cond, msg) { total++; if (cond) { console.log(`✓ ${msg}`); passed++; } else { console.error(`✗ ${msg}`); }}

const testCSV = 'id,text\n1,"  HELLO  "\n2,"world"\n3,"Great Product"';
const df = rozes.fromCSV(testCSV, { hasHeader: true, inferTypes: true });

// Test trim
const dfTrim = df.strTrim('text');
assert(dfTrim.column('text').get(0) === 'HELLO', 'Trimmed whitespace');
dfTrim.free();

// Test lower
const dfLower = df.strLower('text');
assert(dfLower.column('text').get(0) === '  hello  ', 'Converted to lowercase');
dfLower.free();

// Test upper
const dfUpper = df.strUpper('text');
assert(dfUpper.column('text').get(1) === 'WORLD', 'Converted to uppercase');
dfUpper.free();

// Test contains
const dfContains = df.strContains('text', 'HELLO');
assert(dfContains.column('text_contains_HELLO').get(0) === 1, 'Contains detection works');
dfContains.free();

df.free();

console.log(`\nTests passed: ${passed}/${total}`);
process.exit(passed === total ? 0 : 1);
