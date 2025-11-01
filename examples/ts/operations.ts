/**
 * Rozes DataFrame Operations Example - TypeScript
 *
 * Demonstrates all DataFrame operations with full type safety:
 * filter, select, head, tail, sort, and operation chaining
 */

import { Rozes, DataFrame } from '../../dist/index.js';

async function main(): Promise<void> {
    console.log('🌹 Rozes DataFrame Library - Operations Example (TypeScript)\n');

    // Initialize Rozes with type safety
    console.log('Initializing Rozes...');
    const rozes: Rozes = await Rozes.init();
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

    const df: DataFrame = rozes.DataFrame.fromCSV(csv);
    console.log(`📊 Original DataFrame: ${df.shape.rows} rows × ${df.shape.cols} columns`);
    console.log(`   Columns: ${df.columns.join(', ')}\n`);

    // ═══════════════════════════════════════════════════════════════
    // 1. FILTER - Filter rows by condition (type-safe operators)
    // ═══════════════════════════════════════════════════════════════
    console.log('─'.repeat(60));
    console.log('1️⃣  FILTER OPERATION');
    console.log('─'.repeat(60));

    // Filter: age >= 30 (TypeScript ensures operator is valid)
    console.log('\n🔍 Filter: employees age >= 30');
    const adults: DataFrame = df.filter('age', '>=', 30);
    console.log(`   Result: ${adults.shape.rows} employees`);
    const adultAges = adults.column('age');
    if (adultAges) {
        console.log(`   Ages: [${Array.from(adultAges).join(', ')}]`);
    }
    adults.free();

    // Filter: salary > 100000
    console.log('\n🔍 Filter: high earners (salary > $100,000)');
    const highEarners: DataFrame = df.filter('salary', '>', 100000);
    console.log(`   Result: ${highEarners.shape.rows} employees`);
    const salaries = highEarners.column('salary');
    if (salaries) {
        console.log(`   Salaries: [${Array.from(salaries).map(s => `$${s.toLocaleString()}`).join(', ')}]`);
    }
    highEarners.free();

    // ═══════════════════════════════════════════════════════════════
    // 2. SELECT - Select specific columns
    // ═══════════════════════════════════════════════════════════════
    console.log('\n' + '─'.repeat(60));
    console.log('2️⃣  SELECT OPERATION');
    console.log('─'.repeat(60));

    // Select: name and salary only
    console.log('\n📋 Select: name and salary columns');
    const nameSalary: DataFrame = df.select(['name', 'salary']);
    console.log(`   Result: ${nameSalary.shape.rows} rows × ${nameSalary.shape.cols} columns`);
    console.log(`   Columns: ${nameSalary.columns.join(', ')}`);
    nameSalary.free();

    // ═══════════════════════════════════════════════════════════════
    // 3. HEAD & TAIL - Get first/last rows
    // ═══════════════════════════════════════════════════════════════
    console.log('\n' + '─'.repeat(60));
    console.log('3️⃣  HEAD & TAIL OPERATIONS');
    console.log('─'.repeat(60));

    // Head: first 3 employees
    console.log('\n📄 Head: first 3 employees');
    const top3: DataFrame = df.head(3);
    console.log(`   Result: ${top3.shape.rows} rows`);
    const top3Ages = top3.column('age');
    if (top3Ages) {
        console.log(`   Ages: [${Array.from(top3Ages).join(', ')}]`);
    }
    top3.free();

    // Tail: last 3 employees
    console.log('\n📄 Tail: last 3 employees');
    const bottom3: DataFrame = df.tail(3);
    console.log(`   Result: ${bottom3.shape.rows} rows`);
    const bottom3Ages = bottom3.column('age');
    if (bottom3Ages) {
        console.log(`   Ages: [${Array.from(bottom3Ages).join(', ')}]`);
    }
    bottom3.free();

    // ═══════════════════════════════════════════════════════════════
    // 4. SORT - Sort by column
    // ═══════════════════════════════════════════════════════════════
    console.log('\n' + '─'.repeat(60));
    console.log('4️⃣  SORT OPERATION');
    console.log('─'.repeat(60));

    // Sort: by age (ascending)
    console.log('\n🔢 Sort: by age (ascending)');
    const sortedByAge: DataFrame = df.sort('age');
    console.log(`   Result: ${sortedByAge.shape.rows} rows`);
    const sortedAges = sortedByAge.column('age');
    if (sortedAges) {
        console.log(`   Ages: [${Array.from(sortedAges).join(', ')}]`);
    }
    sortedByAge.free();

    // Sort: by salary (descending - type-safe boolean)
    console.log('\n🔢 Sort: by salary (descending)');
    const sortedBySalary: DataFrame = df.sort('salary', true);
    console.log(`   Result: ${sortedBySalary.shape.rows} rows`);
    const topSalaries = sortedBySalary.column('salary');
    if (topSalaries) {
        console.log(`   Top 3 salaries: [${Array.from(topSalaries).slice(0, 3).map(s => `$${s.toLocaleString()}`).join(', ')}]`);
    }
    sortedBySalary.free();

    // ═══════════════════════════════════════════════════════════════
    // 5. OPERATION CHAINING - Combine multiple operations
    // ═══════════════════════════════════════════════════════════════
    console.log('\n' + '═'.repeat(60));
    console.log('5️⃣  OPERATION CHAINING - Complex Transformations');
    console.log('═'.repeat(60));

    // Example 1: Filter → Select → Sort
    console.log('\n🔗 Chain 1: High earners (>$70k) → Select numeric columns → Sort by salary');
    const highPaid: DataFrame = df.filter('salary', '>', 70000);
    const highPaidSalaries: DataFrame = highPaid.select(['age', 'salary', 'years_experience']);
    const sortedHighPaid: DataFrame = highPaidSalaries.sort('salary', true);

    console.log(`   Result: ${sortedHighPaid.shape.rows} high earners, sorted by salary`);
    const finalSalaries = sortedHighPaid.column('salary');
    const finalAges = sortedHighPaid.column('age');
    if (finalSalaries && finalAges) {
        console.log(`   Top 3 salaries: [${Array.from(finalSalaries).slice(0, 3).map(s => `$${s.toLocaleString()}`).join(', ')}]`);
        console.log(`   Corresponding ages: [${Array.from(finalAges).slice(0, 3).join(', ')}]`);
    }

    sortedHighPaid.free();
    highPaidSalaries.free();
    highPaid.free();

    // Example 2: Filter → Sort → Head (type-safe chaining)
    console.log('\n🔗 Chain 2: Experienced (>5 years) → Sort by salary → Top 3');
    const experienced: DataFrame = df.filter('years_experience', '>', 5);
    const expSorted: DataFrame = experienced.sort('salary', true);
    const top3Exp: DataFrame = expSorted.head(3);

    console.log(`   Result: Top 3 highest-paid experienced employees`);
    const expSalaries = top3Exp.column('salary');
    const expYears = top3Exp.column('years_experience');

    if (expSalaries && expYears) {
        for (let i = 0; i < expSalaries.length; i++) {
            console.log(`      ${i + 1}. $${expSalaries[i].toLocaleString()}/year, ${expYears[i]} years exp`);
        }
    }

    top3Exp.free();
    expSorted.free();
    experienced.free();

    // Example 3: Complex multi-step transformation
    console.log('\n🔗 Chain 3: Age 25-35 → Salary >$70k → Sort by experience → Top 3');
    const youngAdults: DataFrame = df.filter('age', '>=', 25);
    const youngAdultsMax: DataFrame = youngAdults.filter('age', '<=', 35);
    const wellPaid: DataFrame = youngAdultsMax.filter('salary', '>', 70000);
    const sortedByExp: DataFrame = wellPaid.sort('years_experience', true);
    const top3Final: DataFrame = sortedByExp.head(3);

    console.log(`   Result: ${top3Final.shape.rows} young, well-paid, experienced employees`);
    const chain3Ages = top3Final.column('age');
    const chain3Exp = top3Final.column('years_experience');
    const chain3Sal = top3Final.column('salary');

    if (chain3Ages && chain3Exp && chain3Sal) {
        console.log('   Profile:');
        for (let i = 0; i < chain3Ages.length; i++) {
            console.log(`      ${i + 1}. Age ${chain3Ages[i]}, ${chain3Exp[i]} years, $${chain3Sal[i].toLocaleString()}/year`);
        }
    }

    // Clean up in reverse order (best practice)
    top3Final.free();
    sortedByExp.free();
    wellPaid.free();
    youngAdultsMax.free();
    youngAdults.free();

    // ═══════════════════════════════════════════════════════════════
    // 6. PRACTICAL USE CASE - Type-Safe Data Analysis
    // ═══════════════════════════════════════════════════════════════
    console.log('\n' + '═'.repeat(60));
    console.log('6️⃣  PRACTICAL USE CASE - Junior Talent Investment Analysis');
    console.log('═'.repeat(60));

    console.log('\n📊 Goal: Find junior employees (<5 years) with high potential');
    console.log('   (Age <30, performing well, earning <$80k)');

    // Type-safe pipeline
    const juniorEmployees: DataFrame = df.filter('years_experience', '<', 5);
    console.log(`\n   Step 1: Filter experience < 5 years → ${juniorEmployees.shape.rows} employees`);

    const youngJuniors: DataFrame = juniorEmployees.filter('age', '<', 30);
    console.log(`   Step 2: Filter age < 30 → ${youngJuniors.shape.rows} employees`);

    const affordableJuniors: DataFrame = youngJuniors.filter('salary', '<', 80000);
    console.log(`   Step 3: Filter salary < $80k → ${affordableJuniors.shape.rows} employees`);

    const talentProfile: DataFrame = affordableJuniors.select(['age', 'salary', 'years_experience']);
    const sortedTalent: DataFrame = talentProfile.sort('salary', true);
    console.log(`   Step 4: Select numeric profile & sort by salary`);

    console.log('\n   📋 High-Potential Junior Talent:');
    const profileAges = sortedTalent.column('age');
    const profileExp = sortedTalent.column('years_experience');
    const profileSal = sortedTalent.column('salary');

    if (profileAges && profileExp && profileSal) {
        for (let i = 0; i < profileAges.length; i++) {
            console.log(`      ${i + 1}. Age ${profileAges[i]}, ${profileExp[i]} years, $${profileSal[i].toLocaleString()}/year`);
        }
    }

    // Clean up
    sortedTalent.free();
    talentProfile.free();
    affordableJuniors.free();
    youngJuniors.free();
    juniorEmployees.free();

    // ═══════════════════════════════════════════════════════════════
    // Final cleanup
    // ═══════════════════════════════════════════════════════════════
    df.free();
    console.log('\n✅ All DataFrames freed');

    console.log('\n' + '═'.repeat(60));
    console.log('🎉 Operations example completed successfully!');
    console.log('   TypeScript ensures type safety at compile time');
    console.log('═'.repeat(60));
}

main().catch((err: Error) => {
    console.error('❌ Error:', err);
    process.exit(1);
});
