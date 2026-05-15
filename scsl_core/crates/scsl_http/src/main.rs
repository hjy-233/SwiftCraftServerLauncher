mod app_state;
mod error;
mod handlers;
mod models;
mod router;
mod ws;

use app_state::AppState;
use models::ListenAddressArgs;
use router::build_router;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::Arc;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = parse_args()?;
    let state = Arc::new(AppState::for_current_platform()?);
    let app = build_router(state);

    let ip = args
        .host
        .parse::<IpAddr>()
        .unwrap_or(IpAddr::V4(Ipv4Addr::LOCALHOST));
    let address = SocketAddr::new(ip, args.port);
    let listener = tokio::net::TcpListener::bind(address).await?;
    println!("scsl-http listening on http://{address}");
    axum::serve(listener, app).await?;
    Ok(())
}

fn parse_args() -> Result<ListenAddressArgs, Box<dyn std::error::Error>> {
    let mut args = ListenAddressArgs {
        host: "127.0.0.1".to_string(),
        port: 31800,
    };
    let mut cursor = std::env::args().skip(1);
    while let Some(argument) = cursor.next() {
        match argument.as_str() {
            "--host" => {
                let value = cursor.next().ok_or("missing value for --host")?;
                args.host = value;
            }
            "--port" => {
                let value = cursor.next().ok_or("missing value for --port")?;
                args.port = value.parse::<u16>()?;
            }
            "--help" | "-h" => {
                print_help();
                std::process::exit(0);
            }
            other => {
                return Err(format!("unexpected argument: {other}").into());
            }
        }
    }
    Ok(args)
}

fn print_help() {
    println!("scsl-http [--host 127.0.0.1] [--port 31800]");
}
