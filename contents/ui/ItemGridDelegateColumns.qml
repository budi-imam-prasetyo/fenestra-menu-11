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
    clip: true

    enabled: !model.disabled

    property int iconSize
    property bool showLabel: true
    property int itemIndex: model.index
    property string favoriteId: model.favoriteId !== undefined ? model.favoriteId : ""
    property url url: model.url !== undefined ? model.url : ""
    property variant icon: model.decoration !== undefined ? model.decoration : ""
    property var m: model
    property bool isFolderItem: model.itemType === "folder"
    property bool isIndented:   model.indented === true
    property bool isLetterHeader: ("itemType" in model) && model.itemType === "letterHeader"

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
        Tools.fillActionMenu(i18n, actionMenu, actionList, GridView.view.model.favoritesModel, model.favoriteId);
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
        visible: isFolderItem && colFolderDropArea.containsDrag
        color: root.colorWithAlpha(Kirigami.Theme.highlightColor, 0.18)
        border.width: 2
        border.color: Kirigami.Theme.highlightColor
        z: 1
    }

    // Drop-onto-folder area (only active for folder items)
    DropArea {
        id: colFolderDropArea
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

    Kirigami.Icon {
        id: icon
        visible: !item.isLetterHeader
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Kirigami.Units.largeSpacing + indentOffset

        width: isIndented ? iconSize * 0.85 : iconSize
        height: width

        animated: false

        source: model.decoration
    }

    PlasmaComponents3.Label {
        id: letterHeaderLabel
        visible: item.isLetterHeader
        anchors.left: parent.left
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.verticalCenter: parent.verticalCenter
        text: model.display
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
        color: (Kirigami.Theme.textColor.hslLightness > 0.5 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : "#4A4A4A")
    }

    // Text block centered alongside the icon — avoids vertical overflow at any DPI/font size
    Column {
        id: textBlock
        visible: !item.isLetterHeader
        anchors.left: icon.right
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.right: parent.right
        anchors.rightMargin: Kirigami.Units.largeSpacing
        anchors.verticalCenter: icon.verticalCenter
        spacing: Kirigami.Units.smallSpacing / 2

        PlasmaComponents3.Label {
            id: label
            visible: item.showLabel
            width: parent.width
            horizontalAlignment: Text.AlignLeft
            maximumLineCount: item.labels2lines ? 2 : 1
            elide: item.labels2lines ? Text.ElideNone : Text.ElideRight
            color: isIndented ? root.colorWithAlpha(Kirigami.Theme.textColor, 0.85) : Kirigami.Theme.textColor
            font.pointSize: isIndented
                            ? Kirigami.Theme.defaultFont.pointSize * 0.9
                            : Kirigami.Theme.defaultFont.pointSize
            text: ("name" in model ? model.name : model.display)
            textFormat: Text.PlainText
        }

        PlasmaComponents3.Label {
            id: desc
            visible: text.length > 0
            width: parent.width
            horizontalAlignment: Text.AlignLeft
            maximumLineCount: 1
            elide: Text.ElideRight
            color: colorWithAlpha(Kirigami.Theme.textColor, 0.4)
            font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
            text: ("description" in model ? model.description : "")
            textFormat: Text.PlainText
        }
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
        PlasmaComponents3.ToolTip.delay: 400
    }

    // Folder edit zone: hover-only tracker (clicks pass through to hoverArea which emits folderEditRequested)
    MouseArea {
        id: folderBtnZone
        visible: isFolderItem
        anchors.right: parent.right
        width: Kirigami.Units.gridUnit * 2.5
        height: parent.height
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: 1
    }

    property bool folderEditZoneHovered: isFolderItem && folderBtnZone.containsMouse

    // Visual indicator — non-interactive, appears when hovering the edit zone
    Item {
        visible: isFolderItem && folderEditZoneHovered
        anchors.right: parent.right
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
        height: width
        z: 2

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

    // Quick-pin button: appears on hover, absent for items without favoriteId
    Loader {
        id: pinButtonLoader
        active: false   // fanion favori retiré (épinglage via clic droit)
        anchors.right: parent.right
        anchors.rightMargin: Kirigami.Units.largeSpacing
        anchors.verticalCenter: parent.verticalCenter
        z: 2

        sourceComponent: PlasmaComponents3.ToolButton {
            property var favModel: item.GridView.view ? item.GridView.view.model.favoritesModel : null
            property bool isFav: favModel !== null && favoriteId !== "" && favModel.isFavorite(favoriteId)

            icon.name: isFav ? "bookmark-remove" : "bookmark-new"
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small

            PlasmaComponents3.ToolTip.text: isFav ? i18n("Unpin from Start") : i18n("Pin to Start")
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: 600

            opacity: hovered ? 1.0 : 0.6

            onClicked: {
                if (!favModel) return;
                if (isFav) {
                    favModel.removeFavorite(favoriteId);
                } else {
                    favModel.addFavorite(favoriteId);
                }
            }
        }
    }

    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Menu && hasActionList) {
                            event.accepted = true;
                            openActionMenu(item);
                        } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                            event.accepted = true;

                            if ("trigger" in GridView.view.model) {
                                GridView.view.model.trigger(index, "", null);
                                root.toggle();
                            }

                            itemGrid.itemActivated(index, "", null);
                        }
                    }
}
