/**
 * String Operations API Showcase (TypeScript)
 *
 * Demonstrates all string manipulation operations:
 * - str.lower() - Convert to lowercase
 * - str.upper() - Convert to uppercase
 * - str.trim() - Remove whitespace
 * - str.contains() - Check if contains substring
 * - str.replace() - Replace substring
 * - str.slice() - Extract substring
 * - str.startsWith() - Check prefix
 * - str.endsWith() - Check suffix
 * - str.len() - String length
 */

import { Rozes, DataFrame as DataFrameType } from '../../dist/index.mjs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main(): Promise<void> {
  console.log('📝 String Operations API Showcase (TypeScript)\n');

  // Initialize Rozes
  const wasmPath = join(__dirname, '../../zig-out/bin/rozes.wasm');
  const rozes = await Rozes.init(wasmPath);
  console.log('✅ Rozes initialized\n');

  const DataFrame = rozes.DataFrame;

  // Sample dataset with various string patterns
  const csv: string = `name,email,product,description,tags
Alice Smith,Alice.Smith@Example.COM,  Widget A  ,"  High-quality widget  ","#electronics #new"
Bob Jones,bob@COMPANY.com,Gadget B,"Premium gadget for professionals","#tools #premium"
Charlie Brown,  charlie@email.net  ,Tool C,"  Basic tool set  ","#tools #basic"
Diana Lee,DIANA.LEE@CORP.IO,Widget D,"Advanced widget system","#electronics #advanced"
Eve Wilson,eve@example.org,Part E,"  Replacement part  ","#parts #maintenance"`;

  const df: DataFrameType = DataFrame.fromCSV(csv);
  console.log('Original DataFrame:');
  df.show();
  console.log();

  // Example 1: Convert to lowercase
  console.log('1️⃣  Convert to Lowercase: strLower()');
  console.log('─'.repeat(50));
  const dfLowerEmail: DataFrameType = df.strLower('email');
  console.log('Email addresses in lowercase:');
  dfLowerEmail.select(['name', 'email']).show();
  console.log();

  // Example 2: Convert to uppercase
  console.log('2️⃣  Convert to Uppercase: strUpper()');
  console.log('─'.repeat(50));
  const dfUpperProduct: DataFrameType = df.strUpper('product');
  console.log('Products in uppercase:');
  dfUpperProduct.select(['name', 'product']).show();
  console.log();

  // Example 3: Trim whitespace
  console.log('3️⃣  Trim Whitespace: strTrim()');
  console.log('─'.repeat(50));
  const dfTrimProduct: DataFrameType = df.strTrim('product');
  const dfTrimDesc: DataFrameType = dfTrimProduct.strTrim('description');
  console.log('Products and descriptions trimmed:');
  dfTrimDesc.select(['product', 'description']).show();
  console.log();

  // Example 4: Check if contains substring
  console.log('4️⃣  Check Contains: strContains()');
  console.log('─'.repeat(50));
  console.log('Find emails containing "example":');
  const dfContainsExample: DataFrameType = df.strContains('email', 'example');
  dfContainsExample.select(['name', 'email', 'email_contains']).show();
  console.log();

  console.log('Find descriptions containing "widget":');
  const dfContainsWidget: DataFrameType = df.strContains('description', 'widget');
  dfContainsWidget.select(['product', 'description', 'description_contains']).show();
  console.log();

  // Example 5: Replace substring
  console.log('5️⃣  Replace Substring: strReplace()');
  console.log('─'.repeat(50));
  console.log('Replace "Widget" with "Component":');
  const dfReplaceProduct: DataFrameType = df.strReplace('product', 'Widget', 'Component');
  dfReplaceProduct.select(['product']).show();
  console.log();

  console.log('Replace "#" with "Tag:" in tags:');
  const dfReplaceTags: DataFrameType = df.strReplace('tags', '#', 'Tag:');
  dfReplaceTags.select(['tags']).show();
  console.log();

  // Example 6: Extract substring (slice)
  console.log('6️⃣  Extract Substring: strSlice()');
  console.log('─'.repeat(50));
  console.log('Extract first 3 characters of name:');
  const dfSliceName: DataFrameType = df.strSlice('name', 0, 3);
  dfSliceName.select(['name']).show();
  console.log();

  console.log('Extract domain from email (characters after @):');
  // Note: This is a simple example; real email parsing needs more logic
  const dfEmailProcessed: DataFrameType = df.strLower('email');
  console.log('Email domains (showing full email for reference):');
  dfEmailProcessed.select(['email']).show();
  console.log();

  // Example 7: Check if starts with prefix
  console.log('7️⃣  Check Starts With: strStartsWith()');
  console.log('─'.repeat(50));
  console.log('Find products starting with "Widget":');
  const dfStartsWidget: DataFrameType = df.strStartsWith('product', 'Widget');
  dfStartsWidget.select(['product', 'product_startswith']).show();
  console.log();

  console.log('Find tags starting with "#electronics":');
  const dfStartsElec: DataFrameType = df.strStartsWith('tags', '#electronics');
  dfStartsElec.select(['product', 'tags', 'tags_startswith']).show();
  console.log();

  // Example 8: Check if ends with suffix
  console.log('8️⃣  Check Ends With: strEndsWith()');
  console.log('─'.repeat(50));
  console.log('Find emails ending with ".com":');
  const dfEndsCom: DataFrameType = df.strEndsWith('email', '.com');
  dfEndsCom.select(['name', 'email', 'email_endswith']).show();
  console.log();

  console.log('Find descriptions ending with "  " (whitespace):');
  const dfEndsSpace: DataFrameType = df.strEndsWith('description', '  ');
  dfEndsSpace.select(['description', 'description_endswith']).show();
  console.log();

  // Example 9: Get string length
  console.log('9️⃣  Get String Length: strLen()');
  console.log('─'.repeat(50));
  console.log('Calculate name lengths:');
  const dfNameLen: DataFrameType = df.strLen('name');
  dfNameLen.select(['name', 'name_len']).show();
  console.log();

  console.log('Calculate email lengths:');
  const dfEmailLen: DataFrameType = df.strLen('email');
  dfEmailLen.select(['email', 'email_len']).show();
  console.log();

  // Example 10: Chaining string operations
  console.log('🔟 Chaining String Operations');
  console.log('─'.repeat(50));
  console.log('Clean email workflow: trim → lowercase');
  const dfEmailCleaned: DataFrameType = df
    .strTrim('email')
    .strLower('email');
  dfEmailCleaned.select(['name', 'email']).show();
  console.log();

  console.log('Clean product workflow: trim → uppercase → replace');
  const dfProductCleaned: DataFrameType = df
    .strTrim('product')
    .strUpper('product')
    .strReplace('product', 'WIDGET', 'COMPONENT');
  dfProductCleaned.select(['product']).show();
  console.log();

  // Example 11: Filtering based on string operations
  console.log('1️⃣1️⃣  Filter Using String Checks');
  console.log('─'.repeat(50));
  console.log('Filter: Products containing "Widget"');

  const dfWidgets: DataFrameType = df.filter((row) => {
    const product = row.get('product');
    return product && product.includes('Widget');
  });
  dfWidgets.show();
  console.log();

  console.log('Filter: Emails ending with ".com"');
  const dfComEmails: DataFrameType = df.filter((row) => {
    const email = row.get('email');
    return email && email.toLowerCase().trim().endsWith('.com');
  });
  dfComEmails.show();
  console.log();

  // Example 12: Data normalization workflow
  console.log('1️⃣2️⃣  Complete Data Normalization');
  console.log('─'.repeat(50));
  console.log('Normalize all string fields:');

  const dfNormalized: DataFrameType = df
    .strTrim('name')
    .strTrim('email')
    .strLower('email')
    .strTrim('product')
    .strTrim('description')
    .strTrim('tags');

  dfNormalized.show();
  console.log();

  // Cleanup
  df.free();
  dfLowerEmail.free();
  dfUpperProduct.free();
  dfTrimProduct.free();
  dfTrimDesc.free();
  dfContainsExample.free();
  dfContainsWidget.free();
  dfReplaceProduct.free();
  dfReplaceTags.free();
  dfSliceName.free();
  dfEmailProcessed.free();
  dfStartsWidget.free();
  dfStartsElec.free();
  dfEndsCom.free();
  dfEndsSpace.free();
  dfNameLen.free();
  dfEmailLen.free();
  dfEmailCleaned.free();
  dfProductCleaned.free();
  dfWidgets.free();
  dfComEmails.free();
  dfNormalized.free();

  console.log('✅ String operations showcase complete!');
}

// Run examples
main().catch(console.error);
