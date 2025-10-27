/**
 * Rozes DataFrame Library - Browser Conformance Test Suite
 *
 * This test suite validates RFC 4180 compliance and edge case handling
 * for the Rozes CSV parser in browser environments.
 */

// Test configuration
const TEST_DATA_BASE = '../../testdata/csv/';

// Test suite definitions
const testSuites = {
    rfc4180: {
        name: 'RFC 4180 Compliance',
        description: 'Tests for strict RFC 4180 CSV specification compliance',
        tests: [
            {
                file: 'rfc4180/01_simple.csv',
                name: 'Simple CSV with headers',
                description: 'Basic CSV with no special characters',
                expected: {
                    rowCount: 3,
                    columnCount: 3,
                    columns: ['name', 'age', 'city'],
                    types: { age: 'Int64' }
                }
            },
            {
                file: 'rfc4180/02_quoted_fields.csv',
                name: 'Quoted fields',
                description: 'Fields enclosed in double quotes',
                expected: {
                    rowCount: 3,
                    columnCount: 3,
                    columns: ['name', 'description', 'price']
                }
            },
            {
                file: 'rfc4180/03_embedded_commas.csv',
                name: 'Embedded commas in quoted fields',
                description: 'Commas inside quoted fields should not be delimiters',
                expected: {
                    rowCount: 3,
                    columnCount: 3,
                    // Bob Johnson's address should contain commas
                    validate: (df) => {
                        const address = df.column('address').get(2);
                        return address.includes(',');
                    }
                }
            },
            {
                file: 'rfc4180/04_embedded_newlines.csv',
                name: 'Embedded newlines in quoted fields',
                description: 'Newlines inside quoted fields should be preserved',
                expected: {
                    rowCount: 3,
                    columnCount: 3,
                    validate: (df) => {
                        const comment = df.column('comment').get(0);
                        return comment.includes('\n');
                    }
                }
            },
            {
                file: 'rfc4180/05_escaped_quotes.csv',
                name: 'Escaped double quotes',
                description: 'Double-quote escape (""" → ")',
                expected: {
                    rowCount: 3,
                    columnCount: 3,
                    validate: (df) => {
                        const text = df.column('text').get(0);
                        return text.includes('"') && !text.includes('""');
                    }
                }
            },
            {
                file: 'rfc4180/06_crlf_endings.csv',
                name: 'CRLF line endings',
                description: 'Handle both CRLF and LF line endings',
                expected: {
                    rowCount: 3,
                    columnCount: 3
                }
            },
            {
                file: 'rfc4180/07_empty_fields.csv',
                name: 'Empty fields',
                description: 'Missing values should be represented as null',
                expected: {
                    rowCount: 4,
                    columnCount: 4,
                    validate: (df) => {
                        // Check that row 1 has null phone
                        const phone = df.column('phone').get(0);
                        return phone === null || phone === '';
                    }
                }
            },
            {
                file: 'rfc4180/08_no_header.csv',
                name: 'CSV without header row',
                description: 'Generate column names (col0, col1, ...) when hasHeaders=false',
                options: { hasHeaders: false },
                expected: {
                    rowCount: 3,
                    columnCount: 4,
                    validate: (df) => {
                        return df.columns[0].startsWith('col');
                    }
                }
            },
            {
                file: 'rfc4180/09_trailing_comma.csv',
                name: 'Trailing comma',
                description: 'Trailing comma creates an empty column',
                expected: {
                    rowCount: 3,
                    columnCount: 4 // Extra empty column
                }
            },
            {
                file: 'rfc4180/10_unicode_content.csv',
                name: 'Unicode content',
                description: 'UTF-8 characters (emoji, CJK) should be preserved',
                expected: {
                    rowCount: 4,
                    columnCount: 3,
                    validate: (df) => {
                        const greeting = df.column('greeting').get(0);
                        return greeting.includes('世界');
                    }
                }
            }
        ]
    },

    edgeCases: {
        name: 'Edge Cases',
        description: 'Tests for uncommon but valid CSV scenarios',
        tests: [
            {
                file: 'edge_cases/01_single_column.csv',
                name: 'Single column',
                description: 'CSV with only one column',
                expected: {
                    rowCount: 5,
                    columnCount: 1
                }
            },
            {
                file: 'edge_cases/02_single_row.csv',
                name: 'Single row',
                description: 'CSV with header and one data row',
                expected: {
                    rowCount: 1,
                    columnCount: 4
                }
            },
            {
                file: 'edge_cases/03_blank_lines.csv',
                name: 'Blank lines',
                description: 'Blank lines should be skipped when skipBlankLines=true',
                options: { skipBlankLines: true },
                expected: {
                    rowCount: 3, // Blank lines skipped
                    columnCount: 2
                }
            },
            {
                file: 'edge_cases/04_mixed_types.csv',
                name: 'Mixed data types',
                description: 'Columns with int, float, bool, and string types',
                expected: {
                    rowCount: 4,
                    columnCount: 6,
                    types: {
                        id: 'Int64',
                        score: 'Float64',
                        is_active: 'Bool',
                        price: 'Float64'
                    }
                }
            },
            {
                file: 'edge_cases/05_special_characters.csv',
                name: 'Special characters',
                description: 'Special symbols and unicode math',
                expected: {
                    rowCount: 4,
                    columnCount: 3,
                    validate: (df) => {
                        const symbols = df.column('symbols').get(0);
                        return symbols.includes('!@#$%^&*()');
                    }
                }
            },
            {
                file: 'edge_cases/06_very_long_field.csv',
                name: 'Very long field',
                description: 'Fields with >500 characters',
                expected: {
                    rowCount: 2,
                    columnCount: 3,
                    validate: (df) => {
                        const long = df.column('long').get(0);
                        return long.length > 400;
                    }
                }
            },
            {
                file: 'edge_cases/07_numbers_as_strings.csv',
                name: 'Numbers as strings',
                description: 'Preserve leading zeros (zip codes, account numbers)',
                expected: {
                    rowCount: 3,
                    columnCount: 4,
                    validate: (df) => {
                        // Zip codes should be strings, preserving leading zeros
                        const zip = df.column('zip_code').get(0);
                        return typeof zip === 'string' && zip === '10001';
                    }
                }
            }
        ]
    }
};

// State management
let state = {
    totalTests: 0,
    passedTests: 0,
    failedTests: 0,
    currentFilter: 'all',
    startTime: 0,
    results: []
};

// Logger
const Logger = {
    log(message, type = 'info') {
        const logDiv = document.getElementById('consoleLog');
        const entry = document.createElement('div');
        entry.className = `log-entry log-${type}`;
        entry.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
        logDiv.appendChild(entry);
        logDiv.scrollTop = logDiv.scrollHeight;
    },

    info(msg) { this.log(msg, 'info'); },
    success(msg) { this.log(msg, 'success'); },
    error(msg) { this.log(msg, 'error'); },
    warn(msg) { this.log(msg, 'warn'); }
};

// Mock DataFrame implementation (replace with actual Rozes import)
class MockDataFrame {
    constructor(csv, options = {}) {
        this.csv = csv;
        this.options = options;
        this._parse();
    }

    _parse() {
        const lines = this.csv.trim().split(/\r?\n/);
        const hasHeaders = this.options.hasHeaders !== false;

        // Simple CSV parser (replace with actual Rozes parser)
        this.columns = hasHeaders ? this._parseRow(lines[0]) :
            Array.from({ length: this._parseRow(lines[0]).length }, (_, i) => `col${i}`);

        const dataLines = hasHeaders ? lines.slice(1) : lines;
        this.rowCount = dataLines.length;
        this.columnCount = this.columns.length;

        // Store data by column
        this._data = {};
        this.columns.forEach(col => {
            this._data[col] = [];
        });

        dataLines.forEach(line => {
            if (line.trim() === '' && this.options.skipBlankLines) return;
            const values = this._parseRow(line);
            this.columns.forEach((col, i) => {
                this._data[col].push(values[i] || null);
            });
        });
    }

    _parseRow(row) {
        // Very basic CSV parsing (does not handle all RFC 4180 cases)
        // This is just for demo - actual implementation will use Rozes parser
        const values = [];
        let current = '';
        let inQuotes = false;

        for (let i = 0; i < row.length; i++) {
            const char = row[i];
            const next = row[i + 1];

            if (char === '"') {
                if (inQuotes && next === '"') {
                    current += '"';
                    i++; // Skip next quote
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (char === ',' && !inQuotes) {
                values.push(current);
                current = '';
            } else {
                current += char;
            }
        }
        values.push(current);

        return values;
    }

    column(name) {
        return {
            get: (index) => this._data[name][index]
        };
    }

    static async fromCSV(csvText, options = {}) {
        // Simulate async loading (will use actual Rozes WASM module)
        await new Promise(resolve => setTimeout(resolve, 10));
        return new MockDataFrame(csvText, options);
    }
}

// Replace with actual Rozes import when available
const DataFrame = MockDataFrame;

// Test runner
class TestRunner {
    async runTest(test, suiteName) {
        const testId = `${suiteName}-${test.file}`;
        Logger.info(`Running: ${test.name}`);

        try {
            // Load CSV file
            const csvPath = TEST_DATA_BASE + test.file;
            const response = await fetch(csvPath);

            if (!response.ok) {
                throw new Error(`Failed to load ${csvPath}: ${response.status}`);
            }

            const csvText = await response.text();

            // Parse CSV
            const options = test.options || {};
            const df = await DataFrame.fromCSV(csvText, options);

            // Validate results
            const errors = [];

            if (test.expected.rowCount !== undefined) {
                if (df.rowCount !== test.expected.rowCount) {
                    errors.push(`Row count mismatch: expected ${test.expected.rowCount}, got ${df.rowCount}`);
                }
            }

            if (test.expected.columnCount !== undefined) {
                if (df.columnCount !== test.expected.columnCount) {
                    errors.push(`Column count mismatch: expected ${test.expected.columnCount}, got ${df.columnCount}`);
                }
            }

            if (test.expected.columns) {
                test.expected.columns.forEach((col, i) => {
                    if (df.columns[i] !== col) {
                        errors.push(`Column ${i} name mismatch: expected "${col}", got "${df.columns[i]}"`);
                    }
                });
            }

            if (test.expected.validate) {
                try {
                    if (!test.expected.validate(df)) {
                        errors.push('Custom validation failed');
                    }
                } catch (e) {
                    errors.push(`Validation error: ${e.message}`);
                }
            }

            if (errors.length > 0) {
                throw new Error(errors.join('; '));
            }

            Logger.success(`✓ ${test.name}`);
            return { passed: true, details: `${df.rowCount} rows × ${df.columnCount} columns` };

        } catch (error) {
            Logger.error(`✗ ${test.name}: ${error.message}`);
            return { passed: false, error: error.message };
        }
    }

    async runSuite(suiteName) {
        const suite = testSuites[suiteName];
        if (!suite) {
            Logger.error(`Suite not found: ${suiteName}`);
            return;
        }

        Logger.info(`Starting suite: ${suite.name}`);
        const results = [];

        for (const test of suite.tests) {
            const result = await this.runTest(test, suiteName);
            results.push({ test, result, suite: suite.name });
            this.updateUI(test, result, suite.name);

            if (result.passed) {
                state.passedTests++;
            } else {
                state.failedTests++;
            }

            this.updateStats();
        }

        return results;
    }

    updateUI(test, result, suiteName) {
        let groupDiv = document.querySelector(`[data-group="${suiteName}"]`);

        if (!groupDiv) {
            groupDiv = document.createElement('div');
            groupDiv.className = 'test-group';
            groupDiv.setAttribute('data-group', suiteName);
            groupDiv.innerHTML = `<h3>${testSuites[suiteName].name}</h3>`;
            document.getElementById('results').appendChild(groupDiv);
        }

        const testDiv = document.createElement('div');
        testDiv.className = `test-case ${result.passed ? 'pass' : 'fail'}`;
        testDiv.setAttribute('data-status', result.passed ? 'pass' : 'fail');

        testDiv.innerHTML = `
            <div class="test-header">
                <div class="test-name">${test.name}</div>
                <div class="test-status ${result.passed ? 'status-pass' : 'status-fail'}">
                    ${result.passed ? '✓ PASS' : '✗ FAIL'}
                </div>
            </div>
            <div class="test-description">${test.description}</div>
            ${result.details ? `<div class="test-details">📊 ${result.details}</div>` : ''}
            ${result.error ? `<div class="test-error">❌ ${result.error}</div>` : ''}
        `;

        groupDiv.appendChild(testDiv);
    }

    updateStats() {
        document.getElementById('totalTests').textContent = state.totalTests;
        document.getElementById('passedTests').textContent = state.passedTests;
        document.getElementById('failedTests').textContent = state.failedTests;

        const duration = Date.now() - state.startTime;
        document.getElementById('duration').textContent = `${duration}ms`;

        const progress = (state.passedTests + state.failedTests) / state.totalTests * 100;
        document.getElementById('progressBar').style.width = `${progress}%`;
    }

    async runAll() {
        state.startTime = Date.now();
        state.totalTests = Object.values(testSuites).reduce((sum, suite) => sum + suite.tests.length, 0);
        state.passedTests = 0;
        state.failedTests = 0;

        document.getElementById('results').innerHTML = '';

        Logger.info('Starting all test suites...');

        for (const suiteName of Object.keys(testSuites)) {
            await this.runSuite(suiteName);
        }

        const duration = Date.now() - state.startTime;
        Logger.success(`All tests completed in ${duration}ms`);
        Logger.info(`Results: ${state.passedTests} passed, ${state.failedTests} failed`);
    }
}

// Benchmark suite
class BenchmarkRunner {
    async runBenchmarks() {
        Logger.info('Starting performance benchmarks...');

        const benchmarks = [
            { name: 'Small CSV (1K rows)', rows: 1000, cols: 10 },
            { name: 'Medium CSV (10K rows)', rows: 10000, cols: 10 },
            { name: 'Large CSV (100K rows)', rows: 100000, cols: 10 },
        ];

        const results = [];

        for (const bench of benchmarks) {
            const csv = this.generateCSV(bench.rows, bench.cols);
            const start = performance.now();
            await DataFrame.fromCSV(csv);
            const duration = performance.now() - start;

            results.push({
                name: bench.name,
                rows: bench.rows,
                cols: bench.cols,
                duration: duration.toFixed(2),
                throughput: ((bench.rows * bench.cols) / duration * 1000).toFixed(0)
            });

            Logger.success(`${bench.name}: ${duration.toFixed(2)}ms`);
        }

        this.displayBenchmarkResults(results);
    }

    generateCSV(rows, cols) {
        const headers = Array.from({ length: cols }, (_, i) => `col${i}`).join(',');
        const dataRows = Array.from({ length: rows }, (_, i) =>
            Array.from({ length: cols }, (_, j) => Math.random() * 100).join(',')
        );
        return [headers, ...dataRows].join('\n');
    }

    displayBenchmarkResults(results) {
        const resultsDiv = document.getElementById('results');
        const benchDiv = document.createElement('div');
        benchDiv.className = 'benchmark-results';
        benchDiv.innerHTML = `
            <h4>⚡ Performance Benchmark Results</h4>
            <table class="benchmark-table">
                <thead>
                    <tr>
                        <th>Test Case</th>
                        <th>Rows</th>
                        <th>Columns</th>
                        <th>Duration (ms)</th>
                        <th>Throughput (cells/sec)</th>
                    </tr>
                </thead>
                <tbody>
                    ${results.map(r => `
                        <tr>
                            <td>${r.name}</td>
                            <td>${r.rows.toLocaleString()}</td>
                            <td>${r.cols}</td>
                            <td>${r.duration}</td>
                            <td>${parseInt(r.throughput).toLocaleString()}</td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        `;
        resultsDiv.appendChild(benchDiv);
    }
}

// Event handlers
document.addEventListener('DOMContentLoaded', () => {
    const runner = new TestRunner();
    const benchRunner = new BenchmarkRunner();

    document.getElementById('runAllBtn').addEventListener('click', () => {
        runner.runAll();
    });

    document.getElementById('runRFC4180Btn').addEventListener('click', () => {
        state.startTime = Date.now();
        state.totalTests = testSuites.rfc4180.tests.length;
        state.passedTests = 0;
        state.failedTests = 0;
        document.getElementById('results').innerHTML = '';
        runner.runSuite('rfc4180');
    });

    document.getElementById('runEdgeCasesBtn').addEventListener('click', () => {
        state.startTime = Date.now();
        state.totalTests = testSuites.edgeCases.tests.length;
        state.passedTests = 0;
        state.failedTests = 0;
        document.getElementById('results').innerHTML = '';
        runner.runSuite('edgeCases');
    });

    document.getElementById('runBenchmarkBtn').addEventListener('click', () => {
        document.getElementById('results').innerHTML = '';
        benchRunner.runBenchmarks();
    });

    document.getElementById('clearBtn').addEventListener('click', () => {
        document.getElementById('results').innerHTML = '';
        document.getElementById('consoleLog').innerHTML = '';
        state = {
            totalTests: 0,
            passedTests: 0,
            failedTests: 0,
            currentFilter: 'all',
            startTime: 0,
            results: []
        };
        runner.updateStats();
    });

    // Filter buttons
    document.querySelectorAll('.filter-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
            e.target.classList.add('active');

            const filter = e.target.getAttribute('data-filter');
            state.currentFilter = filter;

            document.querySelectorAll('.test-case').forEach(test => {
                if (filter === 'all') {
                    test.style.display = 'block';
                } else {
                    const status = test.getAttribute('data-status');
                    test.style.display = status === filter ? 'block' : 'none';
                }
            });
        });
    });

    Logger.info('Test suite ready. Click "Run All Tests" to begin.');
});
