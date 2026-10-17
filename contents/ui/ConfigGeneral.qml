/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Modified by naykkalak (2026) for Fenestra Menu 11, a fork of Menu 11 Next by Eisteed.
 * The original notice below is kept. This file is GPL-2.0-or-later;
 * Fenestra Menu 11 as a whole is distributed under GPL-3.0-or-later.
 */
/***************************************************************************
 *   Copyright (C) 2014 by Eike Hein <hein@kde.org>                        *
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

//import QtQuick 2.15
//import QtQuick.Controls 2.15
//import QtQuick.Dialogs 1.2
//import QtQuick.Layouts 1.0
//import org.kde.plasma.core 2.0 as PlasmaCore
//import org.kde.plasma.components 2.0 as PlasmaComponents
//import org.kde.kquickcontrolsaddons 2.0 as KQuickAddons
//import org.kde.draganddrop 2.0 as DragDrop
//import org.kde.kirigami 2.4 as Kirigami

import QtQuick 2.15
import QtQuick.Layouts 1.0
import QtQuick.Controls 2.15
import org.kde.draganddrop 2.0 as DragDrop
import org.kde.kirigami 2.5 as Kirigami
import org.kde.iconthemes as KIconThemes
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami 2.20 as Kirigami
import org.kde.ksvg 1.0 as KSvg
import org.kde.plasma.plasmoid 2.0
import org.kde.kcmutils as KCM



KCM.SimpleKCM {
    id: configGeneral


    property string cfg_icon: plasmoid.configuration.icon
    property bool cfg_useCustomButtonImage: plasmoid.configuration.useCustomButtonImage
    property string cfg_customButtonImage: plasmoid.configuration.customButtonImage
    property alias cfg_numberColumns: numberColumns.value
    property alias cfg_numberRows: numberRows.value

    property alias cfg_labels2lines: labels2lines.checked

    property alias cfg_appsIconSize: appsIconSize.currentIndex
    property alias cfg_docsIconSize: docsIconSize.currentIndex
    property alias cfg_displayPosition: displayPosition.currentIndex
    property alias cfg_kdeConnectMemoriser: kdeConnectMemoriserCb.checked   // Fenestra : option du volet
    property alias cfg_showRecentDocs: showRecentDocsCb.checked
    property alias cfg_showRecentApps: showRecentAppsCb.checked
    property alias cfg_enableShellRunner: enableShellRunnerCb.checked
    property alias cfg_showQuickActions: showQuickActionsCb.checked
    property alias cfg_showSleepButton: showSleepCb.checked
    property alias cfg_showRestartButton: showRestartCb.checked
    property alias cfg_showShutdownButton: showShutdownCb.checked

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        Button {
            id: iconButton

            Kirigami.FormData.label: i18n("Icon:")

            implicitWidth: previewFrame.width + Kirigami.Units.smallSpacing * 2
            implicitHeight: previewFrame.height + Kirigami.Units.smallSpacing * 2

            // Just to provide some visual feedback when dragging;
            // cannot have checked without checkable enabled
            checkable: true
            checked: dropArea.containsAcceptableDrag

            onPressed: iconMenu.opened ? iconMenu.close() : iconMenu.open()

            DragDrop.DropArea {
                id: dropArea

                property bool containsAcceptableDrag: false

                anchors.fill: parent

                onDragEnter: {
                    // Cannot use string operations (e.g. indexOf()) on "url" basic type.
                    var urlString = event.mimeData.url.toString();

                    // This list is also hardcoded in KIconDialog.
                    var extensions = [".png", ".xpm", ".svg", ".svgz"];
                    containsAcceptableDrag = urlString.indexOf("file:///") === 0 && extensions.some(function (extension) {
                        return urlString.indexOf(extension) === urlString.length - extension.length; // "endsWith"
                    });

                    if (!containsAcceptableDrag) {
                        event.ignore();
                    }
                }
                onDragLeave: containsAcceptableDrag = false

                onDrop: {
                    if (containsAcceptableDrag) {
                        // Strip file:// prefix, we already verified in onDragEnter that we have only local URLs.
                        iconDialog.setCustomButtonImage(event.mimeData.url.toString().substr("file://".length));
                    }
                    containsAcceptableDrag = false;
                }
            }

            KIconThemes.IconDialog {
                id: iconDialog

                function setCustomButtonImage(image) {
                    configGeneral.cfg_customButtonImage = image || configGeneral.cfg_icon || "start-here-kde-symbolic"
                    configGeneral.cfg_useCustomButtonImage = true;
                }

                onIconNameChanged: setCustomButtonImage(iconName);
            }

            KSvg.FrameSvgItem {
                id: previewFrame
                anchors.centerIn: parent
                imagePath: Plasmoid.location === PlasmaCore.Types.Vertical || Plasmoid.location === PlasmaCore.Types.Horizontal
                           ? "widgets/panel-background" : "widgets/background"
                width: Kirigami.Units.iconSizes.large + fixedMargins.left + fixedMargins.right
                height: Kirigami.Units.iconSizes.large + fixedMargins.top + fixedMargins.bottom

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.large
                    height: width
                    source: configGeneral.cfg_useCustomButtonImage ? configGeneral.cfg_customButtonImage : configGeneral.cfg_icon
                }
            }

            Menu {
                id: iconMenu

                // Appear below the button
                y: +parent.height

                onClosed: iconButton.checked = false;

                MenuItem {
                    text: i18nc("@item:inmenu Open icon chooser dialog", "Choose…")
                    icon.name: "document-open-folder"
                    onClicked: iconDialog.open()
                }
                MenuItem {
                    text: i18nc("@item:inmenu Reset icon to default", "Clear Icon")
                    icon.name: "edit-clear"
                    onClicked: {
                        configGeneral.cfg_icon = "start-here-kde-symbolic"
                        configGeneral.cfg_useCustomButtonImage = false
                    }
                }
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        ComboBox {
            id: appsIconSize
            Kirigami.FormData.label: i18n("Apps icon size:")
            Layout.fillWidth: true
            model: [i18n("Small"),i18n("Medium"),i18n("Large"), i18n("Huge")]
        }

        ComboBox {
            id: docsIconSize
            Kirigami.FormData.label: i18n("Docs icon size:")
            Layout.fillWidth: true
            model: [i18n("Small"),i18n("Medium"),i18n("Large"), i18n("Huge")]
        }


        ComboBox {

            Kirigami.FormData.label: i18n("Menu position")
            id: displayPosition
            model: [
                i18n("Default"),
                i18n("Center"),
                i18n("Center bottom"),
            ]
            //onActivated: cfg_displayPosition = currentIndex
        }


        CheckBox {
            id: labels2lines
            text: i18n("Show labels in two lines")
            visible: true
        }

        SpinBox{
            id: numberColumns
            enabled: false   // Fenestra : colonnes automatiques (6 / 7 / 8 selon l'écran)

            from: 3
            to: 15
            Kirigami.FormData.label: i18n("Number of columns")

        }

        SpinBox{
            id: numberRows
            from: 1
            to: 15
            Kirigami.FormData.label: i18n("Number of rows")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("All Apps")
        }

        CheckBox {
            id: showRecentDocsCb
            Kirigami.FormData.label: i18n("Recent Documents:")
            text: i18n("Show Recent Documents section")
        }

        // Fenestra : option du volet : remplace « Default view mode » et « Default sort order » (grisés)
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("KDE Connect")
        }

        CheckBox {
            id: kdeConnectMemoriserCb
            Kirigami.FormData.label: i18n("Mobile panel:")
            text: i18n("Keep the mobile panel open between menu openings")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Search")
        }

        CheckBox {
            id: showRecentAppsCb
            Kirigami.FormData.label: i18n("Home page:")
            text: i18n("Show recently opened apps")
        }

        CheckBox {
            id: enableShellRunnerCb
            text: i18n("Enable shell command runner ( > cmd )")
        }

        CheckBox {
            id: showQuickActionsCb
            text: i18n("Show Quick Actions bar (Screenshot, Lock, Terminal…)")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Footer power buttons")
        }

        CheckBox {
            id: showSleepCb
            Kirigami.FormData.label: i18n("Show:")
            text: i18n("Sleep / Suspend")
        }

        CheckBox {
            id: showRestartCb
            text: i18n("Restart")
        }

        CheckBox {
            id: showShutdownCb
            text: i18n("Shutdown")
        }

        RowLayout{

            visible: false
            Button {
                text: i18n("Unhide all hidden applications")
                onClicked: {
                    plasmoid.configuration.hiddenApplications = [""];
                    unhideAllAppsPopup.text = i18n("Unhidden!");
                }
            }
            Label {
                id: unhideAllAppsPopup
            }
        }

    }
}
