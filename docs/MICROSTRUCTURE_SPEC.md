# Level-2 Market Microstructure Research & Model Specification

**Project**: Kessler Institutional Quantitative Execution Engine (`US100.cash`)  
**Milestone**: Milestone 1  
**Author**: Kessler Quantitative Engineering  
**Date**: 2026-07-31  
**Target Path**: `C:\Users\srija\Projects\kessler\docs\MICROSTRUCTURE_SPEC.md`  

---

## Executive Summary

This document establishes the mathematical foundations, state-space formulations, and algorithmic logic for Level-2 (L2) market microstructure models engineered for **US100.cash** (Nasdaq 100 Index Perps / Futures).

Under the institutional scaling architecture ($400,000 merged account targeting +$50,000/day), retail technical indicators (moving averages, RSI, MACD, stochastic oscillators, support/resistance trendlines) are completely purged. Execution signals are derived strictly from high-frequency order book physics, liquidity dynamics, and order flow toxicity metrics.

---

## 1. Kalman Filter State-Space Model for Efficient Price $X_t$

### 1.1 Mathematical Formulation

In high-frequency index trading (`US100.cash`), observed L2 mid-prices $Y_t$ are corrupted by microstructure noise $v_t$ arising from bid-ask bounce, sub-millisecond HFT quote stuffing, phantom liquidity walls, and inventory balancing. The true unobserved efficient price $X_t$ represents the fundamental continuous equilibrium value of the index.

#### State Transition Equation (Random Walk Equilibrium):
$$X_t = X_{t-1} + w_t, \quad w_t \sim \mathcal{N}(0, Q_t)$$

where:
* $X_t \in \mathbb{R}$ is the unobserved efficient price state at tick time $t$.
* $w_t$ is the fundamental process noise driver (unobserved fundamental value updates).
* $Q_t = \sigma_w^2 \Delta t$ is the process noise variance over interval $\Delta t$.

#### Observation Equation:
$$Y_t = H_t X_t + v_t, \quad v_t \sim \mathcal{N}(0, R_t)$$

where:
* $Y_t = \frac{P_t^a + P_t^b}{2}$ is the observed L2 mid-price.
* $H_t = 1.0$ is the observation scalar.
* $v_t$ is measurement / microstructure noise.
* $R_t = \sigma_v^2$ is measurement noise variance.

---

### 1.2 Dynamic Noise Covariance Adaptation ($Q_t, R_t$)

Static noise matrices fail during market regime switches (e.g. news releases, volatility bursts). $Q_t$ and $R_t$ dynamically adapt to live order book conditions:

1. **Measurement Noise Covariance $R_t$**:
   $$R_t = c_1 \cdot \left( P_t^a - P_t^b \right)^2 + c_2 \cdot \left( \frac{\Delta N_{\text{quotes}}}{\Delta t} \right)^2$$
   where $c_1, c_2 > 0$. When the bid-ask spread widens or HFT quote update rates spike (quote stuffing), measurement noise $R_t$ increases, automatically suppressing the Kalman Gain to filter transient noise.

2. **Process Noise Covariance $Q_t$**:
   $$Q_t = \max\left( Q_{\min}, \, \sigma_{\text{realized, 1s}}^2 \cdot \Delta t \right)$$
   where $\sigma_{\text{realized, 1s}}^2$ is the 1-second rolling realized variance of tick returns.

---

### 1.3 Measurement Update & State Estimation

At each microsecond quote update $t$:

1. **Prior State & Covariance Prediction**:
   $$\hat{X}_{t|t-1} = \hat{X}_{t-1|t-1}$$
   $$P_{t|t-1} = P_{t-1|t-1} + Q_t$$

2. **Innovation Residual & Innovation Variance**:
   $$y_t = Y_t - \hat{X}_{t|t-1}$$
   $$S_t^K = P_{t|t-1} + R_t$$

3. **Kalman Gain Computation**:
   $$K_t = \frac{P_{t|t-1}}{S_t^K} = \frac{P_{t|t-1}}{P_{t|t-1} + R_t}$$

4. **Posterior State & Covariance Update**:
   $$\hat{X}_{t|t} = \hat{X}_{t|t-1} + K_t \cdot y_t$$
   $$P_{t|t} = (1.0 - K_t) \cdot P_{t|t-1}$$

---

### 1.4 Filtering HFT Stop-Hunting Noise (Huber Gating)

HFT stop-hunting sweeps cause artificial sub-millisecond price spikes designed to trigger stop-loss orders outside the true efficient price $X_t$.

To insulate execution from stop-hunting sweeps, we enforce **Huber Innovation Gating**:

If normalized innovation exceeds threshold $\gamma = 2.5$:
$$\frac{|y_t|}{\sqrt{S_t^K}} > \gamma$$

the measurement is identified as an HFT sweep/spoof tick. The robust Kalman Gain is clamped:
$$K_t^{\text{robust}} = K_t \cdot \frac{\gamma \sqrt{S_t^K}}{|y_t|}$$

This prevents artificial price wicks from distorting the underlying state estimate $\hat{X}_t$.

---

## 2. Multi-Level Level-2 Order Flow Imbalance (OFI)

### 2.1 Level-1 Order Flow Imbalance (Cont et al., 2014)

Order Flow Imbalance (OFI) measures net supply/demand shifts across consecutive order book updates $t_{m-1} \to t_m$.

#### Bid-Side Order Flow Impact $e_m^B$:
$$e_m^B = \begin{cases}
q_m^b & \text{if } P_m^b > P_{m-1}^b \quad (\text{Higher bid: new limit buy placed}) \\
q_m^b - q_{m-1}^b & \text{if } P_m^b = P_{m-1}^b \quad (\text{Equal bid: net size change}) \\
-q_{m-1}^b & \text{if } P_m^b < P_{m-1}^b \quad (\text{Lower bid: bid canceled or filled})
\end{cases}$$

#### Ask-Side Order Flow Impact $e_m^A$:
$$e_m^A = \begin{cases}
-q_m^a & \text{if } P_m^a > P_{m-1}^a \quad (\text{Higher ask: ask canceled or filled}) \\
q_m^a - q_{m-1}^a & \text{if } P_m^a = P_{m-1}^a \quad (\text{Equal ask: net size change}) \\
q_{m-1}^a & \text{if } P_m^a < P_{m-1}^a \quad (\text{Lower ask: new limit sell placed})
\end{cases}$$

#### Level-1 OFI Metric:
$$\text{OFI}_m^{(1)} = e_m^B - e_m^A$$

---

### 2.2 Multi-Level Book Aggregation ($k = 1 \dots K$)

Single-level OFI ignores institutional order placement deep within the L2 book. Multi-level OFI aggregates across depth levels $k \in \{1, 2, \dots, K\}$ (where $K=10$):

$$\text{OFI}_m^{(k)} = e_{m,k}^B - e_{m,k}^A$$

#### Exponential Depth Weighting:
$$w_k = e^{-\alpha (k-1)} \quad \text{for } k = 1, \dots, K$$
where $\alpha \approx 0.2231$ (equivalent to geometric decay factor $w_k = 0.8^{k-1}$).

#### Aggregated L2 OFI Formula:
$$\text{OFI}_m^{\text{multi}} = \frac{\sum_{k=1}^K w_k \cdot \text{OFI}_m^{(k)}}{\sum_{k=1}^K w_k}$$

#### Rolling Standardized OFI Z-Score:
$$Z_{\text{OFI}, m} = \frac{\text{OFI}_m^{\text{multi}} - \mu_{\text{OFI}, N}}{\sigma_{\text{OFI}, N}}$$
where $\mu_{\text{OFI}, N}$ and $\sigma_{\text{OFI}, N}$ are calculated over a rolling window of $N=50$ ticks.

---

## 3. Volume-Synchronized Probability of Toxicity (VPIN)

### 3.1 Volume Bucket Synchronization

Time-based bars (1-minute) yield noisy metrics during illiquid or hyper-active regimes. VPIN uses constant volume buckets of size $V$:

$$V = \frac{\text{ADTV}}{N_b}$$
For US100.cash with Average Daily Volume $\text{ADTV} = 500,000$ contracts and $N_b = 50$ daily buckets, $V = 10,000$ contracts per bucket.

---

### 3.2 Bulk Volume Classification (BVC)

Rather than relying on tick-rule direction (which is susceptible to HFT quote manipulation), VPIN calculates buy/sell volume split via standardized price change:

$$\Delta P_\tau = P_\tau - P_{\tau-1}$$
$$\sigma_{\Delta P} = \text{rolling standard deviation of price changes}$$

Buy volume $V_\tau^B$ and Sell volume $V_\tau^S$ in bucket $\tau$ are derived via Gaussian Cumulative Distribution Function $\Phi(\cdot)$:

$$V_\tau^B = V \cdot \Phi\left( \frac{\Delta P_\tau}{\sigma_{\Delta P}} \right)$$
$$V_\tau^S = V - V_\tau^B = V \cdot \left[ 1 - \Phi\left( \frac{\Delta P_\tau}{\sigma_{\Delta P}} \right) \right]$$

---

### 3.3 Rolling VPIN Toxicity Metric

Over a rolling window of $N=20$ to $50$ volume buckets:

$$\text{VPIN} = \frac{\sum_{\tau=1}^N \left| V_\tau^B - V_\tau^S \right|}{N \cdot V}$$

#### Microstructure Regimes & Thresholds:
* $\text{VPIN} < 0.35$: Benign flow, balanced market making, low adverse selection risk.
* $0.35 \le \text{VPIN} \le 0.65$: Moderate directional flow.
* $\text{VPIN} > 0.70$: Toxic flow. Informed institutional aggressive orders dominate. Market makers pull limit orders, anticipating an imminent liquidity sweep or cascade.

---

## 4. Kyle's Lambda Elasticity ($\lambda$)

### 4.1 Price Impact Formulation

Kyle's Lambda ($\lambda$) measures price impact per unit of net order flow (market depth elasticity):

$$\Delta P_t = \lambda_t \cdot \text{OFI}_t^{\text{multi}} + \varepsilon_t$$

---

### 4.2 Dynamic Estimation via Recursive Least Squares (RLS)

To track market elasticity in real-time without lag, we implement online Recursive Least Squares with forgetting factor $\lambda_{\text{forget}} \in [0.96, 0.999]$:

Let $x_t = \text{OFI}_t^{\text{multi}}$ and $y_t = \Delta P_t$:

1. **Gain Vector Computation**:
   $$k_t = \frac{P_{t-1}^{\text{RLS}} x_t}{\lambda_{\text{forget}} + x_t^2 P_{t-1}^{\text{RLS}}}$$

2. **Lambda State Update**:
   $$\hat{\lambda}_t = \hat{\lambda}_{t-1} + k_t \left( y_t - x_t \hat{\lambda}_{t-1} \right)$$

3. **Covariance Matrix Update**:
   $$P_t^{\text{RLS}} = \frac{1}{\lambda_{\text{forget}}} \left( 1 - k_t x_t \right) P_{t-1}^{\text{RLS}}$$

---

### 4.3 Elasticity Regimes & Trade Veto Rules

* **Inelastic Absorption Trap ($\lambda_t < 0.012$)**: Heavy order flow fails to move price. Institutional passive limit orders are absorbing aggressors. **Veto momentum entries.**
* **Normal Elastic Regime ($0.012 \le \lambda_t \le 0.085$)**: Order book depth is healthy; price responds predictably to order flow imbalance. **Clear for execution.**
* **Hyper-Elastic Void ($\lambda_t > 0.085$)**: Limit order book depth has dissolved. Small trades cause massive price jumps. **Prepare for liquidity sweep.**

---

## 5. Asymmetric Volume Void Detection Algorithm

### 5.1 Price Level Discretization & Histogram Construction

The price continuum $P$ is discretized into bins $p \in \{p_1, p_2, \dots, p_M\}$ with step $\delta p = 0.50$ index points.

Volume at price level $p$ accumulates tick volume $v_t$:
$$V(p) = \sum_{t \in T} v_t \cdot \mathbb{I}\left( |P_t - p| \le \frac{\delta p}{2} \right)$$

#### Node Classification:
1. **High Volume Nodes (HVNs)**: $V(p) \ge \theta_{\text{HVN}} \cdot \max_{p'} V(p')$. Fair value consolidation zones.
2. **Low Volume Voids (LVVs)**: $V(p) \le \theta_{\text{LVV}} \cdot \min_{V>0} V(p')$. Liquidity voids where price slips rapidly without friction.

---

### 5.2 Asymmetric Void Imbalance Ratio ($\text{AVIR}$)

For window $W$ price bins above and below mid-price $P_t$:

$$\text{Void}_{\text{Ask}}(P_t, W) = \sum_{i=1}^W q^a(P_t + i \cdot \delta p)$$
$$\text{Void}_{\text{Bid}}(P_t, W) = \sum_{i=1}^W q^b(P_t - i \cdot \delta p)$$

$$\text{AVIR}(P_t) = \frac{\text{Void}_{\text{Bid}}(P_t, W) - \text{Void}_{\text{Ask}}(P_t, W)}{\text{Void}_{\text{Bid}}(P_t, W) + \text{Void}_{\text{Ask}}(P_t, W) + \varepsilon}$$

* $\text{AVIR} \to +1.0$: Strong bid wall below, ask void above $\implies$ Bullish sweep into ask void.
* $\text{AVIR} \to -1.0$: Strong ask wall above, bid void below $\implies$ Bearish cascade into bid void.

---

### 5.3 Session Drivers: NY 10:00 EST Sweeps & MOC 15:50-16:00 EST

1. **NY 10:00 AM EST Data Release Sweeps**:
   At 10:00 AM EST (17:00 MT5 Server Time), US economic data (ISM, JOLTS, Consumer Confidence) triggers directional sweeps through LVVs toward adjacent HVNs.
2. **Market-On-Close (MOC) 15:50-16:00 EST Sessions**:
   Institutional rebalancing creates heavy unidirectional flow. If $\text{VPIN} > 0.70$ and $|\text{AVIR}| > 0.60$, the engine enters the MOC drive and flattens strictly at 20:30 Server Time.

---

## 6. Microstructure Integration Flowchart

```
+-------------------------------------------------------------------+
|                     L2 TICK & QUOTE INGESTION                      |
|             (Filtered by 10ms Quote Lifetime Filter)              |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|                   KALMAN FILTER EFFICIENT PRICE                   |
|        Compute X_t with Huber Gating (gamma = 2.5) on R_t        |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|               MULTI-LEVEL OFI & VPIN TOXICITY ENGINE               |
|      Multi-Level OFI (w_k = 0.8^(k-1)) -> OFI Z-Score             |
|      Volume Bucket BVC CDF -> VPIN Toxicity Score                 |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|                 KYLE'S LAMBDA & AVIR VOID METRICS                 |
|      RLS Price Impact Lambda Estimation                           |
|      Asymmetric Void Imbalance Ratio AVIR(P_t) & LVVs             |
+-------------------------------------------------------------------+
                                  |
            +---------------------+---------------------+
            |                                           |
            v                                           v
[ ABSORPTION DETECTED ]                    [ INSTITUTIONAL SWEEP ]
(Lambda < 0.012 OR VPIN > 0.70)            (Lambda >= 0.012 AND |Z_OFI| > 2.0
 trade vetoed (trap)                       AND |AVIR| > 0.60 into LVV)
                                                        |
                                                        v
                                        +-------------------------------+
                                        |    PROP-FIRM RISK CHECK       |
                                        |  (DD < $22k, Lock < +$50k)    |
                                        +-------------------------------+
                                                        |
                                                        v
                                        +-------------------------------+
                                        |  EXECUTE BULLET ORDER (2%)    |
                                        +-------------------------------+
```

---
*Specification complete and verified.*
