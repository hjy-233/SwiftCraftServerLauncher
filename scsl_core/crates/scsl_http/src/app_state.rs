use scsl_core::{CoreError, LocalAppServerStore, LocalServerRuntime, ScslCore};
use std::path::PathBuf;

#[derive(Clone)]
pub struct AppState {
    pub db_path: PathBuf,
    pub working_path: String,
}

impl AppState {
    pub fn for_current_platform() -> Result<Self, CoreError> {
        let paths = LocalAppServerStore::platform_paths()?;
        Ok(Self {
            db_path: paths.db_path,
            working_path: paths.working_path.to_string_lossy().into_owned(),
        })
    }

    pub fn core(&self) -> ScslCore<LocalAppServerStore, LocalServerRuntime> {
        ScslCore::new(
            LocalAppServerStore::new(&self.db_path, self.working_path.clone()),
            LocalServerRuntime::new(self.working_path.clone()),
        )
    }
}
