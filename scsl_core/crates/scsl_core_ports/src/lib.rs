use scsl_core_domain::{CoreError, LogQuery, LogSnapshot, ServerInstance, ServerStatus};

pub trait ServerStorePort {
    fn list_servers(&self) -> Result<Vec<ServerInstance>, CoreError>;
    fn get_server(&self, id: &str) -> Result<Option<ServerInstance>, CoreError>;
    fn save_server(&self, server: ServerInstance) -> Result<(), CoreError>;
    fn delete_server(&self, id: &str) -> Result<(), CoreError>;
}

pub trait ServerRuntimePort {
    fn start(&self, server: &ServerInstance) -> Result<(), CoreError>;
    fn stop(&self, server: &ServerInstance) -> Result<(), CoreError>;
    fn status(&self, server: &ServerInstance) -> Result<ServerStatus, CoreError>;
    fn logs(&self, server: &ServerInstance, query: LogQuery) -> Result<LogSnapshot, CoreError>;
}
