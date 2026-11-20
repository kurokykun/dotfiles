pragma Singleton
import QtQuick
import Quickshell
import qs.config

// Estado del OSD (volumen, micrófono, brillo, distribución de teclado).
// Escucha los servicios y publica qué mostrar; modules/osd lo pinta.
Singleton {
    id: root

    property bool visible: false
    property string kind: ""        // volume | mic | brightness | keyboard
    property string icon: ""
    property string text: ""        // "66%" o "ES"
    property real value: -1         // 0..1.5 para la barra; -1 = sin barra
    property bool muted: false

    readonly property int timeout: 1500

    function show(k, ic, txt, val, mute) {
        kind = k; icon = ic; text = txt; value = val; muted = !!mute;
        visible = true;
        hideTimer.restart();
    }
    function hide() { visible = false; }

    Timer { id: hideTimer; interval: root.timeout; onTriggered: root.visible = false }

    // Silencio al arrancar y al cambiar de dispositivo de salida
    // (PipeWire "cambia" el volumen al conectar el nodo).
    property bool _armed: false
    Timer { id: armTimer; interval: 1500; running: true; onTriggered: root._armed = true }
    function _quiet(ms) { _armed = false; armTimer.interval = ms; armTimer.restart(); }

    // No hace falta OSD si el panel de sonido está abierto (ya se ve el slider)
    readonly property bool _audioQuiet: !_armed || Ui.audioOpen

    function showVolume() {
        if (_audioQuiet || !Audio.sinkReady) return;
        show("volume", Audio.volumeIcon(Audio.volume, Audio.muted),
             Audio.muted ? "Silencio" : Math.round(Audio.volume * 100) + "%",
             Audio.volume, Audio.muted);
    }

    Connections {
        target: Audio
        function onVolumeChanged() { root.showVolume(); }
        function onMutedChanged() { root.showVolume(); }
        function onSinkChanged() { root._quiet(600); }
        function onMicMutedChanged() {
            if (root._audioQuiet || !Audio.sourceReady) return;
            root.show("mic", Audio.micMuted ? Icons.micOff : Icons.mic,
                      Audio.micMuted ? "Micrófono silenciado" : "Micrófono activado", -1, Audio.micMuted);
        }
    }

    Connections {
        target: Brightness
        function onUserChanged() {
            if (Ui.batteryOpen) return;      // el slider del panel ya lo muestra
            const v = Brightness.value;
            root.show("brightness",
                      v < 0.34 ? Icons.brightnessLow : v < 0.67 ? Icons.brightnessMid : Icons.brightnessHigh,
                      Math.round(v * 100) + "%", v, false);
        }
    }

    property string _lastLayout: ""
    Connections {
        target: Keyboard
        function onCurrentChanged() {
            const cur = Keyboard.current;
            if (root._armed && root._lastLayout !== "" && cur !== root._lastLayout)
                root.show("keyboard", Icons.keyboard, Keyboard.label, -1, false);
            root._lastLayout = cur;
        }
    }
    Component.onCompleted: _lastLayout = Keyboard.current
}
