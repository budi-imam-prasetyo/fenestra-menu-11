//! Command-palette filtering.
//!
//! The palette matches command names and descriptions. A command is kept when
//! its name starts with the query or when the query is a subsequence of
//! `"<name> <description>"`. Prefix matches sort first; the original order is
//! preserved within each group, as with the previous stable JavaScript sort.
//!
//! Matching is case- and accent-insensitive, which is a deliberate
//! improvement over the old JavaScript (it compared raw characters).

use serde_json::Value;
use unicode_normalization::UnicodeNormalization;

/// Fold text for comparison: lower-case, decomposed and stripped of combining
/// marks. `É` and `e` therefore compare equal.
pub fn fold(text: &str) -> String {
    text.nfkd()
        .filter(|character| !is_combining_mark(*character))
        .collect::<String>()
        .to_lowercase()
}

fn is_combining_mark(character: char) -> bool {
    matches!(character as u32, 0x0300..=0x036F | 0x1AB0..=0x1AFF | 0x1DC0..=0x1DFF | 0x20D0..=0x20FF | 0xFE20..=0xFE2F)
}

/// Case- and accent-insensitive subsequence match.
pub fn fuzzy_match(haystack: &str, query: &str) -> bool {
    let haystack = fold(haystack);
    let query = fold(query);
    if query.is_empty() {
        return true;
    }
    let mut query_chars = query.chars();
    let Some(mut wanted) = query_chars.next() else {
        return true;
    };
    for character in haystack.chars() {
        if character == wanted {
            match query_chars.next() {
                Some(next) => wanted = next,
                None => return true,
            }
        }
    }
    false
}

fn command_matches(name: &str, description: &str, folded_query: &str) -> bool {
    let folded_name = fold(name);
    if folded_name.starts_with(folded_query) {
        return true;
    }
    let haystack = format!("{name} {description}");
    fuzzy_match(&haystack, folded_query)
}

/// Filter and rank a JSON array of command objects.
///
/// Objects without a string `name` are ignored. An empty or whitespace-only
/// query returns the array unchanged. The result is a JSON array so it can be
/// handed back to QML directly.
pub fn rank_commands(commands: &Value, query: &str) -> Value {
    let Some(array) = commands.as_array() else {
        return Value::Array(Vec::new());
    };
    let query = fold(query.trim());
    if query.is_empty() {
        return Value::Array(array.clone());
    }

    let mut prefix = Vec::new();
    let mut fuzzy = Vec::new();
    for command in array {
        let Some(name) = command.get("name").and_then(Value::as_str) else {
            continue;
        };
        let description = command
            .get("desc")
            .and_then(Value::as_str)
            .unwrap_or_default();
        if fold(name).starts_with(&query) {
            prefix.push(command.clone());
        } else if command_matches(name, description, &query) {
            fuzzy.push(command.clone());
        }
    }
    prefix.extend(fuzzy);
    Value::Array(prefix)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn fuzzy_match_is_a_subsequence() {
        assert!(fuzzy_match("lock the screen", "lts"));
        assert!(fuzzy_match("Lock the screen", "LTS"));
        assert!(!fuzzy_match("lock", "locks"));
        assert!(fuzzy_match("anything", ""));
    }

    #[test]
    fn folding_handles_accents_and_case() {
        assert_eq!(fold("Écran"), "ecran");
        assert!(fuzzy_match("Préférences système", "pref"));
    }

    #[test]
    fn rank_puts_prefix_matches_first_and_keeps_order() {
        let commands = json!([
            { "name": "settings", "desc": "Open System Settings" },
            { "name": "files", "desc": "Open file manager" },
            { "name": "set", "desc": "Set something" },
            { "name": "terminal", "desc": "Open a terminal" }
        ]);
        let ranked = rank_commands(&commands, "set");
        let names: Vec<&str> = ranked
            .as_array()
            .unwrap()
            .iter()
            .map(|command| command["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, vec!["settings", "set"]);
    }

    #[test]
    fn rank_matches_description_after_name() {
        let commands = json!([
            { "name": "terminal", "desc": "Open a terminal" },
            { "name": "files", "desc": "Open file manager" }
        ]);
        let ranked = rank_commands(&commands, "manager");
        assert_eq!(ranked.as_array().unwrap().len(), 1);
        assert_eq!(ranked[0]["name"], "files");
    }

    #[test]
    fn empty_query_returns_everything_and_malformed_input_is_empty() {
        let commands = json!([{ "name": "a" }, { "name": "b" }]);
        assert_eq!(rank_commands(&commands, "   "), commands);
        assert_eq!(rank_commands(&json!({}), "a"), json!([]));
        assert_eq!(
            rank_commands(&json!([{ "desc": "no name" }]), "a"),
            json!([])
        );
    }
}
