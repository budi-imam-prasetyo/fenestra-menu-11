/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Part of Fenestra Menu 11 (naykkalak, 2026), a fork of Menu 11 Next by Eisteed,
 * itself based on Menu 11 / Ditto Menu by adhe (GPL-2.0-or-later).
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import QtCore
import Qt5Compat.GraphicalEffects

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support

import org.kde.plasma.private.kicker 0.1 as Kicker
import org.kde.coreaddons 1.0 as KCoreAddons
import org.kde.plasma.private.shell

import org.kde.kwindowsystem
import org.kde.kquickcontrolsaddons

import org.kde.plasma.components as PlasmaComponents3


import org.kde.kirigami as Kirigami
import org.kde.plasma.private.sessions

RowLayout{

    Logic { id: monLogic; core: root.core }

    property var core: null

    spacing: Kirigami.Units.largeSpacing

    signal tabOut

    // ferme les fenêtres du pied (Compte, autres comptes, Alimentation) ;
    // appelée par MenuRepresentation.qml quand le menu se ferme
    function closeMenus() {
        usersMenu.visible = false;
        accountMenu.visible = false;
        powerMenu.visible = false;
    }

    function requestHibernate() {
        powerMenu.visible = false;
        if (sessionManager.canHibernate && typeof sessionManager.hibernate === "function") {
            try {
                sessionManager.hibernate();
                return;
            } catch (e) {
                console.warn("fenestra-menu11: KDE hibernate failed:", e);
            }
        }
        if (!hibernateProbe.requestHibernate()) {
            console.warn("fenestra-menu11: hibernate is not available");
        }
    }

    Keys.onTabPressed: event => {
        event.accepted = true;
        tabOut();
    }

    KCoreAddons.KUser {   id: kuser  }
    //Logic {   id: logic }

    SessionManagement {
        id: sessionManager
    }

    HibernateProbe {
        id: hibernateProbe
        powerSession: sessionManager
        core: root.core
    }

    readonly property bool hibernateAvailable: hibernateProbe.hibernateAvailable

    // ── Lanceur de commande shell (ex: ouvrir les Paramètres système)
    Plasma5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: (sourceName, data) => disconnectSource(sourceName)
        function run(cmd) { connectSource(cmd) }
    }

    // ── Liste des autres comptes locaux (uid >= 1000, hors utilisateur courant
    // et hors comptes sans shell de connexion) - relue à chaque ouverture du
    // popup "Autres utilisateurs" via refresh()
    Plasma5Support.DataSource {
        id: usersCheck
        engine: "executable"
        connectedSources: []
        property var users: []
        Component.onCompleted: refresh()
        readonly property string cmd: "getent passwd | awk -F: -v OFS='|' '$3>=1000 && $3<60000 && $7!~/nologin|false/ {print $1,$5}'"

        // Chaque refresh utilise une source légèrement différente (commentaire
        // shell horodaté, ignoré à l'exécution) pour empêcher le moteur
        // "executable" de resservir l'ancienne réponse mise en cache.
        property string currentSource: ""

        function refresh() {
            if (currentSource !== "") {
                disconnectSource(currentSource);
            }
            currentSource = cmd + " #" + Date.now();
            connectSource(currentSource);
        }

        onNewData: (sourceName, data) => {
            var out = ((data["stdout"] || "") + "").trim();
            var list = [];
            if (out !== "") {
                var lines = out.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split("|");
                    var login = parts[0];
                    if (login === "" || login === kuser.loginName) {
                        continue;
                    }
                    var full = (parts[1] || "").split(",")[0].trim();
                    list.push({ login: login, name: full !== "" ? full : login });
                }
            }
            users = list;
        }
    }

    // ── Bouton "Compte" - avatar + nom. Ouvre la fenêtre Compte
    // (logo distribution, avatar, nom, type de compte, liens).
    //
    // Pour éviter que le menu principal se referme quand cette fenêtre
    // prend le focus, les deux signaux ci-dessous doivent être connectés
    // dans MenuRepresentation.qml :
    //   onAccountMenuAboutToOpen: root.hideOnWindowDeactivate = false
    //   onAccountMenuClosed:      root.hideOnWindowDeactivate = true
    signal accountMenuAboutToOpen
    signal accountMenuClosed

    Item {
        id: accountButton
        // cadre-compte-v1 : même style que le bouton Alimentation
        implicitWidth: userInfoRow.implicitWidth + 20
        implicitHeight: userInfoRow.implicitHeight + 8
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: 15 // cadre-compte-v2 : 25 - 10 (le cadre déborde, l'avatar reste en place)

        Rectangle {
            anchors.fill: parent
            radius: 5
            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
            border.width: 1
            border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
            opacity: (accountMouse.containsMouse || accountMouse.pressed || accountMenu.visible) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }

        RowLayout {
            id: userInfoRow
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter

            Item {
                id: avatarMaskContainer
                width: 36
                height: 36
                Layout.alignment: Qt.AlignVCenter

                Image {
                    id: iconUser
                    anchors.fill: parent
                    source: {
                        var faceUrl = kuser.faceIconUrl.toString()
                        if (faceUrl !== "") {
                            return faceUrl
                        }
                        return Qt.resolvedUrl("../icons/status/fenestra-avatar.svg")   // Fenestra 1.1 : avatar par défaut
                    }
                    cache: false
                    visible: false
                    sourceSize.width: 36
                    sourceSize.height: 36
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                }

                Rectangle {
                    id: avatarRoundMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                }

                OpacityMask {
                    anchors.fill: parent
                    source: iconUser
                    maskSource: avatarRoundMask
                    visible: iconUser.source !== ""
                }
            }

            Text {
                Layout.leftMargin: 5   // Fenestra : nom écarté de l'avatar
                wrapMode: Text.NoWrap
                color: Kirigami.Theme.textColor
                font: Kirigami.Theme.defaultFont
                text: qsTr(kuser.fullName)
            }
        }

        MouseArea {
            id: accountMouse
            hoverEnabled: true
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                usersCheck.refresh();
                accountMenuAboutToOpen();
                accountMenu.visible = true;
            }
        }

        PlasmaCore.Dialog {
            id: accountMenu
            flags: Qt.WindowStaysOnTopHint
            location: PlasmaCore.Types.Floating
            hideOnWindowDeactivate: true

            onVisibleChanged: {
                if (visible) {
                    Qt.callLater(accountMenu.reposition);
                } else {
                    usersMenu.visible = false;
                    accountMenuClosed();
                }
            }

            function reposition() {
                // Centré horizontalement sur le bouton, ouvert vers le HAUT :
                // le bouton Compte est dans la même barre du bas que le
                // bouton Alimentation, tout en bas de l'écran, donc il n'y a
                // de place que vers le haut (comme pour le menu Alimentation).
                var pos = accountButton.mapToGlobal(accountButton.width / 2, 0);
                x = Math.round(pos.x - width / 2);
                y = Math.round(pos.y - height - Kirigami.Units.smallSpacing);
            }

            mainItem: ColumnLayout {
                width: 340
                spacing: Kirigami.Units.largeSpacing

                // ── Ligne du haut : logo distro à gauche, "Se déconnecter" à droite
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing + 6
                    Layout.rightMargin: Kirigami.Units.smallSpacing + 6
                    Layout.topMargin: Kirigami.Units.smallSpacing + 1

                    Image {
                        id: distroLogo
                        property bool primaryFailed: false
                        // Fenestra 1.1 : aucun logo de distribution n'est chargé (élément gardé vide)
                        source: ""
                        visible: false   // Fenestra : logo de distribution masqué
                        onStatusChanged: {
                            if (status === Image.Error && !primaryFailed) {
                                primaryFailed = true;
                            }
                        }
                        fillMode: Image.PreserveAspectFit
                        Layout.preferredHeight: 20
                        Layout.alignment: Qt.AlignVCenter
                        sourceSize.height: 20
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        id: logoutButton
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: logoutLabel.implicitWidth + 20
                        implicitHeight: logoutLabel.implicitHeight + 12
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, logoutMouse.containsMouse ? 0.07 : 0.0) : Qt.rgba(0, 0, 0, logoutMouse.containsMouse ? 0.07 : 0.0))
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            id: logoutLabel
                            anchors.centerIn: parent
                            text: i18n("Sign out")
                            color: Kirigami.Theme.textColor
                            font.family: Kirigami.Theme.defaultFont.family
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize || 10
                        }

                        MouseArea {
                            id: logoutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                accountMenu.visible = false;
                                sessionManager.requestLogout();
                            }
                        }
                    }

                    // ── Bouton "..." (trois petits points) - action : verrouiller la session
                    Rectangle {
                        id: moreButton
                        Layout.alignment: Qt.AlignVCenter
                        visible: usersCheck.users.length > 0
                        implicitWidth: 32
                        implicitHeight: logoutButton.implicitHeight
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(1, 1, 1, (moreMouse.containsMouse || usersMenu.visible) ? 0.07 : 0.0) : Qt.rgba(0, 0, 0, (moreMouse.containsMouse || usersMenu.visible) ? 0.07 : 0.0))
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 3

                            Repeater {
                                model: 3
                                Rectangle {
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: Kirigami.Theme.textColor
                                }
                            }
                        }

                        MouseArea {
                            id: moreMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (usersMenu.visible) {
                                    usersMenu.visible = false;
                                    return;
                                }
                                usersCheck.refresh();
                                // Empêche la fenêtre Compte de se fermer quand
                                // le popup prend le focus
                                accountMenu.hideOnWindowDeactivate = false;
                                usersMenu.visible = true;
                            }
                        }

                        // ── Popup "Autres utilisateurs" - petite fenêtre
                        // système séparée, placée SOUS le bouton "..."
                        PlasmaCore.Dialog {
                            id: usersMenu
                            flags: Qt.WindowStaysOnTopHint
                            location: PlasmaCore.Types.Floating
                            hideOnWindowDeactivate: true

                            onVisibleChanged: {
                                if (visible) {
                                    Qt.callLater(usersMenu.reposition);
                                } else {
                                    accountMenu.hideOnWindowDeactivate = true;
                                    if (accountMenu.visible) {
                                        accountMenu.requestActivate();
                                    }
                                }
                            }

                            function reposition() {
                                // Bord gauche aligné sur le bouton "...",
                                // juste en dessous de lui
                                var pos = moreButton.mapToGlobal(0, moreButton.height);
                                x = Math.round(pos.x);
                                y = Math.round(pos.y + Kirigami.Units.smallSpacing);
                            }

                            mainItem: ColumnLayout {
                                width: 260
                                spacing: 0

                                Text {
                                    Layout.leftMargin: Kirigami.Units.smallSpacing + 6
                                    Layout.rightMargin: Kirigami.Units.smallSpacing + 6
                                    Layout.topMargin: Kirigami.Units.smallSpacing + 6
                                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                                    text: i18n("Other users")
                                    color: Kirigami.Theme.disabledTextColor
                                    font.family: Kirigami.Theme.defaultFont.family
                                    font.pointSize: (Kirigami.Theme.defaultFont.pointSize || 10) - 1
                                }

                                Repeater {
                                    model: usersCheck.users

                                    delegate: PlasmaComponents3.ItemDelegate {
                                        id: userDelegate
                                        Layout.fillWidth: true
                                        hoverEnabled: true
                                        leftPadding: Kirigami.Units.smallSpacing + 6
                                        rightPadding: Kirigami.Units.smallSpacing + 6
                                        topPadding: Kirigami.Units.smallSpacing
                                        bottomPadding: Kirigami.Units.smallSpacing

                                        background: Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            radius: Kirigami.Units.smallSpacing
                                            color: Kirigami.Theme.highlightColor
                                            opacity: userDelegate.hovered ? 0.18 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 100 } }
                                        }

                                        contentItem: RowLayout {
                                            spacing: Kirigami.Units.largeSpacing

                                            Item {
                                                Layout.preferredWidth: 32
                                                Layout.preferredHeight: 32
                                                Layout.alignment: Qt.AlignVCenter

                                                Image {
                                                    id: otherFace
                                                    property bool failed: false
                                                    anchors.fill: parent
                                                    source: failed
                                                        ? Qt.resolvedUrl("../icons/status/fenestra-avatar.svg")   // Fenestra 1.1 : avatar par défaut
                                                        : ("file:///var/lib/AccountsService/icons/" + modelData.login)
                                                    onStatusChanged: {
                                                        if (status === Image.Error && !failed) {
                                                            failed = true;
                                                        }
                                                    }
                                                    visible: false
                                                    sourceSize.width: 32
                                                    sourceSize.height: 32
                                                    fillMode: Image.PreserveAspectCrop
                                                    layer.enabled: true
                                                }

                                                Rectangle {
                                                    id: otherFaceMask
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    visible: false
                                                }

                                                OpacityMask {
                                                    anchors.fill: parent
                                                    source: otherFace
                                                    maskSource: otherFaceMask
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                text: modelData.name
                                                elide: Text.ElideRight
                                                color: Kirigami.Theme.textColor
                                                font.family: Kirigami.Theme.defaultFont.family
                                                font.pointSize: Kirigami.Theme.defaultFont.pointSize || 10
                                            }
                                        }

                                        onClicked: {
                                            accountMenu.visible = false;
                                            usersMenu.visible = false;
                                            // Ouvre le changement d'utilisateur
                                            // (écran de connexion)
                                            if (typeof sessionManager.switchUser === "function") {
                                                sessionManager.switchUser();
                                            } else {
                                                sessionManager.lock();
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: usersCheck.users.length === 0
                                    Layout.leftMargin: Kirigami.Units.smallSpacing + 6
                                    Layout.rightMargin: Kirigami.Units.smallSpacing + 6
                                    Layout.bottomMargin: Kirigami.Units.smallSpacing + 6
                                    text: i18n("No other users")
                                    color: Kirigami.Theme.textColor
                                    font.family: Kirigami.Theme.defaultFont.family
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize || 10
                                }
                            }
                        }
                    }
                }

                // ── Avatar + nom + type de compte + lien
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing + 6
                    Layout.rightMargin: Kirigami.Units.smallSpacing + 6
                    Layout.bottomMargin: Kirigami.Units.smallSpacing + 6
                    spacing: Kirigami.Units.largeSpacing

                    Item {
                        id: accountAvatarMaskContainer
                        width: 64
                        height: 64
                        Layout.alignment: Qt.AlignVCenter

                        Image {
                            id: accountAvatarImg
                            anchors.fill: parent
                            source: iconUser.source
                            cache: false
                            visible: false
                            sourceSize.width: 64
                            sourceSize.height: 64
                            fillMode: Image.PreserveAspectCrop
                            layer.enabled: true
                        }

                        Rectangle {
                            id: accountAvatarRoundMask
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                        }

                        OpacityMask {
                            anchors.fill: parent
                            source: accountAvatarImg
                            maskSource: accountAvatarRoundMask
                            visible: accountAvatarImg.source !== ""
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        Text {
                            text: qsTr(kuser.fullName)
                            color: Kirigami.Theme.textColor
                            font.family: Kirigami.Theme.defaultFont.family
                            font.bold: true
                            font.pointSize: (Kirigami.Theme.defaultFont.pointSize || 10) + 3
                        }

                        Text {
                            text: i18n("Local account")
                            color: Kirigami.Theme.disabledTextColor
                            font.family: Kirigami.Theme.defaultFont.family
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize || 10
                        }

                        Text {
                            id: manageLink
                            text: i18n("Manage my account")
                            color: Kirigami.Theme.linkColor
                            font.family: Kirigami.Theme.defaultFont.family
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize || 10
                            font.underline: manageMouse.containsMouse

                            MouseArea {
                                id: manageMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    accountMenu.visible = false;
                                    runner.run("kcmshell6 kcm_users");
                                }
                            }
                        }
                    }
                }
            }
        }
    }


    Item{
        Layout.fillWidth: true
    }

    // ── Bouton "Alimentation" unique - ouvre une fenêtre système séparée
    // (PlasmaCore.Dialog), pas un Popup intégré, pour pouvoir rester
    // parfaitement centrée sur le bouton même si elle dépasse les limites
    // de la fenêtre principale du menu (qui, elle, ne peut pas afficher de
    // contenu hors de ses propres bords).
    //
    // Pour éviter que le menu principal se referme quand cette seconde
    // fenêtre prend le focus (hideOnWindowDeactivate en cascade), les deux
    // signaux ci-dessous doivent être connectés dans MenuRepresentation.qml :
    //   onPowerMenuAboutToOpen: root.hideOnWindowDeactivate = false
    //   onPowerMenuClosed:      root.hideOnWindowDeactivate = true
    signal powerMenuAboutToOpen
    signal powerMenuClosed

    PlasmaComponents3.ToolButton {
        id: powerButton
        icon.width: 22
        icon.height: 22
        icon.source: Qt.resolvedUrl("../icons/status/system-shutdown-v2.svg")   // Fenestra : icône d'alimentation du widget
        Layout.rightMargin: 27 // 20 + 5 + 2 points supplémentaires
        // cadre-alimentation-v1 : carré de la hauteur du bloc utilisateur,
        // même style que les boutons d'applis de la barre des tâches
        Layout.preferredWidth: accountButton.implicitHeight - 3   // Fenestra : cadre Alimentation réduit
        Layout.preferredHeight: accountButton.implicitHeight - 3
        Layout.alignment: Qt.AlignVCenter
        background: Rectangle {
            radius: 5
            color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
            border.width: 1
            border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
            opacity: (powerButton.hovered || powerButton.down || powerMenu.visible) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
        // enfoncement-alimentation-v1 : l'icône s'enfonce au clic (comme le bouton Démarrer)
        contentItem: Item {
            implicitWidth: powerButton.icon.width
            implicitHeight: powerButton.icon.height
            Kirigami.Icon {
                anchors.centerIn: parent
                width: powerButton.icon.width
                height: powerButton.icon.height
                source: powerButton.icon.source
                active: false
                isMask: true   // couleur du texte du thème
                color: Kirigami.Theme.textColor
                scale: powerButton.down ? 0.85 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }
            }
        }
        PlasmaComponents3.ToolTip.delay: 1000
        PlasmaComponents3.ToolTip.timeout: 1000
        PlasmaComponents3.ToolTip.visible: hovered && !powerMenu.visible
        PlasmaComponents3.ToolTip.text: i18n("Power")
        visible: sessionManager.canLock || sessionManager.canSuspend || (hibernateAvailable && Plasmoid.configuration.showHibernateButton) || sessionManager.canReboot || sessionManager.canShutdown

        onClicked: {
            hibernateProbe.refresh();
            powerMenuAboutToOpen();
            powerMenu.visible = true;
        }

        PlasmaCore.Dialog {
            id: powerMenu
            flags: Qt.WindowStaysOnTopHint
            location: PlasmaCore.Types.Floating
            hideOnWindowDeactivate: true

            onVisibleChanged: {
                if (visible) {
                    Qt.callLater(powerMenu.reposition);
                } else {
                    powerMenuClosed();
                }
            }

            function reposition() {
                // Centré horizontalement sur le bouton, ouvert vers le haut.
                // Fenêtre système distincte : peut déborder librement du
                // cadre du menu principal si elle s'élargit, sans jamais
                // être tronquée.
                var pos = powerButton.mapToGlobal(powerButton.width / 2, 0);
                x = Math.round(pos.x - width / 2);
                y = Math.round(pos.y - height - Kirigami.Units.smallSpacing);
            }

            mainItem: ColumnLayout {
                spacing: 0

                PlasmaComponents3.ItemDelegate {
                    Layout.fillWidth: true
                    visible: sessionManager.canLock
                    hoverEnabled: true
                    spacing: Kirigami.Units.smallSpacing + 6
                    leftPadding: Kirigami.Units.smallSpacing + 6
                    rightPadding: Kirigami.Units.smallSpacing + 6
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    icon.width: 22
                    icon.height: 22
                    icon.source: Qt.resolvedUrl("../icons/status/system-lock-screen-v2.svg")   // Fenestra : icône d'alimentation du widget
                    contentItem: RowLayout {   // icône à la couleur du texte du thème
                        spacing: parent ? parent.spacing : Kirigami.Units.smallSpacing + 6
                        Kirigami.Icon {
                            source: Qt.resolvedUrl("../icons/status/system-lock-screen-v2.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        PlasmaComponents3.Label {
                            text: parent.parent ? parent.parent.text : ""
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    text: i18n("Lock")
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") // surlignement-alim-v1
                        border.width: 1                 // même bordure que les autres surlignements
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: parent.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    onClicked: {
                        powerMenu.visible = false;
                        sessionManager.lock();
                    }
                }
                PlasmaComponents3.ItemDelegate {
                    Layout.fillWidth: true
                    visible: sessionManager.canSuspend && Plasmoid.configuration.showSleepButton
                    hoverEnabled: true
                    spacing: Kirigami.Units.smallSpacing + 6
                    leftPadding: Kirigami.Units.smallSpacing + 6
                    rightPadding: Kirigami.Units.smallSpacing + 6
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    icon.width: 22
                    icon.height: 22
                    icon.source: Qt.resolvedUrl("../icons/status/system-suspend-v2.svg")   // Fenestra : icône d'alimentation du widget
                    contentItem: RowLayout {   // icône à la couleur du texte du thème
                        spacing: parent ? parent.spacing : Kirigami.Units.smallSpacing + 6
                        Kirigami.Icon {
                            source: Qt.resolvedUrl("../icons/status/system-suspend-v2.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        PlasmaComponents3.Label {
                            text: parent.parent ? parent.parent.text : ""
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    text: i18n("Sleep")
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") // surlignement-alim-v1
                        border.width: 1                 // même bordure que les autres surlignements
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: parent.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    onClicked: {
                        powerMenu.visible = false;
                        sessionManager.suspend();
                    }
                }
                PlasmaComponents3.ItemDelegate {
                    Layout.fillWidth: true
                    visible: hibernateAvailable && Plasmoid.configuration.showHibernateButton
                    hoverEnabled: true
                    spacing: Kirigami.Units.smallSpacing + 6
                    leftPadding: Kirigami.Units.smallSpacing + 6
                    rightPadding: Kirigami.Units.smallSpacing + 6
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    icon.width: 22
                    icon.height: 22
                    icon.source: Qt.resolvedUrl("../icons/status/system-hibernate-v2.svg")   // Fenestra : icône d'alimentation du widget
                    contentItem: RowLayout {   // icône à la couleur du texte du thème
                        spacing: parent ? parent.spacing : Kirigami.Units.smallSpacing + 6
                        Kirigami.Icon {
                            source: Qt.resolvedUrl("../icons/status/system-hibernate-v2.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        PlasmaComponents3.Label {
                            text: parent.parent ? parent.parent.text : ""
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    text: i18n("Hibernate")
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") // surlignement-alim-v1
                        border.width: 1                 // même bordure que les autres surlignements
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: parent.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    onClicked: requestHibernate()
                }
                PlasmaComponents3.ItemDelegate {
                    Layout.fillWidth: true
                    visible: sessionManager.canShutdown && Plasmoid.configuration.showShutdownButton
                    hoverEnabled: true
                    spacing: Kirigami.Units.smallSpacing + 6
                    leftPadding: Kirigami.Units.smallSpacing + 6
                    rightPadding: Kirigami.Units.smallSpacing + 6
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    icon.width: 22
                    icon.height: 22
                    icon.source: Qt.resolvedUrl("../icons/status/system-shutdown-v2.svg")   // Fenestra : icône d'alimentation du widget
                    contentItem: RowLayout {   // icône à la couleur du texte du thème
                        spacing: parent ? parent.spacing : Kirigami.Units.smallSpacing + 6
                        Kirigami.Icon {
                            source: Qt.resolvedUrl("../icons/status/system-shutdown-v2.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        PlasmaComponents3.Label {
                            text: parent.parent ? parent.parent.text : ""
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    text: i18n("Shut down")
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") // surlignement-alim-v1
                        border.width: 1                 // même bordure que les autres surlignements
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: parent.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    onClicked: {
                        powerMenu.visible = false;
                        sessionManager.requestShutdown();
                    }
                }
                PlasmaComponents3.ItemDelegate {
                    Layout.fillWidth: true
                    visible: sessionManager.canReboot && Plasmoid.configuration.showRestartButton
                    hoverEnabled: true
                    spacing: Kirigami.Units.smallSpacing + 6
                    leftPadding: Kirigami.Units.smallSpacing + 6
                    rightPadding: Kirigami.Units.smallSpacing + 6
                    topPadding: Kirigami.Units.smallSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    icon.width: 22
                    icon.height: 22
                    icon.source: Qt.resolvedUrl("../icons/status/system-reboot-v2.svg")   // Fenestra : icône d'alimentation du widget
                    contentItem: RowLayout {   // icône à la couleur du texte du thème
                        spacing: parent ? parent.spacing : Kirigami.Units.smallSpacing + 6
                        Kirigami.Icon {
                            source: Qt.resolvedUrl("../icons/status/system-reboot-v2.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                        PlasmaComponents3.Label {
                            text: parent.parent ? parent.parent.text : ""
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    text: i18n("Restart")
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Kirigami.Units.smallSpacing
                        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") // surlignement-alim-v1
                        border.width: 1                 // même bordure que les autres surlignements
                        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                        opacity: parent.hovered ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                    onClicked: {
                        powerMenu.visible = false;
                        sessionManager.requestReboot();
                    }
                }
            }
        }
    }

    
}
