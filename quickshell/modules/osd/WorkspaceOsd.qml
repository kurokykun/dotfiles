import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services
import qs.widgets

// Aviso al cambiar de escritorio (sustituye al OSD de labwc: rc.xml <popupTime>0</popupTime>).
// Pastilla centrada con los mismos puntos que la barra + nombre del escritorio. No recibe clics.
PanelWindow {
    id: win

    property bool shown: false
    screen: Quickshell.screens.find(s => s.name === Ui.dockMonitor) ?? Quickshell.screens[0]
    visible: shown || card.opacity > 0
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-workspace-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    color: "transparent"
    implicitWidth: card.implicitWidth + 40
    implicitHeight: card.implicitHeight + 40

    Connections {
        target: Workspaces
        function onSwitched(i) {
            win.shown = true;
            hideTimer.restart();
            pop.restart();
        }
    }
    Timer { id: hideTimer; interval: 900; onTriggered: win.shown = false }

    Rectangle {
        id: card
        anchors.centerIn: parent
        implicitWidth: col.implicitWidth + 48
        implicitHeight: col.implicitHeight + 32
        radius: 24
        color: Theme.bg
        border.width: 1
        border.color: Theme.border
        opacity: win.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

        // Pequeño rebote al aparecer o cambiar otra vez
        SequentialAnimation {
            id: pop
            NumberAnimation { target: card; property: "scale"; to: 1.05; duration: 90; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "scale"; to: 1.0; duration: 160; easing.type: Easing.OutBack }
        }

        ColumnLayout {
            id: col
            anchors.centerIn: parent
            spacing: 12

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                Repeater {
                    model: Workspaces.list
                    delegate: Rectangle {
                        required property var modelData
                        width: modelData.active ? 44 : 14
                        height: 14
                        radius: 7
                        color: modelData.active ? Theme.accent : Qt.rgba(1, 1, 1, 0.22)
                        Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: Theme.animNormal } }
                    }
                }
            }

            BarText {
                Layout.alignment: Qt.AlignHCenter
                text: Workspaces.active?.name ?? ""
                font.pixelSize: Theme.fontSize + 2
                font.bold: true
            }
        }
    }
}
