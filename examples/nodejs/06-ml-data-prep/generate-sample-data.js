/**
 * Generates sample customer data for ML data preparation examples.
 * Creates CSV with categorical, numerical, and date features.
 */

const fs = require('fs');
const path = require('path');

const RECORD_COUNT = 1000;
const categories = { tier: ['Bronze', 'Silver', 'Gold', 'Platinum'], region: ['North', 'South', 'East', 'West'], device: ['Mobile', 'Desktop', 'Tablet'] };

function randomChoice(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
function randomInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }

const records = [];
for (let i = 1; i <= RECORD_COUNT; i++) {
  const age = randomInt(18, 75);
  const income = randomInt(20000, 150000);
  const purchases = randomInt(0, 100);
  const daysSinceSignup = randomInt(1, 1000);
  records.push([i, randomChoice(categories.tier), age, income, purchases, randomChoice(categories.region), randomChoice(categories.device), daysSinceSignup].join(','));
}

const csv = ['customer_id,tier,age,income,purchases,region,device,days_since_signup', ...records].join('\n');
fs.writeFileSync(path.join(__dirname, 'customers.csv'), csv);
console.log(`✓ Generated ${RECORD_COUNT} customer records → customers.csv`);
