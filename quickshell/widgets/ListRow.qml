import QtQuick
import QtQuick.Layouts
import qs.config

// Fila de lista: icono, título, subtítulo y controles a la derecha
Rectangle {
    id: row
    property string icon: ""
    property color iconColor: Theme.fg
    property string title: ""
    property string subtitle: ""
    property bool highlighted: false
    property bool clickable: true
    property bool busy: false
    default property alias trailing: trail.data
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: subtitle !== "" ? 52 : 42
    radius: 12
    color: highlighted ? Theme.surfaceHover : area.containsMouse && clickable ? Theme.surface : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: row.clickable
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }

    RowLayout {
        anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
        spacing: 12

        BarText {
            id: rowIcon
            Layout.preferredWidth: 22
            horizontalAlignment: Text.AlignHCenter
            text: row.icon
            font.pixelSize: 18
            color: row.iconColor

            SequentialAnimation on opacity {
                running: row.busy
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 450 }
                NumberAnimation { to: 1; duration: 450 }
                onRunningChanged: if (!running) rowIcon.opacity = 1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            BarText {
                Layout.fillWidth: true
                text: row.title
                elide: Text.ElideRight
                font.bold: row.highlighted
            }
            BarText {
                Layout.fillWidth: true
                visible: row.subtitle !== ""
                text: row.subtitle
                elide: Text.ElideRight
                color: Theme.dim
                font.pixelSize: Theme.fontSize - 2
            }
        }

        RowLayout {
            id: trail
            spacing: 6
        }
    }
}
