import QtQuick
import QtQuick.Layouts
import qs.config

// Bloque redondeado dentro de la barra
Rectangle {
    id: pill
    default property alias content: row.data
    property alias spacing: row.spacing
    property bool hoverable: false
    property bool active: false
    signal clicked(var mouse)

    implicitHeight: Theme.pillHeight
    implicitWidth: row.implicitWidth + 20
    radius: Theme.radius
    color: active || (hoverable && area.containsMouse) ? Theme.surfaceHover : Theme.pill
    scale: area.pressed ? 0.95 : 1
    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
    Behavior on implicitWidth { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 10
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: pill.hoverable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => pill.clicked(mouse)
    }
}
