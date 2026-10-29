/* SPDX-License-Identifier: GPL-2.0-or-later
 * Shared presentation for the existing Kicker delegates and action dispatch.
 */
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "code/tools.js" as Tools

Item {
    id: item
    objectName: "applicationDelegate_" + favoriteId
    property bool listMode: false
    property int iconSize: 32
    property bool showLabel: true
    property bool labels2lines: false
    property bool showNewTag: false
    property int itemColumns: listMode ? 2 : 1
    readonly property int itemIndex: model.index
    readonly property string favoriteId: model.favoriteId || ""
    readonly property url url: model.url || ""
    readonly property var icon: model.decoration || "application-x-executable"
    readonly property var m: model
    readonly property bool isFolderItem: model.itemType === "folder"
    readonly property bool isIndented: model.indented === true
    readonly property bool isLetterHeader: model.itemType === "letterHeader"
    readonly property bool isBlank: model.itemType === "blank"
    readonly property bool hasActionList: isFolderItem || (!isIndented && favoriteId.length > 0)
    readonly property bool isNewTag: showNewTag && !!rootItem.newApps[favoriteId]
    readonly property bool folderEditZoneHovered: folderEdit.item !== null && folderEdit.item.containsMouse
    readonly property real inset: isIndented ? Design.space5 : Design.space3
    width: GridView.view ? GridView.view.cellWidth : 96
    height: GridView.view ? GridView.view.cellHeight : 96
    enabled: !isBlank && !isLetterHeader && model.disabled !== true
    clip: true
    Accessible.role: Accessible.MenuItem
    Accessible.name: model.display || ""

    function openActionMenu(x, y) {
        if (isFolderItem) {
            allAppsFolderContextMenu.targetIndex = model.folderIdx;
            allAppsFolderContextMenu.popup();
            return;
        }
        var view = item.GridView.view;
        var favorites = view.favoritesModelOverride || view.model.favoritesModel;
        Tools.fillActionMenu(i18n, actionMenu, model.actionList || [], favorites, favoriteId);
        actionMenu.visualParent = item;
        actionMenu.open(x, y);
    }
    function actionTriggered(actionId, argument) {
        if (Tools.triggerAction(item.GridView.view.model, itemIndex, actionId, argument)) root.toggle();
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Design.space1
        radius: Design.radius
        visible: item.enabled
        color: itemGrid.pressedIndex === item.itemIndex ? Design.pressed
               : item.GridView.isCurrentItem ? Design.selected : "transparent"
        border.width: item.GridView.isCurrentItem && itemGrid.activeFocus && itemGrid._keyNavRecently() ? 2 : 0
        border.color: Design.focus
    }
    Kirigami.Icon {
        id: appIcon
        source: item.icon
        fallback: "application-x-executable"
        animated: false
        visible: !item.isBlank && !item.isLetterHeader
        width: item.isIndented ? item.iconSize * 0.85 : item.iconSize
        height: width
        x: item.listMode ? item.inset : Math.round((item.width - width) / 2)
        y: item.listMode || !item.showLabel ? Math.round((item.height - height) / 2) : Design.space3
    }
    Text {
        visible: item.isLetterHeader
        x: Design.space3
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Design.space3 * 2
        text: model.display || ""
        color: Design.secondaryText
        font.family: Kirigami.Theme.defaultFont.family
        font.pointSize: Design.smallFontSize
        font.weight: Font.DemiBold
    }
    Text {
        id: nameLabel
        visible: item.showLabel && !item.isLetterHeader && !item.isBlank
        x: item.listMode ? appIcon.x + appIcon.width + Design.space3 : Design.space2
        y: item.listMode ? Math.round((item.height - height - (description.visible ? description.height + Design.space1 : 0)) / 2)
                         : appIcon.y + appIcon.height + Design.space2
        width: item.width - x - (item.listMode ? Design.space3 : Design.space2)
        text: model.name || model.display || ""
        textFormat: Text.PlainText
        color: Design.text
        font.family: Kirigami.Theme.defaultFont.family
        font.pointSize: Design.fontSize
        maximumLineCount: item.listMode ? 1 : 2
        wrapMode: item.listMode ? Text.NoWrap : Text.WordWrap
        elide: Text.ElideRight
        horizontalAlignment: item.listMode ? Text.AlignLeft : Text.AlignHCenter
    }
    Text {
        id: description
        visible: item.listMode && !item.isLetterHeader && text.length > 0
        x: nameLabel.x
        y: nameLabel.y + nameLabel.height + Design.space1
        width: nameLabel.width
        text: model.description || ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Design.secondaryText
        font.family: Kirigami.Theme.defaultFont.family
        font.pointSize: Design.smallFontSize
    }
    Rectangle {
        objectName: "applicationNewDot_" + item.favoriteId
        visible: item.isNewTag
        x: parent.width - width - Design.space2
        y: Design.space2
        width: 6
        height: width
        radius: width / 2
        color: Design.accent
    }
    HoverHandler { id: hover }
    PC3.ToolTip.text: model.display || ""
    PC3.ToolTip.visible: hover.hovered && root.visible && !rootItem.scrolling && nameLabel.truncated
    PC3.ToolTip.delay: 500

    // Folder-only affordances are created only for actual folders.
    Loader {
        id: folderEdit
        active: item.isFolderItem
        anchors.right: parent.right
        anchors.top: parent.top
        width: Design.controlHeight
        height: item.listMode ? parent.height : Design.controlHeight
        sourceComponent: MouseArea {
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Design.smallIcon
                height: width
                source: "list-add"
                visible: parent.containsMouse
            }
        }
    }
    Loader {
        active: item.isFolderItem
        anchors.fill: parent
        sourceComponent: DropArea {
            onDropped: {
                var src = kicker.dragSource;
                if (!src || !src.favoriteId || src.favoriteId === "" || src.isFolderItem) return;
                var folders = rootItem.allAppsFoldersData.slice();
                var folder = folders[model.folderIdx];
                if (!folder || (folder.items || []).indexOf(src.favoriteId) >= 0) return;
                folders[model.folderIdx] = { name: folder.name, items: (folder.items || []).concat([src.favoriteId]), createdAt: folder.createdAt || 0 };
                rootItem.allAppsFoldersData = folders;
                rootItem.saveAllAppsFolders();
            }
            Rectangle {
                anchors.fill: parent
                radius: Design.radius
                visible: parent.containsDrag
                color: Design.selected
                border.width: 2
                border.color: Design.accent
            }
        }
    }
    Rectangle {
        readonly property int relativeIndex: item.itemIndex % Math.max(1, rootItem.pinnedItemsPerPage)
        visible: !item.isFolderItem && !item.isLetterHeader && !item.isBlank && rootItem.ctrlHeld && relativeIndex < 9
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Design.space2
        width: Design.actionIcon
        height: width
        radius: Design.radius
        color: Design.accent
        Text { anchors.centerIn: parent; text: parent.relativeIndex + 1; color: Design.accentText; font.pointSize: Design.smallFontSize }
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Menu && hasActionList) {
            event.accepted = true;
            openActionMenu(width / 2, height / 2);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            event.accepted = true;
            itemGrid.activate(itemIndex);
        }
    }
}
