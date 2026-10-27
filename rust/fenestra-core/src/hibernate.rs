//! Parsing of systemd-logind's `CanHibernate()` reply.
//!
//! The QML widget queries logind with `busctl` because KDE's
//! `SessionManagement.canHibernate` is cached at session start. The reply is a
//! string such as `s "yes"`; this module turns it into a stable, testable
//! capability decision.

/// A parsed `CanHibernate()` reply.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CanHibernate {
    /// Whether the reply was one of the statuses documented by logind.
    pub known: bool,
    /// Lower-case status extracted from the reply (empty when unknown).
    pub status: String,
}

const KNOWN_STATUSES: &[&str] = &[
    "yes",
    "no",
    "na",
    "challenge",
    "inhibited",
    "inhibitor-blocked",
    "inhibited-blocked",
    "challenge-inhibitor-blocked",
];

fn is_known_status(status: &str) -> bool {
    KNOWN_STATUSES.contains(&status)
}

/// Parse the output of `busctl call ... CanHibernate`.
///
/// Accepts both the normal `s "yes"` form and a bare string, which some D-Bus
/// tools print. An empty or unrecognised reply is reported as `known: false`
/// so the caller can fall back to KDE's cached answer.
pub fn parse_can_hibernate(output: &str) -> CanHibernate {
    let text = output.trim();
    if text.is_empty() {
        return CanHibernate {
            known: false,
            status: String::new(),
        };
    }

    if let Some(start) = text.find('"') {
        if let Some(end_rel) = text[start + 1..].find('"') {
            let status = text[start + 1..start + 1 + end_rel].trim().to_lowercase();
            return CanHibernate {
                known: is_known_status(&status),
                status,
            };
        }
    }

    // Bare string, as printed by some D-Bus tools. Strip a leading "s " and
    // one pair of surrounding quotes, matching the previous JavaScript.
    let mut bare = text;
    if let Some(rest) = bare.strip_prefix("s ") {
        bare = rest.trim_start();
    }
    let bare = bare
        .trim_matches(|c| c == '"' || c == '\'')
        .trim()
        .to_lowercase();
    CanHibernate {
        known: is_known_status(&bare),
        status: bare,
    }
}

/// Whether a known logind status means hibernation can be requested.
///
/// `challenge` requires Polkit authorization; the inhibited variants are
/// normally available but currently blocked by an inhibitor. All of them are
/// advertised, while `no` and `na` are not.
pub fn is_hibernate_available(status: &str) -> bool {
    matches!(
        status,
        "yes"
            | "challenge"
            | "inhibited"
            | "inhibitor-blocked"
            | "inhibited-blocked"
            | "challenge-inhibitor-blocked"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_quoted_statuses() {
        let cases = [
            ("s \"yes\"", true, "yes"),
            ("s \"challenge\"", true, "challenge"),
            ("s \"inhibited\"", true, "inhibited"),
            ("s \"inhibitor-blocked\"", true, "inhibitor-blocked"),
            ("s \"inhibited-blocked\"", true, "inhibited-blocked"),
            (
                "s \"challenge-inhibitor-blocked\"",
                true,
                "challenge-inhibitor-blocked",
            ),
            ("s \"no\"", true, "no"),
            ("s \"na\"", true, "na"),
            ("s \"maybe\"", false, "maybe"),
        ];
        for (raw, known, status) in cases {
            let parsed = parse_can_hibernate(raw);
            assert_eq!(parsed.known, known, "raw={raw}");
            assert_eq!(parsed.status, status, "raw={raw}");
        }
    }

    #[test]
    fn parses_bare_and_empty_statuses() {
        assert_eq!(
            parse_can_hibernate("yes"),
            CanHibernate {
                known: true,
                status: "yes".into()
            }
        );
        assert_eq!(
            parse_can_hibernate("maybe"),
            CanHibernate {
                known: false,
                status: "maybe".into()
            }
        );
        assert_eq!(
            parse_can_hibernate("   "),
            CanHibernate {
                known: false,
                status: String::new()
            }
        );
    }

    #[test]
    fn capability_matrix_matches_kde_and_systemd() {
        for status in [
            "yes",
            "challenge",
            "inhibited",
            "inhibitor-blocked",
            "inhibited-blocked",
            "challenge-inhibitor-blocked",
        ] {
            assert!(is_hibernate_available(status), "{status}");
        }
        for status in ["no", "na", "maybe", ""] {
            assert!(!is_hibernate_available(status), "{status}");
        }
    }
}
