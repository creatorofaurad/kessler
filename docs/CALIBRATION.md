# CALIBRATION & PARAMETER TUNING

Project Kessler is a non-linear system. Small changes in micro-parameters lead to massive macro-level phase transitions. Use this guide to tune the oracle.

## 1. Agent Topology
- **`agent_count`**: Increasing this increases the resolution of the "glass economy." At 1,000 agents, you see localized shocks. At 1,000,000, you see systemic "Silence Waves."
- **`neighbor_count`**: Controls the "tightness" of the social graph. Higher counts increase the speed of **Herd Behavior** contagion.

## 2. Contagion Mechanics
- **Hawkes Intensity ($\lambda$):** If the market recovers too fast after a default, increase the `intensity_spike`. If the market enters an infinite death spiral too easily, increase the `decay_rate`.
- **Gai-Kapadia Sensitivity:** The threshold for deleveraging is currently set at 8% capital adequacy. Adjust this to simulate different regulatory environments (e.g., Basel III vs. shadow banking).

## 3. Market Microstructure
- **Kyle's Lambda:** Controls "Slippage." If large trades don't move the price enough, increase the base lambda. 
- **Hurst Parameter ($H$):** For **Rough Volatility**, $H < 0.5$ creates "anti-persistent" jagged spikes. Tuning $H$ closer to 0 makes the volatility more "explosive" and less predictable.

## 4. Calibration Workflow
1. Run a **Parameter Sweep** using `scripts/run_sweep.sh`.
2. Compare the output `kurtosis` and `vol_clustering` in `diary.zig` to historical data.
3. Use `scripts/calibrate.py` (ML-assisted) to back-fit parameters to a specific historical event, like the 2010 Flash Crash.
