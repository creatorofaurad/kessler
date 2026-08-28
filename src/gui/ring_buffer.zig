const std = @import("std");

pub const TickSnapshot = struct {
    tick_number: u64,
    market_prices: [200]f64,
    price_write_idx: u8,
    base_depths: [36]f64,
    volatilities: [36]f64,
    asset_frozen: [36]bool,
    cascade_depth: u32,
    total_defaults: u64,
    theta_avg: f64,
    theta_distribution: [4]f64, // bullish, neutral, bearish, panicked
    hash_first8: [8]u8,
    engine_running: bool,
};

pub const RingBuffer = struct {
    pub const CAPACITY = 256;
    slots: [CAPACITY]TickSnapshot,
    write_idx: std.atomic.Value(u64),
    read_idx: std.atomic.Value(u64),
    
    pub fn init() RingBuffer {
        return RingBuffer{
            .slots = [_]TickSnapshot{std.mem.zeroes(TickSnapshot)} ** CAPACITY,
            .write_idx = std.atomic.Value(u64).init(0),
            .read_idx = std.atomic.Value(u64).init(0),
        };
    }
};
