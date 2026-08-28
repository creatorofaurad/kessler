#!/usr/bin/env python3
"""
Rift Phase 1.5 — Temporal Heatmap Generator
=============================================
Ingests historical SOL/ETH 5m candle data from Binance/Bybit CSVs,
simulates the stat-arb Z-score mean-reversion logic across the entire
dataset, and outputs a deterministic Time-of-Day (ToD) profitability
matrix.

Reveals exactly which UTC hours are alpha-rich (Tokyo close)
and which are toxic (New York lunchtime chop).

Output:
  - Console heatmap with Sharpe Ratio per hour
  - Console heatmap with Sharpe Ratio per (hour, day-of-week)
  - Exports tod_filter.json with the optimal trading windows
"""

import os
import sys
import json
import numpy as np
import pandas as pd
from datetime import datetime

# ═══════════════════════════════════════════════════
# CONFIG
# ═══════════════════════════════════════════════════
DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
SOL_GENESIS = os.path.join(DATA_DIR, "SOLUSDT_5m_genesis.csv")
ETH_GENESIS = os.path.join(DATA_DIR, "ETHUSDT_5m_genesis.csv")
SOL_RECENT = os.path.join(DATA_DIR, "SOLUSDT_5m_historical.csv")
ETH_RECENT = os.path.join(DATA_DIR, "BTCUSDT_5m_historical.csv")  # Recent fallback

# Stat-arb parameters (must match the live engine)
LOOKBACK = 60       # 60 x 5m = 5 hours rolling window
Z_ENTRY = 1.75
Z_EXIT = 0.2
Z_STOP = 3.5

# Output
OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "..", "tod_filter.json")


def load_sol_eth():
    """Load and align SOL and ETH price series from genesis to present."""
    print("[HEATMAP] Loading SOL 6-year data (Genesis + Recent)...")
    sol_gen = pd.read_csv(SOL_GENESIS)
    sol_rec = pd.read_csv(SOL_RECENT)
    sol_df = pd.concat([sol_gen, sol_rec]).drop_duplicates(subset=["timestamp"])
    
    if sol_df["timestamp"].dtype == object or str(sol_df["timestamp"].iloc[0]).count("-") >= 2:
        sol_df["timestamp"] = pd.to_datetime(sol_df["timestamp"])
    else:
        sol_df["timestamp"] = pd.to_datetime(sol_df["timestamp"], unit="ms")
    
    sol_df = sol_df[["timestamp", "close"]].rename(columns={"close": "sol_close"})
    sol_df = sol_df.set_index("timestamp").sort_index()
    
    print("[HEATMAP] Loading ETH 6-year data (Genesis + Recent)...")
    eth_gen = pd.read_csv(ETH_GENESIS)
    
    # We try to use the recent eth file if available, or fall back to the BTC proxy file
    # but since we downloaded genesis, we can just use the genesis file which goes up to 2024,
    # and then eth_master for the rest.
    eth_master = os.path.join(DATA_DIR, "eth_master_1m.csv")
    eth_rec = pd.read_csv(eth_master)
    eth_df = pd.concat([eth_gen, eth_rec]).drop_duplicates(subset=["timestamp"])
    
    if eth_df["timestamp"].dtype == object or str(eth_df["timestamp"].iloc[0]).count("-") >= 2:
        eth_df["timestamp"] = pd.to_datetime(eth_df["timestamp"])
    else:
        eth_df["timestamp"] = pd.to_datetime(eth_df["timestamp"], unit="ms")
        
    eth_df = eth_df[["timestamp", "close"]].rename(columns={"close": "eth_close"})
    eth_df = eth_df.set_index("timestamp").sort_index()
    
    print("[HEATMAP] Resampling ETH to 5m...")
    eth_df = eth_df.resample("5min").last().dropna()

    # Align on shared timestamps
    print("[HEATMAP] Aligning timestamps...")
    combined = sol_df.join(eth_df, how="inner").dropna()
    print(f"[HEATMAP] Aligned {len(combined)} shared 5m bars")
    print(f"[HEATMAP] Date range: {combined.index[0]} to {combined.index[-1]}")
    return combined


def compute_spread_zscore(sol_prices, eth_prices, lookback):
    """Vectorized rolling Z-score computation for the log spread."""
    log_sol = np.log(sol_prices)
    log_eth = np.log(eth_prices)
    
    n = len(log_sol)
    z_scores = np.full(n, np.nan)
    betas = np.full(n, np.nan)
    r_squared = np.full(n, np.nan)
    
    for i in range(lookback, n):
        window_sol = log_sol[i - lookback:i]
        window_eth = log_eth[i - lookback:i]
        
        # Beta via covariance
        cov = np.cov(window_sol, window_eth)
        var_eth = np.var(window_eth)
        if var_eth < 1e-12:
            continue
        beta = cov[0][1] / var_eth
        betas[i] = beta
        
        # Spread
        spread_window = window_sol - beta * window_eth
        mu = np.mean(spread_window)
        sigma = np.std(spread_window)
        if sigma < 1e-10:
            continue
        
        # Current spread point
        current_spread = log_sol[i] - beta * log_eth[i]
        z_scores[i] = (current_spread - mu) / sigma
        
        # R² for regime quality
        x = window_eth
        y = window_sol
        x_mean = np.mean(x)
        y_mean = np.mean(y)
        ss_xy = np.sum((x - x_mean) * (y - y_mean))
        ss_xx = np.sum((x - x_mean) ** 2)
        ss_yy = np.sum((y - y_mean) ** 2)
        if ss_xx > 1e-12 and ss_yy > 1e-12:
            r = ss_xy / np.sqrt(ss_xx * ss_yy)
            r_squared[i] = r ** 2
    
    return z_scores, betas, r_squared


def simulate_trades(df, z_scores, r_squared):
    """
    Simulate the stat-arb entry/exit logic across the full dataset.
    Returns a list of trade dicts with entry_time, exit_time, pnl, direction.
    """
    trades = []
    position = 0  # 0=flat, 1=long spread, -1=short spread
    entry_idx = 0
    entry_z = 0.0
    
    for i in range(len(z_scores)):
        z = z_scores[i]
        if np.isnan(z):
            continue
        
        r2 = r_squared[i] if not np.isnan(r_squared[i]) else 0.0
        
        # Skip if regime is bad
        if r2 < 0.60:
            if position != 0:
                # Force close on regime break
                pnl = _calc_trade_pnl(df, entry_idx, i, position)
                trades.append({
                    "entry_time": df.index[entry_idx],
                    "exit_time": df.index[i],
                    "pnl": pnl,
                    "direction": position,
                    "exit_reason": "REGIME_BREAK"
                })
                position = 0
            continue
        
        if position == 0:
            # Entry logic
            if z >= Z_ENTRY:
                position = -1  # Short spread
                entry_idx = i
                entry_z = z
            elif z <= -Z_ENTRY:
                position = 1  # Long spread
                entry_idx = i
                entry_z = z
        else:
            # Exit logic
            # Stop loss
            if abs(z) >= Z_STOP:
                pnl = _calc_trade_pnl(df, entry_idx, i, position)
                trades.append({
                    "entry_time": df.index[entry_idx],
                    "exit_time": df.index[i],
                    "pnl": pnl,
                    "direction": position,
                    "exit_reason": "STOP_LOSS"
                })
                position = 0
                continue
            
            # Mean reverted
            if abs(z) <= Z_EXIT:
                pnl = _calc_trade_pnl(df, entry_idx, i, position)
                trades.append({
                    "entry_time": df.index[entry_idx],
                    "exit_time": df.index[i],
                    "pnl": pnl,
                    "direction": position,
                    "exit_reason": "MEAN_REVERTED"
                })
                position = 0
                continue
            
            # Time stop (max 120 bars = 10 hours)
            if (i - entry_idx) > 120:
                pnl = _calc_trade_pnl(df, entry_idx, i, position)
                trades.append({
                    "entry_time": df.index[entry_idx],
                    "exit_time": df.index[i],
                    "pnl": pnl,
                    "direction": position,
                    "exit_reason": "TIME_STOP"
                })
                position = 0
                continue
    
    return trades


def _calc_trade_pnl(df, entry_idx, exit_idx, direction):
    """Calculate simple spread P&L (normalized to basis points)."""
    sol_entry = df["sol_close"].iloc[entry_idx]
    eth_entry = df["eth_close"].iloc[entry_idx]
    sol_exit = df["sol_close"].iloc[exit_idx]
    eth_exit = df["eth_close"].iloc[exit_idx]
    
    # Log return of each leg
    sol_ret = (sol_exit - sol_entry) / sol_entry
    eth_ret = (eth_exit - eth_entry) / eth_entry
    
    if direction == -1:  # Short spread: short SOL, long ETH
        return (-sol_ret + eth_ret) * 10000  # basis points
    else:  # Long spread: long SOL, short ETH
        return (sol_ret - eth_ret) * 10000


def build_hourly_heatmap(trades):
    """Group trades by entry hour (UTC) and compute Sharpe per hour."""
    hourly = {h: [] for h in range(24)}
    
    for t in trades:
        hour = t["entry_time"].hour
        hourly[hour].append(t["pnl"])
    
    results = {}
    for hour in range(24):
        pnls = hourly[hour]
        if len(pnls) < 5:
            results[hour] = {"sharpe": 0.0, "mean_pnl": 0.0, "count": len(pnls),
                             "win_rate": 0.0, "total_pnl": 0.0}
            continue
        
        arr = np.array(pnls)
        mean = np.mean(arr)
        std = np.std(arr)
        sharpe = (mean / std) if std > 1e-8 else 0.0
        win_rate = np.sum(arr > 0) / len(arr) * 100
        
        results[hour] = {
            "sharpe": round(sharpe, 4),
            "mean_pnl": round(mean, 2),
            "count": len(pnls),
            "win_rate": round(win_rate, 1),
            "total_pnl": round(float(np.sum(arr)), 2)
        }
    
    return results


def build_dow_heatmap(trades):
    """Group trades by (day_of_week, hour) and compute Sharpe."""
    dow_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    grid = {}
    for dow in range(7):
        for hour in range(24):
            key = (dow, hour)
            grid[key] = []
    
    for t in trades:
        dow = t["entry_time"].weekday()
        hour = t["entry_time"].hour
        grid[(dow, hour)].append(t["pnl"])
    
    results = {}
    for (dow, hour), pnls in grid.items():
        if len(pnls) < 3:
            results[f"{dow_names[dow]}_{hour:02d}"] = {"sharpe": 0.0, "count": len(pnls)}
            continue
        arr = np.array(pnls)
        mean = np.mean(arr)
        std = np.std(arr)
        sharpe = (mean / std) if std > 1e-8 else 0.0
        results[f"{dow_names[dow]}_{hour:02d}"] = {
            "sharpe": round(sharpe, 4),
            "count": len(pnls),
            "mean_pnl": round(mean, 2),
            "win_rate": round(np.sum(arr > 0) / len(arr) * 100, 1)
        }
    
    return results


def classify_hours(hourly_results):
    """
    Classify each hour into ALPHA, NEUTRAL, or TOXIC based on Sharpe.
    Returns the tod_filter config for injection into the PairsEngine.
    """
    alpha_hours = []
    toxic_hours = []
    neutral_hours = []
    
    for hour, stats in sorted(hourly_results.items()):
        if stats["sharpe"] >= 0.15 and stats["count"] >= 10:
            alpha_hours.append(hour)
        elif stats["sharpe"] <= -0.05 or stats["win_rate"] < 40:
            toxic_hours.append(hour)
        else:
            neutral_hours.append(hour)
    
    return {
        "alpha_hours_utc": alpha_hours,
        "toxic_hours_utc": toxic_hours,
        "neutral_hours_utc": neutral_hours,
        "mode": "HIBERNATE_ON_TOXIC",
        "description": "Rift will HIBERNATE during toxic hours and run at full Kelly during alpha hours."
    }


def print_heatmap(hourly_results):
    """Pretty-print the 24-hour heatmap."""
    print("\n" + "=" * 80)
    print("  RIFT TEMPORAL HEATMAP — 24-Hour Sharpe Ratio (UTC)")
    print("=" * 80)
    print(f"  {'Hour':>6} | {'Sharpe':>8} | {'Mean PnL':>10} | {'Win Rate':>9} | {'Trades':>7} | {'Total PnL':>10} | {'Rating'}")
    print("-" * 80)
    
    for hour in range(24):
        s = hourly_results[hour]
        sharpe = s["sharpe"]
        
        if sharpe >= 0.15:
            rating = "🟢 ALPHA"
        elif sharpe >= 0.0:
            rating = "🟡 NEUTRAL"
        else:
            rating = "🔴 TOXIC"
        
        # IST conversion
        ist_hour = (hour + 5) % 24  # +5:30 approximated to +5 for display
        
        print(f"  {hour:02d} UTC | {sharpe:>8.4f} | {s['mean_pnl']:>8.2f} bp | {s['win_rate']:>7.1f}% | {s['count']:>7} | {s['total_pnl']:>8.2f} bp | {rating}")
    
    print("=" * 80)


def print_session_summary(hourly_results):
    """Print summary by trading session."""
    sessions = {
        "Tokyo (00-08 UTC)": list(range(0, 8)),
        "London (08-13 UTC)": list(range(8, 13)),
        "NY Open (13-17 UTC)": list(range(13, 17)),
        "NY Close (17-21 UTC)": list(range(17, 21)),
        "Dead Zone (21-00 UTC)": list(range(21, 24)),
    }
    
    print("\n" + "=" * 60)
    print("  SESSION-LEVEL SUMMARY")
    print("=" * 60)
    
    for name, hours in sessions.items():
        total_pnl = sum(hourly_results[h]["total_pnl"] for h in hours)
        total_trades = sum(hourly_results[h]["count"] for h in hours)
        avg_sharpe = np.mean([hourly_results[h]["sharpe"] for h in hours])
        
        emoji = "🟢" if avg_sharpe >= 0.10 else ("🔴" if avg_sharpe < 0 else "🟡")
        print(f"  {emoji} {name:30s} | Sharpe: {avg_sharpe:+.4f} | Trades: {total_trades:>5} | Total: {total_pnl:>+10.2f} bp")
    
    print("=" * 60)


def main():
    print("=" * 60)
    print("  RIFT PHASE 1.5 — TEMPORAL HEATMAP GENERATOR")
    print("  Medallion-Style Time-of-Day Pattern Extraction")
    print("=" * 60)
    
    # Load data
    df = load_sol_eth()
    
    if len(df) < LOOKBACK + 100:
        print(f"[ERROR] Not enough aligned data. Got {len(df)} bars, need at least {LOOKBACK + 100}.")
        sys.exit(1)
    
    # Compute Z-scores
    print("[HEATMAP] Computing rolling Z-scores and R² across full dataset...")
    sol_arr = df["sol_close"].values
    eth_arr = df["eth_close"].values
    z_scores, betas, r_squared = compute_spread_zscore(sol_arr, eth_arr, LOOKBACK)
    
    valid_z = np.sum(~np.isnan(z_scores))
    print(f"[HEATMAP] Computed {valid_z} valid Z-score observations")
    
    # Simulate trades
    print("[HEATMAP] Simulating stat-arb trades across full history...")
    trades = simulate_trades(df, z_scores, r_squared)
    print(f"[HEATMAP] Simulated {len(trades)} total trades")
    
    if len(trades) < 20:
        print("[ERROR] Too few trades to build a reliable heatmap.")
        sys.exit(1)
    
    wins = sum(1 for t in trades if t["pnl"] > 0)
    total_pnl = sum(t["pnl"] for t in trades)
    print(f"[HEATMAP] Win Rate: {wins}/{len(trades)} ({wins/len(trades)*100:.1f}%)")
    print(f"[HEATMAP] Total Simulated P&L: {total_pnl:+.2f} basis points")
    
    # Build heatmaps
    hourly = build_hourly_heatmap(trades)
    dow = build_dow_heatmap(trades)
    
    # Print results
    print_heatmap(hourly)
    print_session_summary(hourly)
    
    # Classify and export
    tod_filter = classify_hours(hourly)
    
    print(f"\n[HEATMAP] 🟢 ALPHA HOURS (UTC): {tod_filter['alpha_hours_utc']}")
    print(f"[HEATMAP] 🔴 TOXIC HOURS (UTC): {tod_filter['toxic_hours_utc']}")
    print(f"[HEATMAP] 🟡 NEUTRAL HOURS (UTC): {tod_filter['neutral_hours_utc']}")
    
    # Save filter config
    with open(OUTPUT_FILE, "w") as f:
        json.dump(tod_filter, f, indent=2)
    print(f"\n[HEATMAP] ✅ ToD filter exported to: {OUTPUT_FILE}")
    
    # Also save the full dow heatmap for deep analysis
    dow_file = os.path.join(os.path.dirname(__file__), "..", "dow_heatmap.json")
    with open(dow_file, "w") as f:
        json.dump(dow, f, indent=2)
    print(f"[HEATMAP] ✅ Day-of-Week heatmap exported to: {dow_file}")
    
    print(f"\n{'='*60}")
    print(f"  INTEGRATION INSTRUCTIONS")
    print(f"{'='*60}")
    print(f"  Add to PairsEngine.generate_signal():")
    print(f"")
    print(f"    from datetime import datetime, timezone")
    print(f"    tod = json.load(open('tod_filter.json'))")
    print(f"    current_utc_hour = datetime.now(timezone.utc).hour")
    print(f"    if current_utc_hour in tod['toxic_hours_utc']:")
    print(f"        return None  # HIBERNATE")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
