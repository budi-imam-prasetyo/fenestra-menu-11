//! Detection and bookkeeping for newly installed applications.
//!
//! The widget watches the XDG application directories and keeps two JSON
//! documents in its configuration: the list of `.desktop` file names seen on
//! the previous scan, and a map of applications flagged as new. This module
//! owns the set arithmetic, the seven-day expiry and the merge rules.

use serde_json::{json, Map, Value};
use std::collections::HashSet;

/// A new application discovered by the catalogue scan.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FoundApp {
    /// `.desktop` file name, used as the stable identifier.
    pub id: String,
    /// Display name shown in the notification and badge.
    pub name: String,
    /// Menu category the application was filed under.
    pub category: String,
}

/// Difference between the previously known files and the current scan.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Diff {
    /// Files present now but not in the previous scan, in scan order.
    pub added: Vec<String>,
    /// Files that disappeared since the previous scan, in previous order.
    pub removed: Vec<String>,
    /// Whether the sets differ at all.
    pub changed: bool,
}

/// Compare the stored list with a fresh directory listing.
pub fn diff(known: &[String], current: &[String]) -> Diff {
    let known_set: HashSet<&str> = known.iter().map(String::as_str).collect();
    let current_set: HashSet<&str> = current.iter().map(String::as_str).collect();

    let added: Vec<String> = current
        .iter()
        .filter(|id| !known_set.contains(id.as_str()))
        .cloned()
        .collect();
    let removed: Vec<String> = known
        .iter()
        .filter(|id| !current_set.contains(id.as_str()))
        .cloned()
        .collect();

    Diff {
        changed: !added.is_empty() || !removed.is_empty() || known.len() != current.len(),
        added,
        removed,
    }
}

/// Parse a stored string array, ignoring malformed entries.
pub fn parse_list(raw: &str) -> Vec<String> {
    serde_json::from_str::<Value>(raw)
        .ok()
        .and_then(|value| value.as_array().cloned())
        .map(|array| {
            array
                .into_iter()
                .filter_map(|item| item.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default()
}

/// Parse a stored new-app map, falling back to an empty object.
pub fn parse_map(raw: &str) -> Value {
    serde_json::from_str(raw)
        .ok()
        .filter(Value::is_object)
        .unwrap_or_else(|| Value::Object(Map::new()))
}

/// Drop entries older than `max_age_ms`.
///
/// Entries without a numeric `t` are dropped, matching the previous
/// JavaScript behaviour. The input is cloned rather than mutated.
pub fn prune(stored: &Value, now_ms: i64, max_age_ms: i64) -> Value {
    let mut kept = Map::new();
    if let Some(object) = stored.as_object() {
        for (id, entry) in object {
            let Some(timestamp) = entry.get("t").and_then(Value::as_i64) else {
                continue;
            };
            if now_ms.saturating_sub(timestamp) < max_age_ms {
                kept.insert(id.clone(), entry.clone());
            }
        }
    }
    Value::Object(kept)
}

/// Merge resolved applications into the new-app map.
///
/// Each entry is stored as `{ "t": now, "cat": category, "name": name }`.
pub fn mark_new(stored: &Value, found: &[FoundApp], now_ms: i64) -> Value {
    let mut root = stored.as_object().cloned().unwrap_or_default();
    for app in found {
        root.insert(
            app.id.clone(),
            json!({ "t": now_ms, "cat": app.category, "name": app.name }),
        );
    }
    Value::Object(root)
}

/// Remove one application from the new-app map.
pub fn forget(stored: &Value, app_id: &str) -> Value {
    let mut root = stored.as_object().cloned().unwrap_or_default();
    root.remove(app_id);
    Value::Object(root)
}

/// Return the pending identifiers that are not in `found_ids`, preserving
/// their original order. Used to retry while the catalogue catches up.
pub fn missing(pending: &[String], found_ids: &[String]) -> Vec<String> {
    let found: HashSet<&str> = found_ids.iter().map(String::as_str).collect();
    pending
        .iter()
        .filter(|id| !found.contains(id.as_str()))
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strings(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| (*value).to_owned()).collect()
    }

    #[test]
    fn diff_reports_additions_and_removals_in_order() {
        let result = diff(
            &strings(&["a.desktop", "b.desktop", "gone.desktop"]),
            &strings(&["new2.desktop", "a.desktop", "new1.desktop"]),
        );
        assert_eq!(result.added, strings(&["new2.desktop", "new1.desktop"]));
        assert_eq!(result.removed, strings(&["b.desktop", "gone.desktop"]));
        assert!(result.changed);
    }

    #[test]
    fn diff_is_stable_when_nothing_changed() {
        let list = strings(&["a.desktop", "b.desktop"]);
        let result = diff(&list, &list);
        assert!(!result.changed);
        assert!(result.added.is_empty());
        assert!(result.removed.is_empty());
    }

    #[test]
    fn first_scan_is_a_baseline_not_an_announcement() {
        // The caller handles the empty-known case separately; this documents
        // that every file would otherwise be reported as added.
        let result = diff(&[], &strings(&["a.desktop", "b.desktop"]));
        assert_eq!(result.added, strings(&["a.desktop", "b.desktop"]));
    }

    #[test]
    fn prune_expires_entries_after_seven_days() {
        let now = 10_000_000_000i64;
        let week = 7 * 86_400_000i64;
        let stored = json!({
            "fresh": { "t": now - 1, "cat": "A", "name": "Fresh" },
            "edge": { "t": now - week, "cat": "B", "name": "Edge" },
            "old": { "t": now - week - 1, "cat": "C", "name": "Old" },
            "bad": { "cat": "D" },
            "number": 3
        });
        let pruned = prune(&stored, now, week);
        assert!(pruned.get("fresh").is_some());
        assert!(pruned.get("edge").is_none());
        assert!(pruned.get("old").is_none());
        assert!(pruned.get("bad").is_none());
        assert!(pruned.get("number").is_none());
    }

    #[test]
    fn mark_new_merges_and_forget_removes() {
        let stored = json!({ "keep": { "t": 1, "cat": "A", "name": "Keep" } });
        let found = vec![FoundApp {
            id: "org.kde.dolphin.desktop".into(),
            name: "Dolphin".into(),
            category: "System".into(),
        }];
        let marked = mark_new(&stored, &found, 99);
        assert_eq!(marked["keep"]["name"], "Keep");
        assert_eq!(marked["org.kde.dolphin.desktop"]["t"], 99);
        assert_eq!(marked["org.kde.dolphin.desktop"]["cat"], "System");
        assert_eq!(marked["org.kde.dolphin.desktop"]["name"], "Dolphin");

        let forgotten = forget(&marked, "org.kde.dolphin.desktop");
        assert!(forgotten.get("org.kde.dolphin.desktop").is_none());
        assert!(forgotten.get("keep").is_some());
    }

    #[test]
    fn missing_preserves_pending_order() {
        assert_eq!(
            missing(&strings(&["a", "b", "c"]), &strings(&["b", "c", "d"])),
            strings(&["a"])
        );
    }

    #[test]
    fn parsers_are_forgiving() {
        assert_eq!(parse_list("[1,\"a\",null]"), strings(&["a"]));
        assert_eq!(parse_list("nope"), Vec::<String>::new());
        assert_eq!(parse_map("[]"), json!({}));
        assert_eq!(parse_map("{\"a\":1}"), json!({ "a": 1 }));
    }
}
