# API & CONTROL INTERFACE

Project Kessler is controlled via the CLI and a set of internal hooks for real-time monitoring.

## CLI Parameters
While basic runs use the `main.zig` Control Panel, the binary supports the following raw flags for automated sweeps:

- `--seed <u64>`: Force a specific deterministic history.
- `--ticks <u32>`: Set simulation duration.
- `--agents <u32>`: Set population scale (default: 1000).
- `--config <path>`: Load a specific crisis scenario from the `config/` directory.
- `--export-csv <bool>`: Toggle telemetry output.

## Programmatic Interaction (Zig/C Hooks)
If Kessler is compiled as a library (`.lib` or `.a`), the following core functions are exposed:

### `kessler_init(config_path: [*:0]const u8) -> *KesslerContext`
Initializes the `stash.zig` arena and pre-allocates all SoA structures based on the YAML schema.

### `kessler_tick(ctx: *KesslerContext)`
Advances the simulation by exactly one microsecond. This allows for "Pause/Step" debugging of financial contagion.

### `kessler_inject_shock(ctx: *KesslerContext, asset_id: u32, magnitude: f64)`
Manually forces a price drop or liquidity withdrawal to observe how the **Gai-Kapadia loop** reacts to external "Black Swan" events.

## Output Schema
Telemetry is standardized in the `kessler_*.csv` format. 
- **Prices:** `[tick, asset_0...asset_n]`
- **Defaults:** `[tick, active_defaults, contagion_depth]`
- **Agents:** `[tick, agent_id, equity, status]`
