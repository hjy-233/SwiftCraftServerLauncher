use rusqlite::{Connection, OptionalExtension, params};
use scsl_core_domain::{CoreError, ServerInstance};
use scsl_core_ports::ServerStorePort;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const APP_NAME: &str = "SwiftCraftServerLauncher";
const TABLE_NAME: &str = "server_instances";

pub struct LocalAppServerStore {
    db_path: PathBuf,
    working_path: String,
}

pub struct LocalAppPaths {
    pub db_path: PathBuf,
    pub working_path: PathBuf,
}

pub type SwiftDataServerStore = LocalAppServerStore;
pub type SwiftDataPaths = LocalAppPaths;

impl LocalAppServerStore {
    pub fn new(db_path: impl Into<PathBuf>, working_path: impl Into<String>) -> Self {
        Self {
            db_path: db_path.into(),
            working_path: working_path.into(),
        }
    }

    pub fn for_current_platform() -> Result<Self, CoreError> {
        let paths = platform_paths()?;
        Ok(Self::new(
            paths.db_path,
            paths.working_path.to_string_lossy().into_owned(),
        ))
    }

    pub fn platform_paths() -> Result<LocalAppPaths, CoreError> {
        platform_paths()
    }

    pub fn db_path(&self) -> &Path {
        &self.db_path
    }

    pub fn working_path(&self) -> &str {
        &self.working_path
    }

    fn ensure_schema(&self) -> Result<(), CoreError> {
        let connection = self.open_connection()?;
        connection
            .execute_batch(&format!(
                "CREATE TABLE IF NOT EXISTS {TABLE_NAME} (
                id TEXT PRIMARY KEY,
                working_path TEXT NOT NULL,
                server_name TEXT NOT NULL,
                data_json TEXT NOT NULL,
                last_played REAL NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_server_working_path ON {TABLE_NAME}(working_path);
            CREATE INDEX IF NOT EXISTS idx_server_last_played ON {TABLE_NAME}(last_played);
            CREATE INDEX IF NOT EXISTS idx_server_name ON {TABLE_NAME}(server_name);"
            ))
            .map_err(storage_error)
    }

    fn open_connection(&self) -> Result<Connection, CoreError> {
        if let Some(parent) = self.db_path.parent() {
            std::fs::create_dir_all(parent).map_err(|error| {
                CoreError::storage(format!("failed to create database directory: {error}"))
            })?;
        }
        let connection = Connection::open(&self.db_path).map_err(storage_error)?;
        connection
            .execute_batch("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=1000;")
            .map_err(storage_error)?;
        Ok(connection)
    }
}

impl ServerStorePort for LocalAppServerStore {
    fn list_servers(&self) -> Result<Vec<ServerInstance>, CoreError> {
        self.ensure_schema()?;
        let connection = self.open_connection()?;
        let mut statement = connection
            .prepare(&format!(
                "SELECT data_json FROM {TABLE_NAME} WHERE working_path = ? ORDER BY last_played DESC"
            ))
            .map_err(storage_error)?;
        let rows = statement
            .query_map(params![self.working_path], |row| row.get::<_, String>(0))
            .map_err(storage_error)?;
        rows.map(|row| decode_server_json(row.map_err(storage_error)?))
            .collect()
    }

    fn get_server(&self, id: &str) -> Result<Option<ServerInstance>, CoreError> {
        self.ensure_schema()?;
        let connection = self.open_connection()?;
        let json = connection
            .query_row(
                &format!(
                    "SELECT data_json FROM {TABLE_NAME} WHERE working_path = ? AND id = ? ORDER BY last_played DESC LIMIT 1"
                ),
                params![self.working_path, id],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(storage_error)?;
        json.map(decode_server_json).transpose()
    }

    fn save_server(&self, server: ServerInstance) -> Result<(), CoreError> {
        self.ensure_schema()?;
        let json = serde_json::to_string(&server).map_err(|error| {
            CoreError::storage(format!("failed to encode server json: {error}"))
        })?;
        let now = unix_timestamp();
        let connection = self.open_connection()?;
        connection
            .execute(
                &format!(
                    "INSERT OR REPLACE INTO {TABLE_NAME}
            (id, working_path, server_name, data_json, last_played, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, COALESCE((SELECT created_at FROM {TABLE_NAME} WHERE id = ?), ?), ?)"
                ),
                params![
                    server.id,
                    self.working_path,
                    server.name,
                    json,
                    server.last_played,
                    server.id,
                    now,
                    now
                ],
            )
            .map_err(storage_error)?;
        Ok(())
    }

    fn delete_server(&self, id: &str) -> Result<(), CoreError> {
        self.ensure_schema()?;
        let connection = self.open_connection()?;
        connection
            .execute(
                &format!("DELETE FROM {TABLE_NAME} WHERE id = ?"),
                params![id],
            )
            .map_err(storage_error)?;
        Ok(())
    }
}

fn decode_server_json(json: String) -> Result<ServerInstance, CoreError> {
    serde_json::from_str(&json)
        .map_err(|error| CoreError::storage(format!("invalid server json: {error}")))
}

fn storage_error(error: rusqlite::Error) -> CoreError {
    CoreError::storage(error.to_string())
}

fn unix_timestamp() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs_f64())
        .unwrap_or_default()
}

fn platform_paths() -> Result<LocalAppPaths, CoreError> {
    let app_support = platform_app_data_dir()?;
    Ok(LocalAppPaths {
        db_path: app_support.join("data").join("data.db"),
        working_path: app_support,
    })
}

fn platform_app_data_dir() -> Result<PathBuf, CoreError> {
    #[cfg(target_os = "macos")]
    {
        let home = env_path("HOME")?;
        return Ok(home
            .join("Library")
            .join("Application Support")
            .join(APP_NAME));
    }

    #[cfg(target_os = "windows")]
    {
        if let Some(appdata) = optional_env_path("APPDATA") {
            return Ok(appdata.join(APP_NAME));
        }
        if let Some(local_appdata) = optional_env_path("LOCALAPPDATA") {
            return Ok(local_appdata.join(APP_NAME));
        }
        return Err(CoreError::storage(
            "failed to resolve Windows app data directory".to_string(),
        ));
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        if let Some(xdg_data_home) = optional_env_path("XDG_DATA_HOME") {
            return Ok(xdg_data_home.join(APP_NAME));
        }
        let home = env_path("HOME")?;
        Ok(home.join(".local").join("share").join(APP_NAME))
    }
}

fn env_path(key: &str) -> Result<PathBuf, CoreError> {
    optional_env_path(key).ok_or_else(|| {
        CoreError::storage(format!(
            "failed to resolve required environment variable: {key}"
        ))
    })
}

fn optional_env_path(key: &str) -> Option<PathBuf> {
    std::env::var_os(key).map(PathBuf::from).filter(|path| {
        let value: OsString = path.as_os_str().to_os_string();
        !value.is_empty()
    })
}

#[cfg(test)]
mod tests {
    use super::{APP_NAME, LocalAppServerStore, platform_app_data_dir};
    use scsl_core_domain::{ServerInstance, ServerType};
    use scsl_core_ports::ServerStorePort;
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn stores_and_loads_swift_server_rows() {
        let db_path = temp_db_path();
        let store = LocalAppServerStore::new(&db_path, "/tmp/scsl-work");
        let mut server = ServerInstance::new(
            "server-1",
            "Paper Demo",
            "Paper Demo",
            ServerType::Paper,
            "1.21.1",
            "server.jar",
        );
        server.last_played = 1710000000.0;
        server.java_path = "java".to_string();

        store
            .save_server(server.clone())
            .expect("server should save");

        let loaded = store
            .get_server("server-1")
            .expect("server should load")
            .expect("server should exist");
        assert_eq!(loaded, server);
        assert_eq!(
            store.list_servers().expect("servers should list"),
            vec![server]
        );

        store
            .delete_server("server-1")
            .expect("server should delete");
        assert!(
            store
                .get_server("server-1")
                .expect("query should succeed")
                .is_none()
        );

        let _ = fs::remove_file(db_path);
    }

    #[test]
    fn current_platform_paths_match_app_convention() {
        let store = LocalAppServerStore::for_current_platform().expect("store should resolve");
        let app_dir = platform_app_data_dir().expect("app dir should resolve");
        assert_eq!(store.db_path(), app_dir.join("data").join("data.db"));
        assert_eq!(store.working_path(), app_dir.to_string_lossy());
        assert!(store.working_path().contains(APP_NAME));
    }

    fn temp_db_path() -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be valid")
            .as_nanos();
        std::env::temp_dir().join(format!("scsl-core-swiftdata-{nonce}.db"))
    }
}
