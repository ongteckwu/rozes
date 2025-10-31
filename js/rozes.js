/**
 * Rozes DataFrame Library - JavaScript Wrapper
 *
 * High-performance DataFrame library powered by WebAssembly.
 * Provides zero-copy access to columnar data via TypedArrays.
 *
 * @example
 * ```javascript
 * const rozes = await Rozes.init();
 * const csv = "name,age,score\nAlice,30,95.5\nBob,25,87.3\n";
 * const df = rozes.DataFrame.fromCSV(csv);
 *
 * console.log(df.shape); // { rows: 2, cols: 3 }
 * const ages = df.column('age'); // Float64Array [30, 25]
 * console.log(df.columns); // ['name', 'age', 'score']
 *
 * df.free(); // Release memory
 * ```
 */

/**
 * FinalizationRegistry for automatic memory cleanup
 * When a DataFrame is garbage collected, this will automatically free the Wasm memory
 */
const finalizationRegistry = new FinalizationRegistry((handle) => {
    // Get the wasm instance from the static property
    const wasm = DataFrame._wasm;
    if (wasm && wasm.instance && wasm.instance.exports && wasm.instance.exports.rozes_free) {
        try {
            wasm.instance.exports.rozes_free(handle);
        } catch (err) {
            // Silently ignore errors during finalization (Wasm might be shutting down)
            console.warn(`Failed to auto-free DataFrame handle ${handle}:`, err);
        }
    }
});

/**
 * Error codes from Wasm module
 */
const ErrorCode = {
    Success: 0,
    OutOfMemory: -1,
    InvalidFormat: -2,
    InvalidHandle: -3,
    ColumnNotFound: -4,
    TypeMismatch: -5,
    IndexOutOfBounds: -6,
    TooManyDataFrames: -7,
    InvalidOptions: -8,
};

/**
 * Error messages for each error code
 */
const ErrorMessages = {
    [ErrorCode.OutOfMemory]: 'Out of memory',
    [ErrorCode.InvalidFormat]: 'Invalid CSV format',
    [ErrorCode.InvalidHandle]: 'Invalid DataFrame handle',
    [ErrorCode.ColumnNotFound]: 'Column not found',
    [ErrorCode.TypeMismatch]: 'Type mismatch - column is not the requested type',
    [ErrorCode.IndexOutOfBounds]: 'Index out of bounds',
    [ErrorCode.TooManyDataFrames]: 'Too many DataFrames (max 1000)',
    [ErrorCode.InvalidOptions]: 'Invalid CSV options',
};

/**
 * Rozes Error class
 */
class RozesError extends Error {
    constructor(code, message) {
        const errorMsg = ErrorMessages[code] || `Unknown error (code: ${code})`;
        super(message ? `${errorMsg}: ${message}` : errorMsg);
        this.code = code;
        this.name = 'RozesError';
    }
}

/**
 * Check Wasm function result and throw error if failed
 */
function checkResult(code, context = '') {
    if (code < 0) {
        throw new RozesError(code, context);
    }
    return code;
}

/**
 * DataFrame class - represents a 2D columnar data structure
 */
class DataFrame {
    /**
     * @private
     * @param {number} handle - Wasm handle to the DataFrame
     * @param {Object} wasm - Wasm instance
     * @param {boolean} autoCleanup - Whether to automatically free memory on GC (default: true)
     */
    constructor(handle, wasm, autoCleanup = true) {
        this._handle = handle;
        this._wasm = wasm;
        this._freed = false;
        this._autoCleanup = autoCleanup;

        // Register with FinalizationRegistry if autoCleanup is enabled
        // We use 'this' as the unregister token so we can unregister if manually freed
        if (autoCleanup) {
            finalizationRegistry.register(this, handle, this);
        }

        // Cache dimensions
        const rowsPtr = new Uint32Array(wasm.memory.buffer, 0, 1);
        const colsPtr = new Uint32Array(wasm.memory.buffer, 4, 1);
        checkResult(
            wasm.instance.exports.rozes_getDimensions(handle, rowsPtr.byteOffset, colsPtr.byteOffset),
            'Failed to get DataFrame dimensions'
        );

        this._rows = rowsPtr[0];
        this._cols = colsPtr[0];

        // Cache column names
        this._columnNames = this._getColumnNames();
    }

    /**
     * Parse CSV string into DataFrame
     *
     * @param {string} csvText - CSV data as string
     * @param {Object} options - Parsing options
     * @param {string} [options.delimiter=','] - Field delimiter
     * @param {boolean} [options.has_headers=true] - Whether first row contains headers
     * @param {boolean} [options.skip_blank_lines=true] - Skip blank lines
     * @param {boolean} [options.trim_whitespace=false] - Trim whitespace from fields
     * @param {boolean} [options.autoCleanup=true] - Automatically free memory on GC (default: true)
     * @returns {DataFrame} - New DataFrame instance
     *
     * @example
     * // Automatic memory management (default - convenient)
     * const df = DataFrame.fromCSV("age,score\n30,95.5\n25,87.3");
     * // Memory freed automatically when df is garbage collected
     * // Can still call df.free() for immediate cleanup
     *
     * @example
     * // Manual memory management (opt-out for production)
     * const df = DataFrame.fromCSV("age,score\n30,95.5\n25,87.3", { autoCleanup: false });
     * df.free(); // Must call this
     */
    static fromCSV(csvText, options = {}) {
        const wasm = DataFrame._wasm;
        if (!wasm) {
            throw new Error('Rozes not initialized. Call Rozes.init() first.');
        }

        // Extract autoCleanup option (not passed to Wasm)
        const { autoCleanup = true, ...csvOptions } = options;

        // Encode CSV to UTF-8
        const csvBytes = new TextEncoder().encode(csvText);

        // Allocate memory for CSV buffer using Wasm allocator
        const csvPtr = wasm.instance.exports.rozes_alloc(csvBytes.length);
        if (csvPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate CSV buffer');
        }

        let optsPtr = 0;
        let optsLen = 0;

        try {
            // Copy CSV data to Wasm memory
            const csvArray = new Uint8Array(wasm.memory.buffer, csvPtr, csvBytes.length);
            csvArray.set(csvBytes);

            // Encode options to JSON if provided
            if (Object.keys(csvOptions).length > 0) {
                const optsJSON = JSON.stringify(csvOptions);
                const optsBytes = new TextEncoder().encode(optsJSON);
                optsPtr = wasm.instance.exports.rozes_alloc(optsBytes.length);

                if (optsPtr === 0) {
                    throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate options buffer');
                }

                const optsArray = new Uint8Array(wasm.memory.buffer, optsPtr, optsBytes.length);
                optsArray.set(optsBytes);
                optsLen = optsBytes.length;
            }

            // Call Wasm function
            const handle = wasm.instance.exports.rozes_parseCSV(
                csvPtr,
                csvBytes.length,
                optsPtr,
                optsLen
            );

            checkResult(handle, 'Failed to parse CSV');

            return new DataFrame(handle, wasm, autoCleanup);
        } finally {
            // Always free allocated buffers
            wasm.instance.exports.rozes_free_buffer(csvPtr, csvBytes.length);
            if (optsPtr !== 0) {
                wasm.instance.exports.rozes_free_buffer(optsPtr, optsLen);
            }
        }
    }

    /**
     * Get DataFrame dimensions
     * @returns {{rows: number, cols: number}}
     */
    get shape() {
        this._checkNotFreed();
        return { rows: this._rows, cols: this._cols };
    }

    /**
     * Get column names
     * @returns {string[]}
     */
    get columns() {
        this._checkNotFreed();
        return this._columnNames;
    }

    /**
     * Get column data as TypedArray or string array (zero-copy for numeric types)
     *
     * @param {string} name - Column name
     * @returns {Float64Array|BigInt64Array|Uint8Array|string[]|null} - Column data or null if not found
     *   - Float64Array for Float64 columns
     *   - BigInt64Array for Int64 columns
     *   - Uint8Array for Bool columns (0 = false, 1 = true)
     *   - string[] for String columns
     *
     * @example
     * const ages = df.column('age'); // Float64Array or BigInt64Array
     * const names = df.column('name'); // string[]
     * const active = df.column('active'); // Uint8Array
     */
    column(name) {
        this._checkNotFreed();

        const wasm = this._wasm;
        const nameBytes = new TextEncoder().encode(name);

        // Allocate scratch space in Wasm memory for outputs
        // Layout: [ptr: u64 at offset 0][len: u32 at offset 8][name bytes at offset 12]
        const scratchOffset = 0;
        const ptrOffset = scratchOffset;      // 8 bytes for pointer (usize/u64)
        const lenOffset = scratchOffset + 8;  // 4 bytes for length (u32)
        const nameOffset = scratchOffset + 12;

        // Write column name to memory
        new Uint8Array(wasm.memory.buffer).set(nameBytes, nameOffset);

        // Try Float64 first - pass ADDRESSES where Wasm should write results
        const f64Result = wasm.instance.exports.rozes_getColumnF64(
            this._handle,
            nameOffset,
            nameBytes.length,
            ptrOffset,  // Address where pointer should be written
            lenOffset   // Address where length should be written
        );

        if (f64Result === ErrorCode.ColumnNotFound) {
            // Column doesn't exist - return null instead of throwing
            return null;
        }

        if (f64Result === ErrorCode.Success) {
            // Read the pointer and length that Wasm wrote
            // For wasm32, pointers are 32-bit, but we use 64-bit to be safe
            const view = new DataView(wasm.memory.buffer);
            const ptr = view.getUint32(ptrOffset, true);  // true = little-endian
            const len = view.getUint32(lenOffset, true);

            // Validate pointer alignment (Float64Array needs 8-byte alignment)
            if (ptr % 8 !== 0) {
                throw new Error(`Invalid pointer alignment: ${ptr} (must be 8-byte aligned for Float64Array)`);
            }

            // Validate length and bounds
            if (len === 0) {
                return new Float64Array(0);
            }

            const byteLength = len * 8; // 8 bytes per Float64
            if (ptr + byteLength > wasm.memory.buffer.byteLength) {
                throw new Error(`Pointer out of bounds: ${ptr} + ${byteLength} > ${wasm.memory.buffer.byteLength}`);
            }

            return new Float64Array(wasm.memory.buffer, ptr, len);
        }

        if (f64Result !== ErrorCode.TypeMismatch) {
            checkResult(f64Result, `Failed to get column '${name}'`);
        }

        // Try Int64
        const i64Result = wasm.instance.exports.rozes_getColumnI64(
            this._handle,
            nameOffset,
            nameBytes.length,
            ptrOffset,  // Address where pointer should be written
            lenOffset   // Address where length should be written
        );

        if (i64Result === ErrorCode.Success) {
            // Read the pointer and length that Wasm wrote
            const view = new DataView(wasm.memory.buffer);
            const ptr = view.getUint32(ptrOffset, true);  // true = little-endian
            const len = view.getUint32(lenOffset, true);

            // Validate pointer alignment (BigInt64Array needs 8-byte alignment)
            if (ptr % 8 !== 0) {
                throw new Error(`Invalid pointer alignment: ${ptr} (must be 8-byte aligned for BigInt64Array)`);
            }

            // Validate length and bounds
            if (len === 0) {
                return new BigInt64Array(0);
            }

            const byteLength = len * 8; // 8 bytes per Int64
            if (ptr + byteLength > wasm.memory.buffer.byteLength) {
                throw new Error(`Pointer out of bounds: ${ptr} + ${byteLength} > ${wasm.memory.buffer.byteLength}`);
            }

            return new BigInt64Array(wasm.memory.buffer, ptr, len);
        }

        if (i64Result !== ErrorCode.TypeMismatch) {
            checkResult(i64Result, `Failed to get column '${name}'`);
        }

        // Try Bool
        const boolResult = wasm.instance.exports.rozes_getColumnBool(
            this._handle,
            nameOffset,
            nameBytes.length,
            ptrOffset,
            lenOffset
        );

        if (boolResult === ErrorCode.Success) {
            // Read the pointer and length that Wasm wrote
            const view = new DataView(wasm.memory.buffer);
            const ptr = view.getUint32(ptrOffset, true);
            const len = view.getUint32(lenOffset, true);

            // Validate length and bounds
            if (len === 0) {
                return new Uint8Array(0);
            }

            const byteLength = len; // 1 byte per bool
            if (ptr + byteLength > wasm.memory.buffer.byteLength) {
                throw new Error(`Pointer out of bounds: ${ptr} + ${byteLength} > ${wasm.memory.buffer.byteLength}`);
            }

            // Return as Uint8Array (0 = false, 1 = true)
            return new Uint8Array(wasm.memory.buffer, ptr, len);
        }

        if (boolResult !== ErrorCode.TypeMismatch) {
            checkResult(boolResult, `Failed to get column '${name}'`);
        }

        // Try String
        // Layout: [offsetsPtr: u32][offsetsLen: u32][bufferPtr: u32][bufferLen: u32]
        const offsetsPtrOffset = scratchOffset;
        const offsetsLenOffset = scratchOffset + 4;
        const bufferPtrOffset = scratchOffset + 8;
        const bufferLenOffset = scratchOffset + 12;

        const stringResult = wasm.instance.exports.rozes_getColumnString(
            this._handle,
            nameOffset,
            nameBytes.length,
            offsetsPtrOffset,
            offsetsLenOffset,
            bufferPtrOffset,
            bufferLenOffset
        );

        if (stringResult === ErrorCode.Success) {
            const view = new DataView(wasm.memory.buffer);
            const offsetsPtr = view.getUint32(offsetsPtrOffset, true);
            const offsetsLen = view.getUint32(offsetsLenOffset, true);
            const bufferPtr = view.getUint32(bufferPtrOffset, true);
            const bufferLen = view.getUint32(bufferLenOffset, true);

            // Validate bounds
            if (offsetsPtr + offsetsLen * 4 > wasm.memory.buffer.byteLength) {
                throw new Error(`Offsets pointer out of bounds`);
            }
            if (bufferPtr + bufferLen > wasm.memory.buffer.byteLength) {
                throw new Error(`Buffer pointer out of bounds`);
            }

            // Get offsets array and buffer
            const offsets = new Uint32Array(wasm.memory.buffer, offsetsPtr, offsetsLen);
            const buffer = new Uint8Array(wasm.memory.buffer, bufferPtr, bufferLen);

            // Decode strings from buffer using offsets
            const strings = [];
            const decoder = new TextDecoder('utf-8');

            for (let i = 0; i < offsetsLen; i++) {
                const start = i === 0 ? 0 : offsets[i - 1];
                const end = offsets[i];
                const stringBytes = buffer.subarray(start, end);
                strings.push(decoder.decode(stringBytes));
            }

            return strings;
        }

        checkResult(stringResult, `Failed to get column '${name}'`);
        return null;
    }

    /**
     * Select specific columns from DataFrame
     *
     * @param {string[]} columnNames - Array of column names to select
     * @returns {DataFrame} - New DataFrame with selected columns only
     *
     * @example
     * const selected = df.select(['name', 'age']);
     * // selected now has only 'name' and 'age' columns
     * selected.free(); // Don't forget to free!
     */
    select(columnNames) {
        this._checkNotFreed();

        if (!Array.isArray(columnNames) || columnNames.length === 0) {
            throw new Error('select() requires a non-empty array of column names');
        }

        const wasm = this._wasm;

        // Encode column names as JSON array
        const colNamesJSON = JSON.stringify(columnNames);
        const colNamesBytes = new TextEncoder().encode(colNamesJSON);

        // Allocate memory for JSON string
        const colNamesPtr = wasm.instance.exports.rozes_alloc(colNamesBytes.length);
        if (colNamesPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column names buffer');
        }

        try {
            // Copy JSON to WASM memory
            const colNamesArray = new Uint8Array(wasm.memory.buffer, colNamesPtr, colNamesBytes.length);
            colNamesArray.set(colNamesBytes);

            // Call WASM function
            const newHandle = wasm.instance.exports.rozes_select(
                this._handle,
                colNamesPtr,
                colNamesBytes.length
            );

            checkResult(newHandle, `Failed to select columns: ${columnNames.join(', ')}`);

            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(colNamesPtr, colNamesBytes.length);
        }
    }

    /**
     * Get first n rows of DataFrame
     *
     * @param {number} n - Number of rows to return
     * @returns {DataFrame} - New DataFrame with first n rows
     *
     * @example
     * const top10 = df.head(10);
     * console.log(top10.shape); // { rows: 10, cols: ... }
     * top10.free();
     */
    head(n) {
        this._checkNotFreed();

        if (typeof n !== 'number' || n <= 0) {
            throw new Error('head() requires a positive number');
        }

        const wasm = this._wasm;
        const newHandle = wasm.instance.exports.rozes_head(this._handle, n);

        checkResult(newHandle, `Failed to get first ${n} rows`);

        return new DataFrame(newHandle, wasm, this._autoCleanup);
    }

    /**
     * Get last n rows of DataFrame
     *
     * @param {number} n - Number of rows to return
     * @returns {DataFrame} - New DataFrame with last n rows
     *
     * @example
     * const bottom10 = df.tail(10);
     * console.log(bottom10.shape); // { rows: 10, cols: ... }
     * bottom10.free();
     */
    tail(n) {
        this._checkNotFreed();

        if (typeof n !== 'number' || n <= 0) {
            throw new Error('tail() requires a positive number');
        }

        const wasm = this._wasm;
        const newHandle = wasm.instance.exports.rozes_tail(this._handle, n);

        checkResult(newHandle, `Failed to get last ${n} rows`);

        return new DataFrame(newHandle, wasm, this._autoCleanup);
    }

    /**
     * Sort DataFrame by column
     *
     * @param {string} columnName - Column to sort by
     * @param {boolean} [descending=false] - Sort in descending order
     * @returns {DataFrame} - New sorted DataFrame
     *
     * @example
     * const sorted = df.sort('age'); // ascending
     * const sortedDesc = df.sort('age', true); // descending
     * sorted.free();
     * sortedDesc.free();
     */
    sort(columnName, descending = false) {
        this._checkNotFreed();

        if (typeof columnName !== 'string' || columnName.length === 0) {
            throw new Error('sort() requires a column name');
        }

        const wasm = this._wasm;
        const nameBytes = new TextEncoder().encode(columnName);

        // Allocate scratch space for column name
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        if (namePtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column name buffer');
        }

        try {
            // Copy column name to WASM memory
            new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length).set(nameBytes);

            const newHandle = wasm.instance.exports.rozes_sort(
                this._handle,
                namePtr,
                nameBytes.length,
                descending ? 1 : 0
            );

            checkResult(newHandle, `Failed to sort by column '${columnName}'`);

            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Filter DataFrame by numeric condition
     *
     * @param {string} columnName - Column to filter on
     * @param {string} operator - Comparison operator: '==', '!=', '>', '<', '>=', '<='
     * @param {number} value - Value to compare against
     * @returns {DataFrame} - New filtered DataFrame
     *
     * @example
     * const adults = df.filter('age', '>=', 18);
     * const seniors = df.filter('age', '>', 65);
     * adults.free();
     * seniors.free();
     */
    filter(columnName, operator, value) {
        this._checkNotFreed();

        if (typeof columnName !== 'string' || columnName.length === 0) {
            throw new Error('filter() requires a column name');
        }

        if (typeof value !== 'number') {
            throw new Error('filter() requires a numeric value');
        }

        // Map operator string to numeric code
        const operatorMap = {
            '==': 0,
            '!=': 1,
            '>': 2,
            '<': 3,
            '>=': 4,
            '<=': 5
        };

        const operatorCode = operatorMap[operator];
        if (operatorCode === undefined) {
            throw new Error(`Invalid operator '${operator}'. Use: ==, !=, >, <, >=, <=`);
        }

        const wasm = this._wasm;
        const nameBytes = new TextEncoder().encode(columnName);

        // Allocate scratch space for column name
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        if (namePtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column name buffer');
        }

        try {
            // Copy column name to WASM memory
            new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length).set(nameBytes);

            const newHandle = wasm.instance.exports.rozes_filterNumeric(
                this._handle,
                namePtr,
                nameBytes.length,
                operatorCode,
                value
            );

            checkResult(newHandle, `Failed to filter by '${columnName} ${operator} ${value}'`);

            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Group DataFrame by column and apply aggregation function
     *
     * @param {string} groupColumn - Column to group by
     * @param {string} valueColumn - Column to aggregate
     * @param {string} aggFunc - Aggregation function: 'sum', 'mean', 'count', 'min', or 'max'
     * @returns {DataFrame} - New DataFrame with grouped and aggregated data
     *
     * @example
     * // Group by city and calculate average age
     * const grouped = df.groupBy('city', 'age', 'mean');
     * console.log(grouped.shape); // { rows: num_unique_cities, cols: 2 }
     * grouped.free();
     *
     * @example
     * // Group by region and sum sales
     * const salesByRegion = df.groupBy('region', 'sales', 'sum');
     * salesByRegion.free();
     */
    groupBy(groupColumn, valueColumn, aggFunc) {
        this._checkNotFreed();

        if (typeof groupColumn !== 'string' || groupColumn.length === 0) {
            throw new Error('groupBy() requires a non-empty group column name');
        }
        if (typeof valueColumn !== 'string' || valueColumn.length === 0) {
            throw new Error('groupBy() requires a non-empty value column name');
        }

        // Map aggFunc string to numeric code
        const aggFuncMap = {
            'sum': 0,
            'mean': 1,
            'count': 2,
            'min': 3,
            'max': 4
        };

        if (!aggFuncMap.hasOwnProperty(aggFunc)) {
            throw new Error(`Invalid aggregation function '${aggFunc}'. Must be one of: sum, mean, count, min, max`);
        }

        const aggFuncCode = aggFuncMap[aggFunc];
        const wasm = this._wasm;

        // Encode column names
        const groupColBytes = new TextEncoder().encode(groupColumn);
        const valueColBytes = new TextEncoder().encode(valueColumn);

        // Allocate memory for column names
        const groupColPtr = wasm.instance.exports.rozes_alloc(groupColBytes.length);
        if (groupColPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate group column name buffer');
        }

        const valueColPtr = wasm.instance.exports.rozes_alloc(valueColBytes.length);
        if (valueColPtr === 0) {
            wasm.instance.exports.rozes_free_buffer(groupColPtr, groupColBytes.length);
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate value column name buffer');
        }

        try {
            // Copy column names to WASM memory
            const groupColArray = new Uint8Array(wasm.memory.buffer, groupColPtr, groupColBytes.length);
            groupColArray.set(groupColBytes);

            const valueColArray = new Uint8Array(wasm.memory.buffer, valueColPtr, valueColBytes.length);
            valueColArray.set(valueColBytes);

            // Call WASM function
            const newHandle = wasm.instance.exports.rozes_groupByAgg(
                this._handle,
                groupColPtr,
                groupColBytes.length,
                valueColPtr,
                valueColBytes.length,
                aggFuncCode
            );

            checkResult(newHandle, `Failed to groupBy('${groupColumn}').${aggFunc}('${valueColumn}')`);

            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(groupColPtr, groupColBytes.length);
            wasm.instance.exports.rozes_free_buffer(valueColPtr, valueColBytes.length);
        }
    }

    /**
     * Join this DataFrame with another DataFrame
     *
     * @param {DataFrame} other - DataFrame to join with
     * @param {string|string[]} on - Column name(s) to join on (must exist in both DataFrames)
     * @param {string} how - Join type: 'inner' or 'left' (default: 'inner')
     * @returns {DataFrame} - New DataFrame with joined data
     *
     * @example
     * // Inner join on single column
     * const joined = left.join(right, 'user_id');
     * // Result: only rows where user_id exists in both DataFrames
     * joined.free();
     *
     * @example
     * // Left join on multiple columns
     * const joined = left.join(right, ['city', 'state'], 'left');
     * // Result: all rows from left + matching rows from right
     * joined.free();
     *
     * @example
     * // Inner join with explicit type
     * const joined = orders.join(customers, 'customer_id', 'inner');
     * joined.free();
     */
    join(other, on, how = 'inner') {
        this._checkNotFreed();

        if (!(other instanceof DataFrame)) {
            throw new Error('join() requires another DataFrame as first argument');
        }
        if (other._freed) {
            throw new Error('Cannot join with a freed DataFrame');
        }

        // Normalize 'on' to array
        const joinColumns = Array.isArray(on) ? on : [on];
        if (joinColumns.length === 0) {
            throw new Error('join() requires at least one column name');
        }

        // Validate join type
        const joinTypeMap = {
            'inner': 0,
            'left': 1
        };

        if (!joinTypeMap.hasOwnProperty(how)) {
            throw new Error(`Invalid join type '${how}'. Must be 'inner' or 'left'`);
        }

        const joinTypeCode = joinTypeMap[how];
        const wasm = this._wasm;

        // Encode column names as JSON array
        const joinColsJSON = JSON.stringify(joinColumns);
        const joinColsBytes = new TextEncoder().encode(joinColsJSON);

        // Allocate memory for JSON string
        const joinColsPtr = wasm.instance.exports.rozes_alloc(joinColsBytes.length);
        if (joinColsPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate join columns buffer');
        }

        try {
            // Copy JSON to WASM memory
            const joinColsArray = new Uint8Array(wasm.memory.buffer, joinColsPtr, joinColsBytes.length);
            joinColsArray.set(joinColsBytes);

            // Call WASM function
            const newHandle = wasm.instance.exports.rozes_join(
                this._handle,
                other._handle,
                joinColsPtr,
                joinColsBytes.length,
                joinTypeCode
            );

            checkResult(newHandle, `Failed to ${how} join on columns: ${joinColumns.join(', ')}`);

            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(joinColsPtr, joinColsBytes.length);
        }
    }

    /**
     * Export DataFrame to CSV format
     *
     * @param {Object} options - CSV formatting options
     * @param {string} [options.delimiter=','] - Field delimiter
     * @param {boolean} [options.has_headers=true] - Include header row
     * @returns {string} - CSV string
     *
     * @example
     * const csv = df.toCSV();
     * console.log(csv);
     * // Output:
     * // name,age,score
     * // Alice,30,95.5
     * // Bob,25,87.3
     *
     * @example
     * // Custom delimiter (tab-separated)
     * const tsv = df.toCSV({ delimiter: '\t' });
     *
     * @example
     * // Without headers
     * const dataOnly = df.toCSV({ has_headers: false });
     */
    toCSV(options = {}) {
        this._checkNotFreed();

        const wasm = this._wasm;

        // Encode options to JSON if provided
        let optsPtr = 0;
        let optsLen = 0;

        if (Object.keys(options).length > 0) {
            const optsJSON = JSON.stringify(options);
            const optsBytes = new TextEncoder().encode(optsJSON);
            optsPtr = wasm.instance.exports.rozes_alloc(optsBytes.length);
            if (optsPtr === 0) {
                throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate options buffer');
            }
            optsLen = optsBytes.length;

            // Copy options to WASM memory
            new Uint8Array(wasm.memory.buffer, optsPtr, optsLen).set(optsBytes);
        }

        // Layout: [csvPtr: u32][csvLen: u32]
        const scratchOffset = 0;
        const csvPtrOffset = scratchOffset;
        const csvLenOffset = scratchOffset + 4;

        try {
            // Call WASM function
            const result = wasm.instance.exports.rozes_toCSV(
                this._handle,
                optsPtr,
                optsLen,
                csvPtrOffset,
                csvLenOffset
            );

            checkResult(result, 'Failed to export DataFrame to CSV');

            // Read CSV pointer and length
            const view = new DataView(wasm.memory.buffer);
            const csvPtr = view.getUint32(csvPtrOffset, true);
            const csvLen = view.getUint32(csvLenOffset, true);

            // Validate bounds
            if (csvPtr + csvLen > wasm.memory.buffer.byteLength) {
                throw new Error(`CSV pointer out of bounds`);
            }

            // Copy CSV data from WASM memory
            const csvBytes = new Uint8Array(wasm.memory.buffer, csvPtr, csvLen);
            const csvString = new TextDecoder('utf-8').decode(csvBytes);

            // Free the CSV buffer
            wasm.instance.exports.rozes_free_buffer(csvPtr, csvLen);

            return csvString;
        } finally {
            // Free options buffer if allocated
            if (optsPtr !== 0) {
                wasm.instance.exports.rozes_free_buffer(optsPtr, optsLen);
            }
        }
    }

    /**
     * Free DataFrame memory
     *
     * **Manual memory management (default)**: You must call this when done to prevent leaks.
     * **Auto cleanup**: If autoCleanup is enabled, this is optional (but still recommended for deterministic cleanup).
     *
     * @example
     * const df = DataFrame.fromCSV(csvText);
     * // ... use df
     * df.free(); // Release memory immediately
     */
    free() {
        if (!this._freed) {
            // Unregister from FinalizationRegistry if auto cleanup was enabled
            if (this._autoCleanup) {
                finalizationRegistry.unregister(this);
            }

            this._wasm.instance.exports.rozes_free(this._handle);
            this._freed = true;
            this._handle = -1;
        }
    }

    /**
     * Pretty-print DataFrame info
     * @returns {string}
     */
    toString() {
        if (this._freed) {
            return 'DataFrame(freed)';
        }
        return `DataFrame(${this._rows} rows × ${this._cols} cols)\nColumns: ${this._columnNames.join(', ')}`;
    }

    /**
     * @private
     */
    _getColumnNames() {
        const wasm = this._wasm;
        const bufferSize = 1024; // 1KB for column names JSON
        const buffer = new Uint8Array(wasm.memory.buffer, 1024, bufferSize);
        const writtenPtr = new Uint32Array(wasm.memory.buffer, 2048, 1);

        checkResult(
            wasm.instance.exports.rozes_getColumnNames(
                this._handle,
                buffer.byteOffset,
                bufferSize,
                writtenPtr.byteOffset
            ),
            'Failed to get column names'
        );

        const written = writtenPtr[0];
        const jsonStr = new TextDecoder().decode(buffer.slice(0, written));
        return JSON.parse(jsonStr);
    }

    /**
     * @private
     */
    _checkNotFreed() {
        if (this._freed) {
            throw new Error('DataFrame has been freed');
        }
    }

    /**
     * @private
     * Set by Rozes.init()
     */
    static _wasm = null;
}

/**
 * Rozes namespace - main entry point
 */
class Rozes {
    /**
     * Initialize Rozes library by loading Wasm module
     *
     * @param {string|URL} [wasmPath='./rozes.wasm'] - Path to Wasm file
     * @returns {Promise<Rozes>} - Initialized Rozes instance
     *
     * @example
     * const rozes = await Rozes.init('./zig-out/bin/rozes.wasm');
     */
    static async init(wasmPath = './rozes.wasm') {
        // Load Wasm module
        const response = await fetch(wasmPath);
        const buffer = await response.arrayBuffer();

        // Instantiate with WASI imports (complete snapshot_preview1)
        const wasi = {
            // Args
            args_get: () => 0,
            args_sizes_get: () => 0,

            // Environment
            environ_get: () => 0,
            environ_sizes_get: () => 0,

            // Clock
            clock_res_get: () => 0,
            clock_time_get: () => 0,

            // File descriptors
            fd_advise: () => 0,
            fd_allocate: () => 0,
            fd_close: () => 0,
            fd_datasync: () => 0,
            fd_fdstat_get: () => 0,
            fd_fdstat_set_flags: () => 0,
            fd_fdstat_set_rights: () => 0,
            fd_filestat_get: () => 0,
            fd_filestat_set_size: () => 0,
            fd_filestat_set_times: () => 0,
            fd_pread: () => 0,
            fd_prestat_get: () => 0,
            fd_prestat_dir_name: () => 0,
            fd_pwrite: () => 0,
            fd_read: () => 0,
            fd_readdir: () => 0,
            fd_renumber: () => 0,
            fd_seek: () => 0,
            fd_sync: () => 0,
            fd_tell: () => 0,
            fd_write: () => 0,

            // Path
            path_create_directory: () => 0,
            path_filestat_get: () => 0,
            path_filestat_set_times: () => 0,
            path_link: () => 0,
            path_open: () => 0,
            path_readlink: () => 0,
            path_remove_directory: () => 0,
            path_rename: () => 0,
            path_symlink: () => 0,
            path_unlink_file: () => 0,

            // Poll
            poll_oneoff: () => 0,

            // Process
            proc_exit: () => {},
            proc_raise: () => 0,

            // Random
            random_get: () => 0,

            // Sched
            sched_yield: () => 0,

            // Socket
            sock_recv: () => 0,
            sock_send: () => 0,
            sock_shutdown: () => 0,
        };

        const result = await WebAssembly.instantiate(buffer, {
            wasi_snapshot_preview1: wasi,
        });

        // Store Wasm instance
        const wasm = {
            instance: result.instance,
            memory: result.instance.exports.memory,
        };

        DataFrame._wasm = wasm;

        return new Rozes(wasm);
    }

    /**
     * @private
     */
    constructor(wasm) {
        this._wasm = wasm;
        this.DataFrame = DataFrame;
    }

    /**
     * Get library version
     * @returns {string}
     */
    get version() {
        return '0.1.0-dev';
    }
}

// Export for ES modules
export { Rozes, DataFrame, RozesError };

// Also support CommonJS and browser globals
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { Rozes, DataFrame, RozesError };
}

if (typeof window !== 'undefined') {
    window.Rozes = Rozes;
    window.DataFrame = DataFrame;
    window.RozesError = RozesError;
}
