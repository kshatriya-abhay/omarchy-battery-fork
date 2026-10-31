import QtQuick
import QtQuick.Layouts
import qs.Ui         // PanelSectionHeader
import qs.Commons    // Color, Style tokens

// "PERIPHERALS" section of the power popup, adapted from hl.peripheral_battery's
// DevicePanel. Read-only: one row per device with its type glyph, name, charge
// bar and percentage. A row turns red once the device is at or below the low
// threshold, the same point where the low-battery notification fires.
Column {
    id: section

    property var bar: null
    property var devices: []
    property int lowThreshold: 20
    property int criticalThreshold: 10

    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property real barHeight: Math.max(4, Math.round(Style.spacing.controlHeight * 0.2))

    spacing: Style.space(12)

    PanelSectionHeader {
        text: "PERIPHERALS"
        foreground: section.foreground
        fontFamily: section.fontFamily
    }

    Repeater {
        model: section.devices
        delegate: Column {
            id: deviceRow
            required property var modelData
            width: section.width
            spacing: Style.space(6)

            readonly property bool low: DeviceIcons.tier(modelData.pct, modelData.state,
                section.lowThreshold, section.criticalThreshold) > 0
            readonly property color tint: low ? Color.urgent : section.foreground

            // line 1: type glyph + name + charging bolt + percentage
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
                    text: modelData.model || modelData.type
                    color: deviceRow.tint
                    font.family: section.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    maximumLineCount: 1
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
                    text: modelData.pct + "%"
                    color: deviceRow.tint
                    font.family: section.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.weight: Font.Medium
                }
            }

            // line 2: charge bar, styled like the laptop battery bar above
            Rectangle {
                id: barTrack
                width: parent.width
                height: section.barHeight
                radius: height / 2
                color: Qt.rgba(section.foreground.r, section.foreground.g, section.foreground.b, 0.12)

                Rectangle {
                    width: Math.max(barTrack.height, barTrack.width * Math.max(0, Math.min(1, modelData.pct / 100)))
                    height: parent.height
                    radius: parent.radius
                    color: deviceRow.tint
                    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }
    }
}
