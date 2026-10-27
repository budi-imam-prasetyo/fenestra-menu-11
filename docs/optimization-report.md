# Fenestra Menu 11 1.4.0 implementation report

## Implementation summary

The recent-document Recommended section and its full-page view were removed. A horizontally scrollable, theme-aware category filter now sits between pinned apps and application browsing. Categories come from the existing KDE Kicker category tree; an app appearing in several categories is deduplicated within each filtered view. Pinned apps, optional recently launched apps, folders, app launching, KDE Connect, power controls, file search and the Rust fallback boundary remain in place.

## Responsiveness findings and changes

The old startup path triggered `refreshDocDates()`, which launched a Python process to query the activity database and stat up to 60 file paths. Removing the document feature removes that process from popup opening. Opening the popup also reparsed unchanged folder and launch-history JSON, causing the all-app combo model to rebuild when the all-app folder array was reassigned. Raw configuration values are now checked before parsing or reassigning those models. Category changes keep the unfiltered combo model intact and fill only the selected category's model. The new-app desktop-entry scan previously ran every 10 seconds after an initial 5-second delay; it now runs once per minute, prevents overlap and disconnects a stalled scan after 15 seconds. This reduces routine background work while potentially delaying new-app notifications by up to one minute.

The existing all-app grid is still the repository's tall `GridView` within an outer `Flickable`. Its rendering cost remains a candidate for measurement in a real Plasma session before attempting a coordinated virtual-scrolling change. The native bridge remains synchronous for its existing small pure computations; no threading change was justified by the evidence here.

## Category behavior and design

The default filter is All apps. Kicker supplies category labels and desktop-entry membership, including application visibility rules. Empty categories are omitted from the toolbar. Category buttons have theme-based selected, hover and keyboard-focus states; the row scrolls horizontally at narrow widths. Left and Right move between filters, Enter/Space select one, and Down moves into the application grid. An empty result displays a message. Search uses the existing global runner and temporarily replaces browsing; clearing it returns to the selected category without resetting the filter. When Kicker refreshes, the selected category is matched by its displayed label and falls back to All apps if it disappears. In Categories tile view, selecting a filter displays its applications in a list.

## Files and architecture

`contents/ui/MenuRepresentation.qml` owns the category state and selected model; `contents/ui/main.qml` disables recent documents in Kicker. `contents/ui/ItemGridView.qml`, `contents/ui/ConfigGeneral.qml`, `contents/config/main.xml` and the removed `RecentDocDelegate.qml` retire the unused document UI. `README.md`, `metadata.json`, `translate/template.pot` and this documentation reflect version 1.4.0. The Rust `docs_rank` API remains for native binary compatibility but has no UI caller; no new dependencies or runtime requirements were added.

## Tests and build results

- Baseline uploaded archive: `tests/run.sh` passed 21 tests.
- Updated tree: `tests/run.sh` passed 23 tests, including category membership, nested duplicates, multi-category apps, an empty category, catalog reordering, removed categories and removal of the recent-document UI path. The JavaScript test executes the actual QML functions against Kicker-like model doubles under Node.js.
- JSON and XML parsed; translation template passed `msgfmt --check` with existing header metadata warnings; shell scripts passed `sh -n`; the original archive passed `unzip -t`.
- `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, `qmltestrunner`, `qmllint`, `kpackagetool6`, Plasma integration and dark/light visual inspection could not run because Cargo, Qt 6 and Plasma tools and a KDE session are unavailable in this environment. These checks are still required on a Plasma 6 workstation before installation or release.

## Performance evidence and limits

No trustworthy before/after latency, CPU or memory figures were obtained. The provided environment has no Plasma session or Qt QML profiler. Existing timings in `docs/native-core.md` were produced on another machine for an earlier implementation and are not evidence of a 1.4.0 speedup. To measure the change, use QML Profiler on the same Plasma 6 session and app catalog before and after; sample popup opening, first usable input, click-to-paint, search, category selection, launch initiation and idle resource usage. Report sample count, median and p95. Do not substitute the Node model-double test for UI latency.

## Compatibility and lifecycle audit

The application source remains Kicker, so desktop-entry visibility filtering and launch dispatch follow the same model as before. The category filter works without Rust. The scan timer has a single active source and a timeout. No new subprocess, daemon, thread or dependency was introduced. The archived source lacks `.git`, so branch state and commit history could not be verified; file changes were compared against the extracted original. No commit, tag, installation or release was made.

## Version

`metadata.json` moves from 1.3.0 to 1.4.0: the new public category feature is a compatible SemVer minor release. The retired Recommended UI is an intentional feature replacement; existing recent-app and search functions stay available.
