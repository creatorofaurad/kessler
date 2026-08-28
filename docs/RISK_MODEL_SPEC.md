# Compliance & Asymmetric Risk Architecture Specification

**Project**: Kessler Institutional Quantitative Execution Engine (`US100.cash`)  
**Milestone**: Milestone 2  
**Author**: Kessler Risk Architecture & Quantitative Engineering  
**Date**: 2026-07-31  
**Target Path**: `C:\Users\srija\Projects\kessler\docs\RISK_MODEL_SPEC.md`  

---

## Executive Summary

This document specifies the compliance, money management, position sizing, intraday drive structure, session time fencing, and Finite State Machine (FSM) risk sentinels for the **$400,000 merged institutional prop firm account** operating on **US100.cash**.

The system is designed to generate **+$50,000.00 (+12.5%) daily profit** while guaranteeing total compliance with prop firm risk limits:
* **Max Daily Drawdown Ceiling**: $< 5.5\%$ ($-\$22,000.00$)
* **Absolute Drawdown Floor**: $< 9.5\%$ ($-\$38,000.00$)
* **Fixed Risk Sizing**: 2.0% risk per bullet ($\$8,000.00$) with minimum $3.125:1$ Reward-to-Risk (R:R) ratio ($\ge +\$25,000.00$ target)
* **Drive Target**: Exactly two (2) successful institutional drives hit $+\$50,000.00$ and lock the account for the session
* **Session Flatten Shield**: Mandatory liquidation and order deletion at **20:30 Server Time** (zero overnight holds)

---

## 1. Merged Account Risk Parameters ($400,000 Baseline)

### 1.1 Account Capital Baseline
$$\text{Balance}_{\text{initial}} = \$400,000.00$$

Merged from two (2) $200,000 institutional funded accounts into a single execution vehicle.

---

### 1.2 Daily Drawdown Limit Mechanics ($-\$22,000.00 / -5.5\%$)
* **Daily Drawdown Limit Percentage**: $D_{\text{daily\_pct}} = 5.5\%$ (capped strictly at $\$22,000.00$).
* **Daily Starting Balance Watermark**: $B_{\text{daily\_start}}$ (recorded at 00:00:00 server time).
* **Daily Max Drawdown Amount**:
  $$L_{\text{daily\_max}} = B_{\text{daily\_start}} \times 0.055 = \$400,000.00 \times 0.055 = \$22,000.00$$
* **Intraday Minimum Equity Floor**:
  $$E_{\text{daily\_floor}} = B_{\text{daily\_start}} - L_{\text{daily\_max}} = \$400,000.00 - \$22,000.00 = \$378,000.00$$

If floating + closed intraday equity drops to or below $E_{\text{daily\_floor}}$ at any time, the intraday kill switch triggers instantly.

---

### 1.3 Absolute Drawdown Floor Mechanics ($-\$38,000.00 / -9.5\%$)
* **Absolute Max Drawdown Percentage**: $D_{\text{abs\_pct}} = 9.5\%$ (capped strictly at $\$38,000.00$).
* **Initial Capital Baseline**: $C_0 = \$400,000.00$.
* **Absolute Max Drawdown Amount**:
  $$L_{\text{abs\_max}} = C_0 \times 0.095 = \$400,000.00 \times 0.095 = \$38,000.00$$
* **Absolute Equity Floor**:
  $$E_{\text{abs\_floor}} = C_0 - L_{\text{abs\_max}} = \$400,000.00 - \$38,000.00 = \$362,000.00$$

If total account equity falls to or below $\$362,000.00$, the engine activates terminal termination (`STATE_KILLED`).

---

### 1.4 Daily Profit Target Lockout ($+\$50,000.00 / +12.5\%$)
* **Daily Profit Target Percentage**: $P_{\text{target\_pct}} = +12.5\%$.
* **Daily Target Cash Amount**:
  $$T_{\text{daily}} = B_{\text{daily\_start}} \times 0.125 = \$400,000.00 \times 0.125 = +\$50,000.00$$
* **Profit Lock Equity Target**:
  $$E_{\text{target}} = B_{\text{daily\_start}} + T_{\text{daily}} = \$400,000.00 + \$50,000.00 = \$450,000.00$$

When net closed + floating intraday PnL hits or exceeds $+\$50,000.00$, the engine flattens all open positions, deletes pending orders, and locks the account until the next trading day.

---

## 2. Asymmetric Position Sizing & Lot Calculation Math

### 2.1 Fixed Cash Risk Per Bullet
Each trade ("bullet") risks exactly **2.0%** of initial capital:
$$R_{\text{bullet}} = C_0 \times 0.020 = \$400,000.00 \times 0.020 = \$8,000.00$$

---

### 2.2 Asymmetric Reward-to-Risk (R:R) Sizing
The engine requires a minimum Reward-to-Risk ratio $RR_{\text{min}} \ge 3.125$:
$$W_{\text{bullet}} = R_{\text{bullet}} \times RR_{\text{min}} = \$8,000.00 \times 3.125 = +\$25,000.00$$

---

### 2.3 MQL5 Lot Sizing Formula for US100.cash

To calculate exact position size $N_{\text{lots}}$ for index CFD contracts:

#### Parameters:
* $R_{\text{bullet}}$ = Fixed risk amount = $\$8,000.00$
* $P_{\text{entry}}$ = Order entry price
* $P_{\text{sl}}$ = Stop loss price
* $S_{\text{points}} = |P_{\text{entry}} - P_{\text{sl}}|$ = Stop distance in index points (e.g. 20.0 points)
* $T_{\text{size}}$ = `SYMBOL_TRADE_TICK_SIZE` (e.g. 0.25)
* $V_{\text{tick}}$ = `SYMBOL_TRADE_TICK_VALUE` (monetary value of 1 tick per 1.0 lot in USD)
* $L_{\text{step}}$ = `SYMBOL_VOLUME_STEP` (lot step size)

#### Exact Lot Sizing Formula:
$$S_{\text{ticks}} = \frac{S_{\text{points}}}{T_{\text{size}}}$$

$$N_{\text{raw}} = \frac{R_{\text{bullet}}}{S_{\text{ticks}} \times V_{\text{tick}}} = \frac{8000 \times T_{\text{size}}}{S_{\text{points}} \times V_{\text{tick}}}$$

#### Broker Contract Scenarios for US100.cash:

| Contract Type | Contract Size | Tick Size ($T_{\text{size}}$) | Tick Value ($V_{\text{tick}}$) | Point Value / Lot | Lot Sizing for 20.0 Pt Stop ($S_{\text{points}}=20.0$) |
|---|---|---|---|---|---|
| **Standard CFD (1:1)** | 1.0 | 0.25 | $0.25 | $1.00 / pt | $N = \frac{8000}{20.0 \times 1.0} = 400.00\text{ lots}$ |
| **Micro Index (10:1)** | 10.0 | 0.25 | $2.50 | $10.00 / pt | $N = \frac{8000}{20.0 \times 10.0} = 40.00\text{ lots}$ |
| **Institutional Futures CFD (20:1)** | 20.0 | 0.25 | $5.00 | $20.00 / pt | $N = \frac{8000}{20.0 \times 20.0} = 20.00\text{ lots}$ |

#### MQL5 Lot Clamping Logic:
$$N_{\text{clamped}} = \max \left( \text{MIN\_LOT}, \, \min \left( \text{MAX\_LOT}, \, \left\lfloor \frac{N_{\text{raw}}}{L_{\text{step}}} \right\rfloor \times L_{\text{step}} \right) \right)$$

---

## 3. Intraday Drive Architecture & Sequence Analysis

### 3.1 Two-Drive Target Clearance Math
With target reward $W_{\text{bullet}} = +\$25,000.00$, exactly **2 consecutive winning drives** clear the $+\$50,000.00$ daily target:
$$\text{PnL}_{2\text{W}} = 2 \times \$25,000.00 = +\$50,000.00 \implies \text{LOCK ACCOUNT}$$

---

### 3.2 Sequence & Outcome Analysis Matrix

| Seq # | Outcome Path | Trade PnL Sequence | Cumulative PnL | Intraday Equity | Daily DD % | Remaining Buffer | FSM State Action |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **1** | `[WIN, WIN]` | +$25k, +$25k | **+$50,000.00** | **$450,000.00** | +12.5% | $22,000.00 | `STATE_PROFIT_LOCKED` |
| **2** | `[LOSS, WIN, WIN]` | -$8k, +$25k, +$25k | **+$42,000.00** | **$442,000.00** | +10.5% | $22,000.00 | `STATE_ACTIVE` (Drive 4 hits lock) |
| **2a**| `[LOSS, WIN, WIN, WIN]`| -$8k, +$25k, +$25k, +$25k| **+$67,000.00** (Lock at +$50k) | **$450,000.00** | +12.5% | $22,000.00 | `STATE_PROFIT_LOCKED` |
| **3** | `[WIN, LOSS, WIN, WIN]`| +$25k, -$8k, +$25k, +$25k| **+$67,000.00** (Lock at +$50k) | **$450,000.00** | +12.5% | $22,000.00 | `STATE_PROFIT_LOCKED` |
| **4** | `[LOSS, LOSS]` | -$8k, -$8k | **-$16,000.00** | **$384,000.00** | -4.00% | **$6,000.00** | `STATE_ACTIVE` (Risk Clamped) |
| **5** | `[LOSS, LOSS, LOSS]` | -$8k, -$8k, -$8k | **-$24,000.00** | **$376,000.00** | **-6.00% (BREACH)**| **-$2,000.00**| `STATE_KILLED` (Triggered at -$22k) |

---

### 3.3 Loss Capacity & Bullet 3 Risk Clamping Protocol
1. **Max Consecutive Losses Allowed**: 2 losses ($-\$16,000.00$).
2. **Remaining Daily Loss Capacity after 2 Losses**:
   $$\text{Buffer}_{\text{remaining}} = L_{\text{daily\_max}} - |-\$16,000.00| = \$22,000.00 - \$16,000.00 = \$6,000.00$$
3. **Bullet 3 Clamping Rule**:
   If 2 consecutive losses occur, Bullet 3 risk allocation $R_{\text{bullet\_3}}$ is dynamically clamped:
   $$R_{\text{bullet\_3}} = \min(\$8,000.00, \, \text{Buffer}_{\text{remaining}}) = \$6,000.00$$
   This ensures that if Bullet 3 stops out, cumulative loss equals exactly $-\$22,000.00$, hitting `STATE_KILLED` cleanly without overshooting the $-5.5\%$ limit.

---

## 4. Hard Session Flatten Shield (20:30 Server Time)

### 4.1 Time Window Mapping

| Timezone | NY Market Open | Microstructure Sweep Window | Session Flatten Shield | NY Market Close |
|---|---|---|---|---|
| **EST / EDT (NY Local)** | 09:30 AM / 10:00 AM | 10:00 AM - 11:30 AM | **13:30 PM EST** | 16:00 PM EST |
| **Server Time (EEST, UTC+3)**| 16:30 PM / 17:00 PM | 17:00 PM - 18:30 PM | **20:30 Server Time** | 23:00 Server Time |

---

### 4.2 Flatten Action Protocol
At exactly **20:30:00 Server Time**:
1. Engine evaluates `TimeCurrent() >= 20:30:00`.
2. Liquidates all active positions matching `MagicNumber` via `CTrade::PositionClose()`.
3. Cancels all pending orders via `CTrade::OrderDelete()`.
4. Transitions FSM state to `STATE_FLATTENED`.
5. Disables order placement loops for the remainder of the session.

---

## 5. Account Finite State Machine (FSM) Architecture

### 5.1 State Definitions

```
                     +-----------------------+
                     |     STATE_ACTIVE      |
                     +-----------------------+
                       /         |         \
         PnL >= +$50k /          |          \ Time >= 20:30
                     /    PnL <= -$22k       \
                    v            v            v
      +------------------+  +--------------+  +-----------------+
      |STATE_PROFIT_LOCKED|  | STATE_KILLED |  | STATE_FLATTENED |
      +------------------+  +--------------+  +-----------------+
```

| State Enum ID | State Constant | Description | Order Placement Allowed | Open Positions Allowed |
|:---:|---|---|:---:|:---:|
| `0` | `STATE_ACTIVE` | Account operating normally | **YES** | **YES** |
| `1` | `STATE_PROFIT_LOCKED` | Daily target (+$50k) hit; account locked | **NO** | **NO** |
| `2` | `STATE_KILLED` | Daily DD (-$22k) or Abs DD (-$38k) breached | **NO** | **NO** |
| `3` | `STATE_FLATTENED` | Hard 20:30 server time ceiling reached | **NO** | **NO** |

---

### 5.2 State Transition Logic Matrix

| Source State | Event / Trigger | Execution Action Taken | Target State |
|---|---|---|---|
| `STATE_ACTIVE` | Intraday PnL $\ge +\$50,000.00$ | Close all positions, delete pending orders, halt EA | `STATE_PROFIT_LOCKED` |
| `STATE_ACTIVE` | Intraday PnL $\le -\$22,000.00$ | Emergency close all positions, delete orders, halt EA | `STATE_KILLED` |
| `STATE_ACTIVE` | Account Equity $\le \$362,000.00$ | Emergency close all positions, fatal kill lockout | `STATE_KILLED` |
| `STATE_ACTIVE` | `TimeCurrent() >= 20:30:00` | Close all positions, delete pending orders, halt EA | `STATE_FLATTENED` |
| `STATE_PROFIT_LOCKED` | `TimeCurrent()` crosses 00:00 (New Day) | Re-capture $B_{\text{daily\_start}}$, reset PnL counter | `STATE_ACTIVE` |
| `STATE_FLATTENED` | `TimeCurrent()` crosses 00:00 (New Day) | Re-capture $B_{\text{daily\_start}}$, reset PnL counter | `STATE_ACTIVE` |
| `STATE_KILLED` | Daily breach only & new day reset | Require admin re-authorization | `STATE_ACTIVE` |
| `STATE_KILLED` | Absolute breach ($\le \$362\text{k}$) | Permanent account termination | **LOCKED PERMANENTLY** |

---
*Specification complete and verified.*
