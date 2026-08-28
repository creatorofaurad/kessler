import random
import numpy as np
import time

print("\n[+] BOOTING THE 28K FORK PROTOCOL MONTE CARLO SIMULATOR...")

STARTING_CAPITAL = 2000.0
TARGET_CAPITAL = 28000.0
APPLE_GEAR_CAPEX = 15800.0  # Approx 12.8 Lakh INR
TD3_FUNDING = 10000.0
BASELINE_RETAINED = 2000.0

# Aggressive high-leverage win/loss metrics (Estimated for SAC-GRU Sniper)
WIN_RATE = 0.55
RR_RATIO = 2.0 # Average win is 2.0x the average loss
RISK_PER_TRADE_PCT = 0.04 # 4% risk due to high compounding goals
TRADES_PER_DAY = 4

SIMULATIONS = 10000
DAYS_LIMIT = 200

success_days = []
ruin_count = 0

start_time = time.time()

for _ in range(SIMULATIONS):
    equity = STARTING_CAPITAL
    days = 0
    for day in range(DAYS_LIMIT):
        days += 1
        for _ in range(TRADES_PER_DAY):
            risk_amount = equity * RISK_PER_TRADE_PCT
            if random.random() < WIN_RATE:
                equity += risk_amount * RR_RATIO
            else:
                equity -= risk_amount
            
            if equity < 100:
                break
        
        if equity >= TARGET_CAPITAL or equity < 100:
            break
            
    if equity >= TARGET_CAPITAL:
        success_days.append(days)
    else:
        ruin_count += 1

success_rate = (len(success_days) / SIMULATIONS) * 100
avg_days = np.mean(success_days) if success_days else 0

print(f"\n[*] SIMULATION COMPLETE: {SIMULATIONS} Timelines Analyzed in {round(time.time()-start_time, 2)}s")
print(f"==================================================")
print(f" -> STARTING CAPITAL    : ${STARTING_CAPITAL}")
print(f" -> TARGET MILESTONE    : ${TARGET_CAPITAL}")
print(f" -> RISK PER TRADE      : {RISK_PER_TRADE_PCT*100}%")
print(f" -> WIN RATE ESTIMATE   : {WIN_RATE*100}% (RR {RR_RATIO}:1)")
print(f"==================================================")
print(f"[>] PROBABILITY OF HITTING 28K FORK : {round(success_rate, 2)}%")
print(f"[>] AVERAGE TRADING DAYS TO TARGET  : {round(avg_days, 1)} Days")
print(f"[>] RISK OF RUIN (LIQUIDATION)      : {round((ruin_count/SIMULATIONS)*100, 2)}%")
print(f"==================================================")
if success_rate > 50:
    print(f"\n[+] POST-FORK ALLOCATION AT DAY {int(avg_days)}:")
    print(f"    - Hardware CapEx (Apple Gear) : ${APPLE_GEAR_CAPEX} (₹12.8L Secured)")
    print(f"    - TD3 Offshore Funding        : ${TD3_FUNDING}")
    print(f"    - Base Engine Retained        : ${BASELINE_RETAINED}")
    print("\n[+] MATH CHECKS OUT. CAPITAL VELOCITY IS OPTIMAL.")
else:
    print("\n[-] RISK OF RUIN TOO HIGH. TWEAK LEVERAGE PARAMETERS.")
