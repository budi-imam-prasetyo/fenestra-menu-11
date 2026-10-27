pragma Singleton
import QtQuick
import org.kde.kirigami as Kirigami

// Theme-derived, shared desktop geometry. No platform palette is replaced.
QtObject {
    readonly property int space1: Math.max(2, Kirigami.Units.smallSpacing / 2)
    readonly property int space2: Kirigami.Units.smallSpacing
    readonly property int space3: space2 * 2
    readonly property int space4: space2 * 3
    readonly property int space5: space2 * 4
    readonly property int radius: 6
    readonly property int popupRadius: 8
    readonly property int controlHeight: Math.max(30, Math.ceil(fontPixels + space3 * 2))
    readonly property int smallIcon: Kirigami.Units.iconSizes.small
    readonly property int actionIcon: Kirigami.Units.iconSizes.smallMedium
    readonly property real fontSize: Kirigami.Theme.defaultFont.pointSize
    readonly property real smallFontSize: Math.max(8, fontSize - 1)
    readonly property real headingSize: fontSize
    readonly property real fontPixels: Kirigami.Theme.defaultFont.pixelSize > 0
                                      ? Kirigami.Theme.defaultFont.pixelSize : fontSize * 4 / 3
    readonly property color surface: Kirigami.Theme.backgroundColor
    readonly property color elevated: Kirigami.Theme.alternateBackgroundColor
    readonly property color text: Kirigami.Theme.textColor
    readonly property color secondaryText: Kirigami.Theme.disabledTextColor
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color accentText: Kirigami.Theme.highlightedTextColor
    readonly property color border: alpha(text, 0.12)
    readonly property color hover: alpha(text, 0.06)
    readonly property color pressed: alpha(accent, 0.22)
    readonly property color selected: alpha(accent, 0.13)
    readonly property color focus: accent
    readonly property color disabled: Kirigami.Theme.disabledTextColor

    function alpha(value, opacity) { return Qt.rgba(value.r, value.g, value.b, opacity); }
    function tileHeight(iconSize) { return Math.ceil(iconSize + fontPixels * 2.4 + space3 * 2 + space2); }
    function rowHeight(iconSize) { return Math.max(48, Math.ceil(iconSize + space3 * 2), Math.ceil(fontPixels * 2.2 + space2 * 2)); }
}
