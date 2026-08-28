# INSTITUTIONAL SECURITY & INTEGRITY

Project Kessler is designed for high-trust, air-gapped environments. 

## 1. Zero-Trust Architecture
- **No Phoning Home:** Kessler has zero networking code in the core engine. All data is ingested via local `config/` files and exported via local `stdout` or CSV.
- **Static Linking:** By default, Kessler compiles to a static binary. It does not rely on external shared libraries that can be hijacked via `LD_PRELOAD`.

## 2. Execution Integrity
- **Deterministic Hashing:** Every simulation run generates a unique SHA-256 hash of the final state. Two different Kessler instances running the same seed MUST produce the same hash. Any deviation indicates hardware failure or bit-flipping (cosmic rays/tampering).
- **TEE Readiness:** The memory-safety of Zig and the "Zero-Allocation" tick loop make Kessler an ideal candidate for **Intel SGX** or **AWS Nitro Enclaves**. You can run the oracle in a "black box" where even the cloud provider cannot see the simulation parameters.

## 3. Auditability
The "Vibecode" philosophy is balanced by "Direct-to-Metal" clarity. There are no hidden abstractions. A senior security auditor can trace an order from `mail.zig` through `bazaar.zig` to `diary.zig` without ever leaving the Kessler source tree.
