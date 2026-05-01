# scsl_core Workspace

This directory hosts the cross-platform runtime that will gradually take over
server-management business logic from the SwiftUI app in `../scsl_macos`.

## Current Scope

The first phase is intentionally narrow:

- Build a reusable `scsl_core` facade crate
- Keep the focus on local server-management workflows
- Define stable domain models, errors, and ports for future adapters
- Prove the core can run without any UI dependencies

Remote-node support is not part of this first Rust step. Once the local core
is stable, additional crates can be added here without changing the workspace
layout.

## Planned Layout

```text
scsl_core/
  crates/
    scsl_core_domain/    # domain models + errors
    scsl_core_inventory/ # post-load server dedupe + corrupted-directory detection
    scsl_core_launch/    # server launch planning + direct-mode scripts
    scsl_core_ports/     # store/runtime ports
    scsl_core_service/   # application service / use cases
    scsl_core_inmemory/  # demo in-memory adapters
    scsl_core_swiftdata/ # adapter for the Swift app's server_instances table
    scsl_core/           # facade crate re-exporting the split core
    scsl_cli/            # command-line entrypoint
    scsl_agent/  # future local agent / service entrypoint
```

## CLI Against Swift Data

The CLI uses the Swift app's default Application Support data automatically:

```sh
cargo run -p scsl_cli -- server list
cargo run -p scsl_cli -- server show <server-id>
cargo run -p scsl_cli -- server command <server-id>
cargo run -p scsl_cli -- server corrupted
cargo run -p scsl_cli -- server status <server-id>
cargo run -p scsl_cli -- server logs <server-id> -n 50
```

Custom database and working-path overrides are still available:

```sh
cargo run -p scsl_cli -- --db /path/to/data.db --working-path /path/to/working-dir server list
```

Local `start`, `stop`, and `restart` use the same `.scsl.pid`,
`.scsl.stdin`, and `scsl-server.log` files as the Swift app's direct local
server mode. Launch command generation lives in `scsl_core_launch`, including
JVM memory arguments, quoted JVM argument splitting, custom commands with
`nogui`, and Forge `run.sh` / `unix_args.txt` / server-jar detection.

Loaded server lists are normalized through `scsl_core_inventory`, matching the
Swift repository behavior for duplicate `(nodeId, name)` records and missing
local server directories.
