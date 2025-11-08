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
    InvalidRange: -10,
    NotImplemented: -11,
    InsufficientData: -12,
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
    [ErrorCode.InvalidRange]: 'Invalid range - start is greater than end',
    [ErrorCode.NotImplemented]: 'Feature not yet implemented',
    [ErrorCode.InsufficientData]: 'Insufficient data for this operation',
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
                return [];
            }

            const byteLength = len; // 1 byte per bool
            if (ptr + byteLength > wasm.memory.buffer.byteLength) {
                throw new Error(`Pointer out of bounds: ${ptr} + ${byteLength} > ${wasm.memory.buffer.byteLength}`);
            }

            // Convert Uint8Array (0 = false, 1 = true) to JavaScript boolean array
            const uint8Array = new Uint8Array(wasm.memory.buffer, ptr, len);
            return Array.from(uint8Array, byte => byte !== 0);
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
            // NOTE: Skip buffer bounds check if bufferLen is 0 (all empty strings)
            // In this case, bufferPtr may be undefined/arbitrary
            if (bufferLen > 0 && bufferPtr + bufferLen > wasm.memory.buffer.byteLength) {
                throw new Error(`Buffer pointer out of bounds`);
            }

            // Get offsets array and buffer
            const offsets = new Uint32Array(wasm.memory.buffer, offsetsPtr, offsetsLen);
            // NOTE: If bufferLen is 0 (all empty strings), create empty buffer without using potentially invalid bufferPtr
            const buffer = bufferLen > 0
                ? new Uint8Array(wasm.memory.buffer, bufferPtr, bufferLen)
                : new Uint8Array(0); // Empty buffer for all empty strings

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
     * Drop columns by name
     * @param {string[]} columnNames - Array of column names to drop
     * @returns {DataFrame} - New DataFrame without the specified columns
     * @example
     * const df = DataFrame.fromCSV('a,b,c\n1,2,3\n4,5,6\n', { hasHeader: true });
     * const dropped = df.drop(['b']);
     * console.log(dropped.columns); // ['a', 'c']
     */
    drop(columnNames) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!Array.isArray(columnNames) || columnNames.length === 0) {
            throw new Error('drop() requires a non-empty array of column names');
        }

        const colNamesJSON = JSON.stringify(columnNames);
        const colNamesBytes = new TextEncoder().encode(colNamesJSON);
        const colNamesPtr = wasm.instance.exports.rozes_alloc(colNamesBytes.length);

        if (colNamesPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column names buffer');
        }

        const colNamesBuffer = new Uint8Array(wasm.memory.buffer, colNamesPtr, colNamesBytes.length);
        colNamesBuffer.set(colNamesBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_drop(
                this._handle,
                colNamesPtr,
                colNamesBytes.length
            );

            checkResult(newHandle, `Failed to drop columns: ${columnNames.join(', ')}`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(colNamesPtr, colNamesBytes.length);
        }
    }

    /**
     * Rename a column
     * @param {string} oldName - Current column name
     * @param {string} newName - New column name
     * @returns {DataFrame} - New DataFrame with renamed column
     * @example
     * const df = DataFrame.fromCSV('old_name\n1\n2\n', { hasHeader: true });
     * const renamed = df.rename('old_name', 'new_name');
     * console.log(renamed.columns); // ['new_name']
     */
    rename(oldName, newName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!oldName || typeof oldName !== 'string') {
            throw new Error('rename() requires oldName as non-empty string');
        }
        if (!newName || typeof newName !== 'string') {
            throw new Error('rename() requires newName as non-empty string');
        }

        const oldBytes = new TextEncoder().encode(oldName);
        const newBytes = new TextEncoder().encode(newName);

        const oldPtr = wasm.instance.exports.rozes_alloc(oldBytes.length);
        const newPtr = wasm.instance.exports.rozes_alloc(newBytes.length);

        if (oldPtr === 0 || newPtr === 0) {
            if (oldPtr > 0) wasm.instance.exports.rozes_free_buffer(oldPtr, oldBytes.length);
            if (newPtr > 0) wasm.instance.exports.rozes_free_buffer(newPtr, newBytes.length);
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate rename buffers');
        }

        const oldBuffer = new Uint8Array(wasm.memory.buffer, oldPtr, oldBytes.length);
        const newBuffer = new Uint8Array(wasm.memory.buffer, newPtr, newBytes.length);
        oldBuffer.set(oldBytes);
        newBuffer.set(newBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_rename(
                this._handle,
                oldPtr,
                oldBytes.length,
                newPtr,
                newBytes.length
            );

            checkResult(newHandle, `Failed to rename column '${oldName}' to '${newName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(oldPtr, oldBytes.length);
            wasm.instance.exports.rozes_free_buffer(newPtr, newBytes.length);
        }
    }

    /**
     * Get unique values in a column
     * @param {string} columnName - Name of the column
     * @returns {DataFrame} - New DataFrame with unique values
     * @example
     * const df = DataFrame.fromCSV('category\nA\nB\nA\nC\nB\n', { hasHeader: true });
     * const unique = df.unique('category');
     * console.log(unique.shape.rows); // 3 (A, B, C)
     */
    unique(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('unique() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_unique(
                this._handle,
                namePtr,
                nameBytes.length
            );

            checkResult(newHandle, `Failed to get unique values from column '${columnName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Remove duplicate rows based on specified columns
     * @param {string[]} columnNames - Array of column names to check for duplicates
     * @returns {DataFrame} - New DataFrame with duplicates removed
     * @example
     * const df = DataFrame.fromCSV('a,b\n1,2\n1,2\n3,4\n', { hasHeader: true });
     * const dedup = df.dropDuplicates(['a', 'b']);
     * console.log(dedup.shape.rows); // 2
     */
    dropDuplicates(columnNames) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!Array.isArray(columnNames) || columnNames.length === 0) {
            throw new Error('dropDuplicates() requires a non-empty array of column names');
        }

        const colNamesJSON = JSON.stringify(columnNames);
        const colNamesBytes = new TextEncoder().encode(colNamesJSON);
        const colNamesPtr = wasm.instance.exports.rozes_alloc(colNamesBytes.length);

        if (colNamesPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column names buffer');
        }

        const colNamesBuffer = new Uint8Array(wasm.memory.buffer, colNamesPtr, colNamesBytes.length);
        colNamesBuffer.set(colNamesBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_dropDuplicates(
                this._handle,
                colNamesPtr,
                colNamesBytes.length
            );

            checkResult(newHandle, `Failed to drop duplicates on columns: ${columnNames.join(', ')}`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(colNamesPtr, colNamesBytes.length);
        }
    }

    /**
     * Generate descriptive statistics (count, mean, std, min, max, etc.)
     * @param {string} [columnName] - Optional: column name. If not provided, describes all numeric columns
     * @returns {Object} - Statistics object with count, mean, std, min, max, median, q25, q75
     * @example
     * const df = DataFrame.fromCSV('value\n10\n20\n30\n40\n50\n', { hasHeader: true });
     * const stats = df.describe('value');
     * console.log(stats); // { count: 5, mean: 30, std: 15.81, min: 10, max: 50, ... }
     */
    describe(columnName) {
        this._checkNotFreed();

        if (columnName) {
            // Single column description
            return {
                count: this.shape.rows,
                mean: this.mean(columnName),
                std: this.stddev(columnName),
                min: this.min(columnName),
                max: this.max(columnName),
                median: this.median(columnName),
                q25: this.quantile(columnName, 0.25),
                q75: this.quantile(columnName, 0.75)
            };
        } else {
            // All numeric columns
            const result = {};
            for (const col of this.columns) {
                try {
                    result[col] = this.describe(col);
                } catch (e) {
                    // Skip non-numeric columns
                }
            }
            return result;
        }
    }

    /**
     * Random sample of rows
     * @param {number} n - Number of rows to sample
     * @returns {DataFrame} - New DataFrame with sampled rows
     * @example
     * const df = DataFrame.fromCSV('value\n1\n2\n3\n4\n5\n', { hasHeader: true });
     * const sampled = df.sample(3);
     * console.log(sampled.shape.rows); // 3
     */
    sample(n) {
        this._checkNotFreed();

        if (typeof n !== 'number' || n <= 0) {
            throw new Error('sample() requires a positive number');
        }

        // Create array of all row indices
        const allIndices = Array.from({ length: this.shape.rows }, (_, i) => i);

        // Fisher-Yates shuffle
        for (let i = allIndices.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [allIndices[i], allIndices[j]] = [allIndices[j], allIndices[i]];
        }

        // Take first n indices
        const sampleIndices = allIndices.slice(0, Math.min(n, allIndices.length)).sort((a, b) => a - b);

        // Filter to keep only sampled rows
        let rowIdx = 0;
        return this.filter(() => {
            const include = sampleIndices.includes(rowIdx);
            rowIdx++;
            return include;
        });
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
     * Sort DataFrame by multiple columns with per-column sort order
     * @param {Array<{column: string, order: 'asc'|'desc'}>} sortSpecs - Array of sort specifications
     * @returns {DataFrame} - New sorted DataFrame
     *
     * @example
     * // Sort by age descending, then by name ascending
     * const sorted = df.sortBy([
     *   { column: 'age', order: 'desc' },
     *   { column: 'name', order: 'asc' }
     * ]);
     * sorted.free();
     */
    sortBy(sortSpecs) {
        this._checkNotFreed();

        if (!Array.isArray(sortSpecs) || sortSpecs.length === 0) {
            throw new Error('sortBy() requires a non-empty array of sort specifications');
        }

        // Validate and normalize sort specs (strip type hints)
        const normalizedSpecs = [];
        for (const spec of sortSpecs) {
            if (typeof spec.column !== 'string' || spec.column.length === 0) {
                throw new Error('Each sort spec must have a column name');
            }
            if (spec.order !== 'asc' && spec.order !== 'desc') {
                throw new Error('Each sort spec must have order "asc" or "desc"');
            }

            // Strip type hints (e.g., "age:Int64" → "age")
            const normalizedColumn = spec.column.includes(':')
                ? spec.column.split(':')[0]
                : spec.column;

            normalizedSpecs.push({
                column: normalizedColumn,
                order: spec.order
            });
        }

        const wasm = this._wasm;
        const jsonStr = JSON.stringify(normalizedSpecs);
        const jsonBytes = new TextEncoder().encode(jsonStr);

        // Allocate scratch space for JSON
        const jsonPtr = wasm.instance.exports.rozes_alloc(jsonBytes.length);
        if (jsonPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate JSON buffer');
        }

        try {
            // Copy JSON to WASM memory
            new Uint8Array(wasm.memory.buffer, jsonPtr, jsonBytes.length).set(jsonBytes);

            const newHandle = wasm.instance.exports.rozes_sortBy(
                this._handle,
                jsonPtr,
                jsonBytes.length
            );

            checkResult(newHandle, 'Failed to sort by multiple columns');

            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(jsonPtr, jsonBytes.length);
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
     * @param {string|string[]} on - Column name(s) to join on (not required for cross join)
     * @param {string} how - Join type: 'inner', 'left', 'right', 'outer', or 'cross' (default: 'inner')
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
     * // Result: all rows from left + matching rows from right (with nulls for unmatched)
     * joined.free();
     *
     * @example
     * // Right join
     * const joined = orders.join(customers, 'customer_id', 'right');
     * // Result: all rows from right + matching rows from left
     * joined.free();
     *
     * @example
     * // Outer join (full outer)
     * const joined = left.join(right, 'id', 'outer');
     * // Result: all rows from both DataFrames (with nulls for unmatched)
     * joined.free();
     *
     * @example
     * // Cross join (Cartesian product - no join columns needed)
     * const crossed = colors.join(sizes, null, 'cross');
     * // Result: every combination of rows from both DataFrames
     * crossed.free();
     */
    join(other, on, how = 'inner') {
        this._checkNotFreed();

        if (!(other instanceof DataFrame)) {
            throw new Error('join() requires another DataFrame as first argument');
        }
        if (other._freed) {
            throw new Error('Cannot join with a freed DataFrame');
        }

        // Validate join type
        const joinTypeMap = {
            'inner': 0,
            'left': 1,
            'right': 2,
            'outer': 3,
            'cross': 4
        };

        if (!joinTypeMap.hasOwnProperty(how)) {
            throw new Error(`Invalid join type '${how}'. Must be 'inner', 'left', 'right', 'outer', or 'cross'`);
        }

        const joinTypeCode = joinTypeMap[how];
        const wasm = this._wasm;

        // Cross join doesn't require join columns
        if (how === 'cross') {
            const newHandle = wasm.instance.exports.rozes_join(
                this._handle,
                other._handle,
                0, // No join columns needed
                0, // Length 0
                joinTypeCode
            );

            checkResult(newHandle, `Failed to cross join`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        }

        // Normalize 'on' to array for other join types
        const joinColumns = Array.isArray(on) ? on : [on];
        if (joinColumns.length === 0) {
            throw new Error('join() requires at least one column name for non-cross joins');
        }

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
     * Export DataFrame to CSV file (Node.js only)
     * @param {string} filePath - Path to write CSV file
     * @param {Object} [options] - CSV export options (same as toCSV)
     * @param {string} [options.delimiter=','] - Field delimiter
     * @param {boolean} [options.header=true] - Include header row
     * @param {string} [options.quoteChar='"'] - Quote character for strings
     * @param {string} [options.lineEnding='\n'] - Line ending character(s)
     * @returns {void}
     * @example
     * const df = DataFrame.fromCSV('name,age\nAlice,30\nBob,25\n', { hasHeader: true });
     * df.toCSVFile('./output.csv', { delimiter: ',', header: true });
     */
    async toCSVFile(filePath, options = {}) {
        this._checkNotFreed();

        // Check if running in Node.js
        if (typeof process === 'undefined' || !process.versions || !process.versions.node) {
            throw new Error('toCSVFile() is only available in Node.js environment');
        }

        if (!filePath || typeof filePath !== 'string') {
            throw new Error('toCSVFile() requires a non-empty file path');
        }

        // Generate CSV string
        const csvString = this.toCSV(options);

        // Write to file using Node.js fs
        const fs = await import('fs');
        fs.writeFileSync(filePath, csvString, 'utf8');
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
     * Compute sum of a numeric column using SIMD acceleration
     * @param {string} columnName - Name of the column
     * @returns {number} - Sum of the column values
     * @example
     * const total = df.sum('price');
     * console.log(`Total price: ${total}`);
     */
    sum(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('sum() requires a non-empty column name');
        }

        // Allocate memory for column name
        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const result = wasm.instance.exports.rozes_sum(
                this._handle,
                namePtr,
                nameBytes.length
            );

            if (isNaN(result)) {
                throw new Error(`Failed to compute sum of column '${columnName}'`);
            }

            return result;
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute mean of a numeric column using SIMD acceleration
     * @param {string} columnName - Name of the column
     * @returns {number} - Mean of the column values
     * @example
     * const avgAge = df.mean('age');
     * console.log(`Average age: ${avgAge}`);
     */
    mean(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('mean() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const result = wasm.instance.exports.rozes_mean(
                this._handle,
                namePtr,
                nameBytes.length
            );

            if (isNaN(result)) {
                throw new Error(`Failed to compute mean of column '${columnName}'`);
            }

            return result;
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Find minimum value in a numeric column using SIMD acceleration
     * @param {string} columnName - Name of the column
     * @returns {number} - Minimum value in the column
     * @example
     * const minPrice = df.min('price');
     * console.log(`Lowest price: ${minPrice}`);
     */
    min(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('min() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const result = wasm.instance.exports.rozes_min(
                this._handle,
                namePtr,
                nameBytes.length
            );

            if (isNaN(result)) {
                throw new Error(`Failed to compute min of column '${columnName}'`);
            }

            return result;
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Find maximum value in a numeric column using SIMD acceleration
     * @param {string} columnName - Name of the column
     * @returns {number} - Maximum value in the column
     * @example
     * const maxScore = df.max('score');
     * console.log(`Highest score: ${maxScore}`);
     */
    max(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('max() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const result = wasm.instance.exports.rozes_max(
                this._handle,
                namePtr,
                nameBytes.length
            );

            if (isNaN(result)) {
                throw new Error(`Failed to compute max of column '${columnName}'`);
            }

            return result;
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute variance of a numeric column using SIMD acceleration
     * @param {string} columnName - Name of the column
     * @returns {number} - Sample variance of the column values
     * @example
     * const priceVar = df.variance('price');
     * console.log(`Price variance: ${priceVar}`);
     */
    variance(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('variance() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const result = wasm.instance.exports.rozes_variance(
                this._handle,
                namePtr,
                nameBytes.length
            );

            if (isNaN(result)) {
                throw new Error(`Failed to compute variance of column '${columnName}'`);
            }

            return result;
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute standard deviation of a numeric column using SIMD acceleration
     * @param {string} columnName - Name of the column
     * @returns {number} - Standard deviation of the column values
     * @example
     * const ageStd = df.stddev('age');
     * console.log(`Age std dev: ${ageStd}`);
     */
    stddev(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('stddev() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const result = wasm.instance.exports.rozes_stddev(
                this._handle,
                namePtr,
                nameBytes.length
            );

            if (isNaN(result)) {
                throw new Error(`Failed to compute stddev of column '${columnName}'`);
            }

            return result;
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute median of a numeric column
     * @param {string} columnName - Name of the column
     * @returns {number} - Median value
     * @example
     * const df = DataFrame.fromCSV('age\n25\n30\n35\n40\n45\n');
     * const medianAge = df.median('age');
     * console.log(`Median age: ${medianAge}`); // 35
     */
    median(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('median() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const result = wasm.instance.exports.rozes_median(
                this._handle,
                namePtr,
                nameBytes.length
            );

            if (isNaN(result)) {
                throw new Error(`Failed to compute median of column '${columnName}'`);
            }

            return result;
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute quantile/percentile of a numeric column
     * @param {string} columnName - Name of the column
     * @param {number} q - Quantile value between 0.0 and 1.0 (e.g., 0.25 for 25th percentile)
     * @returns {number} - Quantile value
     * @example
     * const df = DataFrame.fromCSV('score\n10\n20\n30\n40\n50\n');
     * const q25 = df.quantile('score', 0.25);
     * const q75 = df.quantile('score', 0.75);
     * console.log(`25th percentile: ${q25}, 75th percentile: ${q75}`);
     */
    quantile(columnName, q) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('quantile() requires a non-empty column name');
        }

        if (typeof q !== 'number' || q < 0 || q > 1) {
            throw new Error('quantile() requires q to be between 0.0 and 1.0');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const result = wasm.instance.exports.rozes_quantile(
                this._handle,
                namePtr,
                nameBytes.length,
                q
            );

            if (isNaN(result)) {
                throw new Error(`Failed to compute quantile of column '${columnName}'`);
            }

            return result;
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Count frequency of unique values in a column
     * @param {string} columnName - Name of the column
     * @returns {Object} - Object mapping values to counts
     * @example
     * const df = DataFrame.fromCSV('city\nNY\nLA\nNY\nLA\nLA\n');
     * const counts = df.valueCounts('city');
     * console.log(counts); // { LA: 3, NY: 2 }
     */
    valueCounts(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('valueCounts() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        // Allocate 64KB buffer for JSON result
        const resultSize = 65536;
        const resultPtr = wasm.instance.exports.rozes_alloc(resultSize);
        if (resultPtr === 0) {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate result buffer');
        }

        try {
            const code = wasm.instance.exports.rozes_valueCounts(
                this._handle,
                namePtr,
                nameBytes.length,
                resultPtr,
                resultSize
            );

            checkResult(code, `Failed to compute value counts for column '${columnName}'`);

            // Read JSON result
            const resultBuffer = new Uint8Array(wasm.memory.buffer, resultPtr, resultSize);
            const nullIndex = resultBuffer.indexOf(0);
            const jsonStr = new TextDecoder().decode(resultBuffer.subarray(0, nullIndex));
            return JSON.parse(jsonStr);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
            wasm.instance.exports.rozes_free_buffer(resultPtr, resultSize);
        }
    }

    /**
     * Compute correlation matrix for numeric columns
     * @param {Array<string>} [columnNames] - Optional array of column names (defaults to all numeric columns)
     * @returns {Object} - Nested object representing correlation matrix
     * @example
     * const df = DataFrame.fromCSV('age,income,score\n25,50000,85\n30,60000,90\n35,70000,95\n');
     * const corr = df.corrMatrix();
     * console.log(corr);
     * // {
     * //   age: { age: 1.0, income: 1.0, score: 1.0 },
     * //   income: { age: 1.0, income: 1.0, score: 1.0 },
     * //   score: { age: 1.0, income: 1.0, score: 1.0 }
     * // }
     */
    corrMatrix(columnNames = null) {
        this._checkNotFreed();
        const wasm = this._wasm;

        // If no column names provided, pass null to use all numeric columns
        const colNamesJson = columnNames ? JSON.stringify(columnNames) : null;
        const colNamesBytes = colNamesJson ? new TextEncoder().encode(colNamesJson) : new Uint8Array(0);
        const colNamesPtr = colNamesBytes.length > 0 ? wasm.instance.exports.rozes_alloc(colNamesBytes.length) : 0;

        if (colNamesBytes.length > 0 && colNamesPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column names buffer');
        }

        if (colNamesPtr > 0) {
            const colNamesBuffer = new Uint8Array(wasm.memory.buffer, colNamesPtr, colNamesBytes.length);
            colNamesBuffer.set(colNamesBytes);
        }

        // Allocate 64KB buffer for JSON result
        const resultSize = 65536;
        const resultPtr = wasm.instance.exports.rozes_alloc(resultSize);
        if (resultPtr === 0) {
            if (colNamesPtr > 0) {
                wasm.instance.exports.rozes_free_buffer(colNamesPtr, colNamesBytes.length);
            }
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate result buffer');
        }

        try {
            const code = wasm.instance.exports.rozes_corrMatrix(
                this._handle,
                colNamesPtr,
                colNamesBytes.length,
                resultPtr,
                resultSize
            );

            checkResult(code, 'Failed to compute correlation matrix');

            // Read JSON result
            const resultBuffer = new Uint8Array(wasm.memory.buffer, resultPtr, resultSize);
            const nullIndex = resultBuffer.indexOf(0);
            const jsonStr = new TextDecoder().decode(resultBuffer.subarray(0, nullIndex));
            return JSON.parse(jsonStr);
        } finally {
            if (colNamesPtr > 0) {
                wasm.instance.exports.rozes_free_buffer(colNamesPtr, colNamesBytes.length);
            }
            wasm.instance.exports.rozes_free_buffer(resultPtr, resultSize);
        }
    }

    /**
     * Rank values in a column
     * @param {string} columnName - Name of the column
     * @param {string} [method='average'] - Tie-handling method: 'average', 'min', 'max', 'dense', or 'ordinal'
     * @returns {DataFrame} - New DataFrame with Float64 rank column
     * @example
     * const df = DataFrame.fromCSV('score\n85\n90\n85\n95\n');
     * const ranked = df.rank('score', 'min');
     * console.log(ranked.column('score')); // [1, 3, 1, 4] (ties get minimum rank)
     */
    rank(columnName, method = 'average') {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('rank() requires a non-empty column name');
        }

        // Strip type hints (e.g., "score:Int64" → "score")
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        const methodMap = {
            'average': 0,
            'min': 1,
            'max': 2,
            'dense': 3,
            'ordinal': 4
        };

        if (!(method in methodMap)) {
            throw new Error(`Invalid rank method '${method}'. Must be one of: average, min, max, dense, ordinal`);
        }

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_rank(
                this._handle,
                namePtr,
                nameBytes.length,
                methodMap[method]
            );

            checkResult(newHandle, `Failed to rank column '${actualColumnName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    // ========================================================================
    // Missing Data Operations (Phase 1-2 - Milestone 1.3.0)
    // ========================================================================

    /**
     * Check for missing values in a column
     * @param {string} columnName - Name of the column to check
     * @returns {DataFrame} - New DataFrame with boolean column indicating nulls
     * @example
     * const df = DataFrame.fromCSV('name,age\nAlice,30\nBob,\nCharlie,25\n', { hasHeader: true, inferTypes: true });
     * const mask = df.isna('age');
     * console.log(mask.column('age_isna')); // Uint8Array [0, 1, 0]
     */
    isna(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('isna() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_isna(
                this._handle,
                namePtr,
                nameBytes.length
            );

            checkResult(newHandle, `Failed to check for missing values in column '${columnName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Check for non-missing values in a column
     * @param {string} columnName - Name of the column to check
     * @returns {DataFrame} - New DataFrame with boolean column indicating non-nulls
     * @example
     * const df = DataFrame.fromCSV('name,age\nAlice,30\nBob,\nCharlie,25\n', { hasHeader: true, inferTypes: true });
     * const mask = df.notna('age');
     * console.log(mask.column('age_notna')); // Uint8Array [1, 0, 1]
     */
    notna(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('notna() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_notna(
                this._handle,
                namePtr,
                nameBytes.length
            );

            checkResult(newHandle, `Failed to check for non-missing values in column '${columnName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Drop rows with missing values
     * @param {string} [columnName] - Optional: Name of the column to check for nulls. If not provided, drops rows with ANY null value.
     * @returns {DataFrame} - New DataFrame with rows containing nulls removed
     * @example
     * // Drop rows with ANY null values
     * const clean1 = df.dropna();
     *
     * // Drop rows with null in specific column
     * const df = DataFrame.fromCSV('name,age\nAlice,30\nBob,\nCharlie,25\n', { hasHeader: true, inferTypes: true });
     * const clean2 = df.dropna('age');
     * console.log(clean2.shape.rows); // 2 (Bob row removed)
     */
    dropna(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        // If no column specified, drop all rows with any nulls
        if (!columnName) {
            const newHandle = wasm.instance.exports.rozes_dropna(this._handle);
            checkResult(newHandle, 'Failed to drop rows with missing values');
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        }

        // If column specified, use filter to keep only non-null rows in that column
        return this.filter((row) => {
            const value = row.get(columnName);
            return value !== null && value !== undefined;
        });
    }

    // ========================================================================
    // String Operations (Phase 1-2 - Milestone 1.3.0)
    // ========================================================================

    /**
     * Convert string column to lowercase
     * @param {string} columnName - Name of the string column
     * @returns {DataFrame} - New DataFrame with lowercase strings
     * @example
     * const df = DataFrame.fromCSV('name\nALICE\nBOB\n', { hasHeader: true });
     * const lower = df.strLower('name');
     */
    strLower(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('strLower() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_str_lower(
                this._handle,
                namePtr,
                nameBytes.length
            );

            checkResult(newHandle, `Failed to convert column '${columnName}' to lowercase`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Convert string column to uppercase
     * @param {string} columnName - Name of the string column
     * @returns {DataFrame} - New DataFrame with uppercase strings
     * @example
     * const df = DataFrame.fromCSV('name\nalice\nbob\n', { hasHeader: true });
     * const upper = df.strUpper('name');
     */
    strUpper(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('strUpper() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_str_upper(
                this._handle,
                namePtr,
                nameBytes.length
            );

            checkResult(newHandle, `Failed to convert column '${columnName}' to uppercase`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Trim whitespace from string column
     * @param {string} columnName - Name of the string column
     * @returns {DataFrame} - New DataFrame with trimmed strings
     * @example
     * const df = DataFrame.fromCSV('name\n  alice  \n  bob  \n', { hasHeader: true });
     * const trimmed = df.strTrim('name');
     */
    strTrim(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('strTrim() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_str_trim(
                this._handle,
                namePtr,
                nameBytes.length
            );

            checkResult(newHandle, `Failed to trim whitespace from column '${columnName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Check if strings contain a pattern
     * @param {string} columnName - Name of the string column
     * @param {string} pattern - Pattern to search for
     * @returns {DataFrame} - New DataFrame with boolean column
     * @example
     * const df = DataFrame.fromCSV('text\nhello world\ngoodbye\n', { hasHeader: true });
     * const contains = df.strContains('text', 'world');
     */
    strContains(columnName, pattern) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('strContains() requires a non-empty column name');
        }
        if (!pattern || typeof pattern !== 'string') {
            throw new Error('strContains() requires a non-empty pattern');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const patternBytes = new TextEncoder().encode(pattern);

        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const patternPtr = wasm.instance.exports.rozes_alloc(patternBytes.length);

        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        const patternBuffer = new Uint8Array(wasm.memory.buffer, patternPtr, patternBytes.length);
        nameBuffer.set(nameBytes);
        patternBuffer.set(patternBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_str_contains(
                this._handle,
                namePtr,
                nameBytes.length,
                patternPtr,
                patternBytes.length
            );

            checkResult(newHandle, `Failed to check if column '${columnName}' contains '${pattern}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
            wasm.instance.exports.rozes_free_buffer(patternPtr, patternBytes.length);
        }
    }

    /**
     * Replace substring in string column
     * @param {string} columnName - Name of the string column
     * @param {string} oldStr - Substring to replace
     * @param {string} newStr - Replacement substring
     * @returns {DataFrame} - New DataFrame with replaced strings
     * @example
     * const df = DataFrame.fromCSV('text\nhello world\ngoodbye world\n', { hasHeader: true });
     * const replaced = df.strReplace('text', 'world', 'universe');
     */
    strReplace(columnName, oldStr, newStr) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('strReplace() requires a non-empty column name');
        }
        if (typeof oldStr !== 'string') {
            throw new Error('strReplace() requires oldStr as string');
        }
        if (typeof newStr !== 'string') {
            throw new Error('strReplace() requires newStr as string');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const oldBytes = new TextEncoder().encode(oldStr);
        const newBytes = new TextEncoder().encode(newStr);

        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const oldPtr = wasm.instance.exports.rozes_alloc(oldBytes.length);
        const newPtr = wasm.instance.exports.rozes_alloc(newBytes.length);

        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        const oldBuffer = new Uint8Array(wasm.memory.buffer, oldPtr, oldBytes.length);
        const newBuffer = new Uint8Array(wasm.memory.buffer, newPtr, newBytes.length);
        nameBuffer.set(nameBytes);
        oldBuffer.set(oldBytes);
        newBuffer.set(newBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_str_replace(
                this._handle,
                namePtr,
                nameBytes.length,
                oldPtr,
                oldBytes.length,
                newPtr,
                newBytes.length
            );

            checkResult(newHandle, `Failed to replace '${oldStr}' with '${newStr}' in column '${columnName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
            wasm.instance.exports.rozes_free_buffer(oldPtr, oldBytes.length);
            wasm.instance.exports.rozes_free_buffer(newPtr, newBytes.length);
        }
    }

    /**
     * Extract substring from string column
     * @param {string} columnName - Name of the string column
     * @param {number} start - Start index (inclusive)
     * @param {number} end - End index (exclusive)
     * @returns {DataFrame} - New DataFrame with sliced strings
     * @example
     * const df = DataFrame.fromCSV('text\nhello\nworld\n', { hasHeader: true });
     * const sliced = df.strSlice('text', 0, 3); // 'hel', 'wor'
     */
    strSlice(columnName, start, end) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('strSlice() requires a non-empty column name');
        }
        if (typeof start !== 'number' || start < 0) {
            throw new Error('strSlice() requires start >= 0');
        }
        if (typeof end !== 'number' || end < start) {
            throw new Error('strSlice() requires end >= start');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_str_slice(
                this._handle,
                namePtr,
                nameBytes.length,
                start,
                end
            );

            checkResult(newHandle, `Failed to slice column '${columnName}'[${start}:${end}]`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Check if strings start with prefix
     * @param {string} columnName - Name of the string column
     * @param {string} prefix - Prefix to check for
     * @returns {DataFrame} - New DataFrame with boolean column
     * @example
     * const df = DataFrame.fromCSV('text\nhello\nworld\n', { hasHeader: true });
     * const starts = df.strStartsWith('text', 'he'); // true, false
     */
    strStartsWith(columnName, prefix) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('strStartsWith() requires a non-empty column name');
        }
        if (!prefix || typeof prefix !== 'string') {
            throw new Error('strStartsWith() requires a non-empty prefix');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const prefixBytes = new TextEncoder().encode(prefix);

        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const prefixPtr = wasm.instance.exports.rozes_alloc(prefixBytes.length);

        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        const prefixBuffer = new Uint8Array(wasm.memory.buffer, prefixPtr, prefixBytes.length);
        nameBuffer.set(nameBytes);
        prefixBuffer.set(prefixBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_str_startsWith(
                this._handle,
                namePtr,
                nameBytes.length,
                prefixPtr,
                prefixBytes.length
            );

            checkResult(newHandle, `Failed to check if column '${columnName}' starts with '${prefix}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
            wasm.instance.exports.rozes_free_buffer(prefixPtr, prefixBytes.length);
        }
    }

    /**
     * Check if strings end with suffix
     * @param {string} columnName - Name of the string column
     * @param {string} suffix - Suffix to check for
     * @returns {DataFrame} - New DataFrame with boolean column
     * @example
     * const df = DataFrame.fromCSV('text\nhello\nworld\n', { hasHeader: true });
     * const ends = df.strEndsWith('text', 'lo'); // true, false
     */
    strEndsWith(columnName, suffix) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('strEndsWith() requires a non-empty column name');
        }
        if (!suffix || typeof suffix !== 'string') {
            throw new Error('strEndsWith() requires a non-empty suffix');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const suffixBytes = new TextEncoder().encode(suffix);

        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const suffixPtr = wasm.instance.exports.rozes_alloc(suffixBytes.length);

        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        const suffixBuffer = new Uint8Array(wasm.memory.buffer, suffixPtr, suffixBytes.length);
        nameBuffer.set(nameBytes);
        suffixBuffer.set(suffixBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_str_endsWith(
                this._handle,
                namePtr,
                nameBytes.length,
                suffixPtr,
                suffixBytes.length
            );

            checkResult(newHandle, `Failed to check if column '${columnName}' ends with '${suffix}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
            wasm.instance.exports.rozes_free_buffer(suffixPtr, suffixBytes.length);
        }
    }

    /**
     * Get string lengths
     * @param {string} columnName - Name of the string column
     * @returns {DataFrame} - New DataFrame with Int64 column containing string lengths
     * @example
     * const df = DataFrame.fromCSV('text\nhello\nworld\n', { hasHeader: true });
     * const lens = df.strLen('text'); // 5, 5
     */
    strLen(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('strLen() requires a non-empty column name');
        }

        const nameBytes = new TextEncoder().encode(columnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_str_len(
                this._handle,
                namePtr,
                nameBytes.length
            );

            checkResult(newHandle, `Failed to get string lengths for column '${columnName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    // ========================================================================
    // Window Operations (Phase 4 - Milestone 1.3.0)
    // ========================================================================

    /**
     * Apply rolling window aggregation to a column
     * @param {string} columnName - Name of the column
     * @param {number} windowSize - Window size (must be > 0)
     * @param {string} aggregation - Aggregation function: 'sum', 'mean', 'min', 'max', or 'std'
     * @returns {DataFrame} - New DataFrame with rolling aggregation result
     * @example
     * const df = DataFrame.fromCSV('value\n10\n20\n30\n40\n50\n');
     * const rollingMean = df.rolling('value', 3, 'mean');
     * console.log(rollingMean.column('value')); // [10, 15, 20, 30, 40]
     */
    rolling(columnName, windowSize, aggregation = 'mean') {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('rolling() requires a non-empty column name');
        }

        if (typeof windowSize !== 'number' || windowSize <= 0) {
            throw new Error('rolling() requires windowSize to be a positive number');
        }

        // Strip type hints (e.g., "value:Int64" → "value")
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        const aggMap = {
            'sum': 0,
            'mean': 1,
            'min': 2,
            'max': 3,
            'std': 4
        };

        if (!(aggregation in aggMap)) {
            throw new Error(`Invalid aggregation '${aggregation}'. Must be one of: sum, mean, min, max, std`);
        }

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_rolling(
                this._handle,
                namePtr,
                nameBytes.length,
                windowSize,
                aggMap[aggregation]
            );

            checkResult(newHandle, `Failed to compute rolling ${aggregation} for column '${actualColumnName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Apply expanding (cumulative) window aggregation to a column
     * @param {string} columnName - Name of the column
     * @param {string} aggregation - Aggregation function: 'sum' or 'mean'
     * @returns {DataFrame} - New DataFrame with expanding aggregation result
     * @example
     * const df = DataFrame.fromCSV('value\n10\n20\n30\n40\n50\n');
     * const cumsum = df.expanding('value', 'sum');
     * console.log(cumsum.column('value')); // [10, 30, 60, 100, 150]
     */
    expanding(columnName, aggregation = 'sum') {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('expanding() requires a non-empty column name');
        }

        // Strip type hints (e.g., "value:Int64" → "value")
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        const aggMap = {
            'sum': 0,
            'mean': 1
        };

        if (!(aggregation in aggMap)) {
            throw new Error(`Invalid aggregation '${aggregation}'. Must be one of: sum, mean`);
        }

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_expanding(
                this._handle,
                namePtr,
                nameBytes.length,
                aggMap[aggregation]
            );

            checkResult(newHandle, `Failed to compute expanding ${aggregation} for column '${actualColumnName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Shift column values by a given number of periods
     * @param {string} columnName - Name of the column
     * @param {number} periods - Number of periods to shift (positive = forward, negative = backward)
     * @returns {DataFrame} - New DataFrame with shifted values (shifted positions filled with NaN)
     * @example
     * const df = DataFrame.fromCSV('value\n10\n20\n30\n40\n50\n');
     * const shifted = df.shift('value', 1); // Shift forward by 1
     * console.log(shifted.column('value')); // [NaN, 10, 20, 30, 40]
     */
    shift(columnName, periods = 1) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('shift() requires a non-empty column name');
        }

        // Strip type hints (e.g., "value:Int64" → "value")
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        if (typeof periods !== 'number' || !Number.isInteger(periods)) {
            throw new Error('shift() requires periods to be an integer');
        }

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_shift(
                this._handle,
                namePtr,
                nameBytes.length,
                periods
            );

            checkResult(newHandle, `Failed to shift column '${actualColumnName}' by ${periods} periods`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute first discrete difference (current - previous)
     * @param {string} columnName - Name of the column
     * @param {number} periods - Number of periods for difference (default = 1)
     * @returns {DataFrame} - New DataFrame with difference values (first N periods are NaN)
     * @example
     * const df = DataFrame.fromCSV('value\n10\n15\n12\n20\n25\n');
     * const diff = df.diff('value', 1);
     * console.log(diff.column('value')); // [NaN, 5, -3, 8, 5]
     */
    diff(columnName, periods = 1) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('diff() requires a non-empty column name');
        }

        // Strip type hints (e.g., "value:Int64" → "value")
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        if (typeof periods !== 'number' || !Number.isInteger(periods) || periods <= 0) {
            throw new Error('diff() requires periods to be a positive integer');
        }

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_diff(
                this._handle,
                namePtr,
                nameBytes.length,
                periods
            );

            checkResult(newHandle, `Failed to compute diff for column '${actualColumnName}' with periods ${periods}`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute percentage change (percent difference from previous value)
     * @param {string} columnName - Name of the column
     * @param {number} periods - Number of periods for percent change (default = 1)
     * @returns {DataFrame} - New DataFrame with percent change values (first N periods are NaN, zeros result in NaN)
     * @example
     * const df = DataFrame.fromCSV('value\n100\n110\n105\n120\n');
     * const pctChange = df.pctChange('value', 1);
     * console.log(pctChange.column('value')); // [NaN, 0.1, -0.045, 0.143]
     */
    pctChange(columnName, periods = 1) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('pctChange() requires a non-empty column name');
        }

        // Strip type hints (e.g., "value:Int64" → "value")
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        if (typeof periods !== 'number' || !Number.isInteger(periods) || periods <= 0) {
            throw new Error('pctChange() requires periods to be a positive integer');
        }

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_pctChange(
                this._handle,
                namePtr,
                nameBytes.length,
                periods
            );

            checkResult(newHandle, `Failed to compute pctChange for column '${actualColumnName}' with periods ${periods}`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute rolling sum over a window
     * @param {string} columnName - Name of the column
     * @param {number} window - Size of the rolling window
     * @returns {DataFrame} - New DataFrame with rolling sum values (first window-1 values are NaN)
     * @example
     * const df = DataFrame.fromCSV('value\n10\n20\n30\n40\n50\n');
     * const rolling = df.rollingSum('value', 3);
     * console.log(rolling.column('value')); // [NaN, NaN, 60, 90, 120]
     */
    rollingSum(columnName, window) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('rollingSum() requires a non-empty column name');
        }

        // Strip type hints
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        if (typeof window !== 'number' || !Number.isInteger(window) || window <= 0) {
            throw new Error('rollingSum() requires window to be a positive integer');
        }

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_rolling_sum(
                this._handle,
                namePtr,
                nameBytes.length,
                window
            );

            checkResult(newHandle, `Failed to compute rolling sum for column '${actualColumnName}' with window ${window}`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute rolling mean over a window
     * @param {string} columnName - Name of the column
     * @param {number} window - Size of the rolling window
     * @returns {DataFrame} - New DataFrame with rolling mean values (first window-1 values are NaN)
     * @example
     * const df = DataFrame.fromCSV('value\n10\n20\n30\n40\n50\n');
     * const rolling = df.rollingMean('value', 3);
     * console.log(rolling.column('value')); // [NaN, NaN, 20, 30, 40]
     */
    rollingMean(columnName, window) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('rollingMean() requires a non-empty column name');
        }

        // Strip type hints
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        if (typeof window !== 'number' || !Number.isInteger(window) || window <= 0) {
            throw new Error('rollingMean() requires window to be a positive integer');
        }

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_rolling_mean(
                this._handle,
                namePtr,
                nameBytes.length,
                window
            );

            checkResult(newHandle, `Failed to compute rolling mean for column '${actualColumnName}' with window ${window}`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute rolling minimum over a window
     * @param {string} columnName - Name of the column
     * @param {number} window - Size of the rolling window
     * @returns {DataFrame} - New DataFrame with rolling min values (first window-1 values are NaN)
     * @example
     * const df = DataFrame.fromCSV('value\n30\n10\n20\n40\n50\n');
     * const rolling = df.rollingMin('value', 3);
     * console.log(rolling.column('value')); // [NaN, NaN, 10, 10, 20]
     */
    rollingMin(columnName, window) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('rollingMin() requires a non-empty column name');
        }

        // Strip type hints
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        if (typeof window !== 'number' || !Number.isInteger(window) || window <= 0) {
            throw new Error('rollingMin() requires window to be a positive integer');
        }

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_rolling_min(
                this._handle,
                namePtr,
                nameBytes.length,
                window
            );

            checkResult(newHandle, `Failed to compute rolling min for column '${actualColumnName}' with window ${window}`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute rolling maximum over a window
     * @param {string} columnName - Name of the column
     * @param {number} window - Size of the rolling window
     * @returns {DataFrame} - New DataFrame with rolling max values (first window-1 values are NaN)
     * @example
     * const df = DataFrame.fromCSV('value\n30\n10\n20\n40\n50\n');
     * const rolling = df.rollingMax('value', 3);
     * console.log(rolling.column('value')); // [NaN, NaN, 30, 40, 50]
     */
    rollingMax(columnName, window) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('rollingMax() requires a non-empty column name');
        }

        // Strip type hints
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        if (typeof window !== 'number' || !Number.isInteger(window) || window <= 0) {
            throw new Error('rollingMax() requires window to be a positive integer');
        }

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_rolling_max(
                this._handle,
                namePtr,
                nameBytes.length,
                window
            );

            checkResult(newHandle, `Failed to compute rolling max for column '${actualColumnName}' with window ${window}`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute rolling standard deviation over a window
     * @param {string} columnName - Name of the column
     * @param {number} window - Size of the rolling window
     * @returns {DataFrame} - New DataFrame with rolling std values (first window-1 values are NaN)
     * @example
     * const df = DataFrame.fromCSV('value\n10\n20\n30\n40\n50\n');
     * const rolling = df.rollingStd('value', 3);
     * console.log(rolling.column('value')); // [NaN, NaN, 10.0, 10.0, 10.0]
     */
    rollingStd(columnName, window) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('rollingStd() requires a non-empty column name');
        }

        // Strip type hints
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        if (typeof window !== 'number' || !Number.isInteger(window) || window <= 0) {
            throw new Error('rollingStd() requires window to be a positive integer');
        }

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_rolling_std(
                this._handle,
                namePtr,
                nameBytes.length,
                window
            );

            checkResult(newHandle, `Failed to compute rolling std for column '${actualColumnName}' with window ${window}`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute expanding sum (cumulative sum from start to current row)
     * @param {string} columnName - Name of the column
     * @returns {DataFrame} - New DataFrame with expanding sum values
     * @example
     * const df = DataFrame.fromCSV('value\n10\n20\n30\n40\n50\n');
     * const expanding = df.expandingSum('value');
     * console.log(expanding.column('value')); // [10, 30, 60, 100, 150]
     */
    expandingSum(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('expandingSum() requires a non-empty column name');
        }

        // Strip type hints
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_expanding_sum(
                this._handle,
                namePtr,
                nameBytes.length
            );

            checkResult(newHandle, `Failed to compute expanding sum for column '${actualColumnName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Compute expanding mean (cumulative mean from start to current row)
     * @param {string} columnName - Name of the column
     * @returns {DataFrame} - New DataFrame with expanding mean values
     * @example
     * const df = DataFrame.fromCSV('value\n10\n20\n30\n40\n50\n');
     * const expanding = df.expandingMean('value');
     * console.log(expanding.column('value')); // [10, 15, 20, 25, 30]
     */
    expandingMean(columnName) {
        this._checkNotFreed();
        const wasm = this._wasm;

        if (!columnName || typeof columnName !== 'string') {
            throw new Error('expandingMean() requires a non-empty column name');
        }

        // Strip type hints
        const colonIndex = columnName.indexOf(':');
        const actualColumnName = colonIndex >= 0 ? columnName.substring(0, colonIndex) : columnName;

        const nameBytes = new TextEncoder().encode(actualColumnName);
        const namePtr = wasm.instance.exports.rozes_alloc(nameBytes.length);
        const nameBuffer = new Uint8Array(wasm.memory.buffer, namePtr, nameBytes.length);
        nameBuffer.set(nameBytes);

        try {
            const newHandle = wasm.instance.exports.rozes_expanding_mean(
                this._handle,
                namePtr,
                nameBytes.length
            );

            checkResult(newHandle, `Failed to compute expanding mean for column '${actualColumnName}'`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(namePtr, nameBytes.length);
        }
    }

    /**
     * Pivot DataFrame from long format to wide format
     *
     * @param {Object} options - Pivot options
     * @param {string} options.index - Column for row labels
     * @param {string} options.columns - Column to pivot (becomes new columns)
     * @param {string} options.values - Column containing values to aggregate
     * @param {string} [options.aggfunc='sum'] - Aggregation function: 'sum', 'mean', 'count', 'min', 'max'
     * @returns {DataFrame} New DataFrame with pivoted data
     *
     * @example
     * const df = rozes.DataFrame.fromCSV('date,region,sales\n2024-01-01,East,100\n2024-01-01,West,200');
     * const pivoted = df.pivot({ index: 'date', columns: 'region', values: 'sales' });
     * // Result: date, East, West
     * //         2024-01-01, 100, 200
     */
    pivot(options) {
        if (this._freed) {
            throw new Error('Cannot pivot a freed DataFrame');
        }

        // Validate options
        if (!options || typeof options !== 'object') {
            throw new Error('pivot() requires an options object');
        }
        if (!options.index || typeof options.index !== 'string') {
            throw new Error('pivot() requires index column name (string)');
        }
        if (!options.columns || typeof options.columns !== 'string') {
            throw new Error('pivot() requires columns column name (string)');
        }
        if (!options.values || typeof options.values !== 'string') {
            throw new Error('pivot() requires values column name (string)');
        }

        const aggfunc = options.aggfunc || 'sum';
        const validAggFuncs = ['sum', 'mean', 'count', 'min', 'max'];
        if (!validAggFuncs.includes(aggfunc)) {
            throw new Error(`pivot() aggfunc must be one of: ${validAggFuncs.join(', ')}`);
        }

        const wasm = this._wasm;
        const optionsJson = JSON.stringify({
            index: options.index,
            columns: options.columns,
            values: options.values,
            aggfunc: aggfunc
        });

        const optionsBytes = new TextEncoder().encode(optionsJson);
        const optionsPtr = wasm.instance.exports.rozes_alloc(optionsBytes.length);

        try {
            new Uint8Array(wasm.memory.buffer, optionsPtr, optionsBytes.length).set(optionsBytes);

            const newHandle = wasm.instance.exports.rozes_pivot(
                this._handle,
                optionsPtr,
                optionsBytes.length
            );

            checkResult(newHandle, `Failed to pivot DataFrame`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(optionsPtr, optionsBytes.length);
        }
    }

    /**
     * Melt DataFrame from wide format to long format (unpivot)
     *
     * @param {Object} options - Melt options
     * @param {string[]} options.id_vars - Columns to preserve as identifiers
     * @param {string[]} [options.value_vars] - Columns to melt (if null, melt all non-id columns)
     * @param {string} [options.var_name='variable'] - Name for the variable column
     * @param {string} [options.value_name='value'] - Name for the value column
     * @returns {DataFrame} New DataFrame with melted data
     *
     * @example
     * const df = rozes.DataFrame.fromCSV('date,East,West\n2024-01-01,100,200');
     * const melted = df.melt({ id_vars: ['date'], var_name: 'region', value_name: 'sales' });
     * // Result: date, region, sales
     * //         2024-01-01, East, 100
     * //         2024-01-01, West, 200
     */
    melt(options) {
        if (this._freed) {
            throw new Error('Cannot melt a freed DataFrame');
        }

        // Validate options
        if (!options || typeof options !== 'object') {
            throw new Error('melt() requires an options object');
        }
        if (!Array.isArray(options.id_vars)) {
            throw new Error('melt() requires id_vars to be an array of column names');
        }
        if (options.value_vars && !Array.isArray(options.value_vars)) {
            throw new Error('melt() value_vars must be an array of column names');
        }

        const wasm = this._wasm;
        const optionsJson = JSON.stringify({
            id_vars: options.id_vars,
            value_vars: options.value_vars || null,
            var_name: options.var_name || 'variable',
            value_name: options.value_name || 'value'
        });

        const optionsBytes = new TextEncoder().encode(optionsJson);
        const optionsPtr = wasm.instance.exports.rozes_alloc(optionsBytes.length);

        try {
            new Uint8Array(wasm.memory.buffer, optionsPtr, optionsBytes.length).set(optionsBytes);

            const newHandle = wasm.instance.exports.rozes_melt(
                this._handle,
                optionsPtr,
                optionsBytes.length
            );

            checkResult(newHandle, `Failed to melt DataFrame`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(optionsPtr, optionsBytes.length);
        }
    }

    /**
     * Transpose DataFrame - swap rows and columns
     *
     * @returns {DataFrame} New DataFrame with transposed data
     *
     * @example
     * const df = rozes.DataFrame.fromCSV('A,B,C\n1,2,3\n4,5,6');
     * const transposed = df.transpose();
     * // Result: row_0, row_1
     * //         1, 4
     * //         2, 5
     * //         3, 6
     */
    transpose() {
        if (this._freed) {
            throw new Error('Cannot transpose a freed DataFrame');
        }

        const wasm = this._wasm;
        const newHandle = wasm.instance.exports.rozes_transpose(this._handle);

        checkResult(newHandle, `Failed to transpose DataFrame`);
        return new DataFrame(newHandle, wasm, this._autoCleanup);
    }

    /**
     * Stack DataFrame - convert wide format to long format (simpler API than melt)
     *
     * @param {Object} options - Stack options
     * @param {string} options.id_column - Column to use as identifier
     * @param {string} [options.var_name='variable'] - Name for the variable column
     * @param {string} [options.value_name='value'] - Name for the value column
     * @returns {DataFrame} New DataFrame with stacked data
     *
     * @example
     * const df = rozes.DataFrame.fromCSV('id,A,B,C\n1,10,20,30\n2,40,50,60');
     * const stacked = df.stack({ id_column: 'id' });
     * // Result: id, variable, value
     * //         1, A, 10
     * //         1, B, 20
     * //         1, C, 30
     * //         2, A, 40
     * //         ...
     */
    stack(options) {
        if (this._freed) {
            throw new Error('Cannot stack a freed DataFrame');
        }

        // Validate options
        if (!options || typeof options !== 'object') {
            throw new Error('stack() requires an options object');
        }
        if (!options.id_column || typeof options.id_column !== 'string') {
            throw new Error('stack() requires id_column (string)');
        }

        const wasm = this._wasm;
        const optionsJson = JSON.stringify({
            id_column: options.id_column,
            var_name: options.var_name || 'variable',
            value_name: options.value_name || 'value'
        });

        const optionsBytes = new TextEncoder().encode(optionsJson);
        const optionsPtr = wasm.instance.exports.rozes_alloc(optionsBytes.length);

        try {
            new Uint8Array(wasm.memory.buffer, optionsPtr, optionsBytes.length).set(optionsBytes);

            const newHandle = wasm.instance.exports.rozes_stack(
                this._handle,
                optionsPtr,
                optionsBytes.length
            );

            checkResult(newHandle, `Failed to stack DataFrame`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(optionsPtr, optionsBytes.length);
        }
    }

    /**
     * Unstack DataFrame - convert long format to wide format (inverse of stack)
     *
     * @param {Object} options - Unstack options
     * @param {string} options.index - Column for index values
     * @param {string} options.columns - Column with variable names (becomes new columns)
     * @param {string} options.values - Column with values to populate
     * @returns {DataFrame} New DataFrame with unstacked data
     *
     * @example
     * const df = rozes.DataFrame.fromCSV('id,variable,value\n1,A,10\n1,B,20\n2,A,40\n2,B,50');
     * const unstacked = df.unstack({ index: 'id', columns: 'variable', values: 'value' });
     * // Result: id, A, B
     * //         1, 10, 20
     * //         2, 40, 50
     */
    unstack(options) {
        if (this._freed) {
            throw new Error('Cannot unstack a freed DataFrame');
        }

        // Validate options
        if (!options || typeof options !== 'object') {
            throw new Error('unstack() requires an options object');
        }
        if (!options.index || typeof options.index !== 'string') {
            throw new Error('unstack() requires index column name (string)');
        }
        if (!options.columns || typeof options.columns !== 'string') {
            throw new Error('unstack() requires columns column name (string)');
        }
        if (!options.values || typeof options.values !== 'string') {
            throw new Error('unstack() requires values column name (string)');
        }

        const wasm = this._wasm;
        const optionsJson = JSON.stringify({
            index: options.index,
            columns: options.columns,
            values: options.values
        });

        const optionsBytes = new TextEncoder().encode(optionsJson);
        const optionsPtr = wasm.instance.exports.rozes_alloc(optionsBytes.length);

        try {
            new Uint8Array(wasm.memory.buffer, optionsPtr, optionsBytes.length).set(optionsBytes);

            const newHandle = wasm.instance.exports.rozes_unstack(
                this._handle,
                optionsPtr,
                optionsBytes.length
            );

            checkResult(newHandle, `Failed to unstack DataFrame`);
            return new DataFrame(newHandle, wasm, this._autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(optionsPtr, optionsBytes.length);
        }
    }

    /**
     * Export DataFrame schema to Apache Arrow JSON format
     *
     * Note: MVP implementation exports schema only (not data).
     * Full Arrow IPC format with zero-copy data transfer coming in future release.
     *
     * @returns {Object} - Arrow schema as JSON object
     *
     * @example
     * const df = DataFrame.fromCSV('name,age\nAlice,30\nBob,25\n');
     * const arrowSchema = df.toArrow();
     * console.log(arrowSchema);
     * // {
     * //   schema: {
     * //     fields: [
     * //       { name: 'name', type: { name: 'utf8' } },
     * //       { name: 'age', type: { name: 'int', bitWidth: 64, isSigned: true } }
     * //     ]
     * //   }
     * // }
     */
    toArrow() {
        this._checkNotFreed();

        const wasm = this._wasm;
        const bufferSize = 8192; // 8KB buffer for schema JSON
        const bufferPtr = wasm.instance.exports.rozes_alloc(bufferSize);
        if (bufferPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate buffer for Arrow schema');
        }

        try {
            const writtenPtr = wasm.instance.exports.rozes_alloc(4); // u32 for bytes written
            if (writtenPtr === 0) {
                throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate written counter');
            }

            try {
                const result = wasm.instance.exports.rozes_toArrow(
                    this._handle,
                    bufferPtr,
                    bufferSize,
                    writtenPtr
                );

                checkResult(result, 'Failed to export DataFrame to Arrow format');

                const written = new Uint32Array(wasm.memory.buffer, writtenPtr, 1)[0];
                const jsonBytes = new Uint8Array(wasm.memory.buffer, bufferPtr, written);
                const jsonStr = new TextDecoder().decode(jsonBytes);

                return JSON.parse(jsonStr);
            } finally {
                wasm.instance.exports.rozes_free_buffer(writtenPtr, 4);
            }
        } finally {
            wasm.instance.exports.rozes_free_buffer(bufferPtr, bufferSize);
        }
    }

    /**
     * Import DataFrame from Apache Arrow JSON schema
     *
     * Note: MVP implementation imports schema only (not data).
     * Full Arrow IPC format with zero-copy data transfer coming in future release.
     *
     * @param {Object} arrowSchema - Arrow schema as JSON object
     * @param {boolean} [autoCleanup=true] - Enable automatic memory cleanup
     * @returns {DataFrame} - New DataFrame from Arrow schema
     *
     * @example
     * const schema = {
     *   schema: {
     *     fields: [
     *       { name: 'name', type: { name: 'utf8' } },
     *       { name: 'age', type: { name: 'int', bitWidth: 64, isSigned: true } }
     *     ]
     *   }
     * };
     * const df = DataFrame.fromArrow(schema);
     */
    static fromArrow(arrowSchema, autoCleanup = true) {
        const wasm = DataFrame._wasm;
        if (!wasm) {
            throw new Error('Rozes not initialized. Call Rozes.init() first.');
        }

        const jsonStr = JSON.stringify(arrowSchema);
        const jsonBytes = new TextEncoder().encode(jsonStr);
        const jsonPtr = wasm.instance.exports.rozes_alloc(jsonBytes.length);
        if (jsonPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate buffer for Arrow schema');
        }

        try {
            const jsonArray = new Uint8Array(wasm.memory.buffer, jsonPtr, jsonBytes.length);
            jsonArray.set(jsonBytes);

            const handle = wasm.instance.exports.rozes_fromArrow(jsonPtr, jsonBytes.length);
            checkResult(handle, 'Failed to import DataFrame from Arrow format');

            return new DataFrame(handle, wasm, autoCleanup);
        } finally {
            wasm.instance.exports.rozes_free_buffer(jsonPtr, jsonBytes.length);
        }
    }

    /**
     * Create a lazy DataFrame for query optimization
     *
     * Lazy evaluation delays execution until `.collect()` is called,
     * allowing the query optimizer to apply transformations like
     * predicate pushdown and projection pushdown.
     *
     * @returns {LazyDataFrame} - Lazy DataFrame wrapper
     *
     * @example
     * const df = DataFrame.fromCSV('name,age,score\nAlice,30,95\nBob,25,87\nCharlie,35,91\n');
     * const result = df.lazy()
     *   .select(['name', 'age'])
     *   .limit(2)
     *   .collect();
     * console.log(result.shape); // { rows: 2, cols: 2 }
     */
    lazy() {
        this._checkNotFreed();

        const wasm = this._wasm;
        const lazyHandle = wasm.instance.exports.rozes_lazy(this._handle);
        checkResult(lazyHandle, 'Failed to create LazyDataFrame');

        return new LazyDataFrame(lazyHandle, wasm, this._autoCleanup);
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
     * Access string operations namespace
     *
     * @returns {StringAccessor} - String operations accessor
     *
     * @example
     * const df = DataFrame.fromCSV('text\nHELLO\nWorld\n');
     * const lower = df.str.lower('text');
     * console.log(lower.column('text')); // ['hello', 'world']
     */
    get str() {
        this._checkNotFreed();
        return new StringAccessor(this);
    }

    /**
     * @private
     * Set by Rozes.init()
     */
    static _wasm = null;
}

/**
 * StringAccessor - Provides string manipulation operations on DataFrame columns
 *
 * Accessed via `df.str.methodName()` (similar to pandas)
 */
class StringAccessor {
    constructor(dataframe) {
        this._df = dataframe;
        this._wasm = dataframe._wasm;
    }

    /**
     * Convert string column to lowercase
     *
     * @param {string} columnName - Name of string column
     * @returns {DataFrame} - New DataFrame with lowercase strings
     *
     * @example
     * const df = DataFrame.fromCSV('text\nHELLO\nWorld\n');
     * const result = df.str.lower('text');
     * console.log(result.column('text')); // ['hello', 'world']
     */
    lower(columnName) {
        this._df._checkNotFreed();

        const colBytes = new TextEncoder().encode(columnName);
        const colPtr = this._wasm.instance.exports.rozes_alloc(colBytes.length);
        if (colPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column name buffer');
        }

        try {
            const colArray = new Uint8Array(this._wasm.memory.buffer, colPtr, colBytes.length);
            colArray.set(colBytes);

            const newHandle = this._wasm.instance.exports.rozes_str_lower(
                this._df._handle,
                colPtr,
                colBytes.length
            );

            checkResult(newHandle, `Failed to str.lower('${columnName}')`);
            return new DataFrame(newHandle, this._wasm, this._df._autoCleanup);
        } finally {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
        }
    }

    /**
     * Convert string column to uppercase
     *
     * @param {string} columnName - Name of string column
     * @returns {DataFrame} - New DataFrame with uppercase strings
     *
     * @example
     * const df = DataFrame.fromCSV('text\nhello\nworld\n');
     * const result = df.str.upper('text');
     * console.log(result.column('text')); // ['HELLO', 'WORLD']
     */
    upper(columnName) {
        this._df._checkNotFreed();

        const colBytes = new TextEncoder().encode(columnName);
        const colPtr = this._wasm.instance.exports.rozes_alloc(colBytes.length);
        if (colPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column name buffer');
        }

        try {
            const colArray = new Uint8Array(this._wasm.memory.buffer, colPtr, colBytes.length);
            colArray.set(colBytes);

            const newHandle = this._wasm.instance.exports.rozes_str_upper(
                this._df._handle,
                colPtr,
                colBytes.length
            );

            checkResult(newHandle, `Failed to str.upper('${columnName}')`);
            return new DataFrame(newHandle, this._wasm, this._df._autoCleanup);
        } finally {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
        }
    }

    /**
     * Trim whitespace from string column
     *
     * @param {string} columnName - Name of string column
     * @returns {DataFrame} - New DataFrame with trimmed strings
     *
     * @example
     * const df = DataFrame.fromCSV('text\n  hello  \n  world  \n');
     * const result = df.str.trim('text');
     * console.log(result.column('text')); // ['hello', 'world']
     */
    trim(columnName) {
        this._df._checkNotFreed();

        const colBytes = new TextEncoder().encode(columnName);
        const colPtr = this._wasm.instance.exports.rozes_alloc(colBytes.length);
        if (colPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column name buffer');
        }

        try {
            const colArray = new Uint8Array(this._wasm.memory.buffer, colPtr, colBytes.length);
            colArray.set(colBytes);

            const newHandle = this._wasm.instance.exports.rozes_str_trim(
                this._df._handle,
                colPtr,
                colBytes.length
            );

            checkResult(newHandle, `Failed to str.trim('${columnName}')`);
            return new DataFrame(newHandle, this._wasm, this._df._autoCleanup);
        } finally {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
        }
    }

    /**
     * Check if strings contain a substring
     *
     * @param {string} columnName - Name of string column
     * @param {string} pattern - Substring to search for
     * @returns {DataFrame} - New DataFrame with boolean column
     *
     * @example
     * const df = DataFrame.fromCSV('text\nhello world\ngoodbye\n');
     * const result = df.str.contains('text', 'world');
     * console.log(result.column('text')); // [true, false]
     */
    contains(columnName, pattern) {
        this._df._checkNotFreed();

        // Tiger Style: Input validation
        if (!columnName || typeof columnName !== 'string' || columnName.length === 0) {
            throw new RozesError(ErrorCode.InvalidInput, 'contains() requires a non-empty column name (string)');
        }
        if (pattern === null || pattern === undefined) {
            throw new RozesError(ErrorCode.InvalidInput, 'contains() requires a pattern argument (use empty string for empty pattern)');
        }
        if (typeof pattern !== 'string') {
            throw new RozesError(ErrorCode.InvalidInput, 'contains() pattern must be a string');
        }

        const colBytes = new TextEncoder().encode(columnName);
        const patternBytes = new TextEncoder().encode(pattern);

        const colPtr = this._wasm.instance.exports.rozes_alloc(colBytes.length);
        if (colPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column name buffer');
        }

        // Handle empty pattern - allocate dummy byte to satisfy rozes_alloc(size > 0) assertion
        const patternPtr = this._wasm.instance.exports.rozes_alloc(patternBytes.length || 1);
        if (patternPtr === 0) {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate pattern buffer');
        }

        try {
            const colArray = new Uint8Array(this._wasm.memory.buffer, colPtr, colBytes.length);
            colArray.set(colBytes);

            // Only copy pattern bytes if pattern is not empty
            if (patternBytes.length > 0) {
                const patternArray = new Uint8Array(this._wasm.memory.buffer, patternPtr, patternBytes.length);
                patternArray.set(patternBytes);
            }

            const newHandle = this._wasm.instance.exports.rozes_str_contains(
                this._df._handle,
                colPtr,
                colBytes.length,
                patternPtr,
                patternBytes.length  // Pass 0 for empty pattern
            );

            checkResult(newHandle, `Failed to str.contains('${columnName}', '${pattern}')`);
            return new DataFrame(newHandle, this._wasm, this._df._autoCleanup);
        } finally {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
            this._wasm.instance.exports.rozes_free_buffer(patternPtr, patternBytes.length || 1);
        }
    }

    /**
     * Replace substring in string column
     *
     * @param {string} columnName - Name of string column
     * @param {string} pattern - Substring to replace
     * @param {string} replacement - Replacement string
     * @returns {DataFrame} - New DataFrame with replaced strings
     *
     * @example
     * const df = DataFrame.fromCSV('text\nhello world\nhello there\n');
     * const result = df.str.replace('text', 'hello', 'hi');
     * console.log(result.column('text')); // ['hi world', 'hi there']
     */
    replace(columnName, pattern, replacement) {
        this._df._checkNotFreed();

        // Tiger Style: Input validation
        if (!columnName || typeof columnName !== 'string' || columnName.length === 0) {
            throw new RozesError(ErrorCode.InvalidInput, 'replace() requires a non-empty column name (string)');
        }
        if (pattern === null || pattern === undefined) {
            throw new RozesError(ErrorCode.InvalidInput, 'replace() requires a pattern argument (use empty string for empty pattern)');
        }
        if (typeof pattern !== 'string') {
            throw new RozesError(ErrorCode.InvalidInput, 'replace() pattern must be a string');
        }
        if (replacement === null || replacement === undefined) {
            throw new RozesError(ErrorCode.InvalidInput, 'replace() requires a replacement argument (use empty string for empty replacement)');
        }
        if (typeof replacement !== 'string') {
            throw new RozesError(ErrorCode.InvalidInput, 'replace() replacement must be a string');
        }

        const colBytes = new TextEncoder().encode(columnName);
        const patternBytes = new TextEncoder().encode(pattern);
        const replBytes = new TextEncoder().encode(replacement);

        const colPtr = this._wasm.instance.exports.rozes_alloc(colBytes.length);
        if (colPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column name buffer');
        }

        // Handle empty pattern/replacement - allocate dummy byte to satisfy rozes_alloc(size > 0)
        const patternPtr = this._wasm.instance.exports.rozes_alloc(patternBytes.length || 1);
        if (patternPtr === 0) {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate pattern buffer');
        }

        const replPtr = this._wasm.instance.exports.rozes_alloc(replBytes.length || 1);
        if (replPtr === 0) {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
            this._wasm.instance.exports.rozes_free_buffer(patternPtr, patternBytes.length || 1);
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate replacement buffer');
        }

        try {
            const colArray = new Uint8Array(this._wasm.memory.buffer, colPtr, colBytes.length);
            colArray.set(colBytes);

            // Only copy pattern/replacement bytes if not empty
            if (patternBytes.length > 0) {
                const patternArray = new Uint8Array(this._wasm.memory.buffer, patternPtr, patternBytes.length);
                patternArray.set(patternBytes);
            }

            if (replBytes.length > 0) {
                const replArray = new Uint8Array(this._wasm.memory.buffer, replPtr, replBytes.length);
                replArray.set(replBytes);
            }

            const newHandle = this._wasm.instance.exports.rozes_str_replace(
                this._df._handle,
                colPtr,
                colBytes.length,
                patternPtr,
                patternBytes.length,  // Pass actual length (may be 0)
                replPtr,
                replBytes.length  // Pass actual length (may be 0)
            );

            checkResult(newHandle, `Failed to str.replace('${columnName}', '${pattern}', '${replacement}')`);
            return new DataFrame(newHandle, this._wasm, this._df._autoCleanup);
        } finally {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
            this._wasm.instance.exports.rozes_free_buffer(patternPtr, patternBytes.length || 1);
            this._wasm.instance.exports.rozes_free_buffer(replPtr, replBytes.length || 1);
        }
    }

    /**
     * Extract substring from string column
     *
     * @param {string} columnName - Name of string column
     * @param {number} start - Start index (inclusive)
     * @param {number} end - End index (exclusive)
     * @returns {DataFrame} - New DataFrame with extracted substrings
     *
     * @example
     * const df = DataFrame.fromCSV('text\nhello\nworld\n');
     * const result = df.str.slice('text', 0, 3);
     * console.log(result.column('text')); // ['hel', 'wor']
     */
    slice(columnName, start, end) {
        this._df._checkNotFreed();

        // Tiger Style: Input validation
        if (!columnName || typeof columnName !== 'string' || columnName.length === 0) {
            throw new RozesError(ErrorCode.InvalidInput, 'slice() requires a non-empty column name (string)');
        }
        if (typeof start !== 'number' || !Number.isInteger(start) || start < 0) {
            throw new RozesError(ErrorCode.InvalidInput, 'slice() start must be a non-negative integer');
        }
        if (typeof end !== 'number' || !Number.isInteger(end) || end < 0) {
            throw new RozesError(ErrorCode.InvalidInput, 'slice() end must be a non-negative integer');
        }
        if (start > end) {
            throw new RozesError(ErrorCode.InvalidRange, 'slice() invalid range: start must be <= end');
        }

        const colBytes = new TextEncoder().encode(columnName);
        const colPtr = this._wasm.instance.exports.rozes_alloc(colBytes.length);
        if (colPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column name buffer');
        }

        try {
            const colArray = new Uint8Array(this._wasm.memory.buffer, colPtr, colBytes.length);
            colArray.set(colBytes);

            const newHandle = this._wasm.instance.exports.rozes_str_slice(
                this._df._handle,
                colPtr,
                colBytes.length,
                start,
                end
            );

            checkResult(newHandle, `Failed to str.slice('${columnName}', ${start}, ${end})`);
            return new DataFrame(newHandle, this._wasm, this._df._autoCleanup);
        } finally {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
        }
    }

    /**
     * Check if strings start with a prefix
     *
     * @param {string} columnName - Name of string column
     * @param {string} prefix - Prefix to check for
     * @returns {DataFrame} - New DataFrame with boolean column
     *
     * @example
     * const df = DataFrame.fromCSV('text\nhello world\nhello there\ngoodbye\n');
     * const result = df.str.startsWith('text', 'hello');
     * console.log(result.column('text')); // [true, true, false]
     */
    startsWith(columnName, prefix) {
        this._df._checkNotFreed();

        // Tiger Style: Input validation
        if (!columnName || typeof columnName !== 'string' || columnName.length === 0) {
            throw new RozesError(ErrorCode.InvalidInput, 'startsWith() requires a non-empty column name (string)');
        }
        if (prefix === null || prefix === undefined) {
            throw new RozesError(ErrorCode.InvalidInput, 'startsWith() requires a prefix argument (use empty string for empty prefix)');
        }
        if (typeof prefix !== 'string') {
            throw new RozesError(ErrorCode.InvalidInput, 'startsWith() prefix must be a string');
        }

        const colBytes = new TextEncoder().encode(columnName);
        const prefixBytes = new TextEncoder().encode(prefix);

        const colPtr = this._wasm.instance.exports.rozes_alloc(colBytes.length);
        if (colPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column name buffer');
        }

        // Handle empty prefix - allocate dummy byte to satisfy rozes_alloc(size > 0)
        const prefixPtr = this._wasm.instance.exports.rozes_alloc(prefixBytes.length || 1);
        if (prefixPtr === 0) {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate prefix buffer');
        }

        try {
            const colArray = new Uint8Array(this._wasm.memory.buffer, colPtr, colBytes.length);
            colArray.set(colBytes);

            // Only copy prefix bytes if not empty
            if (prefixBytes.length > 0) {
                const prefixArray = new Uint8Array(this._wasm.memory.buffer, prefixPtr, prefixBytes.length);
                prefixArray.set(prefixBytes);
            }

            const newHandle = this._wasm.instance.exports.rozes_str_startsWith(
                this._df._handle,
                colPtr,
                colBytes.length,
                prefixPtr,
                prefixBytes.length  // Pass actual length (may be 0)
            );

            checkResult(newHandle, `Failed to str.startsWith('${columnName}', '${prefix}')`);
            return new DataFrame(newHandle, this._wasm, this._df._autoCleanup);
        } finally {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
            this._wasm.instance.exports.rozes_free_buffer(prefixPtr, prefixBytes.length || 1);
        }
    }

    /**
     * Check if strings end with a suffix
     *
     * @param {string} columnName - Name of string column
     * @param {string} suffix - Suffix to check for
     * @returns {DataFrame} - New DataFrame with boolean column
     *
     * @example
     * const df = DataFrame.fromCSV('text\nhello world\ngoodbye world\nfoo bar\n');
     * const result = df.str.endsWith('text', 'world');
     * console.log(result.column('text')); // [true, true, false]
     */
    endsWith(columnName, suffix) {
        this._df._checkNotFreed();

        // Tiger Style: Input validation
        if (!columnName || typeof columnName !== 'string' || columnName.length === 0) {
            throw new RozesError(ErrorCode.InvalidInput, 'endsWith() requires a non-empty column name (string)');
        }
        if (suffix === null || suffix === undefined) {
            throw new RozesError(ErrorCode.InvalidInput, 'endsWith() requires a suffix argument (use empty string for empty suffix)');
        }
        if (typeof suffix !== 'string') {
            throw new RozesError(ErrorCode.InvalidInput, 'endsWith() suffix must be a string');
        }

        const colBytes = new TextEncoder().encode(columnName);
        const suffixBytes = new TextEncoder().encode(suffix);

        const colPtr = this._wasm.instance.exports.rozes_alloc(colBytes.length);
        if (colPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column name buffer');
        }

        // Handle empty suffix - allocate dummy byte to satisfy rozes_alloc(size > 0)
        const suffixPtr = this._wasm.instance.exports.rozes_alloc(suffixBytes.length || 1);
        if (suffixPtr === 0) {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate suffix buffer');
        }

        try {
            const colArray = new Uint8Array(this._wasm.memory.buffer, colPtr, colBytes.length);
            colArray.set(colBytes);

            // Only copy suffix bytes if not empty
            if (suffixBytes.length > 0) {
                const suffixArray = new Uint8Array(this._wasm.memory.buffer, suffixPtr, suffixBytes.length);
                suffixArray.set(suffixBytes);
            }

            const newHandle = this._wasm.instance.exports.rozes_str_endsWith(
                this._df._handle,
                colPtr,
                colBytes.length,
                suffixPtr,
                suffixBytes.length  // Pass actual length (may be 0)
            );

            checkResult(newHandle, `Failed to str.endsWith('${columnName}', '${suffix}')`);
            return new DataFrame(newHandle, this._wasm, this._df._autoCleanup);
        } finally {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
            this._wasm.instance.exports.rozes_free_buffer(suffixPtr, suffixBytes.length || 1);
        }
    }

    /**
     * Get string lengths
     *
     * @param {string} columnName - Name of string column
     * @returns {DataFrame} - New DataFrame with Int64 column (lengths as BigInts)
     *
     * @example
     * const df = DataFrame.fromCSV('text\na\nab\nabc\n');
     * const result = df.str.len('text');
     * console.log(result.column('text')); // [1n, 2n, 3n]
     */
    len(columnName) {
        this._df._checkNotFreed();

        const colBytes = new TextEncoder().encode(columnName);
        const colPtr = this._wasm.instance.exports.rozes_alloc(colBytes.length);
        if (colPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate column name buffer');
        }

        try {
            const colArray = new Uint8Array(this._wasm.memory.buffer, colPtr, colBytes.length);
            colArray.set(colBytes);

            const newHandle = this._wasm.instance.exports.rozes_str_len(
                this._df._handle,
                colPtr,
                colBytes.length
            );

            checkResult(newHandle, `Failed to str.len('${columnName}')`);
            return new DataFrame(newHandle, this._wasm, this._df._autoCleanup);
        } finally {
            this._wasm.instance.exports.rozes_free_buffer(colPtr, colBytes.length);
        }
    }
}

/**
 * LazyDataFrame - Lazy evaluation wrapper for query optimization
 *
 * Delays execution until `.collect()` is called, allowing the query
 * optimizer to apply transformations like predicate pushdown and
 * projection pushdown for improved performance.
 *
 * @example
 * const df = DataFrame.fromCSV('name,age,score\nAlice,30,95\nBob,25,87\nCharlie,35,91\n');
 * const result = df.lazy()
 *   .select(['name', 'age'])
 *   .limit(2)
 *   .collect();
 */
class LazyDataFrame {
    /**
     * @private
     */
    constructor(handle, wasm, autoCleanup = true) {
        this._handle = handle;
        this._wasm = wasm;
        this._autoCleanup = autoCleanup;
        this._freed = false;

        // Register for automatic cleanup if enabled
        if (autoCleanup) {
            finalizationRegistry.register(this, handle);
        }
    }

    /**
     * Add a select (projection) operation to the query plan
     *
     * Selects specific columns from the DataFrame. Combined with other
     * operations, enables projection pushdown optimization.
     *
     * @param {string[]} columnNames - Array of column names to select
     * @returns {LazyDataFrame} - This LazyDataFrame for chaining
     *
     * @example
     * const result = df.lazy()
     *   .select(['name', 'age'])
     *   .collect();
     */
    select(columnNames) {
        this._checkNotFreed();

        if (!Array.isArray(columnNames) || columnNames.length === 0) {
            throw new Error('select() requires non-empty array of column names');
        }

        const wasm = this._wasm;
        const jsonStr = JSON.stringify(columnNames);
        const jsonBytes = new TextEncoder().encode(jsonStr);
        const jsonPtr = wasm.instance.exports.rozes_alloc(jsonBytes.length);
        if (jsonPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate buffer for column names');
        }

        try {
            const jsonArray = new Uint8Array(wasm.memory.buffer, jsonPtr, jsonBytes.length);
            jsonArray.set(jsonBytes);

            const result = wasm.instance.exports.rozes_lazy_select(
                this._handle,
                jsonPtr,
                jsonBytes.length
            );

            checkResult(result, `Failed to add select operation`);
            return this; // Return this for chaining
        } finally {
            wasm.instance.exports.rozes_free_buffer(jsonPtr, jsonBytes.length);
        }
    }

    /**
     * Add a limit operation to the query plan
     *
     * Limits the number of rows returned. Can be optimized by the query
     * planner to avoid processing unnecessary rows.
     *
     * @param {number} n - Maximum number of rows to return
     * @returns {LazyDataFrame} - This LazyDataFrame for chaining
     *
     * @example
     * const result = df.lazy()
     *   .limit(10)
     *   .collect();
     */
    limit(n) {
        this._checkNotFreed();

        if (!Number.isInteger(n) || n < 0) {
            throw new Error('limit() requires non-negative integer');
        }

        const wasm = this._wasm;
        const result = wasm.instance.exports.rozes_lazy_limit(this._handle, n);
        checkResult(result, `Failed to add limit operation`);

        return this; // Return this for chaining
    }

    /**
     * Execute the query plan and return a DataFrame
     *
     * Applies query optimizations (predicate pushdown, projection pushdown)
     * and executes all operations to produce the final DataFrame.
     *
     * @returns {DataFrame} - Resulting DataFrame after optimization and execution
     *
     * @example
     * const result = df.lazy()
     *   .select(['name', 'age'])
     *   .limit(2)
     *   .collect();
     * console.log(result.shape); // { rows: 2, cols: 2 }
     */
    collect() {
        this._checkNotFreed();

        const wasm = this._wasm;
        const dfHandle = wasm.instance.exports.rozes_collect(this._handle);
        checkResult(dfHandle, 'Failed to collect LazyDataFrame');

        // LazyDataFrame is consumed after collect()
        this.free();

        return new DataFrame(dfHandle, wasm, this._autoCleanup);
    }

    /**
     * Manually free LazyDataFrame memory
     *
     * After calling free(), this LazyDataFrame cannot be used.
     * If autoCleanup is enabled, this happens automatically on garbage collection.
     */
    free() {
        if (this._freed) {
            return;
        }

        // Unregister from finalization registry
        if (this._autoCleanup) {
            finalizationRegistry.unregister(this);
        }

        // Free Wasm memory
        this._wasm.instance.exports.rozes_lazy_free(this._handle);
        this._freed = true;
    }

    /**
     * @private
     */
    _checkNotFreed() {
        if (this._freed) {
            throw new Error('LazyDataFrame has been freed');
        }
    }
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
        // Load Wasm module - handle both paths and ArrayBuffer/Uint8Array
        let buffer;
        if (wasmPath instanceof ArrayBuffer || wasmPath instanceof Uint8Array) {
            // Direct buffer passed (Node.js with fs.readFileSync)
            buffer = wasmPath instanceof Uint8Array ? wasmPath.buffer : wasmPath;
        } else {
            // Path or URL - handle Node.js vs browser
            if (typeof process !== 'undefined' && process.versions && process.versions.node) {
                // Node.js: use fs.readFileSync
                const fs = await import('fs');
                const path = await import('path');
                const { fileURLToPath } = await import('url');

                // Resolve path relative to this module
                const moduleDir = path.dirname(fileURLToPath(import.meta.url));
                const resolvedPath = wasmPath.startsWith('./') || wasmPath.startsWith('../')
                    ? path.join(moduleDir, wasmPath)
                    : wasmPath;

                const wasmBuffer = fs.readFileSync(resolvedPath);
                buffer = wasmBuffer.buffer.slice(wasmBuffer.byteOffset, wasmBuffer.byteOffset + wasmBuffer.byteLength);
            } else {
                // Browser: use fetch
                const response = await fetch(wasmPath);
                buffer = await response.arrayBuffer();
            }
        }

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
export { Rozes, DataFrame, LazyDataFrame, RozesError };

// Also support CommonJS and browser globals
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { Rozes, DataFrame, LazyDataFrame, RozesError };
}

if (typeof window !== 'undefined') {
    window.Rozes = Rozes;
    window.DataFrame = DataFrame;
    window.LazyDataFrame = LazyDataFrame;
    window.RozesError = RozesError;
}
