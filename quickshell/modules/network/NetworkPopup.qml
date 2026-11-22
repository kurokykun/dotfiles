import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import qs.config
import qs.services
import qs.widgets

// Panel de red estilo "ajustes rápidos" de GNOME.
// Páginas: principal · cableado · Wi-Fi (lista, contraseña, oculta, detalles) · VPN (lista, editar).
Scope {
    id: root

    // ───────────── Helpers ─────────────
    function deviceStateLabel(state) {
        if (state === "connected") return "Conectado";
        if (state === "disconnected") return "Desconectado";
        if (state === "unavailable") return "Cable desconectado";
        if (state === "unmanaged") return "No gestionado";
        if (state.startsWith("connecting")) return "Conectando…";
        if (state.startsWith("deactivating")) return "Desconectando…";
        return state;
    }

    function securityLabel(sec) {
        if (!sec || sec === "--") return "Abierta";
        if (sec.includes("802.1X")) return "Empresarial (802.1X)";
        if (sec.includes("WPA3") || sec.includes("SAE")) return "WPA3";
        if (sec.includes("WPA2")) return "WPA2";
        if (sec.includes("WPA")) return "WPA";
        if (sec.includes("WEP")) return "WEP";
        return sec;
    }

    function toggleWiredMain() {
        const devs = Network.wiredDevices;
        const on = devs.find(d => d.state === "connected");
        if (on) { Network.toggleWired(on); return; }
        const off = devs.find(d => d.state === "disconnected");
        if (off) Network.toggleWired(off);
        else Network.notify("Sin cable de red", "Conecta un cable Ethernet para usar la red cableada.", false);
    }

    function toggleVpnMain() {
        if (Network.activeVpn) { Network.toggleVpn(Network.activeVpn); return; }
        if (Network.vpns.length === 0) { Ui.openNetwork("vpn"); return; }
        const vpn = Network.vpns.find(v => v.uuid === Ui.lastVpn) ?? Network.vpns[0];
        Ui.lastVpn = vpn.uuid;
        Network.toggleVpn(vpn);
    }

    function clickWifi(net) {
        if (net.active) { Ui.openNetwork("wifi-details", net.ssid); return; }
        if (net.known || !net.secure) { Network.connectWifi(net.ssid, "", false); return; }
        if (net.security.includes("802.1X")) { Network.openAdvanced(); return; }
        Ui.openNetwork("wifi-password", net.ssid);
    }

    // ───── Bluetooth ─────
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property var btDevices: bt ? bt.devices.values : []
    readonly property var btPaired: btDevices.filter(d => d.paired || d.bonded)
        .sort((a, b) => (b.connected - a.connected) || (a.name || "").localeCompare(b.name || ""))
    readonly property var btAvailable: btDevices.filter(d => !d.paired && !d.bonded && (d.name || d.deviceName))
    readonly property var btConnected: btDevices.filter(d => d.connected)
    property string confirmForget: ""

    function btStateLabel(d) {
        if (d.pairing) return "Emparejando…";
        if (d.state === BluetoothDeviceState.Connecting) return "Conectando…";
        if (d.state === BluetoothDeviceState.Disconnecting) return "Desconectando…";
        if (d.connected) return "Conectado" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "% batería" : "");
        return "Desconectado";
    }

    function setBtScanning(on) {
        if (bt && bt.enabled && bt.discovering !== on) bt.discovering = on;
    }

    // ───── Proxy cntlm ─────
    function toggleProxyMain() {
        if (Cntlm.active) { Cntlm.deactivate(); return; }
        if (Cntlm.profiles.length === 0) { Ui.openNetwork("cntlm"); return; }
        const p = Cntlm.profiles.find(x => x.name === Ui.lastProxy) ?? Cntlm.profiles[0];
        Cntlm.activate(p.name);
    }

    property string cntlmAuth: "NTLMv2"
    property bool cntlmConfirmDelete: false
    property bool cntlmHasPassword: false

    function loadCntlmEdit() {
        const p = Cntlm.profiles.find(x => x.name === Ui.netArg) ?? null;
        cntlmConfirmDelete = false;
        cntlmMsg.text = "";
        cName.text = p ? p.name : "";
        cUser.text = p ? p.username : "";
        cDomain.text = p ? p.domain : "";
        cPass.clear();
        cntlmHasPassword = p ? (p.password !== "" || p.hasHash) : false;
        cProxy.text = p ? p.proxies.join(", ") : "";
        cListen.text = p ? p.listen : "3128";
        cNoProxy.text = p ? p.noProxy : "";
        cntlmAuth = p ? p.auth : "NTLMv2";
        Qt.callLater(() => (p ? cPass : cName).focusInput());
    }

    // Respuestas del servicio
    Connections {
        target: Network
        function onWifiConnectFailed(ssid, message) {
            const net = Network.wifiNetworks.find(n => n.ssid === ssid);
            if (Ui.networkOpen && (Ui.netPage === "wifi-password" || Ui.netPage === "wifi-hidden") && Ui.netArg === ssid) {
                pwError.text = message;
            } else if (net && net.secure && /Contraseña/.test(message)) {
                Ui.openNetwork("wifi-password", ssid);
                pwError.text = message;
            } else {
                Network.notify("No se pudo conectar a " + ssid, message, true);
            }
        }
        function onWifiConnected_(ssid) {
            if (Ui.netPage === "wifi-password" || Ui.netPage === "wifi-hidden") Ui.netPage = "wifi";
        }
        function onVpnImported(uuid, needsCredentials) {
            Ui.vpnJustImported = needsCredentials;
            Ui.openNetwork("vpn-edit", uuid);
        }
    }

    // Al entrar en cada página
    Connections {
        target: Ui
        function onNetPageChanged() {
            pageAnim.restart();
            pwError.text = "";
            const p = Ui.netPage;
            if (p === "wifi") Network.scanWifi();
            if (p === "wired") Network.wiredDevices.forEach(d => Network.loadDetails(d.device));
            if (p === "wifi-details" && Network.wifiDevice) Network.loadDetails(Network.wifiDevice.device);
            if (p === "wifi-password") { pwField.clear(); Qt.callLater(() => pwField.focusInput()); }
            if (p === "wifi-hidden") { hiddenSsid.clear(); hiddenPw.clear(); Qt.callLater(() => hiddenSsid.focusInput()); }
            if (p === "vpn-edit") loadVpnEdit();
            root.setBtScanning(p === "bluetooth");
            root.confirmForget = "";
            if (p === "cntlm") Cntlm.refresh();
            if (p === "cntlm-edit") loadCntlmEdit();
        }
        function onNetworkOpenChanged() {
            if (!Ui.networkOpen) root.setBtScanning(false);
            if (Ui.networkOpen) {
                Cntlm.refresh();
                Network.refresh();
                if (Network.activeWired) Network.loadDetails(Network.activeWired.device);
                else if (Network.wifiConnected) Network.loadDetails(Network.wifiDevice.device);
            }
        }
    }

    // ───── Datos de la página de edición de VPN ─────
    property var vpnInfo: null
    property bool confirmDelete: false
    property bool saving: false

    function loadVpnEdit() {
        vpnInfo = null;
        confirmDelete = false;
        vpnName.text = Network.vpns.find(v => v.uuid === Ui.netArg)?.name ?? "";
        vpnUser.clear();
        vpnPass.clear();
        Network.loadVpnInfo(Ui.netArg, info => {
            vpnInfo = info;
            vpnUser.text = info.user;
        });
    }

    // ───────────── Ventanas ─────────────

    // Capa invisible a pantalla completa: clic fuera del panel = cerrar
    PanelWindow {
        visible: Ui.networkOpen
        screen: Ui.popupScreen ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-network-backdrop"
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            onClicked: Ui.networkOpen = false
        }
    }

    PanelWindow {
        id: popup
        visible: Ui.networkOpen
        screen: Ui.popupScreen ?? Quickshell.screens[0]
        anchors { top: true; right: true }
        margins {
            top: Theme.barHeight + Theme.gap
            right: Theme.gap
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-network"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        implicitWidth: 400
        implicitHeight: card.implicitHeight
        color: "transparent"

        Rectangle {
            id: card
            anchors.fill: parent
            implicitHeight: pages.implicitHeight + 32
            radius: 22
            color: Theme.bgSolid
            border.width: 1
            border.color: Theme.border
            focus: true
            Keys.onEscapePressed: {
                if (Ui.netPage === "main") Ui.networkOpen = false;
                else Ui.netPage = Ui.netPage.startsWith("wifi-") ? "wifi" : Ui.netPage === "vpn-edit" ? "vpn" : Ui.netPage === "cntlm-edit" ? "cntlm" : "main";
            }

            ColumnLayout {
                id: pages
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 0

                // Animación al cambiar de página
                transform: Translate { id: slide }
                ParallelAnimation {
                    id: pageAnim
                    NumberAnimation { target: slide; property: "x"; from: 24; to: 0; duration: Theme.animNormal; easing.type: Easing.OutCubic }
                    NumberAnimation { target: pages; property: "opacity"; from: 0; to: 1; duration: Theme.animNormal }
                }

                // ═════════════ PRINCIPAL ═════════════
                ColumnLayout {
                    visible: Ui.netPage === "main"
                    Layout.fillWidth: true
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            BarText { text: "Red"; font.bold: true; font.pixelSize: Theme.fontSize + 3 }
                            BarText {
                                text: Network.airplane ? "Modo avión activado"
                                    : !Network.connected ? "Sin conexión"
                                    : Network.activeVpn ? "Conectado · VPN activa" : "Conectado"
                                color: Network.connected ? Theme.dim : Theme.red
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }
                        ActionButton { kind: "icon"; icon: Icons.close; onClicked: Ui.networkOpen = false }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 10

                        QuickTile {
                            visible: Network.wiredDevices.length > 0
                            icon: Network.activeWired ? Icons.ethernet : Icons.lanOff
                            title: "Cableado"
                            subtitle: Network.activeWired ? Network.activeWired.connection
                                : Network.wiredDevices.some(d => d.state === "disconnected") ? "Desconectado" : "Sin cable"
                            checked: Network.activeWired !== null
                            busy: Network.wiredDevices.some(d => Network.isBusy(d.device))
                            onToggled: root.toggleWiredMain()
                            onOpened: Ui.openNetwork("wired")
                        }

                        QuickTile {
                            visible: Network.wifiAvailable
                            icon: !Network.wifiEnabled ? Icons.wifiOff : Icons.wifi(Network.wifiSignal)
                            title: "Wi-Fi"
                            subtitle: !Network.wifiEnabled ? "Apagado"
                                : Network.wifiConnected ? Network.wifiDevice.connection : "Sin conectar"
                            checked: Network.wifiEnabled
                            onToggled: Network.setWifiEnabled(!Network.wifiEnabled)
                            onOpened: Ui.openNetwork("wifi")
                        }

                        QuickTile {
                            icon: Network.activeVpn ? Icons.shieldLock : Icons.shield
                            title: "VPN"
                            subtitle: Network.vpnBusy ? "Cambiando…"
                                : Network.activeVpn ? Network.activeVpn.name
                                : Network.vpns.length ? "Desactivada" : "Sin configurar"
                            checked: Network.activeVpn !== null
                            busy: Network.vpnBusy
                            onToggled: root.toggleVpnMain()
                            onOpened: Ui.openNetwork("vpn")
                        }

                        QuickTile {
                            visible: root.bt !== null
                            icon: !(root.bt?.enabled ?? false) ? Icons.bluetoothOff
                                : root.btConnected.length ? Icons.bluetoothConnected : Icons.bluetooth
                            title: "Bluetooth"
                            subtitle: !(root.bt?.enabled ?? false) ? "Apagado"
                                : root.btConnected.length === 1 ? root.btConnected[0].name
                                : root.btConnected.length > 1 ? root.btConnected.length + " dispositivos"
                                : "Activado"
                            checked: root.bt?.enabled ?? false
                            onToggled: if (root.bt) root.bt.enabled = !root.bt.enabled
                            onOpened: Ui.openNetwork("bluetooth")
                        }

                        QuickTile {
                            icon: Icons.proxy
                            title: "Proxy"
                            subtitle: Cntlm.busy ? "Cambiando…"
                                : Cntlm.active ? Cntlm.active
                                : Cntlm.state === "failed" ? "Error al arrancar"
                                : Cntlm.profiles.length ? "Desactivado" : "Sin perfiles"
                            checked: Cntlm.active !== ""
                            busy: Cntlm.busy
                            onToggled: root.toggleProxyMain()
                            onOpened: Ui.openNetwork("cntlm")
                        }

                        QuickTile {
                            icon: Network.airplane ? Icons.airplane : Icons.airplaneOff
                            title: "Modo avión"
                            subtitle: Network.airplane ? "Activado" : "Desactivado"
                            checked: Network.airplane
                            hasMenu: false
                            onToggled: Network.setAirplane(!Network.airplane)
                        }
                    }

                    // Resumen de la conexión actual
                    Rectangle {
                        id: summaryCard
                        visible: Network.connected
                        Layout.fillWidth: true
                        implicitHeight: summary.implicitHeight + 24
                        radius: 14
                        color: Theme.surface

                        readonly property string dev: Network.activeWired ? Network.activeWired.device
                            : Network.wifiConnected ? Network.wifiDevice.device : ""
                        readonly property var info: Network.details[dev] ?? null

                        ColumnLayout {
                            id: summary
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                BarText {
                                    text: Network.primaryType === "ethernet" ? Icons.ethernet : Icons.wifi(Network.wifiSignal)
                                    color: Theme.accent
                                    font.pixelSize: 16
                                }
                                BarText {
                                    Layout.fillWidth: true
                                    text: Network.primaryName
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                BarText {
                                    text: "Detalles " + Icons.chevronRight
                                    color: detailsArea.containsMouse ? Theme.accent : Theme.dim
                                    font.pixelSize: Theme.fontSize - 2
                                    MouseArea {
                                        id: detailsArea
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Network.primaryType === "ethernet" ? Ui.openNetwork("wired")
                                            : Ui.openNetwork("wifi-details", Network.wifiDevice.connection)
                                    }
                                }
                            }
                            InfoLine { label: "IP"; value: summaryCard.info?.ip4.join(", ") ?? "" }
                            InfoLine { label: "Puerta de enlace"; value: summaryCard.info?.gateway ?? "" }
                            InfoLine { label: "VPN"; value: Network.activeVpn ? Network.activeVpn.name : "" }
                            InfoLine { label: "Proxy"; value: Cntlm.activeProfile ? Cntlm.active + " · " + Cntlm.localUrl(Cntlm.activeProfile).replace("http://", "") : "" }
                        }
                    }

                    ActionButton {
                        Layout.fillWidth: true
                        icon: Icons.cog
                        text: "Configuración avanzada de red"
                        onClicked: { Ui.networkOpen = false; Network.openAdvanced(); }
                    }
                }

                // ═════════════ CABLEADO ═════════════
                ColumnLayout {
                    visible: Ui.netPage === "wired"
                    Layout.fillWidth: true
                    spacing: 12

                    PageHeader { title: "Cableado"; subtitle: Network.activeWired ? "Conectado" : "Desconectado" }

                    Repeater {
                        model: Network.wiredDevices
                        delegate: Rectangle {
                            id: wiredCard
                            required property var modelData
                            readonly property var info: Network.details[modelData.device] ?? null
                            readonly property bool on: modelData.state === "connected"

                            Layout.fillWidth: true
                            implicitHeight: wiredCol.implicitHeight + 24
                            radius: 14
                            color: Theme.surface

                            ColumnLayout {
                                id: wiredCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    BarText {
                                        text: wiredCard.on ? Icons.ethernet : Icons.lanOff
                                        color: wiredCard.on ? Theme.accent : Theme.dim
                                        font.pixelSize: 20
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        BarText {
                                            Layout.fillWidth: true
                                            text: wiredCard.modelData.connection || ("Ethernet (" + wiredCard.modelData.device + ")")
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        BarText {
                                            text: wiredCard.modelData.device + " · " + root.deviceStateLabel(wiredCard.modelData.state)
                                            color: Theme.dim
                                            font.pixelSize: Theme.fontSize - 2
                                        }
                                    }
                                    Toggle {
                                        checked: wiredCard.on
                                        busy: Network.isBusy(wiredCard.modelData.device)
                                        enabled: wiredCard.modelData.state !== "unavailable"
                                        opacity: enabled ? 1 : 0.4
                                        onToggled: Network.toggleWired(wiredCard.modelData)
                                    }
                                }

                                ColumnLayout {
                                    visible: wiredCard.on && wiredCard.info !== null
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    spacing: 3
                                    InfoLine { label: "Velocidad"; value: wiredCard.info?.speed ?? "" }
                                    InfoLine { label: "IPv4"; value: wiredCard.info?.ip4.join(", ") ?? "" }
                                    InfoLine { label: "IPv6"; value: wiredCard.info?.ip6[0] ?? "" }
                                    InfoLine { label: "Puerta de enlace"; value: wiredCard.info?.gateway ?? "" }
                                    InfoLine { label: "DNS"; value: wiredCard.info?.dns.join(", ") ?? "" }
                                    InfoLine { label: "MAC"; value: wiredCard.info?.mac ?? "" }
                                }

                                RowLayout {
                                    visible: wiredCard.modelData.connection !== ""
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    readonly property var conn: Network.connections.find(c => c.name === wiredCard.modelData.connection) ?? null
                                    BarText { text: "Conectar automáticamente"; color: Theme.dim; font.pixelSize: Theme.fontSize - 1 }
                                    Item { Layout.fillWidth: true }
                                    Toggle {
                                        checked: parent.conn?.autoconnect ?? false
                                        onToggled: if (parent.conn) Network.setAutoconnect(parent.conn.uuid, !parent.conn.autoconnect)
                                    }
                                }
                            }
                        }
                    }
                }

                // ═════════════ WI-FI: LISTA ═════════════
                ColumnLayout {
                    visible: Ui.netPage === "wifi"
                    Layout.fillWidth: true
                    spacing: 10

                    PageHeader {
                        title: "Wi-Fi"
                        subtitle: !Network.wifiEnabled ? "Apagado"
                            : Network.wifiConnected ? "Conectado a " + Network.wifiDevice.connection : "Sin conectar"
                        ActionButton {
                            kind: "icon"
                            icon: Icons.refresh
                            busy: Network.scanning
                            visible: Network.wifiEnabled
                            onClicked: Network.scanWifi()
                        }
                        Toggle {
                            checked: Network.wifiEnabled
                            onToggled: Network.setWifiEnabled(!Network.wifiEnabled)
                        }
                    }

                    // Apagado
                    ColumnLayout {
                        visible: !Network.wifiEnabled
                        Layout.fillWidth: true
                        Layout.topMargin: 16
                        Layout.bottomMargin: 8
                        spacing: 10
                        BarText { Layout.alignment: Qt.AlignHCenter; text: Icons.wifiOff; font.pixelSize: 40; color: Theme.dim }
                        BarText { Layout.alignment: Qt.AlignHCenter; text: "El Wi-Fi está apagado"; color: Theme.dim }
                        ActionButton {
                            Layout.alignment: Qt.AlignHCenter
                            kind: "primary"
                            text: "Encender Wi-Fi"
                            onClicked: Network.setWifiEnabled(true)
                        }
                    }

                    // Buscando
                    BarText {
                        visible: Network.wifiEnabled && Network.wifiNetworks.length === 0
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 12
                        Layout.bottomMargin: 12
                        text: Network.scanning ? "Buscando redes…" : "No se encontraron redes"
                        color: Theme.dim
                    }

                    Flickable {
                        visible: Network.wifiEnabled && Network.wifiNetworks.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 330)
                        contentHeight: wifiList.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: wifiList
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: Network.wifiNetworks
                                delegate: ListRow {
                                    id: wifiRow
                                    required property var modelData
                                    readonly property bool connecting: Network.isBusy(modelData.ssid)

                                    icon: Icons.wifi(modelData.signal)
                                    iconColor: modelData.active ? Theme.accent : Theme.fg
                                    title: modelData.ssid
                                    subtitle: connecting ? "Conectando…"
                                        : modelData.active ? "Conectada"
                                        : modelData.known ? "Guardada"
                                        : root.securityLabel(modelData.security)
                                    highlighted: modelData.active
                                    busy: connecting
                                    onClicked: root.clickWifi(modelData)

                                    BarText {
                                        visible: wifiRow.modelData.secure
                                        text: Icons.lock
                                        color: Theme.dim
                                        font.pixelSize: 14
                                    }
                                    ActionButton {
                                        visible: wifiRow.modelData.known || wifiRow.modelData.active
                                        kind: "icon"
                                        icon: Icons.cog
                                        onClicked: Ui.openNetwork("wifi-details", wifiRow.modelData.ssid)
                                    }
                                }
                            }
                        }
                    }

                    ActionButton {
                        visible: Network.wifiEnabled
                        Layout.fillWidth: true
                        icon: Icons.plus
                        text: "Conectar a una red oculta"
                        onClicked: Ui.openNetwork("wifi-hidden")
                    }
                }

                // ═════════════ WI-FI: CONTRASEÑA ═════════════
                ColumnLayout {
                    visible: Ui.netPage === "wifi-password"
                    Layout.fillWidth: true
                    spacing: 12

                    readonly property var net: Network.wifiNetworks.find(n => n.ssid === Ui.netArg) ?? null

                    PageHeader { title: Ui.netArg; subtitle: "Se necesita contraseña · " + root.securityLabel(parent.net?.security ?? "") }

                    FormField {
                        id: pwField
                        label: "Contraseña"
                        placeholder: "Introduce la contraseña de la red"
                        password: true
                        onAccepted: if (text.length) Network.connectWifi(Ui.netArg, text, false)
                    }

                    BarText {
                        id: pwError
                        visible: text !== ""
                        Layout.fillWidth: true
                        color: Theme.red
                        font.pixelSize: Theme.fontSize - 1
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        ActionButton { Layout.fillWidth: true; text: "Cancelar"; onClicked: Ui.netPage = "wifi" }
                        ActionButton {
                            Layout.fillWidth: true
                            kind: "primary"
                            text: Network.isBusy(Ui.netArg) ? "Conectando…" : "Conectar"
                            enabled: pwField.text.length >= 8 && !Network.isBusy(Ui.netArg)
                            onClicked: { pwError.text = ""; Network.connectWifi(Ui.netArg, pwField.text, false); }
                        }
                    }
                }

                // ═════════════ WI-FI: RED OCULTA ═════════════
                ColumnLayout {
                    visible: Ui.netPage === "wifi-hidden"
                    Layout.fillWidth: true
                    spacing: 12

                    PageHeader { title: "Red oculta"; subtitle: "Conectar a una red que no anuncia su nombre" }

                    FormField { id: hiddenSsid; label: "Nombre de la red (SSID)"; placeholder: "MiRed" }
                    FormField {
                        id: hiddenPw
                        label: "Contraseña (vacío si es abierta)"
                        password: true
                        onAccepted: if (hiddenSsid.text) { Ui.netArg = hiddenSsid.text; Network.connectWifi(hiddenSsid.text, text, true); }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        ActionButton { Layout.fillWidth: true; text: "Cancelar"; onClicked: Ui.netPage = "wifi" }
                        ActionButton {
                            Layout.fillWidth: true
                            kind: "primary"
                            text: Network.isBusy(hiddenSsid.text) ? "Conectando…" : "Conectar"
                            enabled: hiddenSsid.text.length > 0 && (hiddenPw.text.length === 0 || hiddenPw.text.length >= 8)
                            onClicked: { Ui.netArg = hiddenSsid.text; Network.connectWifi(hiddenSsid.text, hiddenPw.text, true); }
                        }
                    }
                }

                // ═════════════ WI-FI: DETALLES ═════════════
                ColumnLayout {
                    id: wifiDetails
                    visible: Ui.netPage === "wifi-details"
                    Layout.fillWidth: true
                    spacing: 12

                    readonly property var net: Network.wifiNetworks.find(n => n.ssid === Ui.netArg) ?? null
                    readonly property var conn: Network.connections.find(c => c.type === "802-11-wireless" && c.name === Ui.netArg) ?? null
                    readonly property bool active: net?.active ?? false
                    readonly property var info: active && Network.wifiDevice ? (Network.details[Network.wifiDevice.device] ?? null) : null

                    PageHeader {
                        title: Ui.netArg
                        subtitle: wifiDetails.active ? "Conectada" : wifiDetails.conn ? "Guardada" : "Fuera de alcance"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: detCol.implicitHeight + 24
                        radius: 14
                        color: Theme.surface
                        ColumnLayout {
                            id: detCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 3
                            InfoLine { label: "Señal"; value: wifiDetails.net ? wifiDetails.net.signal + " %" : "" }
                            InfoLine { label: "Seguridad"; value: wifiDetails.net ? root.securityLabel(wifiDetails.net.security) : "" }
                            InfoLine { label: "IPv4"; value: wifiDetails.info?.ip4.join(", ") ?? "" }
                            InfoLine { label: "IPv6"; value: wifiDetails.info?.ip6[0] ?? "" }
                            InfoLine { label: "Puerta de enlace"; value: wifiDetails.info?.gateway ?? "" }
                            InfoLine { label: "DNS"; value: wifiDetails.info?.dns.join(", ") ?? "" }
                            InfoLine { label: "MAC"; value: wifiDetails.info?.mac ?? "" }
                            RowLayout {
                                visible: wifiDetails.conn !== null
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                BarText { text: "Conectar automáticamente"; color: Theme.dim; font.pixelSize: Theme.fontSize - 1 }
                                Item { Layout.fillWidth: true }
                                Toggle {
                                    checked: wifiDetails.conn?.autoconnect ?? false
                                    onToggled: Network.setAutoconnect(wifiDetails.conn.uuid, !wifiDetails.conn.autoconnect)
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        ActionButton {
                            Layout.fillWidth: true
                            visible: wifiDetails.active
                            text: "Desconectar"
                            onClicked: Network.disconnectWifi()
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            visible: !wifiDetails.active && wifiDetails.net !== null
                            kind: "primary"
                            text: "Conectar"
                            onClicked: { Network.connectWifi(Ui.netArg, "", false); Ui.netPage = "wifi"; }
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            visible: wifiDetails.conn !== null
                            kind: "danger"
                            icon: Icons.trash
                            text: "Olvidar red"
                            onClicked: { Network.forgetWifi(wifiDetails.conn.uuid); Ui.netPage = "wifi"; }
                        }
                    }
                }

                // ═════════════ VPN: LISTA ═════════════
                ColumnLayout {
                    visible: Ui.netPage === "vpn"
                    Layout.fillWidth: true
                    spacing: 10

                    PageHeader {
                        title: "VPN"
                        subtitle: Network.activeVpn ? "Protegido · " + Network.activeVpn.name : "Desactivada"
                    }

                    ColumnLayout {
                        visible: Network.vpns.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.bottomMargin: 6
                        spacing: 8
                        BarText { Layout.alignment: Qt.AlignHCenter; text: Icons.shield; font.pixelSize: 40; color: Theme.dim }
                        BarText { Layout.alignment: Qt.AlignHCenter; text: "No hay VPNs configuradas"; color: Theme.dim }
                    }

                    Repeater {
                        model: Network.vpns
                        delegate: ListRow {
                            id: vpnRow
                            required property var modelData
                            readonly property bool busy_: Network.isBusy(modelData.uuid)

                            icon: modelData.active ? Icons.shieldLock : Icons.shield
                            iconColor: modelData.active ? Theme.green : Theme.fg
                            title: modelData.name
                            subtitle: (modelData.type === "wireguard" ? "WireGuard" : "OpenVPN")
                                + (busy_ ? " · cambiando…" : modelData.active ? " · conectada" : "")
                            highlighted: modelData.active
                            busy: busy_
                            onClicked: Ui.openNetwork("vpn-edit", modelData.uuid)

                            ActionButton {
                                kind: "icon"
                                icon: Icons.cog
                                onClicked: Ui.openNetwork("vpn-edit", vpnRow.modelData.uuid)
                            }
                            Toggle {
                                checked: vpnRow.modelData.active
                                busy: vpnRow.busy_
                                onToggled: { Ui.lastVpn = vpnRow.modelData.uuid; Network.toggleVpn(vpnRow.modelData); }
                            }
                        }
                    }

                    BarText {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        text: "Agregar VPN"
                        color: Theme.dim
                        font.pixelSize: Theme.fontSize - 2
                    }

                    ListRow {
                        icon: Icons.fileImport
                        iconColor: Theme.accent
                        title: "Importar desde archivo…"
                        subtitle: "OpenVPN (.ovpn) o WireGuard (.conf)"
                        onClicked: { Ui.networkOpen = false; Network.importVpn(); }
                        BarText { text: Icons.chevronRight; color: Theme.dim; font.pixelSize: 16 }
                    }
                    ListRow {
                        icon: Icons.pencil
                        iconColor: Theme.accent
                        title: "Configurar manualmente…"
                        subtitle: "OpenVPN, WireGuard, IPsec, OpenConnect…"
                        onClicked: { Ui.networkOpen = false; Network.openAdvanced(); }
                        BarText { text: Icons.chevronRight; color: Theme.dim; font.pixelSize: 16 }
                    }
                }

                // ═════════════ BLUETOOTH ═════════════
                ColumnLayout {
                    visible: Ui.netPage === "bluetooth"
                    Layout.fillWidth: true
                    spacing: 10

                    PageHeader {
                        title: "Bluetooth"
                        subtitle: !root.bt ? "Sin adaptador"
                            : !root.bt.enabled ? "Apagado"
                            : root.bt.discovering ? "Buscando dispositivos…" : "Activado"
                        ActionButton {
                            kind: "icon"
                            icon: Icons.refresh
                            visible: root.bt?.enabled ?? false
                            busy: root.bt?.discovering ?? false
                            onClicked: root.setBtScanning(!(root.bt?.discovering ?? false))
                        }
                        Toggle {
                            visible: root.bt !== null
                            checked: root.bt?.enabled ?? false
                            onToggled: {
                                root.bt.enabled = !root.bt.enabled;
                                if (root.bt.enabled) Qt.callLater(() => root.setBtScanning(true));
                            }
                        }
                    }

                    // Apagado
                    ColumnLayout {
                        visible: !(root.bt?.enabled ?? false)
                        Layout.fillWidth: true
                        Layout.topMargin: 14
                        Layout.bottomMargin: 8
                        spacing: 10
                        BarText { Layout.alignment: Qt.AlignHCenter; text: Icons.bluetoothOff; font.pixelSize: 40; color: Theme.dim }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.bt ? "El Bluetooth está apagado" : "No se encontró ningún adaptador Bluetooth"
                            color: Theme.dim
                        }
                        ActionButton {
                            visible: root.bt !== null
                            Layout.alignment: Qt.AlignHCenter
                            kind: "primary"
                            text: "Encender Bluetooth"
                            onClicked: { root.bt.enabled = true; Qt.callLater(() => root.setBtScanning(true)); }
                        }
                    }

                    Flickable {
                        visible: root.bt?.enabled ?? false
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 360)
                        contentHeight: btList.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: btList
                            width: parent.width
                            spacing: 2

                            BarText {
                                visible: root.btPaired.length > 0
                                text: "Mis dispositivos"
                                color: Theme.dim
                                font.pixelSize: Theme.fontSize - 2
                                Layout.bottomMargin: 2
                            }

                            Repeater {
                                model: root.btPaired
                                delegate: ListRow {
                                    id: btRow
                                    required property var modelData
                                    readonly property bool working: modelData.pairing
                                        || modelData.state === BluetoothDeviceState.Connecting
                                        || modelData.state === BluetoothDeviceState.Disconnecting

                                    icon: Icons.btDevice(modelData.icon)
                                    iconColor: modelData.connected ? Theme.accent : Theme.fg
                                    title: modelData.name || modelData.address
                                    subtitle: root.confirmForget === modelData.address ? "Pulsa otra vez la papelera para olvidarlo"
                                        : root.btStateLabel(modelData)
                                    highlighted: modelData.connected
                                    busy: working
                                    onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()

                                    ActionButton {
                                        kind: "icon"
                                        icon: Icons.trash
                                        onClicked: {
                                            if (root.confirmForget === btRow.modelData.address) {
                                                root.confirmForget = "";
                                                btRow.modelData.forget();
                                            } else {
                                                root.confirmForget = btRow.modelData.address;
                                            }
                                        }
                                    }
                                    Toggle {
                                        checked: btRow.modelData.connected
                                        busy: btRow.working
                                        onToggled: btRow.modelData.connected ? btRow.modelData.disconnect() : btRow.modelData.connect()
                                    }
                                }
                            }

                            BarText {
                                text: "Dispositivos disponibles"
                                color: Theme.dim
                                font.pixelSize: Theme.fontSize - 2
                                Layout.topMargin: root.btPaired.length > 0 ? 8 : 0
                                Layout.bottomMargin: 2
                            }

                            BarText {
                                visible: root.btAvailable.length === 0
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 6
                                Layout.bottomMargin: 6
                                text: (root.bt?.discovering ?? false) ? "Buscando…" : "Pulsa ↻ para buscar dispositivos"
                                color: Theme.dim
                                font.pixelSize: Theme.fontSize - 1
                            }

                            Repeater {
                                model: root.btAvailable
                                delegate: ListRow {
                                    id: newRow
                                    required property var modelData
                                    icon: Icons.btDevice(modelData.icon)
                                    title: modelData.name || modelData.deviceName
                                    subtitle: modelData.pairing ? "Emparejando…" : "Pulsa para emparejar"
                                    busy: modelData.pairing
                                    onClicked: {
                                        if (modelData.pairing) { modelData.cancelPair(); return; }
                                        // Parar el escaneo antes: con discovery activo el
                                        // controlador Intel falla/se cuelga al emparejar
                                        root.setBtScanning(false);
                                        modelData.trusted = true;
                                        modelData.pair();
                                    }
                                    // Al terminar de emparejar, conectar
                                    Connections {
                                        target: newRow.modelData
                                        function onPairedChanged() { if (newRow.modelData.paired) newRow.modelData.connect(); }
                                    }
                                    BarText { text: Icons.plus; color: Theme.dim; font.pixelSize: 16 }
                                }
                            }
                        }
                    }
                }

                // ═════════════ PROXY (CNTLM): PERFILES ═════════════
                ColumnLayout {
                    visible: Ui.netPage === "cntlm"
                    Layout.fillWidth: true
                    spacing: 10

                    PageHeader {
                        title: "Proxy (cntlm)"
                        subtitle: Cntlm.busy ? "Cambiando…"
                            : Cntlm.active ? "Activo · " + Cntlm.active
                            : "Desactivado"
                        Toggle {
                            checked: Cntlm.active !== ""
                            busy: Cntlm.busy
                            enabled: Cntlm.profiles.length > 0
                            onToggled: root.toggleProxyMain()
                        }
                    }

                    // Estado del perfil activo + prueba
                    Rectangle {
                        visible: Cntlm.activeProfile !== null
                        Layout.fillWidth: true
                        implicitHeight: proxyInfo.implicitHeight + 24
                        radius: 14
                        color: Theme.surface
                        ColumnLayout {
                            id: proxyInfo
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 4
                            InfoLine { label: "Proxy local"; value: Cntlm.localUrl(Cntlm.activeProfile) }
                            InfoLine { label: "Proxy superior"; value: Cntlm.activeProfile?.proxies.join(", ") ?? "" }
                            InfoLine { label: "Usuario"; value: Cntlm.activeProfile ? Cntlm.activeProfile.username + (Cntlm.activeProfile.domain ? " @ " + Cntlm.activeProfile.domain : "") : "" }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                spacing: 10
                                ActionButton {
                                    icon: Icons.flask
                                    text: Cntlm.testing ? "Probando…" : "Probar conexión"
                                    enabled: !Cntlm.testing
                                    onClicked: Cntlm.test()
                                }
                                BarText {
                                    Layout.fillWidth: true
                                    visible: Cntlm.testResult !== ""
                                    text: Cntlm.testResult.slice(Cntlm.testResult.indexOf(":") + 1)
                                    color: Cntlm.testResult.startsWith("ok") ? Theme.green : Theme.red
                                    font.pixelSize: Theme.fontSize - 1
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }

                    BarText {
                        visible: Cntlm.error !== ""
                        Layout.fillWidth: true
                        text: Cntlm.error
                        color: Theme.red
                        font.pixelSize: Theme.fontSize - 1
                        wrapMode: Text.Wrap
                    }

                    BarText {
                        text: "Perfiles"
                        color: Theme.dim
                        font.pixelSize: Theme.fontSize - 2
                        Layout.topMargin: 2
                    }

                    BarText {
                        visible: Cntlm.profiles.length === 0
                        Layout.fillWidth: true
                        text: "No hay perfiles en ~/.config/cntlm"
                        color: Theme.dim
                        font.pixelSize: Theme.fontSize - 1
                    }

                    Repeater {
                        model: Cntlm.profiles
                        delegate: ListRow {
                            id: profRow
                            required property var modelData
                            readonly property bool isActive: Cntlm.active === modelData.name
                            readonly property bool isFailed: Cntlm.failed === modelData.name && !isActive

                            icon: isActive ? Icons.radioOn : Icons.radioOff
                            iconColor: isActive ? Theme.accent : isFailed ? Theme.red : Theme.dim
                            title: modelData.name
                            subtitle: isFailed ? "No pudo arrancar — revisa los datos"
                                : (modelData.username ? modelData.username + (modelData.domain ? "@" + modelData.domain : "") + "  →  " : "")
                                  + (modelData.proxies[0] ?? "sin proxy")
                            highlighted: isActive
                            busy: Cntlm.busy && Ui.lastProxy === modelData.name
                            // Clic: activar este perfil (si ya es el activo, desactivar)
                            onClicked: isActive ? Cntlm.deactivate() : Cntlm.activate(modelData.name)

                            ActionButton {
                                kind: "icon"
                                icon: Icons.cog
                                onClicked: Ui.openNetwork("cntlm-edit", profRow.modelData.name)
                            }
                        }
                    }

                    ListRow {
                        icon: Icons.plus
                        iconColor: Theme.accent
                        title: "Agregar perfil…"
                        onClicked: Ui.openNetwork("cntlm-edit", "")
                        BarText { text: Icons.chevronRight; color: Theme.dim; font.pixelSize: 16 }
                    }
                }

                // ═════════════ PROXY (CNTLM): EDITAR / NUEVO ═════════════
                ColumnLayout {
                    visible: Ui.netPage === "cntlm-edit"
                    Layout.fillWidth: true
                    spacing: 10

                    readonly property bool isNew: Ui.netArg === ""

                    PageHeader {
                        title: parent.isNew ? "Nuevo perfil" : Ui.netArg
                        subtitle: parent.isNew ? "Se guardará en ~/.config/cntlm" : "~/.config/cntlm/" + Ui.netArg + ".conf"
                    }

                    FormField { id: cName; label: "Nombre del perfil"; placeholder: "trabajo" }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        FormField { id: cUser; label: "Usuario"; placeholder: "usuario" }
                        FormField { id: cDomain; label: "Dominio"; placeholder: "empresa.cu" }
                    }
                    FormField {
                        id: cPass
                        label: "Contraseña"
                        password: true
                        placeholder: root.cntlmHasPassword ? "•••••••• guardada" : "Contraseña"
                    }
                    FormField { id: cProxy; label: "Proxy superior (host:puerto, varios separados por coma)"; placeholder: "10.0.0.1:8080" }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        FormField { id: cListen; label: "Escuchar en"; placeholder: "3128" }
                        FormField { id: cNoProxy; label: "Sin proxy para (opcional)"; placeholder: "localhost, 127.0.0.*, 10.*" }
                    }

                    // Autenticación
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        BarText { text: "Autenticación"; color: Theme.dim; font.pixelSize: Theme.fontSize - 2 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: ["NTLMv2", "NTLM", "LM", "NT"]
                                delegate: Rectangle {
                                    id: authBtn
                                    required property string modelData
                                    readonly property bool on: root.cntlmAuth.toUpperCase() === modelData.toUpperCase()
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 10
                                    color: on ? Theme.accent : authArea.containsMouse ? Theme.surfaceHover : Theme.surface
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                    BarText {
                                        anchors.centerIn: parent
                                        text: authBtn.modelData
                                        color: authBtn.on ? Theme.textOnAccent : Theme.fg
                                        font.bold: authBtn.on
                                        font.pixelSize: Theme.fontSize - 1
                                    }
                                    MouseArea {
                                        id: authArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.cntlmAuth = authBtn.modelData
                                    }
                                }
                            }
                        }
                    }

                    BarText {
                        id: cntlmMsg
                        visible: text !== ""
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Theme.red
                        font.pixelSize: Theme.fontSize - 1
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        ActionButton {
                            visible: Ui.netArg !== ""
                            Layout.fillWidth: true
                            kind: "danger"
                            icon: Icons.trash
                            text: root.cntlmConfirmDelete ? "¿Seguro? Pulsa otra vez" : "Eliminar"
                            onClicked: {
                                if (!root.cntlmConfirmDelete) { root.cntlmConfirmDelete = true; return; }
                                Cntlm.remove(Ui.netArg, (ok, err) => {
                                    if (ok) Ui.netPage = "cntlm"; else cntlmMsg.text = err;
                                });
                            }
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            kind: "primary"
                            icon: Icons.check
                            text: Cntlm.busy ? "Guardando…" : "Guardar"
                            enabled: !Cntlm.busy && cName.text.length > 0 && cProxy.text.length > 0 && cUser.text.length > 0
                                     && (root.cntlmHasPassword || cPass.text.length > 0)
                            onClicked: {
                                cntlmMsg.text = "";
                                Cntlm.save(Ui.netArg, {
                                    name: cName.text.trim(),
                                    username: cUser.text.trim(),
                                    domain: cDomain.text.trim(),
                                    auth: root.cntlmAuth,
                                    password: cPass.text,
                                    proxies: cProxy.text.split(/[,\s]+/).filter(x => x),
                                    listen: cListen.text.trim() || "3128",
                                    noProxy: cNoProxy.text.trim()
                                }, (ok, err) => {
                                    if (ok) Ui.netPage = "cntlm"; else cntlmMsg.text = err;
                                });
                            }
                        }
                    }
                }

                // ═════════════ VPN: EDITAR ═════════════
                ColumnLayout {
                    id: vpnEdit
                    visible: Ui.netPage === "vpn-edit"
                    Layout.fillWidth: true
                    spacing: 12

                    readonly property var vpn: Network.vpns.find(v => v.uuid === Ui.netArg) ?? null

                    PageHeader {
                        title: vpnEdit.vpn?.name ?? "VPN"
                        subtitle: !root.vpnInfo ? "Cargando…"
                            : (root.vpnInfo.type === "wireguard" ? "WireGuard" : "OpenVPN")
                              + (vpnEdit.vpn?.active ? " · conectada" : "")
                    }

                    // Aviso tras importar
                    Rectangle {
                        visible: Ui.vpnJustImported
                        Layout.fillWidth: true
                        implicitHeight: notice.implicitHeight + 20
                        radius: 12
                        color: Qt.alpha(Theme.accent, 0.14)
                        border.width: 1
                        border.color: Qt.alpha(Theme.accent, 0.4)
                        BarText {
                            id: notice
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                            wrapMode: Text.Wrap
                            font.pixelSize: Theme.fontSize - 1
                            text: "VPN importada. Introduce el usuario y la contraseña de tu proveedor "
                                + "(en ProtonVPN son las credenciales OpenVPN de tu cuenta, no tu email)."
                        }
                    }

                    FormField { id: vpnName; label: "Nombre"; placeholder: "Mi VPN" }

                    FormField {
                        id: vpnUser
                        visible: root.vpnInfo?.needsCredentials ?? false
                        label: "Usuario"
                        placeholder: "usuario"
                    }

                    FormField {
                        id: vpnPass
                        visible: root.vpnInfo?.needsCredentials ?? false
                        label: "Contraseña"
                        placeholder: root.vpnInfo?.hasPassword ? "•••••••• guardada" : "Contraseña"
                        password: true
                    }

                    BarText {
                        id: vpnMsg
                        visible: text !== ""
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.green
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        ActionButton {
                            Layout.fillWidth: true
                            kind: "danger"
                            icon: Icons.trash
                            text: root.confirmDelete ? "¿Seguro? Pulsa otra vez" : "Eliminar"
                            onClicked: {
                                if (!root.confirmDelete) { root.confirmDelete = true; return; }
                                Network.deleteVpn(Ui.netArg, (ok, err) => {
                                    if (ok) Ui.netPage = "vpn";
                                    else { vpnMsg.color = Theme.red; vpnMsg.text = err; }
                                });
                            }
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            kind: "primary"
                            icon: Icons.check
                            text: root.saving ? "Guardando…" : "Guardar"
                            enabled: root.vpnInfo !== null && !root.saving && vpnName.text.length > 0
                            onClicked: {
                                root.saving = true;
                                const creds = root.vpnInfo.needsCredentials;
                                Network.saveVpn(Ui.netArg, vpnName.text, creds ? vpnUser.text : null,
                                                creds ? vpnPass.text : "", (ok, err) => {
                                    root.saving = false;
                                    vpnMsg.color = ok ? Theme.green : Theme.red;
                                    vpnMsg.text = ok ? "Cambios guardados" : err;
                                    if (ok) { Ui.vpnJustImported = false; vpnPass.clear(); root.loadVpnEdit(); }
                                });
                            }
                        }
                    }

                    ActionButton {
                        Layout.fillWidth: true
                        visible: vpnEdit.vpn !== null
                        icon: vpnEdit.vpn?.active ? Icons.shieldOff : Icons.shieldLock
                        text: Network.isBusy(Ui.netArg) ? "Cambiando…" : vpnEdit.vpn?.active ? "Desconectar" : "Conectar"
                        enabled: !Network.isBusy(Ui.netArg)
                        onClicked: { Ui.lastVpn = Ui.netArg; Network.toggleVpn(vpnEdit.vpn); }
                    }

                    ActionButton {
                        Layout.fillWidth: true
                        icon: Icons.cog
                        text: "Opciones avanzadas…"
                        onClicked: { Ui.networkOpen = false; Network.openAdvanced(); }
                    }
                }
            }
        }
    }

    // ───────────── Componentes internos ─────────────

    // Encabezado de subpágina con botón atrás y controles opcionales a la derecha
    component PageHeader: RowLayout {
        id: header
        property string title: ""
        property string subtitle: ""
        default property alias extra: extraRow.data
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        spacing: 8

        ActionButton {
            kind: "icon"
            icon: Icons.chevronLeft
            onClicked: Ui.netPage = Ui.netPage.startsWith("wifi-") ? "wifi" : Ui.netPage === "vpn-edit" ? "vpn" : Ui.netPage === "cntlm-edit" ? "cntlm" : "main"
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            BarText {
                Layout.fillWidth: true
                text: header.title
                font.bold: true
                font.pixelSize: Theme.fontSize + 2
                elide: Text.ElideRight
            }
            BarText {
                Layout.fillWidth: true
                visible: header.subtitle !== ""
                text: header.subtitle
                color: Theme.dim
                font.pixelSize: Theme.fontSize - 2
                elide: Text.ElideRight
            }
        }
        RowLayout {
            id: extraRow
            spacing: 8
        }
    }

    // Línea "etiqueta ........ valor"
    component InfoLine: RowLayout {
        id: line
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        visible: value !== ""
        spacing: 10
        BarText { text: line.label; color: Theme.dim; font.pixelSize: Theme.fontSize - 1 }
        BarText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: line.value
            elide: Text.ElideMiddle
            font.pixelSize: Theme.fontSize - 1
        }
    }
}
