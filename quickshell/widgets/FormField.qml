import QtQuick
import QtQuick.Layouts
import qs.config

// Campo de texto (opcionalmente de contraseña con botón para mostrarla)
ColumnLayout {
    id: field
    property string label: ""
    property alias text: input.text
    property string placeholder: ""
    property bool password: false
    property bool reveal: false
    signal accepted()

    function focusInput() { input.forceActiveFocus(); }
    function clear() { input.text = ""; reveal = false; }

    Layout.fillWidth: true
    spacing: 4

    BarText {
        visible: field.label !== ""
        text: field.label
        color: Theme.dim
        font.pixelSize: Theme.fontSize - 2
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 38
        radius: 10
        color: Theme.surface
        border.width: 1
        border.color: input.activeFocus ? Theme.accent : Theme.border
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: input.forceActiveFocus()
        }

        TextInput {
            id: input
            anchors {
                left: parent.left
                right: eye.visible ? eye.left : parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 12
                rightMargin: 10
            }
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            echoMode: field.password && !field.reveal ? TextInput.Password : TextInput.Normal
            selectByMouse: true
            selectionColor: Theme.accent
            selectedTextColor: Theme.textOnAccent
            clip: true
            onAccepted: field.accepted()
            // Texto puesto desde código: mostrar el principio, no el final
            onTextChanged: if (!activeFocus) cursorPosition = 0

            BarText {
                anchors.fill: parent
                visible: input.text === ""
                text: field.placeholder
                color: Theme.dim
                elide: Text.ElideRight
            }
        }

        BarText {
            id: eye
            visible: field.password
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: field.reveal ? Icons.eyeOff : Icons.eye
            color: eyeArea.containsMouse ? Theme.fg : Theme.dim
            font.pixelSize: 16
            MouseArea {
                id: eyeArea
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: field.reveal = !field.reveal
            }
        }
    }
}
