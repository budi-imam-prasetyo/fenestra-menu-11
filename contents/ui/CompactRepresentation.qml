/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Modified by naykkalak (2026) for Fenestra Menu 11, a fork of Menu 11 Next by Eisteed.
 * The original notice below is kept. This file is GPL-2.0-or-later;
 * Fenestra Menu 11 as a whole is distributed under GPL-3.0-or-later.
 */
/***************************************************************************
 *   Copyright (C) 2013-2014 by Eike Hein <hein@kde.org>                   *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA .        *
 ***************************************************************************/
import QtQuick 2.0
import QtQuick.Layouts 1.1
import org.kde.plasma.plasmoid
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

Item {
    id: root
    readonly property var screenGeometry: plasmoid.screenGeometry
    readonly property bool inPanel: (plasmoid.location == PlasmaCore.Types.TopEdge
    || plasmoid.location == PlasmaCore.Types.RightEdge
    || plasmoid.location == PlasmaCore.Types.BottomEdge
    || plasmoid.location == PlasmaCore.Types.LeftEdge)
    readonly property bool vertical: (plasmoid.formFactor == PlasmaCore.Types.Vertical)
    readonly property bool useCustomButtonImage: (Plasmoid.configuration.useCustomButtonImage
    && Plasmoid.configuration.customButtonImage.length != 0)
    property QtObject dashWindow: null

    // ── « Oreille » posée sur la barre (même principe que Panel Colorizer) ──
    // Le bouton Démarrer est dessiné DANS la fenêtre de la barre : on remonte
    // jusqu'à l'élément racine de cette fenêtre et on y pose une poignée
    // PASSIVE, qui entend chaque clic sur la barre sans jamais l'intercepter.
    // Un clic sur la barre (espace vide compris) ferme alors le menu ; le volet
    // KDE Connect suit automatiquement. Le clic sur le bouton Démarrer lui-même
    // est ignoré (il gère déjà l'ouverture/fermeture).
    property QtObject panelEar: null

    function barRoot() {
        var p = root;
        while (p.parent) p = p.parent;
        return p;
    }

    // remise à zéro de l'oreille : si le relâchement d'un clic s'est perdu
    // (une fenêtre s'est fermée pendant l'appui), elle resterait « appuyée »
    // et n'entendrait plus rien -> mêmes symptômes que la barre de recherche.
    function resetEar() {
        if (!panelEar) return;
        panelEar.enabled = false;
        panelEar.enabled = true;
    }

    // ── Oreille PARTAGÉE entre le menu Démarrer et la capsule ──
    // Deux PointHandler posés sur le même élément se volent le clic :
    // celui qui le saisit prive l'autre, qui devient sourd. On n'en pose
    // donc qu'UN SEUL sur la barre, repéré par son objectName, et chaque
    // widget vient y brancher son écoute.
    function oreillePartagee(top) {
        var nom = "fenestraOreilleBarre";
        for (var i = 0; i < top.data.length; i++) {
            var o = top.data[i];
            if (o && o.objectName === nom) return o;
        }
        return Qt.createQmlObject(
            "import QtQuick\nPointHandler { objectName: \"fenestraOreilleBarre\"; acceptedButtons: Qt.LeftButton | Qt.RightButton }",
            top, nom);
    }

    function ensureEar() {
        var top = barRoot();
        if (!top || top === root) return;              // pas encore dans la barre
        if (panelEar && panelEar.parent === top) return; // déjà posée
        panelEar = root.oreillePartagee(top);
        panelEar.activeChanged.connect(function() {
            if (!panelEar || !panelEar.active) return;          // seulement à l'appui
            Qt.callLater(root.resetEar);                       // repart propre pour le clic suivant
            if (!dashWindow || !dashWindow.visible) return;
            var s = panelEar.point.scenePosition;
            var l = root.mapFromItem(null, s.x, s.y);
            if (l.x >= 0 && l.y >= 0 && l.x < root.width && l.y < root.height)
                return;                                          // bouton Démarrer
            dashWindow.visible = false;
        });
    }

    Component.onDestruction: panelEar = null   // oreille partagée : on ne la détruit pas

    // ── Fenêtre réduite ou fermée pendant que le menu est ouvert ──
    // Plasma laisse le menu ouvert dans ce cas (même comportement avec Kickoff) ;
    // Windows 11 le ferme. On surveille la liste des fenêtres (celle de la barre
    // des tâches) : une fenêtre qui passe à « réduite » ou qui disparaît ferme le
    // menu (le volet KDE Connect suit). Le menu et le volet n'y figurent pas.
    property var etatReduit: ({})

    function cleFenetre(row) {
        var idx = fenetres.makeModelIndex(row);
        return String(fenetres.data(idx, TaskManager.AbstractTasksModel.WinIdList));
    }

    function relever(fermerSiReduite) {
        var nouveau = {};
        var ferme = false;
        for (var r = 0; r < fenetres.count; r++) {
            var k = cleFenetre(r);
            var red = fenetres.data(fenetres.makeModelIndex(r),
                                    TaskManager.AbstractTasksModel.IsMinimized) === true;
            nouveau[k] = red;
            if (fermerSiReduite && red && etatReduit[k] === false) ferme = true;
        }
        etatReduit = nouveau;
        if (ferme) fermerMenu();
    }

    function fermerMenu() {
        if (dashWindow && dashWindow.visible) dashWindow.visible = false;
    }

    TaskManager.TasksModel {
        id: fenetres
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByScreen: false
        filterByActivity: false

        onDataChanged: root.relever(true)
        onRowsInserted: root.relever(false)
        onRowsRemoved: {
            root.relever(false);
            root.fermerMenu();          // une fenêtre a été fermée
        }
    }
    Plasmoid.status: dashWindow && dashWindow.visible ? PlasmaCore.Types.RequiresAttentionStatus : PlasmaCore.Types.PassiveStatus

    Rectangle {
        id: activeShadow
        anchors.fill: parent
        radius: 12
        color: "black"
        opacity: (dashWindow && dashWindow.visible) ? 0.12 : 0.0
    }

    Rectangle {
        id: activeBackground
        anchors.fill: parent
        anchors.leftMargin: -5
        anchors.rightMargin: -5
        anchors.topMargin: -4      // 1 px de moins en haut
        anchors.bottomMargin: -4   // 1 px de moins en bas
        radius: 5
        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
        border.width: 1
        border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
        opacity: ((dashWindow && dashWindow.visible) || mouseArea.containsMouse) ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
        }
    }

    Kirigami.Icon {
        id: buttonIcon
        anchors.fill: parent
        source: useCustomButtonImage ? Plasmoid.configuration.customButtonImage : Plasmoid.configuration.icon
        active: false
        smooth: true
        scale: mouseArea.pressed ? 0.85 : 1.0

        Behavior on scale {
            NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            dashWindow.visible = !dashWindow.visible;
        }
    }

    Component.onCompleted: {
        dashWindow = Qt.createQmlObject("MenuRepresentation {}", root);
        // l'oreille est posée à la première ouverture du menu (la barre est prête)
        dashWindow.visibleChanged.connect(function() {
            if (dashWindow.visible) {
                root.ensureEar();
                root.resetEar();        // oreille propre à chaque ouverture
                root.relever(false);    // état de départ des fenêtres
            }
        });
        plasmoid.activated.connect(function() {
            dashWindow.visible = !dashWindow.visible;
        });
    }
}
