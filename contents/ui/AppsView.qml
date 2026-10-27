/* SPDX-License-Identifier: GPL-3.0-or-later */
import QtQuick
import org.kde.plasma.components as PC3

// Retain each bounded viewport after its first use. Switching presentation does
// not replace a GridView's model or delegate component.
FocusScope {
    id: appsView
    property int viewMode: 0
    property var listModel: null
    property var gridModel: null
    property int contextKey: -1
    onContextKeyChanged: {
        if (viewMode === 1 && listLoader.item) listLoader.item.model = null;
        if (viewMode !== 1 && gridLoader.item) gridLoader.item.model = null;
    }
    property int columns: 6
    property int iconSize: 32
    property bool labels2lines: true
    property real viewportHeight: height
    property real viewportOffset: 0
    property bool listLoaded: false
    property bool gridLoaded: false
    Component.onCompleted: {
        if (viewMode === 1) gridLoaded = true;
        else listLoaded = true;
    }
    readonly property var activeGrid: viewMode === 1 ? gridLoader.item : listLoader.item
    readonly property var model: activeGrid ? activeGrid.model : null
    readonly property int count: activeGrid ? activeGrid.count : 0
    readonly property var currentItem: activeGrid ? activeGrid.currentItem : null
    readonly property real cellWidth: activeGrid ? activeGrid.cellWidth : width
    readonly property real cellHeight: viewMode === 1 ? Design.tileHeight(iconSize) : Design.rowHeight(iconSize)
    readonly property int columnsCount: viewMode === 1 ? columns : 1
    readonly property real contentY: activeGrid ? activeGrid.contentY : 0
    readonly property int renderedItemCount: activeGrid ? activeGrid.renderedItemCount : 0
    property int currentIndex: -1
    signal itemActivated(int index, string actionId, string argument)
    signal folderEditRequested(int index)
    signal wheelUnhandled(real delta)
    signal keyNavUp
    signal keyNavDown
    height: activeGrid ? activeGrid.height : 0
    onCurrentIndexChanged: if (activeGrid && activeGrid.currentIndex !== currentIndex) activeGrid.currentIndex = currentIndex
    onActiveGridChanged: currentIndex = activeGrid ? activeGrid.currentIndex : -1
    onViewModeChanged: {
        if (viewMode === 1) gridLoaded = true;
        else listLoaded = true;
    }
    function tryActivate(row, column) { if (activeGrid) activeGrid.tryActivate(row, column); }
    function forceLayout() { if (activeGrid) activeGrid.forceLayout(); }
    function activate(index) { if (activeGrid) activeGrid.activate(index); }
    Connections {
        target: appsView.activeGrid
        function onCurrentIndexChanged() { appsView.currentIndex = appsView.activeGrid.currentIndex; }
        function onItemActivated(index, actionId, argument) { appsView.itemActivated(index, actionId, argument); }
        function onFolderEditRequested(index) { appsView.folderEditRequested(index); }
        function onWheelUnhandled(delta) { appsView.wheelUnhandled(delta); }
        function onKeyNavUp() { appsView.keyNavUp(); }
        function onKeyNavDown() { appsView.keyNavDown(); }
    }
    Binding {
        target: listLoader.item
        property: "model"
        when: listLoader.item !== null && listLoader.visible
        value: appsView.listModel
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: gridLoader.item
        property: "model"
        when: gridLoader.item !== null && gridLoader.visible
        value: appsView.gridModel
        restoreMode: Binding.RestoreNone
    }
    Loader {
        id: listLoader
        width: appsView.width
        active: appsView.listLoaded
        visible: appsView.viewMode !== 1
        sourceComponent: ItemGridView {
            property real savedOffset: 0
            width: appsView.width
            height: Math.max(1, count) * cellHeight
            itemColumns: 2
            iconSize: appsView.iconSize
            cellWidth: width
            cellHeight: Design.rowHeight(iconSize)
            virtualized: true
            viewportHeight: Math.min(height, appsView.viewportHeight)
            viewportOffset: listLoader.visible ? Math.min(height - viewportHeight, appsView.viewportOffset) : savedOffset
            onViewportOffsetChanged: if (listLoader.visible) savedOffset = viewportOffset
            scrollEnabled: false
            dragEnabled: true
            dropEnabled: false
            clip: true
            verticalScrollBarPolicy: PC3.ScrollBar.AlwaysOff
        }
    }
    Loader {
        id: gridLoader
        width: appsView.width
        active: appsView.gridLoaded
        visible: appsView.viewMode === 1
        sourceComponent: ItemGridView {
            property real savedOffset: 0
            width: appsView.width
            height: Math.max(1, Math.ceil(count / appsView.columns)) * cellHeight
            itemColumns: 1
            iconSize: appsView.iconSize
            labels2lines: appsView.labels2lines
            cellWidth: Math.floor(width / Math.max(1, appsView.columns))
            cellHeight: Design.tileHeight(iconSize)
            virtualized: true
            viewportHeight: Math.min(height, appsView.viewportHeight)
            viewportOffset: gridLoader.visible ? Math.min(height - viewportHeight, appsView.viewportOffset) : savedOffset
            onViewportOffsetChanged: if (gridLoader.visible) savedOffset = viewportOffset
            scrollEnabled: false
            dragEnabled: true
            dropEnabled: false
            clip: true
            verticalScrollBarPolicy: PC3.ScrollBar.AlwaysOff
        }
    }
}
