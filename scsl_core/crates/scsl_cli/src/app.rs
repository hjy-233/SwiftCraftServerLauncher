use crate::args::{
    AgentCommand, Cli, Command, GameCommand, MirrorCommand, MirrorCustomConfigArgs,
    MirrorCustomCoreArgs, MirrorCustomCoreGameArgs, MirrorCustomDetailArgs, ModrinthCommand,
    ModrinthSearchArgs, ResourceCommand, ServerCommand, ServerCreateArgs, ServerFileImportArgs,
    ServerFilesCommand, ServerGameVersionsArgs, ServerJavaPathArgs, ServerLoaderVersionsArgs,
    ServerPlayersCommand, ServerPropertiesCommand, ServerResolveDownloadArgs,
    ServerSchedulesCommand, SettingsCommand,
};
use crate::response::{
    AckResponse, BackupEntryResponse, BackupRestoreResponse, DeleteCorruptedResponse,
    DownloadTargetResponse, FileHashResponse, ForgeInstallPlanResponse, GameLaunchPlanResponse,
    JavaVersionResponse, LatestLoaderResponse, LocalLogPollResponse, LocalStartPlanResponse,
    LogSnapshotResponse, PortProcessInfoResponse, RconResponse, ResourceDownloadResponse,
    ResourceFileHashResponse, ServerCreateResponse, ServerDetailResponse, ServerFileReadResponse,
    ServerOperationResponse, ServerSummaryResponse, VerifyJarResponse,
};
use chrono::{Datelike, Local, Timelike};
use fastnbt::{from_bytes as nbt_from_bytes, to_bytes as nbt_to_bytes};
use flate2::read::GzDecoder;
use regex::Regex;
use scsl_core::{
    CoreError, ForgeInstallerPlanner, InMemoryRuntime, InMemoryStore, LocalAppServerStore,
    LocalServerFileEntry, LocalServerRuntime, LogQuery, ResourceDownloadPlanner, ResourceType,
    ScslCore, ServerDownloadPlanner, ServerInstance, ServerInventory, ServerInventoryAnalyzer,
    ServerLaunchPlanner, ServerRuntimePort, ServerStatus, ServerStorePort, ServerType,
    download_file_to_path, fabric_server_jar_target, fastmirror_core_detail_url,
    fastmirror_core_name, forge_installer_target, mirror_direct_target, sample_local_server,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fs;
use std::fs::File;
use std::io::Read;
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::process::Command as ProcessCommand;
use std::thread;
use std::time::{Duration, Instant, UNIX_EPOCH};
use zip::ZipArchive;

pub fn build_app(cli: &Cli) -> Result<CliApp, CoreError> {
    if cli.demo {
        return Ok(build_demo_app());
    }

    let default_store = LocalAppServerStore::for_current_platform()?;
    let db_path = cli
        .db
        .clone()
        .unwrap_or_else(|| default_store.db_path().to_path_buf());
    let persisted_settings = read_cli_settings().ok();
    let working_path = cli
        .working_path
        .clone()
        .or_else(|| {
            persisted_settings
                .as_ref()
                .and_then(|settings| settings.general.launcher_working_directory.clone())
                .filter(|value| !value.trim().is_empty())
        })
        .unwrap_or_else(|| default_store.working_path().to_string());

    Ok(CliApp {
        core: ScslCore::new(
            CliServerStore::SwiftData(LocalAppServerStore::new(db_path, working_path.clone())),
            CliServerRuntime::Local(LocalServerRuntime::new(working_path.clone())),
        ),
        inventory_analyzer: ServerInventoryAnalyzer::new(
            PathBuf::from(&working_path).join("servers"),
        ),
        download_planner: ServerDownloadPlanner::new(&working_path),
        resource_download_planner: ResourceDownloadPlanner::new(&working_path),
        forge_installer: ForgeInstallerPlanner::new(&working_path),
        launch_planner: ServerLaunchPlanner::new(working_path),
    })
}

pub fn run_command(app: &CliApp, command: Command) -> Result<Value, CoreError> {
    match command {
        Command::Server(command) => run_server_command(app, command),
        Command::Mirror(command) => run_mirror_command(command),
        Command::Modrinth(command) => run_modrinth_command(command),
        Command::Resource(command) => run_resource_command(app, command),
        Command::Game(command) => run_game_command(command),
        Command::Settings(command) => run_settings_command(command),
        Command::Agent(command) => run_agent_command(app, command),
    }
}

const AGENT_LABEL: &str = "org.dcstudio.swiftcraftserverlauncher.scsl-agent";

fn run_game_command(command: GameCommand) -> Result<Value, CoreError> {
    match command {
        GameCommand::LaunchPlan(args) => Ok(json!(build_game_launch_plan(&args.json)?)),
        GameCommand::MavenRelativePath(args) => Ok(json!(
            maven_coordinate_to_relative_path_for_url(&args.coordinate)
        )),
        GameCommand::MavenPath(args) => Ok(json!(maven_coordinate_to_full_path(
            &args.coordinate,
            &args.libraries_dir,
        ))),
        GameCommand::LoaderClasspath(args) => Ok(json!(build_loader_classpath(
            &args.json,
            &args.libraries_dir,
            args.include_in_classpath_only,
        )?)),
        GameCommand::ProcessLoaderPlaceholders(args) => {
            Ok(process_loader_placeholders(&args.json, &args.game_version)?)
        }
        GameCommand::ExecuteProcessor(args) => {
            execute_loader_processor(&args.json)?;
            Ok(json!(AckResponse { ok: true }))
        }
        GameCommand::DownloadFile(args) => Ok(json!(ResourceDownloadResponse {
            path: download_file_with_headers(
                &args.url,
                Path::new(&args.destination),
                args.sha1.as_deref(),
                args.headers_json.as_deref(),
            )?
            .display()
            .to_string(),
        })),
        GameCommand::FetchJson(args) => {
            let headers = parse_headers_json(args.headers_json.as_deref())?;
            let header_refs = headers
                .iter()
                .map(|(name, value)| (name.as_str(), value.as_str()))
                .collect::<Vec<_>>();
            Ok(json!(fetch_plain_text(&args.url, &header_refs)?))
        }
        GameCommand::SetExecutable(args) => {
            set_executable_permission(Path::new(&args.path))?;
            Ok(json!(AckResponse { ok: true }))
        }
        GameCommand::ExtractZuluRuntime(args) => {
            extract_zulu_runtime(Path::new(&args.zip_path), Path::new(&args.target_directory))?;
            Ok(json!(AckResponse { ok: true }))
        }
        GameCommand::Sha1File(args) => Ok(json!(FileHashResponse {
            sha1: compute_sha1_file(Path::new(&args.path))?,
        })),
        GameCommand::HashResourceFiles(args) => {
            Ok(json!(hash_resource_files(Path::new(&args.directory,))?))
        }
        GameCommand::BackupCreate(args) => {
            create_backup_archive(
                Path::new(&args.source_root),
                Path::new(&args.output_path),
                args.keep_count,
            )?;
            Ok(json!(ResourceDownloadResponse {
                path: args.output_path,
            }))
        }
        GameCommand::BackupList(args) => {
            Ok(json!(list_backup_archives(Path::new(&args.backup_root,))?))
        }
        GameCommand::BackupListServers(args) => {
            Ok(json!(list_backup_servers(Path::new(&args.backup_path,))?))
        }
        GameCommand::BackupRestore(args) => Ok(json!(restore_backup_server(
            Path::new(&args.backup_path),
            &args.server_name,
            Path::new(&args.target_root),
        )?)),
        GameCommand::ServerAddressesRead(args) => {
            Ok(json!(read_server_addresses(Path::new(&args.path))?))
        }
        GameCommand::ServerAddressesWrite(args) => {
            let mut servers = String::new();
            std::io::stdin()
                .read_to_string(&mut servers)
                .map_err(|error| CoreError::runtime(format!("failed to read stdin: {error}")))?;
            write_server_addresses(Path::new(&args.path), &servers)?;
            Ok(json!(AckResponse { ok: true }))
        }
        GameCommand::LitematicaMetadata(args) => {
            Ok(read_litematica_metadata(Path::new(&args.path), false)?)
        }
        GameCommand::LitematicaFullMetadata(args) => {
            Ok(read_litematica_metadata(Path::new(&args.path), true)?)
        }
    }
}

fn run_settings_command(command: SettingsCommand) -> Result<Value, CoreError> {
    match command {
        SettingsCommand::Read(args) => {
            let settings = read_cli_settings().unwrap_or_default();
            match args.scope.trim().to_ascii_lowercase().as_str() {
                "general" => serde_json::to_value(settings.general).map_err(|error| {
                    CoreError::runtime(format!("failed to encode general settings: {error}"))
                }),
                "game" => serde_json::to_value(settings.game).map_err(|error| {
                    CoreError::runtime(format!("failed to encode game settings: {error}"))
                }),
                "theme" => serde_json::to_value(settings.theme).map_err(|error| {
                    CoreError::runtime(format!("failed to encode theme settings: {error}"))
                }),
                "ai" => serde_json::to_value(settings.ai).map_err(|error| {
                    CoreError::runtime(format!("failed to encode ai settings: {error}"))
                }),
                "mirror" => serde_json::to_value(settings.mirror_sources).map_err(|error| {
                    CoreError::runtime(format!("failed to encode mirror settings: {error}"))
                }),
                other => Err(CoreError::validation(format!(
                    "unknown settings scope: {other}"
                ))),
            }
        }
        SettingsCommand::Write(args) => {
            let mut settings = read_cli_settings().unwrap_or_default();
            match args.scope.trim().to_ascii_lowercase().as_str() {
                "general" => {
                    settings.general = serde_json::from_str(&args.json).map_err(|error| {
                        CoreError::validation(format!("invalid general settings json: {error}"))
                    })?;
                }
                "game" => {
                    settings.game = serde_json::from_str(&args.json).map_err(|error| {
                        CoreError::validation(format!("invalid game settings json: {error}"))
                    })?;
                }
                "theme" => {
                    settings.theme = serde_json::from_str(&args.json).map_err(|error| {
                        CoreError::validation(format!("invalid theme settings json: {error}"))
                    })?;
                }
                "ai" => {
                    settings.ai = serde_json::from_str(&args.json).map_err(|error| {
                        CoreError::validation(format!("invalid ai settings json: {error}"))
                    })?;
                }
                "mirror" => {
                    settings.mirror_sources =
                        serde_json::from_str(&args.json).map_err(|error| {
                            CoreError::validation(format!("invalid mirror settings json: {error}"))
                        })?;
                }
                other => {
                    return Err(CoreError::validation(format!(
                        "unknown settings scope: {other}"
                    )));
                }
            }
            write_cli_settings(&settings)?;
            Ok(json!(AckResponse { ok: true }))
        }
    }
}

fn run_agent_command(app: &CliApp, command: AgentCommand) -> Result<Value, CoreError> {
    match command {
        AgentCommand::Status => Ok(agent_status_json()?),
        AgentCommand::Start => {
            ensure_launch_agent()?;
            Ok(json!(AckResponse { ok: true }))
        }
        AgentCommand::Ensure => {
            ensure_launch_agent()?;
            Ok(json!(AckResponse { ok: true }))
        }
        AgentCommand::Stop => {
            stop_launch_agent()?;
            Ok(json!(AckResponse { ok: true }))
        }
        AgentCommand::Run => run_background_agent(app),
    }
}

pub fn ensure_background_agent(_cli: &Cli) -> Result<(), CoreError> {
    ensure_launch_agent()
}

fn agent_status_json() -> Result<Value, CoreError> {
    let plist_path = agent_plist_path()?;
    let status = agent_status()?;
    Ok(json!({
        "label": AGENT_LABEL,
        "plistPath": plist_path.display().to_string(),
        "isInstalled": plist_path.exists(),
        "isRunning": status,
    }))
}

fn ensure_launch_agent() -> Result<(), CoreError> {
    let plist_path = write_launch_agent_plist()?;
    if agent_status()? {
        return Ok(());
    }
    let domain = launchctl_domain()?;
    let _ = ProcessCommand::new("launchctl")
        .args(["bootout", &domain, AGENT_LABEL])
        .output();
    let bootstrap = ProcessCommand::new("launchctl")
        .args(["bootstrap", &domain, &plist_path.to_string_lossy()])
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to start launch agent: {error}")))?;
    if !bootstrap.status.success() {
        let stderr = String::from_utf8_lossy(&bootstrap.stderr)
            .trim()
            .to_string();
        if !stderr.contains("already bootstrapped") {
            return Err(CoreError::runtime(if stderr.is_empty() {
                "failed to bootstrap launch agent".to_string()
            } else {
                stderr
            }));
        }
    }
    let _ = ProcessCommand::new("launchctl")
        .args(["kickstart", "-k", &format!("{}/{}", domain, AGENT_LABEL)])
        .output();
    Ok(())
}

fn stop_launch_agent() -> Result<(), CoreError> {
    let domain = launchctl_domain()?;
    let _ = ProcessCommand::new("launchctl")
        .args(["bootout", &domain, AGENT_LABEL])
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to stop launch agent: {error}")))?;
    Ok(())
}

fn agent_status() -> Result<bool, CoreError> {
    let domain = launchctl_domain()?;
    let output = ProcessCommand::new("launchctl")
        .args(["print", &format!("{}/{}", domain, AGENT_LABEL)])
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to inspect launch agent: {error}")))?;
    Ok(output.status.success())
}

fn launchctl_domain() -> Result<String, CoreError> {
    let output = ProcessCommand::new("id")
        .arg("-u")
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to resolve uid: {error}")))?;
    if !output.status.success() {
        return Err(CoreError::runtime("failed to resolve uid".to_string()));
    }
    Ok(format!(
        "gui/{}",
        String::from_utf8_lossy(&output.stdout).trim()
    ))
}

fn agent_plist_path() -> Result<PathBuf, CoreError> {
    let home = std::env::var("HOME").map_err(|error| {
        CoreError::runtime(format!("failed to resolve home directory: {error}"))
    })?;
    Ok(PathBuf::from(home)
        .join("Library")
        .join("LaunchAgents")
        .join(format!("{AGENT_LABEL}.plist")))
}

fn write_launch_agent_plist() -> Result<PathBuf, CoreError> {
    let plist_path = agent_plist_path()?;
    let executable = std::env::current_exe().map_err(|error| {
        CoreError::runtime(format!("failed to resolve current executable: {error}"))
    })?;
    if let Some(parent) = plist_path.parent() {
        fs::create_dir_all(parent).map_err(|error| {
            CoreError::runtime(format!("failed to create LaunchAgents directory: {error}"))
        })?;
    }
    let plist = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>{label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>{exe}</string>
    <string>agent</string>
    <string>run</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>{stdout}</string>
  <key>StandardErrorPath</key>
  <string>{stderr}</string>
</dict>
</plist>
"#,
        label = AGENT_LABEL,
        exe = xml_escape(&executable.to_string_lossy()),
        stdout = xml_escape(&agent_stdout_path()?.to_string_lossy()),
        stderr = xml_escape(&agent_stderr_path()?.to_string_lossy()),
    );
    fs::write(&plist_path, plist).map_err(|error| {
        CoreError::runtime(format!("failed to write launch agent plist: {error}"))
    })?;
    Ok(plist_path)
}

fn agent_stdout_path() -> Result<PathBuf, CoreError> {
    Ok(LocalAppServerStore::platform_paths()?
        .working_path
        .join("logs")
        .join("scsl-agent.stdout.log"))
}

fn agent_stderr_path() -> Result<PathBuf, CoreError> {
    Ok(LocalAppServerStore::platform_paths()?
        .working_path
        .join("logs")
        .join("scsl-agent.stderr.log"))
}

fn xml_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

fn run_background_agent(app: &CliApp) -> Result<Value, CoreError> {
    let mut agent = BackgroundAgent::new();
    loop {
        agent.tick(app)?;
        thread::sleep(Duration::from_secs(1));
    }
}

fn run_server_command(app: &CliApp, command: ServerCommand) -> Result<Value, CoreError> {
    match command {
        ServerCommand::List => Ok(json!(
            app.inventory()?
                .servers
                .into_iter()
                .map(ServerSummaryResponse::from)
                .collect::<Vec<_>>()
        )),
        ServerCommand::Show(args) => Ok(json!(ServerDetailResponse::from(
            app.require_inventory_server(&args.id)?
        ))),
        ServerCommand::Delete(args) => {
            app.delete_local_server(&args.id)?;
            Ok(json!(AckResponse { ok: true }))
        }
        ServerCommand::DeleteCorrupted(args) => {
            let deleted_count = app.delete_corrupted_local_servers(&args.name)?;
            Ok(json!(DeleteCorruptedResponse { deleted_count }))
        }
        ServerCommand::LaunchCommand(args) => {
            let server = app.require_inventory_server(&args.id)?;
            let plan = app.launch_planner.plan(&server)?;
            Ok(json!({ "launchCommand": plan.launch_command }))
        }
        ServerCommand::LocalStartPlan(args) => Ok(json!(app.local_start_plan(args)?)),
        ServerCommand::LocalStart(args) => {
            app.local_start(args)?;
            Ok(json!(AckResponse { ok: true }))
        }
        ServerCommand::LocalLogPoll(args) => {
            let server = app.require_inventory_server(&args.id)?;
            let runtime = app.local_runtime()?;
            Ok(json!(LocalLogPollResponse::from(runtime.poll_local_log(
                &server,
                args.current_file_path.as_deref(),
                args.offset,
            )?)))
        }
        ServerCommand::CreateLocal(args) => Ok(json!(app.create_local_server(args)?)),
        ServerCommand::DownloadTarget(args) => Ok(json!(DownloadTargetResponse::from(
            app.resolve_server_download_target(args)?
        ))),
        ServerCommand::Corrupted => Ok(json!(app.inventory()?.corrupted_server_names)),
        ServerCommand::GameVersions(args) => Ok(json!(app.available_game_versions(args)?)),
        ServerCommand::LoaderVersions(args) => Ok(json!(app.available_loader_versions(args)?)),
        ServerCommand::JavaVersion(args) => Ok(json!(JavaVersionResponse::from(
            app.resolve_java_version(&args.game_version)?
        ))),
        ServerCommand::LatestLoader(args) => Ok(json!(LatestLoaderResponse {
            version: app.resolve_latest_loader(&args.server_type, &args.game_version)?,
        })),
        ServerCommand::VerifyJar(args) => {
            let server = app.require_inventory_server(&args.id)?;
            Ok(json!(VerifyJarResponse {
                valid: app.download_planner.verify_local_jar_integrity(&server)
            }))
        }
        ServerCommand::ForgeInstallPlan(args) => {
            let server = app.require_inventory_server(&args.id)?;
            let plan = app.forge_installer.install_plan(&server)?;
            Ok(match plan {
                Some(plan) => {
                    let command = plan.command_line();
                    json!(ForgeInstallPlanResponse {
                        server_id: plan.server_id,
                        server_dir: plan.server_dir.display().to_string(),
                        installer_jar: plan.installer_jar.display().to_string(),
                        command,
                    })
                }
                None => Value::Null,
            })
        }
        ServerCommand::Status(args) => Ok(json!(ServerOperationResponse {
            status: app.core.server_status(&args.id)?,
        })),
        ServerCommand::Start(args) => Ok(json!(ServerOperationResponse {
            status: app.core.start_server(&args.id)?,
        })),
        ServerCommand::Stop(args) => Ok(json!(ServerOperationResponse {
            status: app.core.stop_server(&args.id)?,
        })),
        ServerCommand::Restart(args) => Ok(json!(ServerOperationResponse {
            status: app.core.restart_server(&args.id)?,
        })),
        ServerCommand::Logs(args) => Ok(json!(LogSnapshotResponse::from(
            app.core.server_logs(&args.id, LogQuery::tail(args.lines))?
        ))),
        ServerCommand::Send(args) => {
            app.send_direct_command(&args.id, &args.command)?;
            Ok(json!(AckResponse { ok: true }))
        }
        ServerCommand::Interrupt(args) => {
            app.interrupt_server(&args.id, args.force)?;
            Ok(json!(AckResponse { ok: true }))
        }
        ServerCommand::Rcon(args) => Ok(json!(RconResponse {
            output: app.execute_local_rcon(&args.id, &args.command)?,
        })),
        ServerCommand::Properties(command) => run_server_properties_command(app, command),
        ServerCommand::Files(command) => run_server_files_command(app, command),
        ServerCommand::Players(command) => run_server_players_command(app, command),
        ServerCommand::Schedules(command) => run_server_schedules_command(app, command),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServerCreateRequest {
    id: String,
    name: String,
    directory_name: String,
    icon_name: String,
    icon_image_file_name: Option<String>,
    server_type: ServerType,
    game_version: String,
    loader_version: String,
    launch_command: Option<String>,
    java_path: String,
    jvm_arguments: Option<String>,
    xms: Option<i32>,
    xmx: Option<i32>,
    console_mode: Option<scsl_core::ConsoleMode>,
    rcon_port: Option<i32>,
    rcon_password: Option<String>,
    accept_eula: bool,
    source: ServerCreateSource,
}

#[derive(Deserialize)]
#[serde(tag = "type")]
enum ServerCreateSource {
    #[serde(rename = "customJar", alias = "CustomJar")]
    CustomJar {
        #[serde(alias = "sourcePath")]
        source_path: String,
    },
    #[serde(rename = "download", alias = "Download")]
    Download {
        url: String,
        #[serde(alias = "fileName")]
        file_name: String,
        sha1: Option<String>,
        headers: Option<BTreeMap<String, String>>,
    },
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServerDownloadTargetRequest {
    server_type: ServerType,
    game_version: String,
    loader_version: String,
    mirror_source: String,
    core_name: Option<String>,
    file_name: Option<String>,
    download_url: Option<String>,
    base_url: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GameLaunchPlanRequest {
    java_path: String,
    launch_command: Vec<String>,
    xms: i32,
    xmx: i32,
    jvm_arguments: String,
    working_directory: String,
    environment_variables: String,
    player: Option<GameLaunchPlayer>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GameLaunchPlayer {
    id: String,
    name: String,
    access_token: String,
    xuid: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProcessorExecutionRequest {
    processor: ProcessorPayload,
    libraries_dir: String,
    game_version: String,
    java_path: String,
    data: Option<BTreeMap<String, String>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProcessorPayload {
    jar: Option<String>,
    classpath: Option<Vec<String>>,
    args: Option<Vec<String>>,
    outputs: Option<BTreeMap<String, String>>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CliSettingsFile {
    #[serde(default)]
    general: CoreGeneralSettings,
    #[serde(default)]
    game: CoreGameSettings,
    #[serde(default)]
    theme: CoreThemeSettings,
    #[serde(default)]
    ai: CoreAISettings,
    #[serde(default)]
    mirror_sources: Vec<CoreMirrorSource>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CoreGeneralSettings {
    launcher_working_directory: Option<String>,
    concurrent_downloads: Option<i32>,
    auto_accept_server_eula: Option<bool>,
    backup_auto_enabled: Option<bool>,
    backup_interval_minutes: Option<i32>,
    backup_keep_count: Option<i32>,
    backup_directory_path: Option<String>,
    backup_before_update: Option<bool>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CoreGameSettings {
    global_xms: Option<i32>,
    global_xmx: Option<i32>,
    enable_ai_crash_analysis: Option<bool>,
    default_api_source: Option<String>,
    include_snapshots_for_game_versions: Option<bool>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CoreThemeSettings {
    theme_mode: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CoreAISettings {
    selected_provider: Option<String>,
    ollama_base_url: Option<String>,
    open_ai_base_url: Option<String>,
    model_override: Option<String>,
    ai_avatar_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CoreMirrorSource {
    id: String,
    name: String,
    kind: String,
    base_url: String,
    custom_json: Option<String>,
    is_enabled: bool,
    is_built_in: bool,
}

fn run_server_properties_command(
    app: &CliApp,
    command: ServerPropertiesCommand,
) -> Result<Value, CoreError> {
    match command {
        ServerPropertiesCommand::Read(args) => Ok(json!(app.read_server_properties(&args.id)?)),
        ServerPropertiesCommand::Write(args) => {
            let payload: Value = serde_json::from_str(&args.json).map_err(|error| {
                CoreError::validation(format!("invalid properties json: {error}"))
            })?;
            let object = payload
                .as_object()
                .ok_or_else(|| CoreError::validation("properties json must be an object"))?;
            let properties = object
                .iter()
                .map(|(key, value)| {
                    let text = match value {
                        Value::Null => String::new(),
                        Value::String(text) => text.clone(),
                        _ => value.to_string(),
                    };
                    (key.clone(), text)
                })
                .collect();
            app.write_server_properties(&args.id, &properties)?;
            Ok(json!(AckResponse { ok: true }))
        }
    }
}

fn run_server_files_command(app: &CliApp, command: ServerFilesCommand) -> Result<Value, CoreError> {
    match command {
        ServerFilesCommand::List(args) => Ok(json!(app.list_server_files(&args.id)?)),
        ServerFilesCommand::Read(args) => Ok(json!(ServerFileReadResponse {
            content: app.read_server_file_text(&args.id, &args.path)?,
        })),
        ServerFilesCommand::Write(args) => {
            let mut content = String::new();
            std::io::stdin()
                .read_to_string(&mut content)
                .map_err(|error| CoreError::runtime(format!("failed to read stdin: {error}")))?;
            app.write_server_file_text(&args.id, &args.path, &content)?;
            Ok(json!(AckResponse { ok: true }))
        }
        ServerFilesCommand::Mkdir(args) => {
            app.create_server_directory(&args.id, &args.path)?;
            Ok(json!(AckResponse { ok: true }))
        }
        ServerFilesCommand::Touch(args) => {
            app.create_server_file(&args.id, &args.path)?;
            Ok(json!(AckResponse { ok: true }))
        }
        ServerFilesCommand::Move(args) => {
            app.move_server_path(&args.id, &args.from, &args.to)?;
            Ok(json!(AckResponse { ok: true }))
        }
        ServerFilesCommand::Delete(args) => {
            app.remove_server_path(&args.id, &args.path)?;
            Ok(json!(AckResponse { ok: true }))
        }
        ServerFilesCommand::Import(args) => import_server_file(app, args),
    }
}

fn import_server_file(app: &CliApp, args: ServerFileImportArgs) -> Result<Value, CoreError> {
    app.import_server_path(&args.id, &args.source, &args.directory)?;
    Ok(json!(AckResponse { ok: true }))
}

fn run_server_schedules_command(
    app: &CliApp,
    command: ServerSchedulesCommand,
) -> Result<Value, CoreError> {
    match command {
        ServerSchedulesCommand::Read(args) => {
            let schedules: Value = serde_json::from_str(&app.read_schedules_json(&args.id)?)
                .map_err(|error| {
                    CoreError::runtime(format!("failed to decode schedules: {error}"))
                })?;
            Ok(schedules)
        }
        ServerSchedulesCommand::Write(args) => {
            let mut schedules = String::new();
            std::io::stdin()
                .read_to_string(&mut schedules)
                .map_err(|error| CoreError::runtime(format!("failed to read stdin: {error}")))?;
            app.write_schedules_json(&args.id, &schedules)?;
            Ok(json!(AckResponse { ok: true }))
        }
    }
}

fn run_server_players_command(
    app: &CliApp,
    command: ServerPlayersCommand,
) -> Result<Value, CoreError> {
    match command {
        ServerPlayersCommand::Read(args) => {
            let content = match app.read_server_file_text(&args.id, &args.file_name) {
                Ok(content) => content,
                Err(CoreError::NotFound { .. }) => "[]".to_string(),
                Err(error) => return Err(error),
            };
            let players: Value = serde_json::from_str(&content).map_err(|error| {
                CoreError::runtime(format!("failed to decode player list json: {error}"))
            })?;
            Ok(players)
        }
        ServerPlayersCommand::Write(args) => {
            let mut players = String::new();
            std::io::stdin()
                .read_to_string(&mut players)
                .map_err(|error| CoreError::runtime(format!("failed to read stdin: {error}")))?;
            let validated: Value = serde_json::from_str(&players).map_err(|error| {
                CoreError::validation(format!("invalid player list json: {error}"))
            })?;
            let content = serde_json::to_string_pretty(&validated).map_err(|error| {
                CoreError::runtime(format!("failed to encode player list json: {error}"))
            })?;
            app.write_server_file_text(&args.id, &args.file_name, &(content + "\n"))?;
            Ok(json!(AckResponse { ok: true }))
        }
    }
}

fn run_resource_command(app: &CliApp, command: ResourceCommand) -> Result<Value, CoreError> {
    match command {
        ResourceCommand::Download(args) => {
            let resource_type = ResourceType::parse(&args.resource_type)
                .ok_or_else(|| CoreError::validation("invalid resource type"))?;
            let path = app.resource_download_planner.download_resource(
                &args.game_name,
                resource_type,
                &scsl_core::DownloadTarget {
                    url: args.url,
                    sha1: args.sha1,
                    file_name: args.file_name,
                    headers: Default::default(),
                },
            )?;
            Ok(json!(ResourceDownloadResponse {
                path: path.display().to_string(),
            }))
        }
    }
}

fn run_mirror_command(command: MirrorCommand) -> Result<Value, CoreError> {
    match command {
        MirrorCommand::FastMirrorCores(args) => {
            Ok(json!(fetch_fastmirror_cores(args.base_url.as_deref())?))
        }
        MirrorCommand::FastMirrorGameVersions(args) => Ok(json!(fetch_fastmirror_game_versions(
            &args.core_name,
            args.base_url.as_deref()
        )?)),
        MirrorCommand::FastMirrorCoreVersions(args) => Ok(json!(fetch_fastmirror_core_versions(
            &args.core_name,
            &args.game_version,
            args.base_url.as_deref()
        )?)),
        MirrorCommand::FastMirrorDetail(args) => Ok(json!(fetch_fastmirror_detail(
            &args.core_name,
            &args.game_version,
            &args.core_version,
            args.base_url.as_deref()
        )?)),
        MirrorCommand::PolarsCoreTypes(args) => {
            Ok(json!(fetch_polars_core_types(args.base_url.as_deref())?))
        }
        MirrorCommand::PolarsCoreItems(args) => Ok(json!(fetch_polars_core_items(
            args.core_type_id,
            args.base_url.as_deref()
        )?)),
        MirrorCommand::CustomCores(args) => Ok(json!(fetch_custom_cores(args)?)),
        MirrorCommand::CustomGameVersions(args) => Ok(json!(fetch_custom_game_versions(args)?)),
        MirrorCommand::CustomCoreVersions(args) => Ok(json!(fetch_custom_core_versions(args)?)),
        MirrorCommand::CustomDetail(args) => Ok(json!(fetch_custom_detail(args)?)),
    }
}

fn run_modrinth_command(command: ModrinthCommand) -> Result<Value, CoreError> {
    match command {
        ModrinthCommand::Search(args) => fetch_modrinth_search(args),
        ModrinthCommand::Project(args) => fetch_json_value(
            &format!("https://api.modrinth.com/v2/project/{}", args.id),
            &[("Accept", "application/json")],
        ),
        ModrinthCommand::Versions(args) => fetch_json_value(
            &format!("https://api.modrinth.com/v2/project/{}/version", args.id),
            &[("Accept", "application/json")],
        ),
        ModrinthCommand::Version(args) => fetch_json_value(
            &format!("https://api.modrinth.com/v2/version/{}", args.version_id),
            &[("Accept", "application/json")],
        ),
        ModrinthCommand::FileByHash(args) => fetch_json_value(
            &format!("https://api.modrinth.com/v2/version_file/{}", args.hash),
            &[("Accept", "application/json")],
        ),
        ModrinthCommand::VersionInfo(args) => fetch_json_value(
            &format!(
                "https://launcher-meta.modrinth.com/minecraft/v0/versions/{}.json",
                args.version
            ),
            &[("Accept", "application/json")],
        ),
        ModrinthCommand::LoaderManifest(args) => fetch_json_value(
            &format!(
                "https://launcher-meta.modrinth.com/{}/v0/manifest.json",
                args.loader
            ),
            &[("Accept", "application/json")],
        ),
        ModrinthCommand::LoaderProfile(args) => fetch_json_value(
            &format!(
                "https://launcher-meta.modrinth.com/{}/v0/versions/{}.json",
                args.loader, args.version
            ),
            &[("Accept", "application/json")],
        ),
        ModrinthCommand::VersionsFilter(args) => fetch_modrinth_versions_filter(
            &args.id,
            &args.type_name,
            &args.selected_versions_json,
            &args.selected_loaders_json,
        ),
        ModrinthCommand::Dependencies(args) => fetch_modrinth_dependencies(
            &args.id,
            &args.type_name,
            &args.selected_versions_json,
            &args.selected_loaders_json,
        ),
        ModrinthCommand::Loaders => fetch_json_value(
            "https://api.modrinth.com/v2/tag/loader",
            &[("Accept", "application/json")],
        ),
        ModrinthCommand::Categories => fetch_json_value(
            "https://api.modrinth.com/v2/tag/category",
            &[("Accept", "application/json")],
        ),
        ModrinthCommand::GameVersions(args) => fetch_modrinth_game_versions(args.include_snapshots),
    }
}

fn build_demo_app() -> CliApp {
    let server = sample_local_server();
    let store = InMemoryStore::with_servers([server.clone()]);
    let runtime = InMemoryRuntime::with_server(
        &server.id,
        ServerStatus::Stopped,
        vec![
            "[SCSL] demo runtime booted".to_string(),
            "[SCSL] no filesystem adapter is wired yet".to_string(),
        ],
    );

    CliApp {
        core: ScslCore::new(CliServerStore::Demo(store), CliServerRuntime::Demo(runtime)),
        inventory_analyzer: ServerInventoryAnalyzer::new("servers"),
        download_planner: ServerDownloadPlanner::new("."),
        resource_download_planner: ResourceDownloadPlanner::new("."),
        forge_installer: ForgeInstallerPlanner::new("."),
        launch_planner: ServerLaunchPlanner::new("."),
    }
}

pub struct CliApp {
    core: ScslCore<CliServerStore, CliServerRuntime>,
    inventory_analyzer: ServerInventoryAnalyzer,
    download_planner: ServerDownloadPlanner,
    resource_download_planner: ResourceDownloadPlanner,
    forge_installer: ForgeInstallerPlanner,
    launch_planner: ServerLaunchPlanner,
}

impl CliApp {
    fn inventory(&self) -> Result<ServerInventory, CoreError> {
        Ok(self.inventory_analyzer.analyze(self.core.list_servers()?))
    }

    fn require_inventory_server(&self, id: &str) -> Result<ServerInstance, CoreError> {
        self.inventory()?
            .servers
            .into_iter()
            .find(|server| server.id == id)
            .ok_or_else(|| CoreError::not_found("server", id))
    }

    fn require_store_server(&self, id: &str) -> Result<ServerInstance, CoreError> {
        self.core
            .get_server(id)?
            .ok_or_else(|| CoreError::not_found("server", id))
    }

    fn local_runtime(&self) -> Result<&LocalServerRuntime, CoreError> {
        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support local filesystem polling",
            )),
            CliServerRuntime::Local(runtime) => Ok(runtime),
        }
    }

    fn send_direct_command(&self, id: &str, command: &str) -> Result<(), CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "direct send currently supports local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support direct console commands",
            )),
            CliServerRuntime::Local(runtime) => runtime.send_command(&server, command),
        }
    }

    fn interrupt_server(&self, id: &str, force: bool) -> Result<(), CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "interrupt currently supports local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support interrupts",
            )),
            CliServerRuntime::Local(runtime) => runtime.send_interrupt(&server, force),
        }
    }

    fn execute_local_rcon(&self, id: &str, command: &str) -> Result<String, CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local rcon currently supports local servers only",
            ));
        }

        let properties = self.read_server_properties(id)?;
        let port = properties
            .get("rcon.port")
            .and_then(|value| value.parse::<u16>().ok())
            .unwrap_or(server.rcon_port as u16);
        let password = properties
            .get("rcon.password")
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| server.rcon_password.trim().to_string());

        if password.is_empty() {
            return Err(CoreError::validation(
                "rcon password is missing; configure rcon.password in server.properties first",
            ));
        }

        execute_rcon_command("127.0.0.1", port, &password, command)
    }

    fn local_start_plan(
        &self,
        args: ServerJavaPathArgs,
    ) -> Result<LocalStartPlanResponse, CoreError> {
        let mut server = self.require_inventory_server(&args.id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local start planning currently supports local servers only",
            ));
        }

        server.java_path = args.java_path;
        self.apply_local_console_properties(&server)?;
        let forge_installed = self.forge_installer.install(&server)?;
        let plan = self.launch_planner.plan(&server)?;
        let properties = self.read_server_properties(&server.id)?;
        let port = properties
            .get("server-port")
            .and_then(|value| value.parse::<i32>().ok())
            .unwrap_or(25565);
        let port_processes = local_port_processes(port);

        Ok(LocalStartPlanResponse {
            launch_command: plan.launch_command,
            forge_installed,
            port,
            port_available: port_processes.is_empty(),
            port_processes: port_processes
                .into_iter()
                .map(|process| PortProcessInfoResponse {
                    pid: process.pid,
                    command: process.command,
                    user: process.user,
                })
                .collect(),
        })
    }

    fn local_start(&self, args: ServerJavaPathArgs) -> Result<(), CoreError> {
        let mut server = self.require_inventory_server(&args.id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "local start currently supports local servers only",
            ));
        }

        server.java_path = args.java_path;
        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support local start",
            )),
            CliServerRuntime::Local(runtime) => runtime.start(&server),
        }
    }

    fn apply_local_console_properties(&self, server: &ServerInstance) -> Result<(), CoreError> {
        let mut properties = self.read_server_properties(&server.id)?;
        properties.insert("enable-rcon".to_string(), "false".to_string());
        properties.insert("rcon.port".to_string(), server.rcon_port.to_string());
        if !server.rcon_password.is_empty() {
            properties.insert("rcon.password".to_string(), server.rcon_password.clone());
        }
        self.write_server_properties(&server.id, &properties)
    }

    fn create_local_server(
        &self,
        args: ServerCreateArgs,
    ) -> Result<ServerCreateResponse, CoreError> {
        let request: ServerCreateRequest = serde_json::from_str(&args.json).map_err(|error| {
            CoreError::validation(format!("invalid server create json: {error}"))
        })?;
        let server = self.server_from_create_request(&request)?;
        let server_dir = self.download_planner.server_dir(&server);
        if server_dir.exists() && !self.is_precreated_server_directory_allowed(&server_dir)? {
            return Err(CoreError::validation(format!(
                "server directory already exists: {}",
                server.directory_name
            )));
        }

        fs::create_dir_all(&server_dir).map_err(|error| {
            CoreError::runtime(format!("failed to create server directory: {error}"))
        })?;

        let result = (|| -> Result<ServerCreateResponse, CoreError> {
            let server_jar = match &request.source {
                ServerCreateSource::CustomJar { source_path } => {
                    self.copy_custom_jar(Path::new(source_path), &server_dir)?
                }
                ServerCreateSource::Download {
                    url,
                    file_name,
                    sha1,
                    headers,
                } => {
                    let target = mirror_direct_target(file_name.clone(), url.clone())?;
                    let destination = server_dir.join(&target.file_name);
                    let downloaded =
                        download_file_to_path(
                            &target.url,
                            &destination,
                            sha1.as_deref(),
                            headers.as_ref(),
                        )?;
                    self.materialize_server_artifact(&downloaded, &server_dir)?
                }
            };

            if request.accept_eula {
                self.write_eula(&server_dir)?;
            }

            let mut server_to_save = server.clone();
            server_to_save.server_jar = server_jar.clone();
            if server_to_save.server_type == ServerType::Forge {
                let _ = self.forge_installer.install(&server_to_save)?;
            }
            self.core.save_server(server_to_save.clone())?;

            Ok(ServerCreateResponse {
                id: server_to_save.id,
                directory_name: server_to_save.directory_name,
                server_jar,
                java_path: server_to_save.java_path,
            })
        })();

        if result.is_err() {
            let _ = remove_path_if_exists(&server_dir);
        }
        result
    }

    fn is_precreated_server_directory_allowed(&self, server_dir: &Path) -> Result<bool, CoreError> {
        let entries = fs::read_dir(server_dir)
            .map_err(|error| CoreError::runtime(format!("failed to inspect server directory: {error}")))?;
        for entry in entries {
            let entry = entry
                .map_err(|error| CoreError::runtime(format!("failed to inspect server directory entry: {error}")))?;
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if name.starts_with(".scsl-server-icon.") {
                continue;
            }
            return Ok(false);
        }
        Ok(true)
    }

    fn resolve_server_download_target(
        &self,
        args: ServerResolveDownloadArgs,
    ) -> Result<scsl_core::DownloadTarget, CoreError> {
        let request: ServerDownloadTargetRequest =
            serde_json::from_str(&args.json).map_err(|error| {
                CoreError::validation(format!("invalid download target json: {error}"))
            })?;
        let mirror_source = request.mirror_source.trim().to_ascii_lowercase();
        match mirror_source.as_str() {
            "fastmirror" => self.resolve_fastmirror_target(
                request.server_type,
                &request.game_version,
                &request.loader_version,
                request.core_name.as_deref(),
                request.base_url.as_deref(),
            ),
            "polars" | "custom" => mirror_direct_target(
                request.file_name.unwrap_or_default(),
                request.download_url.unwrap_or_default(),
            ),
            "official" | "" => self.resolve_official_target(
                request.server_type,
                &request.game_version,
                &request.loader_version,
            ),
            other => Err(CoreError::validation(format!(
                "unsupported mirror source: {other}"
            ))),
        }
    }

    fn resolve_java_version(
        &self,
        game_version: &str,
    ) -> Result<scsl_core::JavaVersion, CoreError> {
        let manifest: MojangVersionManifest = fetch_json(
            "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json",
            &[],
        )?;
        let version_info = manifest
            .versions
            .into_iter()
            .find(|item| item.id == game_version)
            .ok_or_else(|| {
                CoreError::runtime(format!("minecraft version not found: {game_version}"))
            })?;
        let version_manifest: MinecraftVersionManifest = fetch_json(&version_info.url, &[])?;
        Ok(scsl_core::JavaVersion {
            component: version_manifest.java_version.component,
            major_version: version_manifest.java_version.major_version,
        })
    }

    fn resolve_latest_loader(
        &self,
        server_type: &str,
        game_version: &str,
    ) -> Result<String, CoreError> {
        match server_type.trim().to_ascii_lowercase().as_str() {
            "fabric" => {
                let loaders: Vec<FabricLoaderEntry> = fetch_json(
                    &format!("https://meta.fabricmc.net/v2/versions/loader/{game_version}"),
                    &[],
                )?;
                loaders
                    .iter()
                    .find(|item| item.loader.stable)
                    .or_else(|| loaders.first())
                    .map(|item| item.loader.version.clone())
                    .ok_or_else(|| {
                        CoreError::runtime("fabric loader version not found".to_string())
                    })
            }
            "forge" => {
                let promotions: ForgePromotions = fetch_json(
                    "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json",
                    &[],
                )?;
                promotions
                    .promos
                    .get(&format!("{game_version}-recommended"))
                    .cloned()
                    .or_else(|| {
                        promotions
                            .promos
                            .get(&format!("{game_version}-latest"))
                            .cloned()
                    })
                    .ok_or_else(|| CoreError::runtime("forge loader version not found".to_string()))
            }
            other => Err(CoreError::validation(format!(
                "latest loader is unsupported for server type: {other}"
            ))),
        }
    }

    fn available_game_versions(
        &self,
        args: ServerGameVersionsArgs,
    ) -> Result<Vec<String>, CoreError> {
        match args.server_type.trim().to_ascii_lowercase().as_str() {
            "vanilla" | "paper" | "custom" => {
                let manifest: MojangVersionManifest = fetch_json(
                    "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json",
                    &[],
                )?;
                let versions = if args.include_snapshots {
                    manifest.versions.into_iter().map(|item| item.id).collect()
                } else {
                    manifest
                        .versions
                        .into_iter()
                        .filter(|item| item.release_type == "release")
                        .map(|item| item.id)
                        .collect()
                };
                Ok(versions)
            }
            "fabric" => {
                let versions: Vec<FabricGameVersionWire> =
                    fetch_json("https://meta.fabricmc.net/v2/versions/game", &[])?;
                let result = if args.include_snapshots {
                    versions.into_iter().map(|item| item.version).collect()
                } else {
                    versions
                        .into_iter()
                        .filter(|item| item.stable)
                        .map(|item| item.version)
                        .collect()
                };
                Ok(result)
            }
            "forge" => {
                let promotions: ForgePromotions = fetch_json(
                    "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json",
                    &[],
                )?;
                let mut versions = promotions
                    .promos
                    .keys()
                    .filter_map(|key| {
                        ["-recommended", "-latest"]
                            .iter()
                            .find(|suffix| key.ends_with(**suffix))
                            .map(|suffix| key.trim_end_matches(suffix).to_string())
                    })
                    .collect::<Vec<_>>();
                versions.sort_by(|left, right| right.cmp(left));
                versions.dedup();
                Ok(versions)
            }
            other => Err(CoreError::validation(format!(
                "game versions are unsupported for server type: {other}"
            ))),
        }
    }

    fn available_loader_versions(
        &self,
        args: ServerLoaderVersionsArgs,
    ) -> Result<Vec<String>, CoreError> {
        match args.server_type.trim().to_ascii_lowercase().as_str() {
            "fabric" => {
                let entries: Vec<FabricLoaderEntry> = fetch_json(
                    &format!(
                        "https://meta.fabricmc.net/v2/versions/loader/{}",
                        args.game_version
                    ),
                    &[],
                )?;
                Ok(entries
                    .into_iter()
                    .map(|entry| entry.loader.version)
                    .collect())
            }
            "forge" => {
                let manifest: LoaderManifestWire = fetch_json(
                    "https://launcher-meta.modrinth.com/forge/v0/manifest.json",
                    &[],
                )?;
                let game_version = manifest
                    .game_versions
                    .into_iter()
                    .find(|entry| entry.id == args.game_version)
                    .ok_or_else(|| {
                        CoreError::runtime(format!(
                            "forge loader versions not found for {}",
                            args.game_version
                        ))
                    })?;
                Ok(game_version
                    .loaders
                    .into_iter()
                    .map(|loader| loader.id)
                    .collect())
            }
            other => Err(CoreError::validation(format!(
                "loader versions are unsupported for server type: {other}"
            ))),
        }
    }

    fn resolve_official_target(
        &self,
        server_type: ServerType,
        game_version: &str,
        loader_version: &str,
    ) -> Result<scsl_core::DownloadTarget, CoreError> {
        match server_type {
            ServerType::Vanilla => self.resolve_vanilla_target(game_version),
            ServerType::Paper => self.resolve_paper_target(game_version),
            ServerType::Fabric => self.resolve_fabric_target(game_version, loader_version),
            ServerType::Forge => self.resolve_forge_target(game_version, loader_version),
            ServerType::Custom => Err(CoreError::validation(
                "custom jar does not have a download target",
            )),
        }
    }

    fn resolve_fastmirror_target(
        &self,
        server_type: ServerType,
        game_version: &str,
        loader_version: &str,
        core_name: Option<&str>,
        base_url: Option<&str>,
    ) -> Result<scsl_core::DownloadTarget, CoreError> {
        if matches!(server_type, ServerType::Custom) {
            return Err(CoreError::validation(
                "custom jar does not have a download target",
            ));
        }
        if loader_version.trim().is_empty() {
            return Err(CoreError::validation("loader version cannot be empty"));
        }
        let resolved_core_name = core_name
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| fastmirror_core_name(server_type));
        let detail_url =
            fastmirror_core_detail_url(base_url, resolved_core_name, game_version, loader_version);
        let detail: FastMirrorCoreDetailWire = fetch_json(&detail_url, &[])?;
        Ok(scsl_core::DownloadTarget {
            url: detail.download_url,
            sha1: detail.sha1,
            file_name: detail.filename,
            headers: BTreeMap::new(),
        })
    }

    fn resolve_vanilla_target(
        &self,
        game_version: &str,
    ) -> Result<scsl_core::DownloadTarget, CoreError> {
        let manifest: MojangVersionManifest = fetch_json(
            "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json",
            &[],
        )?;
        let version_info = manifest
            .versions
            .into_iter()
            .find(|item| item.id == game_version)
            .ok_or_else(|| {
                CoreError::runtime(format!("minecraft version not found: {game_version}"))
            })?;
        let version_manifest: MinecraftVersionManifest = fetch_json(&version_info.url, &[])?;
        let server_download = version_manifest
            .downloads
            .server
            .ok_or_else(|| CoreError::runtime("server download not found".to_string()))?;
        Ok(scsl_core::DownloadTarget {
            file_name: server_download.file_name(),
            url: server_download.url,
            sha1: Some(server_download.sha1),
            headers: BTreeMap::new(),
        })
    }

    fn resolve_paper_target(
        &self,
        game_version: &str,
    ) -> Result<scsl_core::DownloadTarget, CoreError> {
        let builds: Vec<PaperBuildWire> = fetch_json(
            &format!("https://fill.papermc.io/v3/projects/paper/versions/{game_version}/builds"),
            &[("User-Agent", "SwiftCraftServerLauncher/1.0")],
        )?;
        let build = builds
            .into_iter()
            .find(|item| item.channel.eq_ignore_ascii_case("stable"))
            .ok_or_else(|| CoreError::runtime("paper stable build not found".to_string()))?;
        let download = build
            .downloads
            .get("server:default")
            .cloned()
            .ok_or_else(|| CoreError::runtime("paper server download not found".to_string()))?;
        let mut headers = BTreeMap::new();
        headers.insert(
            "User-Agent".to_string(),
            "SwiftCraftServerLauncher/1.0".to_string(),
        );
        Ok(scsl_core::DownloadTarget {
            url: download.url,
            sha1: None,
            file_name: download.name,
            headers,
        })
    }

    fn resolve_fabric_target(
        &self,
        game_version: &str,
        loader_version: &str,
    ) -> Result<scsl_core::DownloadTarget, CoreError> {
        let selected_loader = if !loader_version.trim().is_empty() {
            loader_version.trim().to_string()
        } else {
            self.resolve_latest_loader("fabric", game_version)?
        };
        let installers: Vec<FabricInstallerWire> =
            fetch_json("https://meta.fabricmc.net/v2/versions/installer", &[])?;
        let installer = installers
            .iter()
            .find(|item| item.stable)
            .or_else(|| installers.first())
            .ok_or_else(|| CoreError::runtime("fabric installer version not found".to_string()))?;
        fabric_server_jar_target(game_version, &selected_loader, &installer.version)
    }

    fn resolve_forge_target(
        &self,
        game_version: &str,
        loader_version: &str,
    ) -> Result<scsl_core::DownloadTarget, CoreError> {
        let selected_loader = if !loader_version.trim().is_empty() {
            loader_version.trim().to_string()
        } else {
            self.resolve_latest_loader("forge", game_version)?
        };
        forge_installer_target(game_version, &selected_loader)
    }

    fn server_from_create_request(
        &self,
        request: &ServerCreateRequest,
    ) -> Result<ServerInstance, CoreError> {
        if request.id.trim().is_empty()
            || request.name.trim().is_empty()
            || request.directory_name.trim().is_empty()
        {
            return Err(CoreError::validation(
                "server create request is missing required fields",
            ));
        }

        let initial_jar = match &request.source {
            ServerCreateSource::CustomJar { source_path } => Path::new(source_path)
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("server.jar")
                .to_string(),
            ServerCreateSource::Download { file_name, .. } => file_name.clone(),
        };

        let mut server = ServerInstance::new(
            request.id.clone(),
            request.name.clone(),
            request.directory_name.clone(),
            request.server_type,
            request.game_version.clone(),
            initial_jar,
        );
        server.icon_name = request.icon_name.clone();
        server.icon_image_file_name = request.icon_image_file_name.clone();
        server.loader_version = request.loader_version.clone();
        server.launch_command = request.launch_command.clone().unwrap_or_default();
        server.java_path = request.java_path.clone();
        server.jvm_arguments = request.jvm_arguments.clone().unwrap_or_default();
        server.xms = request.xms.unwrap_or_default();
        server.xmx = request.xmx.unwrap_or_default();
        server.console_mode = request.console_mode.unwrap_or(scsl_core::ConsoleMode::Rcon);
        server.rcon_port = request.rcon_port.unwrap_or(25575);
        server.rcon_password = request.rcon_password.clone().unwrap_or_default();
        Ok(server)
    }

    fn copy_custom_jar(&self, source_path: &Path, server_dir: &Path) -> Result<String, CoreError> {
        let file_name = source_path
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or_else(|| CoreError::validation("custom jar path does not have a file name"))?
            .to_string();
        let target = server_dir.join(&file_name);
        fs::copy(source_path, &target)
            .map_err(|error| CoreError::runtime(format!("failed to copy custom jar: {error}")))?;
        Ok(file_name)
    }

    fn materialize_server_artifact(
        &self,
        downloaded_path: &Path,
        server_dir: &Path,
    ) -> Result<String, CoreError> {
        if downloaded_path
            .extension()
            .and_then(|value| value.to_str())
            .is_some_and(|value| value.eq_ignore_ascii_case("zip"))
        {
            unzip_server_archive(downloaded_path, server_dir)?;
            return find_first_server_jar(server_dir).ok_or_else(|| {
                CoreError::runtime("zip archive did not contain a server jar".to_string())
            });
        }

        Ok(downloaded_path
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or_else(|| {
                CoreError::runtime("downloaded artifact does not have a file name".to_string())
            })?
            .to_string())
    }

    fn write_eula(&self, server_dir: &Path) -> Result<(), CoreError> {
        fs::write(
            server_dir.join("eula.txt"),
            "eula=true\n# accepted by SwiftCraftServerLauncher\n",
        )
        .map_err(|error| CoreError::runtime(format!("failed to write eula.txt: {error}")))
    }

    fn read_server_properties(&self, id: &str) -> Result<BTreeMap<String, String>, CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server.properties currently supports local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server.properties",
            )),
            CliServerRuntime::Local(runtime) => runtime.read_server_properties(&server),
        }
    }

    fn write_server_properties(
        &self,
        id: &str,
        properties: &BTreeMap<String, String>,
    ) -> Result<(), CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server.properties currently supports local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server.properties",
            )),
            CliServerRuntime::Local(runtime) => {
                runtime.write_server_properties(&server, properties)
            }
        }
    }

    fn list_server_files(&self, id: &str) -> Result<Vec<LocalServerFileEntry>, CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server files currently support local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server files",
            )),
            CliServerRuntime::Local(runtime) => runtime.list_server_files(&server),
        }
    }

    fn read_server_file_text(&self, id: &str, relative_path: &str) -> Result<String, CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server files currently support local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server files",
            )),
            CliServerRuntime::Local(runtime) => {
                runtime.read_server_file_text(&server, relative_path)
            }
        }
    }

    fn write_server_file_text(
        &self,
        id: &str,
        relative_path: &str,
        content: &str,
    ) -> Result<(), CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server files currently support local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server files",
            )),
            CliServerRuntime::Local(runtime) => {
                runtime.write_server_file_text(&server, relative_path, content)
            }
        }
    }

    fn create_server_directory(&self, id: &str, relative_path: &str) -> Result<(), CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server files currently support local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server files",
            )),
            CliServerRuntime::Local(runtime) => {
                runtime.create_server_directory(&server, relative_path)
            }
        }
    }

    fn create_server_file(&self, id: &str, relative_path: &str) -> Result<(), CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server files currently support local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server files",
            )),
            CliServerRuntime::Local(runtime) => runtime.create_server_file(&server, relative_path),
        }
    }

    fn move_server_path(&self, id: &str, from: &str, to: &str) -> Result<(), CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server files currently support local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server files",
            )),
            CliServerRuntime::Local(runtime) => runtime.move_server_path(&server, from, to),
        }
    }

    fn remove_server_path(&self, id: &str, relative_path: &str) -> Result<(), CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server files currently support local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server files",
            )),
            CliServerRuntime::Local(runtime) => runtime.remove_server_path(&server, relative_path),
        }
    }

    fn import_server_path(
        &self,
        id: &str,
        source: &PathBuf,
        directory: &str,
    ) -> Result<(), CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server files currently support local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server files",
            )),
            CliServerRuntime::Local(runtime) => {
                runtime.import_server_path(&server, source, directory)
            }
        }
    }

    fn read_schedules_json(&self, id: &str) -> Result<String, CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server schedules currently support local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support schedules",
            )),
            CliServerRuntime::Local(runtime) => runtime.read_schedules_json(&server),
        }
    }

    fn write_schedules_json(&self, id: &str, schedules_json: &str) -> Result<(), CoreError> {
        let server = self.require_inventory_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server schedules currently support local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support schedules",
            )),
            CliServerRuntime::Local(runtime) => {
                runtime.write_schedules_json(&server, schedules_json)
            }
        }
    }

    fn delete_local_server(&self, id: &str) -> Result<(), CoreError> {
        let server = self.require_store_server(id)?;
        if !server.is_local() {
            return Err(CoreError::unsupported(
                "server deletion currently supports local servers only",
            ));
        }

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server deletion",
            )),
            CliServerRuntime::Local(runtime) => {
                runtime.remove_server_directory(&server)?;
                self.core.delete_server(id)
            }
        }
    }

    fn delete_corrupted_local_servers(&self, name: &str) -> Result<usize, CoreError> {
        let servers = self
            .core
            .list_servers()?
            .into_iter()
            .filter(|server| server.is_local() && server.name == name)
            .collect::<Vec<_>>();

        match self.core.runtime() {
            CliServerRuntime::Demo(_) => Err(CoreError::unsupported(
                "demo runtime does not support server deletion",
            )),
            CliServerRuntime::Local(runtime) => {
                for server in &servers {
                    runtime.remove_server_directory(server)?;
                }
                for server in &servers {
                    self.core.delete_server(&server.id)?;
                }
                Ok(servers.len())
            }
        }
    }

    fn read_agent_schedules(
        &self,
        server: &ServerInstance,
    ) -> Result<Vec<AgentSchedule>, CoreError> {
        let schedules = self.read_schedules_json(&server.id)?;
        serde_json::from_str(&schedules)
            .map_err(|error| CoreError::validation(format!("invalid schedules json: {error}")))
    }

    fn poll_local_agent_log(
        &self,
        server: &ServerInstance,
        current_file_path: Option<&str>,
        offset: u64,
    ) -> Result<scsl_core::LocalLogPollResult, CoreError> {
        self.local_runtime()?
            .poll_local_log(server, current_file_path, offset)
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AgentSchedule {
    id: String,
    #[serde(default)]
    is_enabled: bool,
    trigger: AgentScheduleTrigger,
    action: AgentScheduleAction,
    #[serde(default)]
    time: AgentScheduleTime,
    #[serde(default)]
    weekdays: Vec<u32>,
    #[serde(default)]
    command: String,
    #[serde(default)]
    keyword: String,
    #[serde(default = "default_true")]
    keyword_ignore_case: bool,
    #[serde(default)]
    keyword_is_regex: bool,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum AgentScheduleTrigger {
    Time,
    ConsoleKeyword,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
enum AgentScheduleAction {
    Start,
    Stop,
    Restart,
    Command,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct AgentScheduleTime {
    #[serde(default)]
    hour: u32,
    #[serde(default)]
    minute: u32,
}

struct BackgroundAgent {
    last_minute_token: Option<String>,
    last_fire_tokens: BTreeMap<String, String>,
    last_local_log_file_path: BTreeMap<String, String>,
    last_local_log_offset: BTreeMap<String, u64>,
    console_buffers: BTreeMap<String, String>,
    last_console_trigger: BTreeMap<String, Instant>,
}

impl BackgroundAgent {
    fn new() -> Self {
        Self {
            last_minute_token: None,
            last_fire_tokens: BTreeMap::new(),
            last_local_log_file_path: BTreeMap::new(),
            last_local_log_offset: BTreeMap::new(),
            console_buffers: BTreeMap::new(),
            last_console_trigger: BTreeMap::new(),
        }
    }

    fn tick(&mut self, app: &CliApp) -> Result<(), CoreError> {
        let servers = app.core.list_servers()?;
        self.tick_time_schedules(app, &servers)?;
        self.tick_console_schedules(app, &servers)?;
        Ok(())
    }

    fn tick_time_schedules(
        &mut self,
        app: &CliApp,
        servers: &[ServerInstance],
    ) -> Result<(), CoreError> {
        let now = Local::now();
        let minute_token = format!(
            "{}-{}-{}-{}-{}",
            now.year(),
            now.month(),
            now.day(),
            now.hour(),
            now.minute()
        );
        if self.last_minute_token.as_deref() == Some(minute_token.as_str()) {
            return Ok(());
        }
        self.last_minute_token = Some(minute_token.clone());
        for server in servers.iter().filter(|server| server.is_local()) {
            for schedule in app.read_agent_schedules(server)? {
                if !schedule.is_enabled || schedule.trigger != AgentScheduleTrigger::Time {
                    continue;
                }
                if !self.should_fire_time_schedule(&schedule, now) {
                    continue;
                }
                let fire_token = format!("{}-{}", schedule.id, minute_token);
                if self.last_fire_tokens.get(&schedule.id) == Some(&fire_token) {
                    continue;
                }
                self.last_fire_tokens
                    .insert(schedule.id.clone(), fire_token);
                self.execute_schedule(app, server, &schedule, None)?;
            }
        }
        Ok(())
    }

    fn tick_console_schedules(
        &mut self,
        app: &CliApp,
        servers: &[ServerInstance],
    ) -> Result<(), CoreError> {
        for server in servers.iter().filter(|server| server.is_local()) {
            let schedules = app.read_agent_schedules(server)?;
            if !schedules.iter().any(|schedule| {
                schedule.is_enabled && schedule.trigger == AgentScheduleTrigger::ConsoleKeyword
            }) {
                continue;
            }
            let result = app.poll_local_agent_log(
                server,
                self.last_local_log_file_path
                    .get(&server.id)
                    .map(String::as_str),
                *self.last_local_log_offset.get(&server.id).unwrap_or(&0),
            )?;
            self.last_local_log_file_path
                .insert(server.id.clone(), result.file_path.unwrap_or_default());
            self.last_local_log_offset
                .insert(server.id.clone(), result.next_offset);
            if result.appended_text.is_empty() {
                continue;
            }
            let lines = self.consume_console_lines(&server.id, &result.appended_text);
            for line in lines {
                let message = extract_server_message(&sanitize_console_line(&line));
                for schedule in schedules.iter().filter(|schedule| {
                    schedule.is_enabled && schedule.trigger == AgentScheduleTrigger::ConsoleKeyword
                }) {
                    if self.matches_keyword(schedule, &message)? {
                        self.execute_schedule(app, server, schedule, Some(message.clone()))?;
                    }
                }
            }
        }
        Ok(())
    }

    fn should_fire_time_schedule(
        &self,
        schedule: &AgentSchedule,
        now: chrono::DateTime<Local>,
    ) -> bool {
        if schedule.time.hour != now.hour() || schedule.time.minute != now.minute() {
            return false;
        }
        if schedule.weekdays.is_empty() {
            return true;
        }
        let weekday = match now.weekday() {
            chrono::Weekday::Sun => 1,
            chrono::Weekday::Mon => 2,
            chrono::Weekday::Tue => 3,
            chrono::Weekday::Wed => 4,
            chrono::Weekday::Thu => 5,
            chrono::Weekday::Fri => 6,
            chrono::Weekday::Sat => 7,
        };
        schedule.weekdays.contains(&weekday)
    }

    fn consume_console_lines(&mut self, server_id: &str, chunk: &str) -> Vec<String> {
        let buffer = self
            .console_buffers
            .entry(server_id.to_string())
            .or_default();
        buffer.push_str(chunk);
        let mut lines = Vec::new();
        let mut current = String::new();
        for scalar in buffer.chars() {
            if scalar == '\n' || scalar == '\r' {
                if !current.is_empty() {
                    lines.push(current.clone());
                    current.clear();
                }
            } else {
                current.push(scalar);
            }
        }
        *buffer = current;
        lines
    }

    fn matches_keyword(&self, schedule: &AgentSchedule, line: &str) -> Result<bool, CoreError> {
        let keyword = schedule.keyword.trim();
        if keyword.is_empty() {
            return Ok(false);
        }
        if schedule.keyword_is_regex {
            let regex = if schedule.keyword_ignore_case {
                Regex::new(&format!("(?i){keyword}"))
            } else {
                Regex::new(keyword)
            }
            .map_err(|error| CoreError::validation(format!("invalid schedule regex: {error}")))?;
            return Ok(regex.is_match(line));
        }
        if schedule.keyword_ignore_case {
            Ok(line.to_lowercase().contains(&keyword.to_lowercase()))
        } else {
            Ok(line.contains(keyword))
        }
    }

    fn execute_schedule(
        &mut self,
        app: &CliApp,
        server: &ServerInstance,
        schedule: &AgentSchedule,
        line: Option<String>,
    ) -> Result<(), CoreError> {
        if let Some(last) = self.last_console_trigger.get(&schedule.id) {
            if last.elapsed() < Duration::from_millis(500) {
                return Ok(());
            }
        }
        match schedule.action {
            AgentScheduleAction::Start => {
                let _ = app.core.start_server(&server.id);
            }
            AgentScheduleAction::Stop => {
                let _ = app.core.stop_server(&server.id);
            }
            AgentScheduleAction::Restart => {
                let _ = app.core.restart_server(&server.id);
            }
            AgentScheduleAction::Command => {
                let command = build_agent_schedule_command(schedule, line.as_deref());
                if !command.is_empty() {
                    app.send_direct_command(&server.id, &command)?;
                }
            }
        }
        self.last_console_trigger
            .insert(schedule.id.clone(), Instant::now());
        Ok(())
    }
}

fn build_agent_schedule_command(schedule: &AgentSchedule, line: Option<&str>) -> String {
    let mut command = schedule.command.trim().to_string();
    if let Some(line) = line {
        command = command.replace("{{line}}", line);
        command = command.replace("{{raw}}", line);
        command = command.replace("{{rawLine}}", line);
    }
    command.trim().to_string()
}

fn sanitize_console_line(line: &str) -> String {
    Regex::new(r"\u{001B}\[[0-9;?]*[ -/]*[@-~]")
        .ok()
        .map(|regex| regex.replace_all(line, "").to_string())
        .unwrap_or_else(|| line.to_string())
}

fn extract_server_message(line: &str) -> String {
    for token in ["] [Server] ", "] [Server]: ", "[Server] ", "[Server]: "] {
        if let Some(index) = line.rfind(token) {
            let message = line[index + token.len()..].trim();
            if !message.is_empty() {
                return message.to_string();
            }
        }
    }
    line.trim().to_string()
}

fn default_true() -> bool {
    true
}

enum CliServerStore {
    Demo(InMemoryStore),
    SwiftData(LocalAppServerStore),
}

enum CliServerRuntime {
    Demo(InMemoryRuntime),
    Local(LocalServerRuntime),
}

impl ServerRuntimePort for CliServerRuntime {
    fn start(&self, server: &ServerInstance) -> Result<(), CoreError> {
        match self {
            Self::Demo(runtime) => runtime.start(server),
            Self::Local(runtime) => runtime.start(server),
        }
    }

    fn stop(&self, server: &ServerInstance) -> Result<(), CoreError> {
        match self {
            Self::Demo(runtime) => runtime.stop(server),
            Self::Local(runtime) => runtime.stop(server),
        }
    }

    fn status(&self, server: &ServerInstance) -> Result<ServerStatus, CoreError> {
        match self {
            Self::Demo(runtime) => runtime.status(server),
            Self::Local(runtime) => runtime.status(server),
        }
    }

    fn logs(
        &self,
        server: &ServerInstance,
        query: LogQuery,
    ) -> Result<scsl_core::LogSnapshot, CoreError> {
        match self {
            Self::Demo(runtime) => runtime.logs(server, query),
            Self::Local(runtime) => runtime.logs(server, query),
        }
    }
}

impl ServerStorePort for CliServerStore {
    fn list_servers(&self) -> Result<Vec<ServerInstance>, CoreError> {
        match self {
            Self::Demo(store) => store.list_servers(),
            Self::SwiftData(store) => store.list_servers(),
        }
    }

    fn get_server(&self, id: &str) -> Result<Option<ServerInstance>, CoreError> {
        match self {
            Self::Demo(store) => store.get_server(id),
            Self::SwiftData(store) => store.get_server(id),
        }
    }

    fn save_server(&self, server: ServerInstance) -> Result<(), CoreError> {
        match self {
            Self::Demo(store) => store.save_server(server),
            Self::SwiftData(store) => store.save_server(server),
        }
    }

    fn delete_server(&self, id: &str) -> Result<(), CoreError> {
        match self {
            Self::Demo(store) => store.delete_server(id),
            Self::SwiftData(store) => store.delete_server(id),
        }
    }
}

#[derive(Deserialize)]
struct MojangVersionManifest {
    versions: Vec<MojangVersionInfo>,
}

#[derive(Deserialize)]
struct MojangVersionInfo {
    id: String,
    #[serde(rename = "type")]
    release_type: String,
    url: String,
}

#[derive(Deserialize)]
struct MinecraftVersionManifest {
    #[serde(rename = "javaVersion")]
    java_version: JavaVersionWire,
    downloads: MinecraftDownloads,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct JavaVersionWire {
    component: String,
    major_version: u32,
}

#[derive(Deserialize)]
struct MinecraftDownloads {
    server: Option<MinecraftServerDownload>,
}

#[derive(Deserialize)]
struct MinecraftServerDownload {
    sha1: String,
    url: String,
}

impl MinecraftServerDownload {
    fn file_name(&self) -> String {
        self.url
            .rsplit('/')
            .next()
            .filter(|value| !value.is_empty())
            .unwrap_or("server.jar")
            .to_string()
    }
}

#[derive(Clone, Deserialize)]
struct PaperDownloadWire {
    name: String,
    url: String,
}

#[derive(Deserialize)]
struct PaperBuildWire {
    channel: String,
    downloads: BTreeMap<String, PaperDownloadWire>,
}

#[derive(Deserialize)]
struct FabricInstallerWire {
    version: String,
    stable: bool,
}

#[derive(Deserialize)]
struct FabricLoaderVersionWire {
    version: String,
    stable: bool,
}

#[derive(Deserialize)]
struct FabricLoaderEntry {
    loader: FabricLoaderVersionWire,
}

#[derive(Deserialize)]
struct ForgePromotions {
    promos: BTreeMap<String, String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LoaderManifestWire {
    game_versions: Vec<LoaderGameVersionWire>,
}

#[derive(Deserialize)]
struct LoaderGameVersionWire {
    id: String,
    loaders: Vec<LoaderInfoWire>,
}

#[derive(Deserialize)]
struct LoaderInfoWire {
    id: String,
}

#[derive(Deserialize)]
struct FabricGameVersionWire {
    version: String,
    stable: bool,
}

#[derive(Serialize, Deserialize)]
struct FastMirrorCoreDetailWire {
    #[serde(rename = "download_url")]
    download_url: String,
    sha1: Option<String>,
    filename: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MirrorCustomAPIConfigWire {
    unwrap_data: bool,
    core_list_path: String,
    core_detail_path: String,
    core_builds_path: String,
    core_build_detail_path: String,
    cores_key_path: String,
    core_name_key: String,
    core_tag_key: String,
    core_recommend_key: String,
    versions_key_path: String,
    builds_key_path: String,
    build_version_key: String,
    build_sha1_key: String,
    build_download_url_key: String,
    build_file_name_key: String,
}

#[derive(Serialize, Deserialize)]
struct FastMirrorCoreSummaryWire {
    name: String,
    tag: Option<String>,
    recommend: bool,
    homepage: Option<String>,
    #[serde(rename = "mc_versions")]
    mc_versions: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize)]
struct FastMirrorCoreInfoWire {
    #[serde(rename = "mc_versions")]
    mc_versions: Vec<String>,
}

#[derive(Serialize, Deserialize)]
struct FastMirrorBuildListWire {
    builds: Vec<FastMirrorBuildWire>,
}

#[derive(Serialize, Deserialize)]
struct FastMirrorBuildWire {
    #[serde(rename = "core_version")]
    core_version: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PolarsCoreTypeWire {
    id: i64,
    name: String,
    description: Option<String>,
}

#[derive(Serialize, Deserialize)]
struct PolarsCoreItemWire {
    name: String,
    #[serde(rename = "downloadUrl")]
    download_url: String,
}

struct PortProcessInfo {
    pid: i32,
    command: String,
    user: String,
}

fn local_port_processes(port: i32) -> Vec<PortProcessInfo> {
    let output = ProcessCommand::new("/usr/sbin/lsof")
        .args(["-nP", &format!("-iTCP:{port}"), "-sTCP:LISTEN"])
        .output();
    let Ok(output) = output else {
        return Vec::new();
    };
    let text = String::from_utf8_lossy(&output.stdout);
    let mut lines = text.lines();
    if lines.next().is_none() {
        return Vec::new();
    }

    lines
        .filter_map(|line| {
            let parts = line
                .split_whitespace()
                .map(str::to_string)
                .collect::<Vec<_>>();
            if parts.len() < 3 {
                return None;
            }
            let pid = parts[1].parse::<i32>().ok()?;
            Some(PortProcessInfo {
                pid,
                command: parts[0].clone(),
                user: parts[2].clone(),
            })
        })
        .collect()
}

fn remove_path_if_exists(path: &Path) -> Result<(), CoreError> {
    if !path.exists() {
        return Ok(());
    }
    if path.is_dir() {
        fs::remove_dir_all(path)
            .map_err(|error| CoreError::runtime(format!("failed to remove directory: {error}")))
    } else {
        fs::remove_file(path)
            .map_err(|error| CoreError::runtime(format!("failed to remove file: {error}")))
    }
}

fn unzip_server_archive(archive_path: &Path, destination: &Path) -> Result<(), CoreError> {
    let file = File::open(archive_path)
        .map_err(|error| CoreError::runtime(format!("failed to open zip archive: {error}")))?;
    let mut archive = ZipArchive::new(file)
        .map_err(|error| CoreError::runtime(format!("failed to parse zip archive: {error}")))?;

    for index in 0..archive.len() {
        let mut entry = archive
            .by_index(index)
            .map_err(|error| CoreError::runtime(format!("failed to inspect zip entry: {error}")))?;
        let Some(name) = entry.enclosed_name().map(PathBuf::from) else {
            continue;
        };
        let output_path = destination.join(name);
        if entry.is_dir() {
            fs::create_dir_all(&output_path).map_err(|error| {
                CoreError::runtime(format!("failed to create extracted directory: {error}"))
            })?;
            continue;
        }
        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent).map_err(|error| {
                CoreError::runtime(format!("failed to create extracted parent: {error}"))
            })?;
        }
        let mut output = File::create(&output_path).map_err(|error| {
            CoreError::runtime(format!("failed to create extracted file: {error}"))
        })?;
        std::io::copy(&mut entry, &mut output)
            .map_err(|error| CoreError::runtime(format!("failed to extract zip entry: {error}")))?;
    }

    Ok(())
}

fn find_first_server_jar(directory: &Path) -> Option<String> {
    let mut jars = Vec::new();
    collect_jars(directory, directory, &mut jars).ok()?;
    jars.sort();
    jars.into_iter().next()
}

fn collect_jars(root: &Path, current: &Path, jars: &mut Vec<String>) -> Result<(), CoreError> {
    for entry in fs::read_dir(current).map_err(|error| {
        CoreError::runtime(format!("failed to read extracted directory: {error}"))
    })? {
        let entry = entry.map_err(|error| {
            CoreError::runtime(format!("failed to inspect extracted entry: {error}"))
        })?;
        let path = entry.path();
        let metadata = entry.metadata().map_err(|error| {
            CoreError::runtime(format!("failed to inspect extracted metadata: {error}"))
        })?;
        if metadata.is_dir() {
            collect_jars(root, &path, jars)?;
            continue;
        }
        if path
            .extension()
            .and_then(|value| value.to_str())
            .is_some_and(|value| value.eq_ignore_ascii_case("jar"))
        {
            let relative = path
                .strip_prefix(root)
                .ok()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .replace('\\', "/");
            if !relative.is_empty() {
                jars.push(relative);
            }
        }
    }
    Ok(())
}

fn fetch_json<T: for<'de> Deserialize<'de>>(
    url: &str,
    headers: &[(&str, &str)],
) -> Result<T, CoreError> {
    let mut command = ProcessCommand::new("/usr/bin/curl");
    command.args(["-fsSL", url]);
    for (name, value) in headers {
        command.args(["-H", &format!("{name}: {value}")]);
    }
    let output = command
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to launch curl: {error}")))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(CoreError::runtime(format!(
            "http request failed for {url}: {}",
            stderr.trim()
        )));
    }
    serde_json::from_slice(&output.stdout)
        .map_err(|error| CoreError::runtime(format!("failed to decode json from {url}: {error}")))
}

fn fetch_json_value(url: &str, headers: &[(&str, &str)]) -> Result<Value, CoreError> {
    let mut command = ProcessCommand::new("/usr/bin/curl");
    command.args(["-fsSL", url]);
    for (name, value) in headers {
        command.args(["-H", &format!("{name}: {value}")]);
    }
    let output = command
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to launch curl: {error}")))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(CoreError::runtime(format!(
            "http request failed for {url}: {}",
            stderr.trim()
        )));
    }
    serde_json::from_slice(&output.stdout)
        .map_err(|error| CoreError::runtime(format!("failed to decode json from {url}: {error}")))
}

fn fetch_fastmirror_cores(
    base_url: Option<&str>,
) -> Result<Vec<FastMirrorCoreSummaryWire>, CoreError> {
    let url = scsl_core::normalize_fastmirror_base_url(base_url);
    let payload: Value = fetch_json_value(&url, &[("Accept", "application/json")])?;
    decode_wrapped_or_direct(payload)
}

fn fetch_fastmirror_game_versions(
    core_name: &str,
    base_url: Option<&str>,
) -> Result<Vec<String>, CoreError> {
    let url = format!(
        "{}/{}",
        scsl_core::normalize_fastmirror_base_url(base_url),
        core_name.trim()
    );
    let payload: Value = fetch_json_value(&url, &[("Accept", "application/json")])?;
    let info: FastMirrorCoreInfoWire = decode_wrapped_or_direct(payload)?;
    Ok(info.mc_versions)
}

fn fetch_fastmirror_core_versions(
    core_name: &str,
    game_version: &str,
    base_url: Option<&str>,
) -> Result<Vec<String>, CoreError> {
    let mut url = format!(
        "{}/{}/{}",
        scsl_core::normalize_fastmirror_base_url(base_url),
        core_name.trim(),
        game_version.trim()
    );
    url.push_str("?offset=0&limit=25");
    let payload: Value = fetch_json_value(&url, &[("Accept", "application/json")])?;
    let builds: FastMirrorBuildListWire = decode_wrapped_or_direct(payload)?;
    Ok(scsl_core::unique_strings(
        builds
            .builds
            .into_iter()
            .map(|item| item.core_version)
            .collect::<Vec<_>>(),
    ))
}

fn fetch_fastmirror_detail(
    core_name: &str,
    game_version: &str,
    core_version: &str,
    base_url: Option<&str>,
) -> Result<FastMirrorCoreDetailWire, CoreError> {
    let url = fastmirror_core_detail_url(
        base_url,
        core_name.trim(),
        game_version.trim(),
        core_version.trim(),
    );
    let payload: Value = fetch_json_value(&url, &[("Accept", "application/json")])?;
    decode_wrapped_or_direct(payload)
}

fn fetch_polars_core_types(base_url: Option<&str>) -> Result<Vec<PolarsCoreTypeWire>, CoreError> {
    let url = scsl_core::normalize_polars_base_url(base_url);
    fetch_json(&url, &[("Accept", "application/json")])
}

fn fetch_polars_core_items(
    core_type_id: i64,
    base_url: Option<&str>,
) -> Result<Vec<PolarsCoreItemWire>, CoreError> {
    let url = scsl_core::polars_core_items_url(base_url, core_type_id);
    let mut items: Vec<PolarsCoreItemWire> = fetch_json(&url, &[("Accept", "application/json")])?;
    for item in &mut items {
        item.download_url = scsl_core::normalize_polars_download_url(&item.download_url);
    }
    Ok(items)
}

fn fetch_custom_cores(
    args: MirrorCustomConfigArgs,
) -> Result<Vec<FastMirrorCoreSummaryWire>, CoreError> {
    let config: MirrorCustomAPIConfigWire =
        serde_json::from_str(&args.config_json).map_err(|error| {
            CoreError::validation(format!("invalid custom mirror config json: {error}"))
        })?;
    let url = custom_url(&args.base_url, &config.core_list_path, "", "", "")?;
    let root = custom_root(
        fetch_json_value(&url, &[("Accept", "application/json")])?,
        &config,
    );
    let cores = custom_resolve_value(&root, &config.cores_key_path).unwrap_or(root);
    let array = cores.as_array().ok_or_else(|| {
        CoreError::runtime("custom mirror cores payload is not an array".to_string())
    })?;
    Ok(array
        .iter()
        .filter_map(|item| item.as_object())
        .filter_map(|dict| {
            let name = custom_string(dict, &config.core_name_key);
            if name.is_empty() {
                return None;
            }
            let tag = custom_string(dict, &config.core_tag_key);
            Some(FastMirrorCoreSummaryWire {
                name,
                tag: if tag.is_empty() { None } else { Some(tag) },
                recommend: custom_bool(dict, &config.core_recommend_key),
                homepage: None,
                mc_versions: None,
            })
        })
        .collect())
}

fn fetch_custom_game_versions(args: MirrorCustomCoreArgs) -> Result<Vec<String>, CoreError> {
    let config: MirrorCustomAPIConfigWire =
        serde_json::from_str(&args.config_json).map_err(|error| {
            CoreError::validation(format!("invalid custom mirror config json: {error}"))
        })?;
    let url = custom_url(
        &args.base_url,
        &config.core_detail_path,
        &args.core_name,
        "",
        "",
    )?;
    let root = custom_root(
        fetch_json_value(&url, &[("Accept", "application/json")])?,
        &config,
    );
    let versions = custom_resolve_value(&root, &config.versions_key_path).ok_or_else(|| {
        CoreError::runtime("custom mirror versions payload is missing".to_string())
    })?;
    custom_string_array(&versions)
}

fn fetch_custom_core_versions(args: MirrorCustomCoreGameArgs) -> Result<Vec<String>, CoreError> {
    let config: MirrorCustomAPIConfigWire =
        serde_json::from_str(&args.config_json).map_err(|error| {
            CoreError::validation(format!("invalid custom mirror config json: {error}"))
        })?;
    let url = custom_url(
        &args.base_url,
        &config.core_builds_path,
        &args.core_name,
        &args.game_version,
        "",
    )?;
    let root = custom_root(
        fetch_json_value(&url, &[("Accept", "application/json")])?,
        &config,
    );
    let builds = custom_resolve_value(&root, &config.builds_key_path)
        .ok_or_else(|| CoreError::runtime("custom mirror builds payload is missing".to_string()))?;
    let array = builds.as_array().ok_or_else(|| {
        CoreError::runtime("custom mirror builds payload is not an array".to_string())
    })?;
    Ok(scsl_core::unique_strings(
        array
            .iter()
            .filter_map(|item| item.as_object())
            .map(|dict| custom_string(dict, &config.build_version_key))
            .filter(|value| !value.is_empty())
            .collect::<Vec<_>>(),
    ))
}

fn fetch_custom_detail(
    args: MirrorCustomDetailArgs,
) -> Result<FastMirrorCoreDetailWire, CoreError> {
    let config: MirrorCustomAPIConfigWire =
        serde_json::from_str(&args.config_json).map_err(|error| {
            CoreError::validation(format!("invalid custom mirror config json: {error}"))
        })?;
    let url = custom_url(
        &args.base_url,
        &config.core_build_detail_path,
        &args.core_name,
        &args.game_version,
        &args.core_version,
    )?;
    let root = custom_root(
        fetch_json_value(&url, &[("Accept", "application/json")])?,
        &config,
    );
    let dict = root.as_object().ok_or_else(|| {
        CoreError::runtime("custom mirror detail payload is not an object".to_string())
    })?;
    let download_url = custom_string(dict, &config.build_download_url_key);
    let filename = custom_string(dict, &config.build_file_name_key);
    if download_url.is_empty() || filename.is_empty() {
        return Err(CoreError::runtime(
            "custom mirror detail payload is missing download url or filename".to_string(),
        ));
    }
    let sha1 = custom_string(dict, &config.build_sha1_key);
    Ok(FastMirrorCoreDetailWire {
        download_url,
        sha1: if sha1.is_empty() { None } else { Some(sha1) },
        filename,
    })
}

fn decode_wrapped_or_direct<T: for<'de> Deserialize<'de>>(payload: Value) -> Result<T, CoreError> {
    if let Some(data) = payload.get("data") {
        serde_json::from_value(data.clone())
            .or_else(|_| serde_json::from_value(payload))
            .map_err(|error| {
                CoreError::runtime(format!("failed to decode wrapped payload: {error}"))
            })
    } else {
        serde_json::from_value(payload)
            .map_err(|error| CoreError::runtime(format!("failed to decode payload: {error}")))
    }
}

fn custom_root(payload: Value, config: &MirrorCustomAPIConfigWire) -> Value {
    if config.unwrap_data {
        payload.get("data").cloned().unwrap_or(payload)
    } else {
        payload
    }
}

fn custom_resolve_value(root: &Value, key_path: &str) -> Option<Value> {
    if key_path.trim().is_empty() {
        return Some(root.clone());
    }
    let mut current = root;
    for part in key_path.split('.') {
        if let Ok(index) = part.parse::<usize>() {
            current = current.get(index)?;
        } else {
            current = current.get(part)?;
        }
    }
    Some(current.clone())
}

fn custom_url(
    base_url: &str,
    template: &str,
    core_name: &str,
    game_version: &str,
    core_version: &str,
) -> Result<String, CoreError> {
    scsl_core::custom_mirror_url(base_url, template, core_name, game_version, core_version)
}

fn custom_string(dict: &serde_json::Map<String, Value>, key: &str) -> String {
    match dict.get(key) {
        Some(Value::String(value)) => value.clone(),
        Some(Value::Number(value)) => value.to_string(),
        Some(Value::Bool(value)) => value.to_string(),
        _ => String::new(),
    }
}

fn custom_bool(dict: &serde_json::Map<String, Value>, key: &str) -> BoolLike {
    match dict.get(key) {
        Some(Value::Bool(value)) => *value,
        Some(Value::Number(value)) => value.as_i64().unwrap_or_default() != 0,
        Some(Value::String(value)) => matches!(value.as_str(), "true" | "1" | "yes"),
        _ => false,
    }
}

type BoolLike = bool;

fn custom_string_array(value: &Value) -> Result<Vec<String>, CoreError> {
    let array = value.as_array().ok_or_else(|| {
        CoreError::runtime("custom mirror versions payload is not an array".to_string())
    })?;
    Ok(array
        .iter()
        .filter_map(|item| match item {
            Value::String(value) => Some(value.clone()),
            Value::Number(value) => Some(value.to_string()),
            _ => None,
        })
        .collect())
}

fn fetch_modrinth_search(args: ModrinthSearchArgs) -> Result<Value, CoreError> {
    let mut url = format!(
        "https://api.modrinth.com/v2/search?index={}&offset={}&limit={}",
        url_encode(&args.index),
        args.offset,
        args.limit.clamp(1, 100)
    );
    if let Some(query) = args.query.filter(|value| !value.trim().is_empty()) {
        url.push_str("&query=");
        url.push_str(&url_encode(&query));
    }
    if let Some(facets_json) = args.facets_json.filter(|value| !value.trim().is_empty()) {
        url.push_str("&facets=");
        url.push_str(&url_encode(&facets_json));
    }
    fetch_json_value(&url, &[("Accept", "application/json")])
}

fn fetch_modrinth_game_versions(include_snapshots: bool) -> Result<Value, CoreError> {
    let payload = fetch_json_value(
        "https://api.modrinth.com/v2/tag/game_version",
        &[("Accept", "application/json")],
    )?;
    if include_snapshots {
        return Ok(payload);
    }
    let filtered = payload
        .as_array()
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|item| item.get("version_type").and_then(Value::as_str) == Some("release"))
        .collect::<Vec<_>>();
    Ok(Value::Array(filtered))
}

fn fetch_modrinth_versions_filter(
    id: &str,
    type_name: &str,
    selected_versions_json: &str,
    selected_loaders_json: &str,
) -> Result<Value, CoreError> {
    let selected_versions: Vec<String> =
        serde_json::from_str(selected_versions_json).map_err(|error| {
            CoreError::validation(format!("invalid selected versions json: {error}"))
        })?;
    let selected_loaders: Vec<String> =
        serde_json::from_str(selected_loaders_json).map_err(|error| {
            CoreError::validation(format!("invalid selected loaders json: {error}"))
        })?;
    let payload = fetch_json_value(
        &format!("https://api.modrinth.com/v2/project/{id}/version"),
        &[("Accept", "application/json")],
    )?;
    let versions = payload
        .as_array()
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|version| {
            modrinth_version_matches(version, &selected_versions, &selected_loaders, type_name)
        })
        .collect::<Vec<_>>();
    Ok(Value::Array(versions))
}

fn fetch_modrinth_dependencies(
    id: &str,
    type_name: &str,
    selected_versions_json: &str,
    selected_loaders_json: &str,
) -> Result<Value, CoreError> {
    let filtered = fetch_modrinth_versions_filter(
        id,
        type_name,
        selected_versions_json,
        selected_loaders_json,
    )?;
    let Some(first_version) = filtered.as_array().and_then(|items| items.first()).cloned() else {
        return Ok(json!({ "projects": [] }));
    };
    let Some(dependencies) = first_version.get("dependencies").and_then(Value::as_array) else {
        return Ok(json!({ "projects": [] }));
    };
    let selected_versions: Vec<String> =
        serde_json::from_str(selected_versions_json).map_err(|error| {
            CoreError::validation(format!("invalid selected versions json: {error}"))
        })?;
    let selected_loaders: Vec<String> =
        serde_json::from_str(selected_loaders_json).map_err(|error| {
            CoreError::validation(format!("invalid selected loaders json: {error}"))
        })?;
    let mut resolved = Vec::new();
    for dependency in dependencies {
        if dependency.get("dependency_type").and_then(Value::as_str) != Some("required") {
            continue;
        }
        let Some(project_id) = dependency.get("project_id").and_then(Value::as_str) else {
            continue;
        };
        if let Some(version_id) = dependency.get("version_id").and_then(Value::as_str) {
            let version = fetch_json_value(
                &format!("https://api.modrinth.com/v2/version/{version_id}"),
                &[("Accept", "application/json")],
            )?;
            resolved.push(version);
            continue;
        }
        let dep_filtered = fetch_modrinth_versions_filter(
            project_id,
            type_name,
            selected_versions_json,
            selected_loaders_json,
        )?;
        if let Some(version) = dep_filtered
            .as_array()
            .and_then(|items| items.first())
            .cloned()
        {
            if modrinth_version_matches(&version, &selected_versions, &selected_loaders, type_name)
            {
                resolved.push(version);
            }
        }
    }
    Ok(json!({ "projects": resolved }))
}

fn modrinth_version_matches(
    version: &Value,
    selected_versions: &[String],
    selected_loaders: &[String],
    type_name: &str,
) -> bool {
    let game_versions = version
        .get("game_versions")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|item| item.as_str().map(str::to_string))
        .collect::<Vec<_>>();
    let mut loaders = selected_loaders.to_vec();
    if type_name == "datapack" {
        loaders = vec!["datapack".to_string()];
    } else if type_name == "resourcepack" {
        loaders = vec!["minecraft".to_string()];
    }
    let version_match = selected_versions.is_empty()
        || game_versions
            .iter()
            .any(|version_name| selected_versions.contains(version_name));
    let version_loaders = version
        .get("loaders")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|item| item.as_str().map(str::to_string))
        .collect::<Vec<_>>();
    let loader_match = if type_name == "shader" || type_name == "resourcepack" {
        true
    } else {
        loaders.is_empty()
            || version_loaders
                .iter()
                .any(|loader| loaders.contains(loader))
    };
    version_match && loader_match
}

fn url_encode(value: &str) -> String {
    let mut encoded = String::new();
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                encoded.push(byte as char)
            }
            b' ' => encoded.push_str("%20"),
            _ => encoded.push_str(&format!("%{:02X}", byte)),
        }
    }
    encoded
}

#[derive(Serialize, Deserialize)]
struct ServerAddressEntry {
    id: String,
    name: String,
    address: String,
    port: i32,
    hidden: bool,
    icon: Option<String>,
    #[serde(rename = "acceptTextures")]
    accept_textures: bool,
}

#[derive(Serialize, Deserialize)]
struct LitematicaMetadataSummary {
    author: Option<String>,
    description: Option<String>,
    version: Option<String>,
    #[serde(rename = "regionCount")]
    region_count: Option<i32>,
    #[serde(rename = "totalBlocks")]
    total_blocks: Option<i32>,
}

#[derive(Serialize, Deserialize)]
struct LitematicaFullMetadata {
    name: String,
    author: String,
    description: String,
    #[serde(rename = "timeCreated")]
    time_created: i64,
    #[serde(rename = "timeModified")]
    time_modified: i64,
    #[serde(rename = "totalVolume")]
    total_volume: i32,
    #[serde(rename = "totalBlocks")]
    total_blocks: i32,
    #[serde(rename = "enclosingSize")]
    enclosing_size: LitematicaSize,
    #[serde(rename = "regionCount")]
    region_count: i32,
}

#[derive(Serialize, Deserialize)]
struct LitematicaSize {
    x: i32,
    y: i32,
    z: i32,
}

#[derive(Deserialize, Serialize)]
struct ServerDatRoot {
    #[serde(default, rename = "servers")]
    servers: Vec<ServerDatServer>,
}

#[derive(Deserialize, Serialize)]
struct ServerDatServer {
    name: String,
    ip: String,
    #[serde(default)]
    hidden: i8,
    #[serde(default)]
    icon: Option<String>,
    #[serde(default, rename = "preventsChatReports")]
    prevents_chat_reports: i8,
}

#[derive(Deserialize)]
struct LitematicaRoot {
    #[serde(rename = "Metadata")]
    metadata: LitematicaMetadataNbt,
}

#[derive(Deserialize)]
struct LitematicaMetadataNbt {
    #[serde(rename = "Name")]
    name: Option<String>,
    #[serde(rename = "Author")]
    author: Option<String>,
    #[serde(rename = "Description")]
    description: Option<String>,
    #[serde(rename = "Version")]
    version: Option<String>,
    #[serde(rename = "RegionCount")]
    region_count: Option<NbtNumber>,
    #[serde(rename = "TotalBlocks")]
    total_blocks: Option<NbtNumber>,
    #[serde(rename = "TimeCreated")]
    time_created: Option<NbtLong>,
    #[serde(rename = "TimeModified")]
    time_modified: Option<NbtLong>,
    #[serde(rename = "TotalVolume")]
    total_volume: Option<NbtNumber>,
    #[serde(rename = "EnclosingSize")]
    enclosing_size: Option<LitematicaSizeNbt>,
}

#[derive(Deserialize)]
struct LitematicaSizeNbt {
    x: NbtNumber,
    y: NbtNumber,
    z: NbtNumber,
}

#[derive(Deserialize, Copy, Clone)]
#[serde(untagged)]
enum NbtNumber {
    I32(i32),
    I64(i64),
}

type NbtLong = NbtNumber;

impl NbtNumber {
    fn as_i32(self) -> i32 {
        match self {
            Self::I32(value) => value,
            Self::I64(value) => value as i32,
        }
    }

    fn as_i64(self) -> i64 {
        match self {
            Self::I32(value) => i64::from(value),
            Self::I64(value) => value,
        }
    }
}

fn read_server_addresses(path: &Path) -> Result<Vec<ServerAddressEntry>, CoreError> {
    if !path.exists() {
        return Ok(Vec::new());
    }
    let data = read_nbt_file(path)?;
    let root: ServerDatRoot = nbt_from_bytes(&data)
        .map_err(|error| CoreError::runtime(format!("failed to decode servers.dat: {error}")))?;
    Ok(root
        .servers
        .into_iter()
        .map(|server| {
            let (address, port) = parse_server_host_and_port(&server.ip);
            ServerAddressEntry {
                id: build_stable_server_id(&server.name, &address, port),
                name: server.name,
                address,
                port,
                hidden: server.hidden != 0,
                icon: server.icon,
                accept_textures: server.prevents_chat_reports != 0,
            }
        })
        .collect())
}

fn write_server_addresses(path: &Path, json: &str) -> Result<(), CoreError> {
    let servers: Vec<ServerAddressEntry> = serde_json::from_str(json).map_err(|error| {
        CoreError::validation(format!("invalid server addresses json: {error}"))
    })?;
    let root = ServerDatRoot {
        servers: servers
            .into_iter()
            .map(|server| ServerDatServer {
                name: server.name,
                ip: if server.port > 0 {
                    format!("{}:{}", server.address, server.port)
                } else {
                    server.address
                },
                hidden: if server.hidden { 1 } else { 0 },
                icon: server.icon.filter(|value| !value.trim().is_empty()),
                prevents_chat_reports: if server.accept_textures { 1 } else { 0 },
            })
            .collect(),
    };
    let encoded = nbt_to_bytes(&root)
        .map_err(|error| CoreError::runtime(format!("failed to encode servers.dat: {error}")))?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| {
            CoreError::runtime(format!("failed to create servers.dat directory: {error}"))
        })?;
    }
    fs::write(path, encoded)
        .map_err(|error| CoreError::runtime(format!("failed to write servers.dat: {error}")))?;
    Ok(())
}

fn read_litematica_metadata(path: &Path, include_full: bool) -> Result<Value, CoreError> {
    let data = read_nbt_file(path)?;
    let root: LitematicaRoot = nbt_from_bytes(&data).map_err(|error| {
        CoreError::runtime(format!("failed to decode litematica metadata: {error}"))
    })?;
    if include_full {
        return serde_json::to_value(LitematicaFullMetadata {
            name: root
                .metadata
                .name
                .unwrap_or_else(|| default_name_from_path(path)),
            author: root.metadata.author.unwrap_or_default(),
            description: root.metadata.description.unwrap_or_default(),
            time_created: root
                .metadata
                .time_created
                .map(NbtNumber::as_i64)
                .unwrap_or(0),
            time_modified: root
                .metadata
                .time_modified
                .map(NbtNumber::as_i64)
                .unwrap_or(0),
            total_volume: root
                .metadata
                .total_volume
                .map(NbtNumber::as_i32)
                .unwrap_or(0),
            total_blocks: root
                .metadata
                .total_blocks
                .map(NbtNumber::as_i32)
                .unwrap_or(0),
            enclosing_size: root
                .metadata
                .enclosing_size
                .map(|size| LitematicaSize {
                    x: size.x.as_i32(),
                    y: size.y.as_i32(),
                    z: size.z.as_i32(),
                })
                .unwrap_or(LitematicaSize { x: 0, y: 0, z: 0 }),
            region_count: root
                .metadata
                .region_count
                .map(NbtNumber::as_i32)
                .unwrap_or(0),
        })
        .map_err(|error| CoreError::runtime(format!("failed to encode metadata: {error}")));
    }
    serde_json::to_value(LitematicaMetadataSummary {
        author: root.metadata.author,
        description: root.metadata.description,
        version: root.metadata.version,
        region_count: root.metadata.region_count.map(NbtNumber::as_i32),
        total_blocks: root.metadata.total_blocks.map(NbtNumber::as_i32),
    })
    .map_err(|error| CoreError::runtime(format!("failed to encode metadata: {error}")))
}

fn read_nbt_file(path: &Path) -> Result<Vec<u8>, CoreError> {
    let data = fs::read(path)
        .map_err(|error| CoreError::runtime(format!("failed to read nbt file: {error}")))?;
    if data.starts_with(&[0x1f, 0x8b]) {
        let mut decoder = GzDecoder::new(data.as_slice());
        let mut decoded = Vec::new();
        decoder.read_to_end(&mut decoded).map_err(|error| {
            CoreError::runtime(format!("failed to decompress nbt file: {error}"))
        })?;
        Ok(decoded)
    } else {
        Ok(data)
    }
}

fn parse_server_host_and_port(ip: &str) -> (String, i32) {
    if let Some((host, port)) = ip.rsplit_once(':')
        && let Ok(port) = port.parse::<i32>()
        && port > 0
    {
        return (host.to_string(), port);
    }
    (ip.to_string(), 0)
}

fn build_stable_server_id(name: &str, address: &str, port: i32) -> String {
    let content = format!("{name}|{address}|{port}");
    let hash = Sha256::digest(content.as_bytes());
    let mut bytes = [0_u8; 16];
    bytes.copy_from_slice(&hash[..16]);
    bytes[6] = (bytes[6] & 0x0F) | 0x50;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    uuid_bytes_to_string(bytes)
}

fn uuid_bytes_to_string(bytes: [u8; 16]) -> String {
    format!(
        "{:08x}-{:04x}-{:04x}-{:04x}-{:012x}",
        u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]),
        u16::from_be_bytes([bytes[4], bytes[5]]),
        u16::from_be_bytes([bytes[6], bytes[7]]),
        u16::from_be_bytes([bytes[8], bytes[9]]),
        u64::from_be_bytes([
            0, 0, bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ])
    )
}

fn default_name_from_path(path: &Path) -> String {
    path.file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_string()
}

fn build_game_launch_plan(json: &str) -> Result<GameLaunchPlanResponse, CoreError> {
    let request: GameLaunchPlanRequest = serde_json::from_str(json).map_err(|error| {
        CoreError::validation(format!("invalid game launch plan json: {error}"))
    })?;
    let java_path = request.java_path.trim().to_string();
    if java_path.is_empty() {
        return Err(CoreError::validation("game java path must not be empty"));
    }

    let mut arguments = request
        .launch_command
        .iter()
        .cloned()
        .map(|argument| replace_game_launch_placeholders(argument, &request))
        .collect::<Vec<_>>();

    if !request.jvm_arguments.trim().is_empty() {
        let mut extra_args = split_cli_args(&request.jvm_arguments);
        extra_args.append(&mut arguments);
        arguments = extra_args;
    }

    Ok(GameLaunchPlanResponse {
        java_path,
        arguments,
        working_directory: request.working_directory,
        environment: parse_environment_variables(&request.environment_variables),
    })
}

fn replace_game_launch_placeholders(input: String, request: &GameLaunchPlanRequest) -> String {
    let mut replaced = input
        .replace("${xms}", &request.xms.to_string())
        .replace("${xmx}", &request.xmx.to_string());

    if let Some(player) = &request.player {
        replaced = replaced
            .replace("${auth_player_name}", &player.name)
            .replace("${auth_uuid}", &player.id)
            .replace("${auth_access_token}", &player.access_token)
            .replace("${auth_xuid}", &player.xuid);
    }

    replaced
}

fn parse_environment_variables(input: &str) -> BTreeMap<String, String> {
    input
        .lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                return None;
            }
            trimmed.find('=').map(|index| {
                (
                    trimmed[..index].to_string(),
                    trimmed[index + 1..].to_string(),
                )
            })
        })
        .collect()
}

fn split_cli_args(input: &str) -> Vec<String> {
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

fn maven_coordinate_to_full_path(coordinate: &str, libraries_dir: &str) -> String {
    let base = PathBuf::from(libraries_dir);
    base.join(maven_coordinate_to_relative_path_for_url(coordinate))
        .to_string_lossy()
        .into_owned()
}

fn maven_coordinate_to_relative_path(coordinate: &str) -> Option<String> {
    let parts = coordinate.split(':').collect::<Vec<_>>();
    if parts.len() < 3 {
        return None;
    }

    let group = parts[0].replace('.', "/");
    let artifact = parts[1];

    let mut version = String::new();
    let mut classifier = None;

    match parts.len() {
        3 => version = parts[2].to_string(),
        4 => {
            version = parts[2].to_string();
            classifier = Some(parts[3].to_string());
        }
        5 => {
            version = parts[4].to_string();
            classifier = Some(parts[3].to_string());
        }
        _ => {}
    }

    Some(match classifier {
        Some(classifier) => {
            format!("{group}/{artifact}/{version}/{artifact}-{version}-{classifier}.jar")
        }
        None => format!("{group}/{artifact}/{version}/{artifact}-{version}.jar"),
    })
}

fn parse_maven_coordinate_with_at_symbol(coordinate: &str) -> String {
    let parts = coordinate.split(':').collect::<Vec<_>>();
    if parts.len() < 3 {
        return coordinate.to_string();
    }

    let group_id = parts[0];
    let artifact_id = parts[1];
    let mut version = parts[2].to_string();
    let mut extension = String::new();
    let mut classifier_name = String::new();

    if version.contains('@') {
        let version_copy = version.clone();
        let version_parts = version_copy.split('@').collect::<Vec<_>>();
        if version_parts.len() >= 2 {
            version = version_parts[0].to_string();
            extension = version_parts[1].to_string();
        }
    } else if parts.len() > 3 {
        let classifier_part = parts[3];
        if classifier_part.contains('@') {
            let classifier_parts = classifier_part.split('@').collect::<Vec<_>>();
            if classifier_parts.len() >= 2 {
                classifier_name = classifier_parts[0].to_string();
                extension = classifier_parts[1].to_string();
            }
        } else {
            extension = classifier_part.to_string();
        }
    }

    let classifier_suffix = if classifier_name.is_empty() {
        String::new()
    } else {
        format!("-{classifier_name}")
    };
    let extension_suffix = if extension.is_empty() {
        ".jar".to_string()
    } else {
        format!(".{extension}")
    };
    let file_name = format!("{artifact_id}-{version}{classifier_suffix}{extension_suffix}");
    let group_path = group_id.replace('.', "/");
    format!("{group_path}/{artifact_id}/{version}/{file_name}")
}

fn maven_coordinate_to_relative_path_for_url(coordinate: &str) -> String {
    if coordinate.contains('@') {
        parse_maven_coordinate_with_at_symbol(coordinate)
    } else {
        maven_coordinate_to_relative_path(coordinate).unwrap_or_else(|| coordinate.to_string())
    }
}

fn build_loader_classpath(
    json: &str,
    libraries_dir: &str,
    include_in_classpath_only: bool,
) -> Result<String, CoreError> {
    let payload: Value = serde_json::from_str(json)
        .map_err(|error| CoreError::validation(format!("invalid loader json: {error}")))?;
    let libraries = payload
        .get("libraries")
        .and_then(Value::as_array)
        .ok_or_else(|| CoreError::validation("loader json must contain libraries array"))?;
    let base = Path::new(libraries_dir);
    let mut paths = Vec::new();

    for library in libraries {
        if include_in_classpath_only
            && !library
                .get("include_in_classpath")
                .and_then(Value::as_bool)
                .unwrap_or(false)
        {
            continue;
        }

        if include_in_classpath_only {
            if let Some(path) = library
                .get("downloads")
                .and_then(|downloads| downloads.get("artifact"))
                .and_then(|artifact| artifact.get("path"))
                .and_then(Value::as_str)
            {
                paths.push(base.join(path).to_string_lossy().into_owned());
            }
            continue;
        }

        if let Some(name) = library.get("name").and_then(Value::as_str)
            && let Some(relative_path) = maven_coordinate_to_relative_path(name)
        {
            paths.push(base.join(relative_path).to_string_lossy().into_owned());
        }
    }

    Ok(paths.join(":"))
}

fn process_loader_placeholders(json: &str, game_version: &str) -> Result<Value, CoreError> {
    let mut payload: Value = serde_json::from_str(json)
        .map_err(|error| CoreError::validation(format!("invalid loader json: {error}")))?;
    let libraries = payload
        .get_mut("libraries")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| CoreError::validation("loader json must contain libraries array"))?;

    for library in libraries {
        if let Some(name) = library.get_mut("name")
            && let Some(text) = name.as_str()
        {
            *name = Value::String(text.replace("${modrinth.gameVersion}", game_version));
        }
    }

    Ok(payload)
}

fn execute_loader_processor(json: &str) -> Result<(), CoreError> {
    let request: ProcessorExecutionRequest = serde_json::from_str(json).map_err(|error| {
        CoreError::validation(format!("invalid processor execution json: {error}"))
    })?;
    let libraries_dir = PathBuf::from(&request.libraries_dir);
    let jar_path = validate_processor_jar_path(request.processor.jar.as_deref(), &libraries_dir)?;
    let classpath = build_processor_classpath(
        request.processor.classpath.as_deref(),
        &jar_path,
        &libraries_dir,
    )?;
    let main_class = get_main_class_from_jar(&jar_path)?;
    let command = build_processor_command(
        &classpath,
        &main_class,
        request.processor.args.as_deref(),
        &request.game_version,
        &libraries_dir,
        request.data.as_ref(),
    );
    execute_java_command(&request.java_path, &command, &libraries_dir)?;
    if let Some(outputs) = request.processor.outputs.as_ref() {
        process_processor_outputs(outputs, &libraries_dir)?;
    }
    Ok(())
}

fn validate_processor_jar_path(
    jar: Option<&str>,
    libraries_dir: &Path,
) -> Result<PathBuf, CoreError> {
    let jar = jar.ok_or_else(|| CoreError::validation("processor jar is missing"))?;
    let relative_path = maven_coordinate_to_relative_path(jar).ok_or_else(|| {
        CoreError::validation(format!("invalid processor maven coordinate: {jar}"))
    })?;
    let jar_path = libraries_dir.join(relative_path);
    if jar_path.exists() {
        Ok(jar_path)
    } else {
        Err(CoreError::not_found("processor jar", jar.to_string()))
    }
}

fn build_processor_classpath(
    processor_classpath: Option<&[String]>,
    jar_path: &Path,
    libraries_dir: &Path,
) -> Result<Vec<String>, CoreError> {
    let mut classpath = Vec::new();
    if let Some(entries) = processor_classpath {
        for entry in entries {
            let path = if entry.contains(':') {
                libraries_dir.join(maven_coordinate_to_relative_path_for_url(entry))
            } else {
                libraries_dir.join(entry)
            };
            if path.exists() {
                classpath.push(path.to_string_lossy().into_owned());
            }
        }
    }
    classpath.push(jar_path.to_string_lossy().into_owned());
    Ok(classpath)
}

fn build_processor_command(
    classpath: &[String],
    main_class: &str,
    args: Option<&[String]>,
    game_version: &str,
    libraries_dir: &Path,
    data: Option<&BTreeMap<String, String>>,
) -> Vec<String> {
    let mut command = vec!["-cp".to_string(), classpath.join(":")];
    command.push(main_class.to_string());

    if let Some(args) = args {
        for raw_arg in args {
            if let Some(extracted) = extract_processor_client_value(raw_arg, libraries_dir) {
                command.push(process_processor_placeholders(
                    &extracted,
                    game_version,
                    libraries_dir,
                    data,
                ));
            }
        }
    }

    command
}

fn extract_processor_client_value(value: &str, libraries_dir: &Path) -> Option<String> {
    if value.contains(':') && !value.starts_with('[') && !value.starts_with('{') {
        return Some(
            libraries_dir
                .join(maven_coordinate_to_relative_path_for_url(value))
                .to_string_lossy()
                .into_owned(),
        );
    }

    if value.starts_with('[') && value.ends_with(']') {
        let content = &value[1..value.len() - 1];
        if content.contains(':') {
            return Some(
                libraries_dir
                    .join(maven_coordinate_to_relative_path_for_url(content))
                    .to_string_lossy()
                    .into_owned(),
            );
        }
        return Some(content.to_string());
    }

    Some(value.to_string())
}

fn process_processor_placeholders(
    arg: &str,
    game_version: &str,
    libraries_dir: &Path,
    data: Option<&BTreeMap<String, String>>,
) -> String {
    if !arg.contains('{') {
        return arg.to_string();
    }

    let mut processed = arg
        .replace("{SIDE}", "client")
        .replace("{VERSION}", game_version)
        .replace("{VERSION_NAME}", game_version)
        .replace("{LIBRARY_DIR}", &libraries_dir.to_string_lossy())
        .replace("{WORKING_DIR}", &libraries_dir.to_string_lossy());

    if let Some(data) = data {
        for (key, value) in data {
            let replacement = if value.contains(':') && !value.starts_with('/') {
                extract_processor_client_value(value, libraries_dir)
                    .unwrap_or_else(|| value.clone())
            } else {
                value.clone()
            };
            processed = processed.replace(&format!("{{{key}}}"), &replacement);
        }
    }

    processed
}

fn execute_java_command(
    java_path: &str,
    command: &[String],
    working_dir: &Path,
) -> Result<(), CoreError> {
    let output = ProcessCommand::new(java_path)
        .args(command)
        .current_dir(working_dir)
        .env("LIBRARY_DIR", working_dir)
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to launch processor: {error}")))?;
    if output.status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let message = if stderr.is_empty() {
            stdout
        } else if stdout.is_empty() {
            stderr
        } else {
            format!("{stdout}\n{stderr}")
        };
        Err(CoreError::runtime(format!(
            "processor execution failed (exit code {}): {}",
            output.status.code().unwrap_or(-1),
            message
        )))
    }
}

fn process_processor_outputs(
    outputs: &BTreeMap<String, String>,
    working_dir: &Path,
) -> Result<(), CoreError> {
    for (source, destination) in outputs {
        let source_path = working_dir.join(source);
        let destination_path = working_dir.join(destination);
        if !source_path.exists() {
            continue;
        }
        if let Some(parent) = destination_path.parent() {
            fs::create_dir_all(parent).map_err(|error| {
                CoreError::runtime(format!(
                    "failed to create processor output directory: {error}"
                ))
            })?;
        }
        if destination_path.exists() {
            remove_path_if_exists(&destination_path)?;
        }
        fs::rename(&source_path, &destination_path).map_err(|error| {
            CoreError::runtime(format!("failed to move processor output: {error}"))
        })?;
    }
    Ok(())
}

fn get_main_class_from_jar(jar_path: &Path) -> Result<String, CoreError> {
    let file = File::open(jar_path)
        .map_err(|error| CoreError::runtime(format!("failed to open processor jar: {error}")))?;
    let mut archive = ZipArchive::new(file)
        .map_err(|error| CoreError::runtime(format!("failed to read processor jar: {error}")))?;
    let mut manifest = archive
        .by_name("META-INF/MANIFEST.MF")
        .map_err(|error| CoreError::runtime(format!("missing processor manifest: {error}")))?;
    let mut content = String::new();
    manifest.read_to_string(&mut content).map_err(|error| {
        CoreError::runtime(format!("failed to read processor manifest: {error}"))
    })?;
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(main_class) = trimmed.strip_prefix("Main-Class:") {
            return Ok(main_class.trim().to_string());
        }
    }
    Err(CoreError::runtime(
        "processor manifest missing Main-Class".to_string(),
    ))
}

fn set_executable_permission(path: &Path) -> Result<(), CoreError> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let metadata = fs::metadata(path).map_err(|error| {
            CoreError::runtime(format!("failed to inspect file permissions: {error}"))
        })?;
        let mut permissions = metadata.permissions();
        permissions.set_mode(permissions.mode() | 0o111);
        fs::set_permissions(path, permissions).map_err(|error| {
            CoreError::runtime(format!("failed to set executable permission: {error}"))
        })?;
        Ok(())
    }
    #[cfg(not(unix))]
    {
        let _ = path;
        Ok(())
    }
}

fn download_file_with_headers(
    url: &str,
    destination: &Path,
    expected_sha1: Option<&str>,
    headers_json: Option<&str>,
) -> Result<PathBuf, CoreError> {
    if !(url.starts_with("https://") || url.starts_with("http://")) {
        return Err(CoreError::validation("invalid download url"));
    }

    let parent = destination.parent().ok_or_else(|| {
        CoreError::validation("download destination must have a parent directory")
    })?;
    fs::create_dir_all(parent).map_err(|error| {
        CoreError::runtime(format!("failed to create download directory: {error}"))
    })?;

    let temp_path = destination.with_extension(format!(
        "{}.download",
        destination
            .extension()
            .and_then(|ext| ext.to_str())
            .unwrap_or_default()
    ));
    if temp_path.exists() {
        let _ = fs::remove_file(&temp_path);
    }

    let mut command = ProcessCommand::new("curl");
    command
        .arg("-L")
        .arg("--fail")
        .arg("--silent")
        .arg("--show-error");

    if let Some(headers_json) = headers_json.filter(|value| !value.trim().is_empty()) {
        let headers: BTreeMap<String, String> = serde_json::from_str(headers_json)
            .map_err(|error| CoreError::validation(format!("invalid headers json: {error}")))?;
        for (key, value) in headers {
            command.arg("-H").arg(format!("{key}: {value}"));
        }
    }

    let output = command
        .arg("--output")
        .arg(&temp_path)
        .arg(url)
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to spawn curl: {error}")))?;
    if !output.status.success() {
        return Err(CoreError::runtime(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }

    if let Some(expected_sha1) = expected_sha1.filter(|value| !value.trim().is_empty()) {
        let actual = compute_sha1_file(&temp_path)?;
        if !actual.eq_ignore_ascii_case(expected_sha1.trim()) {
            let _ = fs::remove_file(&temp_path);
            return Err(CoreError::runtime(format!(
                "sha1 mismatch: expected {expected_sha1}, got {actual}"
            )));
        }
    }

    if destination.exists() {
        let _ = fs::remove_file(destination);
    }
    fs::rename(&temp_path, destination).map_err(|error| {
        CoreError::runtime(format!("failed to persist downloaded file: {error}"))
    })?;
    Ok(destination.to_path_buf())
}

fn compute_sha1_file(path: &Path) -> Result<String, CoreError> {
    let output = ProcessCommand::new("shasum")
        .arg("-a")
        .arg("1")
        .arg(path)
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to compute sha1: {error}")))?;
    if !output.status.success() {
        return Err(CoreError::runtime(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let sha1 = stdout
        .split_whitespace()
        .next()
        .unwrap_or_default()
        .to_string();
    if sha1.is_empty() {
        return Err(CoreError::runtime("sha1 command returned empty output"));
    }
    Ok(sha1)
}

fn fetch_plain_text(url: &str, headers: &[(&str, &str)]) -> Result<String, CoreError> {
    let mut command = ProcessCommand::new("/usr/bin/curl");
    command.args(["-fsSL", url]);
    for (name, value) in headers {
        command.args(["-H", &format!("{name}: {value}")]);
    }
    let output = command
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to launch curl: {error}")))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(CoreError::runtime(format!(
            "http request failed for {url}: {}",
            stderr.trim()
        )));
    }
    String::from_utf8(output.stdout)
        .map_err(|error| CoreError::runtime(format!("invalid utf8 from {url}: {error}")))
}

fn parse_headers_json(headers_json: Option<&str>) -> Result<Vec<(String, String)>, CoreError> {
    let Some(headers_json) = headers_json.filter(|value| !value.trim().is_empty()) else {
        return Ok(Vec::new());
    };
    let headers: BTreeMap<String, String> = serde_json::from_str(headers_json)
        .map_err(|error| CoreError::validation(format!("invalid headers json: {error}")))?;
    Ok(headers.into_iter().collect())
}

fn extract_zulu_runtime(zip_path: &Path, target_directory: &Path) -> Result<(), CoreError> {
    let file = File::open(zip_path)
        .map_err(|error| CoreError::runtime(format!("failed to open java zip: {error}")))?;
    let mut archive = ZipArchive::new(file)
        .map_err(|error| CoreError::runtime(format!("failed to open java archive: {error}")))?;

    if target_directory.exists() {
        remove_path_if_exists(target_directory)?;
    }
    fs::create_dir_all(target_directory).map_err(|error| {
        CoreError::runtime(format!("failed to create java target directory: {error}"))
    })?;

    let prefix = find_zulu_prefix(&mut archive)?
        .ok_or_else(|| CoreError::validation("zulu runtime folder not found in archive"))?;

    for index in 0..archive.len() {
        let mut entry = archive.by_index(index).map_err(|error| {
            CoreError::runtime(format!("failed to inspect java archive entry: {error}"))
        })?;
        let name = entry.name().replace('\\', "/");
        if !name.starts_with(&prefix) {
            continue;
        }
        let relative = name.trim_start_matches(&prefix);
        if relative.is_empty() {
            continue;
        }
        let output = target_directory.join(relative);
        if entry.is_dir() {
            fs::create_dir_all(&output).map_err(|error| {
                CoreError::runtime(format!("failed to create java directory: {error}"))
            })?;
            continue;
        }
        if let Some(parent) = output.parent() {
            fs::create_dir_all(parent).map_err(|error| {
                CoreError::runtime(format!("failed to create java parent directory: {error}"))
            })?;
        }
        let mut destination = File::create(&output)
            .map_err(|error| CoreError::runtime(format!("failed to create java file: {error}")))?;
        std::io::copy(&mut entry, &mut destination)
            .map_err(|error| CoreError::runtime(format!("failed to extract java file: {error}")))?;
    }
    Ok(())
}

fn find_zulu_prefix(archive: &mut ZipArchive<File>) -> Result<Option<String>, CoreError> {
    for index in 0..archive.len() {
        let entry = archive.by_index(index).map_err(|error| {
            CoreError::runtime(format!("failed to inspect java archive entry: {error}"))
        })?;
        let name = entry.name().replace('\\', "/");
        let mut prefix_parts = Vec::new();
        for component in name.split('/') {
            if component.is_empty() {
                continue;
            }
            prefix_parts.push(component);
            if component.starts_with("zulu-") && component.contains(".jre") {
                return Ok(Some(format!("{}/", prefix_parts.join("/"))));
            }
        }
    }
    Ok(None)
}

fn hash_resource_files(directory: &Path) -> Result<Vec<ResourceFileHashResponse>, CoreError> {
    if !directory.exists() {
        return Ok(Vec::new());
    }

    let mut results = Vec::new();
    for entry in fs::read_dir(directory).map_err(|error| {
        CoreError::runtime(format!("failed to read resource directory: {error}"))
    })? {
        let entry = entry.map_err(|error| {
            CoreError::runtime(format!("failed to inspect resource entry: {error}"))
        })?;
        let path = entry.path();
        if !entry
            .file_type()
            .map_err(|error| {
                CoreError::runtime(format!("failed to inspect resource file type: {error}"))
            })?
            .is_file()
        {
            continue;
        }
        let extension = path
            .extension()
            .and_then(|value| value.to_str())
            .map(|value| value.to_ascii_lowercase())
            .unwrap_or_default();
        if !matches!(extension.as_str(), "jar" | "zip" | "disable") {
            continue;
        }
        results.push(ResourceFileHashResponse {
            path: path.display().to_string(),
            sha1: compute_sha1_file(&path)?,
        });
    }
    results.sort_by(|left, right| left.path.cmp(&right.path));
    Ok(results)
}

fn create_backup_archive(
    source_root: &Path,
    output_path: &Path,
    keep_count: Option<usize>,
) -> Result<(), CoreError> {
    let parent = output_path
        .parent()
        .ok_or_else(|| CoreError::validation("backup output path must have a parent directory"))?;
    fs::create_dir_all(parent).map_err(|error| {
        CoreError::runtime(format!("failed to create backup directory: {error}"))
    })?;
    if output_path.exists() {
        remove_path_if_exists(output_path)?;
    }
    let output = ProcessCommand::new("/usr/bin/ditto")
        .args([
            "-c",
            "-k",
            "--keepParent",
            source_root.to_string_lossy().as_ref(),
            output_path.to_string_lossy().as_ref(),
        ])
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to launch ditto: {error}")))?;
    if !output.status.success() {
        return Err(CoreError::runtime(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }
    if let Some(keep_count) = keep_count {
        prune_backup_archives(parent, keep_count)?;
    }
    Ok(())
}

fn list_backup_archives(backup_root: &Path) -> Result<Vec<BackupEntryResponse>, CoreError> {
    if !backup_root.exists() {
        return Ok(Vec::new());
    }
    let mut entries = Vec::new();
    for entry in fs::read_dir(backup_root)
        .map_err(|error| CoreError::runtime(format!("failed to read backup directory: {error}")))?
    {
        let entry = entry.map_err(|error| {
            CoreError::runtime(format!("failed to inspect backup entry: {error}"))
        })?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("zip") {
            continue;
        }
        let modified = entry
            .metadata()
            .and_then(|value| value.modified())
            .ok()
            .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
            .map(|value| value.as_secs_f64())
            .unwrap_or_default();
        entries.push(BackupEntryResponse {
            path: path.display().to_string(),
            modified_at: modified,
        });
    }
    entries.sort_by(|left, right| {
        right
            .modified_at
            .partial_cmp(&left.modified_at)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    Ok(entries)
}

fn list_backup_servers(backup_path: &Path) -> Result<Vec<String>, CoreError> {
    let file = File::open(backup_path)
        .map_err(|error| CoreError::runtime(format!("failed to open backup zip: {error}")))?;
    let mut archive = ZipArchive::new(file)
        .map_err(|error| CoreError::runtime(format!("failed to open backup archive: {error}")))?;
    let mut names = std::collections::BTreeSet::new();
    for index in 0..archive.len() {
        let entry = archive.by_index(index).map_err(|error| {
            CoreError::runtime(format!("failed to inspect backup archive entry: {error}"))
        })?;
        let normalized = entry.name().replace('\\', "/");
        if let Some(name) = backup_server_name_from_path(&normalized) {
            names.insert(name.to_string());
        }
    }
    Ok(names.into_iter().collect())
}

fn restore_backup_server(
    backup_path: &Path,
    server_name: &str,
    target_root: &Path,
) -> Result<BackupRestoreResponse, CoreError> {
    let file = File::open(backup_path)
        .map_err(|error| CoreError::runtime(format!("failed to open backup zip: {error}")))?;
    let mut archive = ZipArchive::new(file)
        .map_err(|error| CoreError::runtime(format!("failed to open backup archive: {error}")))?;
    fs::create_dir_all(target_root).map_err(|error| {
        CoreError::runtime(format!("failed to create restore target root: {error}"))
    })?;
    let server_root = target_root.join(server_name);
    if server_root.exists() {
        remove_path_if_exists(&server_root)?;
    }

    let prefix = format!("servers/{server_name}/");
    let mut restored = false;
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index).map_err(|error| {
            CoreError::runtime(format!("failed to inspect backup archive entry: {error}"))
        })?;
        let normalized = entry.name().replace('\\', "/");
        if !normalized.starts_with(&prefix) {
            continue;
        }
        let relative = normalized.trim_start_matches(&prefix);
        if relative.is_empty() {
            continue;
        }
        let output = server_root.join(relative);
        if entry.is_dir() {
            fs::create_dir_all(&output).map_err(|error| {
                CoreError::runtime(format!("failed to create restored directory: {error}"))
            })?;
            restored = true;
            continue;
        }
        if let Some(parent) = output.parent() {
            fs::create_dir_all(parent).map_err(|error| {
                CoreError::runtime(format!(
                    "failed to create restored parent directory: {error}"
                ))
            })?;
        }
        let mut destination = File::create(&output).map_err(|error| {
            CoreError::runtime(format!("failed to create restored file: {error}"))
        })?;
        std::io::copy(&mut entry, &mut destination).map_err(|error| {
            CoreError::runtime(format!("failed to restore backup file: {error}"))
        })?;
        restored = true;
    }
    if !restored {
        return Err(CoreError::not_found("backup server", server_name));
    }
    Ok(BackupRestoreResponse {
        created_server: false,
    })
}

fn backup_server_name_from_path(path: &str) -> Option<&str> {
    let normalized = path.trim_start_matches("./");
    let mut components = normalized.split('/').filter(|value| !value.is_empty());
    if components.next()? != "servers" {
        return None;
    }
    let name = components.next()?;
    if name.starts_with('.') || name == ".DS_Store" {
        return None;
    }
    Some(name)
}

fn prune_backup_archives(backup_root: &Path, keep_count: usize) -> Result<(), CoreError> {
    if keep_count == 0 {
        return Ok(());
    }
    let mut files = list_backup_archives(backup_root)?;
    if files.len() <= keep_count {
        return Ok(());
    }
    for file in files.drain(keep_count..) {
        remove_path_if_exists(Path::new(&file.path))?;
    }
    Ok(())
}

fn read_cli_settings() -> Result<CliSettingsFile, CoreError> {
    let path = cli_settings_path()?;
    let legacy_path = legacy_cli_settings_path()?;
    let target_path = if path.exists() {
        path
    } else if legacy_path.exists() {
        legacy_path
    } else {
        return Ok(CliSettingsFile::default());
    };
    let content = fs::read_to_string(&target_path)
        .map_err(|error| CoreError::runtime(format!("failed to read settings file: {error}")))?;
    serde_json::from_str(&content)
        .map_err(|error| CoreError::runtime(format!("failed to decode settings file: {error}")))
}

fn write_cli_settings(settings: &CliSettingsFile) -> Result<(), CoreError> {
    let path = cli_settings_path()?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| {
            CoreError::runtime(format!("failed to create settings directory: {error}"))
        })?;
    }
    let content = serde_json::to_string_pretty(settings)
        .map_err(|error| CoreError::runtime(format!("failed to encode settings file: {error}")))?;
    fs::write(&path, content)
        .map_err(|error| CoreError::runtime(format!("failed to write settings file: {error}")))?;
    Ok(())
}

fn cli_settings_path() -> Result<PathBuf, CoreError> {
    Ok(LocalAppServerStore::platform_paths()?
        .working_path
        .join("data")
        .join("settings.json"))
}

fn legacy_cli_settings_path() -> Result<PathBuf, CoreError> {
    Ok(LocalAppServerStore::platform_paths()?
        .working_path
        .join("data")
        .join("cli_settings.json"))
}

fn execute_rcon_command(
    host: &str,
    port: u16,
    password: &str,
    command: &str,
) -> Result<String, CoreError> {
    let mut stream = TcpStream::connect((host, port))
        .map_err(|error| CoreError::runtime(format!("failed to connect to rcon: {error}")))?;
    stream
        .set_read_timeout(Some(std::time::Duration::from_secs(6)))
        .map_err(|error| {
            CoreError::runtime(format!("failed to configure rcon timeout: {error}"))
        })?;
    stream
        .set_write_timeout(Some(std::time::Duration::from_secs(6)))
        .map_err(|error| {
            CoreError::runtime(format!("failed to configure rcon timeout: {error}"))
        })?;

    send_rcon_packet(&mut stream, 101, 3, password)?;
    let auth = receive_rcon_packet(&mut stream)?;
    if auth.request_id != 101 {
        return Err(CoreError::validation("rcon authentication failed"));
    }

    send_rcon_packet(&mut stream, 102, 2, command)?;
    let response = receive_rcon_packet(&mut stream)?;
    if response.request_id != 102 {
        return Err(CoreError::runtime("unexpected rcon response id"));
    }
    Ok(response.body)
}

struct RconPacket {
    request_id: i32,
    body: String,
}

fn send_rcon_packet(
    stream: &mut TcpStream,
    request_id: i32,
    packet_type: i32,
    body: &str,
) -> Result<(), CoreError> {
    let body_bytes = body.as_bytes();
    let length = 4 + 4 + body_bytes.len() + 2;
    let mut packet = Vec::with_capacity(length + 4);
    packet.extend_from_slice(&(length as i32).to_le_bytes());
    packet.extend_from_slice(&request_id.to_le_bytes());
    packet.extend_from_slice(&packet_type.to_le_bytes());
    packet.extend_from_slice(body_bytes);
    packet.extend_from_slice(&[0, 0]);
    std::io::Write::write_all(stream, &packet)
        .map_err(|error| CoreError::runtime(format!("failed to write rcon packet: {error}")))
}

fn receive_rcon_packet(stream: &mut TcpStream) -> Result<RconPacket, CoreError> {
    let mut length_bytes = [0_u8; 4];
    std::io::Read::read_exact(stream, &mut length_bytes).map_err(|error| {
        CoreError::runtime(format!("failed to read rcon packet length: {error}"))
    })?;
    let length = i32::from_le_bytes(length_bytes);
    if length < 10 {
        return Err(CoreError::runtime("invalid rcon packet length"));
    }

    let mut payload = vec![0_u8; length as usize];
    std::io::Read::read_exact(stream, &mut payload).map_err(|error| {
        CoreError::runtime(format!("failed to read rcon packet payload: {error}"))
    })?;

    let request_id = i32::from_le_bytes([payload[0], payload[1], payload[2], payload[3]]);
    let body = String::from_utf8_lossy(&payload[8..payload.len().saturating_sub(2)]).into_owned();
    Ok(RconPacket { request_id, body })
}
