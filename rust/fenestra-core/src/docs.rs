//! Ordering for the "Recommended" documents section.
//!
//! The QML side reads each document's last-use time (falling back to its
//! modification time) and hands the rows to this module. Rows are ordered by
//! timestamp descending, then by their original model row ascending so ties
//! stay stable. The first six rows feed the visible page; rows from the last
//! seven days feed the "this week" list.
//!
//! Both lists and the full display order are computed here so the QML layer
//! does not need to duplicate the limits or the week window.

use serde_json::{json, Value};

/// Number of rows shown in the limited recommendations page.
pub const TOP_LIMIT: usize = 6;
/// Length of the "recent" window, in seconds.
pub const WEEK_SECONDS: i64 = 7 * 86_400;

/// Parse `{ "i": modelRow, "t": epochSeconds }` rows into
/// `(modelRow, timestamp, inputPosition)` triples, ignoring rows without a
/// numeric `i`.
fn parse_rows(rows: &Value) -> Vec<(usize, i64, usize)> {
    let mut parsed: Vec<(usize, i64, usize)> = rows
        .as_array()
        .map(|array| {
            array
                .iter()
                .enumerate()
                .filter_map(|(position, row)| {
                    let index = row.get("i").and_then(Value::as_u64)? as usize;
                    let timestamp = row.get("t").and_then(Value::as_i64).unwrap_or(0);
                    Some((index, timestamp, position))
                })
                .collect()
        })
        .unwrap_or_default();

    parsed.sort_by(|left, right| {
        right
            .1
            .cmp(&left.1)
            .then_with(|| left.0.cmp(&right.0))
            .then_with(|| left.2.cmp(&right.2))
    });
    parsed
}

/// Build the recommendation lists for a given time.
///
/// `rows` is `[{ "i": modelRow, "url": url, "t": epochSeconds }]`. Returns
/// `{ "top": [modelRow...], "week": [modelRow...], "order": [modelRow...] }`.
/// `top` is the first [`TOP_LIMIT`] rows, `week` only contains rows with a
/// positive timestamp inside the last [`WEEK_SECONDS`], and `order` is the
/// full display order. A missing or non-positive `t` sorts last but keeps
/// model order.
pub fn build_lists(rows: &Value, now_seconds: i64) -> Value {
    let entries = parse_rows(rows);

    let top: Vec<usize> = entries
        .iter()
        .take(TOP_LIMIT)
        .map(|(index, _, _)| *index)
        .collect();
    let week: Vec<usize> = entries
        .iter()
        .filter(|(_, timestamp, _)| {
            *timestamp > 0 && now_seconds.saturating_sub(*timestamp) < WEEK_SECONDS
        })
        .map(|(index, _, _)| *index)
        .collect();
    let order: Vec<usize> = entries.iter().map(|(index, _, _)| *index).collect();

    json!({ "top": top, "week": week, "order": order })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn sorts_newest_first_and_ties_by_model_row() {
        let rows = json!([
            { "i": 0, "url": "file:///a", "t": 100 },
            { "i": 1, "url": "file:///b", "t": 300 },
            { "i": 2, "url": "file:///c", "t": 300 },
            { "i": 3, "url": "file:///d", "t": 0 }
        ]);
        assert_eq!(build_lists(&rows, 1000)["order"], json!([1, 2, 0, 3]));
    }

    #[test]
    fn missing_timestamps_sort_last_in_model_order() {
        let rows = json!([
            { "i": 5, "url": "file:///a" },
            { "i": 2, "url": "file:///b", "t": 10 },
            { "i": 4, "url": "file:///c" }
        ]);
        assert_eq!(build_lists(&rows, 1000)["order"], json!([2, 4, 5]));
    }

    #[test]
    fn lists_limit_the_page_and_the_week_window() {
        let now = 1_000_000i64;
        let rows = json!([
            { "i": 0, "t": now - 10 },
            { "i": 1, "t": now - 20 },
            { "i": 2, "t": now - 30 },
            { "i": 3, "t": now - 40 },
            { "i": 4, "t": now - 50 },
            { "i": 5, "t": now - 60 },
            { "i": 6, "t": now - 70 },
            { "i": 7, "t": now - WEEK_SECONDS },
            { "i": 8, "t": 0 }
        ]);
        let lists = build_lists(&rows, now);
        assert_eq!(lists["top"], json!([0, 1, 2, 3, 4, 5]));
        assert_eq!(lists["week"], json!([0, 1, 2, 3, 4, 5, 6]));
        assert_eq!(lists["order"], json!([0, 1, 2, 3, 4, 5, 6, 7, 8]));
    }

    #[test]
    fn malformed_input_is_empty() {
        assert_eq!(
            build_lists(&json!({}), 0),
            json!({ "top": [], "week": [], "order": [] })
        );
        assert_eq!(
            build_lists(&json!([]), 0),
            json!({ "top": [], "week": [], "order": [] })
        );
    }
}
