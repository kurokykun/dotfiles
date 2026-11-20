import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// Avisos flotantes arriba a la derecha. Al desaparecer quedan en el centro de notificaciones
// (clic en la hora de la barra). No se muestran con el panel de fecha abierto.
PanelWindow {
    id: toasts

    screen: Quickshell.screens[0]
    visible: Notifs.popups.length > 0 && !Ui.dateOpen
    anchors { top: true; right: true }
    margins {
        top: Theme.barHeight + Theme.gap
        right: Theme.gap
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    implicitWidth: 380
    implicitHeight: column.implicitHeight
    color: "transparent"

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            model: Notifs.popups
            delegate: NotifCard {
                id: toast
                required property var modelData
                notif: modelData
                popup: true
                onTimedOut: Notifs.hidePopup(modelData)

                // Entrada deslizándose desde la derecha
                transform: Translate { id: shift; x: 40 }
                opacity: 0
                Component.onCompleted: enter.start()
                ParallelAnimation {
                    id: enter
                    NumberAnimation { target: shift; property: "x"; to: 0; duration: Theme.animNormal; easing.type: Easing.OutCubic }
                    NumberAnimation { target: toast; property: "opacity"; to: 1; duration: Theme.animNormal }
                }
            }
        }
    }
}
