import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services
import qs.widgets

// Pastilla flotante abajo al centro: volumen, brillo, micrófono y teclado.
// No recibe clics ni foco (los atraviesa).
PanelWindow {
    id: win

    screen: Quickshell.screens.find(s => s.name === Ui.dockMonitor) ?? Quickshell.screens[0]
    anchors.bottom: true
    margins.bottom: 90
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    color: "transparent"

    // Sigue visible mientras termina la animación de salida
    visible: Osd.visible || card.opacity > 0
    implicitWidth: card.implicitWidth + 24
    implicitHeight: card.implicitHeight + 24

    readonly property bool hasBar: Osd.value >= 0
    readonly property color tint: Osd.muted ? Theme.dim
                                 : Osd.value > 1.0 ? Theme.accent2
                                 : Theme.accent

    Rectangle {
        id: card
        anchors.centerIn: parent
        implicitWidth: win.hasBar ? 320 : row.implicitWidth + 40
        implicitHeight: 56
        radius: height / 2
        color: Theme.bg
        border.width: 1
        border.color: Theme.border

        opacity: Osd.visible ? 1 : 0
        scale: Osd.visible ? 1 : 0.92
        transform: Translate { y: Osd.visible ? 0 : 14; Behavior on y { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack } }
        Behavior on implicitWidth { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        RowLayout {
            id: row
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 14

            // Icono en un círculo con el color de acento
            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 16
                color: Qt.rgba(win.tint.r, win.tint.g, win.tint.b, 0.18)
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                BarText {
                    anchors.centerIn: parent
                    text: Osd.icon
                    color: win.tint
                    font.pixelSize: 18
                }
            }

            // Barra de nivel
            Item {
                visible: win.hasBar
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: Theme.surface
                }
                Rectangle {
                    height: parent.height
                    radius: 3
                    width: parent.width * Math.max(0, Math.min(1, Osd.value))
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Osd.muted ? Theme.dim : Theme.accent }
                        GradientStop { position: 1; color: Osd.muted ? Theme.dim : (Osd.value > 1.0 ? Theme.accent2 : Qt.lighter(Theme.accent, 1.15)) }
                    }
                    Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                }
            }

            BarText {
                text: Osd.text
                color: Osd.muted ? Theme.dim : Theme.fg
                font.bold: true
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: win.hasBar ? Math.max(44, implicitWidth) : implicitWidth
            }
        }
    }
}
