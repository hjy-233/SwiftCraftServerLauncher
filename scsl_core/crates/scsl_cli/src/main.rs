use clap::{Args, Parser, Subcommand};
use serde_json::Value;
use scsl_core::{
    CoreError, ForgeInstallerPlanner, InMemoryRuntime, InMemoryStore, LocalServerRuntime, LogQuery,
    ResourceDownloadPlanner, ResourceType, ScslCore, ServerDownloadPlanner, ServerInstance,
    ServerInventory, ServerInventoryAnalyzer, ServerLaunchPlanner, ServerRuntimePort, ServerStatus,
    ServerStorePort, ServerType, LocalServerFileEntry,
    SwiftDataServerStore, sample_local_server,
};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::PathBuf;
use std::process::ExitCode;

fn main() -> ExitCode {
    let cli = Cli::parse();
    let app = match build_app(&cli) {
        Ok(app) => app,
        Err(error) => {
            eprintln!("{error}");
            return ExitCode::from(2);
        }
    };

    match cli.command {
        Command::Server { command } => match run_server_command(&app, command) {
            Ok(()) => ExitCode::SUCCESS,
            Err(error) => {
                eprintln!("{error}");
                ExitCode::from(1)
            }
        },
        Command::Resource { command } => match run_resource_command(&app, command) {
            Ok(()) => ExitCode::SUCCESS,
            Err(error) => {
                eprintln!("{error}");
                ExitCode::from(1)
            }
        },
    }
}

fn run_server_command(app: &CliApp, command: ServerCommand) -> Result<(), CoreError> {
    match command {
        ServerCommand::List => {
            for server in app.inventory()?.servers {
                println!(
                    "{}\t{}\t{}\t{}",
                    server.id,
                    server.name,
                    server.game_version,
                    display_server_type(server.server_type)
                );
            }
            Ok(())
        }
        ServerCommand::Show(args) => {
            let server = app.require_inventory_server(&args.id)?;
            print_server(&server);
            Ok(())
        }
        ServerCommand::LaunchCommand(args) => {
            let server = app.require_inventory_server(&args.id)?;
            let plan = app.launch_planner.plan(&server)?;
            println!("{}", plan.launch_command);
            Ok(())
        }
        ServerCommand::Corrupted => {
            for name in app.inventory()?.corrupted_server_names {
                println!("{name}");
            }
            Ok(())
        }
        ServerCommand::VerifyJar(args) => {
            let server = app.require_inventory_server(&args.id)?;
            if app.download_planner.verify_local_jar_integrity(&server) {
                println!("ok");
            } else {
                println!("failed");
            }
            Ok(())
        }
        ServerCommand::ForgeInstallPlan(args) => {
            let server = app.require_inventory_server(&args.id)?;
            match app.forge_installer.install_plan(&server)? {
                Some(plan) => {
                    println!("server: {}", plan.server_id);
                    println!("directory: {}", plan.server_dir.display());
                    println!("installer: {}", plan.installer_jar.display());
                    println!("command: {}", plan.command_line().join(" "));
                }
                None => println!("not needed"),
            }
            Ok(())
        }
        ServerCommand::Status(args) => {
            let status = app.core.server_status(&args.id)?;
            println!("{}", display_status(status));
            Ok(())
        }
        ServerCommand::Start(args) => {
            let status = app.core.start_server(&args.id)?;
            println!("{}", display_status(status));
            Ok(())
        }
        ServerCommand::Stop(args) => {
            let status = app.core.stop_server(&args.id)?;
            println!("{}", display_status(status));
            Ok(())
        }
        ServerCommand::Restart(args) => {
            let status = app.core.restart_server(&args.id)?;
            println!("{}", display_status(status));
            Ok(())
        }
        ServerCommand::Logs(args) => {
            let snapshot = app.core.server_logs(&args.id, LogQuery::tail(args.lines))?;
            println!("status: {}", display_status(snapshot.status));
            for line in snapshot.lines {
                println!("{line}");
            }
            Ok(())
        }
        ServerCommand::Send(args) => {
            app.send_direct_command(&args.id, &args.command)?;
            println!("ok");
            Ok(())
        }
        ServerCommand::Interrupt(args) => {
            app.interrupt_server(&args.id, args.force)?;
            println!("ok");
            Ok(())
        }
        ServerCommand::Rcon(args) => {
            let output = app.execute_local_rcon(&args.id, &args.command)?;
            if !output.is_empty() {
                println!("{output}");
            }
            Ok(())
        }
        ServerCommand::Properties { command } => match command {
            ServerPropertiesCommand::Read(args) => {
                let properties = app.read_server_properties(&args.id)?;
                println!(
                    "{}",
                    serde_json::to_string(&properties)
                        .map_err(|error| CoreError::runtime(format!("failed to encode properties: {error}")))?
                );
                Ok(())
            }
            ServerPropertiesCommand::Write(args) => {
                let payload: Value = serde_json::from_str(&args.json)
                    .map_err(|error| CoreError::validation(format!("invalid properties json: {error}")))?;
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
                println!("ok");
                Ok(())
            }
        },
        ServerCommand::Files { command } => match command {
            ServerFilesCommand::List(args) => {
                let entries = app.list_server_files(&args.id)?;
                println!(
                    "{}",
                    serde_json::to_string(&entries)
                        .map_err(|error| CoreError::runtime(format!("failed to encode file list: {error}")))?
                );
                Ok(())
            }
            ServerFilesCommand::Read(args) => {
                let content = app.read_server_file_text(&args.id, &args.path)?;
                print!("{content}");
                Ok(())
            }
            ServerFilesCommand::Write(args) => {
                let mut content = String::new();
                std::io::stdin()
                    .read_to_string(&mut content)
                    .map_err(|error| CoreError::runtime(format!("failed to read stdin: {error}")))?;
                app.write_server_file_text(&args.id, &args.path, &content)?;
                println!("ok");
                Ok(())
            }
            ServerFilesCommand::Mkdir(args) => {
                app.create_server_directory(&args.id, &args.path)?;
                println!("ok");
                Ok(())
            }
            ServerFilesCommand::Touch(args) => {
                app.create_server_file(&args.id, &args.path)?;
                println!("ok");
                Ok(())
            }
            ServerFilesCommand::Move(args) => {
                app.move_server_path(&args.id, &args.from, &args.to)?;
                println!("ok");
                Ok(())
            }
            ServerFilesCommand::Delete(args) => {
                app.remove_server_path(&args.id, &args.path)?;
                println!("ok");
                Ok(())
            }
            ServerFilesCommand::Import(args) => {
                app.import_server_path(&args.id, &args.source, &args.directory)?;
                println!("ok");
                Ok(())
            }
        },
        ServerCommand::Schedules { command } => match command {
            ServerSchedulesCommand::Read(args) => {
                let schedules = app.read_schedules_json(&args.id)?;
                print!("{schedules}");
                Ok(())
            }
            ServerSchedulesCommand::Write(args) => {
                let mut schedules = String::new();
                std::io::stdin()
                    .read_to_string(&mut schedules)
                    .map_err(|error| CoreError::runtime(format!("failed to read stdin: {error}")))?;
                app.write_schedules_json(&args.id, &schedules)?;
                println!("ok");
                Ok(())
            }
        },
    }
}

fn run_resource_command(app: &CliApp, command: ResourceCommand) -> Result<(), CoreError> {
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
            println!("{}", path.display());
            Ok(())
        }
    }
}

fn print_server(server: &ServerInstance) {
    println!("id: {}", server.id);
    println!("name: {}", server.name);
    println!("directory: {}", server.directory_name);
    println!("type: {}", display_server_type(server.server_type));
    println!("game version: {}", server.game_version);
    if !server.loader_version.is_empty() {
        println!("loader version: {}", server.loader_version);
    }
    println!("jar: {}", server.server_jar);
    println!("node: {}", server.node_id);
    println!("console: {}", display_console_mode(server.console_mode));
    if !server.java_path.is_empty() {
        println!("java: {}", server.java_path);
    }
    if server.xms > 0 || server.xmx > 0 {
        println!("memory: {}M / {}M", server.xms, server.xmx);
    }
    if !server.launch_command.trim().is_empty() {
        println!("launch command: {}", server.launch_command);
    }
}

fn display_status(status: ServerStatus) -> &'static str {
    match status {
        ServerStatus::Stopped => "stopped",
        ServerStatus::Running => "running",
        ServerStatus::Starting => "starting",
        ServerStatus::Stopping => "stopping",
    }
}

fn display_console_mode(console_mode: scsl_core::ConsoleMode) -> &'static str {
    match console_mode {
        scsl_core::ConsoleMode::Direct => "direct",
        scsl_core::ConsoleMode::Rcon => "rcon",
    }
}

fn display_server_type(server_type: ServerType) -> &'static str {
    match server_type {
        ServerType::Vanilla => "vanilla",
        ServerType::Fabric => "fabric",
        ServerType::Forge => "forge",
        ServerType::Paper => "paper",
        ServerType::Custom => "custom",
    }
}

fn build_app(cli: &Cli) -> Result<CliApp, CoreError> {
    if cli.demo {
        return Ok(build_demo_app());
    }

    let default_store = SwiftDataServerStore::for_current_platform()?;
    let db_path = cli
        .db
        .clone()
        .unwrap_or_else(|| default_store.db_path().to_path_buf());
    let working_path = cli
        .working_path
        .clone()
        .unwrap_or_else(|| default_store.working_path().to_string());

    Ok(CliApp {
        core: ScslCore::new(
            CliServerStore::SwiftData(SwiftDataServerStore::new(db_path, working_path.clone())),
            CliServerRuntime::Local(LocalServerRuntime::new(working_path.clone())),
        ),
        inventory_analyzer: ServerInventoryAnalyzer::new(PathBuf::from(&working_path).join("servers")),
        download_planner: ServerDownloadPlanner::new(&working_path),
        resource_download_planner: ResourceDownloadPlanner::new(&working_path),
        forge_installer: ForgeInstallerPlanner::new(&working_path),
        launch_planner: ServerLaunchPlanner::new(working_path),
    })
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

struct CliApp {
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

    fn read_server_properties(
        &self,
        id: &str,
    ) -> Result<std::collections::BTreeMap<String, String>, CoreError> {
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
        properties: &std::collections::BTreeMap<String, String>,
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
            CliServerRuntime::Local(runtime) => runtime.write_server_properties(&server, properties),
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
            CliServerRuntime::Local(runtime) => runtime.read_server_file_text(&server, relative_path),
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
            CliServerRuntime::Local(runtime) => runtime.create_server_directory(&server, relative_path),
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
            CliServerRuntime::Local(runtime) => runtime.import_server_path(&server, source, directory),
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
            CliServerRuntime::Local(runtime) => runtime.write_schedules_json(&server, schedules_json),
        }
    }
}

enum CliServerStore {
    Demo(InMemoryStore),
    SwiftData(SwiftDataServerStore),
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

#[derive(Parser)]
#[command(
    name = "scsl",
    version,
    about = "Swift Craft Server Launcher CLI prototype"
)]
struct Cli {
    #[arg(long, value_name = "PATH", global = true)]
    db: Option<PathBuf>,
    #[arg(long, value_name = "PATH", global = true)]
    working_path: Option<String>,
    #[arg(
        long,
        global = true,
        help = "Use the built-in demo data instead of the Swift app database"
    )]
    demo: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    Server {
        #[command(subcommand)]
        command: ServerCommand,
    },
    Resource {
        #[command(subcommand)]
        command: ResourceCommand,
    },
}

#[derive(Subcommand)]
enum ServerCommand {
    List,
    Show(ServerIdArgs),
    #[command(name = "command")]
    LaunchCommand(ServerIdArgs),
    Corrupted,
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
    Properties {
        #[command(subcommand)]
        command: ServerPropertiesCommand,
    },
    Files {
        #[command(subcommand)]
        command: ServerFilesCommand,
    },
    Schedules {
        #[command(subcommand)]
        command: ServerSchedulesCommand,
    },
}

#[derive(Subcommand)]
enum ServerPropertiesCommand {
    Read(ServerIdArgs),
    Write(ServerPropertiesWriteArgs),
}

#[derive(Subcommand)]
enum ServerFilesCommand {
    List(ServerIdArgs),
    Read(ServerFilePathArgs),
    Write(ServerFilePathArgs),
    Mkdir(ServerFilePathArgs),
    Touch(ServerFilePathArgs),
    Move(ServerFileMoveArgs),
    Delete(ServerFilePathArgs),
    Import(ServerFileImportArgs),
}

#[derive(Subcommand)]
enum ServerSchedulesCommand {
    Read(ServerIdArgs),
    Write(ServerIdArgs),
}

#[derive(Subcommand)]
enum ResourceCommand {
    Download(ResourceDownloadArgs),
}

#[derive(Args)]
struct ServerIdArgs {
    id: String,
}

#[derive(Args)]
struct ServerLogsArgs {
    id: String,
    #[arg(long, short = 'n', default_value_t = 50)]
    lines: usize,
}

#[derive(Args)]
struct ServerSendArgs {
    id: String,
    command: String,
}

#[derive(Args)]
struct ServerInterruptArgs {
    id: String,
    #[arg(long)]
    force: bool,
}

#[derive(Args)]
struct ServerPropertiesWriteArgs {
    id: String,
    #[arg(long)]
    json: String,
}

#[derive(Args)]
struct ServerFilePathArgs {
    id: String,
    #[arg(long)]
    path: String,
}

#[derive(Args)]
struct ServerFileMoveArgs {
    id: String,
    #[arg(long)]
    from: String,
    #[arg(long)]
    to: String,
}

#[derive(Args)]
struct ServerFileImportArgs {
    id: String,
    #[arg(long)]
    source: PathBuf,
    #[arg(long, default_value = "")]
    directory: String,
}

#[derive(Args)]
struct ResourceDownloadArgs {
    #[arg(long)]
    game_name: String,
    #[arg(long, value_name = "TYPE")]
    resource_type: String,
    #[arg(long)]
    url: String,
    #[arg(long)]
    file_name: String,
    #[arg(long)]
    sha1: Option<String>,
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
        .map_err(|error| CoreError::runtime(format!("failed to configure rcon timeout: {error}")))?;
    stream
        .set_write_timeout(Some(std::time::Duration::from_secs(6)))
        .map_err(|error| CoreError::runtime(format!("failed to configure rcon timeout: {error}")))?;

    send_rcon_packet(&mut stream, 101, 3, password)?;
    let auth = receive_rcon_packet(&mut stream)?;
    if auth.request_id != 101 {
        return Err(CoreError::validation("rcon authentication failed"));
    }

    send_rcon_packet(&mut stream, 102, 2, command)?;
    let response = receive_rcon_packet(&mut stream)?;
    if response.request_id != 102 {
        return Err(CoreError::runtime("rcon command failed"));
    }
    Ok(response.body)
}

fn send_rcon_packet(
    stream: &mut TcpStream,
    request_id: i32,
    packet_type: i32,
    body: &str,
) -> Result<(), CoreError> {
    let body_bytes = body.as_bytes();
    let size = (4 + 4 + body_bytes.len() + 2) as i32;
    let mut buffer = Vec::with_capacity(size as usize + 4);
    buffer.extend_from_slice(&size.to_le_bytes());
    buffer.extend_from_slice(&request_id.to_le_bytes());
    buffer.extend_from_slice(&packet_type.to_le_bytes());
    buffer.extend_from_slice(body_bytes);
    buffer.extend_from_slice(&[0, 0]);
    stream
        .write_all(&buffer)
        .map_err(|error| CoreError::runtime(format!("failed to write rcon packet: {error}")))
}

fn receive_rcon_packet(stream: &mut TcpStream) -> Result<RconPacket, CoreError> {
    let mut size_bytes = [0_u8; 4];
    stream
        .read_exact(&mut size_bytes)
        .map_err(|error| CoreError::runtime(format!("failed to read rcon header: {error}")))?;
    let size = i32::from_le_bytes(size_bytes) as usize;
    let mut content = vec![0_u8; size];
    stream
        .read_exact(&mut content)
        .map_err(|error| CoreError::runtime(format!("failed to read rcon body: {error}")))?;
    let request_id = i32::from_le_bytes(content[0..4].try_into().unwrap_or([0; 4]));
    let _packet_type = i32::from_le_bytes(content[4..8].try_into().unwrap_or([0; 4]));
    let body = String::from_utf8_lossy(&content[8..content.len().saturating_sub(2)]).to_string();
    Ok(RconPacket {
        request_id,
        body,
    })
}

struct RconPacket {
    request_id: i32,
    body: String,
}
