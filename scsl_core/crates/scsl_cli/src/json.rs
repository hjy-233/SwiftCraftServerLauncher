use scsl_core::CoreError;
use serde::Serialize;

#[derive(Serialize)]
struct SuccessEnvelope<T> {
    ok: bool,
    data: T,
}

#[derive(Serialize)]
struct ErrorEnvelope<'a> {
    ok: bool,
    error: ErrorBody<'a>,
}

#[derive(Serialize)]
struct ErrorBody<'a> {
    message: &'a str,
}

pub fn print_success<T: Serialize>(value: &T) {
    let payload = SuccessEnvelope {
        ok: true,
        data: value,
    };
    println!("{}", to_json(&payload));
}

pub fn print_error(error: &CoreError) {
    let payload = ErrorEnvelope {
        ok: false,
        error: ErrorBody {
            message: &error.to_string(),
        },
    };
    eprintln!("{}", to_json(&payload));
}

fn to_json<T: Serialize>(value: &T) -> String {
    serde_json::to_string(value).unwrap_or_else(|error| {
        format!(
            "{{\"ok\":false,\"error\":{{\"message\":\"failed to encode json: {error}\"}}}}"
        )
    })
}
