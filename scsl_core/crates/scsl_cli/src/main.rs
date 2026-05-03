mod app;
mod args;
mod json;
mod response;

use crate::app::{build_app, ensure_background_agent, run_command};
use crate::args::{Cli, Command};
use crate::json::{print_error, print_success};
use std::process::ExitCode;

fn main() -> ExitCode {
    let cli = match Cli::parse(std::env::args().skip(1).collect()) {
        Ok(cli) => cli,
        Err(error) => {
            print_error(&error);
            return ExitCode::from(2);
        }
    };

    if !matches!(cli.command, Command::Agent(_)) {
        let _ = ensure_background_agent(&cli);
    }

    let app = match build_app(&cli) {
        Ok(app) => app,
        Err(error) => {
            print_error(&error);
            return ExitCode::from(2);
        }
    };

    match run_command(&app, cli.command) {
        Ok(value) => {
            print_success(&value);
            ExitCode::SUCCESS
        }
        Err(error) => {
            print_error(&error);
            ExitCode::from(1)
        }
    }
}
