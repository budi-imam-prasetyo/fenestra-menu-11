/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Modified by naykkalak (2026) for Fenestra Menu 11, a fork of Menu 11 Next by Eisteed.
 * The original notice below is kept. This file is GPL-2.0-or-later;
 * Fenestra Menu 11 as a whole is distributed under GPL-3.0-or-later.
 */
/***************************************************************************
 *   Copyright (C) 2014 by Weng Xuetian <wengxt@gmail.com>
 *   Copyright (C) 2013-2017 by Eike Hein <hein@kde.org>                   *
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

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.kicker 0.1 as Kicker
import org.kde.kquickcontrolsaddons 2.0

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kitemmodels 1.0 as KItemModels
import org.kde.coreaddons 1.0 as KCoreAddons
import "code/plugins.js" as PluginSystem

PlasmaCore.Dialog {
    id: root

    objectName: "popupWindow"
    // Optional Rust accelerator, supplied by main.qml / CompactRepresentation.
    property var core: null
    flags: Qt.WindowStaysOnTopHint
    location: {
        if (Plasmoid.configuration.displayPosition === 1)
            return PlasmaCore.Types.Floating;
        else if (Plasmoid.configuration.displayPosition === 2)
            return PlasmaCore.Types.BottomEdge;
        else
            return Plasmoid.location;
    }
    hideOnWindowDeactivate: true

    // Ensure minimum dimensions to prevent empty dialog error
    // Fenestra : largeur de la fenêtre donnée à l'ouverture (voir onVisibleChanged)
    height: Math.max(rootItem.height, 200)

    // Fenestra : colonnes automatiques : 6 sous 1900 px, 7 pour un écran 1920, 8 à partir de 2500 px
    // (largeur de l'écran en pixels logiques, mise à l'échelle comprise)
    readonly property int colonnesAuto: {
        var w = kicker.screenGeometry.width;
        if (w >= 2500) return 8;
        if (w >= 1900) return 7;
        return 6;
    }

    property int iconSize: {
        switch (Plasmoid.configuration.appsIconSize) {
        case 0:
            return Kirigami.Units.iconSizes.smallMedium;
        case 1:
            return Kirigami.Units.iconSizes.medium;
        case 2:
            return Kirigami.Units.iconSizes.large;
        case 3:
            return Kirigami.Units.iconSizes.huge;
        default:
            return 64;
        }
    }

    property int cellSizeHeight: iconSize + Kirigami.Units.gridUnit * 2 + (2 * Math.max(highlightItemSvg.margins.top + highlightItemSvg.margins.bottom, highlightItemSvg.margins.left + highlightItemSvg.margins.right))
    property int cellSizeWidth: cellSizeHeight + Kirigami.Units.gridUnit

    property bool searching: searchField.text.trim().length > 0

    onSearchingChanged: {
        if (searching) {
            view.currentIndex = 1;
        } else {
            view.currentIndex = 0;
            kicker.searchRunnerFilter = "all";
        }
    }
    onVisibleChanged: {
        if (visible) {
            width = Math.round(rootItem.width + margins.left + margins.right);   // Fenestra : largeur de la fenêtre donnée à l'ouverture
            voletPrevu = Plasmoid.configuration.kdeConnectMemoriser && Plasmoid.configuration.kdeConnectPanelOn;   // Fenestra : groupe menu + volet centré ; Fenestra : option du volet
            var pos = popupPosition(width, height);
            x = pos.x;
            y = pos.y;
            reset();
            // Fenestra : chargements après l'affichage (le menu se dessine d'abord)
            chargementsOuverture.restart();
        } else {
            view.currentIndex = 0;
        }
    }

    onHeightChanged: {
        if (visible) {
            var pos = popupPosition(width, height);
            x = pos.x;
            y = pos.y;
        }
    }

    onWidthChanged: {
        if (visible) {
            var pos = popupPosition(width, height);
            x = pos.x;
            y = pos.y;
        }
    }

    function toggle() {
        root.visible = !root.visible;
    }

    // Fenestra : chargements après l'affichage : appelés juste après l'ouverture
    function chargerApresOuverture(force) {
        if (!root.visible && !force) return;
        if (!rootItem.newAppsLoaded) rootItem.loadNewApps();
        rootItem.loadFolders();
        rootItem.loadAllAppsFolders();
        rootItem.loadLaunchCounts();
        ensureCategoryModel();
    }

    function reset() {
        searchDebounce.stop();
        rootItem.pluginResults = [];
        searchField.text = "";
        searchField.focus = true;
        view.currentIndex = 0;
        mainFlick.contentY = 0;
        globalFavoritesGrid.currentIndex = -1;
        allAppsGrid.currentIndex = -1;
        rootItem.pinnedCurrentPage = 0;
        kicker.searchRunnerFilter = "all";
        folderContentPopup.visible = false;
        createFolderOverlay.visible = false;
        folderRenameOverlay.visible = false;
        allAppsFolderPopup.visible = false;
        createAllAppsFolderOverlay.visible = false;
        viewModePopup.visible = false;
        categoryFlyout.visible = false;
    }

    // Fenestra : groupe menu + volet centré : largeur du volet + écart, quand il est (ou va être) ouvert
    property bool voletPrevu: false
    function largeurVolet() {
        if (!voletPrevu) return 0;
        var w = kdeConnectPanel.width > 0 ? kdeConnectPanel.width
              : kdeConnectPanel.mainItem.width + kdeConnectPanel.margins.left + kdeConnectPanel.margins.right;
        return w + Kirigami.Units.smallSpacing * 2;
    }

    // Fenestra : glissement du menu : durée du déplacement du menu (ms)
    property int dureeGlissement: 250   // Fenestra : glissement du menu
    // Fenestra : délais du groupe : départ du volet après le début du glissement / retour du menu après le début de l'effacement
    property int delaiOuvertureVolet: 250   // Fenestra : délais du groupe
    property int delaiFermetureVolet: 200   // Fenestra : délais du groupe
    function glisserMenuVers(nx) {
        glissementMenu.stop();
        glissementMenu.from = x;
        glissementMenu.to = nx;
        glissementMenu.duration = dureeGlissement;
        glissementMenu.start();
    }
    // Fenestra : ordre du recentrage : à l'ouverture, le menu se décale d'abord, puis le volet apparaît
    function basculerVolet() {
        if (kdeConnectPanel.visible) { kdeConnectPanel.toggle(); return; }
        attenteRecentrage.stop();
        voletPrevu = true;
        var pos = popupPosition(width, height);
        y = pos.y;
        glisserMenuVers(pos.x);
        apparitionVolet.interval = delaiOuvertureVolet;   // Fenestra : glissement du menu : le volet arrive après le glissement
        apparitionVolet.restart();
    }
    function recentrerMenu() {
        if (!visible || kdeConnectPanel.visible) return;
        voletPrevu = false;
        var pos = popupPosition(width, height);
        y = pos.y;
        glisserMenuVers(pos.x);
    }

    function popupPosition(width, height) {
        var screenAvail = kicker.availableScreenRect;
        var screenGeom = kicker.screenGeometry;
        var screen = Qt.rect(screenAvail.x + screenGeom.x, screenAvail.y + screenGeom.y, screenAvail.width, screenAvail.height);

        var offset = Kirigami.Units.smallSpacing;

        // Fall back to bottom-left of screen area when the applet is on the desktop or floating.
        var x = offset;
        var y = screen.height - height - offset;
        var appletTopLeft;
        var horizMidPoint;
        var vertMidPoint;

        if (Plasmoid.configuration.displayPosition === 1) {
            horizMidPoint = screen.x + (screen.width / 2);
            vertMidPoint = screen.y + (screen.height / 2);
            x = horizMidPoint - (width + root.largeurVolet()) / 2;
            y = vertMidPoint - height / 2;
        } else if (Plasmoid.configuration.displayPosition === 2) {
            horizMidPoint = screen.x + (screen.width / 2);
            vertMidPoint = screen.y + (screen.height / 2);
            x = horizMidPoint - (width + root.largeurVolet()) / 2;
            y = screen.y + screen.height - height - offset - panelSvg.margins.top;
        } else if (Plasmoid.location === PlasmaCore.Types.BottomEdge) {
            horizMidPoint = screen.x + (screen.width / 2);
            appletTopLeft = parent.mapToGlobal(0, 0);
            x = (appletTopLeft.x < horizMidPoint) ? screen.x + offset : (screen.x + screen.width) - width - offset;
            y = screen.y + screen.height - height - offset - panelSvg.margins.top;
        } else if (Plasmoid.location === PlasmaCore.Types.TopEdge) {
            horizMidPoint = screen.x + (screen.width / 2);
            var appletBottomLeft = parent.mapToGlobal(0, parent.height);
            x = (appletBottomLeft.x < horizMidPoint) ? screen.x + offset : (screen.x + screen.width) - width - offset;
            y = screen.y + panelSvg.margins.bottom + offset;
        } else if (Plasmoid.location === PlasmaCore.Types.LeftEdge) {
            vertMidPoint = screen.y + (screen.height / 2);
            appletTopLeft = parent.mapToGlobal(0, 0);
            x = appletTopLeft.x * 2 + parent.width + panelSvg.margins.right + offset;
            y = screen.y + (appletTopLeft.y < vertMidPoint) ? screen.y + offset : (screen.y + screen.height) - height - offset;
        } else if (Plasmoid.location === PlasmaCore.Types.RightEdge) {
            vertMidPoint = screen.y + (screen.height / 2);
            appletTopLeft = parent.mapToGlobal(0, 0);
            x = appletTopLeft.x - panelSvg.margins.left - offset - width;
            y = screen.y + (appletTopLeft.y < vertMidPoint) ? screen.y + offset : (screen.y + screen.height) - height - offset;
        }
        return Qt.point(x, y);
    }

    function colorWithAlpha(color: color, alpha: real): color {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    mainItem: FocusScope {
        id: rootItem
        // Fenestra : chargements après l'affichage : minuteur des chargements
        Timer { id: chargementsOuverture; interval: 30; onTriggered: root.chargerApresOuverture() }
        // Fenestra : groupe menu + volet centré : le volet s'ouvre ou se ferme -> le menu se recentre
        Connections {
            target: kdeConnectPanel
            function onVisibleChanged() {
                if (!root.visible) return;
                if (kdeConnectPanel.visible) {
                    attenteRecentrage.stop();
                    if (!root.voletPrevu) {
                        root.voletPrevu = true;
                        var pos = root.popupPosition(root.width, root.height);
                        root.x = pos.x;
                        root.y = pos.y;
                    }
                } else {
                    attenteRecentrage.restart();   // Fenestra : ordre du recentrage : le volet s'efface d'abord
                }
            }
        }
        Timer { id: attenteRecentrage; interval: root.delaiFermetureVolet; onTriggered: root.recentrerMenu() }
        NumberAnimation { id: glissementMenu; target: root; property: "x"; easing.type: Easing.OutCubic }   // Fenestra : glissement du menu
        Timer { id: apparitionVolet; interval: 0; onTriggered: if (root.visible && !kdeConnectPanel.visible) kdeConnectPanel.toggle() }


        property int widthComputed: root.cellSizeWidth * root.colonnesAuto + Kirigami.Units.gridUnit * 2

        property int pinnedCurrentPage: 0
        property int pinnedItemsPerPage: root.colonnesAuto * Plasmoid.configuration.numberRows
        property bool ctrlHeld: false
        property bool pinnedCollapsed: false
        property int pinnedCollapsedRows: 2   // rangées visibles quand replié (façon Windows 11)
        // horodatage (ms) de la dernière touche de navigation dans une grille, partagé par toutes les grilles
        property double lastNavKeyTime: 0
        function keyNavRecently() { return Date.now() - lastNavKeyTime < 400; }
        // bord gauche commun de toutes les rubriques (= bord de la 1re icône épinglée, icône centrée dans sa cellule)
        property int sectionInset: Math.max(0, Math.round((globalFavoritesGrid.cellWidth - root.iconSize) / 2))
        // marge interne gauche des lignes de recommandations / de la liste « Tout » (icône décalée dans sa ligne)
        property int listIconPad: Math.round(Kirigami.Units.gridUnit / 2)

        // Bouton d'en-tête de section : sans cadre, surlignement blanc 50 % au survol
        // (même fond que le cadre des boutons d'applis de la barre des tâches)
        component SectionButton: Item {
            id: sectionBtn
            property string text: ""
            property string iconName: ""
            property bool flat: false          // gardés pour compatibilité avec AToolButton
            property int buttonHeight: 25
            property bool showNewDot: false
            property bool iconLeft: false      // icône avant le texte
            signal clicked()

            implicitWidth: btnRow.implicitWidth + Kirigami.Units.largeSpacing * 2
            implicitHeight: buttonHeight
            Accessible.role: Accessible.Button
            Accessible.name: text

            Rectangle {
                anchors.fill: parent
                radius: 5
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
                border.width: 1                 // même bordure que les autres surlignements
                border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                opacity: btnMouse.containsMouse ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 100 } }
            }

            Row {
                id: btnRow
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing
                layoutDirection: sectionBtn.iconLeft ? Qt.RightToLeft : Qt.LeftToRight

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: sectionBtn.text
                    color: Kirigami.Theme.textColor
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize
                }

                Kirigami.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: sectionBtn.iconName !== ""
                    source: sectionBtn.iconName
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    animated: false
                }
            }

            Rectangle {
                objectName: "categoryButtonNewDot"
                visible: sectionBtn.showNewDot
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 2
                width: 7
                height: width
                radius: width / 2
                color: Kirigami.Theme.highlightColor
            }

            MouseArea {
                id: btnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sectionBtn.clicked()
            }
        }
        property int pinnedTotalPages: globalFavoritesGrid.count > 0
            ? Math.max(1, Math.ceil(globalFavoritesGrid.count / pinnedItemsPerPage))
            : 1

        onPinnedCurrentPageChanged: {
            globalFavoritesGrid.positionAtIndex(pinnedCurrentPage * pinnedItemsPerPage);
        }

        onPinnedTotalPagesChanged: {
            if (pinnedCurrentPage >= pinnedTotalPages) {
                pinnedCurrentPage = Math.max(0, pinnedTotalPages - 1);
            }
        }

        // Fenestra : largeur stable : 733 px de contenu pour 7 colonnes (+ 12 px de cadre = 745 px), en proportion sinon
        // Fenestra : marges latérales réduites : 8 px de marge de chaque côté (18 à l'origine)
        readonly property int margeCote: 8
        // contenu : 697 px d'icônes pour 7 colonnes + 2 marges = 713 px (+ 12 px de cadre = 725 px de fenêtre)
        readonly property int largeurVoulue: Math.round(697 * root.colonnesAuto / 7) + 2 * margeCote
        width: largeurVoulue
        // hauteur souhaitée de la page qui défile (la hauteur réelle s'adapte à la place disponible)
        readonly property real viewWanted: Kirigami.Units.gridUnit * 38

        height: Math.min(view.y + rootItem.viewWanted + footer.height, Math.max(200, kicker.availableScreenRect.height - Kirigami.Units.largeSpacing * 2))   // hauteur demandée : haut de la page + page souhaitée + pied (+ 0 px)

        Layout.minimumWidth: largeurVoulue
        Layout.maximumWidth: largeurVoulue
        Layout.minimumHeight: height
        Layout.maximumHeight: height

        focus: true
        onFocusChanged: searchField.focus = true

        KCoreAddons.KUser { id: menuUser }

        property string timeGreeting: {
            var h = new Date().getHours();
            if (h < 12) return i18n("Good morning");
            if (h < 18) return i18n("Good afternoon");
            return i18n("Good evening");
        }

        // ── Pinned Folders ──────────────────────────────────────────────────
        property var pinnedFoldersData: []
        property string loadedPinnedFolders: ""

        function loadFolders() {
            var raw = Plasmoid.configuration.pinnedFolders || "";
            if (raw === loadedPinnedFolders) return;
            loadedPinnedFolders = raw;
            if (!raw || raw.length === 0) { pinnedFoldersData = []; return; }
            try { pinnedFoldersData = JSON.parse(raw); } catch(e) { pinnedFoldersData = []; }
        }

        function saveFolders() {
            Plasmoid.configuration.pinnedFolders = JSON.stringify(pinnedFoldersData);
            loadedPinnedFolders = Plasmoid.configuration.pinnedFolders;
        }

        // ── All Apps Folders ────────────────────────────────────────────────
        property var allAppsFoldersData: []
        property string loadedAllAppsFolders: ""

        function loadAllAppsFolders() {
            var raw = Plasmoid.configuration.allAppsFolders || "";
            if (raw === loadedAllAppsFolders) return;
            loadedAllAppsFolders = raw;
            if (!raw || raw.length === 0) { allAppsFoldersData = []; return; }
            try { allAppsFoldersData = JSON.parse(raw); } catch(e) { allAppsFoldersData = []; }
        }

        function saveAllAppsFolders() {
            Plasmoid.configuration.allAppsFolders = JSON.stringify(allAppsFoldersData);
            loadedAllAppsFolders = Plasmoid.configuration.allAppsFolders;
        }

        function launchFolderApp(desktopId) {
            var favList = globalFavorites.favorites;
            for (var i = 0; i < favList.length; i++) {
                if (favList[i] === desktopId) {
                    rootItem.recordLaunch(desktopId);
                    globalFavorites.trigger(i, "", null);
                    root.toggle();
                    return;
                }
            }
        }

        function displayNameForId(id) {
            if (id.startsWith("preferred://")) {
                var s = id.slice(12);
                return s.charAt(0).toUpperCase() + s.slice(1);
            }
            var base = id.replace(/\.desktop$/, "");
            var name = base.split(".").pop();
            return name.split("-").map(function(w) {
                return w.length > 0 ? w.charAt(0).toUpperCase() + w.slice(1) : "";
            }).join(" ");
        }

        function iconForId(id) {
            return id.startsWith("preferred://") ? "emblem-default" : id.replace(/\.desktop$/, "");
        }

        function setAppsViewMode(mode) {
            scrollAnim.stop();
            letterScrollAnim.stop();
            if (Plasmoid.configuration.allAppsViewMode === mode) return;
            Plasmoid.configuration.allAppsViewMode = mode;
            allAppsGrid.contentY = 0;
            allAppsGrid.currentIndex = -1;
            mainFlick.contentY = 0;
        }

        property bool _needsComboRebuild: false

        onAllAppsFoldersDataChanged: {
            if (sortedAppsModel.sourceModel) {
                if (folderAppPickerPopup.visible) {
                    _needsComboRebuild = true
                } else {
                    buildAllAppsCombo()
                }
            }
        }

        function openFolderAppPicker(folderIdx, px, py) {
            folderAppPickerPopup.openForFolder(folderIdx, px, py)
        }

        // ── All Apps combo model helpers ─────────────────────────────────────
        // Kicker role IDs (from plasma-workspace/applets/kicker/actionlist.h)
        readonly property int kickerDisplayRole:     Qt.DisplayRole          // 0
        readonly property int kickerDecorationRole:  Qt.DecorationRole       // 1
        readonly property int kickerDescriptionRole: Qt.UserRole + 1         // 257
        readonly property int kickerFavoriteIdRole:  Qt.UserRole + 3         // 259
        readonly property int kickerUrlRole:         Qt.UserRole + 10        // 266
        readonly property int kickerActionListRole:  Qt.UserRole + 9         // 265

        function lookupAppInfo(favId) {
            for (var i = 0; i < sortedAppsModel.rowCount(); i++) {
                var midx = sortedAppsModel.index(i, 0);
                if (sortedAppsModel.data(midx, kickerFavoriteIdRole) === favId) {
                    return {
                        name:        sortedAppsModel.data(midx, kickerDisplayRole)    || displayNameForId(favId),
                        decoration:  sortedAppsModel.data(midx, kickerDecorationRole) || iconForId(favId),
                        description: sortedAppsModel.data(midx, kickerDescriptionRole) || ""
                    };
                }
            }
            return { name: displayNameForId(favId), decoration: iconForId(favId), description: "" };
        }

        function buildAllAppsCombo() {
            // Rebuild only when the catalog, sort mode or folder data changes.
            allAppsListModel.clear();
            allAppsGridModel.clear();
            if (!sortedAppsModel.sourceModel) return;

            var displayRole    = kickerDisplayRole;
            var decorationRole = kickerDecorationRole;
            var favoriteIdRole = kickerFavoriteIdRole;
            var descRole       = kickerDescriptionRole;
            var urlRole        = kickerUrlRole;
            var sortMode       = Plasmoid.configuration.allAppsSortMode;

            // Build set of foldered app IDs
            var folderedIds = {};
            for (var fi = 0; fi < allAppsFoldersData.length; fi++) {
                var fd0 = allAppsFoldersData[fi];
                if (fd0.items) {
                    for (var ai0 = 0; ai0 < fd0.items.length; ai0++) folderedIds[fd0.items[ai0]] = fi;
                }
            }

            // Non-foldered app entries (already sorted by sortedAppsModel)
            var appRows = [];
            for (var i = 0; i < sortedAppsModel.rowCount(); i++) {
                var midx = sortedAppsModel.index(i, 0);
                var favId = favoriteIdRole !== undefined ? (sortedAppsModel.data(midx, favoriteIdRole) || "") : "";
                if (favId !== "" && folderedIds[favId] !== undefined) continue;
                appRows.push({
                    itemType:    "app",
                    display:     sortedAppsModel.data(midx, displayRole)    || "",
                    decoration:  sortedAppsModel.data(midx, decorationRole) || "",
                    favoriteId:  favId,
                    description: descRole !== undefined ? (sortedAppsModel.data(midx, descRole) || "") : "",
                    url:         urlRole !== undefined ? String(sortedAppsModel.data(midx, urlRole) || "") : "",
                    disabled: false, hasActionList: false,
                    sourceRow: i, folderIdx: -1, indented: false, expanded: false
                });
            }

            // Folder entries
            var folderRows = [];
            for (var fi2 = 0; fi2 < allAppsFoldersData.length; fi2++) {
                var fd2 = allAppsFoldersData[fi2];
                folderRows.push({
                    itemType:    "folder",
                    display:     fd2.name,
                    decoration:  "folder",
                    favoriteId:  "",
                    description: i18np("%1 app", "%1 apps", fd2.items ? fd2.items.length : 0),
                    url: "",
                    disabled: false, hasActionList: true,
                    sourceRow: -1, folderIdx: fi2, indented: false, expanded: false
                });
            }

            // Sort folder entries per mode
            if (sortMode === 0 || sortMode === 4)
                folderRows.sort(function(a, b) { return a.display.localeCompare(b.display); });
            else if (sortMode === 1)
                folderRows.sort(function(a, b) { return b.display.localeCompare(a.display); });
            else if (sortMode === 2)
                folderRows.sort(function(a, b) { return (allAppsFoldersData[b.folderIdx].createdAt||0) - (allAppsFoldersData[a.folderIdx].createdAt||0); });
            else if (sortMode === 3)
                folderRows.sort(function(a, b) { return (allAppsFoldersData[a.folderIdx].createdAt||0) - (allAppsFoldersData[b.folderIdx].createdAt||0); });

            // Combine based on sort mode
            var combined = [];
            if (sortMode === 4) {
                combined = folderRows.concat(appRows);
            } else if (sortMode === 0) {
                var ai = 0, fri = 0;
                while (ai < appRows.length && fri < folderRows.length) {
                    if (appRows[ai].display.localeCompare(folderRows[fri].display) <= 0) combined.push(appRows[ai++]);
                    else combined.push(folderRows[fri++]);
                }
                while (ai < appRows.length)   combined.push(appRows[ai++]);
                while (fri < folderRows.length) combined.push(folderRows[fri++]);
            } else if (sortMode === 1) {
                var ai2 = 0, fri2 = 0;
                while (ai2 < appRows.length && fri2 < folderRows.length) {
                    if (appRows[ai2].display.localeCompare(folderRows[fri2].display) >= 0) combined.push(appRows[ai2++]);
                    else combined.push(folderRows[fri2++]);
                }
                while (ai2 < appRows.length)   combined.push(appRows[ai2++]);
                while (fri2 < folderRows.length) combined.push(folderRows[fri2++]);
            } else {
                // Modes 2/3: newest folders first, oldest folders last
                combined = (sortMode === 2) ? folderRows.concat(appRows) : appRows.concat(folderRows);
            }

            if (sortMode === 0 || sortMode === 1) {
                allAppsListModel.append(withAppHeaders(combined, 1));
                allAppsGridModel.append(withAppHeaders(combined, root.colonnesAuto));
            } else if (combined.length > 0) {
                allAppsListModel.append(combined);
                allAppsGridModel.append(combined);
            }
        }

        Timer {
            id: appsCacheRefresh
            interval: 0
            onTriggered: {
                rootItem.buildAllAppsCombo();
                rootItem.rebuildSelectedCategory();
            }
        }
        Connections {
            target: sortedAppsModel
            function onModelReset() { appsCacheRefresh.restart(); }
            function onLayoutChanged() { appsCacheRefresh.restart(); }
            function onRowsInserted() { appsCacheRefresh.restart(); }
            function onRowsRemoved() { appsCacheRefresh.restart(); }
            function onDataChanged() { appsCacheRefresh.restart(); }
        }
        Connections {
            target: root
            function onColonnesAutoChanged() { appsCacheRefresh.restart(); }
        }

        function withAppHeaders(combined, gridCols) {
            var withHeaders = [];
            var lastLetter = null;
            for (var hi = 0; hi < combined.length; hi++) {
                var row = combined[hi];
                var name = row.display || "";
                var letter = name.length > 0 ? name[0].toUpperCase() : "#";
                if (letter < "A" || letter > "Z") letter = "#";
                if (letter !== lastLetter) {
                    if (gridCols > 1 && withHeaders.length % gridCols !== 0) {
                        var manque = gridCols - (withHeaders.length % gridCols);
                        for (var bi = 0; bi < manque; bi++) {
                            withHeaders.push({
                                itemType: "blank",
                                display: "", decoration: "", favoriteId: "", description: "", url: "",
                                disabled: true, hasActionList: false,
                                sourceRow: -1, folderIdx: -1, indented: false, expanded: false
                            });
                        }
                    }
                    withHeaders.push({
                        itemType: "letterHeader",
                        display: letter,
                        decoration: "",
                        favoriteId: "",
                        description: "",
                        url: "",
                        disabled: false, hasActionList: false,
                        sourceRow: -1, folderIdx: -1, indented: false, expanded: false
                    });
                    // complète le reste de la ligne : la lettre occupe toute la rangée à elle seule
                    if (gridCols > 1) {
                        for (var bi2 = 0; bi2 < gridCols - 1; bi2++) {
                            withHeaders.push({
                                itemType: "blank",
                                display: "", decoration: "", favoriteId: "", description: "", url: "",
                                disabled: true, hasActionList: false,
                                sourceRow: -1, folderIdx: -1, indented: false, expanded: false
                            });
                        }
                    }
                    lastLetter = letter;
                }
                withHeaders.push(row);
            }
            return withHeaders;
        }

        // Descend récursivement dans les sous-catégories d'un modèle (ex: Jeux -> Arcade
        // -> ...) et ne garde que les vraies applis (favoriteId non vide), peu importe la
        // profondeur. Générique : marche pour n'importe quelle catégorie à sous-groupes.
        function collectCategoryApps(model, out, seen) {
            if (!model) return;
            var n = 0;
            try { n = model.rowCount(); } catch (e) { return; }
            for (var i = 0; i < n; i++) {
                var idx = model.index(i, 0);
                var fid = "";
                try { fid = String(model.data(idx, kickerFavoriteIdRole) || ""); } catch (e2) { fid = ""; }
                if (fid !== "" && seen[fid]) continue; // déjà vu via une autre sous-catégorie
                if (fid !== "") {
                    seen[fid] = true;
                    out.push({
                        display: String(model.data(idx, kickerDisplayRole) || ""),
                        decoration: model.data(idx, kickerDecorationRole) || "",
                        favoriteId: fid,
                        description: String(model.data(idx, kickerDescriptionRole) || ""),
                        url: String(model.data(idx, kickerUrlRole) || ""),
                        disabled: false, hasActionList: false,
                        srcRow: i,
                        srcModel: model
                    });
                } else {
                    var child = null;
                    try { child = model.modelForRow(i); } catch (e3) { child = null; }
                    if (child) collectCategoryApps(child, out, seen);
                }
            }
        }

        function toggleFolderExpand(folderComboIdx) {
            if (folderComboIdx < 0 || folderComboIdx >= rootItem.allAppsComboModel.count) return;
            var entry = rootItem.allAppsComboModel.get(folderComboIdx);
            if (entry.itemType !== "folder") return;
            var fi = entry.folderIdx;
            if (fi < 0 || fi >= allAppsFoldersData.length) return;
            var folder = allAppsFoldersData[fi];

            if (!entry.expanded) {
                rootItem.allAppsComboModel.set(folderComboIdx, { expanded: true });
                var items = folder.items || [];
                for (var i = 0; i < items.length; i++) {
                    var info = lookupAppInfo(items[i]);
                    rootItem.allAppsComboModel.insert(folderComboIdx + 1 + i, {
                        itemType:    "app",
                        display:     info.name,
                        decoration:  info.decoration,
                        favoriteId:  items[i],
                        description: info.description,
                        url: "",
                        disabled: false, hasActionList: false,
                        sourceRow: -1, folderIdx: fi, indented: true, expanded: false
                    });
                }
            } else {
                rootItem.allAppsComboModel.set(folderComboIdx, { expanded: false });
                while (folderComboIdx + 1 < rootItem.allAppsComboModel.count) {
                    var next = rootItem.allAppsComboModel.get(folderComboIdx + 1);
                    if (next.indented && next.folderIdx === fi) rootItem.allAppsComboModel.remove(folderComboIdx + 1);
                    else break;
                }
            }
        }

        // ── Launch Frequency Tracking ───────────────────────────────────────
        property var launchCounts: ({})
        property string loadedLaunchCounts: ""

        function loadLaunchCounts() {
            var raw = Plasmoid.configuration.appLaunchCounts || "";
            if (raw === loadedLaunchCounts) return;
            loadedLaunchCounts = raw;
            if (!raw || raw.length === 0) { launchCounts = ({}); return; }
            var parsed = root.core !== null ? root.core.launchParseCounts(raw) : null;
            if (parsed !== null) { launchCounts = parsed; return; }
            try { launchCounts = JSON.parse(raw); } catch(e) { launchCounts = ({}); }
        }

        function saveLaunchCounts() {
            Plasmoid.configuration.appLaunchCounts = JSON.stringify(launchCounts);
            loadedLaunchCounts = Plasmoid.configuration.appLaunchCounts;
        }

        // Returns the current workflow bucket key: "day-slot"
        // day: 0=Sun…6=Sat, slot: 0=night(0-5h), 1=morning(6-11h), 2=afternoon(12-17h), 3=evening(18-23h)
        function currentBucket() {
            var now = new Date();
            var day = now.getDay();
            var h = now.getHours();
            var slot = h < 6 ? 0 : h < 12 ? 1 : h < 18 ? 2 : 3;
            return day + "-" + slot;
        }

        // Returns a 0-10 score for how strongly an app matches the current time/day slot.
        // Only used while the native core is unavailable: with the core the
        // same rule is evaluated by launchHasWorkflow(), which avoids a JSON
        // round trip per application.
        function workflowScore(appId) {
            if (!appId) return 0;
            var entry = launchCounts[appId];
            if (!entry || typeof entry !== "object") return 0;
            var bucket = currentBucket();
            var bucketCount = (entry.buckets && entry.buckets[bucket]) || 0;
            var total = entry.total || 0;
            if (total === 0) return 0;
            return Math.round((bucketCount / total) * 10);
        }

        function recordLaunch(appId) {
            if (!appId || appId === "") return;
            if (root.core !== null) {
                var clock = new Date();
                var updated = root.core.launchRecord(
                    JSON.stringify(launchCounts), appId,
                    clock.getDay(), clock.getHours(), Date.now());
                if (updated !== null) {
                    launchCounts = updated;
                    saveLaunchCounts();
                    forgetNewApp(appId);
                    return;
                }
            }
            var updated = JSON.parse(JSON.stringify(launchCounts));
            var bucket = currentBucket();
            var prev = updated[appId];
            // Migrate legacy plain-number entries to the new schema
            var prevTotal = (typeof prev === "number") ? prev : (prev && prev.total ? prev.total : 0);
            var prevBuckets = (prev && typeof prev === "object" && prev.buckets) ? prev.buckets : {};
            prevBuckets[bucket] = (prevBuckets[bucket] || 0) + 1;
            updated[appId] = { total: prevTotal + 1, buckets: prevBuckets, last: Date.now() };
            launchCounts = updated;
            saveLaunchCounts();
            forgetNewApp(appId);
        }

        // ── Smart Context ────────────────────────────────────────────────────
        property string contextLabel: {
            var counts = rootItem.launchCounts;
            var clock = new Date();
            // Check for workflow pattern: any app with bucket score >= 6
            var hasWorkflow = root.core !== null
                ? root.core.launchHasWorkflow(JSON.stringify(counts), clock.getDay(), clock.getHours(), 6)
                : null;
            if (hasWorkflow === null) {
                hasWorkflow = false;
                for (var id in counts) {                    if (rootItem.workflowScore(id) >= 6) { hasWorkflow = true; break; }
                }
            }
            if (hasWorkflow) {
                var now = new Date();
                var days = [i18n("Sunday"), i18n("Monday"), i18n("Tuesday"),
                            i18n("Wednesday"), i18n("Thursday"), i18n("Friday"), i18n("Saturday")];
                var h = now.getHours();
                var dayName = days[now.getDay()];
                if (h < 6)  return i18n("%1 night session", dayName);
                if (h < 12) return i18n("%1 morning picks", dayName);
                if (h < 18) return i18n("%1 afternoon picks", dayName);
                return i18n("%1 evening picks", dayName);
            }
            // Frequency-based fallback
            var topCount = root.core !== null ? root.core.launchTopTotal(JSON.stringify(counts)) : null;
            if (topCount === null) {
                topCount = 0;
                for (var aid in counts) {
                    var entry = counts[aid];
                    var t = (entry && typeof entry === "object") ? (entry.total || 0) : (entry || 0);
                    if (t > topCount) topCount = t;
                }
            }
            if (topCount >= 10) return i18n("Your top picks");
            if (topCount >= 5)  return i18n("Frequently used");
            // Time-of-day fallback
            var hour = new Date().getHours();
            if (hour >= 5  && hour < 9)  return i18n("Your morning session");
            if (hour >= 9  && hour < 12) return i18n("Good morning apps");
            if (hour >= 12 && hour < 14) return i18n("Midday picks");
            if (hour >= 14 && hour < 18) return i18n("Afternoon session");
            if (hour >= 18 && hour < 21) return i18n("Evening apps");
            return i18n("Late night");
        }

        // ── Command Palette ──────────────────────────────────────────────────
        readonly property var paletteCommands: ([
            { name: "lock",       icon: "system-lock-screen",  desc: i18n("Lock the screen"),       cmd: "loginctl lock-session" },
            { name: "sleep",      icon: "system-suspend",      desc: i18n("Suspend to RAM"),         cmd: "systemctl suspend" },
            { name: "reboot",     icon: "system-reboot",       desc: i18n("Restart the computer"),   cmd: "systemctl reboot" },
            { name: "shutdown",   icon: "system-shutdown",     desc: i18n("Shut down the computer"), cmd: "systemctl poweroff" },
            { name: "screenshot", icon: "spectacle",           desc: i18n("Take a screenshot"),      cmd: "spectacle --gui" },
            { name: "settings",   icon: "preferences-system",  desc: i18n("Open System Settings"),   cmd: "systemsettings" },
            { name: "files",      icon: "system-file-manager", desc: i18n("Open file manager"),      cmd: "dolphin" },
            { name: "terminal",   icon: "utilities-terminal",  desc: i18n("Open a terminal"),        cmd: "konsole" },
            { name: "logout",     icon: "system-log-out",      desc: i18n("Log out"),                cmd: "loginctl terminate-user " + Qt.application.name }
        ].concat(PluginSystem.extraCommands()))

        Component.onCompleted: {
            // Calculator — handled inline in QML, stub so it appears in registeredPlugins()
            PluginSystem.register({
                name: "Calculator",
                icon: "accessories-calculator",
                commands: [],
                handleQuery: function(q) { return null; },
                searchResults: function(q) { return []; }
            });

            // Web Search — injects "Search the web for X" into search results
            PluginSystem.register({
                name: "Web Search",
                icon: "internet-web-browser",
                commands: [],
                handleQuery: function(q) { return null; },
                searchResults: function(q) {
                    if (!q || q.length < 2) return [];
                    return [{
                        icon: "internet-web-browser",
                        title: i18n("Search the web for \"%1\"", q),
                        subtitle: i18n("Opens default browser"),
                        action: "xdg-open 'https://duckduckgo.com/?q=" + encodeURIComponent(q).replace(/'/g, "%27") + "'"
                    }];
                }
            });
        }

        // Aggregated plugin search results — updated whenever the runner query changes
        property var pluginResults: []

        function refreshPluginResults(query) {
            pluginResults = (query && query.length >= 2)
                            ? PluginSystem.searchResults(query)
                            : [];
        }

        Plasma5Support.DataSource {
            id: executable
            engine: "executable"
            connectedSources: []

            property bool dolphinRunning: false

            onNewData: function (source, data) {
                if (source.includes("pgrep")) {
                    dolphinRunning = data["exit code"] === 0;
                }
                disconnectSource(source);
            }

            function exec(cmd) {
                connectSource(cmd);
            }

            function checkDolphin() {
                connectSource("pgrep dolphin");
            }
        }

        Kirigami.Heading {
            id: dummyHeading
            visible: false
            width: 0
            level: 5
        }

        TextMetrics {
            id: headingMetrics
            font: dummyHeading.font
        }

        KItemModels.KSortFilterProxyModel {
            id: sortedAppsModel

            sortRoleName: {
                var m = Plasmoid.configuration.allAppsSortMode;
                if (m === 4) return "description";
                if (m === 2 || m === 3) return "url";
                return "display";
            }
            sortOrder: {
                var m = Plasmoid.configuration.allAppsSortMode;
                return (m === 1 || m === 3) ? Qt.DescendingOrder : Qt.AscendingOrder;
            }

            function trigger(row, actionId, argument) {
                var srcIdx = mapToSource(index(row, 0))
                if (srcIdx.valid && sourceModel)
                    sourceModel.trigger(srcIdx.row, actionId, argument)
            }

            property var favoritesModel: sourceModel ? sourceModel.favoritesModel : null
        }

        // ── Le curseur de frappe reste dans la recherche ──
        // si le focus part vers une liste sans navigation au clavier (simple survol), on le rend à la recherche
        Connections {
            id: keepSearchFocus
            target: root
            function onActiveFocusItemChanged() {
                if (!root.visible || rootItem.keyNavRecently()) return;
                var p = root.activeFocusItem;
                while (p) {
                    if (p === globalFavoritesGrid || p === allAppsGrid
                            || p === allAppsCategoryGrid) {
                        Qt.callLater(function () {
                            if (root.visible && !rootItem.keyNavRecently()) searchField.forceActiveFocus();
                        });
                        return;
                    }
                    p = p.parent;
                }
            }
        }

        // ── Nouvelles applications : détection à l'installation, notification, marquage « nouveau » ──
        // incrémenté à chaque rafraîchissement du catalogue (les sous-modèles des catégories sont alors remplacés)
        property int categoryRevision: 0
        property var knownApps: []          // fichiers .desktop connus
        property var newApps: ({})          // identifiant de l'appli -> { t, cat, name }
        property var pendingApps: []        // détectées, en attente de leur catégorie
        property int pendingRounds: 0
        property bool newAppsLoaded: false
        readonly property bool newAppsReady: Plasmoid.configuration.knownApps !== undefined

        readonly property string desktopListCmd: "for d in $(echo \"${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share\" | tr ':' ' '); do ls -1 \"$d/applications\" 2>/dev/null; done | grep '\\.desktop$' | sort -u"

        function shq(s) {
            if (root.core !== null) return root.core.shellQuote(s);
            return "'" + String(s).replace(/'/g, "'\\''") + "'";
        }

        function saveKnownApps() { Plasmoid.configuration.knownApps = JSON.stringify(knownApps); }
        function saveNewApps() { Plasmoid.configuration.newApps = JSON.stringify(newApps); }

        function loadNewApps() {
            try { knownApps = JSON.parse(Plasmoid.configuration.knownApps || "[]"); } catch (e) { knownApps = []; }
            var raw = Plasmoid.configuration.newApps || "{}";
            var stored = {};
            try { stored = JSON.parse(raw); } catch (e) { stored = {}; }
            // une nouveauté est oubliée après 7 jours
            var now = Date.now();
            var keep = root.core !== null
                ? root.core.newAppsPrune(raw, now, 7 * 86400000)
                : null;
            if (keep === null) {
                keep = {};
                for (var k in stored) {
                    if (stored[k] && now - stored[k].t < 7 * 86400000) keep[k] = stored[k];
                }
            }
            newApps = keep;
            if (JSON.stringify(keep) !== JSON.stringify(stored)) saveNewApps();
            newAppsLoaded = true;
        }

        function handleDesktopList(list) {
            if (!newAppsReady || list.length === 0) return;
            if (!newAppsLoaded) loadNewApps();
            if (knownApps.length === 0) {              // 1er passage : état de départ, sans notification
                knownApps = list;
                saveKnownApps();
                return;
            }
            var difference = root.core !== null
                ? root.core.newAppsDiff(knownApps, list)
                : null;
            if (difference !== null) {
                if (!difference.changed) return;
                knownApps = list;
                saveKnownApps();
                if (difference.added.length > 0) {
                    pendingApps = pendingApps.concat(difference.added);
                    pendingRounds = 0;
                    resolveTimer.interval = 3000;
                    resolveTimer.restart();
                }
                return;
            }
            var known = {};
            for (var i = 0; i < knownApps.length; i++) known[knownApps[i]] = true;
            var added = [];
            for (var j = 0; j < list.length; j++) if (!known[list[j]]) added.push(list[j]);
            if (added.length === 0 && list.length === knownApps.length) return;
            knownApps = list;
            saveKnownApps();
            if (added.length > 0) {
                pendingApps = pendingApps.concat(added);
                pendingRounds = 0;
                resolveTimer.interval = 3000;
                resolveTimer.restart();
            }
        }

        // recherche de la catégorie des nouvelles applis dans les catégories du menu
        function resolvePendingApps() {
            if (pendingApps.length === 0) return;
            var want = {};
            for (var i = 0; i < pendingApps.length; i++) want[pendingApps[i]] = true;
            var found = [], foundIds = {};
            for (var c = 0; c < categoryRootModel.rowCount(); c++) {
                var sub = categoryRootModel.modelForRow(c);
                if (!sub) continue;
                var catName = String(categoryRootModel.data(categoryRootModel.index(c, 0), Qt.DisplayRole) || sub.description || "");
                var entries = [];
                collectCategoryApps(sub, entries, {});
                for (var r = 0; r < entries.length; r++) {
                    var entry = entries[r];
                    var fid = entry.favoriteId;
                    if (want[fid] && !foundIds[fid]) {
                        foundIds[fid] = true;
                        found.push({ id: fid, name: entry.display, icon: entry.decoration, cat: catName });
                    }
                }
            }
            var missing = root.core !== null
                ? root.core.newAppsMissing(pendingApps, Object.keys(foundIds))
                : null;
            if (missing === null) {
                missing = pendingApps.filter(function (id) { return !foundIds[id]; });
            }
            if (missing.length > 0 && pendingRounds < 10) {
                // catalogue pas encore à jour : on réessaie un peu plus tard
                pendingApps = missing;
                pendingRounds++;
                resolveTimer.interval = 5000;
                resolveTimer.restart();
            } else {
                pendingApps = [];
                pendingRounds = 0;
            }
            if (found.length === 0) return;
            var updated = root.core !== null
                ? root.core.newAppsMark(JSON.stringify(newApps), found, Date.now())
                : null;
            if (updated === null) {
                updated = JSON.parse(JSON.stringify(newApps));
                for (var f = 0; f < found.length; f++) updated[found[f].id] = { t: Date.now(), cat: found[f].cat, name: found[f].name };
            }
            newApps = updated;
            saveNewApps();
            notifyNewApps(found);
        }

        function notifyNewApps(found) {
            if (Plasmoid.configuration.notifyNewApps === false) return;
            var title, body, icon;
            if (found.length === 1) {
                title = i18n("New application");
                body = i18n("%1 is installed — filed under “%2”", found[0].name, found[0].cat);
                icon = (typeof found[0].icon === "string" && found[0].icon !== "") ? found[0].icon : "applications-other";
            } else {
                title = i18np("%1 new application", "%1 new applications", found.length);
                body = found.slice(0, 4).map(function (f) { return f.name + " (" + f.cat + ")"; }).join(", ")
                       + (found.length > 4 ? "…" : "");
                icon = "applications-other";
            }
            var cmd = root.core !== null ? root.core.cmdNotifySend(title, body, icon) : "";
            if (cmd === "") {
                cmd = "(command -v notify-send >/dev/null 2>&1 && notify-send -a 'Menu Démarrer' -i " + shq(icon) + " -u low "
                      + shq(title) + " " + shq(body) + ") || kdialog --title " + shq(title) + " --passivepopup " + shq(body) + " 8";
            }
            notifySource.connectSource(cmd + " #" + Date.now());
        }

        function forgetNewApp(appId) {
            if (!newAppsReady || !newApps[appId]) return;
            var updated = root.core !== null
                ? root.core.newAppsForget(JSON.stringify(newApps), appId)
                : null;
            if (updated === null) {
                updated = JSON.parse(JSON.stringify(newApps));
                delete updated[appId];
            }
            newApps = updated;
            saveNewApps();
        }

        Timer {
            id: appsWatchTimeout
            interval: 15000
            onTriggered: {
                if (appsWatch.currentSource !== "") {
                    appsWatch.disconnectSource(appsWatch.currentSource);
                    appsWatch.currentSource = "";
                }
            }
        }

        Plasma5Support.DataSource {
            id: appsWatch
            engine: "executable"
            connectedSources: []
            property string currentSource: ""

            function poll() {
                if (currentSource !== "") return; // never start overlapping scans
                currentSource = rootItem.desktopListCmd + " #" + Date.now();
                connectSource(currentSource);
                appsWatchTimeout.restart();
            }

            onNewData: function (source, data) {
                var out = String(data["stdout"] || "").trim();
                disconnectSource(source);
                if (source !== currentSource) return;
                appsWatchTimeout.stop();
                currentSource = "";
                rootItem.handleDesktopList(out === "" ? [] : out.split("\n"));
            }
        }

        Plasma5Support.DataSource {
            id: notifySource
            engine: "executable"
            connectedSources: []
            onNewData: function (source, data) { disconnectSource(source); }
        }

        // Background catalog check once per minute; no overlapping jobs.
        Timer {
            id: appsWatchTimer
            interval: 60000
            repeat: true
            running: rootItem.newAppsReady
            triggeredOnStart: true
            onTriggered: {
                appsWatch.poll();
            }
        }

        // laisse au système le temps de mettre le catalogue à jour, puis relit les catégories
        Timer {
            id: resolveTimer
            interval: 6000
            repeat: false
            onTriggered: {
                var first = !root.categoryModelLoaded;
                root.ensureCategoryModel();
                if (!first) categoryRootModel.refresh();
                rootModel.refresh();
            }
        }

        Connections {
            target: categoryRootModel
            function onRefreshed() {
                rootItem.categoryRevision++;
                rootItem.refreshAvailableCategories();
                rootItem.resolvePendingApps();
            }
        }

        // ── Défilement en cours : les infobulles sont coupées pendant que la liste bouge sous la souris ──
        property bool scrolling: false
        function noteScrolling() {
            scrolling = true;
            scrollEndTimer.restart();
        }

        Timer {
            id: scrollEndTimer
            interval: 350
            repeat: false
            onTriggered: rootItem.scrolling = false
        }

        ListModel {
            id: allAppsListModel
            // Exposes favoritesModel so delegates can Pin/Unpin via the same KActivities model
            property var favoritesModel: sortedAppsModel.favoritesModel
        }

        ListModel {
            id: allAppsGridModel
            property var favoritesModel: sortedAppsModel.favoritesModel
        }
        readonly property var allAppsComboModel: Plasmoid.configuration.allAppsViewMode === 1
                                                ? allAppsGridModel : allAppsListModel

        ListModel {
            id: categoryAppsModel
            property var favoritesModel: sortedAppsModel.favoritesModel
        }

        property int activeCategoryRow: -1
        property string activeCategoryName: ""
        property var availableCategories: [{ row: -1, label: i18n("All apps") }]
        property var categoryMembership: ({})

        readonly property var categoriesWithNewApps: {
            var marked = {};
            var pendingIds = Object.keys(newApps);
            for (var row in categoryMembership) {
                var members = categoryMembership[row];
                for (var i = 0; i < pendingIds.length; i++) {
                    if (members[pendingIds[i]]) {
                        marked[row] = true;
                        marked[-1] = true;
                        break;
                    }
                }
            }
            return marked;
        }

        function refreshAvailableCategories() {
            var choices = [{ row: -1, label: i18n("All apps") }];
            var membership = {};
            for (var row = 0; row < categoryRootModel.rowCount(); row++) {
                var sub = categoryRootModel.modelForRow(row);
                var items = [];
                collectCategoryApps(sub, items, {});
                if (items.length === 0) continue;
                var name = String(categoryRootModel.data(categoryRootModel.index(row, 0), Qt.DisplayRole)
                                  || (sub ? sub.description : "") || "");
                if (!name) continue;
                var ids = {};
                for (var i = 0; i < items.length; i++) ids[items[i].favoriteId] = true;
                membership[row] = ids;
                choices.push({ row: row, label: name });
            }
            categoryMembership = membership;
            availableCategories = choices;
            if (activeCategoryRow >= 0) {
                var replacement = -1;
                for (var j = 1; j < choices.length; j++) {
                    if (choices[j].label === activeCategoryName) { replacement = choices[j].row; break; }
                }
                activeCategoryRow = replacement;
                if (replacement < 0) activeCategoryName = "";
                rebuildSelectedCategory();
            }
        }

        function rebuildSelectedCategory() {
            categoryAppsModel.clear();
            if (activeCategoryRow < 0 || !sortedAppsModel.sourceModel) return;
            var ids = categoryMembership[activeCategoryRow] || {};
            var seen = {};
            for (var i = 0; i < sortedAppsModel.rowCount(); i++) {
                var idx = sortedAppsModel.index(i, 0);
                var fid = String(sortedAppsModel.data(idx, kickerFavoriteIdRole) || "");
                if (!fid || !ids[fid] || seen[fid]) continue;
                seen[fid] = true;
                categoryAppsModel.append({
                    itemType: "app",
                    display: String(sortedAppsModel.data(idx, kickerDisplayRole) || ""),
                    decoration: sortedAppsModel.data(idx, kickerDecorationRole) || "",
                    favoriteId: fid,
                    description: String(sortedAppsModel.data(idx, kickerDescriptionRole) || ""),
                    url: String(sortedAppsModel.data(idx, kickerUrlRole) || ""),
                    disabled: false, hasActionList: false,
                    sourceRow: i, folderIdx: -1, indented: false, expanded: false
                });
            }
        }

        function selectCategory(row) {
            if (activeCategoryRow === row) return;
            // A category with no matching apps can still occur after a catalog refresh.
            activeCategoryRow = row;
            activeCategoryName = "";
            for (var i = 1; i < availableCategories.length; i++) {
                if (availableCategories[i].row === row) {
                    activeCategoryName = availableCategories[i].label;
                    break;
                }
            }
            allAppsGrid.currentIndex = -1;
            mainFlick.contentY = Math.min(mainFlick.contentY, allAppsHeader.y);
            rebuildSelectedCategory();
        }

        PC3.TextField {
            id: searchField
            objectName: "searchField"
            anchors {
                top: parent.top
                topMargin: Kirigami.Units.gridUnit - 10
                left: parent.left
                leftMargin: rootItem.margeCote + 20   // Fenestra : recherche décalée
                right: kdeConnectButton.left
                rightMargin: Kirigami.Units.smallSpacing * 2 + 10   // compense le décalage du bouton
            }
            focus: true
            placeholderText: i18n("Search for apps and settings")
            topPadding: 10
            bottomPadding: 10
            leftPadding: Kirigami.Units.gridUnit + Kirigami.Units.iconSizes.small
            text: ""
            font.pointSize: Kirigami.Theme.defaultFont.pointSize

            background: Rectangle {
                color: Kirigami.Theme.backgroundColor
                radius: 20
                border.width: 1
                border.color: colorWithAlpha(Kirigami.Theme.textColor, 0.05)
            }

            onTextChanged: {
                rootItem.pluginResults = [];
                runnerGrid.flickableItem.contentY = 0;
                if (text.trim().length === 0) {
                    searchDebounce.stop();
                    runnerModel.query = "";
                } else if (text.startsWith('>') && Plasmoid.configuration.enableShellRunner) {
                    searchDebounce.stop();
                    runnerModel.query = "";
                } else if (text.startsWith('/')) {
                    searchDebounce.stop();
                    runnerModel.query = "";
                } else {
                    searchDebounce.restart();
                }
            }
            Keys.onPressed: event => {
                rootItem.lastNavKeyTime = Date.now();
                if (event.key === Qt.Key_Escape) {
                    event.accepted = true;
                    if (categoryFlyout.visible) {
                        categoryFlyout.close();
                    } else if (viewModePopup.visible) {
                        viewModePopup.visible = false;
                    } else if (root.searching) {
                        searchField.clear();
                    } else {
                        root.toggle();
                    }
                }
                // In '/' palette mode, Down focuses the palette list
                if (searchField.text.startsWith('/') && event.key === Qt.Key_Down) {
                    event.accepted = true;
                    commandPaletteList.currentIndex = 0;
                    commandPaletteList.forceActiveFocus();
                    return;
                }

                // Forward Up/Down keys directly to runnerGrid when on search page
                if (view.currentIndex === 1 && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                    event.accepted = true;
                    if (event.key === Qt.Key_Down) {
                        runnerGrid.tryActivate(0, 0);
                    } else if (event.key === Qt.Key_Up) {
                        var lastGridIndex = runnerGrid.count - 1;
                        if (lastGridIndex >= 0) {
                            var lastGrid = runnerGrid.subGridAt(lastGridIndex);
                            if (lastGrid && lastGrid.count > 0) {
                                lastGrid.tryActivate(lastGrid.lastRow(), 0);
                                lastGrid.focus = true;
                            }
                        }
                    }
                    return;
                }

                if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                    event.accepted = true;
                    if (view.currentIndex === 1) {
                        // For search results page
                        runnerGrid.focus = true;
                        runnerGrid.tryActivate(0, 0);
                    } else {
                        // For other pages
                        view.currentItem.forceActiveFocus();
                        view.currentItem.tryActivate(0, 0);
                    }
                }

                
            }
            Keys.onReturnPressed: {
                if (root.searching && searchField.text.startsWith('>') && Plasmoid.configuration.enableShellRunner) {
                    var cmd = searchField.text.slice(1).trim();
                    if (cmd.length > 0) {
                        executable.exec(cmd);
                        root.toggle();
                        return;
                    }
                }
                if (root.searching && searchField.text.startsWith('/')) {
                    // Calculator result: copy to clipboard
                    if (commandPaletteContainer.calcResult !== "") {
                        executable.exec("printf '%s' " + rootItem.shq(commandPaletteContainer.calcResult) + " | xclip -selection clipboard 2>/dev/null || printf '%s' " + rootItem.shq(commandPaletteContainer.calcResult) + " | xsel --clipboard --input 2>/dev/null");
                        root.toggle();
                        return;
                    }
                    // Normal command execution
                    var query = searchField.text.slice(1).toLowerCase().trim();
                    var matched = rootItem.paletteCommands.filter(function(c) {
                        return query === "" || c.name.startsWith(query);
                    });
                    if (matched.length > 0 && matched[0].cmd !== "") {
                        executable.exec(matched[0].cmd);
                        root.toggle();
                    }
                    return;
                }
                if (view.currentIndex === 1) {
                    // On search results page, activate the first available item
                    runnerGrid.focus = true;

                    // Find the first grid with items and activate its first item
                    for (var i = 0; i < runnerGrid.count; i++) {
                        var grid = runnerGrid.subGridAt(i);
                        if (grid && grid.count > 0) {
                            grid.currentIndex = 0;
                            grid.focus = true;

                       
                            if ("trigger" in grid.model) {
                                //console.log("Calling grid.model.trigger(0)");
                                grid.model.trigger(0, "", null);
                                root.toggle();
                            }
                            return;
                        }
                    }
                } else {
                    // Original logic for other pages
                    for (var i = 0; i < runnerGrid.count; i++) {
                        var grid = runnerGrid.subGridAt(i)
                        if (grid && grid.count > 0) {
                            grid.currentIndex = 0
                            grid.focus = true
                            grid.itemActivated(0, "", null)
                            return
                        }
                    }
                }
            }
            function backspace() {
                if (!root.visible) {
                    return;
                }
                focus = true;
                text = text.slice(0, -1);
            }

            function appendText(newText) {
                if (!root.visible) {
                    return;
                }
                focus = true;
                text = text + newText;
            }

            Kirigami.Icon {
                source: root.searching && searchField.text.startsWith('>')
                        ? 'utilities-terminal'
                        : root.searching && searchField.text.startsWith('/')
                        ? 'run-build'
                        : 'search'
                anchors {
                    left: searchField.left
                    verticalCenter: searchField.verticalCenter
                    leftMargin: Kirigami.Units.smallSpacing * 2
                }
                height: Kirigami.Units.iconSizes.small
                width: height

                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }

        // ── Volet « Appareil mobile » (KDE Connect), fichier KdeConnectPanel.qml ──
        KdeConnectPanel {
            id: kdeConnectPanel
            menuWindow: root
            core: root.core
        }

        // ── Bouton KDE Connect à droite de la recherche (action à brancher plus tard) ──
        Item {
            id: kdeConnectButton
            anchors {
                top: searchField.top
                right: parent.right
                rightMargin: rootItem.margeCote   // Fenestra : bouton aligné sur la marge réduite (était décalé de 10 px vers la droite)
            }
            height: searchField.height
            width: height
            Accessible.role: Accessible.Button
            Accessible.name: "KDE Connect"

            Rectangle {
                anchors.fill: parent
                radius: 5
                color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
                border.width: 1
                border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                opacity: (kdeConnectMouse.containsMouse || kdeConnectPanel.visible) ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 100 } }
            }

            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.smallMedium
                height: width
                source: Qt.resolvedUrl("../icons/status/fenestra-kdeconnect.svg")
            }

            MouseArea {
                id: kdeConnectMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onClicked: root.basculerVolet()   // Fenestra : ordre du recentrage
            }

            PC3.ToolTip.text: "KDE Connect"
            PC3.ToolTip.visible: kdeConnectMouse.containsMouse
            PC3.ToolTip.delay: 400
        }

        // ── Quick Actions Bar ────────────────────────────────────────────────
        // Shows contextual single-click actions when search is idle; slides away while searching.
        Item {
            id: quickActionsBar
            anchors.top: searchField.bottom
            anchors.topMargin: Kirigami.Units.smallSpacing
            anchors.left: parent.left
            anchors.leftMargin: rootItem.margeCote
            anchors.right: parent.right
            anchors.rightMargin: rootItem.margeCote
            clip: true
            height: (root.searching || !Plasmoid.configuration.showQuickActions) ? 0 : qaRow.implicitHeight + Kirigami.Units.smallSpacing

            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Row {
                id: qaRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Kirigami.Units.smallSpacing / 2

                Repeater {
                    model: [
                        { icon: "spectacle",           tip: i18n("Screenshot"),     cmd: "spectacle --gui" },
                        { icon: "system-lock-screen",  tip: i18n("Lock Screen"),    cmd: "loginctl lock-session" },
                        { icon: "utilities-terminal",  tip: i18n("Open Terminal"),  cmd: "konsole" },
                        { icon: "system-file-manager", tip: i18n("Open Files"),     cmd: "dolphin" },
                        { icon: "accessories-calculator", tip: i18n("Calculator"),  cmd: "kcalc" },
                        { icon: "preferences-system",  tip: i18n("System Settings"), cmd: "systemsettings" }
                    ]

                    delegate: PC3.ToolButton {
                        icon.name: modelData.icon
                        display: AbstractButton.IconOnly
                        PC3.ToolTip.text: modelData.tip
                        PC3.ToolTip.visible: hovered
                        PC3.ToolTip.delay: 400
                        opacity: hovered ? 1.0 : 0.55
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                        onClicked: {
                            executable.exec(modelData.cmd);
                            root.toggle();
                        }
                    }
                }
            }
        }

        // ── Trait sous la barre de recherche ────────────────────────────────
        Rectangle {
            id: searchSeparator
            // marges du cadre de la fenêtre, mesurées une fois le popup affiché
            property real extLeft: 0
            property real extRight: 0
            function updateExtension() {
                var w = parent.Window.window;
                if (!w) return;
                var p = parent.mapToItem(null, 0, 0);
                extLeft = Math.max(0, p.x);
                extRight = Math.max(0, w.width - p.x - parent.width);
            }
            Component.onCompleted: Qt.callLater(updateExtension)
            Connections {
                target: root
                function onVisibleChanged() {
                    if (root.visible) Qt.callLater(searchSeparator.updateExtension);
                }
            }
            anchors {
                top: quickActionsBar.bottom
                topMargin: Math.round(Kirigami.Units.gridUnit * 0.6)
                left: parent.left
                leftMargin: -extLeft
                right: parent.right
                rightMargin: -extRight
            }
            height: 1
            color: colorWithAlpha(Kirigami.Theme.textColor, 0.15)
        }

        SwipeView {
            id: view

            interactive: false
            currentIndex: 0
            clip: true

            anchors {
                top: searchSeparator.bottom
                topMargin: Kirigami.Units.smallSpacing + 10
                left: parent.left
                leftMargin: rootItem.margeCote
                right: parent.right
                rightMargin: -searchSeparator.extRight
            }
            onCurrentIndexChanged: {
                globalFavoritesGrid.currentIndex = -1;
                    }

            height: Math.max(Kirigami.Units.gridUnit * 8, Math.min(rootItem.viewWanted, rootItem.height - view.y - footer.height - 0))

            // PAGE 1 — page unique : épinglés, recommandations, « Tout »
            Flickable {
                id: mainFlick
                objectName: "mainFlick"
                width: view.width
                height: view.height
                contentWidth: mainColumn.width
                contentHeight: mainColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                onContentYChanged: rootItem.noteScrolling()

                PC3.ScrollBar.vertical: PC3.ScrollBar {}

                function tryActivate(row, col) {
                    if (!rootItem.pinnedCollapsed)
                        globalFavoritesGrid.tryActivate(row, col);
                    else
                        allAppsGrid.tryActivate(0, 0);
                }

                function scrollBy(delta) {
                    scrollAnim.stop();
                    letterScrollAnim.stop();
                    contentY = Math.max(0, Math.min(contentHeight - height, contentY - delta));
                }

                onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, contentHeight - height))

                function scrollTo(y) {
                    var maxY = Math.max(0, contentHeight - height);
                    scrollAnim.stop();
                    scrollAnim.to = Math.max(0, Math.min(y, maxY));
                    scrollAnim.start();
                }

                function ensureVisible(top, bottom) {
                    var pad = Kirigami.Units.largeSpacing;
                    var maxY = Math.max(0, contentHeight - height);
                    if (top - pad < contentY)
                        contentY = Math.max(0, top - pad);
                    else if (bottom + pad > contentY + height)
                        contentY = Math.min(maxY, bottom + pad - height);
                }

                NumberAnimation {
                    id: scrollAnim
                    target: mainFlick
                    property: "contentY"
                    duration: 220
                    easing.type: Easing.OutCubic
                }

                Column {
                id: mainColumn
                width: rootItem.width - rootItem.margeCote * 2
                spacing: Kirigami.Units.largeSpacing

                RowLayout {
                    id: topRow
                    visible: globalFavoritesGrid.count > 0 || rootItem.pinnedFoldersData.length > 0
                    x: rootItem.sectionInset
                    // + largeSpacing + 5 : compense le padding interne du bouton (comme Catégories)
                    width: parent.width - rootItem.sectionInset * 2 + Kirigami.Units.largeSpacing + 5

                    PlasmaExtras.Heading {
                        color: colorWithAlpha(Kirigami.Theme.textColor, 0.8)
                        level: 5
                        text: i18n("Pinned")
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    SectionButton {
                        id: butttonActionAllApps
                        visible: globalFavoritesGrid.count > root.colonnesAuto * rootItem.pinnedCollapsedRows
                        flat: false
                        iconName: rootItem.pinnedCollapsed ? "go-down" : "go-up"
                        text: rootItem.pinnedCollapsed ? i18n("Show more") : i18n("Show less")
                        buttonHeight: 25
                        onClicked: rootItem.pinnedCollapsed = !rootItem.pinnedCollapsed
                    }
                }

                ItemGridView {
                    id: globalFavoritesGrid
                    objectName: "globalFavoritesGrid"
                    scrollEnabled: false
                    whiteHighlight: true // surlignement blanc 50 %
                    visible: count > 0
                    clip: true   // coupe net les rangées au-delà du repli
                    width: parent.width
                    height: count > 0 ? root.cellSizeHeight * Math.min(rootItem.pinnedCollapsed ? rootItem.pinnedCollapsedRows : Plasmoid.configuration.numberRows, Math.ceil(count / root.colonnesAuto)) : 0
                    itemColumns: 1
                    dragEnabled: true
                    dropEnabled: true
                    cellWidth: parent.width / root.colonnesAuto
                    cellHeight: root.cellSizeHeight
                    iconSize: root.iconSize
                    labels2lines: Plasmoid.configuration.labels2lines
                    onWheelUnhandled: delta => mainFlick.scrollBy(delta)
                    onKeyNavUp: {
                        if (rootItem.pinnedCurrentPage > 0) {
                            rootItem.pinnedCurrentPage--;
                            globalFavoritesGrid.tryActivate(Plasmoid.configuration.numberRows - 1, 0);
                        } else {
                            globalFavoritesGrid.focus = false;
                            searchField.focus = true;
                        }
                    }
                    onKeyNavDown: {
                        if (rootItem.pinnedCurrentPage < rootItem.pinnedTotalPages - 1) {
                            rootItem.pinnedCurrentPage++;
                            globalFavoritesGrid.tryActivate(0, 0);
                        } else {
                            globalFavoritesGrid.focus = false;
                            categoryFilters.currentIndex = 0;
                            if (categoryFilters.currentItem) categoryFilters.currentItem.forceActiveFocus();
                        }
                    }
                    onKeyNavLeft: {
                        if (rootItem.pinnedCurrentPage > 0) {
                            rootItem.pinnedCurrentPage--;
                            globalFavoritesGrid.tryActivate(0, root.colonnesAuto - 1);
                        }
                    }
                    onKeyNavRight: {
                        if (rootItem.pinnedCurrentPage < rootItem.pinnedTotalPages - 1) {
                            rootItem.pinnedCurrentPage++;
                            globalFavoritesGrid.tryActivate(0, 0);
                        }
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            event.accepted = true;
                            searchField.focus = true;
                            globalFavoritesGrid.focus = false;
                        } else if (event.key === Qt.Key_PageDown) {
                            event.accepted = true;
                            if (rootItem.pinnedCurrentPage < rootItem.pinnedTotalPages - 1) {
                                rootItem.pinnedCurrentPage++;
                                globalFavoritesGrid.tryActivate(0, 0);
                            }
                        } else if (event.key === Qt.Key_PageUp) {
                            event.accepted = true;
                            if (rootItem.pinnedCurrentPage > 0) {
                                rootItem.pinnedCurrentPage--;
                                globalFavoritesGrid.tryActivate(0, 0);
                            }
                        } else if (event.key === Qt.Key_Home) {
                            event.accepted = true;
                            rootItem.pinnedCurrentPage = 0;
                            globalFavoritesGrid.tryActivate(0, 0);
                        } else if (event.key === Qt.Key_End) {
                            event.accepted = true;
                            rootItem.pinnedCurrentPage = rootItem.pinnedTotalPages - 1;
                            globalFavoritesGrid.tryActivate(0, 0);
                        }
                    }
                }

                // Page indicator dots for pinned apps pagination
                Item {
                    visible: !rootItem.pinnedCollapsed && rootItem.pinnedTotalPages > 1
                    width: parent.width
                    height: visible ? Kirigami.Units.gridUnit : 0

                    Row {
                        anchors.centerIn: parent
                        spacing: Kirigami.Units.smallSpacing * 2
                        visible: rootItem.pinnedTotalPages > 1

                        Repeater {
                            model: rootItem.pinnedTotalPages
                            delegate: Item {
                                readonly property bool isCurrent: rootItem.pinnedCurrentPage === index
                                width: isCurrent ? 20 : 8
                                height: 8
                                anchors.verticalCenter: parent.verticalCenter

                                Behavior on width {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: isCurrent
                                           ? Kirigami.Theme.highlightColor
                                           : root.colorWithAlpha(Kirigami.Theme.textColor, 0.3)

                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rootItem.pinnedCurrentPage = index
                                }
                            }
                        }
                    }
                }

                // ── Pinned Folders strip ────────────────────────────────────────
                Flow {
                    id: folderStrip
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing
                    visible: !rootItem.pinnedCollapsed && rootItem.pinnedFoldersData.length > 0

                    Repeater {
                        id: folderTilesRepeater
                        model: rootItem.pinnedFoldersData

                        delegate: Item {
                            id: folderTile
                            width: root.cellSizeWidth
                            height: root.cellSizeHeight

                            property var fd: rootItem.pinnedFoldersData[index] || {name:"", items:[]}

                            focus: true
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: fd.name

                            Keys.onReturnPressed: {
                                var pos = mapToItem(rootItem, 0, 0);
                                folderContentPopup.showAt(index, pos.x, pos.y, width, height);
                            }
                            Keys.onSpacePressed: Keys.onReturnPressed

                            // Hover/focus background
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing / 2
                                radius: Kirigami.Units.smallSpacing + 2
                                color: Kirigami.Theme.highlightColor
                                opacity: tileHover.containsMouse ? 0.12 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 100 } }
                            }

                            // Keyboard focus ring
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Kirigami.Units.smallSpacing + 3
                                color: "transparent"
                                border.width: folderTile.activeFocus ? 2 : 0
                                border.color: Kirigami.Theme.highlightColor
                                opacity: 0.75
                                Behavior on border.width { NumberAnimation { duration: 80 } }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: Kirigami.Units.smallSpacing

                                // Icon mosaic
                                Item {
                                    id: mosaicBox
                                    width: Kirigami.Units.iconSizes.medium
                                    height: Kirigami.Units.iconSizes.medium
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Kirigami.Units.smallSpacing
                                        color: root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.15)
                                        border.width: 1
                                        border.color: root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.35)
                                    }

                                    Grid {
                                        anchors.centerIn: parent
                                        columns: 2
                                        spacing: 2

                                        Repeater {
                                            model: Math.min(4, folderTile.fd.items.length)
                                            delegate: Kirigami.Icon {
                                                width: (mosaicBox.width - 10) / 2
                                                height: width
                                                source: rootItem.iconForId(folderTile.fd.items[index])
                                                animated: false
                                            }
                                        }
                                    }

                                    // Empty folder icon
                                    Kirigami.Icon {
                                        visible: folderTile.fd.items.length === 0
                                        anchors.centerIn: parent
                                        source: "folder"
                                        width: Kirigami.Units.iconSizes.small
                                        height: width
                                        animated: false
                                    }
                                }

                                // Folder name
                                Text {
                                    width: root.cellSizeWidth - Kirigami.Units.largeSpacing * 2
                                    text: folderTile.fd.name
                                    color: Kirigami.Theme.textColor
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            MouseArea {
                                id: tileHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton

                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        folderContextMenu.targetIndex = index;
                                        folderContextMenu.popup();
                                    } else {
                                        var pos = mapToItem(rootItem, 0, 0);
                                        folderContentPopup.showAt(index, pos.x, pos.y, width, height);
                                    }
                                }
                            }

                            // Drag-to-folder drop target
                            DropArea {
                                id: folderDropTarget
                                anchors.fill: parent

                                onDropped: {
                                    var src = kicker.dragSource;
                                    if (!src || !src.favoriteId || src.favoriteId === "") return;
                                    var favId = src.favoriteId;
                                    var folders = rootItem.pinnedFoldersData.slice();
                                    var folder = folders[index];
                                    if (!folder || folder.items.indexOf(favId) >= 0) return;
                                    folders[index] = { name: folder.name, items: folder.items.concat([favId]) };
                                    rootItem.pinnedFoldersData = folders;
                                    rootItem.saveFolders();
                                }

                                // Drop-hover highlight ring
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: Kirigami.Units.smallSpacing + 3
                                    color: root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.22)
                                    border.width: 2
                                    border.color: Kirigami.Theme.highlightColor
                                    visible: folderDropTarget.containsDrag
                                             && typeof kicker.dragSource !== "undefined"
                                             && kicker.dragSource !== null
                                }
                            }
                        }
                    }
                }

                // Keep only the space occupied by recent apps and category filters.
                Item {
                    id: categoryControls
                    objectName: "categoryControls"
                    x: rootItem.sectionInset
                    width: parent.width - rootItem.sectionInset * 2

                    readonly property int recentAppsStripHeight: Plasmoid.configuration.showRecentApps
                        ? Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing * 3
                        : 0

                    height: recentAppsStripHeight + categoryFilters.height

                    // Recently opened apps — horizontal icon strip
                    Item {
                        id: recentAppsStrip
                        width: parent.width
                        height: categoryControls.recentAppsStripHeight
                        visible: Plasmoid.configuration.showRecentApps

                        // Smart context header
                        Row {
                            id: recentAppsHeader
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Kirigami.Units.smallSpacing / 2

                            Kirigami.Icon {
                                id: recentAppsHeaderIcon
                                source: 'view-history'
                                anchors.verticalCenter: parent.verticalCenter
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: rootItem.contextLabel
                                color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.55)
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.78
                            }
                        }

                        ListView {
                            id: recentAppsListView
                            anchors.left: recentAppsHeader.right
                            anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            orientation: ListView.Horizontal
                            interactive: false
                            spacing: Kirigami.Units.smallSpacing
                            clip: true

                            delegate: Item {
                                id: recentAppItem
                                width: Kirigami.Units.iconSizes.medium + Kirigami.Units.gridUnit * 2
                                height: recentAppsListView.height

                                PC3.ToolTip.text: model.display || ""
                                PC3.ToolTip.visible: recentAppHover.containsMouse && recentAppLabel.truncated
                                PC3.ToolTip.delay: 800

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -Kirigami.Units.smallSpacing / 2
                                    radius: Kirigami.Units.smallSpacing + 2
                                    color: Kirigami.Theme.highlightColor
                                    opacity: recentAppHover.containsMouse ? 0.12 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 100 } }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    Kirigami.Icon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        source: model.decoration || ""
                                        width: Kirigami.Units.iconSizes.smallMedium
                                        height: width
                                    }

                                    Text {
                                        id: recentAppLabel
                                        width: recentAppItem.width - Kirigami.Units.smallSpacing * 2
                                        text: model.display || ""
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.75
                                        font.pointSize: Math.max(6, Kirigami.Theme.defaultFont.pointSize * 0.77)
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }

                                MouseArea {
                                    id: recentAppHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (recentAppsListView.model && "trigger" in recentAppsListView.model) {
                                            recentAppsListView.model.trigger(index, "", null);
                                            root.toggle();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Categories come from Kicker's desktop-entry-aware application tree.
                    // The list model and category membership are refreshed only when Kicker refreshes.
                    ListView {
                        id: categoryFilters
                        y: categoryControls.recentAppsStripHeight
                        width: parent.width
                        height: Kirigami.Units.gridUnit * 2
                        orientation: ListView.Horizontal
                        spacing: Kirigami.Units.smallSpacing
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: rootItem.availableCategories
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            required property int index
                            readonly property bool selected: rootItem.activeCategoryRow === modelData.row
                            readonly property bool hasNew: !!rootItem.categoriesWithNewApps[modelData.row]
                            width: Math.min(categoryFilters.width - 2, chipLabel.implicitWidth + Kirigami.Units.gridUnit * 2)
                            height: categoryFilters.height - Kirigami.Units.smallSpacing
                            radius: Math.min(height / 2, Kirigami.Units.gridUnit)
                            color: selected ? Kirigami.Theme.highlightColor
                                            : (chipHover.hovered ? root.colorWithAlpha(Kirigami.Theme.textColor, 0.12)
                                                                 : root.colorWithAlpha(Kirigami.Theme.textColor, 0.06))
                            border.width: activeFocus ? 2 : 1
                            border.color: activeFocus ? Kirigami.Theme.highlightColor
                                                       : root.colorWithAlpha(Kirigami.Theme.textColor, 0.12)
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.label
                            Accessible.checked: selected
                            Accessible.description: hasNew ? i18n("New applications") : ""
                            function activate() {
                                chip.forceActiveFocus();
                                categoryFilters.currentIndex = index;
                                rootItem.selectCategory(modelData.row);
                                categoryFilters.positionViewAtIndex(index, ListView.Contain);
                            }
                            Keys.onReturnPressed: event => { activate(); event.accepted = true; }
                            Keys.onEnterPressed: event => { activate(); event.accepted = true; }
                            Keys.onSpacePressed: event => { activate(); event.accepted = true; }
                            Keys.onLeftPressed: event => {
                                categoryFilters.currentIndex = Math.max(0, index - 1);
                                categoryFilters.positionViewAtIndex(categoryFilters.currentIndex, ListView.Contain);
                                if (categoryFilters.currentItem) categoryFilters.currentItem.forceActiveFocus();
                                event.accepted = true;
                            }
                            Keys.onRightPressed: event => {
                                categoryFilters.currentIndex = Math.min(categoryFilters.count - 1, index + 1);
                                categoryFilters.positionViewAtIndex(categoryFilters.currentIndex, ListView.Contain);
                                if (categoryFilters.currentItem) categoryFilters.currentItem.forceActiveFocus();
                                event.accepted = true;
                            }
                            Keys.onDownPressed: event => {
                                allAppsGrid.tryActivate(0, 0);
                                event.accepted = true;
                            }
                            HoverHandler { id: chipHover }
                            Text {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: chip.modelData.label
                                color: chip.selected ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                font.weight: chip.selected ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, chip.width - Kirigami.Units.gridUnit)
                            }
                            Rectangle {
                                objectName: "categoryNewDot_" + chip.modelData.row
                                visible: chip.hasNew
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 4
                                width: 6
                                height: width
                                radius: width / 2
                                color: chip.selected ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.highlightColor
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: chip.activate()
                            }
                        }
                    }
                }
                // ── Plugin UI Sections ──────────────────────────────────────
                Column {
                    id: pluginSectionsColumn
                    width: parent.width
                    spacing: Kirigami.Units.largeSpacing
                    visible: pluginSectionsRepeater.count > 0

                    Repeater {
                        id: pluginSectionsRepeater
                        model: PluginSystem.uiSections()

                        delegate: Item {
                            width: pluginSectionsColumn.width
                            height: sectionLoader.implicitHeight + Kirigami.Units.largeSpacing

                            // Section header
                            Row {
                                id: sectionHeader
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: "plugins"
                                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                PlasmaExtras.Heading {
                                    level: 5
                                    text: modelData.name
                                    color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.8)
                                    font.weight: Font.Bold
                                }
                            }

                            Loader {
                                id: sectionLoader
                                anchors.top: sectionHeader.bottom
                                anchors.topMargin: Kirigami.Units.smallSpacing
                                width: parent.width
                                sourceComponent: modelData.component
                            }
                        }
                    }
                }

                // ── Tout (ex-page « Toutes les applications ») ──────────────
                RowLayout {
                    id: allAppsHeader
                    objectName: "allAppsHeader"
                    x: rootItem.sectionInset
                    // en mode Catégories : on suit la largeur réellement occupée par les tuiles
                    // (Math.floor dans CategoryTiles.qml laisse quelques pixels de côté à droite)
                    width: Plasmoid.configuration.allAppsViewMode === 2
                           ? (allAppsCategoryGrid.tileWidth * allAppsCategoryGrid.columnsCount
                              + allAppsCategoryGrid.gap * (allAppsCategoryGrid.columnsCount - 1)
                              + Kirigami.Units.largeSpacing + 5) // compense le padding du bouton + ajustement fin
                           : (parent.width - rootItem.sectionInset * 2)
                    implicitHeight: Kirigami.Units.gridUnit * 2

                    PlasmaExtras.Heading {
                        color: colorWithAlpha(Kirigami.Theme.textColor, 0.8)
                        level: 5
                        text: rootItem.activeCategoryRow < 0 ? i18n("All") : rootItem.activeCategoryName
                        font.weight: Font.Bold
                    }

                    Item { Layout.fillWidth: true }

                    PC3.ToolButton {
                        objectName: "appsListButton"
                        text: i18n("List")
                        icon.name: "view-list-details"
                        checkable: true
                        checked: Plasmoid.configuration.allAppsViewMode === 0
                        onClicked: rootItem.setAppsViewMode(0)
                    }
                    PC3.ToolButton {
                        objectName: "appsGridButton"
                        text: i18n("Grid")
                        icon.name: "view-grid"
                        checkable: true
                        checked: Plasmoid.configuration.allAppsViewMode === 1
                        onClicked: rootItem.setAppsViewMode(1)
                    }
                    SectionButton {
                        id: viewModeButton
                        showNewDot: !!rootItem.categoriesWithNewApps[-1]
                        iconName: "go-down"
                        text: i18n("Categories")
                        onClicked: {
                            if (viewModePopup.visible) viewModePopup.visible = false;
                            else viewModePopup.openFor(viewModeButton);
                        }
                    }
                }

                Item {
                    id: allAppsGridContainer
                    readonly property int listInset: Math.max(0, rootItem.sectionInset - rootItem.listIconPad)
                    readonly property bool gridMode: Plasmoid.configuration.allAppsViewMode === 1
                    x: gridMode ? 0 : listInset
                    width: parent.width - (gridMode ? 0 : listInset) * 2
                    height: rootItem.activeCategoryRow >= 0 && categoryAppsModel.count === 0
                            ? Math.max(allAppsGrid.cellHeight, emptyCategoryLabel.implicitHeight + Kirigami.Units.gridUnit * 2)
                            : allAppsGrid.height
                    visible: Plasmoid.configuration.allAppsViewMode !== 2 || rootItem.activeCategoryRow >= 0

                    Text {
                        id: emptyCategoryLabel
                        anchors.centerIn: parent
                        visible: rootItem.activeCategoryRow >= 0 && categoryAppsModel.count === 0
                        text: i18n("No applications in this category")
                        color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.65)
                    }

                    ItemGridView {
                        id: allAppsGrid
                        objectName: "allAppsGrid"
                        virtualized: true
                        viewportHeight: Math.min(height, mainFlick.height)
                        viewportOffset: Math.max(0, Math.min(height - viewportHeight,
                                                            mainFlick.contentY - allAppsGridContainer.y))
                        scrollEnabled: false
                        onWheelUnhandled: delta => mainFlick.scrollBy(delta)
                        whiteHighlight: true // surlignement blanc 50 %
                        width: parent.width
                        readonly property int columnsCount: cellWidth > 0 ? Math.max(1, Math.floor(width / cellWidth)) : 1
                        // la grille ne défile plus : elle prend toute sa hauteur, c'est la page qui défile
                        height: Math.max(1, Math.ceil((rootItem.activeCategoryRow < 0 ? rootItem.allAppsComboModel.count : categoryAppsModel.count) / columnsCount)) * cellHeight
                        itemColumns: Plasmoid.configuration.allAppsViewMode === 1 ? 1 : 2
                        labels2lines: Plasmoid.configuration.allAppsViewMode === 1 && Plasmoid.configuration.labels2lines
                        dragEnabled: true
                        dropEnabled: false
                        verticalScrollBarPolicy: PC3.ScrollBar.AlwaysOff
                        cellWidth: Plasmoid.configuration.allAppsViewMode === 1
                                   ? Math.floor(width / Math.max(1, root.colonnesAuto))
                                   : width
                        cellHeight: Plasmoid.configuration.allAppsViewMode === 1
                                    ? root.cellSizeHeight
                                    : root.iconSize + Kirigami.Units.gridUnit + Kirigami.Units.largeSpacing
                        iconSize: root.iconSize
                        clip: true
                        model: rootItem.activeCategoryRow < 0 ? rootItem.allAppsComboModel : categoryAppsModel
                        onKeyNavUp: {
                            allAppsGrid.focus = false;
                            categoryFilters.currentIndex = 0;
                            if (categoryFilters.currentItem) categoryFilters.currentItem.forceActiveFocus();
                            else searchField.focus = true;
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Tab) {
                                event.accepted = true;
                                searchField.focus = true;
                                allAppsGrid.focus = false;
                            }
                        }
                    }
                }

                CategoryTiles {
                    id: allAppsCategoryGrid
                    visible: Plasmoid.configuration.allAppsViewMode === 2 && rootItem.activeCategoryRow < 0
                    height: visible ? implicitHeight : 0
                    x: rootItem.sectionInset
                    width: parent.width - rootItem.sectionInset * 2
                    flyoutOpen: categoryFlyout.visible
                    onOpenCategory: (row, title, sx, sy) => categoryFlyout.openFor(row, title, sx, sy)
                }

                Item { width: 1; height: Kirigami.Units.largeSpacing }
                } // fin mainColumn

                // garde la ligne sélectionnée au clavier visible dans la page qui défile
                Connections {
                    target: allAppsGrid
                    function onCurrentIndexChanged() {
                        if (allAppsGrid.currentIndex < 0 || !rootItem.keyNavRecently()) return;
                        var row = Math.floor(allAppsGrid.currentIndex / allAppsGrid.columnsCount);
                        var top = allAppsGridContainer.y + row * allAppsGrid.cellHeight;
                        mainFlick.ensureVisible(top, top + allAppsGrid.cellHeight);
                    }
                }
            // la page suit aussi la sélection clavier quand on remonte vers les recommandations / les épinglés
                Connections {
                    target: globalFavoritesGrid
                    function onCurrentIndexChanged() {
                        if (globalFavoritesGrid.currentIndex < 0 || !rootItem.keyNavRecently()) return;
                        mainFlick.ensureVisible(0, globalFavoritesGrid.y + globalFavoritesGrid.height);
                    }
                }
            } // fin mainFlick


            // PAGE 3 — Search Results
            Item {
                id: searchPage
                width: view.width
                height: view.height

                function tryActivate(row, col) { runnerGrid.tryActivate(row, col); }

                // ── Filter pills (slide in when searching, hidden in shell/palette mode) ──
                Item {
                    id: filterPillsWrapper
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    clip: true
                    height: (root.searching && !searchField.text.startsWith('>') && !searchField.text.startsWith('/'))
                            ? pillsRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                            : 0

                    Behavior on height {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    Row {
                        id: pillsRow
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Repeater {
                            model: [
                                { key: "all",      label: i18n("All")      },
                                { key: "apps",     label: i18n("Apps")     },
                                { key: "settings", label: i18n("Settings") }
                            ]

                            delegate: Item {
                                id: pillDelegate
                                property bool isActive: kicker.searchRunnerFilter === modelData.key
                                height: Kirigami.Units.gridUnit * 2
                                width: pillText.implicitWidth + Kirigami.Units.gridUnit * 2

                                focus: true
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.label
                                Accessible.checked: isActive

                                function activate() {
                                    kicker.searchRunnerFilter = modelData.key;
                                    var q = searchField.text;
                                    runnerModel.query = "";
                                    runnerModel.query = q;
                                }

                                Keys.onReturnPressed: activate()
                                Keys.onSpacePressed:  activate()

                                // Fill background
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: isActive
                                           ? Kirigami.Theme.highlightColor
                                           : colorWithAlpha(Kirigami.Theme.textColor, 0.08)
                                    border.width: isActive ? 0 : 1
                                    border.color: colorWithAlpha(Kirigami.Theme.textColor, 0.12)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                // Keyboard focus ring
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -2
                                    radius: height / 2 + 2
                                    color: "transparent"
                                    border.width: pillDelegate.activeFocus ? 2 : 0
                                    border.color: Kirigami.Theme.highlightColor
                                    opacity: 0.8
                                    Behavior on border.width { NumberAnimation { duration: 80 } }
                                }

                                Text {
                                    id: pillText
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: isActive
                                           ? "white"
                                           : colorWithAlpha(Kirigami.Theme.textColor, 0.75)
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
                                    font.bold: isActive
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pillDelegate.activate()
                                }
                            }
                        }
                    }
                }

                // ── Command Palette (visible when text starts with '/') ──────
                Item {
                    id: commandPaletteContainer
                    anchors.top: filterPillsWrapper.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: Kirigami.Units.smallSpacing
                    anchors.bottom: parent.bottom
                    visible: root.searching && searchField.text.startsWith('/')

                    property string paletteQuery: searchField.text.startsWith('/')
                                                  ? searchField.text.slice(1).toLowerCase().trim()
                                                  : ""

                    // Inline calculator: /calc 2+2  or /= 2+2
                    property string calcQuery: {
                        var q = paletteQuery.trim();
                        if (q.startsWith("calc ")) return q.slice(5).trim();
                        if (q.startsWith("= "))    return q.slice(2).trim();
                        return "";
                    }

                    property string calcResult: {
                        var expr = calcQuery;
                        if (!expr) return "";
                        try {
                            var r = Function("return (" + expr + ")")();
                            if (r === undefined || (typeof r === "number" && isNaN(r))) return "";
                            return String(r);
                        } catch(e) { return ""; }
                    }

                    // Inline AI: /ai <prompt>
                    property var filteredCmds: {
                        var q = paletteQuery;
                        if (q === "") return rootItem.paletteCommands;
                        // Hide normal commands when in calc mode
                        if (calcQuery !== "") return [];
                        var ranked = root.core !== null
                            ? root.core.fuzzyRank(rootItem.paletteCommands, q)
                            : null;
                        if (ranked !== null) return ranked;
                        function fuzzyMatch(str, query) {
                            var qi = 0;
                            for (var ci = 0; ci < str.length && qi < query.length; ci++) {
                                if (str[ci] === query[qi]) qi++;
                            }
                            return qi === query.length;
                        }
                        var matches = rootItem.paletteCommands.filter(function(c) {
                            var searchStr = c.name + " " + c.desc.toLowerCase();
                            return c.name.startsWith(q) || fuzzyMatch(searchStr, q);
                        });
                        // Prefix matches first, then fuzzy-only
                        matches.sort(function(a, b) {
                            var aPrefix = a.name.startsWith(q) ? 0 : 1;
                            var bPrefix = b.name.startsWith(q) ? 0 : 1;
                            return aPrefix - bPrefix;
                        });
                        return matches;
                    }

                    // Calculator result card
                    Item {
                        id: calcResultItem
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: commandPaletteContainer.calcResult !== ""
                                ? Kirigami.Units.gridUnit * 3.5 : 0
                        clip: true
                        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Kirigami.Units.smallSpacing
                            color: root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.08)
                            border.width: 1
                            border.color: root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.22)
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Kirigami.Units.smallSpacing

                            Rectangle {
                                width: Kirigami.Units.gridUnit * 2; height: width
                                radius: width / 2
                                color: root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.18)
                                anchors.verticalCenter: parent.verticalCenter
                                Kirigami.Icon {
                                    source: "accessories-calculator"
                                    width: Kirigami.Units.iconSizes.small; height: width
                                    anchors.centerIn: parent; animated: false
                                }
                            }

                            Column {
                                spacing: 2
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    text: "= " + commandPaletteContainer.calcResult
                                    color: Kirigami.Theme.textColor
                                    font.bold: true
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                                }
                                Text {
                                    text: i18n("Enter or click to copy result")
                                    color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.55)
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.78
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                executable.exec("printf '%s' " + rootItem.shq(commandPaletteContainer.calcResult) + " | xclip -selection clipboard 2>/dev/null || printf '%s' " + rootItem.shq(commandPaletteContainer.calcResult) + " | xsel --clipboard --input 2>/dev/null");
                            }
                        }
                    }

                    // AI result card
                    // Hint when nothing narrowed yet
                    Text {
                        visible: commandPaletteContainer.paletteQuery === ""
                        anchors.left: parent.left
                        anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                        anchors.top: calcResultItem.bottom
                        anchors.topMargin: Kirigami.Units.smallSpacing
                        text: i18n("Type a command  ·  ↓ navigate  ·  /calc expr  ·  Enter run")
                        color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.42)
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.82
                    }

                    ListView {
                        id: commandPaletteList
                        anchors.top: calcResultItem.bottom
                        anchors.topMargin: Kirigami.Units.smallSpacing
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        clip: true
                        model: commandPaletteContainer.filteredCmds
                        currentIndex: -1
                        keyNavigationWraps: true

                        Keys.onReturnPressed: {
                            if (currentIndex >= 0 && currentIndex < model.length) {
                                executable.exec(model[currentIndex].cmd);
                                root.toggle();
                            }
                        }
                        Keys.onEscapePressed: {
                            currentIndex = -1;
                            searchField.forceActiveFocus();
                        }

                        highlight: Rectangle {
                            color: root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.18)
                            radius: Kirigami.Units.smallSpacing
                        }
                        highlightMoveDuration: 80

                        delegate: Item {
                            width: commandPaletteList.width
                            height: Kirigami.Units.gridUnit * 3

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: Kirigami.Units.smallSpacing
                                color: cmdItemHover.containsMouse && commandPaletteList.currentIndex !== index
                                       ? root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.08)
                                       : "transparent"
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Kirigami.Units.smallSpacing

                                Rectangle {
                                    width: Kirigami.Units.gridUnit * 2
                                    height: width
                                    radius: width / 2
                                    color: root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.15)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Kirigami.Icon {
                                        source: modelData.icon
                                        width: Kirigami.Units.iconSizes.small
                                        height: width
                                        anchors.centerIn: parent
                                        animated: false
                                    }
                                }

                                Column {
                                    spacing: 1
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        text: "/" + modelData.name
                                        color: Kirigami.Theme.textColor
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                                        font.bold: true
                                    }
                                    Text {
                                        text: modelData.desc
                                        color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.6)
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.82
                                    }
                                }
                            }

                            MouseArea {
                                id: cmdItemHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    executable.exec(modelData.cmd);
                                    root.toggle();
                                }
                            }
                        }
                    }
                }

                // ── Alt+1-9 hint (subtle, shown when results exist) ──
                Text {
                    anchors.right: parent.right
                    anchors.top: filterPillsWrapper.bottom
                    anchors.topMargin: 2
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    visible: root.searching && runnerGrid.count > 0
                             && !searchField.text.startsWith('/')
                             && !searchField.text.startsWith('>')
                    text: i18n("Alt+1–9 to launch")
                    color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.3)
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.72
                }

                // ── Results grid ──
                ItemMultiGridView {
                    id: runnerGrid
                    objectName: "runnerGrid"
                    anchors.top: filterPillsWrapper.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: pluginResultsColumn.visible ? pluginResultsColumn.top : parent.bottom
                    visible: !(root.searching && searchField.text.startsWith('/'))
                    itemColumns: 3
                    cellWidth: Math.max(1, availableWidth)
                    cellHeight: root.iconSize + Kirigami.Units.gridUnit + Kirigami.Units.largeSpacing
                    model: runnerModel
                    grabFocus: false
                    focus: false
                    onKeyNavUp: {
                        runnerGrid.focus = false;
                        searchField.focus = true;
                    }
                }

                // ── Plugin search results ──
                Column {
                    id: pluginResultsColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Kirigami.Units.smallSpacing
                    spacing: 2
                    visible: root.searching
                             && !searchField.text.startsWith('/')
                             && !searchField.text.startsWith('>')
                             && rootItem.pluginResults.length > 0

                    Repeater {
                        model: rootItem.pluginResults

                        delegate: Item {
                            id: pluginResultItem
                            width: pluginResultsColumn.width
                            height: Kirigami.Units.gridUnit * 3

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: Kirigami.Units.smallSpacing
                                color: pluginResultHover.containsMouse
                                       ? root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.10)
                                       : "transparent"
                                border.width: 1
                                border.color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.07)
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: modelData.icon || "edit-find"
                                    width: Kirigami.Units.iconSizes.smallMedium
                                    height: width
                                    anchors.verticalCenter: parent.verticalCenter
                                    animated: false
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    Text {
                                        text: modelData.title || ""
                                        color: Kirigami.Theme.textColor
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                                        elide: Text.ElideRight
                                        width: pluginResultsColumn.width
                                               - Kirigami.Units.iconSizes.smallMedium
                                               - Kirigami.Units.smallSpacing * 4
                                    }

                                    Text {
                                        visible: modelData.subtitle !== undefined && modelData.subtitle !== ""
                                        text: modelData.subtitle || ""
                                        color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.55)
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.78
                                        elide: Text.ElideRight
                                        width: pluginResultsColumn.width
                                               - Kirigami.Units.iconSizes.smallMedium
                                               - Kirigami.Units.smallSpacing * 4
                                    }
                                }
                            }

                            MouseArea {
                                id: pluginResultHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var act = modelData.action;
                                    if (typeof act === "function") act();
                                    else if (typeof act === "string") executable.exec(act);
                                    root.toggle();
                                }
                            }

                            Keys.onReturnPressed: {
                                var act = modelData.action;
                                if (typeof act === "function") act();
                                else if (typeof act === "string") executable.exec(act);
                                root.toggle();
                            }
                        }
                    }
                }

                // ── Empty state ──
                Column {
                    anchors.centerIn: parent
                    visible: root.searching && !searchField.text.startsWith('/') && runnerGrid.count === 0
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        source: searchField.text.startsWith('>') && Plasmoid.configuration.enableShellRunner
                                ? "utilities-terminal" : "edit-find-none"
                        width: Kirigami.Units.iconSizes.huge
                        height: width
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: 0.4
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            if (searchField.text.startsWith('>') && Plasmoid.configuration.enableShellRunner) {
                                var cmd = searchField.text.slice(1).trim();
                                return cmd.length > 0
                                    ? i18n("Press Enter to run: %1", cmd)
                                    : i18n("Type a shell command after '>'");
                            }
                            if (kicker.searchRunnerFilter !== "all") {
                                return i18n("No results for \"%1\" in %2",
                                            searchField.text,
                                            ({ apps: i18n("Apps"), settings: i18n("Settings") })[kicker.searchRunnerFilter] || kicker.searchRunnerFilter);
                            }
                            return i18n("No results for \"%1\"", searchField.text);
                        }
                        color: Kirigami.Theme.textColor
                        opacity: 0.55
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    }
                }
            }

        }

        // Handle wheel input in viewport coordinates, above app delegates.
        Item {
            anchors.fill: view
            visible: view.currentIndex === 0
            z: 1
            WheelHandler {
                target: null
                acceptedDevices: PointerDevice.AllDevices
                onWheel: event => {
                    var delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y
                              : event.angleDelta.y / 120 * Kirigami.Units.gridUnit * 3;
                    if (delta !== 0) {
                        mainFlick.scrollBy(delta);
                        event.accepted = true;
                    } else {
                        event.accepted = false;
                    }
                }
            }
        }

        // ── Fenêtre « Affichage » de la rubrique Tout (même style que la fenêtre du bouton Alimentation) ──
        // fenêtre système séparée : le menu principal ne doit pas se refermer quand elle prend le focus
        PlasmaCore.Dialog {
            id: viewModePopup
            flags: Qt.WindowStaysOnTopHint
            location: PlasmaCore.Types.Floating
            hideOnWindowDeactivate: true

            property Item anchorItem: null
            property bool keepMenuOpen: false

            onVisibleChanged: {
                if (visible) {
                    Qt.callLater(viewModePopup.reposition);
                } else {
                    kdeConnectPanel.hold = false;
                    root.hideOnWindowDeactivate = !kdeConnectPanel.visible;
                    if (keepMenuOpen) {
                        // choix fait dans cette fenêtre : le menu principal reste ouvert
                        keepMenuOpen = false;
                        root.requestActivate();
                    } else if (!root.active && !kdeConnectPanel.active) {
                        root.visible = false;
                    }
                }
            }

            function openFor(button) {
                anchorItem = button;
                kdeConnectPanel.hold = true;
                root.hideOnWindowDeactivate = false;
                visible = true;
            }

            function choose(mode) {
                // Fenestra : affichage rapide : le petit menu se ferme d'abord, le changement suit
                keepMenuOpen = true;
                visible = false;
                Qt.callLater(function () {
                    rootItem.setAppsViewMode(mode);
                    if (mode === 2) root.ensureCategoryModel();
                });
            }

            function reposition() {
                if (!anchorItem) return;
                // sous le bouton, alignée sur son bord droit ; au-dessus s'il n'y a pas la place dans la hauteur du menu
                var pos = anchorItem.mapToGlobal(anchorItem.width, anchorItem.height);
                x = Math.round(pos.x - width);
                var below = Math.round(pos.y + Kirigami.Units.smallSpacing);
                y = (below + height <= root.y + root.height)
                    ? below
                    : Math.round(anchorItem.mapToGlobal(0, 0).y - height - Kirigami.Units.smallSpacing);
            }

            mainItem: ColumnLayout {
                spacing: 0

                Repeater {
                    model: [
                        { mode: 2, label: i18n("Categories") },
                        { mode: 1, label: i18n("Grid") },
                        { mode: 0, label: i18n("List") }
                    ]

                    delegate: PC3.ItemDelegate {
                        id: modeItem
                        Layout.fillWidth: true
                        hoverEnabled: true
                        leftPadding: Kirigami.Units.smallSpacing + 6
                        rightPadding: Kirigami.Units.smallSpacing + 6
                        topPadding: Kirigami.Units.smallSpacing
                        bottomPadding: Kirigami.Units.smallSpacing
                        readonly property bool current: Plasmoid.configuration.allAppsViewMode === modelData.mode

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing + 6

                            Text {
                                text: "\u2713"
                                color: Kirigami.Theme.textColor
                                opacity: modeItem.current ? 1.0 : 0.0
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                                Layout.preferredWidth: Kirigami.Units.gridUnit
                            }

                            PC3.Label {
                                text: modelData.label
                                Layout.fillWidth: true
                            }
                        }

                        background: Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Kirigami.Units.smallSpacing
                            color: Kirigami.Theme.highlightColor
                            opacity: parent.hovered ? 0.18 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 100 } }
                        }

                        onClicked: viewModePopup.choose(modelData.mode)
                    }
                }
            }
        }

        // ── Fenêtre d'une catégorie (clic sur le paquet de mini-icônes ou sur le fond d'une tuile) ──
        Item {
            id: categoryFlyout
            anchors.fill: parent
            visible: false
            z: 260

            property int row: -1
            property string title: ""

            property real progress: 0          // 0 = fermée, 1 = ouverte
            property bool closing: false
            readonly property int revision: rootItem.categoryRevision   // reprend les nouveaux sous-modèles après un rafraîchissement
            property real startScale: 0.7        // taille de départ (0.5 = petit, 0.9 = discret)
            property real originX: width / 2     // point d'où la fenêtre sort (la tuile cliquée)
            property real originY: height / 2

            // catégorie contenant une nouveauté : les cellules gagnent une ligne pour le tag
            property bool hasNew: false
            readonly property real cellH: root.cellSizeHeight + (hasNew ? Kirigami.Units.gridUnit : 0)

            ListModel { id: categoryFlatModel } // liste aplatie (plus de sous-tuiles de groupe)

            function refreshHasNew() {
                var found = false;
                if (rootItem.newApps) {
                    for (var i = 0; i < categoryFlatModel.count; i++) {
                        var fid = categoryFlatModel.get(i).favoriteId;
                        if (fid && rootItem.newApps[fid]) { found = true; break; }
                    }
                }
                hasNew = found;
            }

            Connections {
                target: rootItem
                function onNewAppsChanged() { categoryFlyout.refreshHasNew(); }
            }

            function openFor(r, t, sx, sy) {
                row = r;
                title = t;
                categoryFlatModel.clear();
                if (r >= 0 && typeof categoryRootModel !== "undefined") {
                    var flat = [];
                    rootItem.collectCategoryApps(categoryRootModel.modelForRow(r), flat, {});
                    for (var k = 0; k < flat.length; k++) categoryFlatModel.append(flat[k]);
                }
                refreshHasNew();
                if (sx !== undefined && sy !== undefined) {
                    var p = mapFromItem(null, sx, sy);
                    originX = p.x;
                    originY = p.y;
                } else {
                    originX = width / 2;
                    originY = height / 2;
                }
                closeAnim.stop();
                closing = false;
                progress = 0;
                visible = true;
                openAnim.restart();
            }

            // fermeture animée (sens inverse de l'ouverture)
            function close() {
                if (!visible || closing) return;
                closing = true;
                openAnim.stop();
                closeAnim.restart();
            }

            onVisibleChanged: {
                if (!visible) {           // fermeture immédiate (ex. le menu se ferme)
                    openAnim.stop();
                    closeAnim.stop();
                    progress = 0;
                    closing = false;
                }
            }

            NumberAnimation {
                id: openAnim
                target: categoryFlyout
                property: "progress"
                to: 1
                duration: 180
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                id: closeAnim
                target: categoryFlyout
                property: "progress"
                to: 0
                duration: 140
                easing.type: Easing.InCubic
                onFinished: {
                    categoryFlyout.closing = false;
                    categoryFlyout.visible = false;
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: mouse => {
                    categoryFlyout.close();
                    mouse.accepted = true;
                }
                onWheel: wheel => { wheel.accepted = true; }
            }

            Rectangle {
                id: flyBox
                anchors.centerIn: parent
                opacity: categoryFlyout.progress
                transform: Scale {
                    origin.x: categoryFlyout.originX - flyBox.x
                    origin.y: categoryFlyout.originY - flyBox.y
                    xScale: categoryFlyout.startScale + (1 - categoryFlyout.startScale) * categoryFlyout.progress
                    yScale: xScale
                }
                width: flyGrid.width + Kirigami.Units.gridUnit * 2
                height: flyTitle.implicitHeight + flyGrid.height + Kirigami.Units.gridUnit * 3
                radius: Kirigami.Units.smallSpacing * 2 + 2
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.15)

                // un clic dans la fenêtre ne la ferme pas
                MouseArea {
                    anchors.fill: parent
                    onPressed: mouse => { mouse.accepted = true; }
                }

                Text {
                    id: flyTitle
                    anchors.top: parent.top
                    anchors.topMargin: Kirigami.Units.gridUnit
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: categoryFlyout.title
                    color: Kirigami.Theme.textColor
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                    font.weight: Font.DemiBold
                }

                ItemGridView {
                    id: flyGrid
                    whiteHighlight: true // surlignement blanc 50 %
                    onContentYChanged: rootItem.noteScrolling()
                    anchors.top: flyTitle.bottom
                    anchors.topMargin: Kirigami.Units.gridUnit
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.cellSizeWidth * 4 + Kirigami.Units.gridUnit
                    height: Math.max(1, Math.min(3, Math.ceil(count / 4))) * categoryFlyout.cellH
                    itemColumns: 1
                    labels2lines: true
                    showNewTag: true
                    favoritesModelOverride: globalFavorites
                    dragEnabled: false // liste fusionnée : la réorganisation n'a pas de sens ici
                    dropEnabled: false
                    verticalScrollBarPolicy: PC3.ScrollBar.AsNeeded
                    cellWidth: root.cellSizeWidth
                    cellHeight: categoryFlyout.cellH
                    iconSize: root.iconSize
                    clip: true
                    model: categoryFlatModel
                }
            }
        }

        PlasmaExtras.PlasmoidHeading {
            id: footer
            contentWidth: parent.width
            contentHeight: Kirigami.Units.gridUnit * 3 - 10   // pied réduit de 10 px (aligné sur le volet KDE Connect)
            anchors.bottom: parent.bottom
            position: PC3.ToolBar.Footer

            Footer {
                id: footerContent
                anchors.fill: parent
                core: root.core
                // le menu se ferme -> les fenêtres Compte / Alimentation aussi
                Connections {
                    target: root
                    function onVisibleChanged() { if (!root.visible) footerContent.closeMenus(); }
                }
                anchors.leftMargin: rootItem.margeCote
                anchors.rightMargin: rootItem.margeCote
                onTabOut: searchField.forceActiveFocus()
                onPowerMenuAboutToOpen: { kdeConnectPanel.hold = true; root.hideOnWindowDeactivate = false; }
                onPowerMenuClosed: {
                    kdeConnectPanel.hold = false;
                    root.hideOnWindowDeactivate = !kdeConnectPanel.visible;
                    // Si le clic qui a fermé la fenêtre Alimentation était à
                    // l'intérieur du menu principal, root redevient actif -
                    // on le laisse ouvert. S'il était complètement en dehors
                    // (le bureau), on ferme tout, comme sur Windows 11.
                    if (!root.active && !kdeConnectPanel.active)
                        root.visible = false;
                }
                onAccountMenuAboutToOpen: { kdeConnectPanel.hold = true; root.hideOnWindowDeactivate = false; }
                onAccountMenuClosed: {
                    kdeConnectPanel.hold = false;
                    root.hideOnWindowDeactivate = !kdeConnectPanel.visible;
                    if (!root.active && !kdeConnectPanel.active)
                        root.visible = false;
                }
            }
        }

        Rectangle {
            id: alphabetOverlay
            anchors.centerIn: view
            width: Kirigami.Units.gridUnit * 4
            height: width
            radius: Kirigami.Units.smallSpacing
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.highlightColor
            z: 50
            opacity: 0
            visible: opacity > 0
            property string currentLetter: ""
            PC3.Label {
                anchors.centerIn: parent
                text: alphabetOverlay.currentLetter
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2
            }
        }

        NumberAnimation {
            id: letterScrollAnim
            target: mainFlick
            property: "contentY"
            duration: 220
            easing.type: Easing.OutCubic
        }

        Timer {
            id: overlayTimer
            interval: 700
            repeat: false
            onTriggered: alphabetOverlay.opacity = 0
        }

        Timer {
            id: searchDebounce
            objectName: "searchDebounce"
            interval: 120
            repeat: false
            onTriggered: {
                runnerModel.query = searchField.text;
                rootItem.refreshPluginResults(searchField.text);
            }
        }

        // ── Fenêtre de catégorie — activation dispatch (liste aplatie) ───────
        Connections {
            target: flyGrid
            function onItemActivated(index, actionId, argument) {
                if (index < 0 || index >= categoryFlatModel.count) return;
                var entry = categoryFlatModel.get(index);
                if (entry.srcModel) {
                    entry.srcModel.trigger(entry.srcRow, actionId, argument);
                    root.toggle();
                }
            }
        }

        // ── All Apps grid — activation dispatch ──────────────────────────────
        Connections {
            target: allAppsGrid
            function onItemActivated(index, actionId, argument) {
                var activeModel = rootItem.activeCategoryRow < 0 ? rootItem.allAppsComboModel : categoryAppsModel;
                if (index < 0 || index >= activeModel.count) return;
                var entry = activeModel.get(index);
                if (entry.itemType === "letterHeader") return;
                if (entry.itemType === "folder") {
                    rootItem.toggleFolderExpand(index);
                } else {
                    // App item (regular or indented folder child)
                    if (entry.sourceRow >= 0) {
                        sortedAppsModel.trigger(entry.sourceRow, "", null);
                        root.toggle();
                    } else {
                        // Indented child — look up row in sortedAppsModel by favoriteId
                        for (var i = 0; i < sortedAppsModel.rowCount(); i++) {
                            var midx = sortedAppsModel.index(i, 0);
                            if (sortedAppsModel.data(midx, rootItem.kickerFavoriteIdRole) === entry.favoriteId) {
                                sortedAppsModel.trigger(i, "", null);
                                root.toggle();
                                return;
                            }
                        }
                    }
                }
            }
        }

        // ── All Apps grid: folder edit button dispatch ───────────────────────
        Connections {
            target: allAppsGrid
            function onFolderEditRequested(index) {
                if (rootItem.activeCategoryRow >= 0 || index < 0 || index >= rootItem.allAppsComboModel.count) return
                var entry = rootItem.allAppsComboModel.get(index)
                if (!entry || entry.itemType !== "folder") return
                var cols = Math.max(1, Math.floor(allAppsGrid.width / allAppsGrid.cellWidth))
                var row = Math.floor(index / cols)
                var itemY = row * allAppsGrid.cellHeight
                var p = allAppsGrid.mapToItem(rootItem, allAppsGrid.width * 0.55,
                                              itemY + allAppsGrid.cellHeight)
                rootItem.openFolderAppPicker(entry.folderIdx, p.x, p.y)
            }
        }

        // ── Folder content popup ─────────────────────────────────────────────
        // Click-outside dismiss layer
        MouseArea {
            id: folderPopupDismiss
            anchors.fill: parent
            z: 198
            visible: folderContentPopup.visible
            onClicked: folderContentPopup.visible = false
        }

        Item {
            id: folderContentPopup
            visible: false
            z: 200
            width: 240
            height: popupBg.height

            function showAt(idx, tileX, tileY, tileW, tileH) {
                folderContentPopup.property_folderIndex = idx;
                var h = popupBg.height;
                x = Math.max(0, Math.min(tileX, rootItem.width - width));
                y = tileY - h - Kirigami.Units.smallSpacing;
                if (y < 0) y = tileY + tileH + Kirigami.Units.smallSpacing;
                visible = true;
            }

            property int property_folderIndex: -1

            Rectangle {
                id: popupBg
                width: parent.width
                height: popupColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.15)

                Column {
                    id: popupColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: 2

                    Text {
                        leftPadding: Kirigami.Units.smallSpacing
                        text: folderContentPopup.property_folderIndex >= 0 && folderContentPopup.property_folderIndex < rootItem.pinnedFoldersData.length
                              ? rootItem.pinnedFoldersData[folderContentPopup.property_folderIndex].name
                              : ""
                        font.bold: true
                        color: Kirigami.Theme.textColor
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                    }

                    Repeater {
                        model: folderContentPopup.property_folderIndex >= 0 && folderContentPopup.property_folderIndex < rootItem.pinnedFoldersData.length
                               ? rootItem.pinnedFoldersData[folderContentPopup.property_folderIndex].items
                               : []

                        delegate: Item {
                            width: folderContentPopup.width - Kirigami.Units.smallSpacing * 2
                            height: Kirigami.Units.gridUnit * 2.5

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: Kirigami.Units.smallSpacing
                                color: appEntryHover.containsMouse
                                       ? root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.12)
                                       : "transparent"
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: rootItem.iconForId(modelData)
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    animated: false
                                }

                                Text {
                                    text: rootItem.displayNameForId(modelData)
                                    color: Kirigami.Theme.textColor
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            MouseArea {
                                id: appEntryHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    folderContentPopup.visible = false;
                                    rootItem.launchFolderApp(modelData);
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Create-folder overlay ────────────────────────────────────────────
        Item {
            id: createFolderOverlay
            anchors.fill: parent
            visible: false
            z: 202

            // Dim background
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.45
                MouseArea { anchors.fill: parent; onClicked: createFolderOverlay.visible = false }
            }

            // Dialog card
            Rectangle {
                id: createDialog
                width: Math.min(340, rootItem.width - Kirigami.Units.largeSpacing * 4)
                height: dialogCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                anchors.centerIn: parent
                radius: Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.15)

                Column {
                    id: dialogCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Text {
                        text: i18n("New folder")
                        color: Kirigami.Theme.textColor
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    }

                    PC3.TextField {
                        id: newFolderNameField
                        width: parent.width
                        placeholderText: i18n("Folder name")
                    }

                    Text {
                        text: i18n("Choose from pinned apps:")
                        color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.7)
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
                        topPadding: Kirigami.Units.smallSpacing
                    }

                    // App picker list
                    Rectangle {
                        width: parent.width
                        height: 160
                        radius: Kirigami.Units.smallSpacing
                        color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.05)
                        clip: true

                        ListView {
                            id: appPickerListView
                            anchors.fill: parent
                            anchors.margins: 4
                            model: globalFavorites
                            clip: true

                            property var checkedIds: []

                            delegate: Item {
                                width: appPickerListView.width
                                height: Kirigami.Units.gridUnit * 2.5

                                property string favId: model.favoriteId !== undefined ? model.favoriteId : ""
                                property bool isChecked: appPickerListView.checkedIds.indexOf(favId) >= 0

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: Kirigami.Units.smallSpacing
                                    color: pickHover.containsMouse
                                           ? root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.08)
                                           : "transparent"
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: Kirigami.Units.smallSpacing
                                    anchors.rightMargin: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.smallSpacing

                                    CheckBox {
                                        anchors.verticalCenter: parent.verticalCenter
                                        checked: isChecked
                                        onToggled: {
                                            if (!favId) return;
                                            var arr = appPickerListView.checkedIds.slice();
                                            var idx = arr.indexOf(favId);
                                            if (checked && idx < 0) arr.push(favId);
                                            else if (!checked && idx >= 0) arr.splice(idx, 1);
                                            appPickerListView.checkedIds = arr;
                                        }
                                    }

                                    Kirigami.Icon {
                                        source: model.decoration !== undefined ? model.decoration : ""
                                        width: Kirigami.Units.iconSizes.small
                                        height: width
                                        animated: false
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: model.display !== undefined ? model.display : ""
                                        color: Kirigami.Theme.textColor
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                                        elide: Text.ElideRight
                                        width: appPickerListView.width - Kirigami.Units.iconSizes.small
                                               - Kirigami.Units.gridUnit * 2 - Kirigami.Units.smallSpacing * 3
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: pickHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (!favId) return;
                                        var arr = appPickerListView.checkedIds.slice();
                                        var idx = arr.indexOf(favId);
                                        if (idx >= 0) arr.splice(idx, 1);
                                        else arr.push(favId);
                                        appPickerListView.checkedIds = arr;
                                    }
                                }
                            }
                        }
                    }

                    // Action buttons
                    RowLayout {
                        width: parent.width

                        Item { Layout.fillWidth: true }

                        PC3.Button {
                            text: i18n("Cancel")
                            onClicked: createFolderOverlay.visible = false
                        }

                        PC3.Button {
                            text: i18n("Create")
                            highlighted: true
                            enabled: newFolderNameField.text.trim().length > 0
                                  && appPickerListView.checkedIds.length > 0
                            onClicked: {
                                var folders = rootItem.pinnedFoldersData.slice();
                                folders.push({
                                    name: newFolderNameField.text.trim(),
                                    items: appPickerListView.checkedIds.slice()
                                });
                                rootItem.pinnedFoldersData = folders;
                                rootItem.saveFolders();
                                createFolderOverlay.visible = false;
                            }
                        }
                    }
                }
            }
        }

        // ── Folder context menu (right-click on tile) ───────────────────────
        Menu {
            id: folderContextMenu
            property int targetIndex: -1

            MenuItem {
                text: i18n("Rename folder")
                icon.name: "edit-rename"
                onTriggered: {
                    var idx = folderContextMenu.targetIndex;
                    if (idx < 0 || idx >= rootItem.pinnedFoldersData.length) return;
                    folderRenameField.text = rootItem.pinnedFoldersData[idx].name;
                    folderRenameOverlay.targetIndex = idx;
                    folderRenameOverlay.visible = true;
                    folderRenameField.forceActiveFocus();
                    folderRenameField.selectAll();
                }
            }

            MenuItem {
                text: i18n("Delete folder")
                icon.name: "delete"
                onTriggered: {
                    var folders = rootItem.pinnedFoldersData.slice();
                    folders.splice(folderContextMenu.targetIndex, 1);
                    rootItem.pinnedFoldersData = folders;
                    rootItem.saveFolders();
                }
            }

            MenuItem {
                text: i18n("Unpin all apps in folder")
                icon.name: "bookmark-remove"
                onTriggered: {
                    if (folderContextMenu.targetIndex < 0) return;
                    var folder = rootItem.pinnedFoldersData[folderContextMenu.targetIndex];
                    if (!folder) return;
                    folder.items.forEach(function(id) {
                        if (globalFavorites.isFavorite(id))
                            globalFavorites.removeFavorite(id);
                    });
                    var folders = rootItem.pinnedFoldersData.slice();
                    folders.splice(folderContextMenu.targetIndex, 1);
                    rootItem.pinnedFoldersData = folders;
                    rootItem.saveFolders();
                }
            }
        }

        // ── Folder rename overlay ────────────────────────────────────────────
        Item {
            id: folderRenameOverlay
            anchors.fill: parent
            visible: false
            z: 202

            property int targetIndex: -1

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.45
                MouseArea { anchors.fill: parent; onClicked: folderRenameOverlay.visible = false }
            }

            Rectangle {
                width: Math.min(300, rootItem.width - Kirigami.Units.largeSpacing * 4)
                height: renameDialogCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                anchors.centerIn: parent
                radius: Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.15)

                Column {
                    id: renameDialogCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Text {
                        text: i18n("Rename Folder")
                        color: Kirigami.Theme.textColor
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.05
                    }

                    PC3.TextField {
                        id: folderRenameField
                        width: parent.width
                        Keys.onReturnPressed: renameSaveBtn.clicked()
                        Keys.onEscapePressed: folderRenameOverlay.visible = false
                    }

                    RowLayout {
                        width: parent.width
                        Item { Layout.fillWidth: true }
                        PC3.Button {
                            text: i18n("Cancel")
                            onClicked: folderRenameOverlay.visible = false
                        }
                        PC3.Button {
                            id: renameSaveBtn
                            text: i18n("Save")
                            highlighted: true
                            enabled: folderRenameField.text.trim().length > 0
                            onClicked: {
                                var folders = rootItem.pinnedFoldersData.slice();
                                if (folderRenameOverlay.targetIndex >= 0 && folderRenameOverlay.targetIndex < folders.length) {
                                    folders[folderRenameOverlay.targetIndex] = {
                                        name: folderRenameField.text.trim(),
                                        items: folders[folderRenameOverlay.targetIndex].items
                                    };
                                    rootItem.pinnedFoldersData = folders;
                                    rootItem.saveFolders();
                                }
                                folderRenameOverlay.visible = false;
                            }
                        }
                    }
                }
            }
        }

        // ── All Apps folder popup ────────────────────────────────────────────
        MouseArea {
            anchors.fill: parent
            z: 199
            visible: allAppsFolderPopup.visible
            onClicked: allAppsFolderPopup.visible = false
        }

        Item {
            id: allAppsFolderPopup
            visible: false
            z: 200
            width: 240
            height: aafPopupBg.height

            property int folderIndex: -1

            function showAt(idx, tileX, tileY, tileW, tileH) {
                folderIndex = idx;
                var h = aafPopupBg.height;
                x = Math.max(0, Math.min(tileX, rootItem.width - width));
                y = tileY - h - Kirigami.Units.smallSpacing;
                if (y < 0) y = tileY + tileH + Kirigami.Units.smallSpacing;
                visible = true;
            }

            Rectangle {
                id: aafPopupBg
                width: parent.width
                height: aafPopupCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.15)

                Column {
                    id: aafPopupCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: 2

                    Text {
                        leftPadding: Kirigami.Units.smallSpacing
                        text: allAppsFolderPopup.folderIndex >= 0
                              && allAppsFolderPopup.folderIndex < rootItem.allAppsFoldersData.length
                              ? rootItem.allAppsFoldersData[allAppsFolderPopup.folderIndex].name : ""
                        font.bold: true
                        color: Kirigami.Theme.textColor
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                    }

                    Repeater {
                        model: allAppsFolderPopup.folderIndex >= 0
                               && allAppsFolderPopup.folderIndex < rootItem.allAppsFoldersData.length
                               ? rootItem.allAppsFoldersData[allAppsFolderPopup.folderIndex].items : []

                        delegate: Item {
                            width: allAppsFolderPopup.width - Kirigami.Units.smallSpacing * 2
                            height: Kirigami.Units.gridUnit * 2.5

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: Kirigami.Units.smallSpacing
                                color: aafAppHover.containsMouse
                                       ? root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.12) : "transparent"
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                                anchors.right: removeFromFolderBtn.left
                                anchors.rightMargin: Kirigami.Units.smallSpacing
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: rootItem.iconForId(modelData)
                                    width: Kirigami.Units.iconSizes.small; height: width
                                    animated: false
                                }
                                Text {
                                    text: rootItem.displayNameForId(modelData)
                                    color: Kirigami.Theme.textColor
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                                    elide: Text.ElideRight
                                    width: allAppsFolderPopup.width - Kirigami.Units.iconSizes.small
                                           - Kirigami.Units.gridUnit * 3.5
                                }
                            }

                            // Remove-from-folder × button
                            Text {
                                id: removeFromFolderBtn
                                anchors.right: parent.right
                                anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                                anchors.verticalCenter: parent.verticalCenter
                                text: "×"
                                color: removeHover.containsMouse
                                       ? Kirigami.Theme.negativeTextColor
                                       : root.colorWithAlpha(Kirigami.Theme.textColor, 0.35)
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                                visible: aafAppHover.containsMouse || removeHover.containsMouse

                                MouseArea {
                                    id: removeHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var fi = allAppsFolderPopup.folderIndex;
                                        if (fi < 0 || fi >= rootItem.allAppsFoldersData.length) return;
                                        var folders = rootItem.allAppsFoldersData.slice();
                                        var folder = folders[fi];
                                        var idx = folder.items.indexOf(modelData);
                                        if (idx < 0) return;
                                        var newItems = folder.items.slice();
                                        newItems.splice(idx, 1);
                                        folders[fi] = { name: folder.name, items: newItems, createdAt: folder.createdAt || 0 };
                                        rootItem.allAppsFoldersData = folders;
                                        rootItem.saveAllAppsFolders();
                                    }
                                }
                            }

                            MouseArea {
                                id: aafAppHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    allAppsFolderPopup.visible = false;
                                    rootItem.launchFolderApp(modelData);
                                }
                            }
                        }
                    }

                    // Empty state
                    Text {
                        visible: allAppsFolderPopup.folderIndex >= 0
                                 && allAppsFolderPopup.folderIndex < rootItem.allAppsFoldersData.length
                                 && rootItem.allAppsFoldersData[allAppsFolderPopup.folderIndex].items.length === 0
                        leftPadding: Kirigami.Units.smallSpacing
                        topPadding: Kirigami.Units.smallSpacing
                        bottomPadding: Kirigami.Units.smallSpacing
                        text: i18n("Drag apps here to add them")
                        color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.45)
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
                        font.italic: true
                    }
                }
            }
        }

        // ── All Apps folder context menu ─────────────────────────────────────
        Menu {
            id: allAppsFolderContextMenu
            property int targetIndex: -1

            MenuItem {
                text: i18n("Rename folder")
                icon.name: "edit-rename"
                onTriggered: {
                    var idx = allAppsFolderContextMenu.targetIndex;
                    if (idx < 0 || idx >= rootItem.allAppsFoldersData.length) return;
                    aafRenameField.text = rootItem.allAppsFoldersData[idx].name;
                    aafRenameOverlay.targetIndex = idx;
                    aafRenameOverlay.visible = true;
                    aafRenameField.forceActiveFocus();
                    aafRenameField.selectAll();
                }
            }

            MenuItem {
                text: i18n("Delete folder")
                icon.name: "delete"
                onTriggered: {
                    var folders = rootItem.allAppsFoldersData.slice();
                    folders.splice(allAppsFolderContextMenu.targetIndex, 1);
                    rootItem.allAppsFoldersData = folders;
                    rootItem.saveAllAppsFolders();
                }
            }
        }

        // ── Create All Apps folder overlay ───────────────────────────────────
        Item {
            id: createAllAppsFolderOverlay
            anchors.fill: parent
            visible: false
            z: 202

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.45
                MouseArea { anchors.fill: parent; onClicked: createAllAppsFolderOverlay.visible = false }
            }

            Rectangle {
                width: Math.min(300, rootItem.width - Kirigami.Units.largeSpacing * 4)
                height: aafCreateCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                anchors.centerIn: parent
                radius: Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.15)

                Column {
                    id: aafCreateCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Text {
                        text: i18n("New folder")
                        color: Kirigami.Theme.textColor
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    }

                    PC3.TextField {
                        id: newAllAppsFolderNameField
                        width: parent.width
                        placeholderText: i18n("Folder name")
                        Keys.onReturnPressed: {
                            if (text.trim().length > 0) aafCreateBtn.clicked()
                        }
                        Keys.onEscapePressed: createAllAppsFolderOverlay.visible = false
                    }

                    Text {
                        text: i18n("Drag apps from the list into this folder to add them.")
                        color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.6)
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.82
                        wrapMode: Text.Wrap
                        width: parent.width
                    }

                    RowLayout {
                        width: parent.width
                        Item { Layout.fillWidth: true }
                        PC3.Button {
                            text: i18n("Cancel")
                            onClicked: createAllAppsFolderOverlay.visible = false
                        }
                        PC3.Button {
                            id: aafCreateBtn
                            text: i18n("Create")
                            highlighted: true
                            enabled: newAllAppsFolderNameField.text.trim().length > 0
                            onClicked: {
                                var folders = rootItem.allAppsFoldersData.slice();
                                folders.push({
                                    name: newAllAppsFolderNameField.text.trim(),
                                    items: [],
                                    createdAt: Date.now()
                                });
                                rootItem.allAppsFoldersData = folders;
                                rootItem.saveAllAppsFolders();
                                createAllAppsFolderOverlay.visible = false;
                            }
                        }
                    }
                }
            }
        }

        // ── All Apps folder rename overlay ───────────────────────────────────
        Item {
            id: aafRenameOverlay
            anchors.fill: parent
            visible: false
            z: 202
            property int targetIndex: -1

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.45
                MouseArea { anchors.fill: parent; onClicked: aafRenameOverlay.visible = false }
            }

            Rectangle {
                width: Math.min(300, rootItem.width - Kirigami.Units.largeSpacing * 4)
                height: aafRenameCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                anchors.centerIn: parent
                radius: Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.15)

                Column {
                    id: aafRenameCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Text {
                        text: i18n("Rename Folder")
                        color: Kirigami.Theme.textColor
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    }

                    PC3.TextField {
                        id: aafRenameField
                        width: parent.width
                        Keys.onReturnPressed: aafRenameConfirmBtn.clicked()
                        Keys.onEscapePressed: aafRenameOverlay.visible = false
                    }

                    RowLayout {
                        width: parent.width
                        Item { Layout.fillWidth: true }
                        PC3.Button {
                            text: i18n("Cancel")
                            onClicked: aafRenameOverlay.visible = false
                        }
                        PC3.Button {
                            id: aafRenameConfirmBtn
                            text: i18n("Rename")
                            highlighted: true
                            enabled: aafRenameField.text.trim().length > 0
                            onClicked: {
                                var idx = aafRenameOverlay.targetIndex;
                                var folders = rootItem.allAppsFoldersData.slice();
                                if (idx >= 0 && idx < folders.length) {
                                    folders[idx] = {
                                        name: folderRenameField.text.trim(),
                                        items: folders[idx].items,
                                        createdAt: folders[idx].createdAt || 0
                                    };
                                    rootItem.allAppsFoldersData = folders;
                                    rootItem.saveAllAppsFolders();
                                }
                                aafRenameOverlay.visible = false;
                            }
                        }
                    }
                }
            }
        }

        // ── All Apps folder app-picker popup ────────────────────────────────
        MouseArea {
            anchors.fill: parent
            z: 204
            visible: folderAppPickerPopup.visible
            onClicked: {
                folderAppPickerPopup.visible = false
                if (rootItem._needsComboRebuild) {
                    rootItem._needsComboRebuild = false
                    rootItem.buildAllAppsCombo()
                }
            }
        }

        Item {
            id: folderAppPickerPopup
            visible: false
            z: 205
            width: 300
            height: 400

            property int folderIndex: -1

            function openForFolder(idx, px, py) {
                folderIndex = idx
                pickerSearchField.text = ""
                rebuildPickerModel()
                var popW = width, popH = height
                x = Math.max(4, Math.min(px - popW / 2, rootItem.width - popW - 4))
                var yAbove = py - popH - 4
                y = yAbove >= 4 ? yAbove : Math.min(py + 4, rootItem.height - popH - 4)
                y = Math.max(4, y)
                visible = true
                pickerSearchField.forceActiveFocus()
            }

            function rebuildPickerModel() {
                pickerAppsModel.clear()
                if (folderIndex < 0 || folderIndex >= rootItem.allAppsFoldersData.length) return
                var folder = rootItem.allAppsFoldersData[folderIndex]
                var folderItems = folder.items || []
                var otherIds = {}
                for (var fi = 0; fi < rootItem.allAppsFoldersData.length; fi++) {
                    if (fi === folderIndex) continue
                    var f = rootItem.allAppsFoldersData[fi]
                    if (f.items) for (var j = 0; j < f.items.length; j++) otherIds[f.items[j]] = true
                }
                for (var i = 0; i < sortedAppsModel.rowCount(); i++) {
                    var midx = sortedAppsModel.index(i, 0)
                    var fid = sortedAppsModel.data(midx, rootItem.kickerFavoriteIdRole) || ""
                    if (!fid || otherIds[fid]) continue
                    pickerAppsModel.append({
                        appName: sortedAppsModel.data(midx, rootItem.kickerDisplayRole) || rootItem.displayNameForId(fid),
                        appIcon: sortedAppsModel.data(midx, rootItem.kickerDecorationRole) || rootItem.iconForId(fid),
                        appId: fid,
                        inFolder: folderItems.indexOf(fid) >= 0
                    })
                }
            }

            function toggleApp(appId) {
                if (folderIndex < 0 || folderIndex >= rootItem.allAppsFoldersData.length) return
                var folders = rootItem.allAppsFoldersData.slice()
                var folder = folders[folderIndex]
                var items = (folder.items || []).slice()
                var pos = items.indexOf(appId)
                var nowIn = pos < 0
                if (pos >= 0) items.splice(pos, 1)
                else items.push(appId)
                folders[folderIndex] = { name: folder.name, items: items, createdAt: folder.createdAt || 0 }
                rootItem.allAppsFoldersData = folders
                rootItem.saveAllAppsFolders()
                for (var i = 0; i < pickerAppsModel.count; i++) {
                    var e = pickerAppsModel.get(i)
                    if (e.appId === appId) {
                        pickerAppsModel.set(i, { appName: e.appName, appIcon: e.appIcon, appId: appId, inFolder: nowIn })
                        break
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.18)

                Column {
                    id: pickerFrameCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Text {
                        width: parent.width
                        text: folderAppPickerPopup.folderIndex >= 0
                              && folderAppPickerPopup.folderIndex < rootItem.allAppsFoldersData.length
                              ? i18n("Add apps — %1", rootItem.allAppsFoldersData[folderAppPickerPopup.folderIndex].name)
                              : i18n("Add apps to folder")
                        color: Kirigami.Theme.textColor
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                        elide: Text.ElideRight
                    }

                    PC3.TextField {
                        id: pickerSearchField
                        width: parent.width
                        placeholderText: i18n("Filter…")
                        Keys.onEscapePressed: {
                            folderAppPickerPopup.visible = false
                            if (rootItem._needsComboRebuild) {
                                rootItem._needsComboRebuild = false
                                rootItem.buildAllAppsCombo()
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 310
                        color: root.colorWithAlpha(Kirigami.Theme.textColor, 0.04)
                        radius: Kirigami.Units.smallSpacing
                        clip: true

                        ListView {
                            id: pickerListView
                            anchors.fill: parent
                            anchors.margins: 2
                            model: pickerAppsModel
                            clip: true

                            PC3.ScrollBar.vertical: PC3.ScrollBar {
                                policy: pickerListView.contentHeight > pickerListView.height
                                        ? PC3.ScrollBar.AlwaysOn : PC3.ScrollBar.AlwaysOff
                                width: 6
                            }

                            delegate: Item {
                                readonly property bool matchesSearch: {
                                    var q = pickerSearchField.text.toLowerCase()
                                    return q === "" || model.appName.toLowerCase().indexOf(q) >= 0
                                }
                                width: pickerListView.width
                                height: matchesSearch ? Math.round(Kirigami.Units.gridUnit * 2.2) : 0
                                clip: true
                                visible: matchesSearch

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: Kirigami.Units.smallSpacing
                                    color: pickerRowHover.containsMouse
                                           ? root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.12)
                                           : "transparent"
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }

                                Kirigami.Icon {
                                    id: pickerAppIcon
                                    anchors.left: parent.left
                                    anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: model.appIcon
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    animated: false
                                }

                                Text {
                                    anchors.left: pickerAppIcon.right
                                    anchors.leftMargin: Kirigami.Units.smallSpacing
                                    anchors.right: pickerCheckRect.left
                                    anchors.rightMargin: Kirigami.Units.smallSpacing
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: model.appName
                                    color: Kirigami.Theme.textColor
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    id: pickerCheckRect
                                    anchors.right: parent.right
                                    anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Kirigami.Units.gridUnit
                                    height: width
                                    radius: 3
                                    border.width: 1.5
                                    border.color: model.inFolder
                                                  ? Kirigami.Theme.highlightColor
                                                  : root.colorWithAlpha(Kirigami.Theme.textColor, 0.35)
                                    color: model.inFolder ? Kirigami.Theme.highlightColor : "transparent"
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                    Behavior on border.color { ColorAnimation { duration: 80 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✓"
                                        color: "white"
                                        font.pixelSize: parent.width * 0.62
                                        visible: model.inFolder
                                    }
                                }

                                MouseArea {
                                    id: pickerRowHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: folderAppPickerPopup.toggleApp(model.appId)
                                }
                            }
                        }
                    }
                }
            }

            ListModel { id: pickerAppsModel }
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Control) {
                rootItem.ctrlHeld = true;
            }
            if (event.modifiers & Qt.ShiftModifier && event.text !== "") {
                searchField.focus = true;
                return;
            }
            // Ctrl+1..9 — quick-launch pinned apps on current page
            if (event.modifiers === Qt.ControlModifier) {
                var digit = event.key - Qt.Key_1;
                if (digit >= 0 && digit <= 8) {
                    var perPage = root.colonnesAuto * Plasmoid.configuration.numberRows;
                    var appIdx = rootItem.pinnedCurrentPage * perPage + digit;
                    if (appIdx < globalFavorites.count) {
                        event.accepted = true;
                        rootItem.recordLaunch(globalFavorites.favorites[appIdx]);
                        globalFavorites.trigger(appIdx, "", null);
                        root.toggle();
                    }
                    return;
                }
            }
            // Alt+1-9 — quick-launch Nth search result
            if (view.currentIndex === 1 && event.modifiers === Qt.AltModifier) {
                var altDigit = event.key - Qt.Key_1;
                if (altDigit >= 0 && altDigit <= 8) {
                    event.accepted = true;
                    var resultCount = 0;
                    for (var si = 0; si < runnerGrid.count; si++) {
                        var sg = runnerGrid.subGridAt(si);
                        if (!sg) continue;
                        if (resultCount + sg.count > altDigit) {
                            var localIdx = altDigit - resultCount;
                            if ("trigger" in sg.model) {
                                sg.model.trigger(localIdx, "", null);
                                root.toggle();
                            }
                            return;
                        }
                        resultCount += sg.count;
                    }
                    return;
                }
            }

            if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_F) {
                event.accepted = true;
                searchField.focus = true;
                return;
            }
            if (event.key === Qt.Key_Escape) {
                event.accepted = true;
                if (categoryFlyout.visible) {
                        categoryFlyout.close();
                    } else if (viewModePopup.visible) {
                        viewModePopup.visible = false;
                    } else if (root.searching) {
                    reset();
                } else {
                    root.visible = false;
                }
                return;
            }

            if (searchField.focus) {
                return;
            }

            if (event.key === Qt.Key_Backspace) {
                event.accepted = true;
                searchField.backspace();
            } else if (event.text !== "") {
                event.accepted = true;
                searchField.appendText(event.text);
            }
        }

        Keys.onReleased: event => {
            if (event.key === Qt.Key_Control) {
                rootItem.ctrlHeld = false;
            }
        }
    }

    function setModels() {
        globalFavoritesGrid.model = globalFavorites;
        // Row order: [RecentApps(0), AllApps(1)].
        recentAppsListView.model = rootModel.modelForRow(0);
        var allAppsRow = 1;
        sortedAppsModel.sourceModel = rootModel.modelForRow(allAppsRow);
        rootItem.buildAllAppsCombo();
        rootItem.rebuildSelectedCategory();
    }

    property bool categoryModelLoaded: false

    function setCategoryModel() {
        allAppsCategoryGrid.model = categoryRootModel;
    }

    function ensureCategoryModel() {
        if (!categoryModelLoaded) {
            categoryModelLoaded = true;
            categoryRootModel.appletInterface = kicker;
            categoryRootModel.refreshed.connect(setCategoryModel);
            categoryRootModel.refresh();
        }
    }

    function scrollToLetter(letter) {
        if ((rootItem.activeCategoryRow < 0 ? rootItem.allAppsComboModel.count : categoryAppsModel.count) === 0) return;

        alphabetOverlay.currentLetter = letter;
        alphabetOverlay.opacity = 1;
        overlayTimer.restart();

        var targetIndex = -1;
        var activeModel = rootItem.activeCategoryRow < 0 ? rootItem.allAppsComboModel : categoryAppsModel;
        for (var i = 0; i < activeModel.count; i++) {
            var entry = activeModel.get(i);
            if (entry.indented) continue;  // skip expanded folder children
            var name = entry.display;
            if (name && name.length > 0) {
                var c = name[0].toUpperCase();
                if (letter === "#") {
                    if (c < "A" || c > "Z") { targetIndex = i; break; }
                } else if (c >= letter) {
                    targetIndex = i; break;
                }
            }
        }
        if (targetIndex < 0) return;

        var columns = Math.max(1, Math.floor(allAppsGrid.width / allAppsGrid.cellWidth));
        var targetY = allAppsGridContainer.y + Math.floor(targetIndex / columns) * allAppsGrid.cellHeight;
        var maxY = Math.max(0, mainFlick.contentHeight - mainFlick.height);
        targetY = Math.min(targetY, maxY);

        allAppsGrid.currentIndex = -1;
        letterScrollAnim.stop();
        letterScrollAnim.to = targetY;
        letterScrollAnim.start();
    }

    Component.onCompleted: {
        rootModel.refreshed.connect(setModels);
        reset();
        rootModel.refresh();
    }
}
