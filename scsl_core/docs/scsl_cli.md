# scsl_cli 文档

`scsl` 是项目内部和前端共用的 CLI 入口。

功能:

- 给 UI 调用
- 给开发调试使用
- 给本地后台 agent 复用

默认所有输出都是 JSON envelope：

```json
{"ok":true,"data":""}
```

失败时：

```json
{"ok":false,"error":{"message":"..."}}
```

## 全局参数

```sh
scsl [--db <path>] [--working-path <path>] [--demo] <command> ...
```

- `--db`: 指定数据库路径
- `--working-path`: 指定工作目录
- `--demo`: 使用 demo/in-memory 模式

## 命令总览

- `server`: 服务器管理
- `mirror`: 服务端镜像源查询
- `modrinth`: Modrinth 查询
- `resource`: 资源下载
- `game`: 游戏运行时 / 工具能力
- `settings`: JSON 设置读写
- `agent`: 本地后台 agent

---

## `server`

### 基础信息

```sh
scsl server list
scsl server show <server-id>
scsl server corrupted
scsl server status <server-id>
scsl server command <server-id>
scsl server logs <server-id> [--lines 200]
```

### 生命周期

```sh
scsl server start <server-id>
scsl server stop <server-id>
scsl server restart <server-id>
scsl server interrupt <server-id> [--force]
scsl server send <server-id> "<command>"
scsl server rcon <server-id> "<command>"
```

### 本地启动相关

```sh
scsl server local-start-plan <server-id> --java-path "/path/to/java"
scsl server local-start <server-id> --java-path "/path/to/java"
scsl server local-log-poll <server-id> [--current-file-path <path>] [--offset 0]
```

### 创建 / 删除

```sh
scsl server create-local --json '<json>'
scsl server delete <server-id>
scsl server delete-corrupted <server-name>
```

`create-local` 的 `json` 是服务器创建请求，典型字段包括：

- `id`
- `name`
- `directoryName`
- `type`
- `version`
- `javaVersion`
- `source`

其中 `source` 支持：

- `customJar`
- `download`

### 下载解析

```sh
scsl server download-target --json '<json>'
scsl server game-versions --server-type vanilla
scsl server game-versions --server-type paper --include-snapshots
scsl server loader-versions --server-type fabric --game-version 1.20.1
scsl server java-version 1.20.1
scsl server latest-loader --server-type forge --game-version 1.20.1
scsl server verify-jar <server-id>
scsl server forge-install-plan <server-id>
```

### `server properties`

```sh
scsl server properties read <server-id>
scsl server properties write <server-id> --json '{"motd":"Hello","online-mode":"false"}'
```

### `server files`

```sh
scsl server files list <server-id>
scsl server files read <server-id> --path "server.properties"
scsl server files write <server-id> --path "eula.txt"
scsl server files mkdir <server-id> --path "mods"
scsl server files touch <server-id> --path "logs/custom.log"
scsl server files move <server-id> --from "a.txt" --to "b.txt"
scsl server files delete <server-id> --path "old.txt"
scsl server files import <server-id> --source "/tmp/mod.jar" [--directory "mods"]
```

说明：

- `write` 当前是从 `stdin` 读内容
- `read` 返回文本内容

示例：

```sh
printf 'eula=true\n' | scsl server files write <server-id> --path "eula.txt"
```

### `server players`

```sh
scsl server players read <server-id> --file-name "whitelist.json"
scsl server players write <server-id> --file-name "whitelist.json"
```

常见文件名：

- `whitelist.json`
- `ops.json`
- `banned-players.json`
- `banned-ips.json`

`write` 同样从 `stdin` 读 JSON。

### `server schedules`

```sh
scsl server schedules read <server-id>
scsl server schedules write <server-id>
```

`write` 从 `stdin` 读 JSON。

---

## `mirror`

### FastMirror

```sh
scsl mirror fastmirror-cores [--base-url <url>]
scsl mirror fastmirror-game-versions --core-name paper [--base-url <url>]
scsl mirror fastmirror-core-versions --core-name paper --game-version 1.20.1 [--base-url <url>]
scsl mirror fastmirror-detail --core-name paper --game-version 1.20.1 --core-version 123 [--base-url <url>]
```

### Polars

```sh
scsl mirror polars-core-types [--base-url <url>]
scsl mirror polars-core-items --core-type-id 1 [--base-url <url>]
```

### Custom Mirror

```sh
scsl mirror custom-cores --base-url <url> --config-json '<json>'
scsl mirror custom-game-versions --base-url <url> --config-json '<json>' --core-name paper
scsl mirror custom-core-versions --base-url <url> --config-json '<json>' --core-name paper --game-version 1.20.1
scsl mirror custom-detail --base-url <url> --config-json '<json>' --core-name paper --game-version 1.20.1 --core-version 123
```

---

## `modrinth`

### 搜索 / 详情

```sh
scsl modrinth search [--query sodium] [--index relevance] [--offset 0] [--limit 20] [--facets-json '<json>']
scsl modrinth project <project-id>
scsl modrinth versions <project-id>
scsl modrinth version <version-id>
scsl modrinth file-by-hash <sha1-or-sha512>
```

### 清单 / 元数据

```sh
scsl modrinth version-info 1.20.1
scsl modrinth loader-manifest fabric
scsl modrinth loader-profile --loader fabric --version 1.20.1
scsl modrinth loaders
scsl modrinth categories
scsl modrinth game-versions [--include-snapshots]
```

### 版本过滤 / 依赖

```sh
scsl modrinth versions-filter --id <project-id> --type mod --selected-versions-json '["1.20.1"]' --selected-loaders-json '["fabric"]'
scsl modrinth dependencies --id <project-id> --type mod --selected-versions-json '["1.20.1"]' --selected-loaders-json '["fabric"]'
```

---

## `resource`

```sh
scsl resource download --game-name "MyProfile" --resource-type mod --url <url> --file-name fabric-api.jar [--sha1 <sha1>]
```

`resource-type` 当前支持项目里已有映射类型，例如：

- `mod`
- `shader`
- `resourcepack`

---

## `game`

### 启动与 loader 工具

```sh
scsl game launch-plan --json '<json>'
scsl game maven-relative-path 'net.fabricmc:fabric-loader:0.15.11'
scsl game maven-path --coordinate 'net.fabricmc:fabric-loader:0.15.11' --libraries-dir "/path/to/libraries"
scsl game loader-classpath --json '<json>' --libraries-dir "/path/to/libraries" [--include-in-classpath-only]
scsl game process-loader-placeholders --json '<json>' --game-version 1.20.1
scsl game execute-processor --json '<json>'
```

### 下载 / 文件 / 权限

```sh
scsl game download-file --url <url> --destination "/tmp/a.jar" [--sha1 <sha1>] [--headers-json '{"User-Agent":"..."}']
scsl game fetch-json --url <url> [--headers-json '{"Accept":"application/json"}']
scsl game set-executable --path "/path/to/file"
scsl game extract-zulu-runtime --zip-path "/tmp/zulu.zip" --target-directory "/tmp/java"
scsl game sha1-file --path "/tmp/file.jar"
scsl game hash-resource-files --directory "/path/to/mods"
```

### 备份

```sh
scsl game backup-create --source-root "/path/to/root" --output-path "/path/to/backup.zip" [--keep-count 10]
scsl game backup-list --backup-root "/path/to/backups"
scsl game backup-list-servers --backup-path "/path/to/backup.zip"
scsl game backup-restore --backup-path "/path/to/backup.zip" --server-name "MyServer" --target-root "/path/to/restore"
```

### NBT / Minecraft 文件

```sh
scsl game server-addresses-read --path "/path/to/servers.dat"
scsl game server-addresses-write --path "/path/to/servers.dat"
scsl game litematica-metadata --path "/path/to/file.litematic"
scsl game litematica-full-metadata --path "/path/to/file.litematic"
```

---

## `settings`

```sh
scsl settings read --scope general
scsl settings read --scope game
scsl settings read --scope mirror
scsl settings read --scope theme
scsl settings read --scope ai

scsl settings write --scope general --json '<json>'
scsl settings write --scope game --json '<json>'
scsl settings write --scope mirror --json '<json>'
scsl settings write --scope theme --json '<json>'
scsl settings write --scope ai --json '<json>'
```

设置文件当前默认落到：

```text
<working-path>/data/settings.json
```

---

## `agent`

`agent` 使用同一个 `scsl` 二进制，不单独安装第二个程序。

```sh
scsl agent run
scsl agent status
scsl agent start
scsl agent stop
scsl agent ensure
```

当前 agent 负责的主要是本地后台监测类任务，例如：

- 本地时间型 schedules
- 本地控制台关键词 schedules

普通 CLI 调用前会自动尝试 `ensure`。

---

## 常用示例

### 列出服务器

```sh
scsl server list
```

### 查看某台服务器详情

```sh
scsl server show 8855879B-3703-4CDE-8D8D-A77989CE68B1
```

### 启动本地服务器

```sh
scsl server local-start 8855879B-3703-4CDE-8D8D-A77989CE68B1 --java-path "/Library/Java/JavaVirtualMachines/..."
```

### 发送控制台命令

```sh
scsl server send 8855879B-3703-4CDE-8D8D-A77989CE68B1 "say hello"
```

### 读取白名单

```sh
scsl server players read 8855879B-3703-4CDE-8D8D-A77989CE68B1 --file-name "whitelist.json"
```

### 安装资源到 profile

```sh
scsl resource download --game-name "Demo" --resource-type mod --url https://example.com/a.jar --file-name a.jar
```