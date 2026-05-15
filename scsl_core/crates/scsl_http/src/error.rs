use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use scsl_core::CoreError;
use serde::Serialize;

#[derive(Debug)]
pub struct HttpError(pub CoreError);

impl From<CoreError> for HttpError {
    fn from(value: CoreError) -> Self {
        Self(value)
    }
}

impl IntoResponse for HttpError {
    fn into_response(self) -> Response {
        let status = match self.0 {
            CoreError::Validation { .. } => StatusCode::BAD_REQUEST,
            CoreError::NotFound { .. } => StatusCode::NOT_FOUND,
            CoreError::Unsupported { .. } => StatusCode::NOT_IMPLEMENTED,
            CoreError::Storage { .. } => StatusCode::INTERNAL_SERVER_ERROR,
            CoreError::Runtime { .. } => StatusCode::INTERNAL_SERVER_ERROR,
        };
        let body = Json(ErrorPayload {
            error: self.0.to_string(),
        });
        (status, body).into_response()
    }
}

#[derive(Serialize)]
struct ErrorPayload {
    error: String,
}
