import QtQuick
import QtQuick.Layouts
import qs.config

// Botón de ajuste rápido estilo GNOME: parte izquierda activa/desactiva, flecha abre el submenú
Rectangle {
    id: tile
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool checked: false
    property bool busy: false
    property bool hasMenu: true
    signal toggled()
    signal opened()

    readonly property color fgc: checked ? Theme.textOnAccent : Theme.fg

    Layout.fillWidth: true
    implicitHeight: 60
    radius: 16
    color: checked ? Theme.accent : Theme.surface
    opacity: enabled ? 1 : 0.5
    Behavior on color { ColorAnimation { duration: Theme.animNormal } }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                radius: tile.radius
                color: mainArea.pressed ? Qt.rgba(0, 0, 0, 0.12) : mainArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 6 }
                spacing: 10

                BarText {
                    id: tileIcon
                    text: tile.icon
                    font.pixelSize: 20
                    color: tile.fgc
                    Behavior on color { ColorAnimation { duration: Theme.animNormal } }

                    SequentialAnimation on opacity {
                        running: tile.busy
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 450 }
                        NumberAnimation { to: 1; duration: 450 }
                        onRunningChanged: if (!running) tileIcon.opacity = 1
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    BarText {
                        Layout.fillWidth: true
                        text: tile.title
                        font.bold: true
                        elide: Text.ElideRight
                        color: tile.fgc
                    }
                    BarText {
                        Layout.fillWidth: true
                        text: tile.subtitle
                        font.pixelSize: Theme.fontSize - 2
                        elide: Text.ElideRight
                        color: tile.checked ? Qt.rgba(0.1, 0.06, 0.02, 0.75) : Theme.dim
                    }
                }
            }

            MouseArea {
                id: mainArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tile.toggled()
            }
        }

        Rectangle {
            visible: tile.hasMenu
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            Layout.topMargin: 14
            Layout.bottomMargin: 14
            color: tile.checked ? Qt.rgba(0, 0, 0, 0.2) : Theme.border
        }

        Item {
            visible: tile.hasMenu
            Layout.preferredWidth: 40
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: 10
                color: menuArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
            }
            BarText {
                anchors.centerIn: parent
                text: Icons.chevronRight
                font.pixelSize: 18
                color: tile.fgc
            }
            MouseArea {
                id: menuArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tile.opened()
            }
        }
    }
}
