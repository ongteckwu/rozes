/**
 * CSV Export API Showcase (TypeScript)
 *
 * Demonstrates all CSV export options available in Rozes DataFrame.
 * This includes custom delimiters, headers, line endings, and quoting behavior.
 */

import { Rozes, DataFrame as DataFrameType } from '../../dist/index.mjs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import fs from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main(): Promise<void> {
  console.log('📊 CSV Export API Showcase (TypeScript)\n');

  // Initialize Rozes
  const wasmPath = join(__dirname, '../../zig-out/bin/rozes.wasm');
  const rozes = await Rozes.init(wasmPath);
  console.log('✅ Rozes initialized\n');

  const DataFrame = rozes.DataFrame;

  // Sample dataset
  const csv: string = `name,age,city,score,notes
Alice,30,San Francisco,95.5,"Works in tech, loves hiking"
Bob,25,New York,87.3,"Finance analyst"
Charlie,35,Seattle,91.0,"Software engineer, plays guitar"
Diana,28,Boston,88.7,"Data scientist"
Eve,32,Austin,93.2,"Product manager, runner"`;

  const df: DataFrameType = DataFrame.fromCSV(csv);
  console.log('Original DataFrame:');
  df.show();
  console.log();

  // Example 1: Basic CSV export (default options)
  console.log('1️⃣  Basic CSV Export (default)');
  console.log('─'.repeat(50));
  const csv1: string = df.toCSV();
  console.log(csv1);
  console.log();

  // Example 2: Export without headers
  console.log('2️⃣  Export without headers');
  console.log('─'.repeat(50));
  const csv2: string = df.toCSV({ includeHeaders: false });
  console.log(csv2);
  console.log();

  // Example 3: Custom delimiter (tab-separated)
  console.log('3️⃣  Tab-Separated Values (TSV)');
  console.log('─'.repeat(50));
  const tsv: string = df.toCSV({ delimiter: '\t' });
  console.log(tsv);
  console.log();

  // Example 4: Custom delimiter (pipe-separated)
  console.log('4️⃣  Pipe-Separated Values');
  console.log('─'.repeat(50));
  const psv: string = df.toCSV({ delimiter: '|' });
  console.log(psv);
  console.log();

  // Example 5: Custom line ending (Windows CRLF)
  console.log('5️⃣  Windows Line Endings (CRLF)');
  console.log('─'.repeat(50));
  const csvCRLF: string = df.toCSV({ lineEnding: '\r\n' });
  console.log('Line ending:', JSON.stringify('\r\n'));
  console.log(csvCRLF);
  console.log();

  // Example 6: Select specific columns before export
  console.log('6️⃣  Export Selected Columns (name, age, score)');
  console.log('─'.repeat(50));
  const dfSubset: DataFrameType = df.select(['name', 'age', 'score']);
  const csv6: string = dfSubset.toCSV();
  console.log(csv6);
  console.log();

  // Example 7: Filter and export
  console.log('7️⃣  Export Filtered Data (age > 30)');
  console.log('─'.repeat(50));
  const dfFiltered: DataFrameType = df.filter((row) => row.get('age') > 30);
  const csv7: string = dfFiltered.toCSV();
  console.log(csv7);
  console.log();

  // Example 8: Export to file (Node.js only)
  console.log('8️⃣  Export to File');
  console.log('─'.repeat(50));
  const outputPath: string = join(__dirname, 'output_example.csv');

  // Method 1: Using toCSV() + fs.writeFileSync
  const csvData: string = df.toCSV();
  fs.writeFileSync(outputPath, csvData, 'utf8');
  console.log(`✅ Exported to: ${outputPath}`);

  // Verify the file was created
  const fileSize: number = fs.statSync(outputPath).size;
  console.log(`   File size: ${fileSize} bytes`);
  console.log();

  // Example 9: Round-trip test (CSV → DataFrame → CSV)
  console.log('9️⃣  Round-Trip Test (preserves data)');
  console.log('─'.repeat(50));
  const originalCSV: string = df.toCSV();
  const dfReloaded: DataFrameType = DataFrame.fromCSV(originalCSV);
  const reexportedCSV: string = dfReloaded.toCSV();

  if (originalCSV === reexportedCSV) {
    console.log('✅ Round-trip successful: Original === Re-exported');
  } else {
    console.log('⚠️  Warning: CSV changed during round-trip');
  }
  console.log();

  // Example 10: Export with special characters and quoting
  console.log('🔟 Special Characters and Quoting');
  console.log('─'.repeat(50));
  const specialCSV: string = `product,description,price
"Widget A","Contains comma, and ""quotes""",19.99
"Widget B","Line break:\nNewline inside",29.99
"Widget C","Tab:\tInside field",39.99`;

  const dfSpecial: DataFrameType = DataFrame.fromCSV(specialCSV);
  const exportedSpecial: string = dfSpecial.toCSV();
  console.log('Original CSV:');
  console.log(specialCSV);
  console.log('\nExported CSV:');
  console.log(exportedSpecial);
  console.log();

  // Cleanup
  df.free();
  dfSubset.free();
  dfFiltered.free();
  dfReloaded.free();
  dfSpecial.free();

  // Clean up temp file
  if (fs.existsSync(outputPath)) {
    fs.unlinkSync(outputPath);
    console.log('🧹 Cleaned up temporary file');
  }

  console.log('\n✅ CSV Export showcase complete!');
}

// Run examples
main().catch(console.error);
