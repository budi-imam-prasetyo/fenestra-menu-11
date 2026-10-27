//! Parsing and filtering for the KDE Connect mobile panel.
//!
//! Device and contact listings are produced by shell commands in the QML
//! layer. Keeping the parsers here makes the tab-separated contract testable
//! and lets the panel avoid a second JavaScript implementation when the Rust
//! bridge is available. The Python vCard reader is superseded by the pure
//! `vcard` module.

use crate::fuzzy::fold;
use serde::Serialize;
use serde_json::{json, Value};

/// One KDE Connect device, matching the object shape used by the QML panel.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Device {
    pub id: String,
    pub name: String,
    #[serde(rename = "type")]
    pub device_type: String,
    pub reachable: bool,
    pub charge: i32,
    pub charging: bool,
    pub plugins: Vec<String>,
    pub net_type: String,
    pub net_strength: i32,
    pub m_title: String,
    pub m_artist: String,
    pub m_playing: bool,
    pub m_length: i64,
    pub m_pos: i64,
    pub m_seek: bool,
    pub m_volume: i32,
}

/// One phone contact with pre-computed search fields.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Contact {
    pub name: String,
    pub number: String,
    #[serde(rename = "type")]
    pub contact_type: String,
    pub key: String,
    pub digits: String,
}

fn field<'a>(fields: &'a [&'a str], index: usize) -> &'a str {
    fields.get(index).copied().unwrap_or_default()
}

fn parse_i32(value: &str, fallback: i32) -> i32 {
    value.trim().parse::<i32>().unwrap_or(fallback)
}

fn parse_i64(value: &str, fallback: i64) -> i64 {
    value.trim().parse::<i64>().unwrap_or(fallback)
}

/// Parse the tab-separated device listing printed by the panel's `readCmd`.
///
/// Lines with fewer than six fields or an empty device id are ignored. The
/// column order is the one documented by the QML command:
/// `id, name, type, reachable, charge, charging, plugins, netType,
/// netStrength, title, artist, playing, length, position, seek, volume`.
pub fn parse_devices(output: &str) -> Vec<Device> {
    let mut devices = Vec::new();
    for line in output.lines() {
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 6 || fields[0].is_empty() {
            continue;
        }
        let id = fields[0].to_owned();
        let name = match field(&fields, 1) {
            "" => id.clone(),
            name => name.to_owned(),
        };
        devices.push(Device {
            id,
            name,
            device_type: field(&fields, 2).to_owned(),
            reachable: field(&fields, 3) == "true",
            charge: parse_i32(field(&fields, 4), -1),
            charging: field(&fields, 5) == "true",
            plugins: field(&fields, 6)
                .split(',')
                .filter(|plugin| !plugin.is_empty())
                .map(str::to_owned)
                .collect(),
            net_type: field(&fields, 7).trim().to_owned(),
            net_strength: parse_i32(field(&fields, 8), -1),
            m_title: field(&fields, 9).trim().to_owned(),
            m_artist: field(&fields, 10).trim().to_owned(),
            m_playing: field(&fields, 11) == "true",
            m_length: parse_i64(field(&fields, 12), 0),
            m_pos: parse_i64(field(&fields, 13), 0),
            m_seek: field(&fields, 14) == "true",
            m_volume: parse_i32(field(&fields, 15), -1),
        });
    }
    devices
}

/// Parse the tab-separated contact listing.
pub fn parse_contacts(output: &str) -> Vec<Contact> {
    output
        .lines()
        .filter_map(|line| {
            let fields: Vec<&str> = line.split('\t').collect();
            if fields.len() < 2 || fields[0].is_empty() || fields[1].is_empty() {
                return None;
            }
            Some(Contact {
                name: fields[0].to_owned(),
                number: fields[1].to_owned(),
                contact_type: field(&fields, 2).to_owned(),
                key: fold(fields[0]),
                digits: digits_of(fields[1]),
            })
        })
        .collect()
}

/// Keep only ASCII digits.
pub fn digits_of(text: &str) -> String {
    text.chars().filter(char::is_ascii_digit).collect()
}

fn only_number_characters(text: &str) -> bool {
    text.chars()
        .all(|character| character.is_ascii_digit() || " +.-()".contains(character))
}

/// Filter contacts by name or number, with French `06…`/`+33 6…` equivalence.
///
/// `contacts` is the JSON array produced by [`parse_contacts`] or the panel.
/// The query is accent-insensitive. At most `limit` contacts are returned.
pub fn filter_contacts(contacts: &Value, query: &str, limit: usize) -> Value {
    let needle = fold(query).trim().to_owned();
    if needle.is_empty() || limit == 0 {
        return json!([]);
    }
    let digits = digits_of(&needle);
    let alternate = if let Some(rest) = digits.strip_prefix('0') {
        format!("33{rest}")
    } else if let Some(rest) = digits.strip_prefix("33") {
        format!("0{rest}")
    } else {
        String::new()
    };
    let number_query = digits.len() >= 3 && only_number_characters(&needle);

    let mut matches = Vec::new();
    if let Some(array) = contacts.as_array() {
        for contact in array {
            let Some(name) = contact.get("name").and_then(Value::as_str) else {
                continue;
            };
            let number = contact
                .get("number")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let key = contact
                .get("key")
                .and_then(Value::as_str)
                .map(str::to_owned)
                .unwrap_or_else(|| fold(name));
            let contact_digits = contact
                .get("digits")
                .and_then(Value::as_str)
                .map(str::to_owned)
                .unwrap_or_else(|| digits_of(number));

            let by_name = key.contains(&needle);
            let by_number = number_query
                && (contact_digits.contains(&digits)
                    || (!alternate.is_empty() && contact_digits.contains(&alternate)));
            if by_name || by_number {
                matches.push(json!({
                    "name": name,
                    "number": number,
                    "type": contact.get("type").and_then(Value::as_str).unwrap_or_default(),
                    "key": key,
                    "digits": contact_digits,
                }));
                if matches.len() >= limit {
                    break;
                }
            }
        }
    }
    Value::Array(matches)
}

/// Format a phone number the way the panel displays it.
///
/// French ten-digit numbers and `+33` numbers are grouped in pairs; anything
/// else is returned trimmed and unchanged.
pub fn format_number(number: &str) -> String {
    let raw = number.trim();
    let digits = digits_of(raw);
    if raw.starts_with('+') && digits.len() == 11 && digits.starts_with("33") {
        return format!("+33{} {}", &digits[2..3], pairs(&digits[3..]));
    }
    if digits.len() == 10 && digits.starts_with('0') {
        return pairs(&digits);
    }
    raw.to_owned()
}

fn pairs(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len() + text.len() / 2);
    for (index, character) in chars.iter().enumerate() {
        if index > 0 && index % 2 == 0 {
            out.push(' ');
        }
        out.push(*character);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const DEVICE_LINE: &str = "abc123\tPixel 8\tphone\ttrue\t87\ttrue\tkdeconnect_notifications,kdeconnect_mprisremote\t5G\t3\tSong\tArtist\ttrue\t240000\t12000\ttrue\t45";

    #[test]
    fn parses_device_rows() {
        let devices = parse_devices(DEVICE_LINE);
        assert_eq!(devices.len(), 1);
        let device = &devices[0];
        assert_eq!(device.id, "abc123");
        assert_eq!(device.name, "Pixel 8");
        assert_eq!(device.device_type, "phone");
        assert!(device.reachable);
        assert_eq!(device.charge, 87);
        assert!(device.charging);
        assert_eq!(
            device.plugins,
            vec!["kdeconnect_notifications", "kdeconnect_mprisremote"]
        );
        assert_eq!(device.net_type, "5G");
        assert_eq!(device.net_strength, 3);
        assert_eq!(device.m_title, "Song");
        assert_eq!(device.m_artist, "Artist");
        assert!(device.m_playing);
        assert_eq!(device.m_length, 240_000);
        assert_eq!(device.m_pos, 12_000);
        assert!(device.m_seek);
        assert_eq!(device.m_volume, 45);
    }

    #[test]
    fn device_defaults_match_the_qml_parser() {
        let line = "id\t\tphone\tfalse\t\tfalse\t\t\t\t\t\tfalse\t\t\tfalse\t";
        let device = parse_devices(line).pop().unwrap();
        assert_eq!(device.name, "id");
        assert_eq!(device.charge, -1);
        assert_eq!(device.net_strength, -1);
        assert_eq!(device.m_length, 0);
        assert_eq!(device.m_pos, 0);
        assert_eq!(device.m_volume, -1);
        assert!(device.plugins.is_empty());
    }

    #[test]
    fn ignores_short_or_empty_device_rows() {
        assert!(parse_devices("").is_empty());
        assert!(parse_devices("id\tname\tphone").is_empty());
        assert!(parse_devices("\tname\tphone\tfalse\t1\tfalse").is_empty());
    }

    #[test]
    fn parses_contacts_with_search_fields() {
        let contacts =
            parse_contacts("Élodie Martin\t06 35 93 98 41\tmobile\n\nBob\t+33612345678\n");
        assert_eq!(contacts.len(), 2);
        assert_eq!(contacts[0].key, "elodie martin");
        assert_eq!(contacts[0].digits, "0635939841");
        assert_eq!(contacts[1].contact_type, "");
    }

    #[test]
    fn filters_by_accent_insensitive_name() {
        let contacts = serde_json::to_value(parse_contacts(
            "Élodie Martin\t06 35 93 98 41\tmobile\nBob\t+33612345678\t\n",
        ))
        .unwrap();
        let found = filter_contacts(&contacts, "elod", 6);
        assert_eq!(found.as_array().unwrap().len(), 1);
        assert_eq!(found[0]["name"], "Élodie Martin");
    }

    #[test]
    fn filters_by_number_with_french_equivalence() {
        let contacts = serde_json::to_value(parse_contacts(
            "Alice\t06 12 34 56 78\tmobile\nBob\t07 00 00 00 00\t\n",
        ))
        .unwrap();
        let local = filter_contacts(&contacts, "0612", 6);
        assert_eq!(local.as_array().unwrap().len(), 1);
        assert_eq!(local[0]["name"], "Alice");
        let international = filter_contacts(&contacts, "+33 6 12 34 56 78", 6);
        assert_eq!(international.as_array().unwrap().len(), 1);
        assert_eq!(international[0]["name"], "Alice");
    }

    #[test]
    fn filter_respects_the_limit_and_empty_queries() {
        let contacts = serde_json::to_value(parse_contacts("A\t1\nA B\t2\nA C\t3\n")).unwrap();
        assert_eq!(
            filter_contacts(&contacts, "a", 2).as_array().unwrap().len(),
            2
        );
        assert_eq!(filter_contacts(&contacts, "", 6), json!([]));
        assert_eq!(filter_contacts(&contacts, "a", 0), json!([]));
    }

    #[test]
    fn formats_french_numbers() {
        assert_eq!(format_number("0635939841"), "06 35 93 98 41");
        assert_eq!(format_number("+33635939841"), "+336 35 93 98 41");
        assert_eq!(format_number("+33 6 35 93 98 41"), "+336 35 93 98 41");
        assert_eq!(format_number("123"), "123");
        assert_eq!(format_number("  +1 555 0100 "), "+1 555 0100");
    }
}
