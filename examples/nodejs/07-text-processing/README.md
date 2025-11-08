# Text Processing Example

Demonstrates Rozes DataFrame for text processing operations:
- String cleaning (trim, lower, upper)
- Pattern matching (contains)
- String manipulation (replace, slice)
- Sentiment analysis (derived features)

## Usage
```bash
npm install
npm run generate-data  # Creates reviews.csv
npm start              # Run text processing pipeline
npm test               # Verify string operations
```

## Key Techniques
```javascript
// Trim whitespace
const cleaned = df.strTrim('review_text');

// Convert case
const lower = df.strLower('review_text');
const upper = df.strUpper('review_text');

// Pattern matching
const containsGreat = df.strContains('review_text', 'great');

// String replacement
const replaced = df.strReplace('review_text', 'bad', 'poor');

// String slicing
const preview = df.strSlice('review_text', 0, 100);
```
