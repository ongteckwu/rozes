/**
 * Rozes DataFrame Library - Node.js CommonJS Entry Point
 *
 * High-performance DataFrame library powered by WebAssembly.
 * 3-10× faster than Papa Parse and csv-parse.
 */

const fs = require('fs');
const path = require('path');

// Load the browser API (already supports CommonJS)
const browserAPI = require('../js/rozes.js');
const { Rozes, DataFrame: BrowserDataFrame, RozesError } = browserAPI;

/**
 * Extended DataFrame class with Node.js file I/O utilities
 */
class DataFrameNode extends BrowserDataFrame {
  /**
   * Parse CSV string into DataFrame (overridden to return DataFrameNode)
   *
   * @param {string} csvText - CSV data as string
   * @param {Object} options - Parsing options
   * @returns {DataFrameNode}
   */
  static fromCSV(csvText, options = {}) {
    // Call parent's fromCSV to get the handle
    const tempDf = BrowserDataFrame.fromCSV.call(this, csvText, options);

    // Create a DataFrameNode instance with the same handle and wasm
    const nodeDf = Object.create(DataFrameNode.prototype);
    nodeDf._handle = tempDf._handle;
    nodeDf._wasm = tempDf._wasm;
    nodeDf._freed = tempDf._freed;
    nodeDf._rows = tempDf._rows;
    nodeDf._cols = tempDf._cols;
    nodeDf._columnNames = tempDf._columnNames;

    return nodeDf;
  }

  /**
   * Load CSV from file
   *
   * @param {string} filePath - Path to CSV file
   * @param {Object} options - Parsing options (same as fromCSV)
   * @returns {DataFrameNode}
   *
   * @example
   * const df = DataFrame.fromCSVFile('data.csv');
   * console.log(df.shape); // { rows: 1000, cols: 5 }
   */
  static fromCSVFile(filePath, options = {}) {
    const csvText = fs.readFileSync(filePath, 'utf-8');
    return this.fromCSV(csvText, options);
  }

  // NOTE: toCSVFile() will be added in 1.1.0 when CSV export is implemented in WASM
  // For now, you can access data via column() and manually write CSV if needed
}

/**
 * Extended Rozes class for Node.js
 */
class RozesNode extends Rozes {
  /**
   * Initialize Rozes with WASM module
   *
   * In Node.js, this loads the WASM file synchronously from the file system.
   *
   * @param {string} wasmPath - Optional path to WASM file (defaults to bundled)
   * @returns {Promise<RozesNode>}
   *
   * @example
   * const rozes = await Rozes.init();
   * const df = rozes.DataFrame.fromCSV("age,score\n30,95.5\n");
   */
  static async init(wasmPath) {
    // Default to bundled WASM file
    if (!wasmPath) {
      wasmPath = path.join(__dirname, '../zig-out/bin/rozes.wasm');
    }

    // Load WASM file synchronously (Node.js supports this)
    const wasmBuffer = fs.readFileSync(wasmPath);

    // Provide minimal WASI imports (stub implementation)
    // Rozes doesn't use file I/O in WASM, so these are no-ops
    const wasiImports = {
      wasi_snapshot_preview1: {
        // File descriptor operations
        fd_close: () => 0,
        fd_write: () => 0,
        fd_read: () => 0,
        fd_seek: () => 0,
        fd_fdstat_get: () => 0,
        fd_fdstat_set_flags: () => 0,
        fd_filestat_get: () => 0,
        fd_filestat_set_size: () => 0,
        fd_filestat_set_times: () => 0,
        fd_prestat_get: () => 0,
        fd_prestat_dir_name: () => 0,
        fd_pread: () => 0,
        fd_pwrite: () => 0,
        fd_readdir: () => 0,
        fd_renumber: () => 0,
        fd_sync: () => 0,
        fd_tell: () => 0,
        fd_advise: () => 0,
        fd_allocate: () => 0,

        // Path operations
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

        // Environment
        environ_sizes_get: () => 0,
        environ_get: () => 0,
        args_sizes_get: () => 0,
        args_get: () => 0,

        // Process
        proc_exit: (code) => process.exit(code),
        proc_raise: () => 0,
        sched_yield: () => 0,

        // Random
        random_get: (buf, len) => {
          const bytes = new Uint8Array(len);
          require('crypto').randomFillSync(bytes);
          return 0;
        },

        // Clock
        clock_res_get: () => 0,
        clock_time_get: () => 0,

        // Poll
        poll_oneoff: () => 0,

        // Socket (Node.js compat)
        sock_recv: () => 0,
        sock_send: () => 0,
        sock_shutdown: () => 0
      }
    };

    const wasmModule = await WebAssembly.instantiate(wasmBuffer, wasiImports);

    const wasm = {
      instance: wasmModule.instance,
      memory: wasmModule.instance.exports.memory
    };

    // Set static reference for DataFrame on both child and parent class
    BrowserDataFrame._wasm = wasm;
    DataFrameNode._wasm = wasm;

    const instance = new RozesNode(wasm);
    instance.DataFrame = DataFrameNode;
    return instance;
  }

  /**
   * Get library version
   */
  get version() {
    return '1.0.0';
  }
}

// Export for CommonJS
module.exports = {
  Rozes: RozesNode,
  DataFrame: DataFrameNode,
  RozesError,

  // Convenience: default export
  default: RozesNode
};
