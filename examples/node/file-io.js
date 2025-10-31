/**
 * Rozes File I/O Example - Node.js
 *
 * Demonstrates reading and writing CSV files
 */

const { Rozes } = require('../../dist/index.js');
const fs = require('fs');
const path = require('path');

async function main() {
    console.log('🌹 Rozes DataFrame Library - File I/O Example\n');

    // Initialize Rozes
    const rozes = await Rozes.init();
    console.log(`✅ Rozes ${rozes.version} initialized\n`);

    // Create sample CSV file
    const csvPath = path.join(__dirname, 'sample.csv');
    const csvContent = `product,price,quantity
Apple,1.20,100
Banana,0.50,150
Orange,1.80,75
Grape,2.50,60`;

    fs.writeFileSync(csvPath, csvContent);
    console.log(`✅ Created sample CSV: ${csvPath}\n`);

    // Load from file
    console.log('Loading CSV from file...');
    const df = rozes.DataFrame.fromCSVFile(csvPath);
    console.log(`✅ Loaded: ${df.shape.rows} rows × ${df.shape.cols} columns`);
    console.log(`   Columns: ${df.columns.join(', ')}\n`);

    // Access data
    const prices = df.column('price');
    const quantities = df.column('quantity');

    console.log('Product data:');
    for (let i = 0; i < prices.length; i++) {
        console.log(`   Product ${i + 1}: $${prices[i].toFixed(2)}, Qty: ${quantities[i]}`);
    }

    // Calculate total value
    let totalValue = 0;
    for (let i = 0; i < prices.length; i++) {
        // Convert BigInt to Number for calculation
        totalValue += prices[i] * Number(quantities[i]);
    }
    console.log(`\n   Total inventory value: $${totalValue.toFixed(2)}\n`);

    // NOTE: CSV export (toCSV/toCSVFile) will be added in a future release
    // For now, you can access and process data via column() method
    console.log('💡 Tip: CSV export (toCSV/toCSVFile) will be added in 1.1.0');

    // Clean up
    df.free();
    console.log('✅ DataFrame freed');

    // Clean up example files
    fs.unlinkSync(csvPath);
    console.log('✅ Cleaned up example files');

    console.log('\n🎉 File I/O example completed successfully!');
}

main().catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
});
