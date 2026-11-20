import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.services
import qs.widgets

// Menú de apagado a pantalla completa.
// Bloquear y Suspender actúan al momento; Cerrar sesión, Reiniciar y Apagar piden confirmación
// con cuenta atrás (pulsar otra vez = hacerlo ya, Esc = cancelar).
// Teclado: ←/→ elegir · Enter confirmar · B S C R A atajos · Esc cerrar.
PanelWindow {
    id: menu

    // Visible mientras está abierto y hasta que termina la animación de salida
    // (si dependiera de "fade.running", habría un instante sin ventana → parpadeo)
    property bool shown: false
    visible: shown
    screen: Ui.popupScreen ?? Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-power"
    WlrLayershell.keyboardFocus: Ui.powerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    readonly property string userName: {
        const u = Quickshell.env("USER") || "usuario";
        return u.charAt(0).toUpperCase() + u.slice(1);
    }

    readonly property var actions: [
        { id: "lock",     icon: Icons.lock,          label: "Bloquear",      key: Qt.Key_B, confirm: false,
          verb: "", cmd: ["sh", "-c", "sleep 0.3; exec \"$0\"", Quickshell.shellDir + "/scripts/lock.sh"] },
        { id: "suspend",  icon: String.fromCodePoint(0xF0904), label: "Suspender", key: Qt.Key_S, confirm: false,
          verb: "", cmd: ["systemctl", "suspend"] },
        { id: "logout",   icon: String.fromCodePoint(0xF0343), label: "Cerrar sesión", key: Qt.Key_C, confirm: true,
          verb: "Cerrando sesión", cmd: ["labwc", "--exit"] },
        { id: "reboot",   icon: String.fromCodePoint(0xF0709), label: "Reiniciar", key: Qt.Key_R, confirm: true,
          verb: "Reiniciando", cmd: ["systemctl", "reboot"] },
        { id: "poweroff", icon: String.fromCodePoint(0xF0425), label: "Apagar", key: Qt.Key_A, confirm: true,
          verb: "Apagando", cmd: ["systemctl", "poweroff"] }
    ]

    property int selected: 4          // por defecto: Apagar
    property string pending: ""       // acción esperando confirmación
    property int countdown: 0
    readonly property int confirmSeconds: 5
    readonly property var pendingAction: actions.find(a => a.id === pending) ?? null

    function trigger(a) {
        if (a.confirm && pending !== a.id) {
            pending = a.id;
            countdown = confirmSeconds;
            ticker.restart();
            return;
        }
        run(a);
    }

    function run(a) {
        ticker.stop();
        pending = "";
        Ui.powerOpen = false;
        Quickshell.execDetached(a.cmd);
    }

    function cancel() {
        if (pending) { pending = ""; ticker.stop(); }
        else Ui.powerOpen = false;
    }

    // Carga perezosa (shell.qml): el panel se crea ya abierto → ejecutar la apertura al crearse
    Component.onCompleted: if (Ui.powerOpen) uiConn.onPowerOpenChanged()
    Connections {
        id: uiConn
        target: Ui
        function onPowerOpenChanged() {
            if (Ui.powerOpen) {
                menu.selected = 4;
                menu.pending = "";
                uptimeFile.reload();
                menu.shown = true;
                fade.from = shade.opacity; fade.to = 1; fade.restart();
                content.forceActiveFocus();
            } else {
                ticker.stop();
                menu.pending = "";
                fade.from = shade.opacity; fade.to = 0; fade.restart();
            }
        }
    }

    Timer {
        id: ticker
        interval: 1000
        repeat: true
        onTriggered: {
            menu.countdown--;
            if (menu.countdown <= 0 && menu.pendingAction) menu.run(menu.pendingAction);
        }
    }

    // Tiempo encendido
    FileView { id: uptimeFile; path: "/proc/uptime" }
    readonly property string uptime: {
        const secs = parseFloat((uptimeFile.text() || "0").split(" ")[0]);
        const d = Math.floor(secs / 86400), h = Math.floor(secs % 86400 / 3600), m = Math.floor(secs % 3600 / 60);
        if (d > 0) return d + " d " + h + " h";
        if (h > 0) return h + " h " + m + " min";
        return m + " min";
    }

    // ───── Fondo oscurecido ─────
    Rectangle {
        id: shade
        anchors.fill: parent
        color: "transparent"
        opacity: 0

        NumberAnimation {
            id: fade
            target: shade
            property: "opacity"
            duration: Theme.animNormal
            easing.type: Easing.OutCubic
            // Al terminar de desvanecerse, ocultar la ventana
            onFinished: if (!Ui.powerOpen) menu.shown = false
        }

        // Tu fondo de pantalla desenfocado y oscurecido
        BlurBackdrop { anchors.fill: parent }

        // Clic en el fondo = cancelar
        MouseArea {
            anchors.fill: parent
            onClicked: menu.cancel()
        }

        ColumnLayout {
            id: content
            anchors.centerIn: parent
            spacing: 28
            focus: true
            scale: 0.94 + 0.06 * shade.opacity

            Keys.onEscapePressed: menu.cancel()
            Keys.onLeftPressed: { menu.selected = (menu.selected + menu.actions.length - 1) % menu.actions.length; }
            Keys.onRightPressed: { menu.selected = (menu.selected + 1) % menu.actions.length; }
            Keys.onReturnPressed: menu.trigger(menu.actions[menu.selected])
            Keys.onEnterPressed: menu.trigger(menu.actions[menu.selected])
            Keys.onPressed: event => {
                const i = menu.actions.findIndex(a => a.key === event.key);
                if (i >= 0) { menu.selected = i; menu.trigger(menu.actions[i]); event.accepted = true; }
            }

            // ───── Usuario ─────
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 92
                    implicitHeight: 92
                    radius: 46
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: Theme.accent2 }
                    }
                    BarText {
                        anchors.centerIn: parent
                        text: menu.userName.charAt(0)
                        font.pixelSize: 44
                        font.bold: true
                        color: Theme.textOnAccent
                    }
                }
                BarText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Hasta luego, " + menu.userName
                    font.pixelSize: 24
                    font.bold: true
                }
                BarText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Encendido desde hace " + menu.uptime
                    color: Theme.dim
                }
            }

            // ───── Acciones ─────
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 18

                Repeater {
                    model: menu.actions
                    delegate: Item {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool isSelected: menu.selected === index
                        readonly property bool isPending: menu.pending === modelData.id
                        readonly property bool danger: modelData.id === "poweroff"

                        implicitWidth: 128
                        implicitHeight: 140

                        // Entrada escalonada
                        opacity: shade.opacity
                        transform: Translate { y: (1 - shade.opacity) * (20 + tile.index * 8) }

                        Rectangle {
                            id: btn
                            width: 116
                            height: 116
                            anchors.horizontalCenter: parent.horizontalCenter
                            radius: 32
                            color: tile.isPending ? (tile.danger ? Theme.red : Theme.accent)
                                 : tile.isSelected || area.containsMouse ? Qt.rgba(1, 1, 1, 0.14)
                                 : Qt.rgba(1, 1, 1, 0.06)
                            border.width: tile.isSelected && !tile.isPending ? 2 : 0
                            border.color: tile.danger ? Theme.red : Theme.accent
                            scale: area.pressed ? 0.93 : (area.containsMouse || tile.isSelected) ? 1.05 : 1
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }

                            // Progreso de la cuenta atrás (se vacía de abajo arriba)
                            Rectangle {
                                visible: tile.isPending
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: parent.height * (menu.countdown / menu.confirmSeconds)
                                radius: parent.radius
                                color: Qt.rgba(0, 0, 0, 0.18)
                                Behavior on height { NumberAnimation { duration: 950 } }
                            }

                            BarText {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: tile.isPending ? -10 : 0
                                text: tile.modelData.icon
                                font.pixelSize: 40
                                color: tile.isPending ? Theme.textOnAccent : tile.danger ? Theme.red : Theme.fg
                            }
                            BarText {
                                visible: tile.isPending
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 14
                                text: menu.countdown + " s"
                                font.bold: true
                                color: Theme.textOnAccent
                            }

                            MouseArea {
                                id: area
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: menu.selected = tile.index
                                onClicked: menu.trigger(tile.modelData)
                            }
                        }

                        BarText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            text: tile.modelData.label
                            font.bold: tile.isSelected
                            color: tile.isSelected ? Theme.fg : Theme.dim
                        }
                    }
                }
            }

            // ───── Confirmación / ayuda ─────
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                BarText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: menu.pendingAction !== null
                    text: menu.pendingAction ? menu.pendingAction.verb + " en " + menu.countdown + " s…" : ""
                    font.pixelSize: Theme.fontSize + 3
                    font.bold: true
                    color: menu.pending === "poweroff" ? Theme.red : Theme.accent
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    visible: menu.pendingAction !== null
                    spacing: 10
                    ActionButton {
                        text: "Cancelar"
                        onClicked: menu.cancel()
                    }
                    ActionButton {
                        kind: menu.pending === "poweroff" ? "danger" : "primary"
                        text: menu.pendingAction ? menu.pendingAction.label + " ahora" : ""
                        onClicked: if (menu.pendingAction) menu.run(menu.pendingAction)
                    }
                }
                BarText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: menu.pendingAction === null
                    text: "←/→ elegir · Enter confirmar · Esc cancelar"
                    color: Qt.rgba(1, 1, 1, 0.35)
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }
}
