//! Safe construction of the shell commands used by the widget.
//!
//! Every value that reaches a shell is either a fixed literal or passed
//! through [`shell_quote`]. Device identifiers, notification ids, MPRIS
//! actions and properties are additionally validated against narrow
//! allow-lists, so a compromised or unexpected D-Bus value cannot escape into
//! the command line. This mirrors the quoting already used by the QML panel,
//! with one implementation instead of several copies.

use crate::error::{CoreError, Result};

/// Quote one argument for a POSIX shell.
///
/// Returns an error for NUL bytes, which cannot appear in an argument.
pub fn shell_quote(value: &str) -> Result<String> {
    if value.contains('\0') {
        return Err(CoreError::Invalid("argument contains a NUL byte".into()));
    }
    Ok(format!("'{}'", value.replace('\'', "'\\''")))
}

/// Check that a KDE Connect device id is safe to embed in a path or command.
///
/// Device ids come from D-Bus and are used to build paths below
/// `/modules/kdeconnect/devices/`, so anything outside this narrow alphabet is
/// rejected.
pub fn validate_device(device: &str) -> Result<()> {
    let valid = !device.is_empty()
        && device.len() <= 128
        && device.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.')
        });
    if valid {
        Ok(())
    } else {
        Err(CoreError::Invalid("invalid KDE Connect device id".into()))
    }
}

fn validate_numeric_id(id: &str) -> Result<()> {
    if !id.is_empty() && id.chars().all(|character| character.is_ascii_digit()) {
        Ok(())
    } else {
        Err(CoreError::Invalid("invalid notification id".into()))
    }
}

fn cli(device: &str, arguments: &str) -> Result<String> {
    validate_device(device)?;
    Ok(format!(
        "kdeconnect-cli -d {} {arguments}",
        shell_quote(device)?
    ))
}

/// `kdeconnect-cli` invocation that rings the phone.
pub fn ring(device: &str) -> Result<String> {
    cli(device, "--ring")
}

/// `kdeconnect-cli` invocation that sends a ping message.
pub fn ping(device: &str, message: &str) -> Result<String> {
    cli(device, &format!("--ping-msg {}", shell_quote(message)?))
}

/// `kdeconnect-cli` invocation that sends the desktop clipboard.
pub fn send_clipboard(device: &str) -> Result<String> {
    cli(device, "--send-clipboard")
}

/// `kdeconnect-cli` invocation that shares a local file.
pub fn share_file(device: &str, path: &str) -> Result<String> {
    cli(device, &format!("--share {}", shell_quote(path)?))
}

/// `kdeconnect-cli` invocation that shares a URL as a link.
pub fn share_url(device: &str, url: &str) -> Result<String> {
    cli(device, &format!("--share {}", shell_quote(url)?))
}

/// `kdeconnect-cli` invocation that sends plain text.
pub fn share_text(device: &str, text: &str) -> Result<String> {
    cli(device, &format!("--share-text {}", shell_quote(text)?))
}

/// Send an SMS and echo the exit status for the panel's confirmation.
pub fn send_sms(device: &str, number: &str, message: &str) -> Result<String> {
    let command = cli(
        device,
        &format!(
            "--destination {} --send-sms {}",
            shell_quote(number)?,
            shell_quote(message)?
        ),
    )?;
    Ok(format!("sh -c {}; echo CODE=$?", shell_quote(&command)?))
}

fn qdbus(
    device: &str,
    suffix: &str,
    interface: &str,
    method: &str,
    argument: Option<&str>,
) -> Result<String> {
    validate_device(device)?;
    let path = format!("/modules/kdeconnect/devices/{device}/{suffix}");
    let mut call = format!(
        "\"$Q\" org.kde.kdeconnect {} {} {}",
        shell_quote(&path)?,
        interface,
        method
    );
    if let Some(argument) = argument {
        call.push(' ');
        call.push_str(&shell_quote(argument)?);
    }
    Ok(format!(
        "sh -c {}",
        shell_quote(&format!(
            "Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); {call}"
        ))?
    ))
}

/// Dismiss one notification.
pub fn dismiss_notification(device: &str, id: &str) -> Result<String> {
    validate_numeric_id(id)?;
    qdbus(
        device,
        &format!("notifications/{id}"),
        "org.kde.kdeconnect.device.notifications.notification",
        "dismiss",
        None,
    )
}

/// Reply to one notification.
pub fn reply_notification(device: &str, id: &str, message: &str) -> Result<String> {
    validate_numeric_id(id)?;
    qdbus(
        device,
        &format!("notifications/{id}"),
        "org.kde.kdeconnect.device.notifications.notification",
        "sendReply",
        Some(message),
    )
}

/// Send one MPRIS action (`PlayPause`, `Next` or `Previous`).
pub fn mpris_action(device: &str, action: &str) -> Result<String> {
    if !matches!(action, "PlayPause" | "Next" | "Previous") {
        return Err(CoreError::Invalid("unsupported MPRIS action".into()));
    }
    qdbus(
        device,
        "mprisremote",
        "org.kde.kdeconnect.device.mprisremote",
        "sendAction",
        Some(action),
    )
}

/// Set a numeric MPRIS property (`position` or `volume`).
pub fn mpris_set(device: &str, property: &str, value: i64) -> Result<String> {
    if !matches!(property, "position" | "volume") {
        return Err(CoreError::Invalid("unsupported MPRIS property".into()));
    }
    qdbus(
        device,
        "mprisremote",
        &format!("org.kde.kdeconnect.device.mprisremote.{property}"),
        &value.to_string(),
        None,
    )
}

/// Ask the phone to take a photo and save it at `file_url` (`file://…`).
pub fn request_photo(device: &str, file_url: &str) -> Result<String> {
    if !file_url.starts_with("file://") {
        return Err(CoreError::Invalid(
            "photo target must be a file:// URL".into(),
        ));
    }
    qdbus(
        device,
        "photo",
        "org.kde.kdeconnect.device.photo",
        "requestPhoto",
        Some(file_url),
    )
}

/// Desktop notification command with a `kdialog` fallback.
pub fn notify_send(title: &str, body: &str, icon: &str) -> Result<String> {
    Ok(format!(
        "(command -v notify-send >/dev/null 2>&1 && notify-send -a 'Menu Démarrer' -i {} -u low {} {}) || kdialog --title {} --passivepopup {} 8",
        shell_quote(icon)?,
        shell_quote(title)?,
        shell_quote(body)?,
        shell_quote(title)?,
        shell_quote(body)?
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quotes_plain_and_hostile_values() {
        assert_eq!(shell_quote("hello").unwrap(), "'hello'");
        assert_eq!(shell_quote("it's").unwrap(), "'it'\\''s'");
        assert_eq!(
            shell_quote("$(rm -rf /); echo pwned").unwrap(),
            "'$(rm -rf /); echo pwned'"
        );
        assert_eq!(shell_quote("a\nb").unwrap(), "'a\nb'");
        assert!(shell_quote("nul\0byte").is_err());
    }

    #[test]
    fn rejects_invalid_device_ids() {
        for device in ["", "../etc", "a b", "a;b", "$(id)", "é"] {
            assert!(ring(device).is_err(), "{device}");
        }
        assert!(ring("0123456789abcdef").is_ok());
        assert!(ring("device-1_2.3").is_ok());
    }

    #[test]
    fn builds_safe_cli_commands() {
        assert_eq!(ring("abc").unwrap(), "kdeconnect-cli -d 'abc' --ring");
        assert_eq!(
            ping("abc", "hi; rm -rf /").unwrap(),
            "kdeconnect-cli -d 'abc' --ping-msg 'hi; rm -rf /'"
        );
        assert_eq!(
            share_file("abc", "/tmp/a b.txt").unwrap(),
            "kdeconnect-cli -d 'abc' --share '/tmp/a b.txt'"
        );
        assert_eq!(
            share_text("abc", "it's").unwrap(),
            "kdeconnect-cli -d 'abc' --share-text 'it'\\''s'"
        );
    }

    #[test]
    fn sms_wraps_the_cli_and_reports_the_exit_code() {
        let command = send_sms("abc", "0612345678", "hello").unwrap();
        assert!(command.starts_with("sh -c 'kdeconnect-cli -d '\\''abc'\\''"));
        assert!(command.ends_with("; echo CODE=$?"));
        assert!(command.contains("--destination"));
        assert!(command.contains("0612345678"));
        assert!(command.contains("--send-sms"));
        assert!(command.contains("hello"));
    }

    #[test]
    fn notification_ids_must_be_numeric() {
        assert!(dismiss_notification("abc", "42").is_ok());
        assert!(dismiss_notification("abc", "4/2").is_err());
        assert!(dismiss_notification("abc", "").is_err());
        assert!(reply_notification("abc", "42", "hi").is_ok());
    }

    #[test]
    fn mpris_actions_and_properties_are_allow_listed() {
        assert!(mpris_action("abc", "Next").is_ok());
        assert!(mpris_action("abc", "Next; reboot").is_err());
        assert!(mpris_set("abc", "volume", 40).is_ok());
        assert!(mpris_set("abc", "volume; reboot", 40).is_err());
    }

    #[test]
    fn photo_target_must_be_a_file_url() {
        assert!(request_photo("abc", "file:///tmp/a.jpg").is_ok());
        assert!(request_photo("abc", "/tmp/a.jpg").is_err());
        assert!(request_photo("abc", "file:///tmp/a b.jpg").is_ok());
    }

    #[test]
    fn notification_builder_quotes_every_field() {
        let command = notify_send("New", "it's here", "app; rm -rf /").unwrap();
        assert!(command.contains("notify-send -a 'Menu Démarrer'"));
        assert!(command.contains("'it'\\''s here'"));
        assert!(command.contains("'app; rm -rf /'"));
        assert!(command.contains("kdialog --title 'New' --passivepopup 'it'\\''s here' 8"));
    }
}
