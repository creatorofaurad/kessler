# CHANGELOG: THE EVOLUTION OF KESSLER

## v0.4.0 - The "Gai-Kapadia" Build (Current)
- **Engine:** Ported to Zig 0.16.0 with a "Zero-Heap" hot path.
- **Physics:** Implemented the Gai-Kapadia contagion loop and Hawkes self-exciting defaults.
- **Microstructure:** Added Kyle's Lambda and VPIN toxicity tracking.
- **Deployment:** Standardized project scaffold with CI/CD and enterprise documentation.

## v0.3.0 - Multi-threaded Sentiment
- **Performance:** Implemented thread-pooling for agent sentiment updates.
- **Architecture:** Introduced `stash.zig` for arena-based memory management.
- **Determinism:** Fixed a critical bug in thread-scheduling that caused seed-drift.

## v0.2.0 - The "Bazaar" Update
- **Markets:** Replaced a simple price-walk with a proper Order Book (`bazaar.zig`).
- **Networking:** Added the initial `gossip.zig` module for neighbor-based herd behavior.

## v0.1.0 - The First Spark
- Initial "Vibecode" implementation. 
- Basic agent-based simulation in Python (later discarded for performance reasons).
- Proof of concept for ASLR-based entropy seeding.
