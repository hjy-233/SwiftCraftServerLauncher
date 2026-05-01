use scsl_core_domain::{CoreError, ServerInstance};
use scsl_core_launch::ServerLaunchPlanner;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ForgeInstallPlan {
    pub server_id: String,
    pub server_dir: PathBuf,
    pub installer_jar: PathBuf,
    pub java_path: String,
    pub arguments: Vec<String>,
}

impl ForgeInstallPlan {
    pub fn command_line(&self) -> Vec<String> {
        std::iter::once(self.java_path.clone())
            .chain(self.arguments.clone())
            .collect()
    }
}

pub struct ForgeInstallerPlanner {
    launch_planner: ServerLaunchPlanner,
}

impl ForgeInstallerPlanner {
    pub fn new(working_path: impl Into<PathBuf>) -> Self {
        Self {
            launch_planner: ServerLaunchPlanner::new(working_path),
        }
    }

    pub fn has_launch_artifacts(&self, server: &ServerInstance) -> bool {
        has_launch_artifacts(&self.launch_planner.server_dir(server))
    }

    pub fn install_plan(
        &self,
        server: &ServerInstance,
    ) -> Result<Option<ForgeInstallPlan>, CoreError> {
        let server_dir = self.launch_planner.server_dir(server);
        if has_launch_artifacts(&server_dir) || !is_installer_jar(&server.server_jar) {
            return Ok(None);
        }

        let installer_jar = server_dir.join(&server.server_jar);
        if !installer_jar.exists() {
            return Err(CoreError::not_found(
                "forge installer",
                installer_jar.display().to_string(),
            ));
        }

        let java_path = if server.java_path.trim().is_empty() {
            "java".to_string()
        } else {
            server.java_path.clone()
        };
        Ok(Some(ForgeInstallPlan {
            server_id: server.id.clone(),
            server_dir,
            installer_jar: installer_jar.clone(),
            java_path,
            arguments: vec![
                "-jar".to_string(),
                installer_jar.to_string_lossy().into_owned(),
                "--installServer".to_string(),
            ],
        }))
    }

    pub fn install(&self, server: &ServerInstance) -> Result<bool, CoreError> {
        let Some(plan) = self.install_plan(server)? else {
            return Ok(false);
        };
        let status = Command::new(&plan.java_path)
            .args(&plan.arguments)
            .current_dir(&plan.server_dir)
            .status()
            .map_err(|error| {
                CoreError::runtime(format!("failed to run forge installer: {error}"))
            })?;
        if status.success() {
            Ok(true)
        } else {
            Err(CoreError::runtime("forge installer failed"))
        }
    }
}

pub fn is_installer_jar(jar_name: &str) -> bool {
    jar_name.to_lowercase().contains("installer")
}

pub fn has_launch_artifacts(server_dir: &Path) -> bool {
    server_dir.join("run.sh").exists()
        || find_unix_args_file(server_dir).is_some()
        || find_forge_server_jar(server_dir).is_some()
}

pub fn find_unix_args_file(server_dir: &Path) -> Option<PathBuf> {
    let libraries = server_dir.join("libraries");
    find_file(&libraries, "unix_args.txt")
        .into_iter()
        .find(|path| {
            path.to_string_lossy()
                .contains("/net/minecraftforge/forge/")
        })
}

pub fn find_forge_server_jar(server_dir: &Path) -> Option<PathBuf> {
    let entries = fs::read_dir(server_dir).ok()?;
    entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .find(|path| {
            let name = path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or_default()
                .to_lowercase();
            name.starts_with("forge-") && name.ends_with("-server.jar")
        })
}

fn find_file(root: &Path, file_name: &str) -> Vec<PathBuf> {
    let mut found = Vec::new();
    let Ok(entries) = fs::read_dir(root) else {
        return found;
    };
    for entry in entries.filter_map(Result::ok) {
        let path = entry.path();
        if path.is_dir() {
            found.extend(find_file(&path, file_name));
        } else if path.file_name().and_then(|name| name.to_str()) == Some(file_name) {
            found.push(path);
        }
    }
    found
}

#[cfg(test)]
mod tests {
    use super::{
        ForgeInstallerPlanner, find_forge_server_jar, has_launch_artifacts, is_installer_jar,
    };
    use scsl_core_domain::{ServerInstance, ServerType};
    use std::fs;
    use std::sync::atomic::{AtomicU64, Ordering};

    static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn detects_installer_jars() {
        assert!(is_installer_jar("forge-1.20.1-47.4.0-installer.jar"));
        assert!(!is_installer_jar("forge-1.20.1-47.4.0-server.jar"));
    }

    #[test]
    fn detects_launch_artifacts() {
        let root = temp_dir();
        fs::create_dir_all(&root).expect("dir should create");
        assert!(!has_launch_artifacts(&root));
        fs::write(root.join("run.sh"), "").expect("run.sh should create");
        assert!(has_launch_artifacts(&root));
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn finds_forge_server_jar() {
        let root = temp_dir();
        fs::create_dir_all(&root).expect("dir should create");
        fs::write(root.join("forge-1.20.1-47.4.0-server.jar"), "").expect("jar should create");
        assert_eq!(
            find_forge_server_jar(&root)
                .expect("jar should exist")
                .file_name()
                .and_then(|name| name.to_str()),
            Some("forge-1.20.1-47.4.0-server.jar")
        );
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn builds_install_plan_for_installer_without_artifacts() {
        let root = temp_dir();
        let server_dir = root.join("servers").join("forge-server");
        fs::create_dir_all(&server_dir).expect("server dir should create");
        fs::write(server_dir.join("forge-installer.jar"), "").expect("installer should create");
        let mut server = ServerInstance::new(
            "server-1",
            "Forge Server",
            "forge-server",
            ServerType::Forge,
            "1.20.1",
            "forge-installer.jar",
        );
        server.java_path = "/usr/bin/java".to_string();

        let plan = ForgeInstallerPlanner::new(&root)
            .install_plan(&server)
            .expect("plan should resolve")
            .expect("install should be needed");

        assert_eq!(plan.java_path, "/usr/bin/java");
        assert_eq!(
            plan.command_line(),
            vec![
                "/usr/bin/java".to_string(),
                "-jar".to_string(),
                server_dir
                    .join("forge-installer.jar")
                    .to_string_lossy()
                    .into_owned(),
                "--installServer".to_string(),
            ]
        );
        let _ = fs::remove_dir_all(root);
    }

    fn temp_dir() -> std::path::PathBuf {
        let nonce = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!("scsl-core-forge-{nonce}"))
    }
}
