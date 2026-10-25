/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Part of Fenestra Menu 11 (naykkalak, 2026), a fork of Menu 11 Next by Eisteed,
 * itself based on Menu 11 / Ditto Menu by adhe (GPL-2.0-or-later).
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

.pragma library

// login1's CanHibernate() returns one of: "yes", "no", "na", "challenge",
// "inhibited", "inhibitor-blocked" or "challenge-inhibitor-blocked".
// ("inhibited-blocked" is an older/KDE-side spelling kept for compatibility.)
// busctl prints the reply as: s "yes".
var knownStatusPattern = /^(yes|no|na|challenge|inhibited|inhibitor-blocked|inhibited-blocked|challenge-inhibitor-blocked)$/;

function parseCanHibernate(output) {
    var text = (output === undefined || output === null) ? "" : String(output).trim();
    if (text === "") {
        return { known: false, status: "" };
    }

    var quoted = text.match(/"([^"]+)"/);
    if (quoted) {
        var quotedStatus = quoted[1].trim().toLowerCase();
        return { known: knownStatusPattern.test(quotedStatus), status: quotedStatus };
    }

    // Also accept a bare string, as printed by some D-Bus tools.
    var bare = text.replace(/^s\s+/, "").replace(/^["']|["']$/g, "").trim().toLowerCase();
    if (knownStatusPattern.test(bare)) {
        return { known: true, status: bare };
    }

    return { known: false, status: bare };
}

// Keep this list in sync with systemd's documented CanHibernate() results
// and KDE's libkworkspace backend: "challenge" means the action is available
// after Polkit authorization, while the inhibited variants are normally
// available but currently blocked by an inhibitor.
function isHibernateAvailable(status) {
    return status === "yes"
        || status === "challenge"
        || status === "inhibited"
        || status === "inhibitor-blocked"
        || status === "inhibited-blocked"
        || status === "challenge-inhibitor-blocked";
}
