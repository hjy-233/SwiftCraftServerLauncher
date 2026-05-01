use scsl_core_domain::{
    ConsoleMode, CoreError, LogQuery, LogSnapshot, ServerInstance, ServerStatus, ServerType,
};
use scsl_core_ports::{ServerRuntimePort, ServerStorePort};
use std::cell::RefCell;
use std::collections::HashMap;

#[derive(Default)]
pub struct InMemoryStore {
    servers: RefCell<HashMap<String, ServerInstance>>,
}

impl InMemoryStore {
    pub fn with_servers<I>(servers: I) -> Self
    where
        I: IntoIterator<Item = ServerInstance>,
    {
        let servers = servers
            .into_iter()
            .map(|server| (server.id.clone(), server))
            .collect();
        Self {
            servers: RefCell::new(servers),
        }
    }
}

impl ServerStorePort for InMemoryStore {
    fn list_servers(&self) -> Result<Vec<ServerInstance>, CoreError> {
        Ok(self.servers.borrow().values().cloned().collect())
    }

    fn get_server(&self, id: &str) -> Result<Option<ServerInstance>, CoreError> {
        Ok(self.servers.borrow().get(id).cloned())
    }

    fn save_server(&self, server: ServerInstance) -> Result<(), CoreError> {
        self.servers.borrow_mut().insert(server.id.clone(), server);
        Ok(())
    }

    fn delete_server(&self, id: &str) -> Result<(), CoreError> {
        self.servers.borrow_mut().remove(id);
        Ok(())
    }
}

#[derive(Default)]
pub struct InMemoryRuntime {
    statuses: RefCell<HashMap<String, ServerStatus>>,
    logs: RefCell<HashMap<String, Vec<String>>>,
}

impl InMemoryRuntime {
    pub fn with_server(server_id: &str, status: ServerStatus, logs: Vec<String>) -> Self {
        let mut statuses = HashMap::new();
        statuses.insert(server_id.to_string(), status);

        let mut runtime_logs = HashMap::new();
        runtime_logs.insert(server_id.to_string(), logs);

        Self {
            statuses: RefCell::new(statuses),
            logs: RefCell::new(runtime_logs),
        }
    }
}

impl ServerRuntimePort for InMemoryRuntime {
    fn start(&self, server: &ServerInstance) -> Result<(), CoreError> {
        self.statuses
            .borrow_mut()
            .insert(server.id.clone(), ServerStatus::Running);
        self.logs
            .borrow_mut()
            .entry(server.id.clone())
            .or_default()
            .push("[SCSL] started".to_string());
        Ok(())
    }

    fn stop(&self, server: &ServerInstance) -> Result<(), CoreError> {
        self.statuses
            .borrow_mut()
            .insert(server.id.clone(), ServerStatus::Stopped);
        self.logs
            .borrow_mut()
            .entry(server.id.clone())
            .or_default()
            .push("[SCSL] stopped".to_string());
        Ok(())
    }

    fn status(&self, server: &ServerInstance) -> Result<ServerStatus, CoreError> {
        Ok(*self
            .statuses
            .borrow()
            .get(&server.id)
            .unwrap_or(&ServerStatus::Stopped))
    }

    fn logs(&self, server: &ServerInstance, query: LogQuery) -> Result<LogSnapshot, CoreError> {
        let status = self.status(server)?;
        let lines = self
            .logs
            .borrow()
            .get(&server.id)
            .cloned()
            .unwrap_or_default();
        let start = lines.len().saturating_sub(query.max_lines);
        Ok(LogSnapshot {
            status,
            lines: lines[start..].to_vec(),
        })
    }
}

pub fn sample_local_server() -> ServerInstance {
    ServerInstance {
        id: "local-demo".to_string(),
        name: "Local Demo".to_string(),
        directory_name: "Local Demo".to_string(),
        icon_name: "server.rack".to_string(),
        icon_image_file_name: None,
        server_type: ServerType::Paper,
        game_version: "1.21.1".to_string(),
        loader_version: String::new(),
        server_jar: "server.jar".to_string(),
        launch_command: String::new(),
        last_played: 0.0,
        java_path: "java".to_string(),
        jvm_arguments: "-Dfile.encoding=UTF-8".to_string(),
        xms: 1024,
        xmx: 2048,
        console_mode: ConsoleMode::Direct,
        node_id: ServerInstance::LOCAL_NODE_ID.to_string(),
        rcon_port: 25575,
        rcon_password: String::new(),
    }
}
