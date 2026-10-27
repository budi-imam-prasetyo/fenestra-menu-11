//! Launch-history scoring and recording.
//!
//! The widget stores launch counts as a JSON object in its configuration:
//!
//! ```json
//! { "org.kde.dolphin": { "total": 4, "buckets": { "2-1": 3 }, "last": 1700000000000 } }
//! ```
//!
//! Older versions stored a plain number per application. Both shapes are
//! accepted, and recording a launch migrates the legacy shape in place. The
//! bucket key is `"<weekday>-<slot>"`, where weekday is 0 (Sunday) to 6 and
//! slot is 0 (night, 0–5 h), 1 (morning, 6–11 h), 2 (afternoon, 12–17 h) or
//! 3 (evening, 18–23 h).

use serde_json::{json, Map, Value};

/// Number of workflow buckets (four per day).
pub const SLOTS: u32 = 4;

/// Build the bucket key used by the widget for a local weekday and hour.
///
/// `day` is clamped to 0–6 and `hour` to 0–23 so a malformed clock reading
/// cannot create an out-of-range bucket.
pub fn bucket_key(day: u32, hour: u32) -> String {
    let day = day.min(6);
    let slot = match hour.min(23) {
        0..=5 => 0,
        6..=11 => 1,
        12..=17 => 2,
        _ => 3,
    };
    format!("{day}-{slot}")
}

/// Total launches recorded for one entry, accepting the legacy number shape.
pub fn entry_total(entry: &Value) -> u64 {
    match entry {
        Value::Number(number) => number.as_u64().unwrap_or(0),
        Value::Object(object) => object.get("total").and_then(Value::as_u64).unwrap_or(0),
        _ => 0,
    }
}

/// Total launches across every entry, used for the frequency fallback label.
pub fn top_total(counts: &Value) -> u64 {
    counts
        .as_object()
        .map(|object| object.values().map(entry_total).max().unwrap_or(0))
        .unwrap_or(0)
}

/// Whether any application has a workflow score of at least `threshold` for
/// the supplied weekday and hour.
pub fn has_workflow(counts: &Value, day: u32, hour: u32, threshold: u32) -> bool {
    counts
        .as_object()
        .map(|object| {
            object
                .keys()
                .any(|id| workflow_score(counts, id, day, hour) >= threshold)
        })
        .unwrap_or(false)
}

/// Score (0–10) for how strongly an application matches the current slot.
///
/// The score is `round(bucket_count / total * 10)`. A missing entry, a
/// non-object legacy value or a zero total scores zero.
pub fn workflow_score(counts: &Value, app_id: &str, day: u32, hour: u32) -> u32 {
    let Some(entry) = counts.get(app_id).and_then(Value::as_object) else {
        return 0;
    };
    let bucket = bucket_key(day, hour);
    let bucket_count = entry
        .get("buckets")
        .and_then(Value::as_object)
        .and_then(|buckets| buckets.get(&bucket))
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let total = entry.get("total").and_then(Value::as_u64).unwrap_or(0);
    if total == 0 {
        return 0;
    }
    ((bucket_count as f64 / total as f64) * 10.0).round() as u32
}

/// Record one launch and return the updated counts object.
///
/// The input is cloned, so callers can keep their previous state until the
/// result is accepted. Unknown top-level keys and per-entry keys are
/// preserved. A malformed input is treated as an empty object.
pub fn record_launch(counts: &Value, app_id: &str, day: u32, hour: u32, now_ms: i64) -> Value {
    let mut root = counts.as_object().cloned().unwrap_or_default();
    let bucket = bucket_key(day, hour);

    let mut entry = match root.get(app_id) {
        Some(Value::Object(object)) => object.clone(),
        Some(Value::Number(number)) => {
            let mut object = Map::new();
            object.insert("total".into(), Value::Number(number.clone()));
            object
        }
        _ => Map::new(),
    };

    let previous_total = entry.get("total").and_then(Value::as_u64).unwrap_or(0);
    let mut buckets = entry
        .get("buckets")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let previous_bucket = buckets.get(&bucket).and_then(Value::as_u64).unwrap_or(0);

    buckets.insert(bucket, json!(previous_bucket + 1));
    entry.insert("total".into(), json!(previous_total + 1));
    entry.insert("buckets".into(), Value::Object(buckets));
    entry.insert("last".into(), json!(now_ms));
    root.insert(app_id.to_owned(), Value::Object(entry));

    Value::Object(root)
}

/// Parse a stored counts document, falling back to an empty object.
pub fn parse_counts(raw: &str) -> Value {
    serde_json::from_str(raw)
        .ok()
        .filter(Value::is_object)
        .unwrap_or_else(|| Value::Object(Map::new()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bucket_keys_match_the_qml_slots() {
        assert_eq!(bucket_key(0, 0), "0-0");
        assert_eq!(bucket_key(3, 5), "3-0");
        assert_eq!(bucket_key(3, 6), "3-1");
        assert_eq!(bucket_key(3, 11), "3-1");
        assert_eq!(bucket_key(3, 12), "3-2");
        assert_eq!(bucket_key(3, 17), "3-2");
        assert_eq!(bucket_key(3, 18), "3-3");
        assert_eq!(bucket_key(3, 23), "3-3");
        assert_eq!(bucket_key(9, 99), "6-3");
    }

    #[test]
    fn records_launches_and_preserves_other_entries() {
        let initial = json!({
            "dolphin": { "total": 2, "buckets": { "1-1": 2 }, "custom": true },
            "konsole": 5
        });
        let updated = record_launch(&initial, "dolphin", 1, 7, 1_700_000_000_000);
        assert_eq!(updated["dolphin"]["total"], 3);
        assert_eq!(updated["dolphin"]["buckets"]["1-1"], 3);
        assert_eq!(updated["dolphin"]["custom"], true);
        assert_eq!(updated["dolphin"]["last"], 1_700_000_000_000i64);
        assert_eq!(updated["konsole"], 5);
    }

    #[test]
    fn migrates_legacy_number_entries() {
        let updated = record_launch(&json!({ "firefox": 4 }), "firefox", 2, 14, 42);
        assert_eq!(updated["firefox"]["total"], 5);
        assert_eq!(updated["firefox"]["buckets"]["2-2"], 1);
        assert_eq!(updated["firefox"]["last"], 42);
    }

    #[test]
    fn creates_missing_entries() {
        let updated = record_launch(&json!({}), "new", 6, 22, 7);
        assert_eq!(updated["new"]["total"], 1);
        assert_eq!(updated["new"]["buckets"]["6-3"], 1);
    }

    #[test]
    fn workflow_score_rounds_and_ignores_missing_data() {
        let counts = json!({
            "a": { "total": 3, "buckets": { "2-1": 2 } },
            "b": { "total": 0, "buckets": { "2-1": 9 } },
            "c": 9
        });
        assert_eq!(workflow_score(&counts, "a", 2, 9), 7);
        assert_eq!(workflow_score(&counts, "b", 2, 9), 0);
        assert_eq!(workflow_score(&counts, "c", 2, 9), 0);
        assert_eq!(workflow_score(&counts, "missing", 2, 9), 0);
        assert!(has_workflow(&counts, 2, 9, 6));
        assert!(!has_workflow(&counts, 2, 9, 8));
    }

    #[test]
    fn top_total_accepts_both_shapes() {
        assert_eq!(
            top_total(&json!({ "a": { "total": 3 }, "b": 8, "c": "x" })),
            8
        );
        assert_eq!(top_total(&json!([])), 0);
    }

    #[test]
    fn parse_counts_is_forgiving() {
        assert_eq!(parse_counts("not json"), json!({}));
        assert_eq!(parse_counts("[1,2]"), json!({}));
        assert_eq!(parse_counts("{\"a\":1}"), json!({ "a": 1 }));
    }
}
