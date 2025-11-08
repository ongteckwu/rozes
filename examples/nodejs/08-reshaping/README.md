# Reshaping Example

Demonstrates Rozes DataFrame for data reshaping operations:
- Pivot tables (wide format aggregation)
- Melt (wide to long format)
- Transpose (swap rows/columns)
- Stack/unstack (multi-index operations)

## Usage
```bash
npm install
npm run generate-data  # Creates sales.csv
npm start              # Run reshaping pipeline
npm test               # Verify operations
```

## Key Techniques
```javascript
// Pivot: Create wide format summary
const pivoted = df.pivot('product', 'quarter', 'sales', 'sum');
// Result: products as rows, quarters as columns

// Melt: Convert wide to long format
const melted = pivoted.melt('product', ['Q1', 'Q2', 'Q3', 'Q4'], 'quarter', 'sales');
// Result: One row per product-quarter combination

// Transpose: Swap rows and columns
const transposed = df.transpose();
```

## Real-World Use Cases
- Financial reports (pivot quarterly results)
- Time series analysis (reshape for modeling)
- Data export (convert to Excel-friendly format)
