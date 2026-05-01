use scsl_core_domain::ServerInstance;
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq)]
pub struct ServerInventory {
    pub servers: Vec<ServerInstance>,
    pub duplicate_server_ids: Vec<String>,
    pub corrupted_server_names: Vec<String>,
}

pub struct ServerInventoryAnalyzer {
    server_root_dir: PathBuf,
}

impl ServerInventoryAnalyzer {
    pub fn new(server_root_dir: impl Into<PathBuf>) -> Self {
        Self {
            server_root_dir: server_root_dir.into(),
        }
    }

    pub fn analyze<I>(&self, servers: I) -> ServerInventory
    where
        I: IntoIterator<Item = ServerInstance>,
    {
        let (servers, duplicate_server_ids) = self.dedupe_by_node_and_name(servers);
        let corrupted_server_names = self.corrupted_local_server_names(&servers);
        ServerInventory {
            servers,
            duplicate_server_ids,
            corrupted_server_names,
        }
    }

    fn dedupe_by_node_and_name<I>(&self, servers: I) -> (Vec<ServerInstance>, Vec<String>)
    where
        I: IntoIterator<Item = ServerInstance>,
    {
        let mut latest_by_key: HashMap<String, ServerInstance> = HashMap::new();
        let mut duplicates = Vec::new();

        for server in servers {
            let key = format!("{}::{}", server.node_id, server.name);
            if let Some(existing) = latest_by_key.get(&key) {
                if server.last_played > existing.last_played {
                    duplicates.push(existing.id.clone());
                    latest_by_key.insert(key, server);
                } else {
                    duplicates.push(server.id);
                }
            } else {
                latest_by_key.insert(key, server);
            }
        }

        let mut unique = latest_by_key.into_values().collect::<Vec<_>>();
        unique.sort_by(|left, right| right.last_played.total_cmp(&left.last_played));
        (unique, duplicates)
    }

    fn corrupted_local_server_names(&self, servers: &[ServerInstance]) -> Vec<String> {
        servers
            .iter()
            .filter(|server| server.is_local())
            .filter(|server| !self.server_root_dir.join(&server.directory_name).exists())
            .map(|server| server.name.clone())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::ServerInventoryAnalyzer;
    use scsl_core_domain::{ServerInstance, ServerType};
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn keeps_latest_duplicate_by_node_and_name() {
        let root = temp_dir();
        let analyzer = ServerInventoryAnalyzer::new(root.join("servers"));
        let mut old = sample_server("old", "Same Name", 10.0);
        let new = sample_server("new", "Same Name", 20.0);
        old.directory_name = "old-dir".to_string();

        let inventory = analyzer.analyze([old, new.clone()]);

        assert_eq!(inventory.servers, vec![new]);
        assert_eq!(inventory.duplicate_server_ids, vec!["old".to_string()]);
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn reports_missing_local_server_directories() {
        let root = temp_dir();
        let server_root = root.join("servers");
        fs::create_dir_all(server_root.join("exists")).expect("server directory should create");
        let analyzer = ServerInventoryAnalyzer::new(&server_root);

        let mut valid = sample_server("valid", "Valid", 20.0);
        valid.directory_name = "exists".to_string();
        let mut missing = sample_server("missing", "Missing", 10.0);
        missing.directory_name = "missing".to_string();
        let mut remote = sample_server("remote", "Remote", 30.0);
        remote.node_id = "remote-node".to_string();
        remote.directory_name = "remote-missing".to_string();

        let inventory = analyzer.analyze([valid, missing, remote]);

        assert_eq!(
            inventory.corrupted_server_names,
            vec!["Missing".to_string()]
        );
        let _ = fs::remove_dir_all(root);
    }

    fn sample_server(id: &str, name: &str, last_played: f64) -> ServerInstance {
        let mut server =
            ServerInstance::new(id, name, name, ServerType::Paper, "1.21.1", "server.jar");
        server.last_played = last_played;
        server
    }

    fn temp_dir() -> std::path::PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be valid")
            .as_nanos();
        std::env::temp_dir().join(format!("scsl-core-inventory-{nonce}"))
    }
}
