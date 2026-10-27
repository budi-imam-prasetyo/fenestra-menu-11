# Fenestra 1.5 design and responsiveness audit

## Before implementation

The initial working tree was clean at 1.4.2. MenuRepresentation.qml owns pinned pagination, folder data, category membership, view switching and the outer scroll viewport. ItemGridView.qml handles launching, keyboard navigation, drag/drop and virtualized grid rendering. ItemGridDelegate.qml and ItemGridDelegateColumns.qml duplicate visual and activation logic. CategoryTiles.qml flattens/sorts categories and exposes the category flyout. Footer.qml owns account/power UI; KdeConnectPanel.qml is intentionally retained. Core.qml dynamically loads RustBridge.qml and falls back when the CXX-Qt module is missing. Rust crates remain independent domain logic plus an optional QObject facade.

Confirmed issues: repeated light/dark literal colors and arbitrary radii; hand-built non-keyboard SectionButtons; category popup doubles as a view selector; screen-derived columns rather than content width; no deliberate empty pinned state; two app delegates create drop targets, edit buttons and labels even for alphabetical padding cells; model switches recreate delegates; category selection rescans the sorted catalog; CategoryTiles rebuilds on every launch-count assignment; a KDE Connect ComboBox implicit-width loop appears in runtime logs. The existing virtual viewport and catalog caches are retained.

Baseline, original 1.4.2, existing 8-switch offscreen Plasma applet harness: upper median 244 ms, maximum 401 ms. Whole-process /usr/bin/time reports 2.52 s user CPU, 0.30 s system CPU, 194404 KiB peak RSS. This includes applet initialization and is not desktop idle usage or physical click-to-photon latency. More comparable repeated measurements follow below.

## Documentation checked before changes

Context7 `/websites/doc_qt_io_qt-6` verified [GridView reuse and delegate pooling](https://doc.qt.io/qt-6/qml-qtquick-gridview.html), [Qt Quick performance](https://doc.qt.io/qt-6/qtquick-performance.html), [layout ownership](https://doc.qt.io/qt-6/qtquicklayouts-overview.html) and [Popup focus/Escape policies](https://doc.qt.io/qt-6/qml-qtquick-controls-popup.html). `/kdab/cxx-qt` verified the Threading/queue pattern for background results. No new worker or bridge migration is justified for the small pure UI computations; existing asynchronous executable sources remain asynchronous.

Initial native verification: cargo fmt, clippy with warnings denied, 48 Rust tests, CMake native build, 12 QML bridge cases, 3 fallback lifecycle cases and 3 relative-import lifecycle cases passed. The missing isolated KActivities database and offscreen shadow/platform warnings are environment limitations; the KDE Connect ComboBox width loop is an actual layout issue to fix without rearranging that panel.

## Implemented design and state changes

`Design.qml` is a lightweight local QML singleton (registered in `qmldir`), using Kirigami theme and font values for semantic colors and a 2/4/8/12/16-style spacing scale. Standard controls use a 6-unit corner radius and popups 8; circles remain circles for badges and avatars. `LauncherButton.qml` uses the existing Plasma ToolButton input/accessibility implementation with matched selected, hover, pressed, focus and disabled states. No icon library or runtime dependency was added. Interface actions follow the KDE icon theme; application icons retain their metadata identities with a safe executable fallback. Existing masked account/power artwork is preserved.

Pinned tiles and application rows share `AppDelegate.qml`; old delegate filenames remain thin compatible wrappers. Folder affordances are loaded only for folders. Launch dispatch is centralized to prevent mouse/key double activation, while existing Kicker triggers, context menus and favorite models remain authoritative. Pinned folders, ordering and drag/drop infrastructure stay in place. Empty pinned content has a compact instructional state rather than a reserved grid row. Columns follow content width and font/icon sizes, with an explicit scrollbar gutter. Search uses an immediate StackLayout page change instead of a horizontal slide. List/Grid/Categories have matched view controls; a separate bounded category popup reuses the same category entries and supports arrows, Enter, Escape and trigger-focus restoration.

`AppsView.qml` lazily retains bounded List and Grid viewports after first use. Switching mode preserves per-view scroll state and maps selected application IDs to the active presentation. Category changes detach the inactive filtered viewport, avoiding hidden delegate reconstruction. Catalog/folder/sort invalidation still refreshes the shared models; cached category rows avoid repeated metadata scans. Category tiles coalesce updates and defer their work while hidden. The launcher scan timer stops while closed; executable sources remain asynchronous and bounded by the existing timeout.

The `core: core` name shadowing in main.qml is fixed by naming the facade `nativeCore`, so the optional bridge actually reaches the popup. Rust APIs and crate versions remain unchanged. The launcher bridge calculations remain small operations; no unmeasured worker migration was introduced. The pre-existing contact filesystem reader was not profiled or moved because no paired-device/contact workload was available. A hidden recent-app label avoids unnecessary bridge JSON work when that optional section is disabled. KDE Connect keeps its panels, controls, layout and device workflows; its only panel change gives the existing device ComboBox nonrecursive implicit size constraints.

## Comparable performance results

Qt 6.12, real Plasma/Kicker applet objects, offscreen Qt software renderer, isolated XDG settings, same test binary and immutable 1.4.2 source snapshot. Each latency row has 20 samples, timed from the operation through event processing and `grabWindow()` rendering. The median is the upper middle sample and p95 the nearest-rank sample. These are warm interaction/controller-to-software-render timings, not physical desktop click-to-photon measurements or GPU frame-rate claims. First-use view materialization is included as one sample; warm cache results should not be interpreted as a cold-start guarantee. No visual tests were run concurrently with the final comparison.

| Installed catalog, ms | 1.4.2 median / p95 | 1.5.0 median / p95 |
|---|---:|---:|
| List/Grid switch | 191.86 / 240.45 | 4.69 / 7.17 |
| Category switch | 26.33 / 28.65 | 20.95 / 27.81 |
| Scroll event/render | 1.82 / 4.09 | 1.72 / 2.98 |
| Warm reopen first paint | 0.80 / 0.98 | 1.72 / 3.20 |
| Search input/clear first paint | 2.47 / 3.44 | 5.59 / 13.04 |

| Installed catalog plus 2,000 synthetic rows, ms | 1.4.2 median / p95 | 1.5.0 median / p95 |
|---|---:|---:|
| List/Grid switch | 191.60 / 235.99 | 3.44 / 4.33 |
| Category switch | 26.58 / 42.76 | 17.63 / 26.32 |
| Scroll event/render | 1.80 / 2.71 | 1.63 / 3.41 |
| Warm reopen first paint | 0.81 / 1.00 | 1.55 / 4.43 |
| Search input/clear first paint | 2.64 / 3.53 | 3.85 / 5.94 |

The synthetic rows stress list/grid rendering and cache bounds; category membership and search still use the installed Kicker catalog. This is not an installation/discovery benchmark for 2,000 desktop files. View switching improves substantially and category/scroll median latency improves. Reopening and search first-paint timings increase in this final run, though their reported p95 remains below 14 ms; no across-the-board speedup is claimed.

Whole-process installed-catalog peak RSS was 208976 → 197976 KiB; user CPU 4.41 → 2.27 s and system CPU 0.30 → 0.35 s across the complete benchmark. With synthetic rows, peak RSS was 210224 → 201620 KiB. A single 2-second closed-window sample used 10.141 → 9.561 ms CPU for the installed catalog, but the larger-row sample varied 10.892 → 28.530 ms. These short samples do not demonstrate an idle CPU improvement or absence of memory leaks. After the repeated operations, installed-catalog RSS was 200352 → 192084 KiB; retained view/model caches explain some process growth and remain bounded by visible delegates. Long-running session profiling remains a limitation.

Reproduce with `python3 tests/plasma/compare_performance.py /path/to/immutable-1.4.2`. Full logs are under `build/performance-validation/`. The script requires a Plasma user D-Bus session and uses only isolated test settings.

## Validation results

- `sh tests/run.sh`: 23 existing regression tests pass, including nested category membership, duplicates, category removal/reordering and power-management regressions.
- `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`: pass, 48 Rust tests.
- Native CMake build, 12 bridge QtTest totals, 3 fallback totals and 3 relative-import totals: pass through `scripts/test-native.sh`.
- 43 runtime assertions pass in each of seven QML-only scenarios: light, dark, compact width, expanded width, fractional 125%, long labels and larger fonts. Runtime logs contain zero ReferenceError, TypeError, binding-loop, invalid-assignment or component-creation failures. Offscreen shadow/platform warnings and the intentionally isolated KActivities database warning are environment limits.
- The native module was staged from the successful build; the complete 43-assertion runtime suite also passes with `NATIVE_AVAILABLE=true`. The QML-only matrix explicitly records `NATIVE_AVAILABLE=false`.
- Keyboard popup selection, Escape/focus restoration, all three view buttons, scroll/letter navigation, search/focus, new-app dots, empty/long/missing-icon cases, pinned add/remove/reorder/context menu, exactly-once pointer and keyboard launch dispatch, app-folder expand/collapse, and pinned-folder presence are exercised. Favorite/launch tests use model doubles so no user applications are launched. Real Kicker application/category/search models are used for browsing/search.
- Native drag gestures, launching real user applications, hardware GPU frame pacing and operations against a paired phone were not automated. Their existing dispatch paths were preserved/reviewed; KDE Connect layout was visually left unchanged. This report does not claim physical end-to-end device validation.
- QML syntax checks, `git diff --check`, metadata JSON and the translation template check pass. `msgfmt --check` reports only missing translator/date/language header fields already typical for the template. New strings use i18n and remain English fallbacks until translators supply entries.

Screenshots and complete logs: `build/design-validation/` and `build/menu-tests/`. Design/control files, delegate wrappers, bounded AppsView, category state/cache code, theme-only footer/compact presentation, three device-selector sizing properties, tests, metadata, template and documentation changed. No unrelated Rust domain, power-management or device-operation logic changed.

## Version and deployment

Compatible feature release 1.4.2 → 1.5.0; native APIs/crate versions stay 0.1.0. See CHANGELOG.md. No tag or public release is created. Package and panel verification are recorded after the final installation below.

## Bridge boundary microbenchmarks

The existing QML benchmark now includes both input JSON.stringify and output JSON.parse at the Rust boundary; it previously precomputed the input JSON despite claiming to include that cost. QtTest reports approximately 1.3 ms JavaScript vs 0.8 ms Rust plus serialization for a 200-command palette, and 0.014 ms JavaScript vs 0.12 ms Rust plus serialization for the legacy 60-document ordering API. The latter API is retained for compatibility and is not used by the launcher. Four benchmark functions pass; repeated calibration PASS lines are not additional unique tests. These are microbenchmarks with substantial run-to-run variance, not launcher latency figures. They support keeping trivial operations in QML rather than assuming every Rust call is faster.

## Installed package verification

The assembled native package was first installed to an isolated `/tmp` package root. All 43 runtime assertions pass from that packaged layout, with the real pointer click for pinned activation and keyboard activation each dispatched exactly once using model doubles. This validates the packaged relative singleton and native-module paths, not merely the source checkout.

Version 1.5.0 was then installed into the user's Plasma package directory and plasmashell restarted after its QML cache was moved aside. D-Bus confirms widget 240 remains on bottom panel 176 at index 1. Installed QML files byte-match the tested source, and `/proc/<plasmashell>/maps` confirms the installed `liborg_fenestra_menu11_core.so` is loaded in the actual Plasma process. The targeted startup log check reports no Fenestra component errors. The old package and panel configuration were backed up to `/tmp` before upgrading. No other panel widgets were removed, and no Git commit, tag or public release was created.
