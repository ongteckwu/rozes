/**
 * Apache Arrow Integration Tests
 *
 * Tests Arrow schema export/import (MVP: schema-only, data transfer deferred)
 */

import { Rozes } from '../../../dist/index.mjs';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main() {
  console.log('🧪 Testing Apache Arrow Integration\n');

  // Initialize Rozes
  const wasmPath = join(__dirname, '../../../zig-out/bin/rozes.wasm');
  const rozes = await Rozes.init(wasmPath);
  console.log('✅ Rozes initialized (version:', rozes.version, ')\n');

  let passedTests = 0;
  let totalTests = 0;

  function test(name, fn) {
    totalTests++;
    try {
      fn();
      console.log(`✅ ${name}`);
      passedTests++;
    } catch (err) {
      console.error(`❌ ${name}`);
      console.error('  ', err.message);
    }
  }

  const DataFrame = rozes.DataFrame;

  test('Arrow: toArrow() exports schema for all column types', () => {
    const csv = 'name:String,age:Int64,score:Float64,active:Bool\nAlice,30,95.5,true\nBob,25,87.3,false\n';
    const df = DataFrame.fromCSV(csv);
    const arrowSchema = df.toArrow();

    if (!arrowSchema.schema) throw new Error('Should have schema object');
    if (!Array.isArray(arrowSchema.schema.fields)) throw new Error('Should have fields array');
    if (arrowSchema.schema.fields.length !== 4) throw new Error(`Expected 4 fields, got ${arrowSchema.schema.fields.length}`);

    const fields = arrowSchema.schema.fields;
    if (fields[0].name !== 'name' || fields[0].type.name !== 'utf8') throw new Error('Field 0 mismatch');
    if (fields[1].name !== 'age' || fields[1].type.name !== 'int') throw new Error('Field 1 mismatch');
    if (fields[2].name !== 'score' || fields[2].type.name !== 'floatingpoint') throw new Error('Field 2 mismatch');
    if (fields[3].name !== 'active' || fields[3].type.name !== 'bool') throw new Error('Field 3 mismatch');

    df.free();
  });

  test('Arrow: toArrow() handles empty DataFrame', () => {
    const csv = 'name,age,score\n';
    const df = DataFrame.fromCSV(csv);
    const arrowSchema = df.toArrow();

    if (!arrowSchema.schema) throw new Error('Should have schema object');
    if (arrowSchema.schema.fields.length !== 3) throw new Error('Should have 3 fields');
    if (arrowSchema.schema.fields[0].name !== 'name') throw new Error('Should have name field');

    df.free();
  });

  test('Arrow: fromArrow() creates DataFrame from schema', () => {
    const schema = {
      schema: {
        fields: [
          { name: 'name', type: { name: 'utf8' } },
          { name: 'age', type: { name: 'int', bitWidth: 64, isSigned: true } },
          { name: 'score', type: { name: 'floatingpoint', precision: 'DOUBLE' } }
        ]
      }
    };

    const df = DataFrame.fromArrow(schema);

    if (!df) throw new Error('Should create DataFrame');
    if (df.shape.cols !== 3) throw new Error('Should have 3 columns');

    const columns = df.columns;
    if (columns.length !== 3) throw new Error('Should have 3 column names');
    if (columns[0] !== 'name' || columns[1] !== 'age' || columns[2] !== 'score') {
      throw new Error('Column names mismatch');
    }

    df.free();
  });

  test('Arrow: round-trip (toArrow → fromArrow) preserves schema', () => {
    const csv = 'name:String,age:Int64,score:Float64\nAlice,30,95.5\nBob,25,87.3\n';
    const df1 = DataFrame.fromCSV(csv);
    const arrowSchema = df1.toArrow();
    const df2 = DataFrame.fromArrow(arrowSchema);

    if (df2.shape.cols !== df1.shape.cols) throw new Error('Column count should match');
    if (JSON.stringify(df2.columns) !== JSON.stringify(df1.columns)) throw new Error('Column names should match');

    df1.free();
    df2.free();
  });

  test('Arrow: toArrow() handles String columns', () => {
    const csv = 'text\nHello\nWorld\n';
    const df = DataFrame.fromCSV(csv);
    const arrowSchema = df.toArrow();

    if (arrowSchema.schema.fields.length !== 1) throw new Error('Should have 1 field');
    if (arrowSchema.schema.fields[0].name !== 'text') throw new Error('Field should be text');
    if (arrowSchema.schema.fields[0].type.name !== 'utf8') throw new Error('Should be utf8 type');

    df.free();
  });

  test('Arrow: toArrow() handles numeric columns', () => {
    const csv = 'int_col:Int64,float_col:Float64\n42,3.14\n100,2.71\n';
    const df = DataFrame.fromCSV(csv);
    const arrowSchema = df.toArrow();

    if (arrowSchema.schema.fields.length !== 2) throw new Error('Should have 2 fields');
    if (arrowSchema.schema.fields[0].type.name !== 'int') throw new Error('Should be int type');
    if (arrowSchema.schema.fields[1].type.name !== 'floatingpoint') throw new Error('Should be floatingpoint type');

    df.free();
  });

  test('Arrow: memory leak test (1000 iterations)', () => {
    const csv = 'name,age,score\nAlice,30,95.5\nBob,25,87.3\n';

    for (let i = 0; i < 1000; i++) {
      const df = DataFrame.fromCSV(csv);
      const arrowSchema = df.toArrow();
      if (!arrowSchema.schema) throw new Error('Should have schema');
      df.free();
    }
  });

  test('Arrow: round-trip memory leak test (1000 iterations)', () => {
    const csv = 'name:String,age:Int64\nAlice,30\n';

    for (let i = 0; i < 1000; i++) {
      const df1 = DataFrame.fromCSV(csv);
      const arrowSchema = df1.toArrow();
      const df2 = DataFrame.fromArrow(arrowSchema);
      df1.free();
      df2.free();
    }
  });

  console.log(`\n📊 Arrow Tests: ${passedTests}/${totalTests} passed`);
  if (passedTests < totalTests) {
    process.exit(1);
  }
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
