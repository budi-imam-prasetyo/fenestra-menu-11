//! Minimal vCard reader for KDE Connect contacts.
//!
//! KDE Connect synchronises contacts as vCard files under
//! `~/.local/share/kpeoplevcard/kdeconnect-<device>/`. The panel only needs
//! `FN` and `TEL`, but real files use folded lines and quoted-printable
//! values, so both are handled. This replaces the previous inline Python
//! reader and removes the `python3` dependency for contacts.

use crate::error::{CoreError, Result};
use crate::fuzzy::fold;
use serde::Serialize;
use std::fs;
use std::path::Path;

/// A contact extracted from a vCard file.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct VCardContact {
    pub name: String,
    pub number: String,
    #[serde(rename = "type")]
    pub contact_type: String,
    pub key: String,
    pub digits: String,
}

fn decode_quoted_printable(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'=' {
            if index + 1 < bytes.len() && bytes[index + 1] == b'\n' {
                index += 2;
                continue;
            }
            if index + 2 < bytes.len() {
                let hex = &value[index + 1..index + 3];
                if let Ok(byte) = u8::from_str_radix(hex, 16) {
                    out.push(byte);
                    index += 3;
                    continue;
                }
            }
        }
        out.push(bytes[index]);
        index += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Unfold continuation lines and join quoted-printable soft breaks.
fn unfold(raw: &str) -> Vec<String> {
    let normalized = raw.replace("\r\n", "\n").replace('\r', "\n");
    let mut lines: Vec<String> = Vec::new();
    for line in normalized.split('\n') {
        if let Some(last) = lines.last_mut() {
            if line.starts_with(' ') || line.starts_with('\t') {
                last.push_str(&line[1..]);
                continue;
            }
            let header = last.split(':').next().unwrap_or_default().to_uppercase();
            if last.ends_with('=') && header.contains("QUOTED-PRINTABLE") {
                last.pop();
                last.push_str(line);
                continue;
            }
        }
        lines.push(line.to_owned());
    }
    lines
}

fn property_type(params: &str) -> String {
    let upper = params.to_uppercase();
    if upper.contains("CELL") {
        "mobile".into()
    } else if upper.contains("HOME") {
        "domicile".into()
    } else if upper.contains("WORK") {
        "travail".into()
    } else {
        String::new()
    }
}

/// Parse one or more vCard documents.
///
/// Duplicate `(name, number, type)` triples are removed and the result is
/// sorted by case-folded name, matching the previous Python reader.
pub fn parse_vcards<'a, I>(documents: I) -> Vec<VCardContact>
where
    I: IntoIterator<Item = &'a str>,
{
    let mut contacts = Vec::new();
    for raw in documents {
        let lines = unfold(raw);
        let mut name = String::new();
        let mut numbers: Vec<(String, String)> = Vec::new();

        for line in &lines {
            let Some((key, value)) = line.split_once(':') else {
                continue;
            };
            let mut parts = key.split(';');
            let property = parts.next().unwrap_or_default().to_uppercase();
            let params = parts.collect::<Vec<_>>().join(";");
            let value = if params.to_uppercase().contains("QUOTED-PRINTABLE") {
                decode_quoted_printable(value)
            } else {
                value.to_owned()
            };
            match property.as_str() {
                "FN" => name = value.trim().to_owned(),
                "TEL" => {
                    let number = value.trim().to_owned();
                    if !number.is_empty() {
                        numbers.push((number, property_type(&params)));
                    }
                }
                _ => {}
            }
        }

        let name = name.replace('\t', " ");
        if name.is_empty() {
            continue;
        }
        for (number, contact_type) in numbers {
            contacts.push(VCardContact {
                key: fold(&name),
                digits: crate::kdeconnect::digits_of(&number),
                name: name.clone(),
                number,
                contact_type,
            });
        }
    }

    contacts.sort_by(|left, right| {
        left.name
            .to_lowercase()
            .cmp(&right.name.to_lowercase())
            .then_with(|| left.number.cmp(&right.number))
    });
    contacts.dedup_by(|left, right| {
        left.name == right.name
            && left.number == right.number
            && left.contact_type == right.contact_type
    });
    contacts
}

/// Read every `*.vcf` file directly inside `directory`.
///
/// A missing directory yields an empty list, because KDE Connect creates it
/// only after the contacts plugin has synchronised at least once. Other I/O
/// failures are reported so the caller can log them.
pub fn load_directory(directory: &Path) -> Result<Vec<VCardContact>> {
    let entries = match fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(CoreError::Io(error)),
    };

    let mut documents = Vec::new();
    for entry in entries {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|extension| extension.to_str()) != Some("vcf") {
            continue;
        }
        documents.push(fs::read_to_string(path)?);
    }
    Ok(parse_vcards(documents.iter().map(String::as_str)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_basic_vcard_with_number_types() {
        let card = "BEGIN:VCARD\nVERSION:3.0\nFN:Alice Martin\nTEL;TYPE=CELL:0612345678\nTEL;TYPE=HOME:+33123456789\nEND:VCARD";
        let contacts = parse_vcards([card]);
        assert_eq!(contacts.len(), 2);
        assert_eq!(contacts[0].name, "Alice Martin");
        let mobile = contacts
            .iter()
            .find(|contact| contact.contact_type == "mobile")
            .unwrap();
        let home = contacts
            .iter()
            .find(|contact| contact.contact_type == "domicile")
            .unwrap();
        assert_eq!(mobile.key, "alice martin");
        assert_eq!(mobile.digits, "0612345678");
        assert_eq!(home.digits, "33123456789");
    }

    #[test]
    fn unfolds_continuation_lines() {
        let card = "FN:Élodie\n  Martin\nTEL:06 35 93 98 41\n";
        let contacts = parse_vcards([card]);
        assert_eq!(contacts[0].name, "Élodie Martin");
    }

    #[test]
    fn decodes_quoted_printable_values() {
        let card = "FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:Andr=C3=A9\nTEL;TYPE=WORK:0102\n";
        let contacts = parse_vcards([card]);
        assert_eq!(contacts[0].name, "André");
        assert_eq!(contacts[0].contact_type, "travail");
    }

    #[test]
    fn joins_quoted_printable_soft_breaks() {
        let card = "FN;ENCODING=QUOTED-PRINTABLE:Long=\nName\nTEL:123\n";
        let contacts = parse_vcards([card]);
        assert_eq!(contacts[0].name, "LongName");
    }

    #[test]
    fn ignores_cards_without_name_or_number() {
        let contacts = parse_vcards([
            "BEGIN:VCARD\nTEL:123\nEND:VCARD",
            "BEGIN:VCARD\nFN:No Number\nEND:VCARD",
            "BEGIN:VCARD\nFN:Empty\nTEL:\nEND:VCARD",
        ]);
        assert!(contacts.is_empty());
    }

    #[test]
    fn sorts_and_deduplicates() {
        let contacts = parse_vcards(["FN:zoe\nTEL:2\n", "FN:Alice\nTEL:1\n", "FN:Alice\nTEL:1\n"]);
        assert_eq!(contacts.len(), 2);
        assert_eq!(contacts[0].name, "Alice");
        assert_eq!(contacts[1].name, "zoe");
    }

    #[test]
    fn missing_directory_is_empty() {
        let path = std::env::temp_dir().join("fenestra-no-such-vcard-dir");
        assert!(load_directory(&path).unwrap().is_empty());
    }

    #[test]
    fn loads_vcf_files_only() {
        let directory = std::env::temp_dir().join(format!(
            "fenestra-vcards-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&directory).unwrap();
        fs::write(directory.join("a.vcf"), "FN:Alice\nTEL:1\n").unwrap();
        fs::write(directory.join("ignore.txt"), "FN:Ignored\nTEL:2\n").unwrap();
        let contacts = load_directory(&directory).unwrap();
        assert_eq!(contacts.len(), 1);
        assert_eq!(contacts[0].name, "Alice");
        fs::remove_dir_all(&directory).unwrap();
    }
}
