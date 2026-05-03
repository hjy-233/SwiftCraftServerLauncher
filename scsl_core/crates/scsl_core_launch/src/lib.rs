use scsl_core_domain::{CoreError, ServerInstance, ServerType};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ServerLaunchKind {
    CustomCommand,
    ForgeRunScript,
    ForgeUnixArgs,
    ForgeServerJar,
    Jar,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerLaunchPlan {
    pub server_id: String,
    pub server_dir: PathBuf,
    pub launch_command: String,
    pub kind: ServerLaunchKind,
}

impl ServerLaunchPlan {
    pub fn direct_start_script(&self) -> String {
        format!(
            "cd {} && \
            if test -f .scsl.pid && kill -0 $(cat .scsl.pid) 2>/dev/null; then \
              echo __SCSL_ALREADY_RUNNING__; \
            else \
              rm -f .scsl.pid .scsl.stdin .scsl.launch.command .scsl.launch.wrapper; \
              cat > .scsl.launch.command <<'__SCSL_CMD__'\nexec {}\n__SCSL_CMD__\n              cat > .scsl.launch.wrapper <<'__SCSL_WRAPPER__'\n#!/bin/sh\necho $$ > .scsl.pid\nexec /bin/sh ./.scsl.launch.command\n__SCSL_WRAPPER__\n              chmod +x .scsl.launch.command .scsl.launch.wrapper && \
              mkfifo .scsl.stdin && \
              nohup /bin/sh -lc 'tail -f .scsl.stdin | ./.scsl.launch.wrapper' >> scsl-server.log 2>&1 & \
              sleep 1; \
              if test -f .scsl.pid && kill -0 $(cat .scsl.pid) 2>/dev/null; then echo __SCSL_STARTED__; else echo __SCSL_START_FAILED__; fi; \
            fi",
            shell_quote(&self.server_dir.to_string_lossy()),
            self.launch_command,
        )
    }

    pub fn graceful_stop_script(&self) -> String {
        format!(
            "cd {} && \
            if test -p .scsl.stdin; then printf '%s\\n' 'stop' > .scsl.stdin || true; fi && \
            sleep 8 && \
            if test -f .scsl.pid; then \
              pid=$(cat .scsl.pid); \
              if kill -0 \"$pid\" 2>/dev/null; then pkill -TERM -P \"$pid\" 2>/dev/null || true; kill -TERM \"$pid\" 2>/dev/null || true; fi; \
              rm -f .scsl.pid .scsl.stdin .scsl.launch.command .scsl.launch.wrapper; \
            fi",
            shell_quote(&self.server_dir.to_string_lossy())
        )
    }
}

pub struct ServerLaunchPlanner {
    working_path: PathBuf,
}

impl ServerLaunchPlanner {
    pub fn new(working_path: impl Into<PathBuf>) -> Self {
        Self {
            working_path: working_path.into(),
        }
    }

    pub fn server_dir(&self, server: &ServerInstance) -> PathBuf {
        self.working_path
            .join("servers")
            .join(&server.directory_name)
    }

    pub fn plan(&self, server: &ServerInstance) -> Result<ServerLaunchPlan, CoreError> {
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "launch planning currently supports local servers only",
            ));
        }

        let server_dir = self.server_dir(server);
        let custom = server.launch_command.trim();
        if !custom.is_empty() {
            let normalized = normalize_launch_command(custom, &server.java_path);
            return Ok(ServerLaunchPlan {
                server_id: server.id.clone(),
                server_dir,
                launch_command: normalized,
                kind: ServerLaunchKind::CustomCommand,
            });
        }

        let java_path = if server.java_path.trim().is_empty() {
            "java"
        } else {
            server.java_path.trim()
        };
        let mut args = jvm_args(server);

        if server.server_type == ServerType::Forge
            && let Some((kind, command)) = forge_launch_command(&server_dir, java_path, &args)
        {
            return Ok(ServerLaunchPlan {
                server_id: server.id.clone(),
                server_dir,
                launch_command: command,
                kind,
            });
        }

        args.extend([
            "-jar".to_string(),
            server_dir
                .join(&server.server_jar)
                .to_string_lossy()
                .into_owned(),
            "nogui".to_string(),
        ]);

        Ok(ServerLaunchPlan {
            server_id: server.id.clone(),
            server_dir,
            launch_command: shell_join(std::iter::once(java_path.to_string()).chain(args)),
            kind: ServerLaunchKind::Jar,
        })
    }
}

fn jvm_args(server: &ServerInstance) -> Vec<String> {
    let mut args = Vec::new();
    if server.xms > 0 {
        args.push(format!("-Xms{}M", server.xms));
    }
    if server.xmx > 0 {
        args.push(format!("-Xmx{}M", server.xmx));
    }
    if !server.jvm_arguments.trim().is_empty() {
        args.extend(split_args(&server.jvm_arguments));
    }
    args
}

fn forge_launch_command(
    server_dir: &Path,
    java_path: &str,
    base_args: &[String],
) -> Option<(ServerLaunchKind, String)> {
    let run_script = server_dir.join("run.sh");
    if run_script.exists() {
        let java_home = Path::new(java_path)
            .parent()
            .and_then(Path::parent)
            .map(Path::to_path_buf)
            .unwrap_or_else(|| PathBuf::from(java_path));
        return Some((
            ServerLaunchKind::ForgeRunScript,
            format!(
                "env JAVA_HOME={} ./run.sh nogui",
                shell_quote(&java_home.to_string_lossy())
            ),
        ));
    }

    let forge_args = find_unix_args_file(server_dir)
        .map(|path| {
            (
                ServerLaunchKind::ForgeUnixArgs,
                vec![format!("@{}", path.to_string_lossy()), "nogui".to_string()],
            )
        })
        .or_else(|| {
            find_forge_server_jar(server_dir).map(|path| {
                (
                    ServerLaunchKind::ForgeServerJar,
                    vec![
                        "-jar".to_string(),
                        path.to_string_lossy().into_owned(),
                        "nogui".to_string(),
                    ],
                )
            })
        })?;

    let (kind, forge_args) = forge_args;
    Some((
        kind,
        shell_join(
            std::iter::once(java_path.to_string())
                .chain(base_args.iter().cloned())
                .chain(forge_args),
        ),
    ))
}

pub fn append_no_gui_if_needed(command: &str) -> String {
    let tokens = split_args(command);
    if tokens.iter().any(|token| token == "nogui") {
        command.to_string()
    } else {
        format!("{command} nogui")
    }
}

pub fn normalize_launch_command(command: &str, executable_hint: &str) -> String {
    let with_no_gui = append_no_gui_if_needed(command);
    let executable_hint = executable_hint.trim();
    if !executable_hint.is_empty()
        && let Some(rest) = with_no_gui.strip_prefix(executable_hint)
    {
        let rest_tokens = split_args(rest.trim());
        return shell_join(std::iter::once(executable_hint.to_string()).chain(rest_tokens));
    }
    let tokens = split_args(&with_no_gui);
    if tokens.is_empty() {
        with_no_gui
    } else {
        shell_join(tokens)
    }
}

pub fn split_args(input: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut current = String::new();
    let mut quote_char = None;

    for char in input.chars() {
        match (char, quote_char) {
            ('"' | '\'', None) => quote_char = Some(char),
            ('"' | '\'', Some(active)) if active == char => quote_char = None,
            (' ', None) if !current.is_empty() => {
                result.push(std::mem::take(&mut current));
            }
            (' ', None) => {}
            _ => current.push(char),
        }
    }

    if !current.is_empty() {
        result.push(current);
    }
    result
}

pub fn shell_join<I>(values: I) -> String
where
    I: IntoIterator<Item = String>,
{
    values
        .into_iter()
        .map(|value| shell_quote(&value))
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\"'\"'"))
}

fn find_unix_args_file(server_dir: &Path) -> Option<PathBuf> {
    let libraries = server_dir.join("libraries");
    find_file(&libraries, "unix_args.txt")
        .into_iter()
        .find(|path| {
            path.to_string_lossy()
                .contains("/net/minecraftforge/forge/")
        })
}

fn find_forge_server_jar(server_dir: &Path) -> Option<PathBuf> {
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
        ServerLaunchKind, ServerLaunchPlanner, append_no_gui_if_needed, shell_quote, split_args,
    };
    use scsl_core_domain::{ServerInstance, ServerType};
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn plans_standard_jar_launch() {
        let root = temp_dir();
        let server = sample_server(ServerType::Paper);
        let plan = ServerLaunchPlanner::new(&root)
            .plan(&server)
            .expect("plan should build");

        assert_eq!(plan.kind, ServerLaunchKind::Jar);
        assert!(plan.launch_command.contains("-Xmx2048M"));
        assert!(plan.launch_command.contains("server.jar"));
        assert!(plan.launch_command.contains("nogui"));
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn prefers_forge_run_script() {
        let root = temp_dir();
        let server = sample_server(ServerType::Forge);
        let server_dir = root.join("servers").join(&server.directory_name);
        fs::create_dir_all(&server_dir).expect("server dir should create");
        fs::write(server_dir.join("run.sh"), "#!/bin/sh").expect("run script should create");

        let plan = ServerLaunchPlanner::new(&root)
            .plan(&server)
            .expect("plan should build");

        assert_eq!(plan.kind, ServerLaunchKind::ForgeRunScript);
        assert_eq!(plan.launch_command, "env JAVA_HOME='/usr' ./run.sh nogui");
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn appends_no_gui_to_custom_commands() {
        assert_eq!(
            append_no_gui_if_needed("java -jar server.jar"),
            "java -jar server.jar nogui"
        );
        assert_eq!(
            append_no_gui_if_needed("java -jar server.jar nogui"),
            "java -jar server.jar nogui"
        );
    }

    #[test]
    fn splits_quoted_arguments() {
        assert_eq!(
            split_args("-Dfoo='hello world' -Xmx2G"),
            vec!["-Dfoo=hello world".to_string(), "-Xmx2G".to_string()]
        );
    }

    #[test]
    fn quotes_shell_values() {
        assert_eq!(shell_quote("a'b"), "'a'\"'\"'b'");
    }

    fn sample_server(server_type: ServerType) -> ServerInstance {
        let mut server = ServerInstance::new(
            "server-1",
            "Server One",
            "Server One",
            server_type,
            "1.21.1",
            "server.jar",
        );
        server.java_path = "/usr/bin/java".to_string();
        server.xms = 1024;
        server.xmx = 2048;
        server.jvm_arguments = "-Dfile.encoding=UTF-8".to_string();
        server
    }

    fn temp_dir() -> std::path::PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be valid")
            .as_nanos();
        std::env::temp_dir().join(format!("scsl-core-launch-{nonce}"))
    }
}
