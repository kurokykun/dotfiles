import QtQuick
import QtQuick.Layouts
import qs.config

// Botón: kind = "normal" | "primary" | "danger" | "icon"
Rectangle {
    id: btn
    property string icon: ""
    property string text: ""
    property string kind: "normal"
    property bool busy: false
    signal clicked()

    readonly property color fgc: kind === "primary" ? Theme.textOnAccent : kind === "danger" ? Theme.red : Theme.fg

    implicitHeight: kind === "icon" ? 32 : 36
    implicitWidth: kind === "icon" ? 32 : row.implicitWidth + 24
    radius: 10
    color: kind === "primary" ? (area.containsMouse ? Qt.lighter(Theme.accent, 1.12) : Theme.accent)
         : kind === "danger" ? (area.containsMouse ? Qt.rgba(1, 0.36, 0.36, 0.28) : Qt.rgba(1, 0.36, 0.36, 0.14))
         : kind === "icon" ? (area.containsMouse ? Theme.surfaceHover : "transparent")
         : (area.containsMouse ? Theme.surfaceHover : Theme.surface)
    opacity: enabled ? 1 : 0.45
    scale: area.pressed ? 0.95 : 1
    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on scale { NumberAnimation { duration: Theme.animFast } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        BarText {
            id: iconText
            visible: btn.icon !== ""
            text: btn.icon
            color: btn.fgc
            font.pixelSize: btn.kind === "icon" ? 17 : Theme.fontSize + 1

            RotationAnimation on rotation {
                running: btn.busy
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
                onRunningChanged: if (!running) iconText.rotation = 0
            }
        }
        BarText {
            visible: btn.text !== ""
            text: btn.text
            color: btn.fgc
            font.pixelSize: Theme.fontSize - 1
            font.bold: btn.kind === "primary"
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
