use scsl_core::{ServerStatus, ServerType};
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
pub struct HealthResponse {
    pub ok: bool,
    pub service: &'static str,
}

#[derive(Serialize)]
pub struct ServerSummary {
    pub id: String,
    pub name: String,
    pub directory_name: String,
    pub server_type: ServerType,
    pub game_version: String,
    pub node_id: String,
}

#[derive(Serialize)]
pub struct ServerStatusResponse {
    pub id: String,
    pub status: ServerStatus,
}

#[derive(Serialize)]
pub struct ServerLogsResponse {
    pub status: ServerStatus,
    pub lines: Vec<String>,
}

#[derive(Serialize)]
pub struct ServerFileTextResponse {
    pub relative_path: String,
    pub content: String,
}

#[derive(Deserialize)]
pub struct ServerFileTextRequest {
    pub content: String,
}

#[derive(Deserialize)]
pub struct ServerCommandRequest {
    pub command: String,
}

#[derive(Serialize)]
pub struct AckResponse {
    pub ok: bool,
}

#[derive(Serialize)]
pub struct ConsoleStreamSnapshot {
    pub r#type: &'static str,
    pub status: ServerStatus,
    pub lines: Vec<String>,
}

#[derive(Serialize)]
pub struct ConsoleStreamAppend {
    pub r#type: &'static str,
    pub status: ServerStatus,
    pub lines: Vec<String>,
}

#[derive(Deserialize)]
pub struct ListLogsQuery {
    pub lines: Option<usize>,
}

#[derive(Deserialize)]
pub struct ListenAddressArgs {
    #[serde(default = "default_host")]
    pub host: String,
    #[serde(default = "default_port")]
    pub port: u16,
}

fn default_host() -> String {
    "127.0.0.1".to_string()
}

fn default_port() -> u16 {
    31800
}
