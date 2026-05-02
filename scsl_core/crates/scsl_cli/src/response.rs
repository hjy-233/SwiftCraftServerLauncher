use scsl_core::{
    ConsoleMode, JavaVersion, LocalServerFileEntry, ServerInstance, ServerStatus, ServerType,
};
use serde::Serialize;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PortProcessInfoResponse {
    pub pid: i32,
    pub command: String,
    pub user: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ForgeInstallPlanResponse {
    pub server_id: String,
    pub server_dir: String,
    pub installer_jar: String,
    pub command: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LogSnapshotResponse {
    pub status: ServerStatus,
    pub lines: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalLogPollResponse {
    pub file_path: Option<String>,
    pub appended_text: String,
    pub next_offset: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResourceDownloadResponse {
    pub path: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerFileReadResponse {
    pub content: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerOperationResponse {
    pub status: ServerStatus,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalStartPlanResponse {
    pub launch_command: String,
    pub forge_installed: bool,
    pub port: i32,
    pub port_available: bool,
    pub port_processes: Vec<PortProcessInfoResponse>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GameLaunchPlanResponse {
    pub java_path: String,
    pub arguments: Vec<String>,
    pub working_directory: String,
    pub environment: std::collections::BTreeMap<String, String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileHashResponse {
    pub sha1: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResourceFileHashResponse {
    pub path: String,
    pub sha1: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupEntryResponse {
    pub path: String,
    pub modified_at: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupRestoreResponse {
    pub created_server: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerSummaryResponse {
    pub id: String,
    pub name: String,
    pub directory_name: String,
    pub server_type: ServerType,
    pub game_version: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VerifyJarResponse {
    pub valid: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteCorruptedResponse {
    pub deleted_count: usize,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AckResponse {
    pub ok: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RconResponse {
    pub output: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerCreateResponse {
    pub id: String,
    pub directory_name: String,
    pub server_jar: String,
    pub java_path: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadTargetResponse {
    pub url: String,
    pub sha1: Option<String>,
    pub file_name: String,
    pub headers: std::collections::BTreeMap<String, String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JavaVersionResponse {
    pub component: String,
    pub major_version: u32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LatestLoaderResponse {
    pub version: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerDetailResponse {
    pub id: String,
    pub name: String,
    pub directory_name: String,
    pub icon_name: String,
    pub icon_image_file_name: Option<String>,
    pub server_type: ServerType,
    pub game_version: String,
    pub loader_version: String,
    pub server_jar: String,
    pub launch_command: String,
    pub last_played: f64,
    pub java_path: String,
    pub jvm_arguments: String,
    pub xms: i32,
    pub xmx: i32,
    pub node_id: String,
    pub console_mode: ConsoleMode,
    pub rcon_port: i32,
    pub rcon_password: String,
}

impl From<ServerInstance> for ServerSummaryResponse {
    fn from(server: ServerInstance) -> Self {
        Self {
            id: server.id,
            name: server.name,
            directory_name: server.directory_name,
            server_type: server.server_type,
            game_version: server.game_version,
        }
    }
}

impl From<ServerInstance> for ServerDetailResponse {
    fn from(server: ServerInstance) -> Self {
        Self {
            id: server.id,
            name: server.name,
            directory_name: server.directory_name,
            icon_name: server.icon_name,
            icon_image_file_name: server.icon_image_file_name,
            server_type: server.server_type,
            game_version: server.game_version,
            loader_version: server.loader_version,
            server_jar: server.server_jar,
            launch_command: server.launch_command,
            last_played: server.last_played,
            java_path: server.java_path,
            jvm_arguments: server.jvm_arguments,
            xms: server.xms,
            xmx: server.xmx,
            node_id: server.node_id,
            console_mode: server.console_mode,
            rcon_port: server.rcon_port,
            rcon_password: server.rcon_password,
        }
    }
}

impl From<scsl_core::LogSnapshot> for LogSnapshotResponse {
    fn from(snapshot: scsl_core::LogSnapshot) -> Self {
        Self {
            status: snapshot.status,
            lines: snapshot.lines,
        }
    }
}

impl From<scsl_core::LocalLogPollResult> for LocalLogPollResponse {
    fn from(result: scsl_core::LocalLogPollResult) -> Self {
        Self {
            file_path: result.file_path,
            appended_text: result.appended_text,
            next_offset: result.next_offset,
        }
    }
}

impl From<scsl_core::DownloadTarget> for DownloadTargetResponse {
    fn from(target: scsl_core::DownloadTarget) -> Self {
        Self {
            url: target.url,
            sha1: target.sha1,
            file_name: target.file_name,
            headers: target.headers,
        }
    }
}

impl From<JavaVersion> for JavaVersionResponse {
    fn from(version: JavaVersion) -> Self {
        Self {
            component: version.component,
            major_version: version.major_version,
        }
    }
}

impl From<Vec<LocalServerFileEntry>> for AckResponse {
    fn from(_: Vec<LocalServerFileEntry>) -> Self {
        Self { ok: true }
    }
}
