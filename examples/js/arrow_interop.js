/**
 * Apache Arrow Interop API Showcase
 *
 * ⚠️ NOTE: This is an MVP implementation (v1.3.0)
 * - Schema export/import is supported
 * - Full IPC data transfer is planned for v1.4.0
 *
 * Demonstrates Apache Arrow format interoperability:
 * - toArrow() - Export DataFrame schema to Arrow format
 * - fromArrow() - Import DataFrame from Arrow schema
 */

import { Rozes } from '../../dist/index.mjs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main() {
  console.log('🏹 Apache Arrow Interop API Showcase\n');
  console.log('⚠️  MVP: Schema-only export/import (v1.3.0)\n');

  // Initialize Rozes
  const wasmPath = join(__dirname, '../../zig-out/bin/rozes.wasm');
  const rozes = await Rozes.init(wasmPath);
  console.log('✅ Rozes initialized\n');

  const DataFrame = rozes.DataFrame;

  // Example 1: Export schema to Arrow format
  console.log('1️⃣  Export Schema: toArrow()');
  console.log('─'.repeat(50));

  const csv = `name:String,age:Int64,score:Float64,active:Bool
Alice,30,95.5,true
Bob,25,87.3,false
Charlie,35,91.0,true`;

  const df = DataFrame.fromCSV(csv);
  console.log('Original DataFrame:');
  df.show();
  console.log();

  try {
    const arrowSchema = df.toArrow();
    console.log('Exported Arrow Schema:');
    console.log(JSON.stringify(arrowSchema, null, 2));
    console.log();

    // Display schema fields
    if (arrowSchema.schema && arrowSchema.schema.fields) {
      console.log('Schema Fields:');
      for (const field of arrowSchema.schema.fields) {
        console.log(`  - ${field.name}: ${field.type.name} (nullable: ${field.nullable})`);
      }
      console.log();
    }
  } catch (err) {
    console.error('❌ toArrow() error:', err.message);
    console.log();
  }

  // Example 2: Import DataFrame from Arrow schema
  console.log('2️⃣  Import from Schema: fromArrow()');
  console.log('─'.repeat(50));

  const arrowSchema = {
    schema: {
      fields: [
        { name: 'id', type: { name: 'int' }, nullable: false },
        { name: 'value', type: { name: 'floatingpoint' }, nullable: false },
        { name: 'label', type: { name: 'utf8' }, nullable: true }
      ]
    }
  };

  console.log('Arrow Schema to import:');
  console.log(JSON.stringify(arrowSchema, null, 2));
  console.log();

  try {
    const dfFromArrow = DataFrame.fromArrow(arrowSchema);
    console.log('Imported DataFrame:');
    dfFromArrow.show();
    console.log(`Shape: ${dfFromArrow.shape.rows} rows × ${dfFromArrow.shape.cols} columns`);
    console.log();
    dfFromArrow.free();
  } catch (err) {
    console.error('❌ fromArrow() error:', err.message);
    console.log();
  }

  // Example 3: Round-trip (DataFrame → Arrow → DataFrame)
  console.log('3️⃣  Round-Trip: DataFrame → Arrow → DataFrame');
  console.log('─'.repeat(50));

  try {
    const schema1 = df.toArrow();
    console.log('Step 1: Exported schema');
    console.log(`  Fields: ${schema1.schema.fields.length}`);
    console.log();

    const dfRoundTrip = DataFrame.fromArrow(schema1);
    console.log('Step 2: Re-imported DataFrame');
    dfRoundTrip.show();
    console.log();

    const schema2 = dfRoundTrip.toArrow();
    console.log('Step 3: Re-exported schema (should match)');
    console.log(`  Fields: ${schema2.schema.fields.length}`);
    console.log();

    // Verify schemas match
    if (JSON.stringify(schema1) === JSON.stringify(schema2)) {
      console.log('✅ Round-trip successful: Schemas match');
    } else {
      console.log('⚠️  Warning: Schemas differ after round-trip');
    }
    console.log();

    dfRoundTrip.free();
  } catch (err) {
    console.error('❌ Round-trip error:', err.message);
    console.log();
  }

  // Example 4: Type mapping (Rozes ↔ Arrow)
  console.log('4️⃣  Type Mapping: Rozes ↔ Arrow');
  console.log('─'.repeat(50));

  console.log('Supported type conversions:');
  console.log('  Rozes          → Arrow');
  console.log('  ─────────────────────────────');
  console.log('  Int64          → int');
  console.log('  Float64        → floatingpoint');
  console.log('  String         → utf8');
  console.log('  Bool           → bool');
  console.log('  Categorical    → dictionary');
  console.log('  Null           → null');
  console.log();

  // Example 5: Schema validation
  console.log('5️⃣  Schema Validation');
  console.log('─'.repeat(50));

  const validSchemas = [
    {
      name: 'All types',
      schema: {
        schema: {
          fields: [
            { name: 'int_col', type: { name: 'int' }, nullable: false },
            { name: 'float_col', type: { name: 'floatingpoint' }, nullable: false },
            { name: 'str_col', type: { name: 'utf8' }, nullable: true },
            { name: 'bool_col', type: { name: 'bool' }, nullable: false }
          ]
        }
      }
    },
    {
      name: 'Single column',
      schema: {
        schema: {
          fields: [
            { name: 'value', type: { name: 'int' }, nullable: false }
          ]
        }
      }
    }
  ];

  for (const test of validSchemas) {
    console.log(`\nValidating: ${test.name}`);
    try {
      const testDf = DataFrame.fromArrow(test.schema);
      console.log(`✅ Valid schema (${testDf.shape.cols} columns)`);
      testDf.free();
    } catch (err) {
      console.log(`❌ Invalid schema: ${err.message}`);
    }
  }
  console.log();

  // Example 6: Future use cases (v1.4.0+)
  console.log('6️⃣  Future Enhancements (v1.4.0+)');
  console.log('─'.repeat(50));

  console.log('Planned features:');
  console.log('  📦 Full IPC data transfer (not just schema)');
  console.log('  🚀 Zero-copy data exchange where possible');
  console.log('  🔄 Arrow RecordBatch import/export');
  console.log('  💾 Arrow file format support (.arrow, .feather)');
  console.log('  🔗 Interop with Apache Arrow JS library');
  console.log('  ⚡ Stream large datasets via Arrow IPC');
  console.log();

  console.log('Example use case (future):');
  console.log('  // Load Arrow file directly');
  console.log('  const df = await DataFrame.fromArrowFile("data.arrow");');
  console.log('  ');
  console.log('  // Export to Arrow IPC format');
  console.log('  await df.toArrowFile("output.arrow");');
  console.log();

  // Cleanup
  df.free();

  console.log('✅ Arrow interop showcase complete!');
  console.log('\n💡 Tip: For production use, wait for v1.4.0 with full IPC support');
}

// Run examples
main().catch(console.error);
