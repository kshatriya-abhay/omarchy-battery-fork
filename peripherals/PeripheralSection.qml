import QtQuick
import QtQuick.Layouts
import qs.Ui         // PanelSectionHeader, ToggleSwitch, PanelActionButton, CursorSurface
import qs.Commons    // Color, Style tokens

// "PERIPHERALS" section of the power popup, adapted from hl.peripheral_battery's
// DevicePanel: a switch for showing every device in the bar, then one row per
// device (type glyph + name + pin button, then a charge bar + percentage).
// Panel.qml owns the cursor, pins and settings; this file only draws them and
// reports clicks and hovers back.
Column {
    id: section

    property var bar: null
    property var devices: []
    property var pinnedNames: []
    property bool compactMode: false
    property int lowThreshold: 20
    property int criticalThreshold: 10
    property bool cursorActive: false
    property string focusSection: ""
    property int selectedIndex: -1

    signal togglePin(string name)
    signal compactToggle(bool on)
    signal hoverToggle()
    signal hoverDevice(int index)
    signal activateDevice(int index)

    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property real barHeight: Math.max(4, Math.round(Style.spacing.controlHeight * 0.2))

    spacing: Style.space(10)

    PanelSectionHeader {
        text: "PERIPHERALS"
        foreground: section.foreground
        fontFamily: section.fontFamily
    }

    // Show every device in the bar (up to 3), not only the pinned ones.
    // Right-clicking the peripheral label in the bar flips the same setting.
    RowLayout {
        width: parent.width
        spacing: Style.space(10)

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: "Show all in bar"
            color: section.foreground
            font.family: section.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
        }

        ToggleSwitch {
            Layout.alignment: Qt.AlignVCenter
            checked: section.compactMode
            foreground: section.foreground
            hasCursor: section.cursorActive && section.focusSection === "compact"
            onHovered: function (on) { if (on) section.hoverToggle() }
            onToggled: section.compactToggle(!section.compactMode)
        }
    }

    Repeater {
        model: section.devices
        delegate: CursorSurface {
            id: deviceRow
            required property var modelData
            required property int index
            width: section.width
            implicitHeight: deviceCol.implicitHeight + Style.spacing.rowPaddingX
            hasCursor: section.cursorActive && section.focusSection === "devices"
                && section.selectedIndex === index
            foreground: section.foreground

            readonly property int tier: DeviceIcons.tier(modelData.pct, modelData.state,
                section.lowThreshold, section.criticalThreshold)
            readonly property color tint: DeviceIcons.tierColor(tier, section.foreground)
            readonly property string deviceName: modelData.model || modelData.type
            readonly property bool pinned: section.pinnedNames.indexOf(deviceName) !== -1

            // Row click toggles the pin; hover moves the shared cursor here.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: section.hoverDevice(index)
                onClicked: section.activateDevice(index)
            }

            Column {
                id: deviceCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                // line 1: type glyph + name + pin button
                RowLayout {
                    width: parent.width
                    spacing: Style.space(10)

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: DeviceIcons.glyph(modelData.type)
                        color: deviceRow.tint
                        font.family: section.fontFamily
                        font.pixelSize: Style.font.heading
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        textFormat: Text.PlainText
                        text: deviceRow.deviceName
                        color: section.foreground
                        font.family: section.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    PanelActionButton {
                        Layout.alignment: Qt.AlignVCenter
                        iconText: deviceRow.pinned ? DeviceIcons.pin : DeviceIcons.pinOff
                        foreground: deviceRow.pinned ? Color.accent : Color.muted
                        hoverColor: section.foreground
                        tooltipText: deviceRow.pinned ? "Unpin from bar" : "Pin to bar"
                        onHovered: function (on) { if (on) section.hoverDevice(index) }
                        onClicked: section.togglePin(deviceRow.deviceName)
                    }
                }

                // line 2: charge bar + charging bolt + percentage
                RowLayout {
                    width: parent.width
                    spacing: Style.space(8)

                    Rectangle {
                        id: barTrack
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: section.barHeight
                        radius: height / 2
                        color: Qt.rgba(section.foreground.r, section.foreground.g, section.foreground.b, 0.12)

                        Rectangle {
                            width: Math.max(barTrack.height, barTrack.width * Math.max(0, Math.min(1, modelData.pct / 100)))
                            height: parent.height
                            radius: parent.radius
                            color: deviceRow.tint
                            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        visible: modelData.state === "charging"
                        text: DeviceIcons.bolt
                        color: deviceRow.tint
                        font.family: section.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: Style.space(40)
                        horizontalAlignment: Text.AlignRight
                        text: modelData.pct + "%"
                        color: deviceRow.tint
                        font.family: section.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
