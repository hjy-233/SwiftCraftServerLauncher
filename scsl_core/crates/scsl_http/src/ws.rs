use crate::app_state::AppState;
use crate::error::HttpError;
use crate::models::{ConsoleStreamAppend, ConsoleStreamSnapshot};
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Path, State};
use axum::response::Response;
use scsl_core::{
    CoreError, LocalServerRuntime, LogQuery, ServerInstance, ServerRuntimePort, ServerStatus,
};
use serde::Serialize;
use std::sync::Arc;
use tokio::time::{Duration, sleep};

pub async fn ws_server_console(
    ws: WebSocketUpgrade,
    Path(id): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Result<Response, HttpError> {
    let core = state.core();
    let server = core
        .get_server(&id)?
        .ok_or_else(|| CoreError::not_found("server", &id))?;
    let snapshot = core.server_logs(&id, LogQuery::tail(200))?;
    Ok(ws.on_upgrade(move |socket| handle_console_socket(socket, state, server, snapshot)))
}

async fn handle_console_socket(
    mut socket: WebSocket,
    state: Arc<AppState>,
    server: ServerInstance,
    snapshot: scsl_core::LogSnapshot,
) {
    let initial = ConsoleStreamSnapshot {
        r#type: "snapshot",
        status: snapshot.status,
        lines: snapshot.lines,
    };
    if send_ws_json(&mut socket, &initial).await.is_err() {
        return;
    }

    let runtime = LocalServerRuntime::new(state.working_path.clone());
    let mut current_file_path: Option<String> = None;
    let mut offset = 0_u64;

    loop {
        match runtime.poll_local_log(&server, current_file_path.as_deref(), offset) {
            Ok(update) => {
                current_file_path = update.file_path.clone();
                offset = update.next_offset;
                if !update.appended_text.is_empty() {
                    let lines = split_lines(&update.appended_text);
                    if !lines.is_empty() {
                        let status = runtime.status(&server).unwrap_or(ServerStatus::Stopped);
                        let message = ConsoleStreamAppend {
                            r#type: "append",
                            status,
                            lines,
                        };
                        if send_ws_json(&mut socket, &message).await.is_err() {
                            break;
                        }
                    }
                }
            }
            Err(_) => break,
        }

        sleep(Duration::from_millis(500)).await;
    }
}

async fn send_ws_json<T: Serialize>(
    socket: &mut WebSocket,
    payload: &T,
) -> Result<(), axum::Error> {
    let text = serde_json::to_string(payload).unwrap_or_else(|_| {
        "{\"type\":\"error\",\"error\":\"failed to encode websocket payload\"}".to_string()
    });
    socket.send(Message::Text(text.into())).await
}

fn split_lines(input: &str) -> Vec<String> {
    input
        .lines()
        .map(str::trim_end)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}
