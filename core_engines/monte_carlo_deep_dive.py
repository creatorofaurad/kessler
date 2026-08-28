import numpy as np
import matplotlib.pyplot as plt
import os
import time

OUTPUT_DIR = r"C:\Users\srija\Projects\kessler\results"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# ---------------------------------------------------------
# 28K FORK PROTOCOL - ADVANCED MONTE CARLO MATRIX
# ---------------------------------------------------------
STARTING_CAPITAL = 2000.0
TARGET_CAPITAL = 28000.0
SIMULATIONS = 1000
DAYS_LIMIT = 90
TRADES_PER_DAY = 4

# True Market Probabilities (Factoring in XAUUSD Volatility)
WIN_RATE = 0.53
RR_RATIO = 2.1
RISK_PER_TRADE_PCT = 0.04
FAT_TAIL_SLIPPAGE = 0.015 # 1.5% chance of severe slippage (losing 2x risk)

print("[*] INITIATING DEEP-DIVE MONTE CARLO SIMULATION...")
print(f"[*] Projecting {SIMULATIONS} multiversal trading trajectories...")

all_trajectories = []
success_count = 0
max_drawdowns = []

start_time = time.time()

for sim in range(SIMULATIONS):
    equity = STARTING_CAPITAL
    trajectory = [equity]
    peak_equity = equity
    max_dd = 0.0
    
    for day in range(DAYS_LIMIT):
        for _ in range(TRADES_PER_DAY):
            risk_amount = equity * RISK_PER_TRADE_PCT
            
            # Simulate Fat Tail (Black Swan / Massive Slippage)
            if np.random.random() < FAT_TAIL_SLIPPAGE:
                equity -= risk_amount * 2.0
            elif np.random.random() < WIN_RATE:
                equity += risk_amount * RR_RATIO
            else:
                equity -= risk_amount
                
            if equity > peak_equity:
                peak_equity = equity
            
            dd = (peak_equity - equity) / peak_equity
            if dd > max_dd:
                max_dd = dd
                
            if equity < 100: # Liquidated
                break
                
        trajectory.append(equity)
        if equity >= TARGET_CAPITAL or equity < 100:
            break
            
    # Pad trajectory so they are all the same length for plotting
    while len(trajectory) < DAYS_LIMIT * TRADES_PER_DAY + 1:
        trajectory.append(trajectory[-1])
        
    all_trajectories.append(trajectory)
    max_drawdowns.append(max_dd)
    if equity >= TARGET_CAPITAL:
        success_count += 1

print(f"[*] Simulation computed in {round(time.time() - start_time, 2)}s.")
print("[*] Rendering Probability Cone Matrix...")

# ---------------------------------------------------------
# RENDER THE VISUALIZATION
# ---------------------------------------------------------
plt.style.use('dark_background')
fig, ax = plt.subplots(figsize=(12, 7))

# Plot all trajectories with low alpha for the "Cone" effect
for traj in all_trajectories:
    color = '#00ffaa' if traj[-1] >= TARGET_CAPITAL else '#ff3333'
    alpha = 0.02 if traj[-1] >= TARGET_CAPITAL else 0.05
    ax.plot(traj, color=color, alpha=alpha, linewidth=1)

# Plot Mean Trajectory
all_trajectories_np = np.array(all_trajectories)
mean_trajectory = np.mean(all_trajectories_np, axis=0)
ax.plot(mean_trajectory, color='white', linewidth=2, label='Mean Capital Velocity')

# Horizontal Thresholds
ax.axhline(TARGET_CAPITAL, color='#00aaff', linestyle='--', linewidth=1.5, label='28k Fork Milestone')
ax.axhline(15800.0, color='#ffff00', linestyle=':', linewidth=1.5, label='Apple Gear CapEx Secured')
ax.axhline(STARTING_CAPITAL, color='gray', linestyle='-', linewidth=1, label='Base Capital ($2k)')

ax.set_title("Capital Velocity Projection: The 28k Fork Protocol", color='white', pad=20, fontsize=14, fontweight='bold')
ax.set_xlabel("Trades Executed", color='lightgray')
ax.set_ylabel("Account Equity (USD)", color='lightgray')
ax.set_yscale('log') # Log scale better represents compounding
ax.set_yticks([1000, 2000, 5000, 10000, 15800, 28000, 50000])
ax.get_yaxis().set_major_formatter(plt.ScalarFormatter())

# Clean up axes
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.grid(color='#333333', linestyle='--', alpha=0.5)

# Metrics Box
success_rate = (success_count / SIMULATIONS) * 100
avg_dd = np.mean(max_drawdowns) * 100
stats_text = (f"Hit Rate to $28k: {success_rate:.1f}%\n"
              f"Avg Max Drawdown: {avg_dd:.1f}%\n"
              f"Win Rate: {WIN_RATE*100}%\n"
              f"Risk/Trade: {RISK_PER_TRADE_PCT*100}%")
props = dict(boxstyle='round', facecolor='#111111', alpha=0.8, edgecolor='#333333')
ax.text(0.02, 0.95, stats_text, transform=ax.transAxes, fontsize=10,
        verticalalignment='top', bbox=props, color='white')

ax.legend(loc='lower right', facecolor='#111111', edgecolor='#333333')

file_path = os.path.join(OUTPUT_DIR, "monte_carlo_deep_dive.png")
plt.savefig(file_path, dpi=300, bbox_inches='tight', facecolor='#0d1117')
print(f"[+] Advanced visualization saved to {file_path}")
