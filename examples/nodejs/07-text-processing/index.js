/**
 * Text Processing Pipeline with Rozes
 * Demonstrates: String operations (trim, lower, upper, contains, replace, slice)
 */

import { Rozes, DataFrame } from 'rozes';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log('=== Rozes Text Processing Pipeline ===\n');

  // Initialize Rozes
  await Rozes.init();

  const dataPath = path.join(__dirname, 'reviews.csv');
  if (!fs.existsSync(dataPath)) {
    console.error('❌ reviews.csv not found. Run: npm run generate-data');
    process.exit(1);
  }

  const csvData = fs.readFileSync(dataPath, 'utf8');
  const df = DataFrame.fromCSV(csvData, { hasHeader: true, inferTypes: true });
  console.log(`✓ Loaded ${df.shape()[0]} reviews\n`);

// 1. Trim whitespace
console.log('1️⃣  Trim Whitespace from Reviews');
const dfTrimmed = df.strTrim('review_text');
console.log('✓ Trimmed whitespace\n');

// 2. Convert to lowercase
console.log('2️⃣  Convert to Lowercase');
const dfLower = dfTrimmed.strLower('review_text');
console.log('✓ Converted to lowercase\n');

// 3. Filter reviews containing "great"
console.log('3️⃣  Filter Reviews Containing "great"');
const dfGreat = dfLower.strContains('review_text', 'great');
const greatCount = dfGreat.column('review_text_contains_great').sum();
console.log(`✓ Found ${greatCount} reviews containing "great"\n`);

// 4. Replace "terrible" with "poor"
console.log('4️⃣  Replace "terrible" with "poor"');
const dfReplaced = dfLower.strReplace('review_text', 'terrible', 'poor');
console.log('✓ Replaced "terrible" with "poor"\n');

// 5. Extract first 20 characters
console.log('5️⃣  Extract First 20 Characters');
const dfSliced = dfReplaced.strSlice('review_text', 0, 20);
const sampleText = dfSliced.column('review_text_slice').get(0);
console.log(`✓ Sample slice: "${sampleText}"\n`);

// 6. Create sentiment labels
console.log('6️⃣  Create Sentiment Labels');
const dfSentiment = dfReplaced.withColumn('sentiment', row => {
  const text = row.get('review_text');
  if (text.includes('great') || text.includes('excellent') || text.includes('amazing')) return 'positive';
  if (text.includes('poor') || text.includes('disappointed')) return 'negative';
  return 'neutral';
});
console.log('✓ Created sentiment column\n');

  // Summary
  const posCount = dfSentiment.filter(r => r.get('sentiment') === 'positive').shape()[0];
  const negCount = dfSentiment.filter(r => r.get('sentiment') === 'negative').shape()[0];
  const neuCount = dfSentiment.filter(r => r.get('sentiment') === 'neutral').shape()[0];

  console.log('Sentiment Distribution:');
  console.log(`  Positive: ${posCount}`);
  console.log(`  Negative: ${negCount}`);
  console.log(`  Neutral:  ${neuCount}\n`);

  // Cleanup
  [df, dfTrimmed, dfLower, dfGreat, dfReplaced, dfSliced, dfSentiment].forEach(d => d.free());
  console.log('=== Text Processing Complete ===');
}

main().catch(console.error);
