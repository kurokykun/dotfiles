pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Servicio de red sobre NetworkManager (nmcli).
// Dispositivos cableados, Wi-Fi, VPN y modo avión. Se actualiza solo con `nmcli monitor`.
Singleton {
    id: root

    // ───────────── Estado ─────────────
    property var devices: []          // [{device, type, state, connection}]
    property var connections: []      // [{uuid, type, active, autoconnect, device, state, name}]
    property var wifiNetworks: []     // [{ssid, signal, security, secure, active, known, uuid}]
    property bool wifiEnabled: false
    property bool wwanEnabled: false
    property bool scanning: false
    property var busy: ({})           // claves en curso: uuid / ssid / dispositivo
    property var details: ({})        // dispositivo -> {mac, ip4, gateway, dns, ip6, speed}

    readonly property var wiredDevices: devices.filter(d => d.type === "ethernet")
    readonly property var wifiDevice: devices.find(d => d.type === "wifi") ?? null
    readonly property bool wifiAvailable: wifiDevice !== null
    readonly property var vpns: connections.filter(c => c.type === "vpn" || c.type === "wireguard")
    readonly property var activeVpn: vpns.find(v => v.active) ?? null
    readonly property bool vpnBusy: vpns.some(v => busy[v.uuid] === true)
    readonly property bool airplane: !wifiEnabled && !wwanEnabled

    readonly property var activeWired: wiredDevices.find(d => d.state === "connected") ?? null
    readonly property bool wifiConnected: wifiDevice !== null && wifiDevice.state === "connected"
    readonly property var activeWifi: wifiNetworks.find(n => n.active) ?? null
    readonly property int wifiSignal: activeWifi ? activeWifi.signal : 0

    readonly property string primaryType: activeWired ? "ethernet" : wifiConnected ? "wifi" : ""
    readonly property string primaryName: activeWired ? activeWired.connection
        : wifiConnected ? wifiDevice.connection : ""
    readonly property bool connected: primaryType !== ""

    signal wifiConnectFailed(string ssid, string message)
    signal wifiConnected_(string ssid)
    signal vpnImported(string uuid, bool needsCredentials)

    // ───────────── Utilidades ─────────────
    function isBusy(key) { return busy[key] === true; }

    function setBusy(key, value) {
        const b = Object.assign({}, busy);
        if (value) b[key] = true; else delete b[key];
        busy = b;
    }

    function notify(title, body, critical) {
        const args = ["notify-send", "-a", "Red", "-i", critical ? "network-error" : "network-wired"];
        if (critical) args.push("-u", "critical");
        args.push(title, body || "");
        Quickshell.execDetached(args);
    }

    // nmcli -t escapa ':' como '\:'. Separa n campos y deja el resto entero (sin escapes).
    function splitFields(line, n) {
        const out = [];
        let rest = line;
        for (let i = 0; i < n; i++) {
            let idx = -1;
            for (let j = 0; j < rest.length; j++) {
                if (rest[j] === "\\") { j++; continue; }
                if (rest[j] === ":") { idx = j; break; }
            }
            if (idx === -1) { out.push(rest); rest = ""; continue; }
            out.push(rest.slice(0, idx).replace(/\\:/g, ":"));
            rest = rest.slice(idx + 1);
        }
        out.push(rest.replace(/\\:/g, ":").replace(/\\\\/g, "\\"));
        return out;
    }

    // Ejecuta un comando y llama a cb(code, stdout, stderr) al terminar
    function run(cmd, cb, env) {
        const props = { command: cmd, callback: cb ?? null };
        if (env) props.environment = env;
        const p = cmdComponent.createObject(root, props);
        p.running = true;
    }

    Component {
        id: cmdComponent
        Process {
            id: proc
            property var callback: null
            property int doneCount: 0
            property int code: 0
            function step() {
                if (++doneCount < 3) return;
                if (callback) callback(code, out.text, err.text);
                proc.destroy();
            }
            stdout: StdioCollector { id: out; onStreamFinished: proc.step() }
            stderr: StdioCollector { id: err; onStreamFinished: proc.step() }
            onExited: exitCode => { proc.code = exitCode; proc.step(); }
        }
    }

    // ───────────── Lectura ─────────────
    function refresh() {
        run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"], (code, text) => {
            if (code !== 0) return;
            const list = [];
            for (const line of text.split("\n")) {
                if (!line) continue;
                const [device, type, state, connection] = splitFields(line, 3);
                if (type === "ethernet" || type === "wifi")
                    list.push({ device, type, state, connection });
            }
            devices = list;
        });

        run(["nmcli", "-t", "-f", "UUID,TYPE,ACTIVE,AUTOCONNECT,DEVICE,STATE,NAME", "connection", "show"], (code, text) => {
            if (code !== 0) return;
            const list = [];
            for (const line of text.split("\n")) {
                if (!line) continue;
                const [uuid, type, active, autoconnect, device, state, name] = splitFields(line, 6);
                list.push({ uuid, type, name, device, state,
                            active: active === "yes" && state === "activated",
                            autoconnect: autoconnect === "yes" });
            }
            list.sort((a, b) => a.name.localeCompare(b.name));
            connections = list;
            mergeKnown();
        });

        run(["nmcli", "-t", "-f", "WIFI,WWAN", "radio"], (code, text) => {
            if (code !== 0) return;
            const [wifi, wwan] = text.trim().split(":");
            wifiEnabled = wifi === "enabled";
            wwanEnabled = wwan === "enabled";
        });

        if (wifiEnabled) listWifi();
    }

    function listWifi() {
        run(["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list", "--rescan", "no"], (code, text) => {
            if (code !== 0) return;
            const seen = {};
            const nets = [];
            for (const line of text.split("\n")) {
                if (!line) continue;
                const [inUse, signal, security, ssid] = splitFields(line, 3);
                if (!ssid) continue;
                const net = { ssid, signal: parseInt(signal) || 0, security,
                              secure: security !== "" && security !== "--",
                              active: inUse === "*", known: false, uuid: "" };
                if (seen[ssid]) {
                    // Mismo SSID en varios puntos de acceso: quedarse con la mejor señal
                    const prev = seen[ssid];
                    prev.signal = Math.max(prev.signal, net.signal);
                    prev.active = prev.active || net.active;
                    continue;
                }
                seen[ssid] = net;
                nets.push(net);
            }
            nets.sort((a, b) => (b.active - a.active) || (b.signal - a.signal));
            wifiNetworks = nets;
            mergeKnown();
        });
    }

    // Marca qué redes Wi-Fi tienen perfil guardado (por nombre de conexión = SSID)
    function mergeKnown() {
        const known = {};
        for (const c of connections)
            if (c.type === "802-11-wireless") known[c.name] = c.uuid;
        let changed = false;
        const nets = wifiNetworks.map(n => {
            const uuid = known[n.ssid] ?? "";
            if (uuid !== n.uuid) changed = true;
            return Object.assign({}, n, { known: uuid !== "", uuid });
        });
        if (changed) wifiNetworks = nets;
    }

    function scanWifi() {
        if (!wifiEnabled || scanning) return;
        scanning = true;
        run(["nmcli", "device", "wifi", "rescan"], () => {
            scanning = false;
            listWifi();
        });
    }

    function loadDetails(device) {
        run(["nmcli", "-t", "-f", "GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,CAPABILITIES.SPEED", "device", "show", device], (code, text) => {
            if (code !== 0) return;
            const d = { mac: "", ip4: [], gateway: "", dns: [], ip6: [], speed: "" };
            for (const line of text.split("\n")) {
                if (!line) continue;
                const [key, value] = splitFields(line, 1);
                if (!value || value === "--") continue;
                if (key === "GENERAL.HWADDR") d.mac = value;
                else if (key.startsWith("IP4.ADDRESS")) d.ip4.push(value);
                else if (key === "IP4.GATEWAY") d.gateway = value;
                else if (key.startsWith("IP4.DNS")) d.dns.push(value);
                else if (key.startsWith("IP6.ADDRESS") && !value.startsWith("fe80")) d.ip6.push(value);
                else if (key === "CAPABILITIES.SPEED" && value !== "unknown") d.speed = value;
            }
            const all = Object.assign({}, details);
            all[device] = d;
            details = all;
        });
    }

    // ───────────── Acciones: generales ─────────────
    function setWifiEnabled(on) {
        run(["nmcli", "radio", "wifi", on ? "on" : "off"], () => refresh());
    }

    function setAirplane(on) {
        run(["nmcli", "radio", "all", on ? "off" : "on"], () => refresh());
    }

    function setAutoconnect(uuid, on) {
        run(["nmcli", "connection", "modify", "uuid", uuid, "connection.autoconnect", on ? "yes" : "no"], () => refresh());
    }

    function openAdvanced() {
        run(["sh", "-c", "command -v nm-connection-editor"], code => {
            if (code === 0)
                Quickshell.execDetached(["nm-connection-editor"]);
            else
                notify("Falta el editor avanzado",
                       "Instálalo con: sudo pacman -S nm-connection-editor", true);
        });
    }

    // ───────────── Acciones: cableado ─────────────
    function toggleWired(dev) {
        const on = dev.state === "connected";
        setBusy(dev.device, true);
        run(["nmcli", "device", on ? "disconnect" : "connect", dev.device], (code, out, err) => {
            setBusy(dev.device, false);
            if (code !== 0)
                notify(on ? "No se pudo desconectar" : "No se pudo conectar el cable",
                       err.trim() || dev.device, true);
            refresh();
        });
    }

    // ───────────── Acciones: Wi-Fi ─────────────
    // password: "" si es abierta o ya guardada. hidden: red oculta.
    function connectWifi(ssid, password, hidden) {
        const net = wifiNetworks.find(n => n.ssid === ssid);
        setBusy(ssid, true);

        if (net && net.known && !password) {
            run(["nmcli", "connection", "up", "uuid", net.uuid], (code, out, err) => {
                setBusy(ssid, false);
                if (code !== 0) wifiConnectFailed(ssid, cleanError(err));
                else wifiConnected_(ssid);
                refresh();
            });
            return;
        }

        const cmd = ["nmcli", "device", "wifi", "connect", ssid];
        if (password) cmd.push("password", password);
        if (hidden) cmd.push("hidden", "yes");
        if (wifiDevice) cmd.push("ifname", wifiDevice.device);
        const wasKnown = net?.known ?? false;

        run(cmd, (code, out, err) => {
            setBusy(ssid, false);
            if (code !== 0) {
                // No dejar perfiles a medio crear con una contraseña incorrecta
                if (!wasKnown) run(["nmcli", "connection", "delete", "id", ssid], () => refresh());
                wifiConnectFailed(ssid, cleanError(err));
            } else {
                wifiConnected_(ssid);
            }
            refresh();
        });
    }

    function disconnectWifi() {
        if (!wifiDevice) return;
        run(["nmcli", "device", "disconnect", wifiDevice.device], () => refresh());
    }

    function forgetWifi(uuid) {
        run(["nmcli", "connection", "delete", "uuid", uuid], () => refresh());
    }

    function cleanError(err) {
        const msg = (err || "").trim().split("\n").pop().replace(/^Error:\s*/, "");
        if (/secrets were required|802-1x|psk|password/i.test(msg)) return "Contraseña incorrecta";
        if (/No network with SSID/i.test(msg)) return "No se encontró la red";
        if (/timeout|timed out/i.test(msg)) return "Tiempo de espera agotado";
        return msg || "No se pudo conectar";
    }

    // ───────────── Acciones: VPN ─────────────
    function toggleVpn(vpn) {
        setBusy(vpn.uuid, true);
        run([Quickshell.shellDir + "/scripts/vpn-toggle.sh", vpn.active ? "down" : "up", vpn.uuid], (code, out, err) => {
            setBusy(vpn.uuid, false);
            if (code !== 0) notify("VPN: " + vpn.name, cleanError(err), true);
            refresh();
        });
    }

    // Abre un selector de archivos e importa la VPN (.ovpn → OpenVPN, .conf → WireGuard)
    function importVpn() {
        run(["zenity", "--file-selection", "--title=Importar VPN",
             "--file-filter=Configuración VPN | *.ovpn *.conf", "--file-filter=Todos | *"], (code, out) => {
            const file = out.trim();
            if (code !== 0 || !file) return;
            const type = file.toLowerCase().endsWith(".ovpn") ? "openvpn" : "wireguard";
            run(["nmcli", "connection", "import", "type", type, "file", file], (c, o, e) => {
                if (c !== 0) {
                    notify("No se pudo importar la VPN", cleanError(e), true);
                    return;
                }
                const m = o.match(/\(([0-9a-f-]{36})\)/);
                const uuid = m ? m[1] : "";
                notify("VPN importada", o.trim(), false);
                refresh();
                if (!uuid) return;
                if (type === "openvpn") {
                    // ¿Pide usuario/contraseña? (ProtonVPN, la mayoría de proveedores)
                    run(["nmcli", "-g", "vpn.data", "connection", "show", "uuid", uuid], (c2, data) => {
                        vpnImported(uuid, /connection-type = (password|password-tls)/.test(data));
                    });
                } else {
                    vpnImported(uuid, false);
                }
            });
        });
    }

    // Lee usuario y si hay contraseña guardada. cb({user, hasPassword, needsCredentials, type})
    function loadVpnInfo(uuid, cb) {
        run(["nmcli", "-g", "connection.type,vpn.data", "connection", "show", "uuid", uuid], (code, out) => {
            const m = out.match(/username = ([^,\n]*)/);
            const needs = /connection-type = (password|password-tls)/.test(out);
            const type = out.startsWith("wireguard") ? "wireguard" : "vpn";
            run(["secret-tool", "lookup", "connection-uuid", uuid, "setting-name", "vpn", "setting-key", "password"], (c2, pw) => {
                cb({ user: m ? m[1].replace(/\\(.)/g, "$1") : "", hasPassword: c2 === 0 && pw.length > 0,
                     needsCredentials: needs, type });
            });
        });
    }

    // Guarda nombre, usuario y contraseña (contraseña en el llavero, igual que GNOME)
    function saveVpn(uuid, name, user, password, cb) {
        const steps = [];
        if (name) steps.push(["nmcli", "connection", "modify", "uuid", uuid, "connection.id", name]);
        if (user !== null)
            steps.push(["nmcli", "connection", "modify", "uuid", uuid, "+vpn.data",
                        "username=" + user.replace(/([,\\=])/g, "\\$1") + ", password-flags=1"]);
        if (password)
            steps.push(["sh", "-c", "printf %s \"$QS_VPN_PW\" | secret-tool store --label=\"VPN password secrets for $2/vpn\" " +
                        "xdg:schema org.freedesktop.NetworkManager.Connection connection-uuid \"$1\" setting-name vpn setting-key password",
                        "sh", uuid, name || uuid]);

        const next = (i, errors) => {
            if (i >= steps.length) {
                refresh();
                if (cb) cb(errors.length === 0, errors.join("\n"));
                return;
            }
            const cmd = steps[i];
            if (cmd[0] === "sh") {
                // La contraseña va por variable de entorno, no en la línea de comandos
                const p = cmdComponent.createObject(root, { command: cmd, environment: { QS_VPN_PW: password },
                    callback: (code, o, e) => next(i + 1, code === 0 ? errors : errors.concat(e.trim())) });
                p.running = true;
            } else {
                run(cmd, (code, o, e) => next(i + 1, code === 0 ? errors : errors.concat(cleanError(e))));
            }
        };
        next(0, []);
    }

    function deleteVpn(uuid, cb) {
        run(["secret-tool", "clear", "connection-uuid", uuid], () => {
            run(["nmcli", "connection", "delete", "uuid", uuid], (code, o, e) => {
                refresh();
                if (cb) cb(code === 0, cleanError(e));
            });
        });
    }

    // ───────────── Actualización automática ─────────────
    Process {
        id: monitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser { onRead: _ => debounce.restart() }
        onExited: restartMonitor.start()
    }

    Timer {
        id: restartMonitor
        interval: 3000
        onTriggered: monitor.running = true
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: root.refresh()
    }

    Timer {
        interval: 20000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
