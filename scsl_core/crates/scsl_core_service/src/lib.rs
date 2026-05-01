use scsl_core_domain::{CoreError, LogQuery, LogSnapshot, ServerInstance, ServerStatus};
use scsl_core_ports::{ServerRuntimePort, ServerStorePort};

pub struct ScslCore<S, R> {
    store: S,
    runtime: R,
}

impl<S, R> ScslCore<S, R>
where
    S: ServerStorePort,
    R: ServerRuntimePort,
{
    pub fn new(store: S, runtime: R) -> Self {
        Self { store, runtime }
    }

    pub fn runtime(&self) -> &R {
        &self.runtime
    }

    pub fn list_servers(&self) -> Result<Vec<ServerInstance>, CoreError> {
        self.store.list_servers()
    }

    pub fn get_server(&self, id: &str) -> Result<Option<ServerInstance>, CoreError> {
        self.store.get_server(id)
    }

    pub fn save_server(&self, server: ServerInstance) -> Result<(), CoreError> {
        self.validate_server(&server)?;
        self.store.save_server(server)
    }

    pub fn delete_server(&self, id: &str) -> Result<(), CoreError> {
        let _ = self.require_server(id)?;
        self.store.delete_server(id)
    }

    pub fn server_status(&self, id: &str) -> Result<ServerStatus, CoreError> {
        let server = self.require_server(id)?;
        self.runtime.status(&server)
    }

    pub fn start_server(&self, id: &str) -> Result<ServerStatus, CoreError> {
        let server = self.require_server(id)?;
        self.ensure_local_server(&server)?;
        self.runtime.start(&server)?;
        self.runtime.status(&server)
    }

    pub fn stop_server(&self, id: &str) -> Result<ServerStatus, CoreError> {
        let server = self.require_server(id)?;
        self.ensure_local_server(&server)?;
        self.runtime.stop(&server)?;
        self.runtime.status(&server)
    }

    pub fn restart_server(&self, id: &str) -> Result<ServerStatus, CoreError> {
        let server = self.require_server(id)?;
        self.ensure_local_server(&server)?;
        self.runtime.stop(&server)?;
        self.runtime.start(&server)?;
        self.runtime.status(&server)
    }

    pub fn server_logs(&self, id: &str, query: LogQuery) -> Result<LogSnapshot, CoreError> {
        let server = self.require_server(id)?;
        self.runtime.logs(&server, query)
    }

    fn require_server(&self, id: &str) -> Result<ServerInstance, CoreError> {
        self.store
            .get_server(id)?
            .ok_or_else(|| CoreError::not_found("server", id))
    }

    fn validate_server(&self, server: &ServerInstance) -> Result<(), CoreError> {
        if server.id.trim().is_empty() {
            return Err(CoreError::validation("server id cannot be empty"));
        }
        if server.name.trim().is_empty() {
            return Err(CoreError::validation("server name cannot be empty"));
        }
        if server.directory_name.trim().is_empty() {
            return Err(CoreError::validation(
                "server directory name cannot be empty",
            ));
        }
        if server.server_jar.trim().is_empty() {
            return Err(CoreError::validation("server jar cannot be empty"));
        }
        Ok(())
    }

    fn ensure_local_server(&self, server: &ServerInstance) -> Result<(), CoreError> {
        if server.is_local() {
            return Ok(());
        }
        Err(CoreError::unsupported(
            "remote-node orchestration is intentionally deferred in the first Rust core milestone",
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::ScslCore;
    use scsl_core_domain::{CoreError, LogQuery, ServerStatus};
    use scsl_core_inmemory::{InMemoryRuntime, InMemoryStore, sample_local_server};

    #[test]
    fn save_server_rejects_missing_required_fields() {
        let store = InMemoryStore::default();
        let runtime = InMemoryRuntime::default();
        let core = ScslCore::new(store, runtime);

        let mut invalid = sample_local_server();
        invalid.name.clear();

        let error = core
            .save_server(invalid)
            .expect_err("server should be rejected");
        assert_eq!(error, CoreError::validation("server name cannot be empty"));
    }

    #[test]
    fn start_stop_and_restart_server_use_runtime_port() {
        let server = sample_local_server();
        let store = InMemoryStore::with_servers([server.clone()]);
        let runtime = InMemoryRuntime::with_server(
            &server.id,
            ServerStatus::Stopped,
            vec!["boot".to_string()],
        );
        let core = ScslCore::new(store, runtime);

        assert_eq!(
            core.start_server(&server.id).expect("start should succeed"),
            ServerStatus::Running
        );
        assert_eq!(
            core.stop_server(&server.id).expect("stop should succeed"),
            ServerStatus::Stopped
        );
        assert_eq!(
            core.restart_server(&server.id)
                .expect("restart should succeed"),
            ServerStatus::Running
        );
    }

    #[test]
    fn server_logs_returns_a_tail_snapshot() {
        let server = sample_local_server();
        let store = InMemoryStore::with_servers([server.clone()]);
        let runtime = InMemoryRuntime::with_server(
            &server.id,
            ServerStatus::Running,
            vec![
                "line-1".to_string(),
                "line-2".to_string(),
                "line-3".to_string(),
            ],
        );
        let core = ScslCore::new(store, runtime);

        let logs = core
            .server_logs(&server.id, LogQuery::tail(2))
            .expect("logs should succeed");

        assert_eq!(logs.status, ServerStatus::Running);
        assert_eq!(logs.lines, vec!["line-2".to_string(), "line-3".to_string()]);
    }

    #[test]
    fn remote_servers_are_rejected_in_the_first_milestone() {
        let mut remote_server = sample_local_server();
        remote_server.node_id = "remote-node-1".to_string();
        let store = InMemoryStore::with_servers([remote_server.clone()]);
        let runtime =
            InMemoryRuntime::with_server(&remote_server.id, ServerStatus::Stopped, Vec::new());
        let core = ScslCore::new(store, runtime);

        let error = core
            .start_server(&remote_server.id)
            .expect_err("remote start should be rejected");
        assert_eq!(
            error,
            CoreError::unsupported(
                "remote-node orchestration is intentionally deferred in the first Rust core milestone",
            )
        );
    }
}
