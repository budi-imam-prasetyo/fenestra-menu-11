/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Optional native core facade.
 *
 * The widget is a QML package and must keep working when the optional Rust
 * accelerator is not installed for the current architecture. This singleton
 * loads `RustBridge.qml` at run time; that file is the only one importing the
 * CXX-Qt module, so a missing module cannot break the widget.
 *
 * When the module is unavailable, methods that would return an object, array,
 * number or boolean return `null`, and command builders return `""`. Callers
 * keep their JavaScript fallback for exactly that case. `shellQuote` always
 * returns a valid POSIX-shell-quoted string.
 */
import QtQuick

QtObject {
    id: core

    // RustBridge instance, or null when the optional module is unavailable.
    property var bridge: null

    readonly property bool available: bridge !== null

    Component.onCompleted: {
        var component = Qt.createComponent("RustBridge.qml");
        if (component.status === Component.Ready) {
            try {
                core.bridge = component.createObject(core);
            } catch (error) {
                core.bridge = null;
            }
        }
        if (core.bridge === null) {
            console.info("fenestra-menu11: optional native core unavailable, using JavaScript fallbacks");
        }
    }

    function version() {
        return bridge !== null ? bridge.version() : "";
    }

    // ── Hibernation (logind CanHibernate) ──────────────────────────────────

    // → { known: bool, status: string } or null.
    function hibernateParse(output) {
        return bridge !== null ? bridge.hibernateParse(output) : null;
    }

    // → bool or null.
    function hibernateAvailable(status) {
        return bridge !== null ? bridge.hibernateAvailable(status) : null;
    }

    // ── Launch history ─────────────────────────────────────────────────────

    // → counts object or null.
    function launchParseCounts(raw) {
        return bridge !== null ? bridge.launchParseCounts(raw) : null;
    }

    // → updated counts object or null.
    function launchRecord(raw, appId, day, hour, nowMs) {
        return bridge !== null ? bridge.launchRecord(raw, appId, day, hour, nowMs) : null;
    }

    // → bool or null.
    function launchHasWorkflow(raw, day, hour, threshold) {
        return bridge !== null ? bridge.launchHasWorkflow(raw, day, hour, threshold) : null;
    }

    // → highest launch total or null.
    function launchTopTotal(raw) {
        return bridge !== null ? bridge.launchTopTotal(raw) : null;
    }

    // ── New application bookkeeping ────────────────────────────────────────

    // → { added: [], removed: [], changed: bool } or null.
    function newAppsDiff(known, current) {
        return bridge !== null ? bridge.newAppsDiff(known, current) : null;
    }

    // → pruned map or null.
    function newAppsPrune(storedJson, nowMs, maxAgeMs) {
        return bridge !== null ? bridge.newAppsPrune(storedJson, nowMs, maxAgeMs) : null;
    }

    // → merged map or null. `found` is [{ id, name, cat }].
    function newAppsMark(storedJson, found, nowMs) {
        return bridge !== null ? bridge.newAppsMark(storedJson, found, nowMs) : null;
    }

    // → map without `appId` or null.
    function newAppsForget(storedJson, appId) {
        return bridge !== null ? bridge.newAppsForget(storedJson, appId) : null;
    }

    // → pending ids not found in `foundIds`, or null.
    function newAppsMissing(pending, foundIds) {
        return bridge !== null ? bridge.newAppsMissing(pending, foundIds) : null;
    }

    // ── Command palette and documents ──────────────────────────────────────

    // → ranked command array or null.
    function fuzzyRank(commands, query) {
        return bridge !== null ? bridge.fuzzyRank(commands, query) : null;
    }

    // → { top: [modelRow…], week: [modelRow…], order: [modelRow…] } or null.
    function docsRank(rows, nowSeconds) {
        return bridge !== null ? bridge.docsRank(rows, nowSeconds) : null;
    }

    // ── KDE Connect ────────────────────────────────────────────────────────

    // → [{ id, name, type, reachable, … }] or null.
    function kdeconnectParseDevices(output) {
        return bridge !== null ? bridge.kdeconnectParseDevices(output) : null;
    }

    // → [{ name, number, type, key, digits }] or null.
    function kdeconnectParseContacts(output) {
        return bridge !== null ? bridge.kdeconnectParseContacts(output) : null;
    }

    // → French-formatted number or null.
    function kdeconnectFormatNumber(number) {
        return bridge !== null ? bridge.kdeconnectFormatNumber(number) : null;
    }

    // → contacts read from ~/.local/share/kpeoplevcard/kdeconnect-<device>.
    function kdeconnectVcardLoad(device) {
        return bridge !== null ? bridge.kdeconnectVcardLoad(device) : null;
    }

    // ── Command builders (return "" when native is unavailable) ────────────

    // Quote one argument for a POSIX shell. Never returns an unquoted value.
    function shellQuote(value) {
        var text = value === undefined || value === null ? "" : String(value);
        if (bridge !== null) {
            var quoted = bridge.shellQuote(text);
            if (quoted !== "" || text === "") {
                return quoted;
            }
        }
        return "'" + text.replace(/'/g, "'\\''") + "'";
    }

    function cmdRing(device) {
        return bridge !== null ? bridge.cmdRing(device) : "";
    }

    function cmdPing(device, message) {
        return bridge !== null ? bridge.cmdPing(device, message) : "";
    }

    function cmdSendClipboard(device) {
        return bridge !== null ? bridge.cmdSendClipboard(device) : "";
    }

    function cmdShareFile(device, path) {
        return bridge !== null ? bridge.cmdShareFile(device, path) : "";
    }

    function cmdShareUrl(device, url) {
        return bridge !== null ? bridge.cmdShareUrl(device, url) : "";
    }

    function cmdShareText(device, text) {
        return bridge !== null ? bridge.cmdShareText(device, text) : "";
    }

    function cmdSendSms(device, number, message) {
        return bridge !== null ? bridge.cmdSendSms(device, number, message) : "";
    }

    function cmdDismissNotification(device, id) {
        return bridge !== null ? bridge.cmdDismissNotification(device, id) : "";
    }

    function cmdReplyNotification(device, id, message) {
        return bridge !== null ? bridge.cmdReplyNotification(device, id, message) : "";
    }

    function cmdMprisAction(device, action) {
        return bridge !== null ? bridge.cmdMprisAction(device, action) : "";
    }

    function cmdMprisSet(device, property, value) {
        return bridge !== null ? bridge.cmdMprisSet(device, property, value) : "";
    }

    function cmdNotifySend(title, body, icon) {
        return bridge !== null ? bridge.cmdNotifySend(title, body, icon) : "";
    }
}
