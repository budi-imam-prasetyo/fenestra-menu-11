/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Part of Fenestra Menu 11 (naykkalak, 2026), a fork of Menu 11 Next by Eisteed,
 * itself based on Menu 11 / Ditto Menu by adhe (GPL-2.0-or-later).
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

Item {
    // Optional Rust accelerator, supplied by Footer.qml.
    property var core: null

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
        }
    }

    // Every argument is shell-quoted: URLs come from file models and desktop
    // entries, so they must not be able to inject a command.
    function shq(value) {
        if (core !== null) return core.shellQuote(value);
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    function openUrl(url) {
        var target = String(url);
        if (target.endsWith(".desktop")) {
            executable.connectSource("kioclient exec " + shq(target));
        } else {
            executable.connectSource("xdg-open " + shq(target));
        }
    }

    function runCommand(cmd) {
        executable.connectSource(cmd);
    }
}
