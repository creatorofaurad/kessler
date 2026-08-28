const std = @import("std");
const ring_buffer = @import("ring_buffer.zig");
const bazaar = @import("../exchange.zig");
const crowd = @import("../agents.zig");
const gossip = @import("../network.zig");
const scenario = @import("../config_parser.zig");
const stash = @import("../memory.zig");

const c = @cImport({
    @cInclude("unistd.h");
});

pub fn engineMain(ring: *ring_buffer.RingBuffer) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const bazaar_config = bazaar.Config{};
    const crowd_config = crowd.Config{};
    
    // In GUI mode, we just run the default scenario / parameters
    const num_assets: usize = 100;
    var market = bazaar.Bazaar.init(allocator, num_assets, bazaar_config) catch return;
    defer market.deinit(allocator);

    const agent_count = 1000;
    var crowd_stash = stash.Stash.stashCreate(allocator, 128 * 1024 * 1024) catch return;
    defer crowd_stash.stashDestroy(allocator);

    var agents = crowd.Crowd.init(&crowd_stash, agent_count, num_assets, crowd_config, 0) catch return;
    

    var net = gossip.Network.init(&crowd_stash, @intCast(agent_count), 42) catch return;

    // Run the modified tick loop
    guiTickLoop(&market, &agents, &net, ring);
}

fn guiTickLoop(market: *bazaar.Bazaar, agents: *crowd.Crowd, net: *gossip.Network, ring: *ring_buffer.RingBuffer) void {
    const num_ticks: u32 = 1000000; // run indefinitely or a very long time for the GUI

    // Wait 1 second before starting so GUI can initialize
    _ = c.usleep(1 * 1000 * 1000);

    var price_history: [200]f64 = [_]f64{100.0} ** 200;
    var price_write_idx: u8 = 0;
    var prev_price: f64 = market.assets[0].price;

    for (0..num_ticks) |tick| {
        // Sleep to throttle the simulation to ~60 ticks per second so we can watch it
        _ = c.usleep(16 * 1000);

        // 1. Placeholder fallback shock if no scenario shocks are defined
        if (tick % 200 == 50) { // Periodically shock to keep it interesting
            market.submitOrder(0, false, 50000.0);
        }

        // 2. Value Investor orders
        for (0..agents.num_assets) |j| {
            const buy_vol = agents.evaluateValueInvestors(market.assets[j].price);
            if (buy_vol > 0) {
                market.submitOrder(@as(u32, @intCast(j)), true, buy_vol);
            }
        }

        // 3. Mark-to-Market & Margin Call / Forced Selling
        for (0..agents.cash.len) |i| {
            if (agents.is_defaulted[i]) continue;

            var asset_value: f64 = 0.0;
            for (0..agents.num_assets) |j| {
                asset_value += agents.positions[i * agents.num_assets + j] * market.assets[j].price;
            }

            const equity = agents.cash[i] + asset_value;
            agents.equity[i] = equity;

            if (equity <= 0) {
                agents.is_defaulted[i] = true;
                continue;
            }

            const current_leverage = asset_value / equity;
            agents.leverage[i] = current_leverage;

            if (current_leverage > agents.config.leverage_cap) {
                const excess_leverage = current_leverage - agents.target_leverage[i];
                const value_to_sell = excess_leverage * equity;

                if (value_to_sell > 0) {
                    for (0..agents.num_assets) |j| {
                        const amount_to_sell = (value_to_sell / @as(f64, @floatFromInt(agents.num_assets))) / market.assets[j].price;
                        if (amount_to_sell > 0 and agents.positions[i * agents.num_assets + j] >= amount_to_sell) {
                            agents.positions[i * agents.num_assets + j] -= amount_to_sell;
                            agents.cash[i] += amount_to_sell * market.assets[j].price;
                            market.submitOrder(@as(u32, @intCast(j)), false, amount_to_sell);
                        }
                    }
                }
            }

            for (0..agents.num_assets) |j| {
                if (market.assets[j].price < 90.0) {
                    const panic_sell = agents.positions[i * agents.num_assets + j] * agents.config.decay_rate * 0.05;
                    if (panic_sell > 0) {
                        agents.positions[i * agents.num_assets + j] -= panic_sell;
                        agents.cash[i] += panic_sell * market.assets[j].price;
                        market.submitOrder(@as(u32, @intCast(j)), false, panic_sell);
                    }
                }
            }
        }

        // 3.5 Hawkes Intensity Decay & Herd Behavior removed in favor of Ising Spin Model in main engine

        // 4. Gai-Kapadia Network Contagion Cascade
        const cascade_depth = net.propagateDefaults(agents, market);

        // 5. Update Market Microstructure
        market.updateMarketMicrostructure();
        
        const new_price = market.assets[0].price;

        price_history[price_write_idx] = new_price;
        price_write_idx = (price_write_idx + 1) % 200;

        // 6. Gather GUI Data
        var active_defaults: u64 = 0;
        for (agents.is_defaulted) |def| {
            if (def) active_defaults += 1;
        }

        var total_sentiment: f64 = 0.0;
        var theta_dist = [_]f64{0, 0, 0, 0};
        var active_agents: f64 = 0.0;
        
        for (0..agents.cash.len) |i| {
            if (agents.is_defaulted[i]) continue;
            
            // Read true spin from agents
            const th = @as(f64, @floatFromInt(agents.spin[i]));
            
            // Map [-1, 1] to [0, 1] for the average
            const normalized_th = (th + 1.0) / 2.0;
            total_sentiment += normalized_th;
            active_agents += 1.0;

            if (normalized_th > 0.7) {
                theta_dist[0] += 1.0; // Bullish
            } else if (normalized_th > 0.3) {
                theta_dist[1] += 1.0; // Neutral
            } else if (normalized_th > 0.1) {
                theta_dist[2] += 1.0; // Bearish
            } else {
                theta_dist[3] += 1.0; // Panicked
            }
        }

        const avg_sentiment = if (active_agents > 0) total_sentiment / active_agents else 0.0;
        if (active_agents > 0) {
            theta_dist[0] /= active_agents;
            theta_dist[1] /= active_agents;
            theta_dist[2] /= active_agents;
            theta_dist[3] /= active_agents;
        }

        var hash_update: [32]u8 = [_]u8{0} ** 32;
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(&std.mem.toBytes(tick));
        hasher.update(&std.mem.toBytes(new_price));
        hasher.update(&std.mem.toBytes(active_defaults));
        hasher.update(&std.mem.toBytes(cascade_depth));
        hasher.update(&std.mem.toBytes(avg_sentiment));
        hasher.final(&hash_update);

        prev_price = new_price;

        var snapshot = ring_buffer.TickSnapshot{
            .tick_number = tick,
            .market_prices = price_history,
            .price_write_idx = price_write_idx,
            .base_depths = [_]f64{0} ** 36,
            .volatilities = [_]f64{0} ** 36,
            .asset_frozen = [_]bool{false} ** 36,
            .cascade_depth = cascade_depth,
            .total_defaults = active_defaults,
            .theta_avg = avg_sentiment,
            .theta_distribution = theta_dist,
            .hash_first8 = [_]u8{0} ** 8,
            .engine_running = true,
        };

        for (0..8) |i| {
            snapshot.hash_first8[i] = hash_update[i];
        }

        for (0..36) |i| {
            if (i < market.assets.len) {
                const asset = &market.assets[i];
                snapshot.base_depths[i] = asset.book_depth / 1000.0; // Normalize against initial depth
                snapshot.asset_frozen[i] = asset.is_frozen;
                
                // Approximate volatility based on price change
                const diff = @abs(asset.price - asset.last_price);
                const rel_diff = diff / asset.last_price;
                // scale up so it's visible as alpha
                var vol = rel_diff * 50.0;
                if (vol > 1.0) vol = 1.0;
                snapshot.volatilities[i] = vol;
            }
        }

        // Write to ring buffer
        const write_idx = ring.write_idx.load(.acquire);
        ring.slots[write_idx % ring_buffer.RingBuffer.CAPACITY] = snapshot;
        ring.write_idx.store(write_idx + 1, .release);
    }
    
    // Final offline snapshot
    const write_idx = ring.write_idx.load(.acquire);
    var final_snap = ring.slots[write_idx % ring_buffer.RingBuffer.CAPACITY];
    final_snap.engine_running = false;
    ring.slots[(write_idx + 1) % ring_buffer.RingBuffer.CAPACITY] = final_snap;
    ring.write_idx.store(write_idx + 1, .release);
}
