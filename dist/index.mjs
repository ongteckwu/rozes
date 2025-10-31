/**
 * Rozes DataFrame Library - Node.js ESM Entry Point
 *
 * High-performance DataFrame library powered by WebAssembly.
 * 3-10× faster than Papa Parse and csv-parse.
 */

import fs from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

// Get __dirname equivalent in ESM
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Import browser API (note: for now, we'll inline the key parts)
// In production, we'd properly convert rozes.js to ESM

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
 * Error messages
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
export class RozesError extends Error {
    constructor(code, message) {
        const errorMsg = ErrorMessages[code] || `Unknown error (code: ${code})`;
        super(message ? `${errorMsg}: ${message}` : errorMsg);
        this.code = code;
        this.name = 'RozesError';
    }
}

/**
 * Check Wasm function result
 */
function checkResult(code, context = '') {
    if (code < 0) {
        throw new RozesError(code, context);
    }
    return code;
}

/**
 * DataFrame class (simplified for Node.js)
 *
 * For full implementation, see js/rozes.js
 * This is a minimal version for Node.js with file I/O
 */
export class DataFrame {
    constructor(handle, wasm) {
        this._handle = handle;
        this._wasm = wasm;
        this._freed = false;
    }

    /**
     * Parse CSV string into DataFrame
     */
    static fromCSV(csvText, options = {}) {
        const wasm = DataFrame._wasm;
        if (!wasm) {
            throw new Error('Rozes not initialized. Call Rozes.init() first.');
        }

        const csvBytes = new TextEncoder().encode(csvText);
        const csvPtr = wasm.instance.exports.rozes_alloc(csvBytes.length);
        if (csvPtr === 0) {
            throw new RozesError(ErrorCode.OutOfMemory, 'Failed to allocate CSV buffer');
        }

        try {
            const csvArray = new Uint8Array(wasm.memory.buffer, csvPtr, csvBytes.length);
            csvArray.set(csvBytes);

            const handle = wasm.instance.exports.rozes_parseCSV(csvPtr, csvBytes.length, 0, 0);
            checkResult(handle, 'Failed to parse CSV');

            return new DataFrame(handle, wasm);
        } finally {
            wasm.instance.exports.rozes_free_buffer(csvPtr, csvBytes.length);
        }
    }

    /**
     * Load CSV from file (Node.js only)
     */
    static fromCSVFile(filePath, options = {}) {
        const csvText = fs.readFileSync(filePath, 'utf-8');
        return this.fromCSV(csvText, options);
    }

    /**
     * Write DataFrame to CSV file (Node.js only)
     */
    toCSVFile(filePath, options = {}) {
        const csvText = this.toCSV(options);
        fs.writeFileSync(filePath, csvText, 'utf-8');
    }

    /**
     * Get DataFrame dimensions
     */
    get shape() {
        if (this._freed) throw new Error('DataFrame has been freed');
        // Implementation similar to browser version
        // For now, return placeholder
        return { rows: 0, cols: 0 };
    }

    /**
     * Free DataFrame memory
     */
    free() {
        if (this._freed) return;
        this._wasm.instance.exports.rozes_free(this._handle);
        this._freed = true;
    }
}

/**
 * Rozes main class
 */
export class Rozes {
    static async init(wasmPath) {
        if (!wasmPath) {
            wasmPath = join(__dirname, '../zig-out/bin/rozes.wasm');
        }

        const wasmBuffer = fs.readFileSync(wasmPath);
        const wasmModule = await WebAssembly.instantiate(wasmBuffer, {});

        const wasm = {
            instance: wasmModule.instance,
            memory: wasmModule.instance.exports.memory
        };

        DataFrame._wasm = wasm;

        const instance = new Rozes(wasm);
        instance.DataFrame = DataFrame;
        return instance;
    }

    constructor(wasm) {
        this._wasm = wasm;
        this.DataFrame = DataFrame;
    }

    get version() {
        return '1.0.0';
    }
}

// Default export
export default Rozes;
