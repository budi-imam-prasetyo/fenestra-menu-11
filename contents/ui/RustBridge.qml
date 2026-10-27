/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * SPDX-FileCopyrightText: 2026 naykkalak
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Native half of `Core.qml`.
 *
 * This file imports the optional CXX-Qt module that is staged next to the QML
 * files as `core/org/fenestra/menu11/core/`. It is only loaded at run time by
 * `Core.qml`, so a widget installed without the module (pure-QML install, or
 * an architecture without a prebuilt plugin) never fails to load: the import
 * error is contained in the dynamically created component.
 *
 * No widget state lives here. Every function takes and returns plain values;
 * JSON is encoded and decoded at this boundary.
 */
import QtQuick
import "core/org/fenestra/menu11/core"

QtObject {
    readonly property bool available: true

    function _decode(raw, fallback) {
        try {
            return JSON.parse(String(raw));
        } catch (error) {
            return fallback;
        }
    }

    function version() { return String(FenestraCore.version()); }

    // ── Hibernation ────────────────────────────────────────────────────────

    function hibernateParse(output) {
        return _decode(FenestraCore.hibernate_parse(String(output)), { known: false, status: "" });
    }

    function hibernateAvailable(status) {
        return FenestraCore.hibernate_available(String(status));
    }

    // ── Launch history ─────────────────────────────────────────────────────

    function launchParseCounts(raw) {
        return _decode(FenestraCore.launch_parse_counts(String(raw)), {});
    }

    function launchRecord(raw, appId, day, hour, nowMs) {
        return _decode(
            FenestraCore.launch_record(String(raw), String(appId), day, hour, nowMs), null);
    }

    function launchHasWorkflow(raw, day, hour, threshold) {
        return FenestraCore.launch_has_workflow(String(raw), day, hour, threshold);
    }

    function launchTopTotal(raw) {
        return FenestraCore.launch_top_total(String(raw));
    }

    // ── New application bookkeeping ────────────────────────────────────────

    function newAppsDiff(known, current) {
        return _decode(
            FenestraCore.new_apps_diff(JSON.stringify(known), JSON.stringify(current)), null);
    }

    function newAppsPrune(storedJson, nowMs, maxAgeMs) {
        return _decode(FenestraCore.new_apps_prune(storedJson, nowMs, maxAgeMs), null);
    }

    function newAppsMark(storedJson, found, nowMs) {
        return _decode(
            FenestraCore.new_apps_mark(storedJson, JSON.stringify(found), nowMs), null);
    }

    function newAppsForget(storedJson, appId) {
        return _decode(FenestraCore.new_apps_forget(storedJson, String(appId)), null);
    }

    function newAppsMissing(pending, foundIds) {
        return _decode(
            FenestraCore.new_apps_missing(JSON.stringify(pending), JSON.stringify(foundIds)), null);
    }

    // ── Command palette and documents ──────────────────────────────────────

    function fuzzyRank(commands, query) {
        return _decode(
            FenestraCore.fuzzy_rank(JSON.stringify(commands), String(query)), null);
    }

    function docsRank(rows, nowSeconds) {
        return _decode(
            FenestraCore.docs_rank(JSON.stringify(rows), nowSeconds), null);
    }

    // ── KDE Connect ────────────────────────────────────────────────────────

    function kdeconnectParseDevices(output) {
        return _decode(FenestraCore.kdeconnect_parse_devices(String(output)), null);
    }

    function kdeconnectParseContacts(output) {
        return _decode(FenestraCore.kdeconnect_parse_contacts(String(output)), null);
    }

    function kdeconnectFormatNumber(number) {
        return String(FenestraCore.kdeconnect_format_number(String(number)));
    }

    function kdeconnectVcardLoad(device) {
        return _decode(FenestraCore.kdeconnect_vcard_load(String(device)), null);
    }

    // ── Command builders ───────────────────────────────────────────────────

    function shellQuote(value) { return String(FenestraCore.shell_quote(String(value))); }
    function cmdRing(device) { return String(FenestraCore.cmd_ring(String(device))); }
    function cmdPing(device, message) { return String(FenestraCore.cmd_ping(String(device), String(message))); }
    function cmdSendClipboard(device) { return String(FenestraCore.cmd_send_clipboard(String(device))); }
    function cmdShareFile(device, path) { return String(FenestraCore.cmd_share_file(String(device), String(path))); }
    function cmdShareUrl(device, url) { return String(FenestraCore.cmd_share_url(String(device), String(url))); }
    function cmdShareText(device, text) { return String(FenestraCore.cmd_share_text(String(device), String(text))); }
    function cmdSendSms(device, number, message) {
        return String(FenestraCore.cmd_send_sms(String(device), String(number), String(message)));
    }
    function cmdDismissNotification(device, id) {
        return String(FenestraCore.cmd_dismiss_notification(String(device), String(id)));
    }
    function cmdReplyNotification(device, id, message) {
        return String(FenestraCore.cmd_reply_notification(String(device), String(id), String(message)));
    }
    function cmdMprisAction(device, action) {
        return String(FenestraCore.cmd_mpris_action(String(device), String(action)));
    }
    function cmdMprisSet(device, property, value) {
        return String(FenestraCore.cmd_mpris_set(String(device), String(property), value));
    }
    function cmdNotifySend(title, body, icon) {
        return String(FenestraCore.cmd_notify_send(String(title), String(body), String(icon)));
    }
}
