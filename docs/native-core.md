# Native core (optional Rust accelerator)

Fenestra Menu 11 is still a QML Plasma applet. It can load a small CXX-Qt module
that evaluates the rules which used to be duplicated in QML/JavaScript. The
module is **optional**: a package without it behaves exactly as before and the
widget logs one informational line at start-up.

```
main.qml / MenuRepresentation.qml / KdeConnectPanel.qml / Footer.qml
        │  property var core
        ▼
contents/ui/Core.qml            (facade; every method has a JS fallback)
        │  Qt.createComponent("RustBridge.qml")
        ▼
contents/ui/RustBridge.qml      (only file importing the native module)
        │  import "core/org/fenestra/menu11/core"
        ▼
CXX-Qt module org.fenestra.menu11.core
        │  singleton FenestraCore (stateless, QString/JSON API)
        ▼
rust/fenestra-core              (pure Rust, no Qt; unit-tested)
```

## Why an in-process module

Two alternatives were evaluated:

* **Separate Rust service on D-Bus.** Adds a process, a protocol, serialisation
  and lifecycle handling for logic that is a few pure functions. It would also
  make the optional fallback harder to keep in sync. Rejected.
* **Keeping the logic in QML/JavaScript.** No build step, but the rules were
  spread across `MenuRepresentation.qml`, `KdeConnectPanel.qml`,
  `code/power.js` and a Python helper, and only the Python parser had any
  test coverage. Kept as the fallback, not as the primary implementation.

CXX-Qt 0.10 was selected because it is the maintained Rust/Qt bridge that
supports Qt 6 QML modules (dynamic plugin, `qml_singleton`) without a separate
Qt application. The generated module was verified against the Qt 6.12 engine
used by Plasma 6.8: it loads from `build/native/qml` with `-import`, from a
widget-relative directory (the layout used in the package), and from the
installed package under `contents/ui/core/org/fenestra/menu11/core/`.

The applet's metadata, package id (`org.fenestra.menu11`), configuration schema
and entry points are unchanged.

## Responsibilities

| Rust module | Rule | QML caller |
| --- | --- | --- |
| `fuzzy` | accent/case-insensitive command-palette ranking (prefix matches first) | `MenuRepresentation.qml` (`filteredCmds`) |
| `docs` | legacy recommended-document ranking API retained for binary compatibility; unused by the launcher since 1.4.0 | no current UI caller |
| `hibernate` | parse `org.freedesktop.login1.Manager.CanHibernate` and decide availability | `HibernateProbe.qml` |
| `launch` | launch counters: legacy migration, workflow buckets, scores, totals | `MenuRepresentation.qml` (`recordLaunch`, `contextLabel`) |
| `new_apps` | new-application set arithmetic, seven-day expiry, merge/forget | `MenuRepresentation.qml` |
| `kdeconnect` | tab-separated device/contact listings, phone-number formatting | `KdeConnectPanel.qml` |
| `vcard` | vCard reading for SMS contacts (replaces the inline Python reader) | `KdeConnectPanel.qml` |
| `commands` | POSIX-quoted KDE Connect and `qdbus` command construction, input validation | `KdeConnectPanel.qml`, `Logic.qml`, `MenuRepresentation.qml` |

QML keeps: layout, animations, focus and keyboard navigation, Plasma
integration, model construction, the KDE Connect polling/pipelines, and the
JavaScript fallback for every migrated rule.

## Cross-language API

`FenestraCore` is a QML singleton with no fields. Every method is synchronous
and side-effect free except `kdeconnect_vcard_load`, which reads the KDE
Connect contact directory. Values cross the boundary as `QString`, `bool`,
`i32`, `i64` or JSON text; there are no exposed Rust objects, so there is no
ownership to transfer.

| Method | Input | Output |
| --- | --- | --- |
| `version()` | — | crate version |
| `hibernate_parse(output)` | logind reply | `{known, status}` |
| `hibernate_available(status)` | status | `bool` |
| `launch_parse_counts(json)` | stored config | counts object |
| `launch_record(json, id, day, hour, nowMs)` | stored config + clock | updated object |
| `launch_has_workflow(json, day, hour, threshold)` | stored config | `bool` |
| `launch_top_total(json)` | stored config | `i32` |
| `new_apps_diff(known, current)` | `.desktop` lists | `{added, removed, changed}` |
| `new_apps_prune(json, nowMs, maxAgeMs)` | stored map | pruned map |
| `new_apps_mark(json, found, nowMs)` | stored map + resolved apps | merged map |
| `new_apps_forget(json, id)` | stored map | map without `id` |
| `new_apps_missing(pending, found)` | id lists | pending ids |
| `fuzzy_rank(commands, query)` | command array | ranked array |
| `docs_rank(rows, nowSeconds)` | `{i, url, t}` rows | `{top, week, order}` |
| `kdeconnect_parse_devices(output)` | tab-separated CLI output | device array |
| `kdeconnect_parse_contacts(output)` | tab-separated CLI output | contact array |
| `kdeconnect_format_number(number)` | raw number | display number |
| `kdeconnect_vcard_load(device)` | device id | contact array |
| `shell_quote(value)` | any string | POSIX-quoted string |
| `cmd_ring`, `cmd_ping`, `cmd_send_clipboard`, `cmd_share_file`, `cmd_share_url`, `cmd_share_text`, `cmd_send_sms`, `cmd_dismiss_notification`, `cmd_reply_notification`, `cmd_mpris_action`, `cmd_mpris_set`, `cmd_notify_send` | validated arguments | shell command (empty string when validation fails) |

Lifetime and threading: the singleton is created and destroyed by the QML
engine; it stores nothing, starts no thread, timer or process, and all calls run
on the GUI thread. The vCard read is the only filesystem access and only happens
when the SMS panel opens; a missing directory yields an empty list. There is no
cancellation surface because no call is long-running.

Since 1.4.0 the category filter is QML-side and uses the existing Kicker
desktop-entry model. The native module is not consulted on category clicks;
crossing the QString/JSON bridge would add work to this lightweight path.
On catalog refresh, the widget caches category membership and rebuilds only
the selected category's rows; opening the menu with unchanged folder and
launch-history configuration skips their JSON parsing and the complete all-app
model rebuild. The obsolete recent-document timestamp subprocess no longer
runs at menu opening. New-application scans run once per minute and never
overlap. No additional thread or daemon was introduced.

The historical benchmark below describes the prior native-core migration, not
an end-to-end measurement of the 1.4.0 launcher. Reproduce interaction timing
in a Plasma 6 Wayland session with QML Profiler: record repeated popup openings,
first input, category changes, search, launch, and idle intervals on the same
application catalog before and after the change; report medians and p95 with
the sample count. An offscreen benchmark cannot measure compositor paint or
input-to-visible latency. The present archive did not include a Git history or
a Qt/Plasma runtime, so such before/after measurements remain unverified.

`Core.qml` is the contract with the UI: when `bridge` is `null`, methods that
would return structured data return `null` and command builders return `""`,
which is exactly what makes the JavaScript fallbacks run. `shellQuote` always
returns a valid quoted string.

## Building

Requirements:

* Rust 1.85+ (verified with 1.95), Cargo
* CMake 3.24+ (verified with 4.4)
* Qt 6.5+ development files: Core, Gui, Qml, Quick, QuickControls2
* CXX-Qt 0.10 CMake package, or network access so `rust/CMakeLists.txt` can
  fetch `cxx-qt-cmake` 0.10.0 (`CXXQT_DIR` points at a local install)

```sh
scripts/build-native.sh            # build into build/native
scripts/build-native.sh --stage    # also copy the module into contents/ui/core
scripts/package.sh --native        # assemble a clean package and install it
```

`scripts/package.sh` exists because `kpackagetool6` copies the whole directory
it is given: installing the checkout directly after a native build copies
`build/` and `rust/target/` (about 1.8 GB) into the widget package. The script
copies only `metadata.json`, `contents/` and `LICENSE` (about 11 MB with the
module).

Pure-QML installs keep working with `kpackagetool6 -t Plasma/Applet -i .`.

Uninstall: `kpackagetool6 -t Plasma/Applet -r org.fenestra.menu11`.

The native module is a Qt plugin and must be rebuilt for each Qt 6 ABI and
architecture; it is optional, not a runtime dependency. After upgrading the
plugin, restart Plasma (`systemctl --user restart plasma-plasmashell`) so the
QML engine reloads it.

## Testing

```sh
tests/run.sh             # Python regression tests (wiring, config, i18n)
scripts/test-native.sh   # fmt, clippy, cargo test, bridge, fallback, install-layout
BENCH=1 scripts/test-native.sh   # also run tests/qml/bench_core.qml
```

Results observed on the machine described below:

* `cargo fmt --all -- --check`: clean.
* `cargo clippy --workspace --all-targets -- -D warnings`: clean.
* `cargo test --workspace`: 48 passed, 0 failed.
* `qmltestrunner -import build/native/qml -input tests/qml/tst_core.qml`:
  12 passed.
* fallback test (`tst_fallback.qml`): 3 passed.
* widget-relative import test: 3 passed.
* `tests/run.sh`: 21 passed.
* package assembled with `scripts/package.sh --native` into an isolated
  `--packageroot`, discovered by `kpackagetool6`, singleton loaded from the
  installed layout, then removed cleanly.

Note: `/usr/bin/qmltestrunner` on this distribution is the Qt 5 binary and exits
silently when given a Qt 6 module. `scripts/test-native.sh` prefers the Qt 6
paths; override with `QMLTESTRUNNER=/path/to/qmltestrunner` if needed.

## Performance

Environment: CachyOS, Intel i3-1115G4 (4 threads), 12 GB RAM, Plasma 6.8.1,
Qt 6.12.0, rustc 1.95.0, CXX-Qt 0.10.0, release build, `QT_QPA_PLATFORM=offscreen`.
The benchmark runs both implementations in the same `qmltestrunner` process on
the same data; the native timings include the `JSON.stringify`/`JSON.parse`
that `Core.qml` performs around each call.

| Workload | JavaScript fallback | Rust core | Ratio |
| --- | --- | --- | --- |
| Command palette, 200 commands, query `set` | 1.3 ms | 0.56 ms | ~2.3× faster |
| Recommended documents, 60 rows (sort + page + week) | 0.014 ms | 0.043 ms | ~3× slower |

Reproduce with:

```sh
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
    -import build/native/qml -input tests/qml/bench_core.qml
```

Interpretation:

* Command-palette ranking is the interaction that visibly benefits; it runs on
  every keystroke over the whole command list.
* Document ordering is *slower* through the bridge in absolute terms, by about
  0.03 ms per rebuild. Rebuilds are debounced (500 ms) and touch at most 60
  rows, so the cost is not perceptible; the native path is kept because it
  makes the six-row page and the seven-day window a single tested rule instead
  of JS constants in a QML file. This is a deliberate, measured trade-off.
* Contact filtering was measured the same way over 400 contacts: JavaScript
  0.0063 ms per query versus 0.46 ms through the bridge, because serialising
  the whole contact list on every keystroke dwarfs the matching work. The
  bridge method was removed; vCard **parsing** stays in Rust (it replaces the
  Python subprocess) and filtering runs in JavaScript on the parsed array.
* The launch-score bridge method was also removed: `contextLabel` only needs
  `launchHasWorkflow`, so the per-application scoring call was unreachable.

Not measured, and therefore not claimed:

* plasmashell idle CPU and resident memory with the widget loaded. Isolating
  the applet in a live session requires adding it to the user's panel and
  restarting plasmashell, which was out of scope here.
* Widget opening and start-up latency in a Plasma session.
* Long-session stability. The native side keeps no state, timers or threads, so
  there is nothing to leak or poll, but this was not proven by a soak test.

Observation from the audit: the existing "new application" watcher runs a
shell pipeline over the XDG application directories every 10 seconds while the
widget is loaded. On this machine that is 245 `.desktop` files and about 6 ms
per run (~0.06 % of one core), inherited from the pre-migration widget. It was
left unchanged because moving it to a filesystem watch or a slower interval
changes notification behaviour and needs its own measurement.

## Security

* Every value placed in a shell command is fixed text or goes through
  `shell_quote`; device ids are restricted to `[A-Za-z0-9._-]`, notification
  ids to digits, MPRIS actions/properties to allow-lists.
* No `unsafe` Rust. No network access, telemetry or persistent service.
* `qdbus` calls are built as `qdbus6`/`qdbus-qt6`/`qdbus` with the member as one
  `interface.method` argument, matching what the QML layer already used. A bug
  where the interface and member were passed as separate arguments made
  notification and media actions fail when the native core was loaded; it is
  covered by a regression test.
* When a command builder rejects its input, the QML caller falls back to its
  quoted JavaScript command, so a rejected device id does not silently launch
  something else.

## Known limitations

* The module is prebuilt for one Qt ABI; the KDE Store package and plain source
  installs stay pure QML unless the builder stages the module.
* No CI configuration exists in the repository; the checks above are the
  documented manual procedure.
* The `.qmlls.ini` generated by `qml-language-server` contains an absolute build
  path and is not part of the repository.
