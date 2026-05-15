use crate::app_state::AppState;
use crate::error::HttpError;
use crate::models::{
    AckResponse, HealthResponse, ListLogsQuery, ServerCommandRequest, ServerFileTextRequest,
    ServerFileTextResponse, ServerLogsResponse, ServerStatusResponse, ServerSummary,
};
use axum::Json;
use axum::extract::{Path, Query, State};
use scsl_core::{CoreError, LocalServerFileEntry, LogQuery, ServerInstance};
use std::collections::BTreeMap;
use std::sync::Arc;

pub async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        ok: true,
        service: "scsl-http",
    })
}

pub async fn list_servers(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<ServerSummary>>, HttpError> {
    let servers = state.core().list_servers()?;
    Ok(Json(servers.into_iter().map(server_summary).collect()))
}

pub async fn get_server(
    Path(id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<ServerInstance>, HttpError> {
    let server = state
        .core()
        .get_server(&id)?
        .ok_or_else(|| CoreError::not_found("server", &id))?;
    Ok(Json(server))
}

pub async fn get_server_status(
    Path(id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<ServerStatusResponse>, HttpError> {
    let status = state.core().server_status(&id)?;
    Ok(Json(ServerStatusResponse { id, status }))
}

pub async fn get_server_logs(
    Path(id): Path<String>,
    State(state): State<Arc<AppState>>,
    Query(query): Query<ListLogsQuery>,
) -> Result<Json<ServerLogsResponse>, HttpError> {
    let snapshot = state
        .core()
        .server_logs(&id, LogQuery::tail(query.lines.unwrap_or(200)))?;
    Ok(Json(ServerLogsResponse {
        status: snapshot.status,
        lines: snapshot.lines,
    }))
}

pub async fn get_server_properties(
    Path(id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<BTreeMap<String, String>>, HttpError> {
    let core = state.core();
    let server = core
        .get_server(&id)?
        .ok_or_else(|| CoreError::not_found("server", &id))?;
    let properties = core.runtime().read_server_properties(&server)?;
    Ok(Json(properties))
}

pub async fn put_server_properties(
    Path(id): Path<String>,
    State(state): State<Arc<AppState>>,
    Json(properties): Json<BTreeMap<String, String>>,
) -> Result<Json<AckResponse>, HttpError> {
    let core = state.core();
    let server = core
        .get_server(&id)?
        .ok_or_else(|| CoreError::not_found("server", &id))?;
    core.runtime()
        .write_server_properties(&server, &properties)?;
    Ok(Json(AckResponse { ok: true }))
}

pub async fn list_server_files(
    Path(id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<LocalServerFileEntry>>, HttpError> {
    let core = state.core();
    let server = core
        .get_server(&id)?
        .ok_or_else(|| CoreError::not_found("server", &id))?;
    let files = core.runtime().list_server_files(&server)?;
    Ok(Json(files))
}

pub async fn read_server_file(
    Path((id, path)): Path<(String, String)>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<ServerFileTextResponse>, HttpError> {
    let core = state.core();
    let server = core
        .get_server(&id)?
        .ok_or_else(|| CoreError::not_found("server", &id))?;
    let content = core.runtime().read_server_file_text(&server, &path)?;
    Ok(Json(ServerFileTextResponse {
        relative_path: path,
        content,
    }))
}

pub async fn write_server_file(
    Path((id, path)): Path<(String, String)>,
    State(state): State<Arc<AppState>>,
    Json(request): Json<ServerFileTextRequest>,
) -> Result<Json<AckResponse>, HttpError> {
    let core = state.core();
    let server = core
        .get_server(&id)?
        .ok_or_else(|| CoreError::not_found("server", &id))?;
    core.runtime()
        .write_server_file_text(&server, &path, &request.content)?;
    Ok(Json(AckResponse { ok: true }))
}

pub async fn read_server_players(
    Path((id, file_name)): Path<(String, String)>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<serde_json::Value>, HttpError> {
    let core = state.core();
    let server = core
        .get_server(&id)?
        .ok_or_else(|| CoreError::not_found("server", &id))?;
    let content = match core.runtime().read_server_file_text(&server, &file_name) {
        Ok(value) => value,
        Err(CoreError::NotFound { .. }) | Err(CoreError::Runtime { .. }) => "[]".to_string(),
        Err(error) => return Err(error.into()),
    };
    let payload = serde_json::from_str(&content).map_err(|error| {
        CoreError::runtime(format!("failed to decode player list json: {error}"))
    })?;
    Ok(Json(payload))
}

pub async fn write_server_players(
    Path((id, file_name)): Path<(String, String)>,
    State(state): State<Arc<AppState>>,
    Json(payload): Json<serde_json::Value>,
) -> Result<Json<AckResponse>, HttpError> {
    let core = state.core();
    let server = core
        .get_server(&id)?
        .ok_or_else(|| CoreError::not_found("server", &id))?;
    let content = serde_json::to_string_pretty(&payload).map_err(|error| {
        CoreError::runtime(format!("failed to encode player list json: {error}"))
    })?;
    core.runtime()
        .write_server_file_text(&server, &file_name, &(content + "\n"))?;
    Ok(Json(AckResponse { ok: true }))
}

pub async fn send_server_command(
    Path(id): Path<String>,
    State(state): State<Arc<AppState>>,
    Json(request): Json<ServerCommandRequest>,
) -> Result<Json<AckResponse>, HttpError> {
    let core = state.core();
    let server = core
        .get_server(&id)?
        .ok_or_else(|| CoreError::not_found("server", &id))?;
    core.runtime().send_command(&server, &request.command)?;
    Ok(Json(AckResponse { ok: true }))
}

pub async fn start_server(
    Path(id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<ServerStatusResponse>, HttpError> {
    let status = state.core().start_server(&id)?;
    Ok(Json(ServerStatusResponse { id, status }))
}

pub async fn stop_server(
    Path(id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<ServerStatusResponse>, HttpError> {
    let status = state.core().stop_server(&id)?;
    Ok(Json(ServerStatusResponse { id, status }))
}

pub async fn restart_server(
    Path(id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<ServerStatusResponse>, HttpError> {
    let status = state.core().restart_server(&id)?;
    Ok(Json(ServerStatusResponse { id, status }))
}

fn server_summary(server: ServerInstance) -> ServerSummary {
    ServerSummary {
        id: server.id,
        name: server.name,
        directory_name: server.directory_name,
        server_type: server.server_type,
        game_version: server.game_version,
        node_id: server.node_id,
    }
}
