/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Part of Fenestra Menu 11 (naykkalak, 2026), a fork of Menu 11 Next by Eisteed,
 * itself based on Menu 11 / Ditto Menu by adhe (GPL-2.0-or-later).
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
/*
    Ligne « recommandation » : icône à gauche, nom, puis « date · dossier » ; infobulle avec le chemin complet.
    Reprend l'interface de ItemGridDelegate.qml (utilisée par ItemGridView.qml).
*/

import QtQuick

import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami 2.20 as Kirigami
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
    property bool isFolderItem: false
    property bool isIndented: false
    property bool folderEditZoneHovered: false

    property bool hasActionList: (model.favoriteId !== null) || (("hasActionList" in model) && (model.hasActionList === true))

    property int itemColumns
    property bool labels2lines: false
    Accessible.role: Accessible.MenuItem
    Accessible.name: model.display

    // texte affiché sous le nom : « date  ·  dossier » (la date est lue par MenuRepresentation, cf. docDates)
    property string dateText: (typeof rootItem !== "undefined" && rootItem.docDates)
                              ? (rootItem.docDates[String(model.url)] || "") : ""
    property string folderText: (model.description !== undefined && model.description !== null) ? String(model.description) : ""
    property string subtitle: (dateText !== "" && folderText !== "") ? (dateText + "  ·  " + folderText)
                                                                    : (dateText !== "" ? dateText : folderText)
    // chemin complet pour l'infobulle
    property string fullPath: String(model.url).replace(/^file:\/\//, "").replace(/\/[^\/]*$/, "").replace(/^\/home\/[^\/]+/, i18n("Home Folder"))

    // mode « page complète » : heure à droite, chemin sous le nom
    property bool wide: (typeof itemGrid !== "undefined") && itemGrid.recentDocsWide === true
    property real epoch: (typeof rootItem !== "undefined" && rootItem.docEpochs) ? (rootItem.docEpochs[String(model.url)] || 0) : 0
    property string timeText: epoch > 0 ? rootItem.formatRecentTime(epoch) : ""
    property string shownSubtitle: wide ? fullPath : subtitle

    function openActionMenu(x, y) {
        var gm = GridView.view.model;
        var actionList = (typeof gm.actionListForRow === "function") ? gm.actionListForRow(model.index)
                                                                   : ((model.actionList !== undefined) ? model.actionList : []);
        Tools.fillActionMenu(i18n, actionMenu, actionList, GridView.view.model.favoritesModel, model.favoriteId);
        actionMenu.visualParent = item;
        actionMenu.open(x, y);
    }

    function actionTriggered(actionId, actionArgument) {
        var close = (Tools.triggerAction(GridView.view.model, model.index, actionId, actionArgument) === true);
        if (typeof rootItem !== "undefined") rootItem.scheduleDocsRefresh();

        if (close) {
            root.toggle();
        }
    }

    Kirigami.Icon {
        id: docIcon
        anchors.left: parent.left
        anchors.leftMargin: (typeof rootItem !== "undefined") ? rootItem.listIconPad : Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        width: item.iconSize
        height: width
        animated: false
        source: model.decoration
    }

    Column {
        anchors.left: docIcon.right
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.right: item.wide ? timeLabel.left : parent.right
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        PlasmaComponents3.Label {
            width: parent.width
            text: model.display
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Kirigami.Theme.textColor
        }

        PlasmaComponents3.Label {
            width: parent.width
            visible: item.shownSubtitle !== ""
            text: item.shownSubtitle
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
        }
    }

    PlasmaComponents3.Label {
        id: timeLabel
        visible: item.wide
        anchors.right: parent.right
        anchors.rightMargin: (item.wide && typeof itemGrid !== "undefined" && itemGrid.timeRightPad !== undefined)
                             ? itemGrid.timeRightPad : Kirigami.Units.largeSpacing
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.gridUnit * 7
        horizontalAlignment: Text.AlignRight
        text: item.timeText
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
    }

    // infobulle compacte (PC3.ToolTip) : nom du document + chemin complet
    Item {
        id: toolTip

        readonly property bool containsMouse: toolTipHover.hovered

        anchors.fill: parent
        HoverHandler {
            id: toolTipHover
            onHoveredChanged: item.GridView.view.itemContainsMouseChanged(hovered)
        }
        PlasmaComponents3.ToolTip.text: model.display + (item.fullPath ? "\n" + item.fullPath : "")
        PlasmaComponents3.ToolTip.visible: toolTipHover.hovered && root.visible
                                           && !(typeof rootItem !== "undefined" && rootItem.scrolling)
        PlasmaComponents3.ToolTip.delay: 400
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
