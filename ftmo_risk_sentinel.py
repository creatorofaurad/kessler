import time
import math

class FTMORiskSentinel:
    def __init__(self, initial_balance):
        self.initial_balance = initial_balance
        self.current_equity = initial_balance
        self.daily_start_equity = initial_balance
        
        # FTMO Hard Limits
        self.MAX_DAILY_DD_PCT = 0.05   # 5% Daily Drawdown limit
        self.MAX_TOTAL_DD_PCT = 0.10   # 10% Absolute Drawdown limit
        
        # Sentinel Kill Switches (We cut trading BEFORE hitting FTMO limits)
        self.KILL_DAILY_DD_PCT = 0.048 # Cut at 4.8%
        
        # Target Tracking
        self.BASE_TARGET_PCT = 0.10    # 10% baseline to trigger FTMO scaling

    def update_equity(self, new_equity):
        self.current_equity = new_equity
        
    def end_of_day_reset(self):
        """Called at 00:00 CE(S)T to reset daily drawdown metrics."""
        self.daily_start_equity = self.current_equity

    def calculate_kelly_fraction(self, win_rate, win_loss_ratio):
        """
        Calculates the dynamic Kelly fraction to size the next trade.
        10% is just the base. We scale dynamically.
        """
        # Standard Kelly Formula: K = W - ((1 - W) / R)
        kelly = win_rate - ((1.0 - win_rate) / win_loss_ratio)
        
        if kelly <= 0:
            return 0.0 # No edge, no trade.

        # Dynamic Risk Modifier based on current equity cushion
        profit_pct = (self.current_equity - self.initial_balance) / self.initial_balance
        
        if profit_pct >= self.BASE_TARGET_PCT:
            # 10% baseline secured. We are playing with house money.
            # We do NOT neuter the bot. We keep compounding, but cap risk to protect the scaling event.
            risk_modifier = 0.5  # Half-Kelly for stable, continuous aggressive growth
        elif profit_pct > 0:
            # In profit, but under 10%. Push aggressively to secure the base.
            risk_modifier = 0.75
        else:
            # In drawdown. Reduce risk exponentially to avoid hitting the 10% hard stop.
            cushion_left = self.MAX_TOTAL_DD_PCT - abs(profit_pct)
            risk_modifier = max(0.1, cushion_left * 5) # Choke sizing as drawdown deepens

        # Ensure we never risk more than 1% of the daily allowance per trade
        daily_cushion_remaining = self.get_daily_cushion()
        max_trade_risk = daily_cushion_remaining * 0.20 # Max 20% of remaining daily buffer per trade
        
        final_risk_pct = min(kelly * risk_modifier, max_trade_risk)
        return max(0.0, final_risk_pct)

    def get_daily_cushion(self):
        """Returns the remaining percentage before hitting the 4.8% daily kill switch."""
        daily_loss_limit = self.daily_start_equity * (1.0 - self.KILL_DAILY_DD_PCT)
        current_daily_loss = self.daily_start_equity - self.current_equity
        
        if current_daily_loss <= 0:
            return self.KILL_DAILY_DD_PCT # We are up for the day, full cushion available
            
        cushion_remaining = (self.current_equity - daily_loss_limit) / self.daily_start_equity
        return max(0.0, cushion_remaining)

    def check_kill_switch(self):
        """Returns True if the engine must be forcefully halted."""
        daily_loss = (self.daily_start_equity - self.current_equity) / self.daily_start_equity
        total_loss = (self.initial_balance - self.current_equity) / self.initial_balance

        if daily_loss >= self.KILL_DAILY_DD_PCT:
            print(f"[FATAL] DAILY RISK BREACH IMMINENT: {daily_loss*100:.2f}%. SEVERING ALL POSITIONS.")
            return True
            
        # FTMO Max Drawdown is static based on initial balance (except for trailing rules on some firms)
        if total_loss >= 0.098:
            print(f"[FATAL] ABSOLUTE RISK BREACH IMMINENT: {total_loss*100:.2f}%. SEVERING ALL POSITIONS.")
            return True
            
        return False

# Example War Room Execution
if __name__ == "__main__":
    sentinel = FTMORiskSentinel(initial_balance=200000)
    
    print("[SENTINEL] Booting FTMO Risk Matrix...")
    print(f"[SENTINEL] Initial Balance: ${sentinel.initial_balance}")
    print(f"[SENTINEL] Baseline Scaling Target (10%): ${sentinel.initial_balance * 1.10}\n")
    
    # Simulate an edge (60% win rate, 1.5 Reward:Risk)
    k_fraction = sentinel.calculate_kelly_fraction(win_rate=0.60, win_loss_ratio=1.5)
    print(f"[MATH] Current Kelly Risk Fraction: {k_fraction*100:.2f}% per trade")
# daily loss circuit breaker
