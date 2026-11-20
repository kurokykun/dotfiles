pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Luz nocturna (wlsunset): pantalla más cálida por la noche.
// Modos:  auto     → atardecer/amanecer reales según la ubicación del clima
//         schedule → horario fijo (sunset → sunrise)
//         always   → cálida todo el tiempo
// wlsunset lo lanza Quickshell; al apagarlo (o si Quickshell se cierra) la pantalla vuelve a su color normal.
Singleton {
    id: root

    // ───── Configuración (se guarda en ~/.local/state/quickshell/nightlight.json) ─────
    property bool enabled: false
    property string mode: "auto"
    property int temperature: 4000          // K de noche (2500 muy cálido … 5500 suave)
    property string sunset: "20:00"         // modo schedule
    property string sunrise: "07:00"

    readonly property real latitude: Weather.latitude
    readonly property real longitude: Weather.longitude

    // ¿Está la pantalla en modo cálido ahora mismo? (para el indicador y el subtítulo)
    readonly property bool warmNow: enabled && (mode === "always" || isNight)
    property bool isNight: false

    function setEnabled(on) { enabled = on; save(); }
    function setMode(m) { mode = m; save(); restart(); }
    function setTemperature(t) { temperature = Math.round(Math.max(2500, Math.min(5500, t)) / 100) * 100; save(); restartLater.restart(); }
    function setSchedule(set, rise) { sunset = set; sunrise = rise; save(); restart(); }

    // ───── Proceso ─────
    property bool _restarting: false
    function restart() { if (enabled) { _restarting = true; restartTimer.restart(); } }
    Timer { id: restartTimer; interval: 250; onTriggered: root._restarting = false }
    Timer { id: restartLater; interval: 500; onTriggered: root.restart() }   // slider: esperar a que se suelte

    Process {
        id: proc
        running: root.enabled && root._loaded && !root._restarting
        command: {
            const t = String(root.temperature);
            let args;
            if (root.mode === "always")                       // día = noche → siempre cálida
                args = ["-t", t, "-T", String(root.temperature + 1)];
            else if (root.mode === "schedule")
                args = ["-t", t, "-T", "6500", "-S", root.sunrise, "-s", root.sunset, "-d", "1800"];
            else
                args = ["-t", t, "-T", "6500", "-l", root.latitude.toFixed(4), "-L", root.longitude.toFixed(4)];
            // Un wlsunset huérfano de un reinicio anterior de Quickshell se elimina antes de lanzar el nuevo
            return ["sh", "-c", 'pkill -x wlsunset; exec wlsunset "$@"', "sh"].concat(args);
        }
        // "calculated sun trajectory: dawn 06:14, sunrise 06:52, sunset 17:35, dusk 18:13"
        stderr: SplitParser {
            onRead: line => {
                const m = line.match(/sunrise (\d\d:\d\d), sunset (\d\d:\d\d)/);
                if (m) { root.autoSunrise = m[1]; root.autoSunset = m[2]; root.updateTimes(); }
                else if (/error|fail|could not/i.test(line)) console.warn("wlsunset:", line);
            }
        }
    }

    // ───── Horas de hoy (para mostrarlas y saber si es de noche) ─────
    // En modo auto las calcula wlsunset con la ubicación y las imprime al arrancar (ver stderr arriba).
    property string autoSunrise: ""
    property string autoSunset: ""
    function toMin(hhmm) { const p = hhmm.split(":"); return Number(p[0]) * 60 + Number(p[1]); }

    property string todaySunset: ""
    property string todaySunrise: ""

    function updateTimes() {
        const now = new Date();
        todaySunrise = mode === "schedule" ? sunrise : autoSunrise;
        todaySunset = mode === "schedule" ? sunset : autoSunset;
        if (!todaySunrise || !todaySunset) { isNight = false; return; }
        const rise = toMin(todaySunrise), set = toMin(todaySunset);
        const m = now.getHours() * 60 + now.getMinutes();
        isNight = set > rise ? (m >= set || m < rise) : (m >= set && m < rise);
    }
    onModeChanged: updateTimes()
    onSunsetChanged: updateTimes()
    onSunriseChanged: updateTimes()
    onLatitudeChanged: updateTimes()
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.updateTimes() }

    // Texto corto para el interruptor del panel
    readonly property string shortStatus: !enabled ? "Apagada"
        : mode === "always" ? "Siempre"
        : warmNow ? "Hasta " + todaySunrise
        : todaySunset ? "Desde " + todaySunset : "Automática"

    // Texto completo (IPC)
    readonly property string status: !enabled ? "Apagada"
        : mode === "always" ? "Siempre · " + temperature + " K"
        : warmNow ? "Activa hasta las " + todaySunrise
        : todaySunset ? "Se activará a las " + todaySunset : "Automática (al atardecer)"

    // ───── Guardar / cargar ─────
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/quickshell"
    property bool _loaded: false

    function save() {
        if (!_loaded) return;
        file.setText(JSON.stringify({ enabled, mode, temperature, sunset, sunrise }));
    }

    Process {
        running: true
        command: ["mkdir", "-p", root.stateDir]
        onExited: file.reload()
    }
    FileView {
        id: file
        path: root.stateDir + "/nightlight.json"
        printErrors: false
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.enabled = !!c.enabled;
                root.mode = c.mode ?? "auto";
                root.temperature = c.temperature ?? 4000;
                root.sunset = c.sunset ?? "20:00";
                root.sunrise = c.sunrise ?? "07:00";
            } catch (e) {}
            root._loaded = true;
            root.updateTimes();
        }
        onLoadFailed: { root._loaded = true; root.updateTimes(); }
    }
}
