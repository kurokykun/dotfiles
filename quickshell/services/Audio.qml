pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.config

// Audio vía PipeWire: salidas, entradas, volumen por aplicación.
Singleton {
    id: root

    readonly property var nodes: Pipewire.nodes.values
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    readonly property var sinks: sortDevices(nodes.filter(n => n.type === PwNodeType.AudioSink))
    readonly property var sources: sortDevices(nodes.filter(n => n.type === PwNodeType.AudioSource))

    // Orden: Bluetooth y USB primero, luego audio interno, al final pantallas externas
    function sortDevices(list) {
        const rank = n => ({ "Bluetooth": 0, "USB": 1, "Audio interno": 2, "Pantalla externa": 3 })[sublabel(n)] ?? 4;
        return list.slice().sort((a, b) => (rank(a) - rank(b)) || label(a).localeCompare(label(b)));
    }
    // Apps que están sonando (flujos de reproducción)
    readonly property var streams: nodes.filter(n => n.type === PwNodeType.AudioOutStream && n.audio)

    // Mantener vivos los datos de volumen de todo lo que se muestra
    PwObjectTracker { objects: root.sinks.concat(root.sources, root.streams) }

    readonly property bool sinkReady: sink !== null && sink.audio !== null
    readonly property bool sourceReady: source !== null && source.audio !== null
    readonly property real volume: sinkReady ? sink.audio.volume : 0
    readonly property bool muted: sinkReady ? sink.audio.muted : false
    readonly property real micVolume: sourceReady ? source.audio.volume : 0
    readonly property bool micMuted: sourceReady ? source.audio.muted : false

    function setVolume(node, v) { if (node?.audio) node.audio.volume = Math.max(0, Math.min(1.5, v)); }
    function toggleMute(node) { if (node?.audio) node.audio.muted = !node.audio.muted; }
    function setDefaultSink(node) { Pipewire.preferredDefaultAudioSink = node; }
    function setDefaultSource(node) { Pipewire.preferredDefaultAudioSource = node; }

    // ───── Nombres legibles ─────
    // "Alder Lake PCH-P High Definition Audio Controller Speaker" → "Altavoces" · "Audio interno"
    function isBluetooth(n) { return (n?.properties?.["device.api"] ?? "") === "bluez5" || (n?.name ?? "").startsWith("bluez"); }

    function label(n) {
        if (!n) return "—";
        let d = n.description || n.nickname || n.name || "";
        const m = d.match(/(?:Audio Controller|Audio)\s+(.+)$/);
        if (!isBluetooth(n) && m) d = m[1];
        d = d.replace(/\s*\((Stereo|Mono|Surround[^)]*)\)\s*$/i, "")
             .replace(/\s+Output$/i, "")
             .replace(/\s+Input$/i, "");
        const tr = {
            "Speaker": "Altavoces", "Speakers": "Altavoces",
            "Headphones": "Auriculares", "Headset": "Auriculares con micrófono",
            "Digital Microphone": "Micrófono digital", "Stereo Microphone": "Micrófono estéreo",
            "Microphone": "Micrófono", "Internal Microphone": "Micrófono interno",
            "Headset Microphone": "Micrófono de los auriculares", "Line Out": "Salida de línea"
        };
        return tr[d] ?? d;
    }

    function sublabel(n) {
        if (!n) return "";
        if (isBluetooth(n)) return "Bluetooth";
        const d = (n.description || "").toLowerCase();
        if (d.includes("hdmi") || d.includes("displayport")) return "Pantalla externa";
        if ((n.properties?.["device.bus"] ?? "") === "usb") return "USB";
        return "Audio interno";
    }

    function icon(n, input) {
        if (input) return Icons.mic;
        const d = (n?.description || "").toLowerCase();
        if (isBluetooth(n) || d.includes("headphone") || d.includes("headset")) return Icons.headphones;
        if (d.includes("hdmi") || d.includes("displayport")) return Icons.monitor;
        return Icons.speaker;
    }

    function volumeIcon(v, mute) {
        if (mute || v <= 0.001) return Icons.volumeOff;
        return v < 0.5 ? Icons.volumeLow : Icons.volumeHigh;
    }

    // Nombre e icono de una app que suena
    function appName(n) {
        const p = n.properties ?? {};
        return p["application.name"] || p["media.name"] || n.description || n.name || "Aplicación";
    }

    function appIcon(n) {
        const p = n.properties ?? {};
        const candidates = [p["application.icon-name"], p["application.process.binary"], (p["application.name"] || "").toLowerCase()];
        for (const c of candidates) {
            if (!c) continue;
            const path = Quickshell.iconPath(c, true);
            if (path) return path;
            const alt = Quickshell.iconPath(c + "-client", true) || Quickshell.iconPath(c + "-launcher", true);
            if (alt) return alt;
        }
        return Quickshell.iconPath("audio-x-generic", "application-x-executable");
    }
}
