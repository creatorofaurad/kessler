# PROOF OF DETERMINISTIC REPLAY

## The Axiom
A systemic risk oracle that yields different results for the same initial conditions is not an oracle; it is a random number generator. Traditional monte carlo engines suffer from thread-scheduling drift and OS-level memory fragmentation. Project Kessler guarantees bit-for-bit deterministic replays across any x86_64 or ARM64 silicon.

## The Entropy Architecture
1. **The ASLR Hack (Chaos Mode):** By default, Kessler harvests entropy by casting the memory address of a stack-allocated dummy variable into a `u64`. Because modern operating systems use Address Space Layout Randomization (ASLR), this guarantees a cryptographically unique starting seed for every unconfigured run. 
2. **Fixed-Seed Strictness:** When a seed is explicitly passed (e.g., `Seed 42`), the ASLR harvest is bypassed. 
3. **Zero Heap Allocations Post-Init:** The `stash.zig` arena allocates the entire SoA (Struct of Arrays) topology before `tick = 0`. During the hot loop, Kessler never calls the OS allocator. Memory layouts remain rigidly fixed, eliminating non-deterministic heap fragmentation.

## IEEE 754 Adherence
To ensure floating-point math remains deterministic across CPU architectures, Kessler strictly avoids non-associative parallel reductions (e.g., unordered thread summations). Herd behavior and price impacts are aggregated sequentially or via deterministic chunking.

**Conclusion:** A flash crash triggered at `tick 583` on an 8GB Dell Latitude will trigger at the exact same microsecond on a 128-core AWS Graviton instance. Unbreakable replayability.
