/**
 * Rozes Basic Example - Node.js
 *
 * Demonstrates basic DataFrame operations in Node.js
 */

const { Rozes } = require('../../dist/index.js');

async function main() {
    console.log('🌹 Rozes DataFrame Library - Basic Example\n');

    // Initialize Rozes
    console.log('Initializing Rozes...');
    const rozes = await Rozes.init();
    console.log(`✅ Rozes ${rozes.version} initialized\n`);

    // Parse CSV
    console.log('Parsing CSV...');
    const csv = `name,age,score
Alice,30,95.5
Bob,25,87.3
Charlie,35,91.0`;

    const df = rozes.DataFrame.fromCSV(csv);
    console.log(`✅ DataFrame created: ${df.shape.rows} rows × ${df.shape.cols} columns`);
    console.log(`   Columns: ${df.columns.join(', ')}\n`);

    // Access column data
    console.log('Accessing column data...');
    const ages = df.column('age');
    console.log(`   Ages: [${Array.from(ages).join(', ')}]`);

    const scores = df.column('score');
    console.log(`   Scores: [${Array.from(scores).join(', ')}]\n`);

    // Clean up
    df.free();
    console.log('✅ DataFrame freed');

    console.log('\n🎉 Example completed successfully!');
}

main().catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
});
