use std::error::Error;
use std::fmt::{self, Display, Formatter};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoreError {
    NotFound { resource: &'static str, id: String },
    Validation(String),
    Storage(String),
    Runtime(String),
    Unsupported(String),
}

impl CoreError {
    pub fn not_found(resource: &'static str, id: impl Into<String>) -> Self {
        Self::NotFound {
            resource,
            id: id.into(),
        }
    }

    pub fn validation(message: impl Into<String>) -> Self {
        Self::Validation(message.into())
    }

    pub fn storage(message: impl Into<String>) -> Self {
        Self::Storage(message.into())
    }

    pub fn runtime(message: impl Into<String>) -> Self {
        Self::Runtime(message.into())
    }

    pub fn unsupported(message: impl Into<String>) -> Self {
        Self::Unsupported(message.into())
    }
}

impl Display for CoreError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound { resource, id } => write!(f, "{resource} not found: {id}"),
            Self::Validation(message) => write!(f, "validation error: {message}"),
            Self::Storage(message) => write!(f, "storage error: {message}"),
            Self::Runtime(message) => write!(f, "runtime error: {message}"),
            Self::Unsupported(message) => write!(f, "unsupported: {message}"),
        }
    }
}

impl Error for CoreError {}
