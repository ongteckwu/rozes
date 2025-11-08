/**
 * Generates sample product review data for text processing examples.
 */

const fs = require('fs');
const path = require('path');

const RECORD_COUNT = 500;
const products = ['Laptop', 'Phone', 'Tablet', 'Watch', 'Headphones'];
const ratings = [1, 2, 3, 4, 5];
const reviews = [
  '  GREAT PRODUCT! Highly recommend.  ',
  'Not bad but could be better',
  '  excellent quality and fast shipping  ',
  'TERRIBLE! Very disappointed.',
  '  Amazing value for money  ',
  'okay product nothing special'
];

function randomChoice(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

const records = [];
for (let i = 1; i <= RECORD_COUNT; i++) {
  const product = randomChoice(products);
  const rating = randomChoice(ratings);
  const review = randomChoice(reviews);
  records.push([i, product, rating, review].map(v => `"${v}"`).join(','));
}

const csv = ['review_id,product,rating,review_text', ...records].join('\n');
fs.writeFileSync(path.join(__dirname, 'reviews.csv'), csv);
console.log(`✓ Generated ${RECORD_COUNT} product reviews → reviews.csv`);
