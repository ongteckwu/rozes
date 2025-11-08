/**
 * Generates sample sales data for reshaping examples.
 */

const fs = require('fs');
const path = require('path');

const RECORD_COUNT = 200;
const products = ['Widget A', 'Widget B', 'Gadget X'];
const regions = ['North', 'South', 'East', 'West'];
const quarters = ['Q1', 'Q2', 'Q3', 'Q4'];

function randomChoice(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
function randomInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }

const records = [];
for (let i = 1; i <= RECORD_COUNT; i++) {
  const product = randomChoice(products);
  const region = randomChoice(regions);
  const quarter = randomChoice(quarters);
  const sales = randomInt(10000, 100000);
  records.push([i, product, region, quarter, sales].join(','));
}

const csv = ['sale_id,product,region,quarter,sales', ...records].join('\n');
fs.writeFileSync(path.join(__dirname, 'sales.csv'), csv);
console.log(`✓ Generated ${RECORD_COUNT} sales records → sales.csv`);
