pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Cafeína: impide que la sesión se bloquee o la pantalla se apague por inactividad.
//  · manual: interruptor (no se guarda: al reiniciar la sesión vuelve a apagado)
//  · auto:   mientras cualquier reproductor MPRIS esté sonando (Spotify, YouTube en Chrome, vídeos…)
// El inhibidor real (protocolo idle-inhibit) lo pone modules/idle/IdleInhibit.qml.
Singleton {
    id: root

    property bool manual: false
    property bool autoMedia: true           // se guarda en ~/.local/state/quickshell/caffeine.json

    readonly property bool mediaPlaying: Mpris.players.values.some(p => p.isPlaying)
    readonly property bool byMedia: autoMedia && mediaPlaying
    readonly property bool active: manual || byMedia

    function setManual(on) { manual = on; }
    function toggle() { manual = !manual; }
    function setAutoMedia(on) { autoMedia = on; save(); }

    readonly property string shortStatus: manual ? "Activada" : byMedia ? "Por música" : autoMedia ? "Automática" : "Apagada"
    readonly property string status: manual ? "Activada"
        : byMedia ? "Activa: hay algo sonando"
        : autoMedia ? "Automática con música o vídeo" : "Apagada"

    // ───── Guardar / cargar ─────
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/quickshell"
    property bool _loaded: false
    function save() { if (_loaded) file.setText(JSON.stringify({ autoMedia })); }

    Process {
        running: true
        command: ["mkdir", "-p", root.stateDir]
        onExited: file.reload()
    }
    FileView {
        id: file
        path: root.stateDir + "/caffeine.json"
        printErrors: false
        onLoaded: {
            try { root.autoMedia = JSON.parse(text()).autoMedia ?? true; } catch (e) {}
            root._loaded = true;
        }
        onLoadFailed: root._loaded = true
    }
}
