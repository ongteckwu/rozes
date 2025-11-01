//! Window operations for time-series analysis
//!
//! This module provides rolling window, expanding window, and shift operations
//! for Series data. These are essential for time-series analysis like moving
//! averages, cumulative sums, and lag features.
//!
//! Tiger Style:
//! - 2+ assertions per function
//! - Bounded loops with explicit MAX constants
//! - Functions ≤70 lines
//! - Explicit types (u32, not usize)

const std = @import("std");
const Allocator = std.mem.Allocator;
const Series = @import("series.zig").Series;
const ValueType = @import("types.zig").ValueType;

/// Maximum window size for rolling operations
pub const MAX_WINDOW_SIZE: u32 = 100_000;

/// Window type for aggregations
pub const WindowType = enum {
    Rolling, // Fixed window size
    Expanding, // Growing window (cumulative)
};

/// Rolling window for fixed-size aggregations
pub const RollingWindow = struct {
    series: *const Series,
    window_size: u32,

    /// Initialize a rolling window
    pub fn init(series: *const Series, window_size: u32) !RollingWindow {
        // Tiger Style: Assertions
        std.debug.assert(window_size > 0);
        std.debug.assert(window_size <= MAX_WINDOW_SIZE);

        if (window_size == 0) return error.InvalidWindowSize;
        if (window_size > MAX_WINDOW_SIZE) return error.WindowSizeTooLarge;

        return RollingWindow{
            .series = series,
            .window_size = window_size,
        };
    }

    /// Compute rolling sum
    ///
    /// **Complexity**:
    /// - Time: O(n × w) where n = series length, w = window size
    /// - Space: O(n) for result array
    /// - Memory: Allocates new Series (no in-place modification)
    ///
    /// **Performance Notes**:
    /// - Uses naive O(n×w) algorithm for clarity
    /// - Optimization opportunity: O(n) with sliding window sum (defer to 0.5.0)
    pub fn sum(self: *const RollingWindow, allocator: Allocator) !Series {
        // Tiger Style: Assertions
        std.debug.assert(self.window_size > 0);
        std.debug.assert(self.series.length > 0);

        const len = self.series.length;
        const result_data = try allocator.alloc(f64, len);

        switch (self.series.valueType) {
            .Int64 => {
                const data = self.series.data.Int64;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const start = if (i + 1 < self.window_size) 0 else i + 1 - self.window_size;
                    var window_sum: f64 = 0.0;
                    var j: u32 = start;
                    while (j <= i) : (j += 1) {
                        window_sum += @as(f64, @floatFromInt(data[j]));
                    }
                    result_data[i] = window_sum;
                }
            },
            .Float64 => {
                const data = self.series.data.Float64;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const start = if (i + 1 < self.window_size) 0 else i + 1 - self.window_size;
                    var window_sum: f64 = 0.0;
                    var j: u32 = start;
                    while (j <= i) : (j += 1) {
                        window_sum += data[j];
                    }
                    result_data[i] = window_sum;
                }
            },
            else => {
                allocator.free(result_data);
                return error.UnsupportedType;
            },
        }

        return Series{
            .name = self.series.name,
            .valueType = .Float64,
            .data = .{ .Float64 = result_data },
            .length = len,
        };
    }

    /// Compute rolling mean
    ///
    /// **Complexity**:
    /// - Time: O(n × w) where n = series length, w = window size
    /// - Space: O(n) for result array
    /// - Memory: Allocates 2 new Series (sum + result)
    ///
    /// **Performance Notes**:
    /// - Reuses rolling sum computation (1 pass)
    /// - Optimization opportunity: Combine sum+mean in single pass (defer to 0.5.0)
    pub fn mean(self: *const RollingWindow, allocator: Allocator) !Series {
        // Tiger Style: Assertions
        std.debug.assert(self.window_size > 0);
        std.debug.assert(self.series.length > 0);

        const sum_series = try self.sum(allocator);
        const len = sum_series.length;
        const sum_data = sum_series.data.Float64;
        const result_data = try allocator.alloc(f64, len);

        var i: u32 = 0;
        while (i < len) : (i += 1) {
            const window_len = @min(i + 1, self.window_size);
            result_data[i] = sum_data[i] / @as(f64, @floatFromInt(window_len));
        }

        allocator.free(sum_data);

        return Series{
            .name = self.series.name,
            .valueType = .Float64,
            .data = .{ .Float64 = result_data },
            .length = len,
        };
    }

    /// Compute rolling minimum
    pub fn min(self: *const RollingWindow, allocator: Allocator) !Series {
        // Tiger Style: Assertions
        std.debug.assert(self.window_size > 0);
        std.debug.assert(self.series.length > 0);

        const len = self.series.length;
        const result_data = try allocator.alloc(f64, len);

        switch (self.series.valueType) {
            .Int64 => {
                const data = self.series.data.Int64;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const start = if (i + 1 < self.window_size) 0 else i + 1 - self.window_size;
                    var window_min: f64 = @as(f64, @floatFromInt(data[start]));
                    var j: u32 = start + 1;
                    while (j <= i) : (j += 1) {
                        const val = @as(f64, @floatFromInt(data[j]));
                        if (val < window_min) window_min = val;
                    }
                    result_data[i] = window_min;
                }
            },
            .Float64 => {
                const data = self.series.data.Float64;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const start = if (i + 1 < self.window_size) 0 else i + 1 - self.window_size;
                    var window_min = data[start];
                    var j: u32 = start + 1;
                    while (j <= i) : (j += 1) {
                        if (data[j] < window_min) window_min = data[j];
                    }
                    result_data[i] = window_min;
                }
            },
            else => {
                allocator.free(result_data);
                return error.UnsupportedType;
            },
        }

        return Series{
            .name = self.series.name,
            .valueType = .Float64,
            .data = .{ .Float64 = result_data },
            .length = len,
        };
    }

    /// Compute rolling maximum
    pub fn max(self: *const RollingWindow, allocator: Allocator) !Series {
        // Tiger Style: Assertions
        std.debug.assert(self.window_size > 0);
        std.debug.assert(self.series.length > 0);

        const len = self.series.length;
        const result_data = try allocator.alloc(f64, len);

        switch (self.series.valueType) {
            .Int64 => {
                const data = self.series.data.Int64;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const start = if (i + 1 < self.window_size) 0 else i + 1 - self.window_size;
                    var window_max: f64 = @as(f64, @floatFromInt(data[start]));
                    var j: u32 = start + 1;
                    while (j <= i) : (j += 1) {
                        const val = @as(f64, @floatFromInt(data[j]));
                        if (val > window_max) window_max = val;
                    }
                    result_data[i] = window_max;
                }
            },
            .Float64 => {
                const data = self.series.data.Float64;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const start = if (i + 1 < self.window_size) 0 else i + 1 - self.window_size;
                    var window_max = data[start];
                    var j: u32 = start + 1;
                    while (j <= i) : (j += 1) {
                        if (data[j] > window_max) window_max = data[j];
                    }
                    result_data[i] = window_max;
                }
            },
            else => {
                allocator.free(result_data);
                return error.UnsupportedType;
            },
        }

        return Series{
            .name = self.series.name,
            .valueType = .Float64,
            .data = .{ .Float64 = result_data },
            .length = len,
        };
    }

    /// Compute rolling standard deviation
    pub fn stddev(self: *const RollingWindow, allocator: Allocator) !Series {
        // Tiger Style: Assertions
        std.debug.assert(self.window_size > 0);
        std.debug.assert(self.series.length > 0);

        const len = self.series.length;
        const result_data = try allocator.alloc(f64, len);

        switch (self.series.valueType) {
            .Int64 => {
                const data = self.series.data.Int64;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const start = if (i + 1 < self.window_size) 0 else i + 1 - self.window_size;
                    const window_len = i - start + 1;

                    // Compute mean
                    var window_sum: f64 = 0.0;
                    var j: u32 = start;
                    while (j <= i) : (j += 1) {
                        window_sum += @as(f64, @floatFromInt(data[j]));
                    }
                    const window_mean = window_sum / @as(f64, @floatFromInt(window_len));

                    // Compute variance
                    var variance: f64 = 0.0;
                    j = start;
                    while (j <= i) : (j += 1) {
                        const val = @as(f64, @floatFromInt(data[j]));
                        const delta = val - window_mean;
                        variance += delta * delta;
                    }
                    variance /= @as(f64, @floatFromInt(window_len));

                    result_data[i] = @sqrt(variance);
                }
            },
            .Float64 => {
                const data = self.series.data.Float64;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const start = if (i + 1 < self.window_size) 0 else i + 1 - self.window_size;
                    const window_len = i - start + 1;

                    // Compute mean
                    var window_sum: f64 = 0.0;
                    var j: u32 = start;
                    while (j <= i) : (j += 1) {
                        window_sum += data[j];
                    }
                    const window_mean = window_sum / @as(f64, @floatFromInt(window_len));

                    // Compute variance
                    var variance: f64 = 0.0;
                    j = start;
                    while (j <= i) : (j += 1) {
                        const delta = data[j] - window_mean;
                        variance += delta * delta;
                    }
                    variance /= @as(f64, @floatFromInt(window_len));

                    result_data[i] = @sqrt(variance);
                }
            },
            else => {
                allocator.free(result_data);
                return error.UnsupportedType;
            },
        }

        return Series{
            .name = self.series.name,
            .valueType = .Float64,
            .data = .{ .Float64 = result_data },
            .length = len,
        };
    }
};

/// Expanding window for cumulative aggregations
pub const ExpandingWindow = struct {
    series: *const Series,

    /// Initialize an expanding window
    pub fn init(series: *const Series) ExpandingWindow {
        // Tiger Style: Assertions
        std.debug.assert(series.length > 0);

        return ExpandingWindow{
            .series = series,
        };
    }

    /// Compute cumulative sum
    pub fn sum(self: *const ExpandingWindow, allocator: Allocator) !Series {
        // Tiger Style: Assertions
        std.debug.assert(self.series.length > 0);

        const len = self.series.length;
        const result_data = try allocator.alloc(f64, len);

        switch (self.series.valueType) {
            .Int64 => {
                const data = self.series.data.Int64;
                var cumsum: f64 = 0.0;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    cumsum += @as(f64, @floatFromInt(data[i]));
                    result_data[i] = cumsum;
                }
            },
            .Float64 => {
                const data = self.series.data.Float64;
                var cumsum: f64 = 0.0;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    cumsum += data[i];
                    result_data[i] = cumsum;
                }
            },
            else => {
                allocator.free(result_data);
                return error.UnsupportedType;
            },
        }

        return Series{
            .name = self.series.name,
            .valueType = .Float64,
            .data = .{ .Float64 = result_data },
            .length = len,
        };
    }

    /// Compute cumulative mean
    pub fn mean(self: *const ExpandingWindow, allocator: Allocator) !Series {
        // Tiger Style: Assertions
        std.debug.assert(self.series.length > 0);

        const sum_series = try self.sum(allocator);
        const len = sum_series.length;
        const sum_data = sum_series.data.Float64;
        const result_data = try allocator.alloc(f64, len);

        var i: u32 = 0;
        while (i < len) : (i += 1) {
            result_data[i] = sum_data[i] / @as(f64, @floatFromInt(i + 1));
        }

        allocator.free(sum_data);

        return Series{
            .name = self.series.name,
            .valueType = .Float64,
            .data = .{ .Float64 = result_data },
            .length = len,
        };
    }
};

/// Shift series values by a given number of periods
pub fn shift(series: *const Series, allocator: Allocator, periods: i32) !Series {
    // Tiger Style: Assertions
    std.debug.assert(series.length > 0);
    std.debug.assert(@abs(periods) < 1_000_000); // Reasonable limit

    const len = series.length;
    const abs_periods = @abs(periods);

    if (abs_periods >= len) {
        // All values would be shifted out, return all NaN
        const result_data = try allocator.alloc(f64, len);
        @memset(result_data, std.math.nan(f64));
        return Series{
            .name = series.name,
            .valueType = .Float64,
            .data = .{ .Float64 = result_data },
            .length = len,
        };
    }

    const result_data = try allocator.alloc(f64, len);

    if (periods > 0) {
        // Shift forward: fill first `periods` with NaN
        @memset(result_data[0..@intCast(periods)], std.math.nan(f64));
        switch (series.valueType) {
            .Int64 => {
                const data = series.data.Int64;
                var i: u32 = @intCast(periods);
                while (i < len) : (i += 1) {
                    result_data[i] = @as(f64, @floatFromInt(data[i - @as(u32, @intCast(periods))]));
                }
            },
            .Float64 => {
                const data = series.data.Float64;
                @memcpy(result_data[@intCast(periods)..], data[0 .. len - @as(u32, @intCast(periods))]);
            },
            else => {
                allocator.free(result_data);
                return error.UnsupportedType;
            },
        }
    } else {
        // Shift backward: fill last `periods` with NaN
        const start_idx = len - @as(u32, @intCast(abs_periods));
        @memset(result_data[start_idx..], std.math.nan(f64));
        switch (series.valueType) {
            .Int64 => {
                const data = series.data.Int64;
                var i: u32 = 0;
                while (i < start_idx) : (i += 1) {
                    result_data[i] = @as(f64, @floatFromInt(data[i + @as(u32, @intCast(abs_periods))]));
                }
            },
            .Float64 => {
                const data = series.data.Float64;
                @memcpy(result_data[0..start_idx], data[@intCast(abs_periods)..]);
            },
            else => {
                allocator.free(result_data);
                return error.UnsupportedType;
            },
        }
    }

    return Series{
        .name = series.name,
        .valueType = .Float64,
        .data = .{ .Float64 = result_data },
        .length = len,
    };
}

/// Compute first discrete difference
pub fn diff(series: *const Series, allocator: Allocator, periods: u32) !Series {
    // Tiger Style: Assertions
    std.debug.assert(series.length > 0);
    std.debug.assert(periods > 0);
    std.debug.assert(periods < 1000);

    const len = series.length;
    const result_data = try allocator.alloc(f64, len);

    // Fill first `periods` with NaN
    @memset(result_data[0..periods], std.math.nan(f64));

    switch (series.valueType) {
        .Int64 => {
            const data = series.data.Int64;
            var i: u32 = periods;
            while (i < len) : (i += 1) {
                const curr = @as(f64, @floatFromInt(data[i]));
                const prev = @as(f64, @floatFromInt(data[i - periods]));
                result_data[i] = curr - prev;
            }
        },
        .Float64 => {
            const data = series.data.Float64;
            var i: u32 = periods;
            while (i < len) : (i += 1) {
                result_data[i] = data[i] - data[i - periods];
            }
        },
        else => {
            allocator.free(result_data);
            return error.UnsupportedType;
        },
    }

    return Series{
        .name = series.name,
        .valueType = .Float64,
        .data = .{ .Float64 = result_data },
        .length = len,
    };
}

/// Compute percentage change
pub fn pctChange(series: *const Series, allocator: Allocator, periods: u32) !Series {
    // Tiger Style: Assertions
    std.debug.assert(series.length > 0);
    std.debug.assert(periods > 0);
    std.debug.assert(periods < 1000);

    const len = series.length;
    const result_data = try allocator.alloc(f64, len);

    // Fill first `periods` with NaN
    @memset(result_data[0..periods], std.math.nan(f64));

    switch (series.valueType) {
        .Int64 => {
            const data = series.data.Int64;
            var i: u32 = periods;
            while (i < len) : (i += 1) {
                const curr = @as(f64, @floatFromInt(data[i]));
                const prev = @as(f64, @floatFromInt(data[i - periods]));
                if (prev == 0.0) {
                    result_data[i] = std.math.nan(f64);
                } else {
                    result_data[i] = (curr - prev) / prev;
                }
            }
        },
        .Float64 => {
            const data = series.data.Float64;
            var i: u32 = periods;
            while (i < len) : (i += 1) {
                const prev = data[i - periods];
                if (prev == 0.0) {
                    result_data[i] = std.math.nan(f64);
                } else {
                    result_data[i] = (data[i] - prev) / prev;
                }
            }
        },
        else => {
            allocator.free(result_data);
            return error.UnsupportedType;
        },
    }

    return Series{
        .name = series.name,
        .valueType = .Float64,
        .data = .{ .Float64 = result_data },
        .length = len,
    };
}
