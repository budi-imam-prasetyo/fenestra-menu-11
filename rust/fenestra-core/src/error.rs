//! Error types used at the Rust domain boundary.
//!
//! Parsing of user configuration is intentionally forgiving (malformed data
//! falls back to an empty/default value). These errors are reserved for
//! operations where silently continuing would hide a real failure, such as
//! reading a directory of vCards or building a system command.

/// Errors returned by the Fenestra core.
#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    /// A JSON document could not be decoded.
    #[error("invalid JSON: {0}")]
    Json(#[from] serde_json::Error),

    /// A filesystem operation failed.
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    /// An argument failed validation before being used in a system operation.
    #[error("invalid input: {0}")]
    Invalid(String),
}

/// Convenience result type for the Fenestra core.
pub type Result<T> = std::result::Result<T, CoreError>;
