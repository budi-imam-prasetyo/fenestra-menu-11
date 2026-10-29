# Fenestra Menu 11

A modern application launcher for KDE Plasma 6, with a built-in **mobile device panel** powered by KDE Connect.

Part of the **Fenestra** series, designed in particular for people coming from Windows, so they don't feel lost on a KDE Plasma desktop.

> Fenestra Menu 11 is a fork of [Menu 11 Next](https://github.com/Eisteed/menu-11-next) by Eisteed, reworked in depth. See [Credits](#credits).

## Features

### Start menu

- **Pinned** apps with folders, an optional strip of recently launched apps, and compact application-category filters derived from KDE's application catalog.
- **All apps** in **List** or **Grid** view, with a vertical category sidebar and retained viewports.
- Select **All apps** or a category to filter the browsing list. Applications in several categories appear once in each relevant filter. Search temporarily shows global runner results; clearing the query restores the selected category.
- Configure pinned app columns and rows in the widget settings. Menu width adapts to the column count, icon size and KDE font scaling, within the available screen space.
- Categories and apps scroll independently while pinned apps stay in place.
- **Search** for apps and settings, with filters, web search, a built-in calculator (`/calc`) and `Alt+1–9` to launch a result.
- Optional shell command runner (`> command`) and optional quick actions bar (screenshot, lock, terminal…).
- Footer with your **account** (avatar, name, manage account, other users) and a **power** menu (lock, sleep, hibernate, shut down, restart, sign out). Hibernate appears only when the running system reports that hibernation is available.
- **New** badge on newly installed apps, with a small dot on the matching category buttons until the app is opened.

### Mobile device panel (KDE Connect)

- Opens next to the menu with the KDE Connect button; menu and panel stay **centered together** on the screen, and the menu glides aside when the panel opens or closes.
- Setting **Keep the mobile panel open between menu openings** (on by default): the button works as a switch and the panel comes back with the menu. Turned off, the panel opens on demand and closes together with the menu.
- Phone status: name, connection, **battery** (with charging indicator), mobile network.
- Actions: **Ring**, **Send files**, **Browse**, **Clipboard**, **Send a link**, **Take a photo** (if the phone supports it), **SMS** (with your phone contacts), **Ping**, **Settings**.
- **Media card** when music plays on the phone: title, artist, previous / play-pause / next, volume, progress.
- **All mirrored notifications** in a scrollable list with edge fades, reply and dismiss.
- Step-by-step **pairing guide** for Android and iPhone.

## Requirements

- **KDE Plasma 6** (Qt 6). Plasma 5 is not supported.
- **Wayland** session. X11 is not supported.
- For the mobile device panel: **KDE Connect** installed and a paired phone, `qdbus` (`qdbus6` or `qdbus-qt6`) and `python3`. The native core replaces the Python contact reader, but the notification listing still uses Python.
- Optional: **Rust**, **CMake** and Qt 6 development files to build the native accelerator (see [Native core](#native-core-optional)).

## Firewall

The mobile device panel uses KDE Connect. If a firewall is active on your computer,
KDE Connect needs ports 1714 to 1764 open (TCP and UDP) on your local network,
otherwise your phone will not be found.

**firewalld** (Fedora, openSUSE):

```bash
sudo firewall-cmd --permanent --add-service=kdeconnect
sudo firewall-cmd --reload
```

**ufw** (Ubuntu, Kubuntu, Linux Mint):

```bash
sudo ufw allow 1714:1764/udp
sudo ufw allow 1714:1764/tcp
```

Solus has no active firewall by default.

## Installation

### From the KDE Store

Right-click the panel → **Add or Manage Widgets** → **Get New Widgets** → search for **Fenestra Menu 11**.

### Manual

```bash
git clone https://github.com/naykkalak/fenestra-menu-11.git
kpackagetool6 -t Plasma/Applet -i fenestra-menu-11
```

Then replace your current menu: right-click the Start button → **Show Alternatives…** → **Fenestra Menu 11**.

To update a manual install: `kpackagetool6 -t Plasma/Applet -u fenestra-menu-11`.

If you built the native core inside the checkout, install through
`scripts/package.sh` instead: `kpackagetool6` copies the whole directory, and
installing the checkout directly would copy `build/` and `rust/target/` into the
widget.

## Native core (optional)

The widget can load a small Rust module that evaluates the rules previously
duplicated in QML and JavaScript: command-palette ranking, hibernation capability parsing, launch history, new-application
bookkeeping, KDE Connect listings and vCard contacts, and the validated shell
commands. Layout, animations, Plasma integration and all fallbacks stay in QML.

```sh
scripts/build-native.sh            # build only
scripts/build-native.sh --stage    # build and copy the module into the widget
scripts/package.sh --native        # clean package + install
```

Requirements: Rust 1.85+, CMake 3.24+, Qt 6.5+ development files. CXX-Qt 0.10
is fetched automatically during the first build unless `CXXQT_DIR` is set.

A package without the module keeps working unchanged; the widget logs one line
and uses its JavaScript implementations. Settings, package id and Plasma
integration are identical in both cases. See [docs/native-core.md](docs/native-core.md)
for the architecture, API, measurements, build/install details and limitations.

Category filtering uses KDE's existing Kicker category model in both native and
QML-only installations. The former recent-document settings are retired in
version 1.4.0. Search in version 1.4.2 is limited to applications and settings.
Pinned items and recently launched apps remain available.

## Tests

```sh
tests/run.sh             # regression tests (wiring, configuration, translations)
scripts/test-native.sh   # Rust formatting, lint, unit tests and QML bridge tests
```

## Languages

English, Chinese (Simplified), Dutch, French, German, Italian, Japanese, Polish, Portuguese, Russian, Spanish and Turkish. The menu follows the language of your system and falls back to English.

Translations other than French are machine-assisted and **should be reviewed by native speakers**: corrections are welcome (files in `translate/`).

## Credits

- **[Menu 11 Next](https://github.com/Eisteed/menu-11-next)** by Eisteed (GPL-2.0-or-later), the starting point of this fork.
- **[Menu 11 / OnzeMenuKDE](https://github.com/adhec/OnzeMenuKDE)** and **Ditto Menu** by adhe (GPL-2.0-or-later), on which Menu 11 Next is based.
- **KDE** launcher code by Eike Hein, Aurélien Gâteau, Ivan Čukić and Weng Xuetian (GPL-2.0-or-later). Their copyright notices are kept in the source files.
- **Icons**
  - Mobile panel pictograms (`contents/icons/kdeconnect/`): [Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons), © Microsoft Corporation, MIT License (license file included).
  - Power button and power menu icons (`contents/icons/status/system-*-v2.svg`): [Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons), © Microsoft Corporation, MIT License.
  - KDE Connect button (`contents/icons/status/fenestra-kdeconnect.svg`): from the [KDE-Windows-Modern](https://github.com/Jeysef/KDE-Windows-Modern) icon theme by Jeysef, GPL-3.0.
  - Phone battery, mute and default avatar icons (`contents/icons/status/phone-*.svg`, `fenestra-avatar.svg`): original creations for Fenestra.

## Also in the Fenestra series

- [Fenestra Weather](https://github.com/naykkalak/fenestra-weather-icons): weather icon pack
- [Fenestra Weather Widget](https://github.com/naykkalak/fenestra-weather-widget): weather widget
- [Fenestra SDDM](https://github.com/naykkalak/fenestra-sddm): login screen
- [Fenestra This PC](https://github.com/naykkalak/fenestra-ce-pc): “This PC” window
- [Fenestra Search](https://github.com/naykkalak/fenestra-search): taskbar search

## License

Fenestra Menu 11 is distributed under the **GNU General Public License v3.0 or later** (see [LICENSE](LICENSE)).
Files inherited from Menu 11 Next and KDE keep their original GPL-2.0-or-later notices, a license that allows this redistribution under GPL-3.0-or-later.

*Not affiliated with or endorsed by Microsoft. “Windows” is a trademark of Microsoft Corporation and is only used here to describe the style.*

### Menu UI regression check

Run `sh scripts/test-menu.sh` on a Plasma 6 workstation with Qt and Plasma
development packages. It loads the real applet with isolated settings and checks
All three view buttons, dropdown selection and Escape, wheel scrolling, alphabet
navigation, pinned model operations, single activation, folders, search and focus. Screenshots are saved under `build/menu-tests/`.

List and Grid cache their catalog data and render only visible rows. The UI test
accepts `--benchmark` on its built `check` executable to time view switches.

Version 1.5 uses shared theme-derived colors, spacing, typography and controls.
Application icons retain their identities; interface actions use the KDE icon
theme. The existing KDE Connect layout and operations are preserved.

For the isolated light/dark, compact/expanded and 125% scale matrix, build the UI
harness above, then run `python3 tests/plasma/run_matrix.py`. Screenshots are in
`build/design-validation/`. Performance comparisons accept an immutable source
snapshot: `python3 tests/plasma/compare_performance.py /path/to/baseline`.
See [the 1.5 audit and validation report](docs/redesign-1.5.md) and
[the changelog](CHANGELOG.md) for evidence and known limits.
