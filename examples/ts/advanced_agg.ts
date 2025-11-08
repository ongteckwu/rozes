/**
 * Advanced Aggregations API Showcase (TypeScript)
 *
 * Demonstrates advanced statistical aggregation operations:
 * - median() - Calculate median value
 * - quantile() - Calculate quantile (percentile)
 * - valueCounts() - Count unique value frequencies
 * - corrMatrix() - Calculate correlation matrix
 * - rank() - Rank values in column
 */

import { Rozes, DataFrame as DataFrameType, Column } from '../../dist/index.mjs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main(): Promise<void> {
  console.log('📊 Advanced Aggregations API Showcase (TypeScript)\n');

  // Initialize Rozes
  const wasmPath = join(__dirname, '../../zig-out/bin/rozes.wasm');
  const rozes = await Rozes.init(wasmPath);
  console.log('✅ Rozes initialized\n');

  const DataFrame = rozes.DataFrame;

  // Sample dataset - Student exam scores
  const csv: string = `student,math,science,english,overall,grade
Alice,95,92,88,91.7,A
Bob,78,85,82,81.7,B
Charlie,92,89,95,92.0,A
Diana,85,88,79,84.0,B
Eve,88,94,91,91.0,A
Frank,72,75,78,75.0,C
Grace,96,98,94,96.0,A
Henry,81,83,85,83.0,B
Ivy,89,87,92,89.3,B
Jack,94,91,89,91.3,A`;

  const df: DataFrameType = DataFrame.fromCSV(csv);
  console.log('Student Exam Scores DataFrame:');
  df.show();
  console.log();

  // Example 1: Calculate median
  console.log('1️⃣  Calculate Median: median()');
  console.log('─'.repeat(50));
  const medianMath: number = df.median('math');
  const medianScience: number = df.median('science');
  const medianEnglish: number = df.median('english');
  console.log(`Math median: ${medianMath}`);
  console.log(`Science median: ${medianScience}`);
  console.log(`English median: ${medianEnglish}`);
  console.log();

  // Example 2: Calculate quantiles (percentiles)
  console.log('2️⃣  Calculate Quantiles: quantile()');
  console.log('─'.repeat(50));
  console.log('Math score distribution:');
  const mathQ25: number = df.quantile('math', 0.25);  // 25th percentile (Q1)
  const mathQ50: number = df.quantile('math', 0.50);  // 50th percentile (median, Q2)
  const mathQ75: number = df.quantile('math', 0.75);  // 75th percentile (Q3)
  console.log(`  Q1 (25th percentile): ${mathQ25}`);
  console.log(`  Q2 (50th percentile): ${mathQ50}`);
  console.log(`  Q3 (75th percentile): ${mathQ75}`);
  console.log(`  IQR (Q3-Q1): ${mathQ75 - mathQ25}`);
  console.log();

  console.log('Overall score distribution:');
  const overallQ10: number = df.quantile('overall', 0.10);  // 10th percentile
  const overallQ90: number = df.quantile('overall', 0.90);  // 90th percentile
  console.log(`  10th percentile: ${overallQ10}`);
  console.log(`  90th percentile: ${overallQ90}`);
  console.log();

  // Example 3: Value counts (frequency distribution)
  console.log('3️⃣  Value Counts: valueCounts()');
  console.log('─'.repeat(50));
  console.log('Grade distribution:');
  const gradeCounts: DataFrameType = df.valueCounts('grade');
  gradeCounts.show();
  console.log();

  // Calculate percentages
  console.log('Grade percentages:');
  const totalStudents: number = df.shape.rows;
  const gradeCountsData: Column | null = gradeCounts.column('count');
  const grades: Column | null = gradeCounts.column('grade');
  if (gradeCountsData && grades) {
    for (let i = 0; i < grades.data.length; i++) {
      const grade: any = grades.data[i];
      const count: any = gradeCountsData.data[i];
      const percentage: string = (count / totalStudents * 100).toFixed(1);
      console.log(`  ${grade}: ${count} students (${percentage}%)`);
    }
  }
  console.log();

  // Example 4: Correlation matrix
  console.log('4️⃣  Correlation Matrix: corrMatrix()');
  console.log('─'.repeat(50));
  console.log('Correlation between math, science, and english scores:');
  const corrMatrix: DataFrameType = df.corrMatrix(['math', 'science', 'english']);
  corrMatrix.show();
  console.log();

  // Interpret correlations
  console.log('Correlation interpretation:');
  console.log('  1.0 = Perfect positive correlation');
  console.log('  0.0 = No correlation');
  console.log(' -1.0 = Perfect negative correlation');
  console.log();

  // Example 5: Ranking
  console.log('5️⃣  Rank Values: rank()');
  console.log('─'.repeat(50));
  console.log('Rank students by math score (average method):');
  const dfMathRank: DataFrameType = df.rank('math', 'average');
  dfMathRank.select(['student', 'math', 'math_rank']).show();
  console.log();

  console.log('Rank students by overall score (min method):');
  const dfOverallRank: DataFrameType = df.rank('overall', 'min');
  dfOverallRank.select(['student', 'overall', 'overall_rank']).show();
  console.log();

  console.log('Rank students by science score (dense method):');
  const dfScienceRank: DataFrameType = df.rank('science', 'dense');
  dfScienceRank.select(['student', 'science', 'science_rank']).show();
  console.log();

  // Example 6: Statistical summary with multiple aggregations
  console.log('6️⃣  Complete Statistical Summary');
  console.log('─'.repeat(50));

  function printStats(df: DataFrameType, column: string): void {
    const mean: number = df.mean(column);
    const median: number = df.median(column);
    const min: number = df.min(column);
    const max: number = df.max(column);
    const q25: number = df.quantile(column, 0.25);
    const q75: number = df.quantile(column, 0.75);

    console.log(`\n${column} statistics:`);
    console.log(`  Count: ${df.shape.rows}`);
    console.log(`  Mean:  ${mean.toFixed(2)}`);
    console.log(`  Median: ${median.toFixed(2)}`);
    console.log(`  Min:   ${min.toFixed(2)}`);
    console.log(`  Q1:    ${q25.toFixed(2)}`);
    console.log(`  Q3:    ${q75.toFixed(2)}`);
    console.log(`  Max:   ${max.toFixed(2)}`);
    console.log(`  Range: ${(max - min).toFixed(2)}`);
    console.log(`  IQR:   ${(q75 - q25).toFixed(2)}`);
  }

  printStats(df, 'math');
  printStats(df, 'science');
  printStats(df, 'english');
  console.log();

  // Example 7: Identify outliers using IQR method
  console.log('7️⃣  Identify Outliers (IQR Method)');
  console.log('─'.repeat(50));

  function findOutliers(df: DataFrameType, column: string): void {
    const q1: number = df.quantile(column, 0.25);
    const q3: number = df.quantile(column, 0.75);
    const iqr: number = q3 - q1;
    const lowerBound: number = q1 - 1.5 * iqr;
    const upperBound: number = q3 + 1.5 * iqr;

    console.log(`\n${column} outlier detection:`);
    console.log(`  Lower bound: ${lowerBound.toFixed(2)}`);
    console.log(`  Upper bound: ${upperBound.toFixed(2)}`);

    // Filter for outliers
    const outliers: DataFrameType = df.filter((row) => {
      const value = row.get(column);
      return value < lowerBound || value > upperBound;
    });

    if (outliers.shape.rows > 0) {
      console.log(`  Found ${outliers.shape.rows} outlier(s):`);
      outliers.select(['student', column]).show();
    } else {
      console.log('  No outliers detected');
    }

    outliers.free();
  }

  findOutliers(df, 'math');
  findOutliers(df, 'science');
  findOutliers(df, 'english');
  console.log();

  // Example 8: Percentile-based grading
  console.log('8️⃣  Percentile-Based Grading');
  console.log('─'.repeat(50));

  const p90: number = df.quantile('overall', 0.90);
  const p70: number = df.quantile('overall', 0.70);
  const p50: number = df.quantile('overall', 0.50);
  const p30: number = df.quantile('overall', 0.30);

  console.log('Grading thresholds:');
  console.log(`  A: ≥ ${p90.toFixed(1)} (top 10%)`);
  console.log(`  B: ≥ ${p70.toFixed(1)} (top 30%)`);
  console.log(`  C: ≥ ${p50.toFixed(1)} (median)`);
  console.log(`  D: ≥ ${p30.toFixed(1)} (bottom 30%)`);
  console.log(`  F: < ${p30.toFixed(1)} (bottom 30%)`);
  console.log();

  // Example 9: Rank correlation (Spearman)
  console.log('9️⃣  Rank-Based Analysis');
  console.log('─'.repeat(50));
  console.log('Compare rankings across subjects:');

  const dfWithRanks: DataFrameType = df
    .rank('math', 'average')
    .rank('science', 'average')
    .rank('english', 'average');

  dfWithRanks.select(['student', 'math_rank', 'science_rank', 'english_rank']).show();
  console.log();

  // Example 10: Grouped aggregations
  console.log('🔟 Grouped Aggregations');
  console.log('─'.repeat(50));
  console.log('Statistics by grade:');

  const gradeA: DataFrameType = df.filter((row) => row.get('grade') === 'A');
  const gradeB: DataFrameType = df.filter((row) => row.get('grade') === 'B');
  const gradeC: DataFrameType = df.filter((row) => row.get('grade') === 'C');

  console.log('\nGrade A students:');
  console.log(`  Count: ${gradeA.shape.rows}`);
  console.log(`  Math mean: ${gradeA.mean('math').toFixed(2)}`);
  console.log(`  Science mean: ${gradeA.mean('science').toFixed(2)}`);
  console.log(`  English mean: ${gradeA.mean('english').toFixed(2)}`);

  console.log('\nGrade B students:');
  console.log(`  Count: ${gradeB.shape.rows}`);
  console.log(`  Math mean: ${gradeB.mean('math').toFixed(2)}`);
  console.log(`  Science mean: ${gradeB.mean('science').toFixed(2)}`);
  console.log(`  English mean: ${gradeB.mean('english').toFixed(2)}`);

  console.log('\nGrade C students:');
  console.log(`  Count: ${gradeC.shape.rows}`);
  console.log(`  Math mean: ${gradeC.mean('math').toFixed(2)}`);
  console.log(`  Science mean: ${gradeC.mean('science').toFixed(2)}`);
  console.log(`  English mean: ${gradeC.mean('english').toFixed(2)}`);
  console.log();

  // Cleanup
  df.free();
  gradeCounts.free();
  corrMatrix.free();
  dfMathRank.free();
  dfOverallRank.free();
  dfScienceRank.free();
  dfWithRanks.free();
  gradeA.free();
  gradeB.free();
  gradeC.free();

  console.log('✅ Advanced aggregations showcase complete!');
}

// Run examples
main().catch(console.error);
