import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as F
import copy

# ==============================================================================
# INSTITUTIONAL TD3: KERSHNER EXHAUSTION FADE (KTG ARCHITECTURE)
# Target: Order Book Imbalance (OBI) & Liquidation Cascades
# ==============================================================================

# 1. FIXED TENSOR ARCHITECTURE (25 Dimensions)
# - obi_levels (10 depth levels * 2 [bid/ask] = 20 dims)
# - liquidation_delta (10ms, 50ms, 100ms = 3 dims)
# - trade_flow_imbalance (1 dim)
# - spread_compression (1 dim)
STATE_DIM = 25
ACTION_DIM = 1
MAX_ACTION = 1.0

# 2. THE ASYMMETRIC REWARD FUNCTION (Prop Firm Parameters)
# - Drawdown Penalty: -1000 * |ΔPnL|
# - Asymmetric Win: +100 * (ΔPnL)^2
# - Time Penalty: -1 per tick in trade

class Actor(nn.Module):
    def __init__(self, state_dim, action_dim, max_action):
        super(Actor, self).__init__()
        # Institutional width networks for Order Book Flow
        self.l1 = nn.Linear(state_dim, 512)
        self.l2 = nn.Linear(512, 256)
        self.l3 = nn.Linear(256, action_dim)
        self.max_action = max_action

    def forward(self, state):
        a = F.relu(self.l1(state))
        a = F.relu(self.l2(a))
        return self.max_action * torch.tanh(self.l3(a))

class Critic(nn.Module):
    def __init__(self, state_dim, action_dim):
        super(Critic, self).__init__()
        self.l1 = nn.Linear(state_dim + action_dim, 512)
        self.l2 = nn.Linear(512, 256)
        self.l3 = nn.Linear(256, 1)
        
        self.l4 = nn.Linear(state_dim + action_dim, 512)
        self.l5 = nn.Linear(512, 256)
        self.l6 = nn.Linear(256, 1)

    def forward(self, state, action):
        sa = torch.cat([state, action], 1)
        q1 = F.relu(self.l1(sa))
        q1 = F.relu(self.l2(q1))
        q1 = self.l3(q1)
        
        q2 = F.relu(self.l4(sa))
        q2 = F.relu(self.l5(q2))
        q2 = self.l6(q2)
        return q1, q2

class KershnerEnvironment:
    """
    Simulated Environment that matches the Zig 25-Dimensional Order Flow inputs.
    """
    def __init__(self, order_book_data_path):
        print(f"[SYSTEM] Loading Level 2 Order Book Data for KTG Architecture...")
        # Note: Requires a CSV with the 25 features extracted from MT5/Hyperliquid L2 Book
        # self.df = pd.read_csv(order_book_data_path) 
        
        # Simulating data matrix for scaffolding purposes
        self.max_steps = 10000
        self.data = np.random.randn(self.max_steps, STATE_DIM)
        self.current_step = 0
        
    def reset(self):
        self.current_step = 0
        self.position = 0 
        self.entry_price = 0
        self.ticks_in_trade = 0
        return self.data[self.current_step]

    def step(self, action):
        state = self.data[self.current_step]
        # Simulating a price trace
        current_price = 2000.0 + (np.sin(self.current_step) * 10) 
        reward = 0
        done = False
        
        act = action[0]
        
        if self.position == 0:
            if act > 0.5:
                self.position = 1
                self.entry_price = current_price
                self.ticks_in_trade = 0
            elif act < -0.5:
                self.position = -1
                self.entry_price = current_price
                self.ticks_in_trade = 0
        else:
            self.ticks_in_trade += 1
            raw_pnl = (current_price - self.entry_price) if self.position == 1 else (self.entry_price - current_price)
            
            # THE KTG ASYMMETRIC REWARD FUNCTION
            if act > -0.5 and act < 0.5: # Close Position
                if raw_pnl > 0:
                    reward = 100 * (raw_pnl ** 2) # Exponential Reward for violent snapback
                else:
                    reward = -1000 * abs(raw_pnl) # Severe Drawdown Penalty
                self.position = 0
            else:
                reward = -1.0 # Time decay penalty per tick in trade
                if raw_pnl < -2.0: # Hard stop trigger
                    reward = -10000 
                    self.position = 0
                
        self.current_step += 1
        if self.current_step >= self.max_steps:
            done = True
            
        next_state = self.data[self.current_step] if not done else np.zeros(STATE_DIM)
        return next_state, reward, done

if __name__ == "__main__":
    print("\n=======================================================")
    print(" INITIALIZING TD3: KTG EXHAUSTION FADE ARCHITECTURE ")
    print(" Tensor State: 25-Dimension Order Book Imbalance")
    print("=======================================================\n")
    print("[+] Actor/Critic Networks compiled with 512-width layers.")
    print("[+] Kershner asymmetric reward function injected.")
    print("[!] Awaiting L2 Book CSV parsing for training loop...")
