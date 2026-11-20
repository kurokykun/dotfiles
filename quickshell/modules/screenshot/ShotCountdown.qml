import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services
import qs.widgets

// Cuenta atrás del temporizador de capturas (centro de la pantalla).
// Se oculta antes de capturar (Screenshot espera 250 ms) para no salir en la imagen.
PanelWindow {
    id: cd

    visible: Screenshot.countdown > 0
    screen: Screenshot.screen ?? Quickshell.screens[0]
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-screenshot-countdown"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    implicitWidth: 150
    implicitHeight: 176
    color: "transparent"

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 120
            implicitHeight: 120
            radius: 60
            color: Qt.alpha(Theme.bgSolid, 0.88)
            border.width: 3
            border.color: Theme.accent

            BarText {
                anchors.centerIn: parent
                text: Screenshot.countdown
                font.pixelSize: 56
                font.bold: true
                color: Theme.fg
            }
            // Pulso en cada segundo
            SequentialAnimation on scale {
                running: cd.visible
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 1.06; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { to: 1.0; duration: 850; easing.type: Easing.InOutSine }
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: cancelRow.implicitWidth + 24
            implicitHeight: 32
            radius: 16
            color: cancelArea.containsMouse ? Qt.rgba(1, 0.36, 0.36, 0.25) : Qt.alpha(Theme.bgSolid, 0.88)
            RowLayout {
                id: cancelRow
                anchors.centerIn: parent
                spacing: 6
                BarText { text: Icons.close; color: Theme.red; font.pixelSize: 13 }
                BarText { text: "Cancelar"; font.pixelSize: Theme.fontSize - 2 }
            }
            MouseArea {
                id: cancelArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Screenshot.cancelCountdown()
            }
        }
    }
}
