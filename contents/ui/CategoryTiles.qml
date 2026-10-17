/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Part of Fenestra Menu 11 (naykkalak, 2026), a fork of Menu 11 Next by Eisteed,
 * itself based on Menu 11 / Ditto Menu by adhe (GPL-2.0-or-later).
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
/*
    Vue « Catégories » façon Windows 11 : une tuile par catégorie du menu KDE.
      - jusqu'à 4 applis : 4 grosses icônes ;
      - plus de 4 : les 3 applis lancées le plus récemment en grosses icônes (un clic les lance)
        + un paquet de 4 mini-icônes qui ouvre la fenêtre de la catégorie.
    Un clic sur le fond de la tuile ouvre aussi la fenêtre de la catégorie.
*/

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3   // infobulle compacte (PC3.ToolTip)
import "code/tools.js" as Tools

Item {
    id: tiles

    // modèle des catégories (Kicker.RootModel non plat) ; renseigné par MenuRepresentation (setCategoryModel)
    property var model: null
    // vrai tant que la fenêtre de catégorie est affichée (le survol des tuiles est alors coupé)
    property bool flyoutOpen: false
    // change à chaque rafraîchissement du catalogue : les tuiles reprennent alors les nouveaux sous-modèles
    readonly property int revision: (typeof rootItem !== "undefined") ? rootItem.categoryRevision : 0

    readonly property int favoriteIdRole: Qt.UserRole + 3
    readonly property int columnsCount: 4
    readonly property real gap: Kirigami.Units.gridUnit
    readonly property real tileWidth: Math.max(60, Math.floor((width - gap * (columnsCount - 1)) / columnsCount))
    readonly property real tileHeight: Math.round(tileWidth * 0.97)
    readonly property real labelHeight: Math.round(Kirigami.Units.gridUnit * 1.6)

    signal openCategory(int row, string title, real sceneX, real sceneY)

    implicitHeight: flow.implicitHeight
    height: implicitHeight

    // menu du clic droit sur une grosse icône (mêmes actions que dans la fenêtre de la catégorie)
    ActionMenu {
        id: tileActionMenu
        property var targetSub: null
        property int targetRow: -1

        onActionClicked: {
            if (!targetSub) return;
            var close = (Tools.triggerAction(targetSub, targetRow, actionId, actionArgument) === true);
            if (close) root.toggle();
        }
    }

    Flow {
        id: flow
        width: tiles.width
        spacing: tiles.gap

        Repeater {
            model: tiles.model

            delegate: Item {
                id: cat

                readonly property int catIndex: index
                property var sub: (tiles.revision >= 0 && tiles.model) ? tiles.model.modelForRow(index) : null
                property int appCount: sub ? sub.count : 0
                property var apps: []
                property string title: {
                    if (!tiles.model) return "";
                    var n = tiles.model.data(tiles.model.index(index, 0), Qt.DisplayRole);
                    return n || (sub ? sub.description : "") || "";
                }
                readonly property bool overflow: appCount > 4
                readonly property int bigCount: overflow ? 3 : Math.min(4, appCount)
                readonly property bool hasNew: {
                    if (typeof rootItem === "undefined" || !rootItem.newApps) return false;
                    for (var i = 0; i < apps.length; i++) if (rootItem.newApps[apps[i].fid]) return true;
                    return false;
                }

                width: tiles.tileWidth
                height: tiles.tileHeight + tiles.labelHeight
                visible: appCount > 0

                // applis de la catégorie : dernière utilisation (dans ce menu) d'abord, puis ordre alphabétique
                function rebuild() {
                    var list = [];
                    if (sub && typeof rootItem !== "undefined") {
                        var flat = [];
                        rootItem.collectCategoryApps(sub, flat, {});
                        for (var i = 0; i < flat.length; i++) {
                            var entry = flat[i];
                            var e = rootItem.launchCounts ? rootItem.launchCounts[entry.favoriteId] : null;
                            list.push({
                                row: entry.srcRow,
                                srcModel: entry.srcModel,
                                name: entry.display,
                                icon: entry.decoration,
                                fid: entry.favoriteId,
                                last: (e && typeof e === "object" && e.last) ? e.last : 0
                            });
                        }
                        list.sort(function (a, b) { return (b.last - a.last) || a.name.localeCompare(b.name); });
                    }
                    apps = list;
                }

                // centre de la tuile en coordonnées de la scène (point de depart de l animation)
                function center() { return tileBg.mapToItem(null, tileBg.width / 2, tileBg.height / 2); }

                function openActions(app, item, x, y) {
                    if (!app || !app.srcModel) return;
                    var actionList = app.srcModel.data(app.srcModel.index(app.row, 0), rootItem.kickerActionListRole) || [];
                    Tools.fillActionMenu(i18n, tileActionMenu, actionList, (typeof globalFavorites !== "undefined" ? globalFavorites : app.srcModel.favoritesModel), app.fid);
                    tileActionMenu.targetSub = app.srcModel;
                    tileActionMenu.targetRow = app.row;
                    tileActionMenu.visualParent = item;
                    tileActionMenu.open(x, y);
                }

                function launch(app) {
                    if (!app || !app.srcModel) return;
                    if (typeof rootItem !== "undefined" && app.fid !== "") rootItem.recordLaunch(app.fid);
                    app.srcModel.trigger(app.row, "", null);
                    root.toggle();
                }

                onAppCountChanged: rebuild()
                onSubChanged: rebuild()
                Component.onCompleted: rebuild()

                Connections {
                    target: (typeof rootItem !== "undefined") ? rootItem : null
                    function onLaunchCountsChanged() { cat.rebuild(); }
                }

                Rectangle {
                    id: tileBg
                    width: parent.width
                    height: tiles.tileHeight
                    radius: 8
                    color: (bgHover.hovered && !tiles.flyoutOpen) ? (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#33ffffff" : "#a6ffffff") : (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
                    border.width: 1
                    border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                    Behavior on color { ColorAnimation { duration: 100 } }

                    HoverHandler { id: bgHover }

                    MouseArea {
                        id: bgMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { var c = cat.center(); tiles.openCategory(cat.catIndex, cat.title, c.x, c.y); }
                    }

                    Grid {
                        id: cellGrid
                        anchors.fill: parent
                        anchors.margins: Math.round(tiles.tileWidth * 0.09)
                        columns: 2
                        spacing: 0

                        Repeater {
                            model: 4

                            delegate: Item {
                                id: cell
                                width: cellGrid.width / 2
                                height: cellGrid.height / 2

                                readonly property var app: (index < cat.bigCount && index < cat.apps.length) ? cat.apps[index] : null
                                readonly property bool isCluster: cat.overflow && index === 3

                                HoverHandler { id: cellHover; enabled: cell.app !== null || cell.isCluster }

                                // survol d'une grosse icône ou du paquet de mini-icônes
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: 5
                                    color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff") // surlignement-tuiles-v1
                                    border.width: 1
                                    border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#1affffff" : "#14000000")
                                    visible: cell.app !== null || cell.isCluster
                                    opacity: (cellHover.hovered && !tiles.flyoutOpen) ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 100 } }
                                }

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: Math.round(parent.width * 0.68)
                                    height: width
                                    visible: cell.app !== null
                                    source: cell.app ? cell.app.icon : ""
                                    animated: false
                                }

                                Grid {
                                    anchors.centerIn: parent
                                    columns: 2
                                    spacing: Math.round(cell.width * 0.06)
                                    visible: cell.isCluster

                                    Repeater {
                                        model: cell.isCluster ? cat.apps.slice(3, 7) : []

                                        delegate: Kirigami.Icon {
                                            width: Math.round(cell.width * 0.34)
                                            height: width
                                            source: modelData.icon
                                            animated: false
                                        }
                                    }
                                }

                                MouseArea {
                                    id: cellMouse
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    enabled: cell.app !== null || cell.isCluster
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton) {
                                            if (cell.app) cat.openActions(cell.app, cell, mouse.x, mouse.y);
                                            return;
                                        }
                                        if (cell.isCluster) { var c = cat.center(); tiles.openCategory(cat.catIndex, cat.title, c.x, c.y); }
                                        else cat.launch(cell.app);
                                    }
                                }

                                // infobulle compacte (PC3.ToolTip), comme « Marche/Arrêt »
                                Item {
                                    anchors.fill: parent
                                    HoverHandler { id: cellTipHover }
                                    PC3.ToolTip.text: cell.app ? cell.app.name : ""
                                    PC3.ToolTip.visible: cellTipHover.hovered && cell.app !== null
                                                         && !(typeof rootItem !== "undefined" && rootItem.scrolling)
                                    PC3.ToolTip.delay: 400
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    // point « nouveau » : la catégorie contient une application récemment installée
                    visible: cat.hasNew
                    z: 5
                    width: Kirigami.Units.smallSpacing * 2 + 2
                    height: width
                    radius: width / 2
                    color: Kirigami.Theme.highlightColor
                    border.width: 1
                    border.color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? "#26ffffff" : "#80ffffff")
                    anchors.top: tileBg.top
                    anchors.right: tileBg.right
                    anchors.margins: Kirigami.Units.smallSpacing + 3
                }

                Text {
                    anchors.top: tileBg.bottom
                    anchors.topMargin: Kirigami.Units.smallSpacing + 2
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: cat.title
                    color: Kirigami.Theme.textColor
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize
                }
            }
        }
    }
}
