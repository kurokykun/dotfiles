import QtQuick
import qs.config

// Interruptor on/off
Rectangle {
    id: sw
    property bool checked: false
    property bool busy: false
    signal toggled()

    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    color: checked ? Theme.accent : Theme.surfaceHover
    opacity: busy ? 0.5 : 1
    Behavior on color { ColorAnimation { duration: 150 } }

    Rectangle {
        width: 16
        height: 16
        radius: 8
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? sw.width - width - 3 : 3
        color: sw.checked ? Theme.bgSolid : Theme.fg
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: !sw.busy
        onClicked: sw.toggled()
    }
}
