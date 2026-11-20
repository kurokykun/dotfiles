import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Quickshell.Bluetooth
import qs.config
import qs.services
import qs.widgets

// Barra superior sólida con módulos agrupados
PanelWindow {
    id: bar

    required property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: Theme.bar

    function toggleAudioPanel() {
        const same = Ui.popupScreen === bar.screen;
        Ui.popupScreen = bar.screen;
        Ui.audioOpen = !(Ui.audioOpen && same);
    }

    function toggleBatteryPanel() {
        const same = Ui.popupScreen === bar.screen;
        Ui.popupScreen = bar.screen;
        Ui.batteryOpen = !(Ui.batteryOpen && same);
    }

    function esc(t) { return (t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

    // ───── Bandeja: relacionar cada icono con las ventanas de su app ─────
    // Nombres posibles de la app a partir del id/título del icono ("spotify-client" → "spotify", "Google Chrome" → "google-chrome")
    function trayNames(item) {
        const out = [];
        for (const raw of [item.id, item.title, item.tooltipTitle]) {
            if (!raw) continue;
            const n = raw.toLowerCase().trim();
            out.push(n, n.replace(/\s+/g, "-"), n.replace(/[-_ ]?(client|status[-_ ]?icon[-_ ]?\d*|tray|indicator|applet)$/, ""));
        }
        return out.filter(x => x.length >= 3);
    }

    function trayWindows(item) {
        const names = trayNames(item);
        return ToplevelManager.toplevels.values.filter(t => {
            const app = (t.appId || "").toLowerCase();
            if (!app) return false;
            const last = app.split(".").pop();   // org.gnome.Nautilus → nautilus
            return names.some(n => n === app || n === last || app.startsWith(n) || n.startsWith(last));
        });
    }

    // Devuelve true si la app tenía ventanas (y las gestionó); false si hay que dejarlo a la app
    function toggleTrayWindows(item) {
        const wins = trayWindows(item);
        if (wins.length === 0) return false;
        if (wins.some(w => w.activated && !w.minimized)) {
            for (const w of wins) w.minimized = true;        // en primer plano → minimizar
        } else {
            for (const w of wins) if (w.minimized) w.minimized = false;
            wins[0].activate();                               // minimizada/detrás → restaurar y enfocar
        }
        return true;
    }

    // Entrada .desktop de la app del icono ("spotify" → spotify-launcher.desktop, "steam" → steam.desktop)
    function trayDesktopEntry(item) {
        const names = trayNames(item);
        for (const n of names) {
            const e = DesktopEntries.byId(n) ?? (DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(n) : null);
            if (e) return e;
        }
        const apps = DesktopEntries.applications.values;
        for (const n of names) {
            const e = apps.find(a => (a.id || "").toLowerCase().startsWith(n) || (a.name || "").toLowerCase() === n);
            if (e) return e;
        }
        return null;
    }

    // App cerrada a la bandeja (sin ventanas): pedirle que se muestre.
    // Los iconos Ayatana/AppIndicator (Spotify, Steam, Electron…) ignoran Activate, así que si
    // no aparece ninguna ventana se relanza la app; al ser de instancia única, muestra la existente.
    property var pendingTrayItem: null
    function restoreFromTray(item) {
        if (!item.onlyMenu) item.activate();
        pendingTrayItem = item;
        trayFallback.restart();
    }

    Timer {
        id: trayFallback
        interval: 500
        onTriggered: {
            const item = bar.pendingTrayItem;
            bar.pendingTrayItem = null;
            if (!item || bar.trayWindows(item).length > 0) return;
            const entry = bar.trayDesktopEntry(item);
            if (entry) {
                entry.execute();
            } else if (item.hasMenu) {
                const p = Qt.point(bar.width - 200, Theme.barHeight + 6);
                item.display(bar, p.x, p.y);
            }
        }
    }

    // Línea inferior sutil
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.border
    }

    // ───────────── Izquierda: escritorios + ventana activa ─────────────
    RowLayout {
        anchors.left: parent.left
        anchors.leftMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.gap

        // Escritorios: clic = ir · rueda = siguiente/anterior · el activo se alarga
        Pill {
            id: wsPill
            visible: Workspaces.count > 0
            spacing: 6

            Repeater {
                model: Workspaces.list
                delegate: Item {
                    id: wsDot
                    required property var modelData
                    required property int index
                    readonly property bool on: modelData.active
                    implicitWidth: on ? 26 : 10
                    implicitHeight: 18
                    Behavior on implicitWidth { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.implicitWidth
                        height: 10
                        radius: 5
                        color: wsDot.on ? Theme.accent
                             : wsArea.containsMouse ? Qt.rgba(1, 1, 1, 0.55)
                             : wsDot.modelData.urgent ? Theme.accent2 : Qt.rgba(1, 1, 1, 0.25)
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }
                    MouseArea {
                        id: wsArea
                        anchors.fill: parent
                        anchors.margins: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Workspaces.activate(wsDot.index)
                    }
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: e => { if (e.angleDelta.y < 0) Workspaces.next(); else if (e.angleDelta.y > 0) Workspaces.previous(); }
            }
        }

        Pill {
            id: winPill
            readonly property var win: ToplevelManager.activeToplevel
            visible: win !== null && win !== undefined && (win.title || win.appId) ? true : false
            BarText {
                Layout.maximumWidth: 390
                elide: Text.ElideRight
                text: winPill.win ? (winPill.win.title || winPill.win.appId) : ""
            }
        }
    }

    // ───────────── Centro: reproducción actual (Spotify) ─────────────
    // Clic: panel de música · Clic central: reproducir/pausar · Rueda: siguiente/anterior
    Rectangle {
        id: mediaPill
        anchors.centerIn: parent
        visible: Media.active
        implicitHeight: Theme.pillHeight
        implicitWidth: mediaRow.implicitWidth + 20
        radius: Theme.radius
        color: (Ui.mediaOpen && Ui.popupScreen === bar.screen) || mediaArea.containsMouse ? Theme.surfaceHover : Theme.pill
        clip: true
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on implicitWidth { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

        RowLayout {
            id: mediaRow
            anchors.centerIn: parent
            spacing: 8

            ClippingRectangle {
                implicitWidth: 20
                implicitHeight: 20
                radius: 5
                color: Theme.surface
                Image {
                    anchors.fill: parent
                    source: Media.art
                    sourceSize.width: 40
                    sourceSize.height: 40
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            Equalizer {
                playing: Media.playing
                color: Media.playing ? Theme.accent : Theme.dim
                maxHeight: 11
                barWidth: 2
            }

            BarText {
                Layout.maximumWidth: 340
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSize - 1
                textFormat: Text.StyledText
                // Título en negrita y el artista en otro tono
                text: "<b>" + bar.esc(Media.title) + "</b>"
                    + (Media.artist ? "<font color='" + Theme.dim + "'>  ·  " + bar.esc(Media.artist) + "</font>" : "")
            }
        }

        // Progreso de la canción, línea fina al pie
        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            height: 2
            width: parent.width * Media.progress
            color: Theme.accent
            opacity: 0.85
            // Sin animación: avanza a saltos de 1 s (animarla redibujaba la barra 144 veces por segundo)
        }

        MouseArea {
            id: mediaArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) { Media.toggle(); return; }
                const same = Ui.popupScreen === bar.screen;
                Ui.popupScreen = bar.screen;
                Ui.mediaOpen = !(Ui.mediaOpen && same);
            }
            onWheel: wheel => wheel.angleDelta.y > 0 ? Media.previous() : Media.next()
        }
    }

    // ───────────── Derecha: bandeja · red/volumen/batería · apagado ─────────────
    RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.gap

        // Bandeja (se oculta el icono de nm-applet, que solo está como agente de contraseñas)
        Pill {
            id: trayPill
            readonly property var items: SystemTray.items.values.filter(i => i.id !== "nm-applet")
            visible: items.length > 0
            spacing: 10

            Repeater {
                model: trayPill.items

                delegate: IconImage {
                    id: trayIcon
                    required property var modelData
                    implicitSize: 18
                    source: modelData.icon

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            const item = trayIcon.modelData;
                            if (mouse.button === Qt.LeftButton && bar.toggleTrayWindows(item)) {
                                // Tenía ventana: restaurada/enfocada o minimizada
                            } else if (mouse.button === Qt.LeftButton) {
                                bar.restoreFromTray(item);   // sin ventana (cerrada a la bandeja): mostrarla
                            } else if (item.hasMenu) {
                                const p = trayIcon.mapToItem(null, 0, trayIcon.height + 12);
                                item.display(bar, p.x, p.y);
                            }
                        }
                    }
                }
            }
        }

        // Grabando pantalla: punto rojo + tiempo · clic = detener
        Pill {
            visible: Screenshot.recording
            hoverable: true
            spacing: 8
            onClicked: Screenshot.stopRecording()
            Rectangle {
                implicitWidth: 10
                implicitHeight: 10
                radius: 5
                color: Theme.red
                SequentialAnimation on opacity {
                    running: Screenshot.recording
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 700 }
                    NumberAnimation { to: 1; duration: 700 }
                }
            }
            BarText {
                text: Math.floor(Screenshot.recSeconds / 60) + ":" + ("0" + Screenshot.recSeconds % 60).slice(-2)
                font.bold: true
            }
            BarText { text: Icons.close; color: Theme.dim; font.pixelSize: Theme.fontSize - 1 }
        }

        // Indicadores de modos activos (solo aparece si hay alguno):
        // luz nocturna → panel de energía · no molestar → calendario · portapapeles en pausa → reanudar
        Pill {
            id: modesPill
            readonly property var modes: [
                { on: NightLight.warmNow, icon: Icons.moon, tip: "Luz nocturna activa", act: "battery" },
                { on: Notifs.dnd, icon: Icons.bellOff, tip: "No molestar", act: "date" },
                { on: Clipboard.paused, icon: Icons.eyeOff, tip: "Portapapeles en pausa (clic: reanudar)", act: "clip" }
            ].filter(m => m.on)
            visible: modes.length > 0
            spacing: 10

            Repeater {
                model: modesPill.modes
                delegate: BarText {
                    id: modeIcon
                    required property var modelData
                    text: modelData.icon
                    color: Theme.accent
                    font.pixelSize: Theme.fontSize + 2

                    MouseArea {
                        id: modeArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const a = modeIcon.modelData.act;
                            if (a === "battery") bar.toggleBatteryPanel();
                            else if (a === "clip") Clipboard.setPaused(false);
                            else {
                                const same = Ui.popupScreen === bar.screen;
                                Ui.popupScreen = bar.screen;
                                Ui.dateOpen = !(Ui.dateOpen && same);
                            }
                        }
                    }

                    // Aviso al pasar el ratón
                    PopupWindow {
                        visible: modeArea.containsMouse
                        anchor.window: bar
                        anchor.rect.x: modeIcon.mapToItem(null, 0, 0).x + modeIcon.width / 2 - implicitWidth / 2
                        anchor.rect.y: bar.height + 4
                        implicitWidth: tipText.implicitWidth + 20
                        implicitHeight: 28
                        color: "transparent"
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: Theme.bgSolid
                            border.width: 1
                            border.color: Theme.border
                            BarText {
                                id: tipText
                                anchors.centerIn: parent
                                text: modeIcon.modelData.tip
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }
                    }
                }
            }
        }

        // Estado del sistema
        Pill {
            spacing: 14

            // Red + VPN (clic: panel de red)
            Rectangle {
                id: netButton
                implicitWidth: netRow.implicitWidth + 12
                implicitHeight: Theme.pillHeight - 6
                radius: 9
                color: Ui.networkOpen && Ui.popupScreen === bar.screen ? Theme.surfaceHover
                     : netArea.containsMouse ? Theme.surface : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                RowLayout {
                    id: netRow
                    anchors.centerIn: parent
                    spacing: 6

                    BarText {
                        font.pixelSize: Theme.fontSize + 3
                        text: Network.primaryType === "ethernet" ? Icons.ethernet
                            : Network.primaryType === "wifi" ? Icons.wifi(Network.wifiSignal)
                            : Network.airplane ? Icons.airplane
                            : Network.wifiAvailable && !Network.wifiEnabled ? Icons.wifiOff
                            : Icons.lanOff
                        color: Network.connected ? Theme.fg : Network.airplane ? Theme.dim : Theme.red
                    }
                    BarText {
                        visible: Cntlm.active !== ""
                        font.pixelSize: Theme.fontSize + 2
                        text: Icons.proxy
                        color: Cntlm.state === "activating" ? Theme.yellow : Theme.blue
                    }
                    BarText {
                        readonly property bool btOn: (Bluetooth.defaultAdapter?.devices.values ?? []).some(d => d.connected)
                        visible: btOn
                        font.pixelSize: Theme.fontSize + 2
                        text: Icons.bluetoothConnected
                        color: Theme.blue
                    }
                    BarText {
                        id: vpnShield
                        visible: Network.activeVpn !== null || Network.vpnBusy
                        font.pixelSize: Theme.fontSize + 3
                        text: Icons.shieldLock
                        color: Network.vpnBusy ? Theme.yellow : Theme.green

                        SequentialAnimation on opacity {
                            running: Network.vpnBusy
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 450 }
                            NumberAnimation { to: 1; duration: 450 }
                            onRunningChanged: if (!running) vpnShield.opacity = 1
                        }
                    }
                }

                MouseArea {
                    id: netArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const same = Ui.popupScreen === bar.screen;
                        Ui.popupScreen = bar.screen;
                        Ui.networkOpen = !(Ui.networkOpen && same);
                    }
                }
            }

            // Volumen (clic: panel de sonido · rueda: subir/bajar · clic central: silenciar · clic derecho: pavucontrol)
            BarText {
                id: volume
                readonly property var sink: Pipewire.defaultAudioSink
                readonly property bool ready: sink !== null && sink.audio !== null
                readonly property int pct: ready ? Math.round(sink.audio.volume * 100) : 0

                PwObjectTracker { objects: volume.sink ? [volume.sink] : [] }

                visible: ready
                text: !ready ? "" : sink.audio.muted ? "  mute"
                    : (pct >= 50 ? "" : "") + "  " + pct + "%"
                color: ready && sink.audio.muted ? Theme.dim : Theme.fg

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Quickshell.execDetached(["pavucontrol"]);
                        else if (mouse.button === Qt.MiddleButton) {
                            if (volume.ready) volume.sink.audio.muted = !volume.sink.audio.muted;
                        } else
                            bar.toggleAudioPanel();
                    }
                    onWheel: wheel => {
                        if (!volume.ready) return;
                        const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                        volume.sink.audio.volume = Math.max(0, Math.min(1.5, volume.sink.audio.volume + step));
                    }
                }
            }

            // Batería (clic: panel de batería · rueda: brillo)
            BarText {
                readonly property var dev: UPower.displayDevice
                readonly property int pct: dev ? Math.round(dev.percentage * 100) : 0
                readonly property bool charging: dev !== null
                    && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
                readonly property string icon: charging ? ""
                    : pct > 85 ? "" : pct > 60 ? "" : pct > 35 ? "" : pct > 10 ? "" : ""

                visible: dev !== null && dev.isLaptopBattery
                text: icon + "  " + pct + "%"
                color: charging ? Theme.green : pct <= 15 ? Theme.red : pct <= 30 ? Theme.yellow : Theme.fg

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.toggleBatteryPanel()
                    // Rueda: brillo ±5%. Se acumula el delta para que el touchpad
                    // (muchos eventos pequeños) no salte de golpe.
                    property real wheelAcc: 0
                    onWheel: wheel => {
                        if (!Brightness.available) return;
                        wheelAcc += wheel.angleDelta.y;
                        const steps = Math.trunc(wheelAcc / 120);
                        if (steps === 0) return;
                        wheelAcc -= steps * 120;
                        Brightness.set(Brightness.value + steps * 0.05);
                    }
                }
            }
        }

        // Distribución de teclado (clic o Super+Espacio: cambiar)
        Pill {
            hoverable: true
            visible: Keyboard.current !== ""
            spacing: 6
            onClicked: Keyboard.next()
            BarText {
                text: "󰌌"
                color: Theme.accent
                font.pixelSize: Theme.fontSize + 3
            }
            BarText {
                text: Keyboard.label
                font.bold: true
            }
        }

        // Hora (clic: calendario, notificaciones y clima)
        Pill {
            hoverable: true
            active: Ui.dateOpen && Ui.popupScreen === bar.screen
            spacing: 6
            onClicked: {
                const same = Ui.popupScreen === bar.screen;
                Ui.popupScreen = bar.screen;
                Ui.dateOpen = !(Ui.dateOpen && same);
            }

            SystemClock {
                id: clock
                precision: SystemClock.Minutes
            }

            BarText {
                visible: Notifs.dnd
                text: Icons.bellOff
                color: Theme.dim
                font.pixelSize: Theme.fontSize + 1
            }
            BarText {
                text: Qt.formatDateTime(clock.date, "HH:mm")
                font.bold: true
            }
            // Punto: hay notificaciones sin ver
            Rectangle {
                visible: Notifs.count > 0 && !Notifs.dnd
                implicitWidth: 6
                implicitHeight: 6
                radius: 3
                color: Theme.accent
            }
        }

        // Apagado
        Pill {
            hoverable: true
            onClicked: { Ui.popupScreen = bar.screen; Ui.powerOpen = !Ui.powerOpen; }
            BarText {
                text: ""
                color: Theme.accent2
            }
        }
    }
}
