/* SPDX-License-Identifier: GPL-3.0-or-later */
import QtQuick

// Lightweight edge fades that leave pointer and wheel input to the viewport.
Item {
    id: fades
    property var flickable: null
    property color surface: Design.surface
    property real fadeSize: 14
    readonly property color clear: Qt.rgba(surface.r, surface.g, surface.b, 0)
    enabled: false
    z: 2
    Rectangle {
        objectName: "scrollFadeTop"
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: Math.min(fades.fadeSize, parent.height / 2)
        visible: fades.flickable !== null && fades.flickable.contentY > fades.flickable.originY + 1
        gradient: Gradient {
            GradientStop { position: 0; color: fades.surface }
            GradientStop { position: 1; color: fades.clear }
        }
    }
    Rectangle {
        objectName: "scrollFadeBottom"
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: Math.min(fades.fadeSize, parent.height / 2)
        visible: fades.flickable !== null && !fades.flickable.atYEnd
        gradient: Gradient {
            GradientStop { position: 0; color: fades.clear }
            GradientStop { position: 1; color: fades.surface }
        }
    }
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: Math.min(4, parent.width / 2)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: fades.surface }
            GradientStop { position: 1; color: fades.clear }
        }
    }
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: Math.min(4, parent.width / 2)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: fades.clear }
            GradientStop { position: 1; color: fades.surface }
        }
    }
}
