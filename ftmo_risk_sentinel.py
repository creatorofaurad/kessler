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

# commit step 3: 917

# commit step 13: 543

# commit step 15: 426

# commit step 19: 137

# commit step 22: 525

# commit step 29: 143

# commit step 41: 819

# commit step 48: 110

# commit step 54: 903

# commit step 63: 138

# commit step 66: 680

# commit step 77: 753

# commit step 84: 134

# commit step 87: 217

# commit step 95: 387

# commit step 103: 831

# commit step 105: 265

# commit step 106: 786

# commit step 107: 421

# commit step 109: 931

# commit step 115: 864

# commit step 120: 796

# commit step 129: 291

# commit step 130: 216

# commit step 138: 192

# commit step 140: 599

# commit step 167: 246

# commit step 169: 761

# commit step 173: 117

# commit step 183: 710

# commit step 188: 208

# commit step 194: 718

# commit step 197: 888

# commit step 198: 519

# commit step 201: 742

# commit step 207: 253

# commit step 208: 873

# commit step 209: 748

# commit step 210: 633

# commit step 214: 191

# commit step 215: 957

# commit step 221: 577

# commit step 224: 387

# commit step 225: 631

# commit step 226: 483

# commit step 235: 787

# commit step 236: 321

# kessler step 1: 649

# kessler step 3: 682

# kessler step 4: 461

# kessler step 6: 887

# commit step 245: 747

# commit step 251: 972

# kessler step 17: 586

# kessler step 23: 803

# commit step 263: 800

# commit step 268: 135

# commit step 269: 513

# kessler step 31: 716

# kessler step 32: 644

# kessler step 39: 477

# kessler step 40: 905

# commit step 280: 718

# kessler step 44: 852

# commit step 284: 306

# commit step 288: 156

# kessler step 52: 198

# kessler step 54: 621

# commit step 295: 744

# kessler step 59: 949

# commit step 298: 642

# commit step 306: 437

# commit step 310: 971

# kessler step 76: 789

# kessler step 81: 203

# commit step 321: 161

# commit step 324: 751

# kessler step 88: 381

# commit step 328: 226

# kessler step 93: 865

# commit step 341: 366

# kessler step 105: 776

# kessler step 106: 686

# kessler step 107: 589

# commit step 345: 411

# commit step 350: 318

# kessler step 114: 602

# commit step 355: 664

# kessler step 118: 249

# commit step 356: 179

# commit step 358: 776

# commit step 364: 250

# kessler step 127: 834

# kessler step 134: 791

# commit step 373: 428

# commit step 374: 355

# kessler step 139: 837

# kessler step 142: 748

# kessler step 158: 662

# kessler step 163: 623

# commit step 401: 961

# kessler step 2: 382

# kessler step 6: 468

# commit step 412: 478

# commit step 414: 658

# kessler step 11: 487

# kessler step 177: 715

# commit step 416: 643

# kessler step 14: 294

# kessler step 17: 404

# kessler step 182: 292

# kessler step 19: 273

# kessler step 26: 997

# kessler step 196: 469

# kessler step 37: 953

# kessler step 207: 721

# kessler step 43: 390

# kessler step 45: 996

# kessler step 47: 964

# commit step 452: 615

# kessler step 50: 124

# kessler step 216: 934

# kessler step 51: 452

# commit step 456: 480

# kessler step 222: 384

# commit step 462: 394

# kessler step 59: 740

# kessler step 225: 310

# kessler step 61: 711

# kessler step 230: 697

# kessler step 240: 948

# kessler step 75: 926

# commit step 479: 983

# commit step 483: 621

# kessler step 245: 819

# commit step 484: 656

# kessler step 246: 500

# kessler step 81: 411

# kessler step 83: 106

# kessler step 84: 918

# kessler step 250: 235

# kessler step 251: 535

# kessler step 93: 934

# kessler step 266: 241

# kessler step 267: 172

# commit step 507: 193

# kessler step 271: 532

# commit step 510: 215

# kessler step 108: 591

# kessler step 112: 941

# commit step 519: 887

# kessler step 116: 323

# kessler step 117: 599

# commit step 522: 760

# kessler step 286: 468

# kessler step 291: 194

# kessler step 292: 696

# kessler step 4: 793

# kessler step 11: 402
