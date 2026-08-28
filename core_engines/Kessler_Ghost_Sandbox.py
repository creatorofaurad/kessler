import asyncio
import json
import websockets
import time
import pandas as pd
import numpy as np
from datetime import datetime, timezone

print("[SYSTEM] Booting Kessler Ghost Sandbox v2.0 (Hyperliquid)...")
print("[SYSTEM] Initializing The 4 Weapons Ensemble: ORB, Silver Bullet, Judas, VWAP.")

class EnsembleSandbox:
    def __init__(self):
        self.balance = 500.0 # Starting Bankroll
        self.risk_pct = 0.05 # 5% Risk per trade
        
        # State
        self.in_trade = False
        self.trade_dir = ""
        self.entry_price = 0.0
        self.target_price = 0.0
        self.stop_price = 0.0
        self.active_weapon = ""
        
        # Market Memory
        self.prices = []
        self.volumes = []
        self.daily_open = None
        self.orb_high = -float('inf')
        self.orb_low = float('inf')
        self.orb_active = False
        
        self.ledger_file = "sandbox_ledger.csv"
        with open(self.ledger_file, "w") as f:
            f.write("Time,Weapon,Action,Price,PnL,Balance\n")
            
    def log_trade(self, action, price, pnl):
        with open(self.ledger_file, "a") as f:
            ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"{ts},{self.active_weapon},{action},{price:.2f},{pnl:.2f},{self.balance:.2f}\n")

    def get_vwap(self):
        if len(self.prices) == 0: return 0
        df = pd.DataFrame({'p': self.prices, 'v': self.volumes})
        if df['v'].sum() == 0: return df['p'].mean()
        return (df['p'] * df['v']).sum() / df['v'].sum()

    def check_exits(self, current_price):
        if not self.in_trade: return
        
        # LONG EXITS
        if self.trade_dir == "LONG":
            if current_price >= self.target_price:
                profit = (self.balance * self.risk_pct * 2.0)
                self.balance += profit
                self.in_trade = False
                print(f"[$$$] {self.active_weapon} LONG TARGET HIT @ {current_price}. Profit: +${profit:.2f} | Balance: ${self.balance:.2f}")
                self.log_trade("CLOSE_WIN", current_price, profit)
            elif current_price <= self.stop_price:
                loss = -(self.balance * self.risk_pct)
                self.balance += loss
                self.in_trade = False
                print(f"[XXX] {self.active_weapon} LONG STOPPED OUT @ {current_price}. Loss: ${loss:.2f} | Balance: ${self.balance:.2f}")
                self.log_trade("CLOSE_LOSS", current_price, loss)
                
        # SHORT EXITS
        elif self.trade_dir == "SHORT":
            if current_price <= self.target_price:
                profit = (self.balance * self.risk_pct * 2.0)
                self.balance += profit
                self.in_trade = False
                print(f"[$$$] {self.active_weapon} SHORT TARGET HIT @ {current_price}. Profit: +${profit:.2f} | Balance: ${self.balance:.2f}")
                self.log_trade("CLOSE_WIN", current_price, profit)
            elif current_price >= self.stop_price:
                loss = -(self.balance * self.risk_pct)
                self.balance += loss
                self.in_trade = False
                print(f"[XXX] {self.active_weapon} SHORT STOPPED OUT @ {current_price}. Loss: ${loss:.2f} | Balance: ${self.balance:.2f}")
                self.log_trade("CLOSE_LOSS", current_price, loss)

    def execute_trade(self, weapon, direction, price):
        self.in_trade = True
        self.active_weapon = weapon
        self.trade_dir = direction
        self.entry_price = price
        
        if direction == "LONG":
            self.stop_price = price * 0.995 # 0.5% stop
            self.target_price = price * 1.01 # 1% target (2R)
        else:
            self.stop_price = price * 1.005 # 0.5% stop
            self.target_price = price * 0.99 # 1% target (2R)
            
        print(f"\n[>>>] WEAPON FIRED: {weapon} | {direction} @ {price:.2f}")
        print(f"      Target: {self.target_price:.2f} | Stop: {self.stop_price:.2f}")
        self.log_trade(f"OPEN_{direction}", price, 0)

HL_WS_URL = "wss://api.hyperliquid.xyz/ws"

async def run_ensemble():
    sandbox = EnsembleSandbox()
    print(f"[*] Account Initialized with ${sandbox.balance:.2f}.")
    
    while True:
        try:
            async with websockets.connect(HL_WS_URL) as ws:
                subscribe_msg = {"method": "subscribe", "subscription": {"type": "trades", "coin": "SOL"}}
                await ws.send(json.dumps(subscribe_msg))
                
                print("[+] The 4 Weapons are Armed. Parsing Hyperliquid L1 Orderflow...")
                
                while True:
                    response = await ws.recv()
                    data = json.loads(response)
                    
                    if "channel" in data and data["channel"] == "trades":
                        for trade in data["data"]:
                            price = float(trade.get("px", 0))
                            vol = float(trade.get("sz", 0))
                            
                            sandbox.prices.append(price)
                            sandbox.volumes.append(vol)
                            if len(sandbox.prices) > 1000:
                                sandbox.prices.pop(0)
                                sandbox.volumes.pop(0)
                                
                            sandbox.check_exits(price)
                            
                            if sandbox.in_trade:
                                continue
                                
                            now = datetime.now(timezone.utc)
                            vwap = sandbox.get_vwap()
                            
                            # 1. ORB (Opening Range Breakout) logic
                            # We define the UTC 00:00 as the open. If price breaks out of the first 15m range with high volume
                            if not sandbox.daily_open or now.hour == 0 and now.minute == 0:
                                sandbox.daily_open = price
                                sandbox.orb_high = price
                                sandbox.orb_low = price
                                sandbox.orb_active = True
                            
                            if sandbox.orb_active and now.hour == 0 and now.minute < 15:
                                sandbox.orb_high = max(sandbox.orb_high, price)
                                sandbox.orb_low = min(sandbox.orb_low, price)
                            
                            # ORB Execution: Breakout of 15m range
                            if sandbox.orb_active and now.hour == 0 and now.minute >= 15:
                                if price > sandbox.orb_high and price > vwap:
                                    sandbox.execute_trade("ORB Breakout", "LONG", price)
                                    sandbox.orb_active = False
                                elif price < sandbox.orb_low and price < vwap:
                                    sandbox.execute_trade("ORB Breakout", "SHORT", price)
                                    sandbox.orb_active = False

                            # 2. JUDAS SWING
                            # Detects sudden fakeout opposite to VWAP and fades it
                            if len(sandbox.prices) > 50:
                                short_sma = np.mean(sandbox.prices[-10:])
                                deviation = (short_sma - vwap) / vwap
                                
                                # If price spikes 0.8% away from VWAP, fade it back to VWAP
                                if deviation > 0.008:
                                    sandbox.execute_trade("Judas Swing", "SHORT", price)
                                elif deviation < -0.008:
                                    sandbox.execute_trade("Judas Swing", "LONG", price)

                            # 3. ICT SILVER BULLET (New York Open 10:00-11:00 AM EST -> 14:00-15:00 UTC)
                            if now.hour == 14:
                                # Sweep liquidity logic (simplified for stream: buy severe dips, sell severe rips in this hour)
                                if price < vwap * 0.995:
                                    sandbox.execute_trade("Silver Bullet", "LONG", price)
                                elif price > vwap * 1.005:
                                    sandbox.execute_trade("Silver Bullet", "SHORT", price)
                                    
        except Exception as e:
            print(f"[-] WebSocket Error: {e}. Reconnecting in 5s...")
            await asyncio.sleep(5)

if __name__ == "__main__":
    try:
        asyncio.run(run_ensemble())
    except KeyboardInterrupt:
        print("\n[SYSTEM] Ensemble Sandbox Terminated.")
