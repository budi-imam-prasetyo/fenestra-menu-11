//! Fenestra Menu 11 — pure Rust domain core.
//!
//! This crate deliberately has no Qt or Plasma dependency. It contains the
//! business logic that is exposed to QML by the `fenestra-qml` crate, so every
//! rule can be unit-tested without a running Plasma session.

pub mod commands;
pub mod docs;
pub mod error;
pub mod fuzzy;
pub mod hibernate;
pub mod kdeconnect;
pub mod launch;
pub mod new_apps;
pub mod vcard;

pub use error::{CoreError, Result};
