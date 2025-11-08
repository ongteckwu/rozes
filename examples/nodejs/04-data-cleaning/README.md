# Data Cleaning Pipeline Example

Demonstrates Rozes DataFrame capabilities for data quality and cleaning:

- **Missing Data Detection**: `isna()`, `notna()` for null value analysis
- **Missing Data Handling**: `dropna()` to remove incomplete records
- **Deduplication**: `dropDuplicates()` for removing duplicate entries
- **Outlier Detection**: Filter predicates for statistical outliers
- **String Cleaning**: `str.trim()` for whitespace normalization
- **Data Validation**: Quality metrics and retention analysis
- **CSV Export**: `toCSV()` for cleaned data output

## Dataset

5,000 customer records with intentional data quality issues:
- **10% missing values** across various columns (age, city, quantity, etc.)
- **5% duplicate records** (same customer_id + product + amount)
- **3% outliers** (unrealistic ages >120, extreme quantities >500)
- **10% formatting issues** (extra whitespace, mixed case)

## Installation

```bash
npm install
```

**Note**: This example uses a locally built `rozes` package. Build the package first:

```bash
cd ../../..
./scripts/build-npm-package.sh
cd examples/nodejs/04-data-cleaning
npm install
```

## Usage

### 1. Generate Sample Data

```bash
npm run generate-data
```

This creates `customer_data_dirty.csv` with 5,250 records (includes duplicates).

### 2. Run Cleaning Pipeline

```bash
npm start
```

### 3. Run Tests

```bash
npm test
```

## Expected Output

```
=== Rozes Data Cleaning Pipeline ===

📊 Loading dirty customer data...
✓ Loaded 5250 records in 38.45ms

1️⃣  Missing Data Analysis
────────────────────────────────────────────────────────────
Column                Missing Values  Percentage
customer_id                         0       0.00%
first_name                        512       9.75%
last_name                           0       0.00%
age                               487       9.28%
city                              501       9.54%
product                             0       0.00%
quantity                          495       9.43%
unit_price                        508       9.68%
amount                              0       0.00%

⚡ Computed in 156.23ms

2️⃣  Remove Rows with Missing Critical Data
────────────────────────────────────────────────────────────
Rows before: 5250
Rows after:  4738
Removed:     512 rows with missing critical data

⚡ Computed in 42.18ms

3️⃣  Duplicate Detection and Removal
────────────────────────────────────────────────────────────
Rows before: 4738
Rows after:  4488
Removed:     250 duplicate records

⚡ Computed in 28.34ms

4️⃣  Outlier Detection and Removal
────────────────────────────────────────────────────────────
Rows before: 4488
Rows after:  4315
Removed:     173 outlier records

⚡ Computed in 34.56ms

5️⃣  String Cleaning and Normalization
────────────────────────────────────────────────────────────
✓ Trimmed whitespace from first_name
✓ Normalized city names to title case

⚡ Computed in 45.67ms

6️⃣  Data Quality Summary
────────────────────────────────────────────────────────────
Original records:    5250
Cleaned records:     4315
Total removed:       935
Retention rate:      82.19%

Breakdown:
  Missing data:      512 rows
  Duplicates:        250 rows
  Outliers:          173 rows

7️⃣  Export Cleaned Data
────────────────────────────────────────────────────────────
✓ Exported to: customer_data_clean.csv
✓ File size: 412.34 KB
⚡ Exported in 23.45ms

✓ All DataFrames cleaned up

=== Data Cleaning Complete ===
```

## Key Techniques

### Missing Data Detection

```javascript
// Detect missing values in a column
const isnaDF = df.isna('age');
const missingCount = isnaDF.column('age_isna').sum();
```

### Missing Data Removal

```javascript
// Drop rows with missing critical data
const cleaned = df
  .dropna('customer_id')
  .dropna('first_name')
  .dropna('amount');
```

### Duplicate Removal

```javascript
// Remove duplicates based on key columns
const deduplicated = df.dropDuplicates([
  'customer_id',
  'product',
  'amount'
]);
```

### Outlier Filtering

```javascript
// Remove statistical outliers
const noOutliers = df.filter(row => {
  const age = row.get('age');
  return age !== null && age > 0 && age <= 120;
});
```

### String Cleaning

```javascript
// Trim whitespace from column
const trimmed = df.strTrim('first_name');

// Custom normalization with withColumn
const normalized = df.withColumn('city', row => {
  const city = row.get('city');
  // Title case: "new york" -> "New York"
  return city.split(' ')
    .map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join(' ');
});
```

### CSV Export

```javascript
// Export cleaned data
const cleanedCSV = df.toCSV({ header: true, delimiter: ',' });
fs.writeFileSync('output.csv', cleanedCSV);
```

## Performance Notes

- **Missing data detection**: ~150ms for 5K rows × 9 columns
- **dropna()**: ~40ms per column
- **dropDuplicates()**: ~30ms for 5K rows
- **Filter (outliers)**: ~35ms per filter
- **String normalization**: ~45ms for 5K rows
- **CSV export**: ~25ms for 4K rows
- **Total pipeline**: ~350-400ms for complete cleaning

On larger datasets (100K+ rows), expect similar relative performance with SIMD/parallel optimizations.

## Real-World Applications

This pipeline demonstrates techniques commonly used for:

- **Customer Data**: Deduplicating CRM records, normalizing contact info
- **Survey Data**: Handling incomplete responses, removing outliers
- **Sensor Data**: Filtering anomalous readings, imputing missing timestamps
- **Financial Data**: Cleaning transaction records, validating amounts
- **Product Data**: Standardizing names/descriptions, removing test entries

## License

MIT
