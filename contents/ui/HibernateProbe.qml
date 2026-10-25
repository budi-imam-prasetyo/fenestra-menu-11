/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Part of Fenestra Menu 11 (naykkalak, 2026), a fork of Menu 11 Next by Eisteed,
 * itself based on Menu 11 / Ditto Menu by adhe (GPL-2.0-or-later).
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "code/power.js" as PowerLogic

// Read-only runtime probe for hibernation support. KDE's SessionManagement
// already wraps login1's CanHibernate(), but its answer is cached when the
// session starts and can be stale (for example after enabling a swap file).
// The probe refreshes the login1 capability each time the power menu opens.
// It never changes system settings and never asks for authentication.
Item {
    id: root

    visible: false
    width: 0
    height: 0

    property var powerSession: null
    property bool known: false
    property bool available: false
    property string status: ""
    property string lastError: ""
    property bool probePending: false

    readonly property bool sessionAvailable: powerSession !== null
        && powerSession !== undefined
        && typeof powerSession.canHibernate !== "undefined"
        && powerSession.canHibernate === true
    readonly property bool hibernateAvailable: known ? available : sessionAvailable

    // Fixed commands only: no user input is ever interpolated into them.
    readonly property string probeCommand: "busctl --system --no-pager --timeout=2 call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate"
    readonly property string actionCommand: "busctl --system --no-pager call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager Hibernate b true"

    function refresh() {
        if (probePending) {
            return;
        }
        probePending = true;
        probeTimeout.restart();
        bus.connectSource(probeCommand + " # fenestra-hibernate-probe-" + Date.now());
    }

    // Fallback used only when KDE's SessionManagement cannot perform the
    // action itself. login1 still applies the normal Polkit authorization.
    function requestHibernate() {
        if (!hibernateAvailable) {
            return false;
        }
        bus.connectSource(actionCommand + " # fenestra-hibernate-action-" + Date.now());
        return true;
    }

    Timer {
        id: probeTimeout
        interval: 5000
        onTriggered: {
            root.probePending = false;
            root.known = false;
            root.lastError = "Timed out while querying logind";
        }
    }

    Plasma5Support.DataSource {
        id: bus
        engine: "executable"
        connectedSources: []

        onNewData: (source, data) => {
            disconnectSource(source);

            var code = Number(data["exit code"]);
            var out = String(data["stdout"] || "");
            var err = String(data["stderr"] || "").trim();

            if (source.indexOf("CanHibernate") !== -1) {
                probeTimeout.stop();
                root.probePending = false;

                if (code !== 0) {
                    root.known = false;
                    root.lastError = err;
                    return;
                }

                let reply = PowerLogic.parseCanHibernate(out);
                if (!reply.known) {
                    root.known = false;
                    root.lastError = "Unexpected logind reply: " + out.trim();
                    return;
                }

                root.status = reply.status;
                root.available = PowerLogic.isHibernateAvailable(reply.status);
                root.known = true;
                root.lastError = "";
            } else if (source.indexOf("Hibernate b true") !== -1 && code !== 0) {
                root.lastError = err;
                console.warn("fenestra-menu11: logind Hibernate failed:", err);
            }
        }
    }

    Component.onCompleted: refresh()
}
