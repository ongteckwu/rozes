/**
 * Reshape Operations API Showcase
 *
 * Demonstrates DataFrame reshaping operations:
 * - pivot() - Pivot table (wide format)
 * - melt() - Unpivot table (long format)
 * - transpose() - Swap rows and columns
 * - stack() - Stack columns into rows
 * - unstack() - Unstack rows into columns
 */

import { Rozes } from '../../dist/index.mjs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main() {
  console.log('🔄 Reshape Operations API Showcase\n');

  // Initialize Rozes
  const wasmPath = join(__dirname, '../../zig-out/bin/rozes.wasm');
  const rozes = await Rozes.init(wasmPath);
  console.log('✅ Rozes initialized\n');

  const DataFrame = rozes.DataFrame;

  // Example 1: Pivot (long to wide format)
  console.log('1️⃣  Pivot: Long to Wide Format');
  console.log('─'.repeat(50));

  const salesLong = `store,product,quarter,sales
Store A,Widget,Q1,100
Store A,Widget,Q2,120
Store A,Gadget,Q1,80
Store A,Gadget,Q2,90
Store B,Widget,Q1,110
Store B,Widget,Q2,130
Store B,Gadget,Q1,85
Store B,Gadget,Q2,95`;

  const dfLong = DataFrame.fromCSV(salesLong);
  console.log('Long format (original):');
  dfLong.show();
  console.log();

  console.log('Pivot: Create product columns from rows');
  const dfPivot = dfLong.pivot('store', 'product', 'sales', 'sum');
  console.log('Wide format (pivoted):');
  dfPivot.show();
  console.log();

  // Example 2: Melt (wide to long format)
  console.log('2️⃣  Melt: Wide to Long Format');
  console.log('─'.repeat(50));

  const scoresWide = `student,math,science,english
Alice,95,92,88
Bob,78,85,82
Charlie,92,89,95`;

  const dfWide = DataFrame.fromCSV(scoresWide);
  console.log('Wide format (original):');
  dfWide.show();
  console.log();

  console.log('Melt: Stack subject columns into rows');
  const dfMelted = dfWide.melt(['student'], ['math', 'science', 'english'], 'subject', 'score');
  console.log('Long format (melted):');
  dfMelted.show();
  console.log();

  // Example 3: Transpose
  console.log('3️⃣  Transpose: Swap Rows and Columns');
  console.log('─'.repeat(50));

  const quarterly = `metric,Q1,Q2,Q3,Q4
Revenue,100,120,115,130
Costs,60,65,62,70
Profit,40,55,53,60`;

  const dfQuarterly = DataFrame.fromCSV(quarterly);
  console.log('Original (metrics as rows):');
  dfQuarterly.show();
  console.log();

  console.log('Transposed (quarters as rows):');
  const dfTransposed = dfQuarterly.transpose();
  dfTransposed.show();
  console.log();

  // Example 4: Stack (multi-column to rows)
  console.log('4️⃣  Stack: Columns to Rows');
  console.log('─'.repeat(50));

  const temperatures = `city,jan,feb,mar
NYC,32,35,45
LA,55,58,62
Chicago,25,28,38`;

  const dfTemp = DataFrame.fromCSV(temperatures);
  console.log('Original (months as columns):');
  dfTemp.show();
  console.log();

  console.log('Stacked (months as rows):');
  const dfStacked = dfTemp.stack();
  dfStacked.show();
  console.log();

  // Example 5: Unstack (rows to multi-column)
  console.log('5️⃣  Unstack: Rows to Columns');
  console.log('─'.repeat(50));

  const inventory = `warehouse,product,quantity
East,WidgetA,100
East,WidgetB,150
West,WidgetA,120
West,WidgetB,130`;

  const dfInventory = DataFrame.fromCSV(inventory);
  console.log('Original (stacked format):');
  dfInventory.show();
  console.log();

  console.log('Unstacked (products as columns):');
  const dfUnstacked = dfInventory.unstack();
  dfUnstacked.show();
  console.log();

  // Example 6: Pivot with different aggregations
  console.log('6️⃣  Pivot with Aggregation Functions');
  console.log('─'.repeat(50));

  const transactions = `customer,product,month,amount
Alice,Widget,Jan,100
Alice,Widget,Feb,120
Alice,Gadget,Jan,80
Bob,Widget,Jan,110
Bob,Gadget,Feb,90`;

  const dfTrans = DataFrame.fromCSV(transactions);
  console.log('Transaction data:');
  dfTrans.show();
  console.log();

  console.log('Pivot: Total sales by customer and product (sum):');
  const dfPivotSum = dfTrans.pivot('customer', 'product', 'amount', 'sum');
  dfPivotSum.show();
  console.log();

  console.log('Pivot: Average sales by customer and product (mean):');
  const dfPivotMean = dfTrans.pivot('customer', 'product', 'amount', 'mean');
  dfPivotMean.show();
  console.log();

  // Example 7: Melt with multiple ID variables
  console.log('7️⃣  Melt with Multiple ID Variables');
  console.log('─'.repeat(50));

  const studentData = `student,grade,math,science,english
Alice,A,95,92,88
Bob,B,78,85,82`;

  const dfStudents = DataFrame.fromCSV(studentData);
  console.log('Original:');
  dfStudents.show();
  console.log();

  console.log('Melted (keep student and grade as IDs):');
  const dfStudentsMelted = dfStudents.melt(
    ['student', 'grade'],
    ['math', 'science', 'english'],
    'subject',
    'score'
  );
  dfStudentsMelted.show();
  console.log();

  // Example 8: Round-trip transformations
  console.log('8️⃣  Round-Trip: Wide → Long → Wide');
  console.log('─'.repeat(50));

  console.log('Step 1: Original wide format');
  dfWide.show();
  console.log();

  console.log('Step 2: Melt to long format');
  const dfRoundTrip1 = dfWide.melt(['student'], ['math', 'science', 'english'], 'subject', 'score');
  dfRoundTrip1.show();
  console.log();

  console.log('Step 3: Pivot back to wide format');
  const dfRoundTrip2 = dfRoundTrip1.pivot('student', 'subject', 'score', 'sum');
  dfRoundTrip2.show();
  console.log();

  // Example 9: Cross-tabulation (pivot with counts)
  console.log('9️⃣  Cross-Tabulation');
  console.log('─'.repeat(50));

  const survey = `age_group,gender,response
18-25,M,Yes
18-25,F,Yes
18-25,M,No
26-35,M,Yes
26-35,F,Yes
26-35,F,No
36-45,M,No
36-45,F,Yes`;

  const dfSurvey = DataFrame.fromCSV(survey);
  console.log('Survey responses:');
  dfSurvey.show();
  console.log();

  console.log('Cross-tab: Count responses by age group and gender');
  // Note: Pivot counts require a dummy value column
  // This is a simplified example
  console.log('(Cross-tabulation would require count aggregation)');
  console.log();

  // Example 10: Chaining reshape operations
  console.log('🔟 Chaining Reshape Operations');
  console.log('─'.repeat(50));

  console.log('Complex transformation pipeline:');
  console.log('1. Start with wide format');
  console.log('2. Melt to long format');
  console.log('3. Filter specific subjects');
  console.log('4. Pivot to different wide format');
  console.log();

  const dfChained = dfWide
    .melt(['student'], ['math', 'science'], 'subject', 'score')
    .filter((row) => row.get('score') > 80);

  console.log('Final result (filtered and reshaped):');
  dfChained.show();
  console.log();

  // Cleanup
  dfLong.free();
  dfPivot.free();
  dfWide.free();
  dfMelted.free();
  dfQuarterly.free();
  dfTransposed.free();
  dfTemp.free();
  dfStacked.free();
  dfInventory.free();
  dfUnstacked.free();
  dfTrans.free();
  dfPivotSum.free();
  dfPivotMean.free();
  dfStudents.free();
  dfStudentsMelted.free();
  dfRoundTrip1.free();
  dfRoundTrip2.free();
  dfSurvey.free();
  dfChained.free();

  console.log('✅ Reshape operations showcase complete!');
}

// Run examples
main().catch(console.error);
