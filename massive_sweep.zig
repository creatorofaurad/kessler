const std = @import("std");
const k2 = @import("k2_backtest_engine.zig");
const td3 = @import("src/td3_native.zig");

const SweepResult = struct {
    cfg: k2.BacktestConfig,
    pnl: f64,
    trades: usize,
};

const Context = struct {
    ticks: []const k2.Tick,
    results: []SweepResult,
    configs: []const k2.BacktestConfig,
    shared_agent: *td3.TD3Agent,
};

fn runWorker(ctx: *Context, start_idx: usize, end_idx: usize) void {
    // Each thread gets its own allocator for the environment's internal lists
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    for (start_idx..end_idx) |i| {
        const cfg = ctx.configs[i];
        
        var env = k2.BacktestEnvironment.init(allocator, cfg, ctx.shared_agent);
        
        // Suppress print statements in the inner loop by running silently
        // We catch errors but ignore them in the sweep
        env.run(ctx.ticks) catch {};

        ctx.results[i] = .{
            .cfg = cfg,
            .pnl = env.equity - cfg.starting_balance,
            .trades = env.trades_count,
        };
        
        // Reset arena after each config to avoid infinite RAM usage
        _ = arena.reset(.retain_capacity);
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("[SWEEP] Initializing Zig Massive Grid Search (TradFi Engine)...\n", .{});

    // 1. Generate Configs - 5.85 Million Permutations
    const total_perms = 5850000; // 50 * 39 * 150 * 20
    var configs = try allocator.alloc(k2.BacktestConfig, total_perms);
    var configs_idx: usize = 0;

    var atr: usize = 2;
    while (atr <= 100) : (atr += 2) {
        var stop: f64 = 0.5;
        while (stop <= 10.0) : (stop += 0.25) {
            var tp: f64 = 0.1;
            while (tp <= 15.0) : (tp += 0.1) {
                var thresh: f32 = 0.05;
                while (thresh <= 1.0) : (thresh += 0.05) {
                    var base_cfg = k2.BacktestConfig{};
                    base_cfg.atr_period_bars = atr;
                    base_cfg.stop_mult = stop;
                    base_cfg.tp_mult = tp;
                    base_cfg.action_long_thresh = thresh;
                    base_cfg.action_short_thresh = -thresh;
                    configs[configs_idx] = base_cfg;
                    configs_idx += 1;
                }
            }
        }
    }

    const results = try allocator.alloc(SweepResult, configs_idx);
    defer allocator.free(results);

    std.debug.print("[SWEEP] Generated {d} strategy permutations.\n", .{configs_idx});

    // 2. Parse CSV into RAM
    std.debug.print("[SWEEP] Loading NAS100 binary ticks into RAM (Runtime)...\n", .{});
    
    const c_path = "data/nas100_5m_yahoo.bin";
    const file = std.c.fopen(c_path, "rb") orelse {
        std.debug.print("Fatal error opening bin file.\n", .{});
        return error.FileNotFound;
    };
    defer _ = std.c.fclose(file);

    var n_bars: u64 = 0;
    _ = std.c.fread(@as([*]u8, @ptrCast(&n_bars)), 8, 1, file);
    const bar_data = try allocator.alloc(f32, n_bars * 5);
    defer allocator.free(bar_data);
    _ = std.c.fread(@as([*]u8, @ptrCast(bar_data.ptr)), 4, n_bars * 5, file);

    var ticks = try allocator.alloc(k2.Tick, n_bars * 4);
    defer allocator.free(ticks);
    var ticks_count: usize = 0;

    var current_ts: f64 = 0.0;
    for (0..n_bars) |i| {
        const o = bar_data[i * 5 + 0];
        const h = bar_data[i * 5 + 1];
        const l = bar_data[i * 5 + 2];
        const c = bar_data[i * 5 + 3];
        const v = bar_data[i * 5 + 4] / 4.0;
        
        const is_bull = c >= o;
        ticks[ticks_count + 0] = .{ .timestamp = current_ts + 0.0, .bid = o, .ask = o + 0.5, .volume = v };
        ticks[ticks_count + 1] = .{ .timestamp = current_ts + 75.0, .bid = if (is_bull) l else h, .ask = (if (is_bull) l else h) + 0.5, .volume = v };
        ticks[ticks_count + 2] = .{ .timestamp = current_ts + 150.0, .bid = if (is_bull) h else l, .ask = (if (is_bull) h else l) + 0.5, .volume = v };
        ticks[ticks_count + 3] = .{ .timestamp = current_ts + 225.0, .bid = c, .ask = c + 0.5, .volume = v };
        ticks_count += 4;
        current_ts += 300.0;
    }
    
    std.debug.print("[SWEEP] Loaded {d} ticks. Engaging Engine.\n", .{ticks_count});

    // 3. Threading (Leaving 1 core free for Brave)
    const total_cores = try std.Thread.getCpuCount();
    const num_threads = if (total_cores > 1) total_cores - 1 else 1;
    std.debug.print("[SWEEP] Detected {d} CPU cores. Using {d} threads (1 core reserved for Brave).\n", .{total_cores, num_threads});

    var shared_agent = td3.TD3Agent.load(allocator, "C:\\Users\\srija\\Projects\\kessler\\kessler_v2_weights.bin") catch {
        std.debug.print("Fatal error: Could not load TD3 neural weights.\n", .{});
        return error.WeightsNotFound;
    };

    var ctx = Context{
        .ticks = ticks[0..ticks_count],
        .results = results,
        .configs = configs[0..configs_idx],
        .shared_agent = &shared_agent,
    };

    var threads = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(threads);

    const chunk_size = configs_idx / num_threads;
    var current_idx: usize = 0;

    for (0..num_threads) |i| {
        const end_idx = if (i == num_threads - 1) configs_idx else current_idx + chunk_size;
        threads[i] = try std.Thread.spawn(.{}, runWorker, .{ &ctx, current_idx, end_idx });
        current_idx = end_idx;
    }

    for (threads) |thread| {
        thread.join();
    }

    // 4. Find Best Result
    var best_pnl: f64 = -9999999.0;
    var best_idx: usize = 0;
    for (results, 0..) |res, i| {
        if (res.pnl > best_pnl and res.trades > 50) {
            best_pnl = res.pnl;
            best_idx = i;
        }
    }

    std.debug.print("\n=== GOD TIER TRADFI CONFIGURATION ===\n", .{});
    std.debug.print("PnL: ${d:.2} | Trades: {d}\n", .{results[best_idx].pnl, results[best_idx].trades});
    std.debug.print("ATR Period: {d} | Stop: {d} | TP: {d} | Thresh: {d}\n", .{
        results[best_idx].cfg.atr_period_bars,
        results[best_idx].cfg.stop_mult,
        results[best_idx].cfg.tp_mult,
        results[best_idx].cfg.action_long_thresh,
    });
    std.debug.print("=====================================\n", .{});
}
