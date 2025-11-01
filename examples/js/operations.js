/**
 * Rozes DataFrame Operations Example - Node.js
 *
 * Demonstrates all DataFrame operations: filter, select, head, tail, sort
 * and operation chaining for complex data transformations
 */

const { Rozes } = require('../../dist/index.js');

async function main() {
    console.log('🌹 Rozes DataFrame Library - Operations Example\n');

    // Initialize Rozes
    console.log('Initializing Rozes...');
    const rozes = await Rozes.init();
    console.log(`✅ Rozes ${rozes.version} initialized\n`);

    // Create sample DataFrame with employee data
    const csv = `name,age,department,salary,years_experience
Alice Johnson,30,Engineering,95000,5
Bob Smith,25,Sales,67000,2
Charlie Davis,35,Engineering,110000,10
Diana Wilson,28,Marketing,72000,4
Eve Brown,45,Engineering,125000,18
Frank Miller,32,Sales,78000,7
Grace Lee,29,Marketing,75000,3
Henry Taylor,38,Engineering,105000,12
Iris Anderson,26,Sales,65000,1
Jack White,41,Engineering,115000,15`;

    const df = rozes.DataFrame.fromCSV(csv);
    console.log(`📊 Original DataFrame: ${df.shape.rows} rows × ${df.shape.cols} columns`);
    console.log(`   Columns: ${df.columns.join(', ')}\n`);

    // ═══════════════════════════════════════════════════════════════
    // 1. FILTER - Filter rows by condition
    // ═══════════════════════════════════════════════════════════════
    console.log('─'.repeat(60));
    console.log('1️⃣  FILTER OPERATION');
    console.log('─'.repeat(60));

    // Filter: age >= 30
    console.log('\n🔍 Filter: employees age >= 30');
    const adults = df.filter('age', '>=', 30);
    console.log(`   Result: ${adults.shape.rows} employees`);
    const adultAges = adults.column('age');
    console.log(`   Ages: [${Array.from(adultAges).join(', ')}]`);
    adults.free();

    // Filter: salary > 100000
    console.log('\n🔍 Filter: high earners (salary > $100,000)');
    const highEarners = df.filter('salary', '>', 100000);
    console.log(`   Result: ${highEarners.shape.rows} employees`);
    const salaries = highEarners.column('salary');
    console.log(`   Salaries: [${Array.from(salaries).map(s => `$${s.toLocaleString()}`).join(', ')}]`);
    highEarners.free();

    // Filter: years_experience == 5
    console.log('\n🔍 Filter: exactly 5 years experience');
    const fiveYears = df.filter('years_experience', '==', 5);
    console.log(`   Result: ${fiveYears.shape.rows} employees`);
    fiveYears.free();

    // ═══════════════════════════════════════════════════════════════
    // 2. SELECT - Select specific columns
    // ═══════════════════════════════════════════════════════════════
    console.log('\n' + '─'.repeat(60));
    console.log('2️⃣  SELECT OPERATION');
    console.log('─'.repeat(60));

    // Select: name and salary only
    console.log('\n📋 Select: name and salary columns');
    const nameSalary = df.select(['name', 'salary']);
    console.log(`   Result: ${nameSalary.shape.rows} rows × ${nameSalary.shape.cols} columns`);
    console.log(`   Columns: ${nameSalary.columns.join(', ')}`);
    nameSalary.free();

    // Select: department, age, years_experience
    console.log('\n📋 Select: department, age, experience');
    const profile = df.select(['department', 'age', 'years_experience']);
    console.log(`   Result: ${profile.shape.rows} rows × ${profile.shape.cols} columns`);
    console.log(`   Columns: ${profile.columns.join(', ')}`);
    profile.free();

    // ═══════════════════════════════════════════════════════════════
    // 3. HEAD & TAIL - Get first/last rows
    // ═══════════════════════════════════════════════════════════════
    console.log('\n' + '─'.repeat(60));
    console.log('3️⃣  HEAD & TAIL OPERATIONS');
    console.log('─'.repeat(60));

    // Head: first 3 employees
    console.log('\n📄 Head: first 3 employees');
    const top3 = df.head(3);
    console.log(`   Result: ${top3.shape.rows} rows`);
    const top3Ages = top3.column('age');
    console.log(`   Ages: [${Array.from(top3Ages).join(', ')}]`);
    top3.free();

    // Tail: last 3 employees
    console.log('\n📄 Tail: last 3 employees');
    const bottom3 = df.tail(3);
    console.log(`   Result: ${bottom3.shape.rows} rows`);
    const bottom3Ages = bottom3.column('age');
    console.log(`   Ages: [${Array.from(bottom3Ages).join(', ')}]`);
    bottom3.free();

    // ═══════════════════════════════════════════════════════════════
    // 4. SORT - Sort by column
    // ═══════════════════════════════════════════════════════════════
    console.log('\n' + '─'.repeat(60));
    console.log('4️⃣  SORT OPERATION');
    console.log('─'.repeat(60));

    // Sort: by age (ascending)
    console.log('\n🔢 Sort: by age (ascending)');
    const sortedByAge = df.sort('age');
    console.log(`   Result: ${sortedByAge.shape.rows} rows`);
    const sortedAges = sortedByAge.column('age');
    console.log(`   Ages: [${Array.from(sortedAges).join(', ')}]`);
    sortedByAge.free();

    // Sort: by salary (descending)
    console.log('\n🔢 Sort: by salary (descending)');
    const sortedBySalary = df.sort('salary', true);
    console.log(`   Result: ${sortedBySalary.shape.rows} rows`);
    const topSalaries = sortedBySalary.column('salary');
    console.log(`   Top 3 salaries: [${Array.from(topSalaries).slice(0, 3).map(s => `$${s.toLocaleString()}`).join(', ')}]`);
    sortedBySalary.free();

    // ═══════════════════════════════════════════════════════════════
    // 5. OPERATION CHAINING - Combine multiple operations
    // ═══════════════════════════════════════════════════════════════
    console.log('\n' + '═'.repeat(60));
    console.log('5️⃣  OPERATION CHAINING - Complex Transformations');
    console.log('═'.repeat(60));

    // Example 1: Filter → Select → Sort
    console.log('\n🔗 Chain 1: Age >= 30 → Select numeric columns → Sort by salary');
    const adults30Plus = df.filter('age', '>=', 30);
    const adultsSalaries = adults30Plus.select(['age', 'salary', 'years_experience']);
    const adultsSorted = adultsSalaries.sort('salary', true);
    console.log(`   Result: ${adultsSorted.shape.rows} employees age >= 30, sorted by salary`);
    const finalSalaries = adultsSorted.column('salary');
    const finalAges = adultsSorted.column('age');
    console.log(`   Top 3 ages: [${Array.from(finalAges).slice(0, 3).join(', ')}]`);
    console.log(`   Top 3 salaries: [${Array.from(finalSalaries).slice(0, 3).map(s => `$${s.toLocaleString()}`).join(', ')}]`);
    adultsSorted.free();
    adultsSalaries.free();
    adults30Plus.free();

    // Example 2: Filter → Sort → Head
    console.log('\n🔗 Chain 2: High earners (>$70k) → Sort by experience → Top 5');
    const highPaid = df.filter('salary', '>', 70000);
    const sortedByExp = highPaid.sort('years_experience', true);
    const top5 = sortedByExp.head(5);
    console.log(`   Result: Top 5 most experienced high earners`);
    const expYears = top5.column('years_experience');
    const expSalaries = top5.column('salary');
    console.log(`   Experience: [${Array.from(expYears).join(', ')} years]`);
    console.log(`   Salaries: [${Array.from(expSalaries).map(s => `$${s.toLocaleString()}`).join(', ')}]`);
    top5.free();
    sortedByExp.free();
    highPaid.free();

    // Example 3: Filter → Filter → Select → Tail
    console.log('\n🔗 Chain 3: Young (<35) & experienced (>3 years) → Select numeric profile → Last 2');
    const young = df.filter('age', '<', 35);
    const experienced = young.filter('years_experience', '>', 3);
    const profileData = experienced.select(['age', 'years_experience', 'salary']);
    const last2 = profileData.tail(2);
    console.log(`   Result: ${last2.shape.rows} matching employees`);
    const profileAges = last2.column('age');
    const profileExp = last2.column('years_experience');
    const profileSal = last2.column('salary');
    if (profileAges && profileExp && profileSal) {
        console.log(`   Ages: [${Array.from(profileAges).join(', ')}]`);
        console.log(`   Experience: [${Array.from(profileExp).join(', ')} years]`);
        console.log(`   Salaries: [${Array.from(profileSal).map(s => `$${s.toLocaleString()}`).join(', ')}]`);
    }
    last2.free();
    profileData.free();
    experienced.free();
    young.free();

    // ═══════════════════════════════════════════════════════════════
    // 6. PRACTICAL USE CASE - Data Analysis Pipeline
    // ═══════════════════════════════════════════════════════════════
    console.log('\n' + '═'.repeat(60));
    console.log('6️⃣  PRACTICAL USE CASE - Senior Engineering Talent Analysis');
    console.log('═'.repeat(60));

    console.log('\n📊 Goal: Find senior engineers (10+ years) earning under $120k');
    console.log('   (Potential retention risk)');

    const seniorEngineers = df.filter('years_experience', '>=', 10);
    console.log(`\n   Step 1: Filter experience >= 10 years → ${seniorEngineers.shape.rows} employees`);

    const underPaid = seniorEngineers.filter('salary', '<', 120000);
    console.log(`   Step 2: Filter salary < $120k → ${underPaid.shape.rows} at-risk employees`);

    const analysis = underPaid.select(['age', 'salary', 'years_experience']);
    const finalAnalysis = analysis.sort('years_experience', true);
    console.log(`   Step 3: Select numeric columns & sort by experience`);

    console.log('\n   📋 At-Risk Senior Talent:');
    const finalExp = finalAnalysis.column('years_experience');
    const finalSal = finalAnalysis.column('salary');
    const finalAge = finalAnalysis.column('age');
    if (finalExp && finalSal && finalAge) {
        for (let i = 0; i < finalExp.length; i++) {
            console.log(`      ${i + 1}. Age ${finalAge[i]}, ${finalExp[i]} years exp, $${finalSal[i].toLocaleString()}/year`);
        }
    }

    // Clean up
    finalAnalysis.free();
    analysis.free();
    underPaid.free();
    seniorEngineers.free();

    // ═══════════════════════════════════════════════════════════════
    // Final cleanup
    // ═══════════════════════════════════════════════════════════════
    df.free();
    console.log('\n✅ All DataFrames freed');

    console.log('\n' + '═'.repeat(60));
    console.log('🎉 Operations example completed successfully!');
    console.log('═'.repeat(60));
}

main().catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
});
