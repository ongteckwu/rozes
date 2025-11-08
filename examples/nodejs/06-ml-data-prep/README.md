# ML Data Preparation Example

Demonstrates Rozes DataFrame for machine learning data preparation:
- Feature engineering (derived columns, binning)
- Normalization (min-max scaling)
- Ranking features
- Feature extraction from dates/strings

## Usage
```bash
npm install
npm run generate-data  # Creates customers.csv
npm start              # Run ML prep pipeline
npm test               # Verify operations
```

## Key Techniques
```javascript
// Feature engineering: Age bins
const df2 = df.withColumn('age_bin', row => {
  const age = row.get('age');
  return age < 25 ? 'young' : age < 65 ? 'middle' : 'senior';
});

// Normalization: Min-max scaling
const normalized = df.withColumn('age_norm', row => {
  const age = row.get('age');
  return (age - minAge) / (maxAge - minAge);
});

// Ranking: Income rank
const ranked = df.rank('income', false); // ascending
```
