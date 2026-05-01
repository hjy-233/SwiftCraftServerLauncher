use serde::{Deserialize, Deserializer, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ServerType {
    Vanilla,
    Fabric,
    Forge,
    Paper,
    Custom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ConsoleMode {
    Direct,
    Rcon,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ServerStatus {
    Stopped,
    Running,
    Starting,
    Stopping,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct MemorySettings {
    pub xms_mb: Option<u32>,
    pub xmx_mb: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerInstance {
    pub id: String,
    pub name: String,
    pub directory_name: String,
    #[serde(default = "default_icon_name")]
    pub icon_name: String,
    #[serde(default)]
    pub icon_image_file_name: Option<String>,
    pub server_type: ServerType,
    pub game_version: String,
    #[serde(default)]
    pub loader_version: String,
    pub server_jar: String,
    #[serde(default)]
    pub launch_command: String,
    #[serde(default)]
    pub last_played: f64,
    #[serde(default)]
    pub java_path: String,
    #[serde(default)]
    pub jvm_arguments: String,
    #[serde(default)]
    pub xms: i32,
    #[serde(default)]
    pub xmx: i32,
    #[serde(default = "default_local_node_id")]
    pub node_id: String,
    #[serde(default = "default_console_mode")]
    pub console_mode: ConsoleMode,
    #[serde(default = "default_rcon_port")]
    pub rcon_port: i32,
    #[serde(default)]
    pub rcon_password: String,
}

impl<'de> Deserialize<'de> for ServerInstance {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct ServerInstanceWire {
            id: String,
            name: String,
            #[serde(default)]
            directory_name: Option<String>,
            #[serde(default = "default_icon_name")]
            icon_name: String,
            #[serde(default)]
            icon_image_file_name: Option<String>,
            server_type: ServerType,
            game_version: String,
            #[serde(default)]
            loader_version: String,
            server_jar: String,
            #[serde(default)]
            launch_command: String,
            #[serde(default)]
            last_played: f64,
            #[serde(default)]
            java_path: String,
            #[serde(default)]
            jvm_arguments: String,
            #[serde(default)]
            xms: i32,
            #[serde(default)]
            xmx: i32,
            #[serde(default = "default_local_node_id")]
            node_id: String,
            #[serde(default = "default_console_mode")]
            console_mode: ConsoleMode,
            #[serde(default = "default_rcon_port")]
            rcon_port: i32,
            #[serde(default)]
            rcon_password: String,
        }

        let wire = ServerInstanceWire::deserialize(deserializer)?;
        Ok(Self {
            directory_name: wire.directory_name.unwrap_or_else(|| wire.name.clone()),
            id: wire.id,
            name: wire.name,
            icon_name: wire.icon_name,
            icon_image_file_name: wire.icon_image_file_name,
            server_type: wire.server_type,
            game_version: wire.game_version,
            loader_version: wire.loader_version,
            server_jar: wire.server_jar,
            launch_command: wire.launch_command,
            last_played: wire.last_played,
            java_path: wire.java_path,
            jvm_arguments: wire.jvm_arguments,
            xms: wire.xms,
            xmx: wire.xmx,
            node_id: wire.node_id,
            console_mode: wire.console_mode,
            rcon_port: wire.rcon_port,
            rcon_password: wire.rcon_password,
        })
    }
}

impl ServerInstance {
    pub const LOCAL_NODE_ID: &str = "00000000-0000-0000-0000-000000000001";

    pub fn new(
        id: impl Into<String>,
        name: impl Into<String>,
        directory_name: impl Into<String>,
        server_type: ServerType,
        game_version: impl Into<String>,
        server_jar: impl Into<String>,
    ) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            directory_name: directory_name.into(),
            icon_name: default_icon_name(),
            icon_image_file_name: None,
            server_type,
            game_version: game_version.into(),
            loader_version: String::new(),
            server_jar: server_jar.into(),
            launch_command: String::new(),
            last_played: 0.0,
            java_path: String::new(),
            jvm_arguments: String::new(),
            xms: 0,
            xmx: 0,
            node_id: Self::LOCAL_NODE_ID.to_string(),
            console_mode: default_console_mode(),
            rcon_port: default_rcon_port(),
            rcon_password: String::new(),
        }
    }

    pub fn is_local(&self) -> bool {
        self.node_id == Self::LOCAL_NODE_ID
    }
}

fn default_icon_name() -> String {
    "server.rack".to_string()
}

fn default_local_node_id() -> String {
    ServerInstance::LOCAL_NODE_ID.to_string()
}

fn default_console_mode() -> ConsoleMode {
    ConsoleMode::Rcon
}

fn default_rcon_port() -> i32 {
    25575
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LogQuery {
    pub max_lines: usize,
}

impl LogQuery {
    pub fn tail(max_lines: usize) -> Self {
        Self { max_lines }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LogSnapshot {
    pub status: ServerStatus,
    pub lines: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::{ConsoleMode, ServerInstance, ServerType};

    #[test]
    fn decodes_swift_server_instance_json() {
        let json = r#"{
            "id": "server-1",
            "name": "Paper Demo",
            "directoryName": "Paper Demo",
            "iconName": "server.rack",
            "iconImageFileName": null,
            "serverType": "paper",
            "gameVersion": "1.21.1",
            "loaderVersion": "",
            "serverJar": "server.jar",
            "launchCommand": "",
            "lastPlayed": 1710000000.5,
            "javaPath": "java",
            "jvmArguments": "-Dfile.encoding=UTF-8",
            "xms": 1024,
            "xmx": 2048,
            "nodeId": "00000000-0000-0000-0000-000000000001",
            "consoleMode": "rcon",
            "rconPort": 25575,
            "rconPassword": ""
        }"#;

        let server: ServerInstance = serde_json::from_str(json).expect("json should decode");

        assert_eq!(server.id, "server-1");
        assert_eq!(server.server_type, ServerType::Paper);
        assert_eq!(server.console_mode, ConsoleMode::Rcon);
        assert_eq!(server.jvm_arguments, "-Dfile.encoding=UTF-8");
        assert_eq!(server.xmx, 2048);
    }
}
