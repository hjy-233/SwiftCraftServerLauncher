use scsl_core::CoreError;
use std::path::PathBuf;

pub struct Cli {
    pub db: Option<PathBuf>,
    pub working_path: Option<String>,
    pub demo: bool,
    pub command: Command,
}

pub enum Command {
    Server(ServerCommand),
    Mirror(MirrorCommand),
    Modrinth(ModrinthCommand),
    Resource(ResourceCommand),
    Game(GameCommand),
    Settings(SettingsCommand),
}

pub enum SettingsCommand {
    Read(SettingsScopeArgs),
    Write(SettingsWriteArgs),
}

pub struct SettingsScopeArgs {
    pub scope: String,
}

pub struct SettingsWriteArgs {
    pub scope: String,
    pub json: String,
}

pub enum ServerCommand {
    List,
    Show(ServerIdArgs),
    Delete(ServerIdArgs),
    DeleteCorrupted(ServerNameArgs),
    LaunchCommand(ServerIdArgs),
    LocalStartPlan(ServerJavaPathArgs),
    LocalStart(ServerJavaPathArgs),
    LocalLogPoll(ServerLocalLogPollArgs),
    CreateLocal(ServerCreateArgs),
    DownloadTarget(ServerResolveDownloadArgs),
    Corrupted,
    GameVersions(ServerGameVersionsArgs),
    LoaderVersions(ServerLoaderVersionsArgs),
    JavaVersion(ServerGameVersionArgs),
    LatestLoader(ServerLatestLoaderArgs),
    VerifyJar(ServerIdArgs),
    ForgeInstallPlan(ServerIdArgs),
    Status(ServerIdArgs),
    Start(ServerIdArgs),
    Stop(ServerIdArgs),
    Restart(ServerIdArgs),
    Logs(ServerLogsArgs),
    Send(ServerSendArgs),
    Interrupt(ServerInterruptArgs),
    Rcon(ServerSendArgs),
    Properties(ServerPropertiesCommand),
    Files(ServerFilesCommand),
    Players(ServerPlayersCommand),
    Schedules(ServerSchedulesCommand),
}

pub enum ServerPropertiesCommand {
    Read(ServerIdArgs),
    Write(ServerPropertiesWriteArgs),
}

pub enum ServerFilesCommand {
    List(ServerIdArgs),
    Read(ServerFilePathArgs),
    Write(ServerFilePathArgs),
    Mkdir(ServerFilePathArgs),
    Touch(ServerFilePathArgs),
    Move(ServerFileMoveArgs),
    Delete(ServerFilePathArgs),
    Import(ServerFileImportArgs),
}

pub enum ServerSchedulesCommand {
    Read(ServerIdArgs),
    Write(ServerIdArgs),
}

pub enum ServerPlayersCommand {
    Read(ServerPlayerListArgs),
    Write(ServerPlayerListArgs),
}

pub struct ServerPlayerListArgs {
    pub id: String,
    pub file_name: String,
}

pub enum ResourceCommand {
    Download(ResourceDownloadArgs),
}

pub enum GameCommand {
    LaunchPlan(GameLaunchPlanArgs),
    MavenRelativePath(GameMavenCoordinateArgs),
    MavenPath(GameMavenPathArgs),
    LoaderClasspath(GameLoaderClasspathArgs),
    ProcessLoaderPlaceholders(GameLoaderPlaceholderArgs),
    ExecuteProcessor(GameExecuteProcessorArgs),
    DownloadFile(GameDownloadFileArgs),
    FetchJson(GameFetchJsonArgs),
    SetExecutable(GameSetExecutableArgs),
    ExtractZuluRuntime(GameExtractZuluRuntimeArgs),
    Sha1File(GameSha1FileArgs),
    HashResourceFiles(GameHashResourceFilesArgs),
    BackupCreate(GameBackupCreateArgs),
    BackupList(GameBackupListArgs),
    BackupListServers(GameBackupListServersArgs),
    BackupRestore(GameBackupRestoreArgs),
}

pub enum MirrorCommand {
    FastMirrorCores(MirrorBaseUrlArgs),
    FastMirrorGameVersions(MirrorCoreArgs),
    FastMirrorCoreVersions(MirrorCoreGameVersionArgs),
    FastMirrorDetail(MirrorCoreVersionDetailArgs),
    PolarsCoreTypes(MirrorBaseUrlArgs),
    PolarsCoreItems(MirrorPolarsItemsArgs),
    CustomCores(MirrorCustomConfigArgs),
    CustomGameVersions(MirrorCustomCoreArgs),
    CustomCoreVersions(MirrorCustomCoreGameArgs),
    CustomDetail(MirrorCustomDetailArgs),
}

pub enum ModrinthCommand {
    Search(ModrinthSearchArgs),
    Project(ModrinthIdArgs),
    Versions(ModrinthIdArgs),
    Version(ModrinthVersionIdArgs),
    FileByHash(ModrinthFileHashArgs),
    VersionInfo(ModrinthMinecraftVersionArgs),
    LoaderManifest(ModrinthLoaderNameArgs),
    LoaderProfile(ModrinthLoaderProfileArgs),
    VersionsFilter(ModrinthVersionsFilterArgs),
    Dependencies(ModrinthDependenciesArgs),
    Loaders,
    Categories,
    GameVersions(ModrinthGameVersionsArgs),
}

pub struct ServerIdArgs {
    pub id: String,
}

pub struct ServerNameArgs {
    pub name: String,
}

pub struct ServerLogsArgs {
    pub id: String,
    pub lines: usize,
}

pub struct ServerSendArgs {
    pub id: String,
    pub command: String,
}

pub struct ServerJavaPathArgs {
    pub id: String,
    pub java_path: String,
}

pub struct ServerLocalLogPollArgs {
    pub id: String,
    pub current_file_path: Option<String>,
    pub offset: u64,
}

pub struct ServerInterruptArgs {
    pub id: String,
    pub force: bool,
}

pub struct ServerPropertiesWriteArgs {
    pub id: String,
    pub json: String,
}

pub struct ServerFilePathArgs {
    pub id: String,
    pub path: String,
}

pub struct ServerFileMoveArgs {
    pub id: String,
    pub from: String,
    pub to: String,
}

pub struct ServerFileImportArgs {
    pub id: String,
    pub source: PathBuf,
    pub directory: String,
}

pub struct ResourceDownloadArgs {
    pub game_name: String,
    pub resource_type: String,
    pub url: String,
    pub file_name: String,
    pub sha1: Option<String>,
}

pub struct GameLaunchPlanArgs {
    pub json: String,
}

pub struct GameMavenCoordinateArgs {
    pub coordinate: String,
}

pub struct GameMavenPathArgs {
    pub coordinate: String,
    pub libraries_dir: String,
}

pub struct GameLoaderClasspathArgs {
    pub json: String,
    pub libraries_dir: String,
    pub include_in_classpath_only: bool,
}

pub struct GameLoaderPlaceholderArgs {
    pub json: String,
    pub game_version: String,
}

pub struct GameExecuteProcessorArgs {
    pub json: String,
}

pub struct GameDownloadFileArgs {
    pub url: String,
    pub destination: String,
    pub sha1: Option<String>,
    pub headers_json: Option<String>,
}

pub struct GameFetchJsonArgs {
    pub url: String,
    pub headers_json: Option<String>,
}

pub struct GameSetExecutableArgs {
    pub path: String,
}

pub struct GameExtractZuluRuntimeArgs {
    pub zip_path: String,
    pub target_directory: String,
}

pub struct GameSha1FileArgs {
    pub path: String,
}

pub struct GameHashResourceFilesArgs {
    pub directory: String,
}

pub struct GameBackupCreateArgs {
    pub source_root: String,
    pub output_path: String,
    pub keep_count: Option<usize>,
}

pub struct GameBackupListArgs {
    pub backup_root: String,
}

pub struct GameBackupListServersArgs {
    pub backup_path: String,
}

pub struct GameBackupRestoreArgs {
    pub backup_path: String,
    pub server_name: String,
    pub target_root: String,
}

pub struct ServerCreateArgs {
    pub json: String,
}

pub struct MirrorBaseUrlArgs {
    pub base_url: Option<String>,
}

pub struct MirrorCoreArgs {
    pub core_name: String,
    pub base_url: Option<String>,
}

pub struct MirrorCoreGameVersionArgs {
    pub core_name: String,
    pub game_version: String,
    pub base_url: Option<String>,
}

pub struct MirrorCoreVersionDetailArgs {
    pub core_name: String,
    pub game_version: String,
    pub core_version: String,
    pub base_url: Option<String>,
}

pub struct MirrorPolarsItemsArgs {
    pub core_type_id: i64,
    pub base_url: Option<String>,
}

pub struct MirrorCustomConfigArgs {
    pub config_json: String,
    pub base_url: String,
}

pub struct MirrorCustomCoreArgs {
    pub config_json: String,
    pub base_url: String,
    pub core_name: String,
}

pub struct MirrorCustomCoreGameArgs {
    pub config_json: String,
    pub base_url: String,
    pub core_name: String,
    pub game_version: String,
}

pub struct MirrorCustomDetailArgs {
    pub config_json: String,
    pub base_url: String,
    pub core_name: String,
    pub game_version: String,
    pub core_version: String,
}

pub struct ModrinthIdArgs {
    pub id: String,
}

pub struct ModrinthVersionIdArgs {
    pub version_id: String,
}

pub struct ModrinthFileHashArgs {
    pub hash: String,
}

pub struct ModrinthMinecraftVersionArgs {
    pub version: String,
}

pub struct ModrinthLoaderNameArgs {
    pub loader: String,
}

pub struct ModrinthLoaderProfileArgs {
    pub loader: String,
    pub version: String,
}

pub struct ModrinthSearchArgs {
    pub index: String,
    pub offset: i32,
    pub limit: i32,
    pub query: Option<String>,
    pub facets_json: Option<String>,
}

pub struct ModrinthGameVersionsArgs {
    pub include_snapshots: bool,
}

pub struct ModrinthVersionsFilterArgs {
    pub id: String,
    pub type_name: String,
    pub selected_versions_json: String,
    pub selected_loaders_json: String,
}

pub struct ModrinthDependenciesArgs {
    pub id: String,
    pub type_name: String,
    pub selected_versions_json: String,
    pub selected_loaders_json: String,
}

pub struct ServerResolveDownloadArgs {
    pub json: String,
}

pub struct ServerGameVersionArgs {
    pub game_version: String,
}

pub struct ServerGameVersionsArgs {
    pub server_type: String,
    pub include_snapshots: bool,
}

pub struct ServerLoaderVersionsArgs {
    pub server_type: String,
    pub game_version: String,
}

pub struct ServerLatestLoaderArgs {
    pub server_type: String,
    pub game_version: String,
}

impl Cli {
    pub fn parse(arguments: Vec<String>) -> Result<Self, CoreError> {
        let mut parser = ArgCursor::new(arguments);
        let mut db = None;
        let mut working_path = None;
        let mut demo = false;

        loop {
            match parser.peek().map(String::as_str) {
                Some("--db") => {
                    parser.next();
                    db = Some(PathBuf::from(parser.required_value("--db")?));
                }
                Some("--working-path") => {
                    parser.next();
                    working_path = Some(parser.required_value("--working-path")?);
                }
                Some("--demo") => {
                    parser.next();
                    demo = true;
                }
                _ => break,
            }
        }

        let command_name = parser.required("command")?;
        let command = match command_name.as_str() {
            "server" => Command::Server(parse_server_command(&mut parser)?),
            "mirror" => Command::Mirror(parse_mirror_command(&mut parser)?),
            "modrinth" => Command::Modrinth(parse_modrinth_command(&mut parser)?),
            "resource" => Command::Resource(parse_resource_command(&mut parser)?),
            "game" => Command::Game(parse_game_command(&mut parser)?),
            "settings" => Command::Settings(parse_settings_command(&mut parser)?),
            other => return Err(CoreError::validation(format!("unknown command: {other}"))),
        };

        parser.finish()?;

        Ok(Self {
            db,
            working_path,
            demo,
            command,
        })
    }
}

fn parse_server_command(parser: &mut ArgCursor) -> Result<ServerCommand, CoreError> {
    let command = parser.required("server command")?;
    match command.as_str() {
        "list" => Ok(ServerCommand::List),
        "show" => Ok(ServerCommand::Show(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "delete" => Ok(ServerCommand::Delete(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "delete-corrupted" => Ok(ServerCommand::DeleteCorrupted(ServerNameArgs {
            name: parser.required("server name")?,
        })),
        "command" => Ok(ServerCommand::LaunchCommand(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "local-start-plan" => {
            let id = parser.required("server id")?;
            let java_path = parser.required_flag_value("--java-path")?;
            Ok(ServerCommand::LocalStartPlan(ServerJavaPathArgs {
                id,
                java_path,
            }))
        }
        "local-start" => {
            let id = parser.required("server id")?;
            let java_path = parser.required_flag_value("--java-path")?;
            Ok(ServerCommand::LocalStart(ServerJavaPathArgs {
                id,
                java_path,
            }))
        }
        "local-log-poll" => {
            let id = parser.required("server id")?;
            let current_file_path = parser.optional_flag_value("--current-file-path")?;
            let offset = parser
                .optional_flag_value("--offset")?
                .and_then(|value| value.parse::<u64>().ok())
                .unwrap_or(0);
            Ok(ServerCommand::LocalLogPoll(ServerLocalLogPollArgs {
                id,
                current_file_path,
                offset,
            }))
        }
        "create-local" => Ok(ServerCommand::CreateLocal(ServerCreateArgs {
            json: parser.required_flag_value("--json")?,
        })),
        "download-target" => Ok(ServerCommand::DownloadTarget(ServerResolveDownloadArgs {
            json: parser.required_flag_value("--json")?,
        })),
        "corrupted" => Ok(ServerCommand::Corrupted),
        "game-versions" => {
            let server_type = parser.required_flag_value("--server-type")?;
            let mut include_snapshots = false;
            while let Some(flag) = parser.peek().map(String::as_str) {
                match flag {
                    "--include-snapshots" => {
                        parser.next();
                        include_snapshots = true;
                    }
                    _ => break,
                }
            }
            Ok(ServerCommand::GameVersions(ServerGameVersionsArgs {
                server_type,
                include_snapshots,
            }))
        }
        "loader-versions" => Ok(ServerCommand::LoaderVersions(ServerLoaderVersionsArgs {
            server_type: parser.required_flag_value("--server-type")?,
            game_version: parser.required_flag_value("--game-version")?,
        })),
        "java-version" => Ok(ServerCommand::JavaVersion(ServerGameVersionArgs {
            game_version: parser.required("game version")?,
        })),
        "latest-loader" => Ok(ServerCommand::LatestLoader(ServerLatestLoaderArgs {
            server_type: parser.required_flag_value("--server-type")?,
            game_version: parser.required_flag_value("--game-version")?,
        })),
        "verify-jar" => Ok(ServerCommand::VerifyJar(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "forge-install-plan" => Ok(ServerCommand::ForgeInstallPlan(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "status" => Ok(ServerCommand::Status(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "start" => Ok(ServerCommand::Start(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "stop" => Ok(ServerCommand::Stop(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "restart" => Ok(ServerCommand::Restart(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "logs" => {
            let id = parser.required("server id")?;
            let mut lines = 50_usize;
            while let Some(flag) = parser.peek().cloned() {
                match flag.as_str() {
                    "--lines" | "-n" => {
                        parser.next();
                        let raw = parser.required_value(&flag)?;
                        lines = raw.parse::<usize>().map_err(|error| {
                            CoreError::validation(format!("invalid lines value: {error}"))
                        })?;
                    }
                    _ => break,
                }
            }
            Ok(ServerCommand::Logs(ServerLogsArgs { id, lines }))
        }
        "send" => Ok(ServerCommand::Send(ServerSendArgs {
            id: parser.required("server id")?,
            command: parser.required("command")?,
        })),
        "interrupt" => {
            let id = parser.required("server id")?;
            let mut force = false;
            while let Some(flag) = parser.peek().map(String::as_str) {
                match flag {
                    "--force" => {
                        parser.next();
                        force = true;
                    }
                    _ => break,
                }
            }
            Ok(ServerCommand::Interrupt(ServerInterruptArgs { id, force }))
        }
        "rcon" => Ok(ServerCommand::Rcon(ServerSendArgs {
            id: parser.required("server id")?,
            command: parser.required("command")?,
        })),
        "properties" => Ok(ServerCommand::Properties(parse_server_properties_command(
            parser,
        )?)),
        "files" => Ok(ServerCommand::Files(parse_server_files_command(parser)?)),
        "players" => Ok(ServerCommand::Players(parse_server_players_command(
            parser,
        )?)),
        "schedules" => Ok(ServerCommand::Schedules(parse_server_schedules_command(
            parser,
        )?)),
        other => Err(CoreError::validation(format!(
            "unknown server command: {other}"
        ))),
    }
}

fn parse_mirror_command(parser: &mut ArgCursor) -> Result<MirrorCommand, CoreError> {
    let command = parser.required("mirror command")?;
    match command.as_str() {
        "fastmirror-cores" => Ok(MirrorCommand::FastMirrorCores(MirrorBaseUrlArgs {
            base_url: optional_flag_value(parser, "--base-url"),
        })),
        "fastmirror-game-versions" => Ok(MirrorCommand::FastMirrorGameVersions(MirrorCoreArgs {
            core_name: parser.required_flag_value("--core-name")?,
            base_url: optional_flag_value(parser, "--base-url"),
        })),
        "fastmirror-core-versions" => Ok(MirrorCommand::FastMirrorCoreVersions(
            MirrorCoreGameVersionArgs {
                core_name: parser.required_flag_value("--core-name")?,
                game_version: parser.required_flag_value("--game-version")?,
                base_url: optional_flag_value(parser, "--base-url"),
            },
        )),
        "fastmirror-detail" => Ok(MirrorCommand::FastMirrorDetail(
            MirrorCoreVersionDetailArgs {
                core_name: parser.required_flag_value("--core-name")?,
                game_version: parser.required_flag_value("--game-version")?,
                core_version: parser.required_flag_value("--core-version")?,
                base_url: optional_flag_value(parser, "--base-url"),
            },
        )),
        "polars-core-types" => Ok(MirrorCommand::PolarsCoreTypes(MirrorBaseUrlArgs {
            base_url: optional_flag_value(parser, "--base-url"),
        })),
        "polars-core-items" => Ok(MirrorCommand::PolarsCoreItems(MirrorPolarsItemsArgs {
            core_type_id: parser
                .required_flag_value("--core-type-id")?
                .parse::<i64>()
                .map_err(|error| CoreError::validation(format!("invalid core type id: {error}")))?,
            base_url: optional_flag_value(parser, "--base-url"),
        })),
        "custom-cores" => Ok(MirrorCommand::CustomCores(MirrorCustomConfigArgs {
            config_json: parser.required_flag_value("--config-json")?,
            base_url: parser.required_flag_value("--base-url")?,
        })),
        "custom-game-versions" => Ok(MirrorCommand::CustomGameVersions(MirrorCustomCoreArgs {
            config_json: parser.required_flag_value("--config-json")?,
            base_url: parser.required_flag_value("--base-url")?,
            core_name: parser.required_flag_value("--core-name")?,
        })),
        "custom-core-versions" => Ok(MirrorCommand::CustomCoreVersions(
            MirrorCustomCoreGameArgs {
                config_json: parser.required_flag_value("--config-json")?,
                base_url: parser.required_flag_value("--base-url")?,
                core_name: parser.required_flag_value("--core-name")?,
                game_version: parser.required_flag_value("--game-version")?,
            },
        )),
        "custom-detail" => Ok(MirrorCommand::CustomDetail(MirrorCustomDetailArgs {
            config_json: parser.required_flag_value("--config-json")?,
            base_url: parser.required_flag_value("--base-url")?,
            core_name: parser.required_flag_value("--core-name")?,
            game_version: parser.required_flag_value("--game-version")?,
            core_version: parser.required_flag_value("--core-version")?,
        })),
        other => Err(CoreError::validation(format!(
            "unknown mirror command: {other}"
        ))),
    }
}

fn parse_modrinth_command(parser: &mut ArgCursor) -> Result<ModrinthCommand, CoreError> {
    let command = parser.required("modrinth command")?;
    match command.as_str() {
        "search" => {
            let mut index = "relevance".to_string();
            let mut offset = 0_i32;
            let mut limit = 20_i32;
            let mut query = None;
            let mut facets_json = None;
            while let Some(flag) = parser.peek().cloned() {
                match flag.as_str() {
                    "--index" => {
                        parser.next();
                        index = parser.required_value("--index")?;
                    }
                    "--offset" => {
                        parser.next();
                        offset =
                            parser
                                .required_value("--offset")?
                                .parse::<i32>()
                                .map_err(|error| {
                                    CoreError::validation(format!("invalid offset: {error}"))
                                })?;
                    }
                    "--limit" => {
                        parser.next();
                        limit =
                            parser
                                .required_value("--limit")?
                                .parse::<i32>()
                                .map_err(|error| {
                                    CoreError::validation(format!("invalid limit: {error}"))
                                })?;
                    }
                    "--query" => {
                        parser.next();
                        query = Some(parser.required_value("--query")?);
                    }
                    "--facets-json" => {
                        parser.next();
                        facets_json = Some(parser.required_value("--facets-json")?);
                    }
                    _ => break,
                }
            }
            Ok(ModrinthCommand::Search(ModrinthSearchArgs {
                index,
                offset,
                limit,
                query,
                facets_json,
            }))
        }
        "project" => Ok(ModrinthCommand::Project(ModrinthIdArgs {
            id: parser.required("project id")?,
        })),
        "versions" => Ok(ModrinthCommand::Versions(ModrinthIdArgs {
            id: parser.required("project id")?,
        })),
        "version" => Ok(ModrinthCommand::Version(ModrinthVersionIdArgs {
            version_id: parser.required("version id")?,
        })),
        "file-by-hash" => Ok(ModrinthCommand::FileByHash(ModrinthFileHashArgs {
            hash: parser.required("file hash")?,
        })),
        "version-info" => Ok(ModrinthCommand::VersionInfo(ModrinthMinecraftVersionArgs {
            version: parser.required("minecraft version")?,
        })),
        "loader-manifest" => Ok(ModrinthCommand::LoaderManifest(ModrinthLoaderNameArgs {
            loader: parser.required("loader name")?,
        })),
        "loader-profile" => Ok(ModrinthCommand::LoaderProfile(ModrinthLoaderProfileArgs {
            loader: parser.required_flag_value("--loader")?,
            version: parser.required_flag_value("--version")?,
        })),
        "versions-filter" => Ok(ModrinthCommand::VersionsFilter(
            ModrinthVersionsFilterArgs {
                id: parser.required_flag_value("--id")?,
                type_name: parser.required_flag_value("--type")?,
                selected_versions_json: parser.required_flag_value("--selected-versions-json")?,
                selected_loaders_json: parser.required_flag_value("--selected-loaders-json")?,
            },
        )),
        "dependencies" => Ok(ModrinthCommand::Dependencies(ModrinthDependenciesArgs {
            id: parser.required_flag_value("--id")?,
            type_name: parser.required_flag_value("--type")?,
            selected_versions_json: parser.required_flag_value("--selected-versions-json")?,
            selected_loaders_json: parser.required_flag_value("--selected-loaders-json")?,
        })),
        "loaders" => Ok(ModrinthCommand::Loaders),
        "categories" => Ok(ModrinthCommand::Categories),
        "game-versions" => {
            let mut include_snapshots = false;
            while let Some(flag) = parser.peek().map(String::as_str) {
                match flag {
                    "--include-snapshots" => {
                        parser.next();
                        include_snapshots = true;
                    }
                    _ => break,
                }
            }
            Ok(ModrinthCommand::GameVersions(ModrinthGameVersionsArgs {
                include_snapshots,
            }))
        }
        other => Err(CoreError::validation(format!(
            "unknown modrinth command: {other}"
        ))),
    }
}

fn optional_flag_value(parser: &mut ArgCursor, flag: &str) -> Option<String> {
    match parser.peek().map(String::as_str) {
        Some(value) if value == flag => {
            parser.next();
            parser.required_value(flag).ok()
        }
        _ => None,
    }
}

fn parse_server_properties_command(
    parser: &mut ArgCursor,
) -> Result<ServerPropertiesCommand, CoreError> {
    let command = parser.required("server properties command")?;
    match command.as_str() {
        "read" => Ok(ServerPropertiesCommand::Read(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "write" => {
            let id = parser.required("server id")?;
            let json = parser.required_flag_value("--json")?;
            Ok(ServerPropertiesCommand::Write(ServerPropertiesWriteArgs {
                id,
                json,
            }))
        }
        other => Err(CoreError::validation(format!(
            "unknown server properties command: {other}"
        ))),
    }
}

fn parse_server_files_command(parser: &mut ArgCursor) -> Result<ServerFilesCommand, CoreError> {
    let command = parser.required("server files command")?;
    match command.as_str() {
        "list" => Ok(ServerFilesCommand::List(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "read" => Ok(ServerFilesCommand::Read(parse_server_file_path_args(
            parser,
        )?)),
        "write" => Ok(ServerFilesCommand::Write(parse_server_file_path_args(
            parser,
        )?)),
        "mkdir" => Ok(ServerFilesCommand::Mkdir(parse_server_file_path_args(
            parser,
        )?)),
        "touch" => Ok(ServerFilesCommand::Touch(parse_server_file_path_args(
            parser,
        )?)),
        "move" => {
            let id = parser.required("server id")?;
            let from = parser.required_flag_value("--from")?;
            let to = parser.required_flag_value("--to")?;
            Ok(ServerFilesCommand::Move(ServerFileMoveArgs {
                id,
                from,
                to,
            }))
        }
        "delete" => Ok(ServerFilesCommand::Delete(parse_server_file_path_args(
            parser,
        )?)),
        "import" => {
            let id = parser.required("server id")?;
            let source = PathBuf::from(parser.required_flag_value("--source")?);
            let directory = parser
                .optional_flag_value("--directory")?
                .unwrap_or_default();
            Ok(ServerFilesCommand::Import(ServerFileImportArgs {
                id,
                source,
                directory,
            }))
        }
        other => Err(CoreError::validation(format!(
            "unknown server files command: {other}"
        ))),
    }
}

fn parse_server_schedules_command(
    parser: &mut ArgCursor,
) -> Result<ServerSchedulesCommand, CoreError> {
    let command = parser.required("server schedules command")?;
    match command.as_str() {
        "read" => Ok(ServerSchedulesCommand::Read(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        "write" => Ok(ServerSchedulesCommand::Write(ServerIdArgs {
            id: parser.required("server id")?,
        })),
        other => Err(CoreError::validation(format!(
            "unknown server schedules command: {other}"
        ))),
    }
}

fn parse_server_players_command(parser: &mut ArgCursor) -> Result<ServerPlayersCommand, CoreError> {
    let command = parser.required("server players command")?;
    match command.as_str() {
        "read" => Ok(ServerPlayersCommand::Read(ServerPlayerListArgs {
            id: parser.required("server id")?,
            file_name: parser.required_flag_value("--file-name")?,
        })),
        "write" => Ok(ServerPlayersCommand::Write(ServerPlayerListArgs {
            id: parser.required("server id")?,
            file_name: parser.required_flag_value("--file-name")?,
        })),
        other => Err(CoreError::validation(format!(
            "unknown server players command: {other}"
        ))),
    }
}

fn parse_resource_command(parser: &mut ArgCursor) -> Result<ResourceCommand, CoreError> {
    let command = parser.required("resource command")?;
    match command.as_str() {
        "download" => Ok(ResourceCommand::Download(ResourceDownloadArgs {
            game_name: parser.required_flag_value("--game-name")?,
            resource_type: parser.required_flag_value("--resource-type")?,
            url: parser.required_flag_value("--url")?,
            file_name: parser.required_flag_value("--file-name")?,
            sha1: parser.optional_flag_value("--sha1")?,
        })),
        other => Err(CoreError::validation(format!(
            "unknown resource command: {other}"
        ))),
    }
}

fn parse_game_command(parser: &mut ArgCursor) -> Result<GameCommand, CoreError> {
    let command = parser.required("game command")?;
    match command.as_str() {
        "launch-plan" => Ok(GameCommand::LaunchPlan(GameLaunchPlanArgs {
            json: parser.required_flag_value("--json")?,
        })),
        "maven-relative-path" => Ok(GameCommand::MavenRelativePath(GameMavenCoordinateArgs {
            coordinate: parser.required("coordinate")?,
        })),
        "maven-path" => Ok(GameCommand::MavenPath(GameMavenPathArgs {
            coordinate: parser.required_flag_value("--coordinate")?,
            libraries_dir: parser.required_flag_value("--libraries-dir")?,
        })),
        "loader-classpath" => {
            let json = parser.required_flag_value("--json")?;
            let libraries_dir = parser.required_flag_value("--libraries-dir")?;
            let mut include_in_classpath_only = false;
            while let Some(flag) = parser.peek().map(String::as_str) {
                match flag {
                    "--include-in-classpath-only" => {
                        parser.next();
                        include_in_classpath_only = true;
                    }
                    _ => break,
                }
            }
            Ok(GameCommand::LoaderClasspath(GameLoaderClasspathArgs {
                json,
                libraries_dir,
                include_in_classpath_only,
            }))
        }
        "process-loader-placeholders" => Ok(GameCommand::ProcessLoaderPlaceholders(
            GameLoaderPlaceholderArgs {
                json: parser.required_flag_value("--json")?,
                game_version: parser.required_flag_value("--game-version")?,
            },
        )),
        "execute-processor" => Ok(GameCommand::ExecuteProcessor(GameExecuteProcessorArgs {
            json: parser.required_flag_value("--json")?,
        })),
        "download-file" => Ok(GameCommand::DownloadFile(GameDownloadFileArgs {
            url: parser.required_flag_value("--url")?,
            destination: parser.required_flag_value("--destination")?,
            sha1: parser.optional_flag_value("--sha1")?,
            headers_json: parser.optional_flag_value("--headers-json")?,
        })),
        "fetch-json" => Ok(GameCommand::FetchJson(GameFetchJsonArgs {
            url: parser.required_flag_value("--url")?,
            headers_json: parser.optional_flag_value("--headers-json")?,
        })),
        "set-executable" => Ok(GameCommand::SetExecutable(GameSetExecutableArgs {
            path: parser.required_flag_value("--path")?,
        })),
        "extract-zulu-runtime" => Ok(GameCommand::ExtractZuluRuntime(
            GameExtractZuluRuntimeArgs {
                zip_path: parser.required_flag_value("--zip-path")?,
                target_directory: parser.required_flag_value("--target-directory")?,
            },
        )),
        "sha1-file" => Ok(GameCommand::Sha1File(GameSha1FileArgs {
            path: parser.required_flag_value("--path")?,
        })),
        "hash-resource-files" => Ok(GameCommand::HashResourceFiles(GameHashResourceFilesArgs {
            directory: parser.required_flag_value("--directory")?,
        })),
        "backup-create" => Ok(GameCommand::BackupCreate(GameBackupCreateArgs {
            source_root: parser.required_flag_value("--source-root")?,
            output_path: parser.required_flag_value("--output-path")?,
            keep_count: parser
                .optional_flag_value("--keep-count")?
                .map(|value| {
                    value.parse::<usize>().map_err(|error| {
                        CoreError::validation(format!("invalid keep count: {error}"))
                    })
                })
                .transpose()?,
        })),
        "backup-list" => Ok(GameCommand::BackupList(GameBackupListArgs {
            backup_root: parser.required_flag_value("--backup-root")?,
        })),
        "backup-list-servers" => Ok(GameCommand::BackupListServers(GameBackupListServersArgs {
            backup_path: parser.required_flag_value("--backup-path")?,
        })),
        "backup-restore" => Ok(GameCommand::BackupRestore(GameBackupRestoreArgs {
            backup_path: parser.required_flag_value("--backup-path")?,
            server_name: parser.required_flag_value("--server-name")?,
            target_root: parser.required_flag_value("--target-root")?,
        })),
        other => Err(CoreError::validation(format!(
            "unknown game command: {other}"
        ))),
    }
}

fn parse_settings_command(parser: &mut ArgCursor) -> Result<SettingsCommand, CoreError> {
    let command = parser.required("settings command")?;
    match command.as_str() {
        "read" => Ok(SettingsCommand::Read(SettingsScopeArgs {
            scope: parser.required_flag_value("--scope")?,
        })),
        "write" => Ok(SettingsCommand::Write(SettingsWriteArgs {
            scope: parser.required_flag_value("--scope")?,
            json: parser.required_flag_value("--json")?,
        })),
        other => Err(CoreError::validation(format!(
            "unknown settings command: {other}"
        ))),
    }
}

fn parse_server_file_path_args(parser: &mut ArgCursor) -> Result<ServerFilePathArgs, CoreError> {
    let id = parser.required("server id")?;
    let path = parser.required_flag_value("--path")?;
    Ok(ServerFilePathArgs { id, path })
}

struct ArgCursor {
    args: Vec<String>,
    index: usize,
}

impl ArgCursor {
    fn new(args: Vec<String>) -> Self {
        Self { args, index: 0 }
    }

    fn peek(&self) -> Option<&String> {
        self.args.get(self.index)
    }

    fn next(&mut self) -> Option<String> {
        let value = self.args.get(self.index).cloned();
        if value.is_some() {
            self.index += 1;
        }
        value
    }

    fn required(&mut self, label: &str) -> Result<String, CoreError> {
        self.next()
            .ok_or_else(|| CoreError::validation(format!("missing {label}")))
    }

    fn required_value(&mut self, flag: &str) -> Result<String, CoreError> {
        self.next()
            .ok_or_else(|| CoreError::validation(format!("missing value for {flag}")))
    }

    fn required_flag_value(&mut self, flag: &str) -> Result<String, CoreError> {
        match self.next().as_deref() {
            Some(actual) if actual == flag => self.required_value(flag),
            Some(actual) => Err(CoreError::validation(format!(
                "expected {flag}, got {actual}"
            ))),
            None => Err(CoreError::validation(format!("missing {flag}"))),
        }
    }

    fn optional_flag_value(&mut self, flag: &str) -> Result<Option<String>, CoreError> {
        match self.peek().map(String::as_str) {
            Some(actual) if actual == flag => {
                self.next();
                Ok(Some(self.required_value(flag)?))
            }
            _ => Ok(None),
        }
    }

    fn finish(&self) -> Result<(), CoreError> {
        if let Some(extra) = self.peek() {
            return Err(CoreError::validation(format!(
                "unexpected argument: {extra}"
            )));
        }
        Ok(())
    }
}
