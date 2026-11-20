import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// Ventana emergente bajo la barra (arriba a la derecha) con:
//  · capa invisible para cerrar al hacer clic fuera
//  · tarjeta redondeada con animación de apertura
//  · Esc para cerrar
// Uso: PanelPopup { open: Ui.xOpen; onCloseRequested: Ui.xOpen = false; ...contenido... }
Scope {
    id: pp

    property bool open: false
    property int panelWidth: 400
    property string name: "panel"
    default property alias content: column.data
    signal closeRequested()

    PanelWindow {
        visible: pp.open
        screen: Ui.popupScreen ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-" + pp.name + "-backdrop"
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            onClicked: pp.closeRequested()
        }
    }

    PanelWindow {
        id: popup
        visible: pp.open
        screen: Ui.popupScreen ?? Quickshell.screens[0]
        anchors { top: true; right: true }
        margins {
            top: Theme.barHeight + Theme.gap
            right: Theme.gap
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-" + pp.name
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        implicitWidth: pp.panelWidth
        implicitHeight: card.implicitHeight
        color: "transparent"

        Rectangle {
            id: card
            anchors.fill: parent
            implicitHeight: column.implicitHeight + 32
            radius: 22
            color: Theme.bgSolid
            border.width: 1
            border.color: Theme.border
            focus: true
            Keys.onEscapePressed: pp.closeRequested()

            opacity: 0
            transform: Translate { id: drop; y: -12 }
            Connections {
                target: popup
                function onVisibleChanged() { if (popup.visible) openAnim.restart(); }
            }
            ParallelAnimation {
                id: openAnim
                NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Theme.animNormal }
                NumberAnimation { target: drop; property: "y"; from: -12; to: 0; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                id: column
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 14
            }
        }
    }
}
