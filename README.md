# KESSLER: Institutional Risk & Execution Engine

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Status](https://img.shields.io/badge/Status-Operational-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Native_Zig-orange)

Kessler is a high-frequency algorithmic risk management and execution engine designed explicitly for institutional index trading (NAS100/US100). 

It operates by physically decoupling the trading logic from standard retail terminals. At its core, Kessler runs a **Twin Delayed DDPG (TD3)** reinforcement learning architecture, written entirely from scratch in native Zig, bypassing heavy ML frameworks like PyTorch or TensorFlow for absolute zero-latency execution.

## The Architecture (Kessler V3)

Kessler utilizes a hyper-optimized, low-level execution topology:

1. **The Native Zig Tensor Engine (`ml_native.zig`)**: A custom-built matrix multiplication and neural network library. It features custom SIMD-optimized dense layers, Adam optimizers, and a continuous-action space policy gradient.
2. **The Crucible (`k2_crucible.zig`)**: The RL training harness. It simulates millions of ticks of level-2 order flow (CVD, Z-Scores) across thousands of epochs.
3. **The Reward Function (Differential Sharpe Ratio)**: Kessler does not optimize for maximum profit. It optimizes for the smoothest equity curve, strictly enforcing the drawdown rules of proprietary trading firms (Funding Pips, FTMO) via a penalty matrix.

## Enterprise Features

* **Zero-Dependency ML**: No Python. No CUDA. No PyTorch. The neural network forward and backward passes are written in raw Zig, ensuring maximum CPU utilization and no garbage collection pauses.
* **Prop-Firm Compliance Matrix**: Natively designed to pass proprietary trading firm challenges. The TD3 agent is penalized heavily for touching the 3% Daily or 8% Overall drawdown limits.
* **Wyckoff Order Flow Ingestion**: The input state is not just price. It is a 6-dimensional vector including Delta, Cumulative Volume Delta (CVD), and normalized Z-Scores, mapping exactly to Wyckoff institutional accumulation/distribution phases.

## Component Breakdown

* `src/ml_native.zig`: The core Machine Learning mathematical engine and TD3 Agent.
* `src/k2_crucible.zig`: The 3000-Epoch training loop and deterministic holdout validator.
* `kessler_daemon.py`: The legacy Python tracking engine (currently being phased out for the native Zig compiler).

## Disclaimer
This software is built for private institutional execution. Use at your own risk. Past performance does not guarantee future results.
