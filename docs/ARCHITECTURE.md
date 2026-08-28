# SYSTEM ARCHITECTURE

Project Kessler is engineered in Zig 0.16.0 to operate directly on the metal. Built for quantitative hedge funds and institutional risk teams, it is designed to maximize L1/L2 cache hit rates and bypass standard library bloat for ultra-low latency execution.

## 1. Struct of Arrays (SoA)
Agents are not defined as objects. Agent data is stripped into parallel, 64-byte aligned arrays (`cash`, `theta`, `is_defaulted`, `neighbors`). This ensures hardware prefetchers can load consecutive memory into CPU cache lines without false sharing or pointer chasing.

## 2. Lock-Free SPSC Queues (`mail.zig`)
Order intents are passed from agent threads to the Central Order Book (`bazaar.zig`) using Single-Producer Single-Consumer (SPSC) lock-free ring buffers. We bypass mutexes entirely. Threads never block; they only spin.

## 3. The 10-Phase Tick Loop (`pulse.zig`)
Every microsecond tick is strictly ordered to prevent race conditions and ensure determinism:
1. Sentiment Update (Herd Behavior / Hawkes Decay)
2. Intent Generation
3. Lock-Free Mail Routing
4. Order Book Aggregation & Clearing
5. Mark-to-Market Revaluation
6. Regulatory Capital Checks (Forced Selling)
7. Gai-Kapadia Solvency Loop
8. Telemetry Logging
9. Stylized Fact Computation (End of Run)

## 4. Bare Metal Compatibility
Because Kessler can optionally bypass `libc` (relying only on raw system calls or simplified I/O interfaces), it is theoretically capable of being flashed onto embedded hardware or secure enclaves (TEE) for air-gapped institutional deployments.
