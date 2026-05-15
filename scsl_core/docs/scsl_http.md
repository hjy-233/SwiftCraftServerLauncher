# `scsl_http`

`scsl_http` 是基于 `axum` 的 HTTP 后端，直接复用现有 Rust core 和本地 store/runtime。

## 启动

```sh
cargo run --manifest-path scsl_core/Cargo.toml -p scsl_http -- --host 127.0.0.1 --port 31800
```

默认监听：

- `127.0.0.1`
- `31800`

## 路由

### 健康检查

```http
GET /health
```

### 服务器

```http
GET  /api/servers
GET  /api/servers/:id
GET  /api/servers/:id/status
GET  /api/servers/:id/logs?lines=200
GET  /api/servers/:id/properties
PUT  /api/servers/:id/properties
GET  /api/servers/:id/files
GET  /api/servers/:id/files/*path
PUT  /api/servers/:id/files/*path
GET  /api/servers/:id/players/:file_name
PUT  /api/servers/:id/players/:file_name
POST /api/servers/:id/command
POST /api/servers/:id/start
POST /api/servers/:id/stop
POST /api/servers/:id/restart
```

### WebSocket

```http
GET /ws/servers/:id/console
```

消息类型：

- `snapshot`
- `append`

## 说明

- 当前面向本地节点
- 数据源直接读取本地 app store
- 已开启开发期 CORS，方便后续接 Web 面板
