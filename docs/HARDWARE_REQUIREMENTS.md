# HARDWARE TARGETS: FROM DELL TO THE ENCLAVE

Project Kessler is optimized for the hardware it's running on, scaling from entry-level laptops to custom-built racks.

## Tier 1: The "Vibecode" Machine (Dell Latitude / MacBook Air)
- **Target:** Prototyping and Scenario Drafting.
- **Capacity:** 1k - 10k Agents.
- **Optimization:** Focus on L3 cache hits. Kessler uses the `stash.zig` arena to ensure the entire agent state stays within the CPU's Last Level Cache (LLC) whenever possible.

## Tier 2: The Quant Rig (Threadripper / Mac Studio)
- **Target:** Large-scale Parameter Sweeps.
- **Capacity:** 100k - 500k Agents.
- **Optimization:** Parallel execution via `pulse.zig` thread-pooling. Kessler leverages SIMD (Single Instruction, Multiple Data) instructions to process agent sentiment updates in parallel blocks.

## Tier 3: The Kessler Box (Custom FPGA / ASIC / Enclave)
- **Target:** Real-time Shadow-Market Monitoring.
- **Capacity:** 10M+ Agents.
- **Optimization:** At this scale, Kessler bypasses the OS kernel entirely. Future versions target custom FPGA bitstreams where the **Gai-Kapadia Loop** is implemented directly in hardware gates for nanosecond-level risk assessments.

**Note on Memory:** Project Kessler is CPU-bound, not RAM-bound. Because we use a **Struct of Arrays (SoA)** layout, we prioritize memory bandwidth over raw capacity.
