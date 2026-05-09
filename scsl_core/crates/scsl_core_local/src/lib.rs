use scsl_core_domain::{CoreError, LogQuery, LogSnapshot, ServerInstance, ServerStatus};
use scsl_core_launch::ServerLaunchPlanner;
use scsl_core_ports::ServerRuntimePort;
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, Serialize)]
pub struct LocalServerFileEntry {
    pub relative_path: String,
    pub is_directory: bool,
    pub file_size: Option<u64>,
}

#[derive(Debug, Clone, Serialize)]
pub struct LocalLogPollResult {
    pub file_path: Option<String>,
    pub appended_text: String,
    pub next_offset: u64,
}

pub struct LocalServerRuntime {
    planner: ServerLaunchPlanner,
}

impl LocalServerRuntime {
    pub fn new(working_path: impl Into<PathBuf>) -> Self {
        Self {
            planner: ServerLaunchPlanner::new(working_path),
        }
    }

    fn server_dir(&self, server: &ServerInstance) -> PathBuf {
        self.planner.server_dir(server)
    }

    fn resolve_server_path(
        &self,
        server: &ServerInstance,
        relative_path: &str,
    ) -> Result<PathBuf, CoreError> {
        let mut path = self.server_dir(server);
        let relative = Path::new(relative_path);
        for component in relative.components() {
            match component {
                Component::Normal(name) => path.push(name),
                Component::CurDir => {}
                Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                    return Err(CoreError::validation(format!(
                        "invalid server-relative path: {relative_path}"
                    )));
                }
            }
        }
        Ok(path)
    }

    fn run_shell(&self, command: &str) -> Result<String, CoreError> {
        let output = Command::new("/bin/zsh")
            .arg("-lc")
            .arg(command)
            .output()
            .map_err(|error| CoreError::runtime(format!("failed to run shell: {error}")))?;
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        let combined = format!("{stdout}{stderr}");
        if output.status.success() {
            Ok(combined)
        } else {
            Err(CoreError::runtime(combined.trim().to_string()))
        }
    }

    pub fn poll_local_log(
        &self,
        server: &ServerInstance,
        current_file_path: Option<&str>,
        offset: u64,
    ) -> Result<LocalLogPollResult, CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let server_dir = self.server_dir(server);
        for file in self.local_log_candidates(&server_dir) {
            if !file.exists() {
                continue;
            }

            let file_path = file.to_string_lossy().to_string();
            let effective_offset = if current_file_path == Some(file_path.as_str()) {
                offset
            } else {
                0
            };

            if let Some((appended_text, next_offset)) =
                self.read_local_log_update(&file, effective_offset)?
            {
                return Ok(LocalLogPollResult {
                    file_path: Some(file_path),
                    appended_text,
                    next_offset,
                });
            }
        }

        Ok(LocalLogPollResult {
            file_path: None,
            appended_text: String::new(),
            next_offset: 0,
        })
    }

    fn local_log_candidates(&self, server_dir: &Path) -> [PathBuf; 4] {
        [
            server_dir.join("scsl-server.log"),
            server_dir.join("logs/latest.log"),
            server_dir.join("latest.log"),
            server_dir.join("server.log"),
        ]
    }

    fn read_local_log_update(
        &self,
        file: &Path,
        offset: u64,
    ) -> Result<Option<(String, u64)>, CoreError> {
        let metadata = fs::metadata(file)
            .map_err(|error| CoreError::runtime(format!("failed to inspect log file: {error}")))?;
        let file_size = metadata.len();
        let safe_offset = offset.min(file_size);
        let bytes = fs::read(file)
            .map_err(|error| CoreError::runtime(format!("failed to read log file: {error}")))?;
        let appended = if safe_offset as usize >= bytes.len() {
            String::new()
        } else {
            String::from_utf8_lossy(&bytes[safe_offset as usize..]).into_owned()
        };
        Ok(Some((appended, file_size)))
    }

    pub fn send_command(&self, server: &ServerInstance, command: &str) -> Result<(), CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let fifo_path = self.server_dir(server).join(".scsl.stdin");
        let shell = format!(
            "test -p {} && printf '%s\\n' {} > {}",
            shell_quote(&fifo_path.to_string_lossy()),
            shell_quote(command),
            shell_quote(&fifo_path.to_string_lossy())
        );
        self.run_shell(&shell).map(|_| ())
    }

    pub fn send_interrupt(&self, server: &ServerInstance, force: bool) -> Result<(), CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let server_dir = self.server_dir(server);
        let server_dir_quoted = shell_quote(&server_dir.to_string_lossy());
        let command = if force {
            format!(
                "cd {} && \
                if test -f .scsl.pid; then \
                  pid=$(cat .scsl.pid); \
                  pkill -KILL -P \"$pid\" 2>/dev/null || true; \
                  kill -KILL \"$pid\" 2>/dev/null || true; \
                  rm -f .scsl.pid .scsl.stdin; \
                  echo __SCSL_FORCE_INTERRUPTED__; \
                else \
                  echo __SCSL_PID_MISSING__; \
                fi",
                server_dir_quoted
            )
        } else {
            format!(
                "cd {} && \
                if test -p .scsl.stdin; then printf '%s\\n' 'stop' > .scsl.stdin || true; fi && \
                sleep 8 && \
                if test -f .scsl.pid; then \
                  pid=$(cat .scsl.pid); \
                  if kill -0 \"$pid\" 2>/dev/null; then \
                    pkill -INT -P \"$pid\" 2>/dev/null || true; \
                    kill -INT \"$pid\" 2>/dev/null || true; \
                    sleep 2; \
                  fi; \
                  if kill -0 \"$pid\" 2>/dev/null; then \
                    pkill -TERM -P \"$pid\" 2>/dev/null || true; \
                    kill -TERM \"$pid\" 2>/dev/null || true; \
                  fi; \
                  rm -f .scsl.pid .scsl.stdin; \
                  echo __SCSL_INTERRUPTED__; \
                else \
                  echo __SCSL_PID_MISSING__; \
                fi",
                server_dir_quoted
            )
        };
        self.run_shell(&command).map(|_| ())
    }

    pub fn direct_mode_available(&self, server: &ServerInstance) -> bool {
        let fifo_path = self.server_dir(server).join(".scsl.stdin");
        fifo_path.exists()
    }

    pub fn read_server_properties(
        &self,
        server: &ServerInstance,
    ) -> Result<BTreeMap<String, String>, CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let path = self.server_dir(server).join("server.properties");
        if !path.exists() {
            return Ok(BTreeMap::new());
        }

        let content = fs::read_to_string(&path).map_err(|error| {
            CoreError::runtime(format!("failed to read server.properties: {error}"))
        })?;
        let mut result = BTreeMap::new();
        for line in content.lines() {
            let raw = line.trim();
            if raw.is_empty() || raw.starts_with('#') {
                continue;
            }
            if let Some((key, value)) = raw.split_once('=') {
                result.insert(key.trim().to_string(), value.trim().to_string());
            }
        }
        Ok(result)
    }

    pub fn write_server_properties(
        &self,
        server: &ServerInstance,
        properties: &BTreeMap<String, String>,
    ) -> Result<(), CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let path = self.server_dir(server).join("server.properties");
        let content = properties
            .iter()
            .map(|(key, value)| format!("{key}={value}"))
            .collect::<Vec<_>>()
            .join("\n");
        let content = if content.is_empty() {
            String::new()
        } else {
            format!("{content}\n")
        };
        fs::write(&path, content).map_err(|error| {
            CoreError::runtime(format!("failed to write server.properties: {error}"))
        })
    }

    pub fn list_server_files(
        &self,
        server: &ServerInstance,
    ) -> Result<Vec<LocalServerFileEntry>, CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let root = self.server_dir(server);
        if !root.exists() {
            return Ok(Vec::new());
        }

        let mut entries = Vec::new();
        self.collect_server_files(&root, &root, &mut entries)?;
        entries.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
        Ok(entries)
    }

    pub fn read_server_file_text(
        &self,
        server: &ServerInstance,
        relative_path: &str,
    ) -> Result<String, CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let path = self.resolve_server_path(server, relative_path)?;
        let bytes = fs::read(&path)
            .map_err(|error| CoreError::runtime(format!("failed to read file: {error}")))?;
        Ok(String::from_utf8_lossy(&bytes).into_owned())
    }

    pub fn write_server_file_text(
        &self,
        server: &ServerInstance,
        relative_path: &str,
        content: &str,
    ) -> Result<(), CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let path = self.resolve_server_path(server, relative_path)?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|error| {
                CoreError::runtime(format!("failed to create parent directory: {error}"))
            })?;
        }
        fs::write(&path, content)
            .map_err(|error| CoreError::runtime(format!("failed to write file: {error}")))
    }

    pub fn create_server_directory(
        &self,
        server: &ServerInstance,
        relative_path: &str,
    ) -> Result<(), CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let path = self.resolve_server_path(server, relative_path)?;
        fs::create_dir_all(&path)
            .map_err(|error| CoreError::runtime(format!("failed to create directory: {error}")))
    }

    pub fn create_server_file(
        &self,
        server: &ServerInstance,
        relative_path: &str,
    ) -> Result<(), CoreError> {
        self.write_server_file_text(server, relative_path, "")
    }

    pub fn move_server_path(
        &self,
        server: &ServerInstance,
        source_relative_path: &str,
        target_relative_path: &str,
    ) -> Result<(), CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let source = self.resolve_server_path(server, source_relative_path)?;
        let target = self.resolve_server_path(server, target_relative_path)?;
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent).map_err(|error| {
                CoreError::runtime(format!("failed to create parent directory: {error}"))
            })?;
        }
        if target.exists() {
            remove_existing_path(&target)?;
        }
        fs::rename(&source, &target).map_err(|error| {
            CoreError::runtime(format!(
                "failed to move {} to {}: {error}",
                source_relative_path, target_relative_path
            ))
        })
    }

    pub fn remove_server_path(
        &self,
        server: &ServerInstance,
        relative_path: &str,
    ) -> Result<(), CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let path = self.resolve_server_path(server, relative_path)?;
        remove_existing_path(&path)
    }

    pub fn import_server_path(
        &self,
        server: &ServerInstance,
        source_path: &Path,
        target_directory: &str,
    ) -> Result<(), CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let target_dir = self.resolve_server_path(server, target_directory)?;
        fs::create_dir_all(&target_dir).map_err(|error| {
            CoreError::runtime(format!("failed to create target directory: {error}"))
        })?;
        let file_name = source_path.file_name().ok_or_else(|| {
            CoreError::validation(format!(
                "source path does not have a file name: {}",
                source_path.display()
            ))
        })?;
        let target_path = target_dir.join(file_name);
        if target_path.exists() {
            remove_existing_path(&target_path)?;
        }
        copy_path_recursively(source_path, &target_path)
    }

    pub fn read_schedules_json(&self, server: &ServerInstance) -> Result<String, CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let path = self.server_dir(server).join(".scsl").join("schedules.json");
        if !path.exists() {
            return Ok("[]".to_string());
        }

        fs::read_to_string(&path)
            .map_err(|error| CoreError::runtime(format!("failed to read schedules.json: {error}")))
    }

    pub fn write_schedules_json(
        &self,
        server: &ServerInstance,
        schedules_json: &str,
    ) -> Result<(), CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let payload: Value = serde_json::from_str(schedules_json)
            .map_err(|error| CoreError::validation(format!("invalid schedules json: {error}")))?;
        if !payload.is_array() {
            return Err(CoreError::validation("schedules json must be an array"));
        }

        let path = self.server_dir(server).join(".scsl").join("schedules.json");
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|error| {
                CoreError::runtime(format!("failed to create schedules directory: {error}"))
            })?;
        }
        let normalized = serde_json::to_string_pretty(&payload).map_err(|error| {
            CoreError::runtime(format!("failed to encode schedules json: {error}"))
        })?;
        fs::write(&path, format!("{normalized}\n"))
            .map_err(|error| CoreError::runtime(format!("failed to write schedules.json: {error}")))
    }

    pub fn remove_server_directory(&self, server: &ServerInstance) -> Result<(), CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let path = self.server_dir(server);
        remove_existing_path(&path)
    }

    fn collect_server_files(
        &self,
        root: &Path,
        current: &Path,
        entries: &mut Vec<LocalServerFileEntry>,
    ) -> Result<(), CoreError> {
        for child in fs::read_dir(current)
            .map_err(|error| CoreError::runtime(format!("failed to read directory: {error}")))?
        {
            let child = child.map_err(|error| {
                CoreError::runtime(format!("failed to inspect directory entry: {error}"))
            })?;
            let path = child.path();
            let name = child.file_name();
            let name = name.to_string_lossy();
            if name.starts_with('.') || name.eq_ignore_ascii_case("eula.txt") {
                continue;
            }

            let metadata = child.metadata().map_err(|error| {
                CoreError::runtime(format!("failed to inspect file metadata: {error}"))
            })?;
            let relative_path = path
                .strip_prefix(root)
                .map_err(|error| {
                    CoreError::runtime(format!("failed to compute relative path: {error}"))
                })?
                .to_string_lossy()
                .replace('\\', "/");
            let is_directory = metadata.is_dir();
            entries.push(LocalServerFileEntry {
                relative_path,
                is_directory,
                file_size: if is_directory {
                    None
                } else {
                    Some(metadata.len())
                },
            });

            if is_directory {
                self.collect_server_files(root, &path, entries)?;
            }
        }
        Ok(())
    }
}

impl ServerRuntimePort for LocalServerRuntime {
    fn start(&self, server: &ServerInstance) -> Result<(), CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local CLI runtime only supports local servers",
            ));
        }

        let server_dir = self.server_dir(server);
        if !server_dir.exists() {
            return Err(CoreError::not_found(
                "server directory",
                server_dir.display().to_string(),
            ));
        }

        let plan = self.planner.plan(server)?;
        let output = self.run_shell(&plan.direct_start_script())?;
        if output.contains("__SCSL_ALREADY_RUNNING__") {
            return Err(CoreError::runtime("server is already running"));
        }
        if output.contains("__SCSL_STARTED__") {
            return Ok(());
        }
        Err(CoreError::runtime(
            "local server start failed; check scsl-server.log",
        ))
    }

    fn stop(&self, server: &ServerInstance) -> Result<(), CoreError> {
        let plan = self.planner.plan(server)?;
        self.run_shell(&plan.graceful_stop_script()).map(|_| ())
    }

    fn status(&self, server: &ServerInstance) -> Result<ServerStatus, CoreError> {
        let pid_path = self.server_dir(server).join(".scsl.pid");
        let Ok(pid) = fs::read_to_string(&pid_path) else {
            return Ok(ServerStatus::Stopped);
        };
        let pid = pid.trim();
        if pid.is_empty() {
            return Ok(ServerStatus::Stopped);
        }
        let status = Command::new("kill")
            .arg("-0")
            .arg(pid)
            .status()
            .map_err(|error| CoreError::runtime(format!("failed to inspect process: {error}")))?;
        if status.success() {
            Ok(ServerStatus::Running)
        } else {
            let _ = fs::remove_file(pid_path);
            let _ = fs::remove_file(self.server_dir(server).join(".scsl.stdin"));
            Ok(ServerStatus::Stopped)
        }
    }

    fn logs(&self, server: &ServerInstance, query: LogQuery) -> Result<LogSnapshot, CoreError> {
        let status = self.status(server)?;
        let log_path = self.server_dir(server).join("scsl-server.log");
        if !log_path.exists() {
            return Ok(LogSnapshot {
                status,
                lines: Vec::new(),
            });
        }
        let output = Command::new("tail")
            .arg("-n")
            .arg(query.max_lines.to_string())
            .arg(&log_path)
            .output()
            .map_err(|error| CoreError::runtime(format!("failed to read log: {error}")))?;
        if !output.status.success() {
            return Err(CoreError::runtime(
                String::from_utf8_lossy(&output.stderr).trim().to_string(),
            ));
        }
        Ok(LogSnapshot {
            status,
            lines: String::from_utf8_lossy(&output.stdout)
                .lines()
                .map(str::to_string)
                .collect(),
        })
    }
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\"'\"'"))
}

fn remove_existing_path(path: &Path) -> Result<(), CoreError> {
    if !path.exists() {
        return Ok(());
    }

    let metadata = fs::metadata(path)
        .map_err(|error| CoreError::runtime(format!("failed to inspect path metadata: {error}")))?;
    if metadata.is_dir() {
        fs::remove_dir_all(path)
            .map_err(|error| CoreError::runtime(format!("failed to remove directory: {error}")))
    } else {
        fs::remove_file(path)
            .map_err(|error| CoreError::runtime(format!("failed to remove file: {error}")))
    }
}

fn copy_path_recursively(source: &Path, destination: &Path) -> Result<(), CoreError> {
    let metadata = fs::metadata(source)
        .map_err(|error| CoreError::runtime(format!("failed to inspect source path: {error}")))?;
    if metadata.is_dir() {
        fs::create_dir_all(destination).map_err(|error| {
            CoreError::runtime(format!("failed to create destination directory: {error}"))
        })?;
        for child in fs::read_dir(source).map_err(|error| {
            CoreError::runtime(format!("failed to read source directory: {error}"))
        })? {
            let child = child.map_err(|error| {
                CoreError::runtime(format!("failed to inspect source directory entry: {error}"))
            })?;
            let child_path = child.path();
            let child_destination = destination.join(child.file_name());
            copy_path_recursively(&child_path, &child_destination)?;
        }
        return Ok(());
    }

    if let Some(parent) = destination.parent() {
        fs::create_dir_all(parent).map_err(|error| {
            CoreError::runtime(format!("failed to create destination parent: {error}"))
        })?;
    }
    fs::copy(source, destination)
        .map(|_| ())
        .map_err(|error| map_copy_error(error, source, destination))
}

fn map_copy_error(error: io::Error, source: &Path, destination: &Path) -> CoreError {
    CoreError::runtime(format!(
        "failed to copy {} to {}: {error}",
        source.display(),
        destination.display()
    ))
}
