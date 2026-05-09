# scsl_core Workspace

`scsl_core` 是 SwiftCraftServerLauncher 的 Rust workspace

主要功能:

- 本地服务器管理 core
- `scsl` CLI
- 本地后台 agent
- 给 macOS app 复用的持久化 / 启动 / 下载 / 日志能力

## 构建

```sh
cargo build --manifest-path scsl_core/Cargo.toml -p scsl_cli
```

调试版产物：

```dir
scsl_core/target/debug/scsl
```

可发布产物：

```sh
cargo build --manifest-path scsl_core/Cargo.toml -p scsl_cli --release
```

```dir
scsl_core/target/release/scsl
```

## 数据目录

默认会自动使用应用数据目录：

- macOS: `~/Library/Application Support/SwiftCraftServerLauncher`
- Windows: `%APPDATA%/SwiftCraftServerLauncher`
- Linux: `$XDG_DATA_HOME/SwiftCraftServerLauncher` 或 `~/.local/share/SwiftCraftServerLauncher`

也可以覆盖：

```sh
scsl --db /path/to/data.db --working-path /path/to/working-dir server list
```

## CLI 文档

完整命令文档见：

- [scsl_cli.md](./docs/scsl_cli.md)

