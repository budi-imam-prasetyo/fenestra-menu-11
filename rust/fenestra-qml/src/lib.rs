//! Optional QML accelerator for Fenestra Menu 11.
//!
//! This crate is a CXX-Qt dynamic QML module named `Fenestra.Core`. It is
//! deliberately stateless: QML keeps the widget state, and each method takes
//! and returns plain values (mostly JSON strings). When the module cannot be
//! installed, `contents/ui/Core.qml` falls back to the JavaScript helpers, so
//! the widget keeps working without the native module.

use cxx_qt_lib::QString;
use fenestra_core::{commands, docs, fuzzy, hibernate, kdeconnect, launch, new_apps, vcard};
use serde_json::{json, Value};
use std::path::Path;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        type FenestraCore = super::FenestraCoreRust;

        #[qinvokable]
        fn version(self: &FenestraCore) -> QString;

        #[qinvokable]
        fn hibernate_parse(self: &FenestraCore, output: &QString) -> QString;
        #[qinvokable]
        fn hibernate_available(self: &FenestraCore, status: &QString) -> bool;

        #[qinvokable]
        fn launch_parse_counts(self: &FenestraCore, counts_json: &QString) -> QString;
        #[qinvokable]
        fn launch_record(
            self: &FenestraCore,
            counts_json: &QString,
            app_id: &QString,
            day: i32,
            hour: i32,
            now_ms: i64,
        ) -> QString;
        #[qinvokable]
        fn launch_score(
            self: &FenestraCore,
            counts_json: &QString,
            app_id: &QString,
            day: i32,
            hour: i32,
        ) -> i32;
        #[qinvokable]
        fn launch_has_workflow(
            self: &FenestraCore,
            counts_json: &QString,
            day: i32,
            hour: i32,
            threshold: i32,
        ) -> bool;
        #[qinvokable]
        fn launch_top_total(self: &FenestraCore, counts_json: &QString) -> QString;

        #[qinvokable]
        fn new_apps_diff(
            self: &FenestraCore,
            known_json: &QString,
            current_json: &QString,
        ) -> QString;
        #[qinvokable]
        fn new_apps_prune(
            self: &FenestraCore,
            stored_json: &QString,
            now_ms: i64,
            max_age_ms: i64,
        ) -> QString;
        #[qinvokable]
        fn new_apps_mark(
            self: &FenestraCore,
            stored_json: &QString,
            found_json: &QString,
            now_ms: i64,
        ) -> QString;
        #[qinvokable]
        fn new_apps_forget(self: &FenestraCore, stored_json: &QString, app_id: &QString)
            -> QString;
        #[qinvokable]
        fn new_apps_missing(
            self: &FenestraCore,
            pending_json: &QString,
            found_json: &QString,
        ) -> QString;

        #[qinvokable]
        fn fuzzy_rank(self: &FenestraCore, commands_json: &QString, query: &QString) -> QString;

        #[qinvokable]
        fn docs_rank(self: &FenestraCore, rows_json: &QString, now_seconds: i64) -> QString;
        #[qinvokable]
        fn docs_sort(self: &FenestraCore, rows_json: &QString) -> QString;

        #[qinvokable]
        fn kdeconnect_parse_devices(self: &FenestraCore, output: &QString) -> QString;
        #[qinvokable]
        fn kdeconnect_parse_contacts(self: &FenestraCore, output: &QString) -> QString;
        #[qinvokable]
        fn kdeconnect_filter_contacts(
            self: &FenestraCore,
            contacts_json: &QString,
            query: &QString,
            limit: i32,
        ) -> QString;
        #[qinvokable]
        fn kdeconnect_format_number(self: &FenestraCore, number: &QString) -> QString;
        #[qinvokable]
        fn kdeconnect_vcard_load(self: &FenestraCore, device: &QString) -> QString;

        #[qinvokable]
        fn vcard_load(self: &FenestraCore, directory: &QString) -> QString;

        #[qinvokable]
        fn shell_quote(self: &FenestraCore, value: &QString) -> QString;
        #[qinvokable]
        fn cmd_ring(self: &FenestraCore, device: &QString) -> QString;
        #[qinvokable]
        fn cmd_ping(self: &FenestraCore, device: &QString, message: &QString) -> QString;
        #[qinvokable]
        fn cmd_send_clipboard(self: &FenestraCore, device: &QString) -> QString;
        #[qinvokable]
        fn cmd_share_file(self: &FenestraCore, device: &QString, path: &QString) -> QString;
        #[qinvokable]
        fn cmd_share_url(self: &FenestraCore, device: &QString, url: &QString) -> QString;
        #[qinvokable]
        fn cmd_share_text(self: &FenestraCore, device: &QString, text: &QString) -> QString;
        #[qinvokable]
        fn cmd_send_sms(
            self: &FenestraCore,
            device: &QString,
            number: &QString,
            message: &QString,
        ) -> QString;
        #[qinvokable]
        fn cmd_dismiss_notification(self: &FenestraCore, device: &QString, id: &QString)
            -> QString;
        #[qinvokable]
        fn cmd_reply_notification(
            self: &FenestraCore,
            device: &QString,
            id: &QString,
            message: &QString,
        ) -> QString;
        #[qinvokable]
        fn cmd_mpris_action(self: &FenestraCore, device: &QString, action: &QString) -> QString;
        #[qinvokable]
        fn cmd_mpris_set(
            self: &FenestraCore,
            device: &QString,
            property: &QString,
            value: i32,
        ) -> QString;
        #[qinvokable]
        fn cmd_request_photo(self: &FenestraCore, device: &QString, file_url: &QString) -> QString;
        #[qinvokable]
        fn cmd_notify_send(
            self: &FenestraCore,
            title: &QString,
            body: &QString,
            icon: &QString,
        ) -> QString;
    }
}

#[derive(Default)]
pub struct FenestraCoreRust;

fn text(value: &QString) -> String {
    value.to_string()
}

fn string(value: &str) -> QString {
    QString::from(value)
}

fn encode(value: &Value) -> QString {
    string(&serde_json::to_string(value).unwrap_or_else(|_| "null".into()))
}

fn encode_or_empty<T: serde::Serialize>(value: &T) -> QString {
    string(&serde_json::to_string(value).unwrap_or_default())
}

fn parse_object(raw: &str) -> Value {
    serde_json::from_str(raw)
        .ok()
        .filter(Value::is_object)
        .unwrap_or_else(|| json!({}))
}

fn parse_array(raw: &str) -> Value {
    serde_json::from_str(raw)
        .ok()
        .filter(Value::is_array)
        .unwrap_or_else(|| json!([]))
}

fn command(result: fenestra_core::Result<String>) -> QString {
    string(&result.unwrap_or_default())
}

impl qobject::FenestraCore {
    fn version(&self) -> QString {
        string(env!("CARGO_PKG_VERSION"))
    }

    fn hibernate_parse(&self, output: &QString) -> QString {
        let parsed = hibernate::parse_can_hibernate(&text(output));
        encode(&json!({ "known": parsed.known, "status": parsed.status }))
    }

    fn hibernate_available(&self, status: &QString) -> bool {
        hibernate::is_hibernate_available(&text(status))
    }

    fn launch_parse_counts(&self, counts_json: &QString) -> QString {
        encode(&launch::parse_counts(&text(counts_json)))
    }

    fn launch_record(
        &self,
        counts_json: &QString,
        app_id: &QString,
        day: i32,
        hour: i32,
        now_ms: i64,
    ) -> QString {
        let counts = parse_object(&text(counts_json));
        let updated = launch::record_launch(
            &counts,
            &text(app_id),
            day.max(0) as u32,
            hour.max(0) as u32,
            now_ms,
        );
        encode(&updated)
    }

    fn launch_score(&self, counts_json: &QString, app_id: &QString, day: i32, hour: i32) -> i32 {
        let counts = parse_object(&text(counts_json));
        launch::workflow_score(
            &counts,
            &text(app_id),
            day.max(0) as u32,
            hour.max(0) as u32,
        ) as i32
    }

    fn launch_has_workflow(
        &self,
        counts_json: &QString,
        day: i32,
        hour: i32,
        threshold: i32,
    ) -> bool {
        let counts = parse_object(&text(counts_json));
        launch::has_workflow(
            &counts,
            day.max(0) as u32,
            hour.max(0) as u32,
            threshold.max(0) as u32,
        )
    }

    fn launch_top_total(&self, counts_json: &QString) -> QString {
        let counts = parse_object(&text(counts_json));
        string(&launch::top_total(&counts).to_string())
    }

    fn new_apps_diff(&self, known_json: &QString, current_json: &QString) -> QString {
        let known = new_apps::parse_list(&text(known_json));
        let current = new_apps::parse_list(&text(current_json));
        let difference = new_apps::diff(&known, &current);
        encode(&json!({
            "added": difference.added,
            "removed": difference.removed,
            "changed": difference.changed,
        }))
    }

    fn new_apps_prune(&self, stored_json: &QString, now_ms: i64, max_age_ms: i64) -> QString {
        let stored = new_apps::parse_map(&text(stored_json));
        encode(&new_apps::prune(&stored, now_ms, max_age_ms))
    }

    fn new_apps_mark(&self, stored_json: &QString, found_json: &QString, now_ms: i64) -> QString {
        let stored = new_apps::parse_map(&text(stored_json));
        let found = parse_array(&text(found_json));
        let found: Vec<new_apps::FoundApp> = found
            .as_array()
            .map(|array| {
                array
                    .iter()
                    .filter_map(|entry| {
                        Some(new_apps::FoundApp {
                            id: entry.get("id")?.as_str()?.to_owned(),
                            name: entry
                                .get("name")
                                .and_then(Value::as_str)
                                .unwrap_or_default()
                                .to_owned(),
                            category: entry
                                .get("cat")
                                .and_then(Value::as_str)
                                .unwrap_or_default()
                                .to_owned(),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        encode(&new_apps::mark_new(&stored, &found, now_ms))
    }

    fn new_apps_forget(&self, stored_json: &QString, app_id: &QString) -> QString {
        let stored = new_apps::parse_map(&text(stored_json));
        encode(&new_apps::forget(&stored, &text(app_id)))
    }

    fn new_apps_missing(&self, pending_json: &QString, found_json: &QString) -> QString {
        let pending = new_apps::parse_list(&text(pending_json));
        let found = new_apps::parse_list(&text(found_json));
        encode_or_empty(&new_apps::missing(&pending, &found))
    }

    fn fuzzy_rank(&self, commands_json: &QString, query: &QString) -> QString {
        let commands = parse_array(&text(commands_json));
        encode(&fuzzy::rank_commands(&commands, &text(query)))
    }

    fn docs_rank(&self, rows_json: &QString, now_seconds: i64) -> QString {
        let rows = parse_array(&text(rows_json));
        encode(&docs::build_lists(&rows, now_seconds))
    }

    fn docs_sort(&self, rows_json: &QString) -> QString {
        let rows = parse_array(&text(rows_json));
        encode_or_empty(&docs::sort_rows(&rows))
    }

    fn kdeconnect_parse_devices(&self, output: &QString) -> QString {
        encode_or_empty(&kdeconnect::parse_devices(&text(output)))
    }

    fn kdeconnect_parse_contacts(&self, output: &QString) -> QString {
        encode_or_empty(&kdeconnect::parse_contacts(&text(output)))
    }

    fn kdeconnect_filter_contacts(
        &self,
        contacts_json: &QString,
        query: &QString,
        limit: i32,
    ) -> QString {
        let contacts = parse_array(&text(contacts_json));
        encode(&kdeconnect::filter_contacts(
            &contacts,
            &text(query),
            limit.max(0) as usize,
        ))
    }

    fn kdeconnect_format_number(&self, number: &QString) -> QString {
        string(&kdeconnect::format_number(&text(number)))
    }

    fn kdeconnect_vcard_load(&self, device: &QString) -> QString {
        let device = text(device);
        if commands::validate_device(&device).is_err() {
            return string("[]");
        }
        let Some(home) = std::env::var_os("HOME") else {
            return string("[]");
        };
        let directory = Path::new(&home)
            .join(".local/share/kpeoplevcard")
            .join(format!("kdeconnect-{device}"));
        match vcard::load_directory(&directory) {
            Ok(contacts) => encode_or_empty(&contacts),
            Err(_) => string("[]"),
        }
    }

    fn vcard_load(&self, directory: &QString) -> QString {
        let path = text(directory);
        let path = if let Some(rest) = path.strip_prefix("file://") {
            rest
        } else {
            &path
        };
        match vcard::load_directory(Path::new(path)) {
            Ok(contacts) => encode_or_empty(&contacts),
            Err(_) => string("[]"),
        }
    }

    fn shell_quote(&self, value: &QString) -> QString {
        command(commands::shell_quote(&text(value)))
    }

    fn cmd_ring(&self, device: &QString) -> QString {
        command(commands::ring(&text(device)))
    }

    fn cmd_ping(&self, device: &QString, message: &QString) -> QString {
        command(commands::ping(&text(device), &text(message)))
    }

    fn cmd_send_clipboard(&self, device: &QString) -> QString {
        command(commands::send_clipboard(&text(device)))
    }

    fn cmd_share_file(&self, device: &QString, path: &QString) -> QString {
        command(commands::share_file(&text(device), &text(path)))
    }

    fn cmd_share_url(&self, device: &QString, url: &QString) -> QString {
        command(commands::share_url(&text(device), &text(url)))
    }

    fn cmd_share_text(&self, device: &QString, text_value: &QString) -> QString {
        command(commands::share_text(&text(device), &text(text_value)))
    }

    fn cmd_send_sms(&self, device: &QString, number: &QString, message: &QString) -> QString {
        command(commands::send_sms(
            &text(device),
            &text(number),
            &text(message),
        ))
    }

    fn cmd_dismiss_notification(&self, device: &QString, id: &QString) -> QString {
        command(commands::dismiss_notification(&text(device), &text(id)))
    }

    fn cmd_reply_notification(&self, device: &QString, id: &QString, message: &QString) -> QString {
        command(commands::reply_notification(
            &text(device),
            &text(id),
            &text(message),
        ))
    }

    fn cmd_mpris_action(&self, device: &QString, action: &QString) -> QString {
        command(commands::mpris_action(&text(device), &text(action)))
    }

    fn cmd_mpris_set(&self, device: &QString, property: &QString, value: i32) -> QString {
        command(commands::mpris_set(
            &text(device),
            &text(property),
            value as i64,
        ))
    }

    fn cmd_request_photo(&self, device: &QString, file_url: &QString) -> QString {
        command(commands::request_photo(&text(device), &text(file_url)))
    }

    fn cmd_notify_send(&self, title: &QString, body: &QString, icon: &QString) -> QString {
        command(commands::notify_send(
            &text(title),
            &text(body),
            &text(icon),
        ))
    }
}
