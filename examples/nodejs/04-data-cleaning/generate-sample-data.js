/**
 * Generates sample customer data with data quality issues for cleaning examples.
 *
 * Creates CSV with:
 * - Missing values (10% nulls in various columns)
 * - Duplicate records (5% duplicates)
 * - Outliers (3% extreme values)
 * - Inconsistent formats (mixed case, extra spaces)
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configuration
const RECORD_COUNT = 5000;
const MISSING_DATA_RATE = 0.10;  // 10% missing values
const DUPLICATE_RATE = 0.05;     // 5% duplicates
const OUTLIER_RATE = 0.03;       // 3% outliers

// Sample data pools
const firstNames = ['Alice', 'Bob', 'Charlie', 'Diana', 'Edward', 'Fiona', 'George', 'Hannah', 'Ivan', 'Julia'];
const lastNames = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez'];
const cities = ['New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix', 'Philadelphia', 'San Antonio', 'San Diego', 'Dallas', 'San Jose'];
const products = ['Widget A', 'Widget B', 'Gadget X', 'Gadget Y', 'Tool Alpha', 'Tool Beta'];

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randomChoice(array) {
  return array[Math.floor(Math.random() * array.length)];
}

function randomMissing(value, rate) {
  return Math.random() < rate ? '' : value;
}

function generateRecord(id) {
  const firstName = randomChoice(firstNames);
  const lastName = randomChoice(lastNames);
  const age = randomInt(18, 75);
  const city = randomChoice(cities);
  const product = randomChoice(products);
  const quantity = randomInt(1, 50);
  const unitPrice = randomInt(10, 200);
  const amount = quantity * unitPrice;

  return {
    customer_id: id,
    first_name: firstName,
    last_name: lastName,
    age: age,
    city: city,
    product: product,
    quantity: quantity,
    unit_price: unitPrice,
    amount: amount
  };
}

function introduceDataQualityIssues(records) {
  const result = [];
  const recordsToClean = [...records];

  // 1. Add duplicates
  const duplicateCount = Math.floor(RECORD_COUNT * DUPLICATE_RATE);
  for (let i = 0; i < duplicateCount; i++) {
    const randomRecord = randomChoice(recordsToClean);
    result.push({ ...randomRecord });
  }

  // 2. Add outliers and missing values
  for (const record of recordsToClean) {
    const cleanRecord = { ...record };

    // Introduce missing values
    if (Math.random() < MISSING_DATA_RATE) {
      const fieldsToNull = ['first_name', 'age', 'city', 'quantity', 'unit_price'];
      const fieldToNull = randomChoice(fieldsToNull);
      cleanRecord[fieldToNull] = '';
    }

    // Introduce outliers
    if (Math.random() < OUTLIER_RATE) {
      if (record.age) {
        cleanRecord.age = randomInt(150, 200); // Unrealistic age
      }
      if (record.quantity) {
        cleanRecord.quantity = randomInt(1000, 5000); // Extreme quantity
      }
    }

    // Introduce inconsistent formatting
    if (Math.random() < 0.1) {
      if (cleanRecord.first_name) {
        cleanRecord.first_name = '  ' + cleanRecord.first_name.toUpperCase() + '  ';
      }
      if (cleanRecord.city) {
        cleanRecord.city = cleanRecord.city.toLowerCase();
      }
    }

    result.push(cleanRecord);
  }

  return result;
}

function recordToCSVRow(record) {
  return [
    record.customer_id,
    record.first_name,
    record.last_name,
    record.age,
    record.city,
    record.product,
    record.quantity,
    record.unit_price,
    record.amount
  ].join(',');
}

function generateCSV() {
  console.log(`Generating ${RECORD_COUNT} customer records with data quality issues...`);

  // Generate clean records
  const cleanRecords = [];
  for (let i = 1; i <= RECORD_COUNT; i++) {
    cleanRecords.push(generateRecord(i));
  }

  // Introduce data quality issues
  const dirtyRecords = introduceDataQualityIssues(cleanRecords);

  // Write CSV
  const header = 'customer_id,first_name,last_name,age,city,product,quantity,unit_price,amount';
  const rows = dirtyRecords.map(recordToCSVRow);
  const csv = [header, ...rows].join('\n');

  const outputPath = path.join(__dirname, 'customer_data_dirty.csv');
  fs.writeFileSync(outputPath, csv);

  console.log(`✓ Generated ${dirtyRecords.length} records (includes ${Math.floor(RECORD_COUNT * DUPLICATE_RATE)} duplicates)`);
  console.log(`✓ Saved to: ${outputPath}`);
  console.log(`✓ File size: ${(fs.statSync(outputPath).size / 1024).toFixed(2)} KB`);
  console.log('\nData quality issues introduced:');
  console.log(`  - Missing values: ~${(MISSING_DATA_RATE * 100).toFixed(0)}%`);
  console.log(`  - Duplicate records: ~${(DUPLICATE_RATE * 100).toFixed(0)}%`);
  console.log(`  - Outliers: ~${(OUTLIER_RATE * 100).toFixed(0)}%`);
  console.log(`  - Formatting issues: ~10%`);
}

// Run generator
generateCSV();
