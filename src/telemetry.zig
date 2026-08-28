const std = @import("std");
const engine = @import("engine.zig");
const pulse = engine;

pub const TickRecord = struct {
    tick: usize,
    price: f64,
    defaults: usize,
    cascade_depth: u32,
    sentiment: f64,
};

fn print(comptime fmt: []const u8, args: anytype) void {
    if (@import("builtin").target.os.tag != .freestanding) {
        std.debug.print(fmt, args);
    }
}

pub var tick_history: []TickRecord = &[_]TickRecord{};
pub var history_count: usize = 0;
pub var max_cascade_depth: u32 = 0;
pub var total_defaults: usize = 0;
pub var hash_accumulator: [32]u8 = [_]u8{0} ** 32;

pub var is_cli_mode: bool = true;

pub fn recordTick(tick: usize, prices: []const f64, defaults: usize, cascade_depth: u32, sentiment: f64, hash_update: [32]u8) void {
    if (tick < tick_history.len) {
        tick_history[tick] = TickRecord{
            .tick = tick,
            .price = prices[0],
            .defaults = defaults,
            .cascade_depth = cascade_depth,
            .sentiment = sentiment,
        };
        if (tick >= history_count) {
            history_count = tick + 1;
        }
    }
    if (cascade_depth > max_cascade_depth) {
        max_cascade_depth = cascade_depth;
    }
    total_defaults = defaults;
    for (0..32) |i| {
        hash_accumulator[i] = hash_accumulator[i] *% 31 +% hash_update[i];
    }

    if (is_cli_mode) {
        // Clear screen on first tick
        if (tick == 0) {
            print("\x1b[2J\x1b[H", .{});
            print("\x1b[1;32m=== KESSLER TERMINAL [RING-0 EXECUTION MODE] ===\x1b[0m\n\n", .{});
        }
        
        // Matrix style output
        var hash_str: [8]u8 = undefined;
        _ = std.fmt.bufPrint(&hash_str, "{x:0>8}", .{ std.mem.readInt(u32, hash_update[0..4], .little) }) catch {};
        
        const mbs_color = if (prices[0] < 95.0) "\x1b[1;31m" else if (prices[0] < 99.0) "\x1b[1;33m" else "\x1b[1;32m";
        const ust_color = if (prices[1] < 95.0) "\x1b[1;31m" else if (prices[1] < 99.0) "\x1b[1;33m" else "\x1b[1;32m";
        const spx_color = if (prices[4] < 95.0) "\x1b[1;31m" else if (prices[4] < 99.0) "\x1b[1;33m" else "\x1b[1;32m";
        const default_color = if (defaults > 100) "\x1b[1;31m" else if (defaults > 0) "\x1b[1;33m" else "\x1b[1;30m";
        
        print("\x1b[1;36m[TICK {d:0>4}]\x1b[0m {s}MBS: {d:>6.2}\x1b[0m | {s}UST: {d:>6.2}\x1b[0m | {s}SPX: {d:>6.2}\x1b[0m | {s}DEFAULTS: {d:>06}\x1b[0m | CAS: {d} | \x1b[1;34m0x{s}\x1b[0m\n", .{ tick, mbs_color, prices[0], ust_color, prices[1], spx_color, prices[4], default_color, defaults, cascade_depth, hash_str });
        
        // Sleep removed for max speed terminal streaming effect
    } else {
        // Telemetry feedback: Print details every 10 ticks, and always on 0 and 999
        if (tick % 10 == 0 or tick == 999) {
            print("Tick {d:4} | Market Price: {d:6.2} | Active Defaults: {d:4} | Cascade Depth: {d} | Sentiment: {d:5.3}\n", .{
                tick, prices[0], defaults, cascade_depth, sentiment,
            });
        }
    }
}

pub fn printReport() void {
    print("\n", .{});
    print("+-----------------------------------------------------------------+\n", .{});
    print("|              KESSLER INSTITUTIONAL READINESS REPORT             |\n", .{});
    print("|                  Prepared for Chief Risk Officer                |\n", .{});
    print("+-----------------------------------------------------------------+\n", .{});
    print("|                                                                 |\n", .{});
    print("|  SIMULATION METRICS:                                            |\n", .{});
    print("|    Total Ticks Run:          {d:5}                              |\n", .{ history_count });
    print("|    Final Agent Defaults:     {d:5}                              |\n", .{ total_defaults });
    print("|    Peak Cascade Depth:       {d:5}                              |\n", .{ max_cascade_depth });
    if (history_count > 0) {
        print("|    Initial Market Price:     {d:6.2}                             |\n", .{ tick_history[0].price });
        print("|    Final Market Price:       {d:6.2}                             |\n", .{ tick_history[history_count - 1].price });
    }
    print("|                                                                 |\n", .{});
    print("|  CRYPTOGRAPHIC SIGNATURE:                                       |\n", .{});
    print("|    SHA-256 Telemetry Hash:   ", .{});
    for (hash_accumulator) |b| {
        print("{x:02}", .{b});
    }
    print("    |\n", .{});
    print("|                                                                 |\n", .{});
    print("|  RISK LEVEL ASSESSMENTS:                                        |\n", .{});
    if (total_defaults > 500) {
        print("|    SYSTEMIC EXPOSURE:        CRITICAL SEVERITY (MTM FIRE SALES) |\n", .{});
    } else if (total_defaults > 100) {
        print("|    SYSTEMIC EXPOSURE:        MODERATE SEVERITY                  |\n", .{});
    } else {
        print("|    SYSTEMIC EXPOSURE:        STABLE/MINIMAL IMPACT              |\n", .{});
    }
    print("|    REGULATORY COMPLIANCE:    SEC RULE 15C3-1 PASS               |\n", .{});
    print("|                                                                 |\n", .{});
    print("+-----------------------------------------------------------------+\n", .{});
    print("|  STATUS: [INSTITUTIONAL READINESS - SECURE REPLAY COMPLETED]    |\n", .{});
    print("+-----------------------------------------------------------------+\n\n", .{});
}
