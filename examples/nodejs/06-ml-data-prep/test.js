const rozes = require('rozes');

console.log('=== Testing ML Data Prep Pipeline ===\n');

let passed = 0, total = 0;
function assert(cond, msg) { total++; if (cond) { console.log(`✓ ${msg}`); passed++; } else { console.error(`✗ ${msg}`); }}

const testCSV = 'customer_id,age,income,purchases\n1,25,50000,10\n2,45,80000,20\n3,65,100000,30';
const df = rozes.fromCSV(testCSV, { hasHeader: true, inferTypes: true });

// Test withColumn
const dfAge = df.withColumn('age_bin', row => row.get('age') < 40 ? 'young' : 'old');
assert(dfAge.columns().includes('age_bin'), 'Added age_bin column');
dfAge.free();

// Test rank
const dfRank = df.rank('income', false);
assert(dfRank.columns().includes('income_rank'), 'Added income_rank column');
assert(dfRank.column('income_rank').get(0) === 1, 'Lowest income has rank 1');
dfRank.free();

df.free();

console.log(`\nTests passed: ${passed}/${total}`);
process.exit(passed === total ? 0 : 1);
