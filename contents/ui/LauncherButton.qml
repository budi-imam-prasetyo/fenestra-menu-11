import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

PC3.ToolButton {
    id: control
    property string iconName: ""
    property bool selected: checked
    property bool showLabel: true
    property bool showNewDot: false
    property string newDotObjectName: ""
    property string toolTipText: text
    property int buttonHeight: Design.controlHeight
    implicitHeight: buttonHeight
    implicitWidth: contentRow.implicitWidth + leftPadding + rightPadding
    leftPadding: Design.space3
    rightPadding: Design.space3
    topPadding: Design.space2
    bottomPadding: Design.space2
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    Accessible.checked: selected
    PC3.ToolTip.text: toolTipText
    PC3.ToolTip.visible: hovered && toolTipText.length > 0
    PC3.ToolTip.delay: 500
    contentItem: RowLayout {
        id: contentRow
        spacing: Design.space2
        Kirigami.Icon {
            visible: control.iconName.length > 0
            source: control.iconName
            fallback: "application-x-executable"
            Layout.preferredWidth: Design.smallIcon
            Layout.preferredHeight: Design.smallIcon
            animated: false
        }
        PC3.Label {
            visible: control.showLabel
            text: control.text
            color: control.enabled ? Design.text : Design.disabled
            font.pointSize: Design.fontSize
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
    background: Rectangle {
        radius: Design.radius
        color: control.down ? Design.pressed : control.selected ? Design.selected
               : control.hovered ? Design.hover : "transparent"
        border.width: control.visualFocus ? 2 : 1
        border.color: control.visualFocus ? Design.focus
                      : control.selected ? Design.alpha(Design.accent, 0.35) : "transparent"
        Rectangle {
            objectName: control.newDotObjectName
            visible: control.showNewDot
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Design.space2
            width: 6
            height: width
            radius: width / 2
            color: Design.accent
        }
    }
}
