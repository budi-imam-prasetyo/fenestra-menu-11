/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * SPDX-FileCopyrightText: 2026 naykkalak
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
/*
 * Fenestra Menu 11 — volet « Appareil mobile » (KDE Connect), façon Windows 11.
 * Fenêtre séparée collée au bord droit du menu (ou gauche si pas la place),
 * même hauteur que le menu. Ouverte/fermée par le bouton à droite de la recherche.
 *
 * Étape 2 : actions (sonner, fichiers, parcourir, presse-papiers, SMS, ping).
 * Étape 1 : détection des appareils appairés, en-tête (nom, état, batterie),
 *           écran « aucun appareil » + guides Android / iPhone.
 * Les données passent par D-Bus (qdbus6 / qdbus-qt6 / qdbus), rien n'est écrit en dur.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs
import QtQuick.Effects
import QtCore   // StandardPaths (icône KDE Connect du thème)
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid   // Fenestra : réglages du widget

PlasmaCore.Dialog {
    id: panel

    // fenêtre du menu principal (renseignée par MenuRepresentation.qml)
    property var menuWindow: null
    // Optional Rust accelerator (Core.qml), supplied by MenuRepresentation.qml.
    property var core: null

    flags: Qt.WindowStaysOnTopHint
    // posé sur le bord bas, comme le menu : pas de bordure ni d'arrondi en bas
    location: PlasmaCore.Types.BottomEdge
    hideOnWindowDeactivate: false
    visible: false

    // ── État ────────────────────────────────────────────────────────────────
    property var devices: []          // [{id, name, type, reachable, charge, charging}]
    property int current: 0
    property bool loaded: false
    property bool noQdbus: false
    property string page: "auto"      // "auto" | "android" | "iphone"
    property bool busy: false         // sélecteur de fichiers ouvert : ne pas tout fermer
    property bool hold: false          // une petite fenêtre du menu est ouverte : volet en pause
    property bool smsOpen: false
    property bool linkOpen: false        // formulaire « Envoyer un lien »
    property string toast: ""
    readonly property bool online: dev !== null && dev.reachable
    readonly property var dev: devices.length > 0 ? devices[Math.min(current, devices.length - 1)] : null
    readonly property bool hasPhoto: dev !== null && dev.plugins.indexOf("kdeconnect_photo") >= 0
    readonly property bool hasMedia: online && dev.mTitle !== ""
    readonly property bool hasNetwork: online && dev.netType !== "" && dev.netStrength >= 0

    // Fenestra : bouton interrupteur : l'état est gardé dans les réglages du widget
    function toggle() {
        Plasmoid.configuration.kdeConnectPanelOn = !visible;
        if (visible) close(); else open();
    }
    // menu ouvert avec le volet actif : réouverture dès que le menu est actif
    property bool aRouvrir: false
    property int retardOuverture: 0   // Fenestra : retard d'ouverture du volet (ms)
    readonly property int recentrageVolet: 4   // Fenestra : recentrage du volet (px vers la gauche)
    function rouvrirSiActif() {
        if (!aRouvrir || !menuWindow || !menuWindow.visible || visible) return;
        aRouvrir = false;
        graceVolet.restart();
        open();
        Qt.callLater(function () { if (menuWindow && menuWindow.visible) menuWindow.requestActivate(); });
    }

    function open() {
        hold = false;
        if (!menuWindow) return;
        page = "auto";
        smsOpen = false;
        linkOpen = false;
        toast = "";
        menuWindow.hideOnWindowDeactivate = false;
        visible = true;
        refresh();
    }

    // ferme le volet sans toucher au menu (une autre fenêtre du menu s'ouvre)
    function closeQuiet() { plusMenu.visible = false; if (visible) visible = false; }

    function close() {
        plusMenu.visible = false;
        if (!visible) return;
        visible = false;
        if (menuWindow) {
            menuWindow.hideOnWindowDeactivate = true;
            if (menuWindow.visible) menuWindow.requestActivate();
        }
    }

    onVisibleChanged: if (visible) Qt.callLater(reposition)

    // Fermeture native du menu (hideOnWindowDeactivate) :
    // coupée seulement quand la souris est sur le volet (pour pouvoir cliquer dedans),
    // réactivée dès que la souris en sort ET que le menu est actif.
    // C'est ce mécanisme natif qui détecte le clic sur la barre des tâches.
    function syncFlag() {
        if (!menuWindow || !visible) return;
        // Fenestra : fermeture native coupée pendant le délai de grâce
        var natif = menuWindow.active && !voletHover.hovered && !busy && !hold && !graceVolet.running;
        if (menuWindow.hideOnWindowDeactivate !== natif)
            menuWindow.hideOnWindowDeactivate = natif;
    }
    onBusyChanged: syncFlag()
    onHoldChanged: { if (!hold) graceVolet.restart(); syncFlag(); }   // Fenestra : délai de grâce après une petite fenêtre

    onActiveChanged: syncFlag()

    // le volet rend le focus au menu juste APRÈS un clic (au relâchement) :
    // jamais pendant, sinon le clic serait coupé en deux et perdu.
    // Exceptions : saisie SMS et sélecteur de fichiers (besoin du clavier).
    function rendreFocus() {
        if (!active || !menuWindow || !menuWindow.visible) return;
        if (smsOpen || linkOpen || notifReplying !== "" || busy || hold) return;
        menuWindow.requestActivate();
    }

    function reposition() {
        if (!menuWindow) return;
        var gap = Kirigami.Units.smallSpacing * 2;
        // Fenestra : écran du menu (au 1er clic, le volet n'est pas encore sur le bon écran)
        var mi = menuWindow.mainItem;
        var ecran = (mi && mi.Screen.width > 0) ? mi.Screen : content.Screen;
        var ecranDroite = ecran.virtualX + ecran.width;
        var ecranGauche = ecran.virtualX;
        var nx = menuWindow.x + menuWindow.width + gap;
        if (nx + width > ecranDroite)
            nx = Math.max(ecranGauche, menuWindow.x - width - gap);
        x = nx;
        y = menuWindow.y;
    }


    // ── Lecture des appareils par D-Bus ─────────────────────────────────────
    readonly property string readCmd:
        "sh -c 'Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); " +
        "[ -n \"$Q\" ] || { echo NOQDBUS; exit 0; }; " +
        "S=org.kde.kdeconnect; P=/modules/kdeconnect; " +
        "for i in $($Q $S $P org.kde.kdeconnect.daemon.devices false true 2>/dev/null); do " +
        "n=$($Q $S $P/devices/$i org.kde.kdeconnect.device.name 2>/dev/null); " +
        "t=$($Q $S $P/devices/$i org.kde.kdeconnect.device.type 2>/dev/null); " +
        "r=$($Q $S $P/devices/$i org.kde.kdeconnect.device.isReachable 2>/dev/null); " +
        "c=$($Q $S $P/devices/$i/battery org.kde.kdeconnect.device.battery.charge 2>/dev/null); " +
        "g=$($Q $S $P/devices/$i/battery org.kde.kdeconnect.device.battery.isCharging 2>/dev/null); " +
        // modules chargés (photo…), réseau mobile, musique en cours sur le téléphone
        "lp=$($Q $S $P/devices/$i org.kde.kdeconnect.device.loadedPlugins 2>/dev/null | tr \"\\n\" \",\"); " +
        "ct=$($Q $S $P/devices/$i/connectivity_report org.kde.kdeconnect.device.connectivity_report.cellularNetworkType 2>/dev/null); " +
        "cs=$($Q $S $P/devices/$i/connectivity_report org.kde.kdeconnect.device.connectivity_report.cellularNetworkStrength 2>/dev/null); " +
        "M=$P/devices/$i/mprisremote; I=org.kde.kdeconnect.device.mprisremote; " +
        "$Q $S $M $I.requestPlayerList >/dev/null 2>&1; " +
        "pl=$($Q $S $M $I.playerList 2>/dev/null | head -n1); pc=$($Q $S $M $I.player 2>/dev/null); " +
        "[ -z \"$pc\" ] && [ -n \"$pl\" ] && $Q $S $M $I.player \"$pl\" >/dev/null 2>&1; " +
        "mt=$($Q $S $M $I.title 2>/dev/null | tr \"\\t\\n\" \"  \"); " +
        "ma=$($Q $S $M $I.artist 2>/dev/null | tr \"\\t\\n\" \"  \"); " +
        "mp=$($Q $S $M $I.isPlaying 2>/dev/null); " +
        "ml=$($Q $S $M $I.length 2>/dev/null); mo=$($Q $S $M $I.position 2>/dev/null); " +
        "mk=$($Q $S $M $I.canSeek 2>/dev/null); mv=$($Q $S $M $I.volume 2>/dev/null); " +
        "printf \"%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n\" " +
        "\"$i\" \"$n\" \"$t\" \"$r\" \"${c:--1}\" \"$g\" \"$lp\" \"$ct\" \"${cs:--1}\" \"$mt\" \"$ma\" \"$mp\" " +
        "\"${ml:-0}\" \"${mo:-0}\" \"$mk\" \"${mv:--1}\"; done'"

    function refresh() { reader.connectSource(readCmd + " #" + Date.now()); }
    function run(cmd)   { runner.connectSource(cmd + " #" + Date.now()); }

    // ── Actions ─────────────────────────────────────────────────────────────
    // icônes Fluent UI (MIT) rangées dans le widget : contents/icons/kdeconnect/
    function ico(n) { return Qt.resolvedUrl("../icons/kdeconnect/" + n + ".svg"); }

    function shq(t) {
        if (core !== null) return core.shellQuote(t);
        return "'" + String(t).replace(/'/g, "'\\''") + "'";
    }
    function cli(args) { return "kdeconnect-cli -d " + shq(dev.id) + " " + args; }
    function say(t) { toast = t; toastTimer.restart(); }

    // Use the Rust command builder when it is available and accepted the
    // input; otherwise fall back to the JavaScript builder.
    function nativeCommand(command, fallback) { return command !== "" ? command : fallback; }

    function doRing() {
        if (!online) return;
        var command = core !== null ? core.cmdRing(dev.id) : "";
        run(nativeCommand(command, cli("--ring")));
        say(i18n("The phone is ringing…"));
    }
    function doPing() {
        if (!online) return;
        var message = i18n("Hello from the PC");
        var command = core !== null ? core.cmdPing(dev.id, message) : "";
        run(nativeCommand(command, cli("--ping-msg " + shq(message))));
        say(i18n("Ping sent"));
    }
    function doClipboard() {
        if (!online) return;
        var command = core !== null ? core.cmdSendClipboard(dev.id) : "";
        run(nativeCommand(command, cli("--send-clipboard")));
        say(i18n("Clipboard sent"));
    }
    function doBrowse() {
        if (!online) return;
        var id = shq(dev.id);
        run("sh -c " + shq("kdeconnect-cli -d " + id + " --mount; " +
            "for n in 1 2 3 4 5 6; do p=$(kdeconnect-cli -d " + id + " --get-mount-point 2>/dev/null); " +
            "[ -n \"$p\" ] && [ -d \"$p\" ] && ls \"$p\" >/dev/null 2>&1 && break; sleep 1; done; " +
            "[ -n \"$p\" ] && dolphin --new-window \"$p\""));
        say(i18n("Opening the phone's files…"));
    }
    function doFiles() {
        if (!online) return;
        busy = true;
        fileDialog.open();
    }
    function sendFiles(urls) {
        for (var k = 0; k < urls.length; k++) {
            var path = urls[k].toString();
            var command = core !== null ? core.cmdShareFile(dev.id, path) : "";
            run(nativeCommand(command, cli("--share " + shq(path))));
        }
        say(i18np("File sent", "%1 files sent", urls.length));
    }
    // lien web -> ouvert sur le téléphone ; autre texte -> envoyé comme texte
    function sendLink(texte) {
        var t = String(texte).trim();
        if (!online || t === "") return false;
        if (/^(https?:\/\/|www\.)/i.test(t)) {
            var url = /^www\./i.test(t) ? "https://" + t : t;
            var command = core !== null ? core.cmdShareUrl(dev.id, url) : "";
            run(nativeCommand(command, cli("--share " + shq(url))));
            say(i18n("Link sent: it opens on the phone"));
        } else {
            var command = core !== null ? core.cmdShareText(dev.id, t) : "";
            run(nativeCommand(command, cli("--share-text " + shq(t))));
            say(i18n("Text sent"));
        }
        return true;
    }

    // photo prise avec le téléphone, rangée dans Images/KDE Connect,
    // puis ouverte sur le PC dès qu'elle arrive (attente jusqu'à 90 s)
    function doPhoto() {
        if (!online || !hasPhoto) return;
        run("sh -c " + shq(
            "d=$(xdg-user-dir PICTURES 2>/dev/null); [ -d \"$d\" ] || d=\"$HOME/Images\"; " +
            "d=\"$d/KDE Connect\"; mkdir -p \"$d\"; " +
            "f=\"$d/photo-$(date +%Y%m%d-%H%M%S).jpg\"; " +
            "Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); " +
            "\"$Q\" org.kde.kdeconnect /modules/kdeconnect/devices/" + shq(dev.id) +
            "/photo org.kde.kdeconnect.device.photo.requestPhoto \"file://$f\" || exit 1; " +
            "for n in $(seq 1 90); do [ -s \"$f\" ] && { sleep 1; xdg-open \"$f\"; exit 0; }; sleep 1; done"));
        say(i18n("Take the photo on the phone: it will open here."));
    }

    // commandes multimédia : PlayPause, Next, Previous
    function media(action) {
        if (!hasMedia) return;
        var command = core !== null ? core.cmdMprisAction(dev.id, action) : "";
        run(nativeCommand(command, "sh -c " + shq(
            "Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); " +
            "\"$Q\" org.kde.kdeconnect /modules/kdeconnect/devices/" + shq(dev.id) +
            "/mprisremote org.kde.kdeconnect.device.mprisremote.sendAction " + action)));
    }

    function doSettings() { run("kdeconnect-app"); }

    // position du morceau (ms), avancée seconde par seconde entre deux lectures
    property real mediaPos: 0
    property real volAvantMuet: 40
    readonly property bool hasProgress: hasMedia && dev.mLength > 0
    readonly property bool hasVolume: hasMedia && dev.mVolume >= 0

    function fmtTime(ms) {
        var t = Math.max(0, Math.floor(ms / 1000));
        var h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), sec = t % 60;
        var ss = (sec < 10 ? "0" : "") + sec;
        return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss;
    }

    function mprisSet(prop, value) {
        var command = core !== null ? core.cmdMprisSet(dev.id, prop, Math.round(value)) : "";
        run(nativeCommand(command, "sh -c " + shq(
            "Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); " +
            "\"$Q\" org.kde.kdeconnect /modules/kdeconnect/devices/" + shq(dev.id) +
            "/mprisremote org.kde.kdeconnect.device.mprisremote." + prop + " " + value)));
    }

    function seekTo(ms) {
        if (!hasProgress || !dev.mSeek) return;
        mediaPos = Math.max(0, Math.min(dev.mLength, ms));
        mprisSet("position", Math.round(mediaPos));
    }

    // Muet : volume du téléphone à 0 en retenant la valeur d'avant ; un second clic la rétablit
    function toggleMute() {
        if (!hasMedia || dev.mVolume < 0) return;
        if (dev.mVolume > 0) {
            volAvantMuet = dev.mVolume;
            mprisSet("volume", 0);
        } else {
            mprisSet("volume", Math.max(1, Math.round(volAvantMuet)));
        }
        // relectures rapprochées : le téléphone met un instant à confirmer son nouveau volume
        run("sleep 0.7"); run("sleep 1.5"); run("sleep 2.5");
    }

    // Le téléphone règle son volume par crans (souvent 15, soit ~6,7 %) et arrondit
    // au cran le plus proche : un pas de 7 % fait franchir exactement un cran.
    // L'affichage montre toujours la valeur RÉELLE du téléphone (relue juste après).
    function volumeStep(delta) {
        if (!hasMedia || dev.mVolume < 0) return;
        mprisSet("volume", Math.max(0, Math.min(100, dev.mVolume + delta)));
    }

    // ── Notifications du téléphone (miroir : rien n'est gardé sur le disque) ──
    // lues avec busctl (un appel par notification) ; les notifications
    // permanentes (non retirables : musique, services…) sont écartées
    property var notifs: []            // [{id, app, title, text, reply, icon}]
    property string notifReplying: ""  // id de la notification à laquelle on répond
    readonly property bool hasNotifPlugin: online && dev.plugins.indexOf("kdeconnect_notifications") >= 0

    readonly property string lecteurNotifs: "import json, subprocess, sys\nbase = \"/modules/kdeconnect/devices/\" + sys.argv[1] + \"/notifications\"\ndef call(path, iface, method, *args):\n    try:\n        r = subprocess.run([\"busctl\", \"--user\", \"--json=short\", \"call\", \"org.kde.kdeconnect\",\n                            path, iface, method] + list(args), capture_output=True, text=True, timeout=5)\n        return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else None\n    except Exception:\n        return None\nr = call(base, \"org.kde.kdeconnect.device.notifications\", \"activeNotifications\")\nids = r[\"data\"][0] if r else []\nout = []\nfor i in ids:\n    g = call(base + \"/\" + i, \"org.freedesktop.DBus.Properties\", \"GetAll\", \"s\",\n             \"org.kde.kdeconnect.device.notifications.notification\")\n    if not g:\n        continue\n    p = {k: v.get(\"data\") for k, v in g[\"data\"][0].items()}\n    if not p.get(\"dismissable\"):\n        continue\n    out.append({\"id\": i, \"app\": p.get(\"appName\") or \"\", \"title\": p.get(\"title\") or \"\",\n                \"text\": p.get(\"text\") or \"\", \"reply\": p.get(\"replyId\") or \"\",\n                \"icon\": (p.get(\"iconPath\") or \"\") if p.get(\"hasIcon\") else \"\"})\nout.sort(key=lambda n: int(n[\"id\"]) if n[\"id\"].isdigit() else 0, reverse=True)\nprint(json.dumps(out))\n"

    function refreshNotifs() {
        if (!hasNotifPlugin) { notifs = []; return; }
        notifSource.connectSource("sh -c " + shq("python3 -c " + shq(lecteurNotifs) + " " + shq(dev.id)) +
                                  " #" + Date.now());
    }

    function notifCall(id, method, arg) {
        run("sh -c " + shq(
            "Q=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus); " +
            "\"$Q\" org.kde.kdeconnect /modules/kdeconnect/devices/" + shq(dev.id) + "/notifications/" + shq(id) +
            " org.kde.kdeconnect.device.notifications.notification." + method +
            (arg !== undefined ? " " + shq(arg) : "")));
    }

    // retirer = balayer la notification : le message lui-même n'est pas supprimé
    function dismissNotif(id) {
        var command = core !== null ? core.cmdDismissNotification(dev.id, id) : "";
        if (command !== "") run(command); else notifCall(id, "dismiss");
        notifs = notifs.filter(function (n) { return n.id !== id; });
        if (notifReplying === id) notifReplying = "";
    }

    function dismissAllNotifs() {
        for (var k = 0; k < notifs.length; k++) dismissNotif(notifs[k].id);
        notifs = [];
        notifReplying = "";
    }

    function replyNotif(id, msg) {
        if (String(msg).trim() === "") return false;
        var command = core !== null ? core.cmdReplyNotification(dev.id, id, msg) : "";
        if (command !== "") run(command); else notifCall(id, "sendReply", msg);
        notifReplying = "";
        say(i18n("Reply sent"));
        return true;
    }

    // ── Contacts (fiches vCard synchronisées par KDE Connect) ──
    // lus à l'ouverture du formulaire SMS, gardés en mémoire seulement
    property var contacts: []          // [{name, number, type, key, digits}]
    property var smsSuggestions: []
    property string smsContact: ""     // « Marie (mobile) » une fois choisi

    readonly property string lecteurContacts: "import sys, os, glob, quopri\nout = set()\nfor f in glob.glob(os.path.join(sys.argv[1], \"*.vcf\")):\n    try:\n        raw = open(f, \"rb\").read().decode(\"utf-8\", \"replace\").replace(\"\\r\\n\", \"\\n\")\n    except Exception:\n        continue\n    lignes = []\n    for l in raw.split(\"\\n\"):\n        if lignes and l[:1] in (\" \", \"\\t\"):\n            lignes[-1] += l[1:]\n            continue\n        if lignes and lignes[-1].endswith(\"=\") and \"QUOTED-PRINTABLE\" in lignes[-1].split(\":\", 1)[0].upper():\n            lignes[-1] = lignes[-1][:-1] + l\n            continue\n        lignes.append(l)\n    nom, tels = \"\", []\n    for l in lignes:\n        if \":\" not in l:\n            continue\n        k, v = l.split(\":\", 1)\n        parts = k.split(\";\")\n        cle, params = parts[0].upper(), \";\".join(parts[1:]).upper()\n        if \"QUOTED-PRINTABLE\" in params:\n            v = quopri.decodestring(v.encode()).decode(\"utf-8\", \"replace\")\n        if cle == \"FN\":\n            nom = v.strip()\n        elif cle == \"TEL\":\n            t = \"mobile\" if \"CELL\" in params else \"domicile\" if \"HOME\" in params else \"travail\" if \"WORK\" in params else \"\"\n            tels.append((v.strip(), t))\n    for num, t in tels:\n        if nom and num:\n            out.add((nom.replace(\"\\t\", \" \"), num, t))\nfor n, num, t in sorted(out, key=lambda x: x[0].lower()):\n    print(n + \"\\t\" + num + \"\\t\" + t)\n"

    function loadContacts() {
        if (!dev) return;
        var nativeContacts = core !== null ? core.kdeconnectVcardLoad(dev.id) : null;
        if (nativeContacts !== null) {
            contacts = nativeContacts;
            return;
        }
        var dossier = "$HOME/.local/share/kpeoplevcard/kdeconnect-" + shq(dev.id);
        contactsSource.connectSource("sh -c " + shq("python3 -c " + shq(lecteurContacts) +
                                     " " + dossier) + " #" + Date.now());
    }

    function sansAccents(t) {
        var r = String(t).toLowerCase();
        try { r = r.normalize("NFD").replace(/[\u0300-\u036f]/g, ""); } catch (e) {}
        return r;
    }

    function filterContacts(q) {
        var n = sansAccents(q).trim();
        if (n === "") { smsSuggestions = []; return; }
        var nativeMatches = core !== null ? core.kdeconnectFilterContacts(contacts, q, 6) : null;
        if (nativeMatches !== null) { smsSuggestions = nativeMatches; return; }
        var chiffres = n.replace(/[^0-9]/g, "");
        // numéros français : 06… et +33 6… sont équivalents
        var autre = chiffres.indexOf("0") === 0 ? "33" + chiffres.slice(1)
                  : chiffres.indexOf("33") === 0 ? "0" + chiffres.slice(2) : "";
        var res = [];
        for (var i = 0; i < contacts.length && res.length < 6; i++) {
            var c = contacts[i];
            var parNom = c.key.indexOf(n) >= 0;
            var parNum = chiffres.length >= 3 && /^[+0-9 .\-()]+$/.test(n)
                         && (c.digits.indexOf(chiffres) >= 0 || (autre !== "" && c.digits.indexOf(autre) >= 0));
            if (parNom || parNum) res.push(c);
        }
        smsSuggestions = res;
    }

    // affichage à la française : 06 35 93 98 41  /  +336 35 93 98 41
    // (numéros étrangers ou courts : laissés tels quels)
    function fmtNumero(num) {
        var nativeNumber = core !== null ? core.kdeconnectFormatNumber(num) : null;
        if (nativeNumber !== null) return nativeNumber;
        var brut = String(num).trim();
        var d = brut.replace(/[^0-9]/g, "");
        function paires(t) { return t.replace(/(\d{2})(?=\d)/g, "$1 "); }
        if (/^\+/.test(brut) && d.length === 11 && d.indexOf("33") === 0)
            return "+33" + d.charAt(2) + " " + paires(d.slice(3));
        if (d.length === 10 && d.charAt(0) === "0")
            return paires(d);
        return brut;
    }

    function pickContact(c) {
        smsContact = c.name + (c.type !== "" ? " (" + c.type + ")" : "");
        smsSuggestions = [];
    }

    onSmsOpenChanged: {
        smsContact = "";
        smsSuggestions = [];
        if (smsOpen) {
            smsNumber.text = "";        // nouveau destinataire à chaque ouverture
            loadContacts();
        }
    }

    function sendSms(num, msg) {
        if (!online || num.trim() === "" || msg.trim() === "") return false;
        if (num.replace(/[^0-9]/g, "").length < 3) {        // un nom, pas un numéro
            say(i18n("Choose a contact from the list or type a number"));
            return false;
        }
        smsEnCours = true;
        say(i18n("Sending SMS…"));
        // « echo CODE=$? » : la commande dit si le téléphone a bien reçu l'ordre d'envoi
        var propre = num.trim().replace(/[\s.\-()]/g, "");   // 06 35… -> 0635…
        var command = core !== null ? core.cmdSendSms(dev.id, propre, msg) : "";
        smsSource.connectSource(nativeCommand(command,
                                "sh -c " + shq(cli("--destination " + shq(propre) +
                                " --send-sms " + shq(msg)) + "; echo CODE=$?")) + " #" + Date.now());
        return true;
    }
    property bool smsEnCours: false


    // ── Petits composants au style du thème ─────────────────────────────────
    // icône Fluent du widget : le SVG sert de pochoir (masque), rempli avec la
    // couleur du texte du thème. Lu directement depuis le fichier : Plasma ne
    // peut pas lui substituer une icône du thème portant le même nom.
    component FluentIcon: Item {
        id: fi
        property string src: ""
        property color tint: Kirigami.Theme.textColor
        Image {
            id: fiForme
            anchors.fill: parent
            source: fi.src
            sourceSize.width: Math.max(1, fi.width) * 2
            sourceSize.height: Math.max(1, fi.height) * 2
            smooth: true
            visible: false
        }
        Rectangle {
            id: fiCouleur
            anchors.fill: parent
            color: fi.tint
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: fiCouleur
            maskEnabled: true
            maskSource: fiForme
            // seuil à mi-transparence + transition douce : les bords anticrénelés
            // gardent leur finesse (sinon chaque trait s'épaissit d'un pixel)
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    // ligne de la fenêtre « ··· » : même présentation que la fenêtre Alimentation
    // (icône 22 px, marges, surlignement blanc 50 % arrondi au survol)
    component PlusItem: Item {
        id: pi
        property string label: ""
        property string icone: ""          // icône Fluent du widget
        property string iconeFichier: ""   // ou fichier d'icône précis (prioritaire)
        signal clicked()
        Layout.fillWidth: true
        implicitWidth: piRow.implicitWidth + (Kirigami.Units.smallSpacing + 6) * 2
        implicitHeight: Math.max(22, piText.implicitHeight) + Kirigami.Units.smallSpacing * 2
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Kirigami.Units.smallSpacing
            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
            border.width: 1                 // même bordure que les autres surlignements
            border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
            opacity: piMouse.containsMouse ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
        Row {
            id: piRow
            x: Kirigami.Units.smallSpacing + 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: Kirigami.Units.smallSpacing + 6
            FluentIcon {
                visible: pi.iconeFichier === ""
                src: pi.iconeFichier === "" ? panel.ico(pi.icone) : ""
                width: 22; height: 22
                anchors.verticalCenter: parent.verticalCenter
            }
            Kirigami.Icon {
                visible: pi.iconeFichier !== ""
                source: pi.iconeFichier
                width: 22; height: 22
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: piText
                text: pi.label
                color: Kirigami.Theme.textColor
                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: piMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pi.clicked()
        }
    }

    // bouton : surlignement blanc 50 % + bordure au survol
    component PanelButton: Item {
        id: pb
        property string text: ""
        property string iconName: ""
        property bool framed: true          // cadre visible au repos (boutons Android / iPhone)
        readonly property bool fluent: iconName.indexOf("/icons/kdeconnect/") >= 0
        readonly property bool hovered: pbMouse.containsMouse
        property bool press: false      // effet d'enfoncement au clic
        signal clicked()
        implicitWidth: pbRow.implicitWidth + Kirigami.Units.largeSpacing * 2
        implicitHeight: Math.max(28, pbRow.implicitHeight + Kirigami.Units.smallSpacing * 2)
        Accessible.role: Accessible.Button
        Accessible.name: text

        Rectangle {
            anchors.fill: parent
            radius: 5
            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
            border.width: 1
            border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
            opacity: (pbMouse.containsMouse || pb.framed) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
        Row {
            id: pbRow
            anchors.centerIn: parent
            scale: (pb.press && pbMouse.pressed) ? 0.85 : 1.0
            Behavior on scale { NumberAnimation { duration: 100 } }
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                visible: pb.iconName !== "" && !pb.fluent
                source: pb.fluent ? "" : pb.iconName
                width: Kirigami.Units.iconSizes.small; height: width
                anchors.verticalCenter: parent.verticalCenter
            }
            FluentIcon {
                visible: pb.fluent
                src: pb.fluent ? pb.iconName : ""
                width: Kirigami.Units.iconSizes.small; height: width
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: pb.text
                color: Kirigami.Theme.textColor
                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: pbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
    }

    // tuile d'action : icône + libellé, surlignement blanc 50 % au survol
    component ActionTile: Item {
        id: at
        FontMetrics { id: atMetrics; font: Kirigami.Theme.smallFont }
        property string text: ""
        property string iconName: ""
        property bool active: true
        readonly property bool fluent: iconName.indexOf("/icons/kdeconnect/") >= 0
        signal clicked()
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
                        + atMetrics.height * 2 + Kirigami.Units.largeSpacing * 2
        opacity: active ? 1.0 : 0.4
        Accessible.role: Accessible.Button
        Accessible.name: text

        Rectangle {
            anchors.fill: parent
            radius: 5
            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
            border.width: 1
            border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
            opacity: (atMouse.containsMouse && at.active) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
        Column {
            id: atCol
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Kirigami.Units.largeSpacing
            width: parent.width - Kirigami.Units.smallSpacing * 2
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                visible: !at.fluent
                anchors.horizontalCenter: parent.horizontalCenter
                source: at.fluent ? "" : at.iconName
                width: Kirigami.Units.iconSizes.smallMedium; height: width
                scale: atMouse.pressed && at.active ? 0.85 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
            }
            FluentIcon {
                visible: at.fluent
                anchors.horizontalCenter: parent.horizontalCenter
                src: at.fluent ? at.iconName : ""
                width: Kirigami.Units.iconSizes.smallMedium; height: width
                scale: atMouse.pressed && at.active ? 0.85 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: at.text
                color: Kirigami.Theme.textColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
        MouseArea {
            id: atMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: at.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (at.active) at.clicked()
        }
    }

    // illustration dessinée (PC portable + téléphone), aux couleurs du thème
    component Illustration: Item {
        implicitWidth: 170
        implicitHeight: 110
        // écran du portable
        Rectangle {
            id: laptop
            x: 0; y: 8
            width: 130; height: 84
            radius: 6
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
                           Kirigami.Theme.highlightColor.b, 0.35)
            border.width: 3
            border.color: "#5A5A5A"
            Rectangle {   // petites « notifications » sur l'écran
                x: 14; y: 30; width: 16; height: 16; radius: 4; color: "#F2A33A"
            }
            Rectangle { x: 34; y: 30; width: 16; height: 16; radius: 4; color: "#3DAEE6" }
            Rectangle { x: 54; y: 30; width: 40; height: 16; radius: 4; color: "#ffffff"; opacity: 0.9 }
        }
        // socle du portable
        Rectangle {
            x: -8; y: laptop.y + laptop.height - 1
            width: laptop.width + 16; height: 7; radius: 3
            color: "#8A8A8A"
        }
        // téléphone
        Rectangle {
            x: 108; y: 0
            width: 52; height: 100
            radius: 9
            color: "#3A3A3A"
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 6
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
                               Kirigami.Theme.highlightColor.b, 0.75)
            }
        }
    }

    // ── Contenu du volet ────────────────────────────────────────────────────
    mainItem: Item {
        id: content
        width: Kirigami.Units.gridUnit * 16
        height: panel.menuWindow
                ? Math.max(Kirigami.Units.gridUnit * 12,
                           panel.menuWindow.height - panel.margins.top - panel.margins.bottom)
                : Kirigami.Units.gridUnit * 20

        focus: true
        Keys.onEscapePressed: panel.close()

        // objets non visuels (un Dialog n'accepte que son mainItem comme enfant)
        // le menu se ferme -> le volet aussi ; le menu bouge -> on suit
        // survol du volet (fonctionne sans focus)
        HoverHandler {
            id: voletHover
            onHoveredChanged: panel.syncFlag()
        }

        // après chaque clic dans le volet (au relâchement, une fois l'action faite),
        // le focus est rendu au menu : KWin l'accepte car c'est la suite d'un clic
        // (un simple déplacement de souris serait refusé sous Wayland).
        // Poignée passive : elle observe les clics sans jamais les intercepter.
        PointHandler {
            acceptedButtons: Qt.LeftButton
            onActiveChanged: if (!active) Qt.callLater(panel.rendreFocus)
        }

        Connections {
            target: panel.menuWindow
            function onActiveChanged() { panel.syncFlag(); }
            function onVisibleChanged() {
                if (!panel.menuWindow.visible) { panel.aRouvrir = false; panel.close(); }
                else { panel.aRouvrir = Plasmoid.configuration.kdeConnectMemoriser && Plasmoid.configuration.kdeConnectPanelOn; retardVolet.restart(); }
            }
            function onXChanged() { if (panel.visible) Qt.callLater(panel.reposition); }
            function onYChanged() { if (panel.visible) Qt.callLater(panel.reposition); }
            function onHeightChanged() { if (panel.visible) Qt.callLater(panel.reposition); }
        }

        // Fenestra : délai de grâce à l'ouverture : menu et volet apparaissent ensemble,
        // la surveillance ci-dessous attend qu'ils soient en place
        Timer { id: graceVolet; interval: 600; onTriggered: panel.syncFlag() }
        Timer { id: retardVolet; interval: panel.retardOuverture; onTriggered: panel.rouvrirSiActif() }
        // Fenestra : préchargement du téléphone : 3 s après le démarrage, volet fermé (contenu prêt à la 1re ouverture)
        Timer { id: prechargementVolet; interval: 3000; running: true; onTriggered: if (!panel.visible) panel.refresh() }

        // clic en dehors du menu ET du volet -> tout se ferme
        Timer {
            interval: 250
            repeat: true
            running: panel.visible
            onTriggered: {
                if (!panel.menuWindow) return;
                panel.syncFlag();
                if (panel.busy || panel.hold || graceVolet.running) return;
                if (!panel.active && !panel.menuWindow.active) {
                    panel.close();
                    panel.menuWindow.visible = false;
                }
            }
        }

        // rafraîchissement régulier tant que le volet est ouvert
        Timer {
            interval: 5000
            repeat: true
            running: panel.visible
            onTriggered: panel.refresh()
        }

        P5Support.DataSource {
            id: reader
            engine: "executable"
            connectedSources: []
            onNewData: (source, data) => {
                disconnectSource(source);
                var out = (data["stdout"] || "").trim();
                panel.noQdbus = (out === "NOQDBUS");
                var list = [];
                if (!panel.noQdbus && out !== "") {
                    var nativeDevices = panel.core !== null ? panel.core.kdeconnectParseDevices(out) : null;
                    if (nativeDevices !== null) {
                        list = nativeDevices;
                    } else {
                        var lines = out.split("\n");
                        for (var k = 0; k < lines.length; k++) {
                            var f = lines[k].split("\t");
                            if (f.length < 6 || f[0] === "") continue;
                            var force = parseInt(f[8]);
                            list.push({ id: f[0], name: f[1] || f[0], type: f[2],
                                        reachable: f[3] === "true",
                                        charge: parseInt(f[4]), charging: f[5] === "true",
                                        plugins: (f[6] || "").split(","),
                                        netType: (f[7] || "").trim(),
                                        netStrength: isNaN(force) ? -1 : force,
                                        mTitle: (f[9] || "").trim(),
                                        mArtist: (f[10] || "").trim(),
                                        mPlaying: f[11] === "true",
                                        mLength: parseInt(f[12]) || 0,
                                        mPos: parseInt(f[13]) || 0,
                                        mSeek: f[14] === "true",
                                        mVolume: isNaN(parseInt(f[15])) ? -1 : parseInt(f[15]) });
                        }
                    }
                }
                // garde l'appareil choisi s'il existe toujours
                var keepId = panel.dev ? panel.dev.id : "";
                panel.devices = list;
                var idx = 0;
                for (var j = 0; j < list.length; j++) if (list[j].id === keepId) idx = j;
                panel.current = idx;
                panel.loaded = true;
                if (panel.dev) panel.mediaPos = panel.dev.mPos;
                panel.refreshNotifs();
            }
        }

        Timer {
            id: toastTimer
            interval: 2500
            onTriggered: panel.toast = ""
        }

        FileDialog {
            id: fileDialog
            title: i18n("Send to phone")
            fileMode: FileDialog.OpenFiles
            onAccepted: {
                panel.sendFiles(selectedFiles);
                panel.busy = false;
                panel.requestActivate();
            }
            onRejected: {
                panel.busy = false;
                panel.requestActivate();
            }
        }

        P5Support.DataSource {
            id: notifSource
            engine: "executable"
            connectedSources: []
            onNewData: (source, data) => {
                disconnectSource(source);
                try {
                    var liste = JSON.parse(String(data["stdout"] || "[]"));
                    if (Array.isArray(liste)) panel.notifs = liste;
                } catch (e) { /* lecture ratée : on garde la liste précédente */ }
            }
        }

        P5Support.DataSource {
            id: smsSource
            engine: "executable"
            connectedSources: []
            onNewData: (source, data) => {
                disconnectSource(source);
                panel.smsEnCours = false;
                var ok = /CODE=0\s*$/.test(String(data["stdout"] || ""));
                if (ok) {
                    panel.say(i18n("✓ SMS handed over to the phone"));
                    smsText.text = "";
                    panel.smsOpen = false;
                } else {
                    // le formulaire reste ouvert, le texte est conservé
                    panel.say(i18n("✗ Failed: SMS not handed over to the phone"));
                }
            }
        }

        P5Support.DataSource {
            id: contactsSource
            engine: "executable"
            connectedSources: []
            onNewData: (source, data) => {
                disconnectSource(source);
                var output = String(data["stdout"] || "");
                var nativeContacts = panel.core !== null ? panel.core.kdeconnectParseContacts(output) : null;
                if (nativeContacts !== null) {
                    panel.contacts = nativeContacts;
                    return;
                }
                var list = [];
                var lignes = output.split("\n");
                for (var k = 0; k < lignes.length; k++) {
                    var f = lignes[k].split("\t");
                    if (f.length < 2 || f[0] === "" || f[1] === "") continue;
                    list.push({ name: f[0], number: f[1], type: f[2] || "",
                                key: panel.sansAccents(f[0]),
                                digits: f[1].replace(/[^0-9]/g, "") });
                }
                panel.contacts = list;
            }
        }

        P5Support.DataSource {
            id: runner
            engine: "executable"
            connectedSources: []
            onNewData: (source, data) => {
                disconnectSource(source);
                Qt.callLater(panel.refresh);
            }
        }

        // ----- Page : aucun appareil appairé (accueil) -----
        ColumnLayout {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -panel.recentrageVolet   // Fenestra : recentrage du volet
            width: parent.width - Kirigami.Units.gridUnit * 2
            spacing: Kirigami.Units.largeSpacing
            visible: panel.loaded && panel.devices.length === 0 && panel.page === "auto"

            Illustration { Layout.alignment: Qt.AlignHCenter }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: i18n("Access your mobile device here")
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: panel.noQdbus
                      ? i18n("The qdbus tool was not found: unable to talk to KDE Connect.")
                      : i18n("See your phone's battery, files and notifications right in the Start menu, thanks to KDE Connect.")
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.largeSpacing
                text: i18n("Select your device")
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.largeSpacing
                PanelButton { text: "Android"; onClicked: panel.page = "android" }
                PanelButton { text: "iPhone";  onClicked: panel.page = "iphone" }
            }
        }

        // ----- Page : guide d'appairage (Android ou iPhone) -----
        ColumnLayout {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -panel.recentrageVolet   // Fenestra : recentrage du volet
            width: parent.width - Kirigami.Units.gridUnit * 2
            spacing: Kirigami.Units.largeSpacing
            visible: panel.page === "android" || panel.page === "iphone"

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: panel.page === "iphone" ? i18n("Connect an iPhone") : i18n("Connect an Android phone")
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                lineHeight: 1.2
                text: (panel.page === "iphone"
                       ? i18n("1. Install the KDE Connect app from the App Store.\n")
                       : i18n("1. Install the KDE Connect app from the Play Store or F-Droid.\n"))
                      + i18n("2. Connect the phone to the same Wi-Fi network as this PC (or connect this PC to the phone's hotspot).\n")
                      + i18n("3. In the app, tap the name of this PC, then “Request pairing”.\n")
                      + i18n("4. Accept the request that appears on this PC.")
            }
            Text {
                Layout.fillWidth: true
                visible: panel.page === "iphone"
                wrapMode: Text.WordWrap
                text: i18n("On iPhone, KDE Connect offers fewer features than on Android.")
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                font.italic: true
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.largeSpacing
                PanelButton {
                    text: i18n("Download")
                    iconName: "internet-web-browser"
                    onClicked: Qt.openUrlExternally("https://kdeconnect.kde.org/download.html")
                }
                PanelButton {
                    text: i18n("Search")
                    iconName: "view-refresh"
                    onClicked: panel.run("kdeconnect-cli --refresh")
                }
            }
            PanelButton {
                Layout.alignment: Qt.AlignHCenter
                framed: false
                text: i18n("< Back")
                onClicked: panel.page = "auto"
            }
        }

        // ----- Page : appareil appairé -----
        ColumnLayout {
            anchors.top: parent.top
            anchors.topMargin: Kirigami.Units.gridUnit
            anchors.bottom: piedVolet.top
            anchors.bottomMargin: Kirigami.Units.smallSpacing
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -panel.recentrageVolet   // Fenestra : recentrage du volet
            width: parent.width - Kirigami.Units.gridUnit * 2
            spacing: Kirigami.Units.smallSpacing
            visible: panel.dev !== null && panel.page === "auto"

            Illustration {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Kirigami.Units.largeSpacing
            }

            // choix de l'appareil s'il y en a plusieurs
            PC3.ComboBox {
                Layout.fillWidth: true
                visible: panel.devices.length > 1
                model: panel.devices.map(d => d.name)
                currentIndex: panel.current
                onActivated: idx => panel.current = idx
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: panel.dev && panel.dev.type === "tablet" ? "tablet" : "smartphone"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: panel.dev ? panel.dev.name : ""
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                        font.weight: Font.DemiBold
                        color: Kirigami.Theme.textColor
                    }
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: panel.dev && panel.dev.reachable ? "#2ecc71" : "#9A9A9A"
                        }
                        Text {
                            text: panel.dev && panel.dev.reachable ? i18n("Connected") : i18n("Offline")
                            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                        }
                        Text {
                            visible: panel.dev && panel.dev.reachable && panel.dev.charge >= 0
                            text: "·"
                            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                        }
                        Kirigami.Icon {
                            visible: panel.dev && panel.dev.reachable && panel.dev.charge >= 0
                            source: {
                                if (!panel.dev || panel.dev.charge < 0) return "battery-missing";
                                var lvl = Math.max(0, Math.min(100, Math.round(panel.dev.charge / 10) * 10));
                                return Qt.resolvedUrl("../icons/status/phone-battery-" + ("00" + lvl).slice(-3) + (panel.dev.charging ? "-charging" : "") + ".svg");
                            }
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        Text {
                            visible: panel.dev && panel.dev.reachable && panel.dev.charge >= 0
                            text: panel.dev ? panel.dev.charge + " %" : ""
                            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                        }
                        // réseau mobile : 4 barres (force 0 à 4) + type (4G, 5G…)
                        Text {
                            visible: panel.hasNetwork
                            text: "·"
                            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                        }
                        Row {
                            visible: panel.hasNetwork
                            spacing: 1
                            Layout.alignment: Qt.AlignVCenter
                            Repeater {
                                model: 4
                                Rectangle {
                                    width: 3
                                    height: 4 + index * 2
                                    anchors.bottom: parent.bottom
                                    radius: 1
                                    color: panel.dev && index < panel.dev.netStrength
                                           ? (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A") : (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.18))
                                }
                            }
                        }
                        Text {
                            visible: panel.hasNetwork
                            text: panel.dev ? panel.dev.netType : ""
                            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                        }
                    }
                }
                PanelButton {
                    framed: false
                    iconName: "view-refresh"
                    implicitWidth: implicitHeight
                    onClicked: panel.run("kdeconnect-cli --refresh")
                    PC3.ToolTip.text: i18n("Refresh")
                    PC3.ToolTip.visible: hovered
                    PC3.ToolTip.delay: 400
                }
            }

            Rectangle {   // trait
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                height: 1
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.1))
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                columns: 3
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: Kirigami.Units.smallSpacing

                ActionTile { text: i18n("Ring");        iconName: panel.ico("ring");       active: panel.online; onClicked: panel.doRing() }
                ActionTile { text: i18n("Send files"); iconName: panel.ico("send");       active: panel.online; onClicked: panel.doFiles() }
                ActionTile { text: i18n("Browse");           iconName: panel.ico("browse");     active: panel.online; onClicked: panel.doBrowse() }
                ActionTile { text: i18n("Clipboard");      iconName: panel.ico("clipboard");  active: panel.online; onClicked: panel.doClipboard() }
                ActionTile { text: i18n("Send a link");     iconName: panel.ico("link");       active: panel.online; onClicked: { panel.linkOpen = !panel.linkOpen; if (panel.linkOpen) { panel.smsOpen = false; linkField.forceActiveFocus(); } } }
                ActionTile { text: i18n("Take a photo");   iconName: panel.ico("camera");     active: panel.online && panel.hasPhoto; onClicked: panel.doPhoto() }
                ActionTile { text: i18n("SMS");                 iconName: panel.ico("sms");        active: panel.online; onClicked: { panel.smsOpen = !panel.smsOpen; if (panel.smsOpen) { panel.linkOpen = false; smsNumber.forceActiveFocus(); } } }
                ActionTile { text: i18n("Ping");                iconName: panel.ico("ping");       active: panel.online; onClicked: panel.doPing() }
                ActionTile { text: i18n("Settings");            iconName: panel.ico("settings");   active: true;         onClicked: panel.doSettings() }
            }

            // formulaire SMS
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: panel.smsOpen && panel.online
                spacing: Kirigami.Units.smallSpacing

                Text {   // destinataire choisi
                    Layout.fillWidth: true
                    visible: panel.smsContact !== ""
                    elide: Text.ElideRight
                    text: i18n("To: %1", panel.smsContact)
                    font.weight: Font.DemiBold
                    color: Kirigami.Theme.textColor
                }
                PC3.TextField {
                    id: smsNumber
                    Layout.fillWidth: true
                    placeholderText: panel.contacts.length > 0 ? i18n("Name or number") : i18n("Phone number")
                    onTextEdited: {
                        panel.smsContact = "";
                        panel.filterContacts(text);
                    }
                    // Entrée : premier contact proposé, sinon passage au message
                    onAccepted: {
                        if (panel.smsSuggestions.length > 0) {
                            var c = panel.smsSuggestions[0];
                            text = panel.fmtNumero(c.number);
                            panel.pickContact(c);
                        }
                        smsText.forceActiveFocus();
                    }
                }
                // suggestions de contacts (6 au plus)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: panel.smsSuggestions.length > 0
                    spacing: 0
                    Repeater {
                        model: panel.smsSuggestions
                        delegate: Item {
                            id: sug
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: sugCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                            Rectangle {
                                anchors.fill: parent
                                radius: 5
                                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
                                border.width: 1
                                border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                                opacity: sugMouse.containsMouse ? 1.0 : 0.0
                            }
                            Column {
                                id: sugCol
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Kirigami.Units.smallSpacing
                                anchors.rightMargin: Kirigami.Units.smallSpacing
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: sug.modelData.name
                                    font.weight: Font.DemiBold
                                    color: Kirigami.Theme.textColor
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: panel.fmtNumero(sug.modelData.number) + (sug.modelData.type !== "" ? " · " + sug.modelData.type : "")
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                                }
                            }
                            MouseArea {
                                id: sugMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    smsNumber.text = panel.fmtNumero(sug.modelData.number);
                                    panel.pickContact(sug.modelData);
                                    smsText.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
                PC3.ScrollView {
                    id: smsScroll
                    Layout.fillWidth: true
                    // grandit avec le texte (4 à 8 unités), puis ascenseur
                    Layout.preferredHeight: Math.max(Kirigami.Units.gridUnit * 4,
                        Math.min(Kirigami.Units.gridUnit * 8,
                                 smsText.contentHeight + smsText.topPadding + smsText.bottomPadding))
                    PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff

                    PC3.TextArea {
                        id: smsText
                        placeholderText: i18n("Message")
                        wrapMode: TextEdit.Wrap
                        // la zone visible suit le curseur pendant la frappe
                        onCursorRectangleChanged: {
                            var f = smsScroll.contentItem;
                            if (!f || f.contentY === undefined) return;
                            var r = cursorRectangle;
                            if (r.y < f.contentY)
                                f.contentY = r.y;
                            else if (r.y + r.height + bottomPadding > f.contentY + f.height)
                                f.contentY = r.y + r.height + bottomPadding - f.height;
                        }
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Kirigami.Units.smallSpacing
                    PanelButton {
                        framed: false
                        text: i18n("Cancel")
                        onClicked: panel.smsOpen = false
                    }
                    PanelButton {
                        text: i18n("Send")
                        iconName: panel.ico("send")
                        enabled: !panel.smsEnCours
                        onClicked: panel.sendSms(smsNumber.text, smsText.text)
                    }
                }
            }

            // formulaire « Envoyer un lien »
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: panel.linkOpen && panel.online
                spacing: Kirigami.Units.smallSpacing

                PC3.TextField {
                    id: linkField
                    Layout.fillWidth: true
                    placeholderText: i18n("Web link or text to send")
                    onAccepted: if (panel.sendLink(text)) { text = ""; panel.linkOpen = false; }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Kirigami.Units.smallSpacing
                    PanelButton {
                        framed: false
                        text: i18n("Cancel")
                        onClicked: panel.linkOpen = false
                    }
                    PanelButton {
                        text: i18n("Send")
                        iconName: panel.ico("send")
                        onClicked: if (panel.sendLink(linkField.text)) { linkField.text = ""; panel.linkOpen = false; }
                    }
                }
            }

            // musique en cours sur le téléphone (visible seulement pendant la lecture)
            Rectangle {   // trait
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: panel.hasMedia
                height: 1
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.1))
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: panel.hasMedia
                spacing: Kirigami.Units.smallSpacing

                FluentIcon {
                    src: panel.ico("music")
                    Layout.leftMargin: -11 + panel.recentrageVolet   // Fenestra : recentrage du volet
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: panel.dev ? panel.dev.mTitle : ""
                        font.weight: Font.DemiBold
                        color: Kirigami.Theme.textColor
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        visible: text !== ""
                        text: panel.dev ? panel.dev.mArtist : ""
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                    }
                }
                PanelButton {
                    framed: false
                    press: true
                    iconName: panel.ico("previous")
                    implicitWidth: implicitHeight
                    onClicked: panel.media("Previous")
                }
                PanelButton {
                    framed: false
                    press: true
                    iconName: panel.ico(panel.dev && panel.dev.mPlaying ? "pause" : "play")
                    implicitWidth: implicitHeight
                    onClicked: panel.media("PlayPause")
                }
                PanelButton {
                    framed: false
                    press: true
                    iconName: panel.ico("next")
                    Layout.rightMargin: -7 - panel.recentrageVolet   // Fenestra : recentrage du volet
                    implicitWidth: implicitHeight
                    onClicked: panel.media("Next")
                }
            }

            // une seule ligne :  −  +   1:24 ━━━━○──── 3:52
            // (volume à gauche ; progression à droite, masquée pour un direct)
            RowLayout {
                Layout.fillWidth: true
                visible: panel.hasProgress || panel.hasVolume
                spacing: Kirigami.Units.smallSpacing

                PanelButton {   // volume : muet / son rétabli
                    visible: panel.hasVolume
                    framed: false
                    press: true
                    Layout.leftMargin: -13 + panel.recentrageVolet   // Fenestra : recentrage du volet
                    iconName: (panel.dev && panel.dev.mVolume === 0) ? Qt.resolvedUrl("../icons/status/phone-audio-volume-muted.svg") : "audio-volume-medium"
                    implicitHeight: 26
                    implicitWidth: implicitHeight
                    onClicked: panel.toggleMute()
                }
                PanelButton {   // volume : un cran de moins
                    visible: panel.hasVolume
                    framed: false
                    press: true
                    Layout.leftMargin: -3
                    iconName: panel.ico("subtract")
                    implicitHeight: 26
                    implicitWidth: implicitHeight
                    onClicked: panel.volumeStep(-7)
                }
                PanelButton {   // volume : un cran de plus
                    visible: panel.hasVolume
                    framed: false
                    press: true
                    iconName: panel.ico("add")
                    implicitHeight: 26
                    implicitWidth: implicitHeight
                    onClicked: panel.volumeStep(7)
                }
                Item {          // direct (pas de durée) : les boutons restent à gauche
                    visible: !panel.hasProgress
                    Layout.fillWidth: true
                }

                Timer {   // avance fluide entre deux lectures (toutes les 5 s)
                    interval: 1000
                    repeat: true
                    running: panel.visible && panel.hasProgress && panel.dev.mPlaying
                    onTriggered: panel.mediaPos = Math.min(panel.dev.mLength, panel.mediaPos + 1000)
                }
                Text {
                    visible: panel.hasProgress
                    Layout.leftMargin: panel.hasVolume ? Kirigami.Units.smallSpacing : 0
                    text: panel.fmtTime(panel.mediaPos)
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                }
                Item {
                    id: barre
                    visible: panel.hasProgress
                    Layout.fillWidth: true
                    implicitHeight: 14
                    readonly property real ratio: panel.hasProgress
                        ? Math.max(0, Math.min(1, panel.mediaPos / panel.dev.mLength)) : 0

                    Rectangle {   // piste
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 3; radius: 1.5
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.15))
                    }
                    Rectangle {   // partie écoulée
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * barre.ratio; height: 3; radius: 1.5
                        color: Kirigami.Theme.highlightColor
                    }
                    Rectangle {   // curseur (au survol, si on peut se déplacer)
                        visible: barreMouse.containsMouse && panel.dev && panel.dev.mSeek
                        width: 10; height: 10; radius: 5
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.width * barre.ratio - width / 2
                        color: Kirigami.Theme.highlightColor
                        border.width: 2
                        border.color: "#ffffff"
                    }
                    MouseArea {
                        id: barreMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: panel.dev && panel.dev.mSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: mouse => panel.seekTo(mouse.x / width * panel.dev.mLength)
                    }
                }
                Text {
                    visible: panel.hasProgress
                    Layout.rightMargin: -panel.recentrageVolet   // Fenestra : recentrage du volet
                    text: panel.hasProgress ? panel.fmtTime(panel.dev.mLength) : ""
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                }
            }


            // message de confirmation
            Text {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: panel.toast !== "" ? panel.toast
                      : (!panel.online ? i18n("The phone is offline: check that it is on the same network.") : "")
                visible: text !== ""
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                font.italic: panel.toast === ""
            }

            // ── Notifications ─────────────────────────────────────────────
            Rectangle {   // trait
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: panel.notifs.length > 0
                height: 1
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.1))
            }
            RowLayout {
                Layout.fillWidth: true
                visible: panel.notifs.length > 0
                Text {
                    Layout.fillWidth: true
                    text: i18n("Recent notifications")
                    font.weight: Font.DemiBold
                    color: Kirigami.Theme.textColor
                }
            }
            // les 3 plus récentes au plus (le volet est un complément), et seulement
            // celles qui tiennent entièrement dans la place restante (carte musique…)
            Item {
                id: notifZone
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: panel.notifs.length > 0
                clip: true
                Column {
                id: notifList
                width: parent.width
                spacing: 2
                Repeater {
                model: panel.notifs.slice(0, 3)

                delegate: Item {
                    id: nt
                    required property var modelData
                    width: notifList.width
                    // masquée si elle ne tient pas entièrement (pas de notification coupée)
                    readonly property bool tient: y + height <= notifZone.height
                    opacity: tient ? 1 : 0
                    enabled: tient
                    implicitHeight: ntCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                    readonly property bool enReponse: panel.notifReplying === nt.modelData.id

                    HoverHandler { id: ntHover }
                    Rectangle {
                        anchors.fill: parent
                        radius: 5
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
                        border.width: 1
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: ntHover.hovered || nt.enReponse ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Image {   // icône de l'application
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            source: nt.modelData.icon !== "" ? "file://" + nt.modelData.icon : ""
                            sourceSize.width: Kirigami.Units.iconSizes.smallMedium * 2
                            sourceSize.height: Kirigami.Units.iconSizes.smallMedium * 2
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                        ColumnLayout {
                            id: ntCol
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: nt.modelData.app
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                elide: Text.ElideRight
                                text: nt.modelData.title
                                font.weight: Font.DemiBold
                                color: Kirigami.Theme.textColor
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                wrapMode: Text.Wrap
                                maximumLineCount: nt.enReponse ? 8 : 3
                                elide: Text.ElideRight
                                text: nt.modelData.text
                                color: Kirigami.Theme.textColor
                            }
                            PanelButton {   // répondre (messageries, SMS…)
                                visible: nt.modelData.reply !== "" && !nt.enReponse
                                framed: false
                                text: i18n("Reply")
                                iconName: panel.ico("sms")
                                onClicked: {
                                    panel.notifReplying = nt.modelData.id;
                                    Qt.callLater(function () { ntReponse.forceActiveFocus(); });
                                }
                            }
                            RowLayout {     // champ de réponse
                                Layout.fillWidth: true
                                visible: nt.enReponse
                                PC3.TextField {
                                    id: ntReponse
                                    Layout.fillWidth: true
                                    placeholderText: i18n("Your reply")
                                    onAccepted: if (panel.replyNotif(nt.modelData.id, text)) text = ""
                                    Keys.onEscapePressed: panel.notifReplying = ""
                                }
                                PanelButton {
                                    iconName: panel.ico("send")
                                    implicitWidth: implicitHeight
                                    onClicked: if (panel.replyNotif(nt.modelData.id, ntReponse.text)) ntReponse.text = ""
                                }
                            }
                        }
                        PanelButton {   // retirer (le message n'est pas supprimé)
                            Layout.alignment: Qt.AlignTop
                            framed: false
                            text: "✕"
                            implicitWidth: implicitHeight
                            onClicked: panel.dismissNotif(nt.modelData.id)
                            PC3.ToolTip.text: i18n("Dismiss notification")
                            PC3.ToolTip.visible: hovered
                            PC3.ToolTip.delay: 400
                        }
                    }
                }
                }
                }
            }

            // sans notification : l'espace libre reste en bas
            Item {
                Layout.fillHeight: true
                visible: panel.notifs.length === 0
            }
        }

        // ----- Chargement -----
        PC3.BusyIndicator {
            anchors.centerIn: parent
            running: visible
            visible: !panel.loaded
        }

        // ----- Bandeau de pied : même composant et même hauteur que celui du menu -----
        PlasmaExtras.PlasmoidHeading {
            id: piedVolet
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            contentHeight: Kirigami.Units.gridUnit * 3 - 10   // même hauteur que le pied du menu
            position: PC3.ToolBar.Footer
            // le fond du bandeau va jusqu'aux bords de la fenêtre
            leftInset: -panel.margins.left
            rightInset: -panel.margins.right
            bottomInset: -panel.margins.bottom

            // « ··· » comme sous Windows 11 : menu d'options
            PanelButton {
                id: plusBouton
                anchors.right: parent.right
                anchors.rightMargin: Kirigami.Units.gridUnit + panel.recentrageVolet   // Fenestra : recentrage du volet
                anchors.verticalCenter: parent.verticalCenter
                framed: false
                text: "···"
                implicitWidth: implicitHeight * 1.4
                onClicked: plusMenu.visible = !plusMenu.visible
                PC3.ToolTip.text: i18n("More options")
                PC3.ToolTip.visible: hovered && !plusMenu.visible   // Fenestra : infobulle masquée menu ouvert
                PC3.ToolTip.delay: 400
            }
        }

        // fenêtre « ··· » : même type et même présentation que la fenêtre Alimentation
        PlasmaCore.Dialog {
            id: plusMenu
            flags: Qt.WindowStaysOnTopHint
            location: PlasmaCore.Types.Floating
            hideOnWindowDeactivate: true
            visible: false

            // ouverte : le volet et le menu restent ouverts (même principe qu'Alimentation)
            onVisibleChanged: {
                if (visible) {
                    panel.hold = true;
                    Qt.callLater(plusMenu.reposition);
                } else {
                    panel.hold = false;
                }
            }

            // au-dessus du bouton, alignée sur son bord droit
            function reposition() {
                var pos = plusBouton.mapToGlobal(plusBouton.width, 0);
                x = Math.round(pos.x - width);
                y = Math.round(pos.y - height - Kirigami.Units.smallSpacing);
            }

            mainItem: ColumnLayout {
                spacing: 0
                PlusItem {
                    label: i18n("Open KDE Connect")
                    // même icône que le bouton KDE Connect du menu
                    iconeFichier: Qt.resolvedUrl("../icons/status/fenestra-kdeconnect.svg")
                    onClicked: { plusMenu.visible = false; panel.run("kdeconnect-app"); }
                }
                PlusItem {
                    label: i18n("KDE Connect settings")
                    icone: "settings"
                    onClicked: { plusMenu.visible = false; panel.run("systemsettings kcm_kdeconnect"); }
                }
                PlusItem {
                    label: i18n("Hide this panel")
                    icone: "subtract"
                    onClicked: { plusMenu.visible = false; Plasmoid.configuration.kdeConnectPanelOn = false; panel.close(); }
                }
            }
        }
    }
}
