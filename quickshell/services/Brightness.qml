pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Brillo de la pantalla vía brightnessctl.
// sysfs no avisa de los cambios, así que los atajos de labwc llaman a
// `qs ipc call brightness changed` después de brightnessctl para refrescar.
Singleton {
    id: root

    property real value: 0          // 0..1
    property bool available: false
    signal userChanged()            // un cambio hecho por el usuario (para el OSD)

    property bool _loaded: false
    property bool _notify: false
    property bool _pending: false

    // Relee el valor real. notify = false: solo sincroniza (sin OSD)
    function refresh(notify) {
        if (notify !== false) _notify = true;
        if (reader.running) _pending = true;   // al mantener la tecla: relee al terminar
        else reader.running = true;
    }

    // Cambia el brillo. La interfaz se actualiza al instante y brightnessctl
    // se lanza como mucho cada 40 ms (al arrastrar el slider).
    property int _target: -1
    function set(v) {
        const pct = Math.round(Math.max(0.01, Math.min(1, v)) * 100);
        value = pct / 100;
        _target = pct;
        if (!writeTimer.running) writeTimer.start();
        userChanged();
    }
    Timer {
        id: writeTimer
        interval: 40
        onTriggered: {
            if (root._target < 0) return;
            Quickshell.execDetached(["brightnessctl", "-q", "set", root._target + "%"]);
            root._target = -1;
        }
    }

    Process {
        id: reader
        // salida: intel_backlight,backlight,96000,100%,96000
        command: ["brightnessctl", "-m", "-c", "backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n")[0]?.split(",") ?? [];
                if (f.length < 5) { root.available = false; return; }
                root.available = true;
                // No pisar un valor que todavía se está escribiendo
                if (!writeTimer.running) root.value = Number(f[2]) / Number(f[4]);
                // Se avisa aunque no cambie (p. ej. subir estando al 100%) para mostrar el OSD
                if (root._loaded && root._notify) root.userChanged();
                root._notify = false;
                root._loaded = true;
                if (root._pending) { root._pending = false; reader.running = true; }
            }
        }
    }

    Component.onCompleted: refresh(false)
}
