/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Modified by naykkalak (2026) for Fenestra Menu 11, a fork of Menu 11 Next by Eisteed.
 * The original notice below is kept. This file is GPL-2.0-or-later;
 * Fenestra Menu 11 as a whole is distributed under GPL-3.0-or-later.
 */
/*
    SPDX-FileCopyrightText: 2015 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami 2.20 as Kirigami
import QtQuick.Layouts 1.1
import "code/tools.js" as Tools

Item {
    id: item

    width: GridView.view.cellWidth
    height: GridView.view.cellHeight
    clip: !isLetterHeader // le bandeau de la lettre déborde volontairement de la cellule

    enabled: !model.disabled

    property int iconSize
    property bool showLabel: true
    // tag « Nouveauté » (activé seulement par la grille de la fenêtre de catégorie)
    property bool showNewTag: false
    readonly property bool isNewTag: showNewTag && !isFolderItem && !isIndented
                                     && favoriteId !== "" && typeof rootItem !== "undefined"
                                     && rootItem.newApps !== undefined && !!rootItem.newApps[favoriteId]

    property int itemIndex: model.index
    property string favoriteId: model.favoriteId !== undefined ? model.favoriteId : ""
    property url url: model.url !== undefined ? model.url : ""
    property variant icon: model.decoration !== undefined ? model.decoration : ""
    property var m: model
    property bool isFolderItem: model.itemType === "folder"
    property bool isIndented:   model.indented === true

    property bool hasActionList: {
        if (isFolderItem) return true;
        if (isIndented)   return false;
        return (model.favoriteId !== null) || (("hasActionList" in model) && (model.hasActionList === true));
    }

    property int itemColumns
    property bool labels2lines: false
    Accessible.role: Accessible.MenuItem
    Accessible.name: model.display

    function openActionMenu(x, y) {
        if (isFolderItem) {
            allAppsFolderContextMenu.targetIndex = model.folderIdx;
            allAppsFolderContextMenu.popup();
            return;
        }
        var actionList = (model.actionList !== undefined) ? model.actionList : [];
        Tools.fillActionMenu(i18n, actionMenu, actionList, (GridView.view.favoritesModelOverride || GridView.view.model.favoritesModel), model.favoriteId);
        actionMenu.visualParent = item;
        actionMenu.open(x, y);
    }

    function actionTriggered(actionId, actionArgument) {
        var close = (Tools.triggerAction(GridView.view.model, model.index, actionId, actionArgument) === true);

        if (close) {
            root.toggle();
        }
    }
    // Left indent for expanded folder children
    property real indentOffset: isIndented ? Kirigami.Units.gridUnit * 1.5 : 0

    // Folder drop highlight ring
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Kirigami.Units.smallSpacing
        visible: isFolderItem && folderDropArea.containsDrag
        color: root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.18)
        border.width: 2
        border.color: Kirigami.Theme.highlightColor
        z: 1
    }

    // Drop-onto-folder area (only active for folder items)
    DropArea {
        id: folderDropArea
        anchors.fill: parent
        enabled: isFolderItem
        onDropped: {
            var src = kicker.dragSource;
            if (!src || !src.favoriteId || src.favoriteId === "") return;
            if (src.m && src.m.itemType === "folder") return;
            var favId = src.favoriteId;
            var fi = model.folderIdx;
            if (fi < 0 || fi >= rootItem.allAppsFoldersData.length) return;
            var folders = rootItem.allAppsFoldersData.slice();
            var folder = folders[fi];
            if (!folder || (folder.items && folder.items.indexOf(favId) >= 0)) return;
            var newItems = (folder.items || []).concat([favId]);
            folders[fi] = { name: folder.name, items: newItems, createdAt: folder.createdAt || 0 };
            rootItem.allAppsFoldersData = folders;
            rootItem.saveAllAppsFolders();
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse
        onWheel: {
            if (typeof scrollFlickable !== "undefined" && scrollFlickable) {
                scrollFlickable.contentY -= wheel.angleDelta.y
            }
        }
    }
    property bool isLetterHeader: ("itemType" in model) && model.itemType === "letterHeader"
    property bool isBlank: ("itemType" in model) && model.itemType === "blank"

    Kirigami.Icon {
        id: icon
        visible: !item.isLetterHeader && !item.isBlank
        y: item.showLabel ? (2 * highlightItemSvg.margins.top) : undefined
        anchors.horizontalCenter: isIndented ? undefined : parent.horizontalCenter
        anchors.left:             isIndented ? parent.left : undefined
        anchors.leftMargin:       isIndented ? indentOffset : 0
        anchors.verticalCenter: item.showLabel ? undefined : parent.verticalCenter

        width: isIndented ? iconSize * 0.85 : iconSize
        height: width

        animated: false

        source: model.decoration
    }

    Rectangle {
        id: letterBand
        visible: item.isLetterHeader
        x: 0
        y: 0
        width: item.GridView.view ? item.GridView.view.width : item.width
        height: item.height
        radius: 0
        color: "transparent" // juste un repère de largeur/position, pas de fond visible
    }

    Text {
        visible: item.isLetterHeader
        anchors.left: letterBand.left
        anchors.leftMargin: item.GridView.view ? Math.round((item.GridView.view.cellWidth - iconSize) / 2)
                                               : Kirigami.Units.largeSpacing
        anchors.verticalCenter: letterBand.verticalCenter
        text: model.display
        font.family: Kirigami.Theme.defaultFont.family
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
        font.weight: Font.Normal
        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
    }

    PlasmaComponents3.Label {
        id: label

        visible: item.showLabel && !item.isLetterHeader && !item.isBlank

        anchors {
            top: icon.bottom
            topMargin: Kirigami.Units.smallSpacing
            left: parent.left
            leftMargin: isIndented ? (indentOffset + icon.width + Kirigami.Units.smallSpacing) : highlightItemSvg.margins.left
            right: parent.right
            rightMargin: highlightItemSvg.margins.right
        }

        horizontalAlignment: isIndented ? Text.AlignLeft : Text.AlignHCenter

        maximumLineCount: item.labels2lines ? 2 : 1
        elide: Text.ElideRight
        wrapMode: Text.WordWrap

        color: isIndented ? root.colorWithAlpha(Kirigami.Theme.textColor, 0.85) : Kirigami.Theme.textColor

        font.pointSize: isIndented
        ? Kirigami.Theme.defaultFont.pointSize * 0.9
        : Kirigami.Theme.defaultFont.pointSize
        text: ("name" in model ? model.name : model.display)
        textFormat: Text.PlainText
    }

    // Tag « Nouveauté » sous le nom de l'appli
    Text {
        id: newTag
        visible: item.isNewTag
        anchors.top: label.bottom
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        text: i18n("New")
        color: Kirigami.Theme.highlightColor
        font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
        font.weight: Font.DemiBold
    }

    // infobulle compacte (PC3.ToolTip), comme « Marche/Arrêt »
    Item {
        id: toolTip

        property string text: model.display
        readonly property bool containsMouse: toolTipHover.hovered

        anchors.fill: parent
        HoverHandler {
            id: toolTipHover
            onHoveredChanged: item.GridView.view.itemContainsMouseChanged(hovered)
        }
        PlasmaComponents3.ToolTip.text: toolTip.text
        PlasmaComponents3.ToolTip.visible: toolTipHover.hovered && root.visible && label.truncated
                                           && !item.isLetterHeader && !item.isBlank
        PlasmaComponents3.ToolTip.delay: 400
    }

    // Folder edit zone: hover-only tracker (clicks pass through to hoverArea which emits folderEditRequested)
    MouseArea {
        id: folderBtnZone
        visible: isFolderItem
        anchors.right: parent.right
        width: Kirigami.Units.gridUnit * 2
        height: parent.height
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: 1
    }

    property bool folderEditZoneHovered: isFolderItem && folderBtnZone.containsMouse

    // Visual indicator — non-interactive, top-right corner badge
    Item {
        visible: isFolderItem && folderEditZoneHovered
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        width: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
        height: width
        z: 3

        Rectangle {
            anchors.fill: parent
            radius: Kirigami.Units.smallSpacing
            color: root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.18)
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            source: "list-add"
            width: Kirigami.Units.iconSizes.small
            height: width
            animated: false
        }
    }

    // Ctrl+number keyboard shortcut badge
    Rectangle {
        property int pageRelIdx: rootItem.pinnedItemsPerPage > 0
                                 ? model.index % rootItem.pinnedItemsPerPage
                                 : model.index
        visible: !isFolderItem && !isIndented && rootItem.ctrlHeld && pageRelIdx < 9
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        width: Kirigami.Units.gridUnit * 1.4
        height: width
        radius: width / 2
        color: Kirigami.Theme.highlightColor
        z: 3

        Behavior on opacity { NumberAnimation { duration: 80 } }

        Text {
            anchors.centerIn: parent
            text: parent.pageRelIdx + 1
            color: "white"
            font.bold: true
            font.pixelSize: parent.width * 0.52
        }
    }

    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Menu && hasActionList) {
                            event.accepted = true;
                            openActionMenu(item);
                        } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                            event.accepted = true;

                            if (favoriteId !== "" && typeof rootItem !== "undefined") {
                                rootItem.recordLaunch(favoriteId);
                            }

                            if ("trigger" in GridView.view.model) {
                                GridView.view.model.trigger(index, "", null);
                                root.toggle();
                            }

                            itemGrid.itemActivated(index, "", null);
                        }
                    }
}
