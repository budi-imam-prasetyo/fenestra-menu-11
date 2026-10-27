import QtQuick
import QtQuick.Controls as QQC
import org.kde.plasma.components as PC3

QQC.Popup {
    id: popup
    objectName: "categoryDropdown"
    property var categories: []
    property var newCategories: ({})
    property int selectedRow: -1
    property Item trigger: null
    signal categoryChosen(int row)
    padding: Design.space2
    focus: true
    closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside
    width: Math.min(280, parent ? parent.width - Design.space3 * 2 : 280)
    height: Math.min(categoryList.contentHeight + padding * 2,
                     parent ? Math.max(Design.controlHeight, parent.height - Design.space4 * 2) : 360, 360)
    function openFor(button) {
        trigger = button;
        var point = button.mapToItem(parent, 0, button.height + Design.space2);
        x = Math.max(Design.space3, Math.min(point.x + button.width - width, parent.width - width - Design.space3));
        y = Math.max(Design.space3, Math.min(point.y, parent.height - height - Design.space3));
        categoryList.currentIndex = 0;
        for (var i = 0; i < categories.length; i++)
            if (categories[i].row === selectedRow) { categoryList.currentIndex = i; break; }
        open();
        categoryList.forceActiveFocus();
        categoryList.positionViewAtIndex(categoryList.currentIndex, ListView.Contain);
    }
    function choose(index) {
        if (index < 0 || index >= categories.length) return;
        categoryChosen(categories[index].row);
        close();
    }
    onClosed: if (trigger) trigger.forceActiveFocus()
    background: Rectangle {
        radius: Design.popupRadius
        color: Design.surface
        border.width: 1
        border.color: Design.border
    }
    contentItem: ListView {
        id: categoryList
        objectName: "categoryDropdownList"
        clip: true
        model: popup.categories
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        Keys.onReturnPressed: popup.choose(currentIndex)
        Keys.onEnterPressed: popup.choose(currentIndex)
        Keys.onEscapePressed: popup.close()
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }
        delegate: LauncherButton {
            required property var modelData
            required property int index
            width: categoryList.width
            height: Design.controlHeight
            text: modelData.label
            iconName: modelData.icon || "applications-all"
            selected: popup.selectedRow === modelData.row
            showNewDot: !!popup.newCategories[modelData.row]
            background: Rectangle {
                radius: Design.radius
                color: parent.down ? Design.pressed : parent.selected ? Design.selected
                       : parent.hovered || categoryList.currentIndex === index ? Design.hover : "transparent"
                border.width: categoryList.activeFocus && categoryList.currentIndex === index ? 1 : 0
                border.color: Design.focus
            }
            onClicked: popup.choose(index)
        }
    }
}
