import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Inhibidor de inactividad para la cafeína (services/Caffeine.qml).
// El protocolo idle-inhibit necesita una superficie visible: una capa de 1 px,
// transparente y que no recibe clics. Mientras esté activo, swayidle no bloquea ni apaga la pantalla.
PanelWindow {
    id: win
    anchors { top: true; left: true }
    implicitWidth: 1
    implicitHeight: 1
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell-idle-inhibit"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    color: "transparent"

    IdleInhibitor {
        window: win
        enabled: Caffeine.active
    }
}
