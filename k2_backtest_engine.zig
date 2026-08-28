const std = @import("std");
const td3 = @import("src/td3_native.zig");

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION
// ─────────────────────────────────────────────────────────────────────────────
pub const BacktestConfig = struct {
    starting_balance: f64 = 200_000.0,
    daily_loss_limit_usd: f64 = 10_000.0,
    internal_gate_usd: f64 = 6_000.0,

    fill_latency_ms: f64 = 35.0,
    commission_per_lot: f64 = 3.00,
    point_value_per_lot: f64 = 100.0,
    lot_step: f64 = 0.1,
    min_lots: f64 = 0.5,

    atr_baseline: f64 = 25.0,
    atr_period_bars: usize = 14,
    stop_mult: f64 = 1.5,
    tp_mult: f64 = 2.0,

    action_long_thresh: f32 = 0.15,
    action_short_thresh: f32 = -0.15,
    min_hold_seconds: f64 = 95.0,

    mc_scenarios: usize = 1_000,
    mc_seed: u64 = 42,
};

// ─────────────────────────────────────────────────────────────────────────────
// DATA STRUCTURES
// ─────────────────────────────────────────────────────────────────────────────
pub const Tick = struct {
    timestamp: f64,
    bid: f64,
    ask: f64,
    volume: f64,

    pub fn mid(self: Tick) f64 {
        return (self.bid + self.ask) / 2.0;
    }
    pub fn spread(self: Tick) f64 {
        return self.ask - self.bid;
    }
};

pub const TradeRecord = struct {
    timestamp: f64,
    direction: i32,
    lots: f64,
    entry_price: f64,
    exit_price: f64,
    pnl_net: f64,
    hold_seconds: f64,
    equity_after: f64,
};

// ─────────────────────────────────────────────────────────────────────────────
// ATR TRACKER
// ─────────────────────────────────────────────────────────────────────────────
pub const ATRTracker = struct {
    period: usize,
    allocator: std.mem.Allocator,
    trs: std.ArrayList(f64),
    bar_start: ?f64,
    bar_h: f64,
    bar_l: f64,
    bar_c: f64,
    prev_close: ?f64,
    current_atr: ?f64,

    const BAR_SECONDS: f64 = 300.0;

    pub fn init(allocator: std.mem.Allocator, period: usize) ATRTracker {
        return .{
            .period = period,
            .allocator = allocator,
            .trs = std.ArrayList(f64).empty,
            .bar_start = null,
            .bar_h = 0.0,
            .bar_l = 0.0,
            .bar_c = 0.0,
            .prev_close = null,
            .current_atr = null,
        };
    }

    pub fn deinit(self: *ATRTracker) void {
        self.trs.deinit(self.allocator);
    }

    pub fn pushTick(self: *ATRTracker, tick: Tick) ?f64 {
        const m = tick.mid();
        if (self.bar_start == null) {
            self.bar_start = tick.timestamp;
            self.bar_h = m;
            self.bar_l = m;
        }

        self.bar_h = @max(self.bar_h, m);
        self.bar_l = @min(self.bar_l, m);
        self.bar_c = m;

        if (tick.timestamp - self.bar_start.? >= BAR_SECONDS) {
            var tr: f64 = self.bar_h - self.bar_l;
            if (self.prev_close) |pc| {
                const tr1 = @abs(self.bar_h - pc);
                const tr2 = @abs(self.bar_l - pc);
                tr = @max(tr, @max(tr1, tr2));
            }

            if (self.trs.items.len >= self.period) {
                _ = self.trs.orderedRemove(0);
            }
            self.trs.append(self.allocator, tr) catch unreachable;

            self.prev_close = self.bar_c;
            self.bar_start = tick.timestamp;
            self.bar_h = m;
            self.bar_l = m;

            if (self.trs.items.len >= self.period) {
                var sum: f64 = 0;
                for (self.trs.items) |t| sum += t;
                self.current_atr = sum / @as(f64, @floatFromInt(self.period));
            }
            return self.current_atr;
        }
        return null;
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// SLIPPAGE MODEL (Monte Carlo)
// ─────────────────────────────────────────────────────────────────────────────
pub const SlippageModel = struct {
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) SlippageModel {
        return .{ .prng = std.Random.DefaultPrng.init(seed) };
    }

    // Gaussian using Box-Muller transform
    fn randomGaussian(self: *SlippageModel) f64 {
        const random = self.prng.random();
        const u_1 = random.float(f64);
        const u_2 = random.float(f64);
        const z0 = @sqrt(-2.0 * @log(u_1 + 1e-8)) * @cos(2.0 * std.math.pi * u_2);
        return z0;
    }

    pub fn sampleSlippage(self: *SlippageModel, lots: f64, is_news: bool, is_spike: bool) f64 {
        const u = self.randomGaussian();
        const base_slip = @exp(-0.85 + 0.6 * u);
        
        const lot_factor = @sqrt(@max(lots, 0.5) / 0.5);
        
        var multiplier: f64 = 1.0;
        const random = self.prng.random();
        
        if (is_spike) {
            // Pareto tail approximation
            const pareto = 5.0 / @exp((1.0 / 1.5) * @log(random.float(f64) + 1e-8));
            multiplier = pareto;
        } else if (is_news) {
            multiplier = 2.5 + random.float(f64) * (6.0 - 2.5);
        }

        return base_slip * lot_factor * multiplier;
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// DEATH LOOP STRESS
// ─────────────────────────────────────────────────────────────────────────────
pub const DeathLoopStress = struct {
    cfg: BacktestConfig,

    pub fn maxSafeLots(self: DeathLoopStress, atr: f64) f64 {
        const denominator = atr * self.cfg.stop_mult * self.cfg.point_value_per_lot;
        if (denominator <= 0) return self.cfg.min_lots;
        const raw = self.cfg.internal_gate_usd / denominator;
        const stepped = @floor(raw / self.cfg.lot_step) * self.cfg.lot_step;
        return @max(stepped, self.cfg.min_lots);
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// BACKTEST ENVIRONMENT
// ─────────────────────────────────────────────────────────────────────────────
pub const BacktestEnvironment = struct {
    cfg: BacktestConfig,
    slip: SlippageModel,
    atr_tracker: ATRTracker,
    death_stress: DeathLoopStress,

    equity: f64,
    day_open_equity: f64,
    last_trade_time: f64 = 0,
    position: i32 = 0,
    entry_price: f64 = 0,
    entry_lots: f64 = 0,
    entry_sl: f64 = 0,
    entry_tp: f64 = 0,
    entry_time: f64 = 0,
    
    agent: *td3.TD3Agent,
    last_bid: f32 = 0,
    last_ask: f32 = 0,
    ofi: f32 = 0,
    cum_delta: f32 = 0,
    
    trades_count: usize = 0,
    allocator: std.mem.Allocator,

    // 35ms Latency Simulator Queue
    pending_dir: i32 = 0,
    pending_action: f32 = 0,
    pending_execute_time: f64 = 0,
    pending_close: bool = false,

    // Trade Telemetry
    entry_ofi: f32 = 0,
    entry_cum_delta: f32 = 0,
    entry_atr: f64 = 0,
    entry_slip: f64 = 0,
    csv_file: ?std.fs.File = null,

    pub fn init(allocator: std.mem.Allocator, cfg: BacktestConfig, agent: *td3.TD3Agent) BacktestEnvironment {
        return .{
            .cfg = cfg,
            .slip = SlippageModel.init(cfg.mc_seed),
            .atr_tracker = ATRTracker.init(allocator, cfg.atr_period_bars),
            .death_stress = DeathLoopStress{ .cfg = cfg },
            .equity = cfg.starting_balance,
            .day_open_equity = cfg.starting_balance,
            .trades_count = 0,
            .allocator = allocator,
            .agent = agent,
            .last_bid = 0,
            .last_ask = 0,
            .ofi = 0,
            .cum_delta = 0,
            .pending_dir = 0,
            .pending_action = 0,
            .pending_execute_time = 0,
            .pending_close = false,
            .csv_file = null,
        };
    }

    pub fn deinit(self: *BacktestEnvironment) void {
        self.atr_tracker.deinit();
        if (self.csv_file) |f| {
            f.close();
        }
    }

    fn computeLots(self: *BacktestEnvironment, atr: f64, action: f32) f64 {
        const atr_max = self.death_stress.maxSafeLots(atr);
        const remaining = @max(self.cfg.internal_gate_usd - (self.day_open_equity - self.equity), 0.0);
        if (remaining <= 0) return 0.0;

        const stop_pts = atr * self.cfg.stop_mult;
        const usd_per_lot = stop_pts * self.cfg.point_value_per_lot;
        if (usd_per_lot <= 0) return self.cfg.min_lots;

        const confidence = @min(@abs(action), 1.0);
        const risk_usd = remaining * 0.15 * confidence;
        var lots = risk_usd / usd_per_lot;

        lots = @min(lots, atr_max);
        const hyp_cap = (0.5 * self.cfg.atr_baseline) / (atr + 1e-8);
        lots = @min(lots, hyp_cap);

        lots = @max(self.cfg.min_lots, lots);
        lots = @floor(lots / self.cfg.lot_step) * self.cfg.lot_step;
        return @max(lots, self.cfg.min_lots);
    }

    pub fn run(self: *BacktestEnvironment, ticks: []const Tick) !void {
        // Mute during grid search
        // std.debug.print("[BACKTEST] Starting simulation on {d} ticks...\n", .{ticks.len});
        
        self.csv_file = try std.fs.cwd().createFile("backtest_trades.csv", .{});
        if (self.csv_file) |f| {
            const w = f.writer();
            try w.print("entry_time,exit_time,duration_sec,dir,lots,entry_price,exit_price,pnl,entry_slip_pts,exit_slip_pts,action_confidence,ofi,cum_delta,atr\n", .{});
        }
        
        // TD3 engine is injected directly, no global init needed
        
        var atr: f64 = self.cfg.atr_baseline;
        var i: usize = 0;

        while (i < ticks.len) : (i += 1) {
            const tick = ticks[i];
            
            if (self.atr_tracker.pushTick(tick)) |new_atr| {
                atr = new_atr;
            }

            // Simple Guardian check
            if ((self.day_open_equity - self.equity) >= self.cfg.internal_gate_usd) {
                if (self.position != 0) {
                    self.closePosition(tick);
                }
                continue;
            }

            // --- 35ms LATENCY EXECUTION QUEUE ---
            if (self.pending_dir != 0 and tick.timestamp >= self.pending_execute_time) {
                self.openPosition(self.pending_dir, tick, atr, self.pending_action);
                self.pending_dir = 0;
            }
            if (self.pending_close and tick.timestamp >= self.pending_execute_time) {
                try self.closePosition(tick);
                self.pending_close = false;
            }

            if (self.position != 0) {
                const mid = tick.mid();
                if (self.position == 1) {
                    if (mid <= self.entry_sl or mid >= self.entry_tp) {
                        if (!self.pending_close) {
                            self.pending_close = true;
                            self.pending_execute_time = tick.timestamp + (self.cfg.fill_latency_ms / 1000.0);
                        }
                    }
                } else {
                    if (mid >= self.entry_sl or mid <= self.entry_tp) {
                        if (!self.pending_close) {
                            self.pending_close = true;
                            self.pending_execute_time = tick.timestamp + (self.cfg.fill_latency_ms / 1000.0);
                        }
                    }
                }
            }

            if (tick.timestamp - self.last_trade_time < self.cfg.min_hold_seconds) {
                continue;
            }

            // AI Deep Learning State Generation
            const bid = @as(f32, @floatCast(tick.bid));
            const ask = @as(f32, @floatCast(tick.ask));
            const vol = @as(f32, @floatCast(tick.volume));
            
            if (self.last_bid != 0 and self.last_ask != 0) {
                if (bid > self.last_bid) self.ofi += vol;
                if (ask < self.last_ask) self.ofi -= vol;
            }
            self.last_bid = bid;
            self.last_ask = ask;
            self.ofi *= 0.95;
            self.cum_delta *= 0.95;

            const current_dd = @as(f32, @floatCast((self.cfg.starting_balance - self.equity) / self.cfg.starting_balance));
            const state = [_]f32{ self.ofi, self.cum_delta, 0.0, current_dd };

            // Ask the Brain
            const action = self.agent.selectAction(state);

            // "Always In" Binary Action Space
            const new_dir: i32 = if (action >= 0.0) 1 else -1;

            if (self.position != 0 and self.position != new_dir) {
                if (!self.pending_close) {
                    self.pending_close = true;
                    self.pending_execute_time = tick.timestamp + (self.cfg.fill_latency_ms / 1000.0);
                }
            }

            if (new_dir != 0 and self.position == 0 and self.pending_dir == 0 and !self.pending_close) {
                self.pending_dir = new_dir;
                self.pending_action = action;
                self.pending_execute_time = tick.timestamp + (self.cfg.fill_latency_ms / 1000.0);
            }
        }
    }

    fn openPosition(self: *BacktestEnvironment, dir: i32, tick: Tick, atr: f64, action: f32) void {
        const lots = self.computeLots(atr, action);
        if (lots <= 0) return;

        const slip = self.slip.sampleSlippage(lots, false, false); 
        const fill = if (dir == 1) tick.ask + slip else tick.bid - slip;
        
        self.position = dir;
        self.entry_price = fill;
        self.entry_lots = lots;
        self.entry_sl = fill - atr * self.cfg.stop_mult * @as(f64, @floatFromInt(dir));
        self.entry_tp = fill + atr * self.cfg.tp_mult * @as(f64, @floatFromInt(dir));
        self.entry_time = tick.timestamp;
        
        self.entry_ofi = self.ofi;
        self.entry_cum_delta = self.cum_delta;
        self.entry_atr = atr;
        self.entry_slip = slip;
    }

    fn closePosition(self: *BacktestEnvironment, tick: Tick) !void {
        const slip = self.slip.sampleSlippage(self.entry_lots, false, false);
        const fill = if (self.position == 1) tick.bid - slip else tick.ask + slip;

        const pts = (fill - self.entry_price) * @as(f64, @floatFromInt(self.position));
        const gross = pts * self.entry_lots * self.cfg.point_value_per_lot;
        const comm = self.cfg.commission_per_lot * self.entry_lots;
        const net = gross - comm;

        self.equity += net;
        const hold_sec = tick.timestamp - self.entry_time;
        
        if (self.csv_file) |f| {
            const w = f.writer();
            try w.print("{d:.3},{d:.3},{d:.1},{d},{d:.2},{d:.5},{d:.5},{d:.2},{d:.5},{d:.5},{d:.4},{d:.2},{d:.2},{d:.5}\n", .{
                self.entry_time, tick.timestamp, hold_sec, self.position, self.entry_lots,
                self.entry_price, fill, net, self.entry_slip, slip, self.pending_action,
                self.entry_ofi, self.entry_cum_delta, self.entry_atr
            });
        }
        
        self.last_trade_time = tick.timestamp;
        self.trades_count += 1;

        self.position = 0;
    }
};


