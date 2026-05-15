use crate::app_state::AppState;
use crate::handlers::{
    get_server, get_server_logs, get_server_properties, get_server_status, health,
    list_server_files, list_servers, put_server_properties, read_server_file, read_server_players,
    restart_server, send_server_command, start_server, stop_server, write_server_file,
    write_server_players,
};
use crate::ws::ws_server_console;
use axum::Router;
use axum::routing::{get, post};
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};

pub fn build_router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/api/servers", get(list_servers))
        .route("/api/servers/{id}", get(get_server))
        .route("/api/servers/{id}/status", get(get_server_status))
        .route("/api/servers/{id}/logs", get(get_server_logs))
        .route(
            "/api/servers/{id}/properties",
            get(get_server_properties).put(put_server_properties),
        )
        .route("/api/servers/{id}/files", get(list_server_files))
        .route(
            "/api/servers/{id}/files/{*path}",
            get(read_server_file).put(write_server_file),
        )
        .route(
            "/api/servers/{id}/players/{file_name}",
            get(read_server_players).put(write_server_players),
        )
        .route("/api/servers/{id}/command", post(send_server_command))
        .route("/api/servers/{id}/start", post(start_server))
        .route("/api/servers/{id}/stop", post(stop_server))
        .route("/api/servers/{id}/restart", post(restart_server))
        .route("/ws/servers/{id}/console", get(ws_server_console))
        .layer(
            CorsLayer::new()
                .allow_methods(Any)
                .allow_headers(Any)
                .allow_origin(Any),
        )
        .with_state(state)
}
