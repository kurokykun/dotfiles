pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Reproducción actual vía MPRIS. Prioriza Spotify; si no está, usa cualquier reproductor activo.
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    readonly property var player: players.find(p => isSpotify(p))
        ?? players.find(p => p.isPlaying)
        ?? players[0]
        ?? null

    readonly property bool active: player !== null && (player.trackTitle ?? "") !== ""
    readonly property bool playing: player?.isPlaying ?? false
    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
    readonly property string album: player?.trackAlbum ?? ""
    // Portada: se descarga UNA vez a ~/.cache/quickshell/covers y todos los componentes usan
    // el archivo local (barra, panel de música, calendario, lock). Así no se baja varias veces por
    // canción (cada Image pedía otro tamaño) ni otra vez al repetir la canción.
    readonly property string artUrl: player?.trackArtUrl ?? ""
    property string art: ""                                     // file://… listo para usar
    readonly property string coverDir: Quickshell.env("HOME") + "/.cache/quickshell/covers"

    onArtUrlChanged: fetchArt()
    Component.onCompleted: fetchArt()      // la canción que ya sonaba al arrancar
    function fetchArt() {
        const u = artUrl;
        if (!u) { art = ""; return; }
        if (!/^https?:\/\//i.test(u)) { art = u; return; }      // file:// u otros: tal cual
        const f = coverDir + "/" + Qt.md5(u) + ".img";
        if (coverFetch.running) { _pendingArt = true; return; }
        art = "";
        coverFetch.forUrl = u;
        coverFetch.file = f;
        coverFetch.command = ["sh", "-c",
            'mkdir -p "$1"\n' +
            'if [ ! -s "$2" ]; then curl -sfL --max-time 20 -o "$2.part" "$3" && mv -f "$2.part" "$2"; rm -f "$2.part"; fi\n' +
            '[ -s "$2" ] && printf ok',
            "sh", coverDir, f, u];
        coverFetch.running = true;
    }
    property bool _pendingArt: false
    Process {
        id: coverFetch
        property string forUrl: ""
        property string file: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === "ok" && coverFetch.forUrl === root.artUrl) root.art = "file://" + coverFetch.file;
                if (root._pendingArt || coverFetch.forUrl !== root.artUrl) {
                    root._pendingArt = false;
                    Qt.callLater(root.fetchArt);
                }
            }
        }
    }
    // Limpieza: portadas que no se usan hace más de 60 días
    Process {
        running: true
        command: ["sh", "-c", 'find "$1" -type f -mtime +60 -delete 2>/dev/null; true', "sh", root.coverDir]
    }
    readonly property real length: player?.length ?? 0          // segundos
    property real position: 0                                   // segundos
    readonly property real progress: length > 0 ? Math.min(1, position / length) : 0

    function isSpotify(p) {
        return (p.identity ?? "").toLowerCase().includes("spotify")
            || (p.dbusName ?? "").toLowerCase().includes("spotify")
            || (p.desktopEntry ?? "").toLowerCase().includes("spotify");
    }

    // La posición no se emite sola: se consulta cada segundo mientras suena
    Timer {
        interval: 1000
        repeat: true
        running: root.player !== null && (root.playing || Ui.mediaOpen)
        triggeredOnStart: true
        onTriggered: root.syncPosition()
    }

    function syncPosition() {
        if (!player) { position = 0; return; }
        player.positionChanged();
        position = player.position;
    }

    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onTrackTitleChanged() { root.syncPosition(); }
        function onPlaybackStateChanged() { root.syncPosition(); }
    }

    // ───── Controles ─────
    function toggle() { if (player?.canTogglePlaying) player.togglePlaying(); }
    function next() { if (player?.canGoNext) { player.next(); Qt.callLater(syncPosition); } }
    function previous() { if (player?.canGoPrevious) { player.previous(); Qt.callLater(syncPosition); } }

    function seekTo(fraction) {
        if (!player?.canSeek || length <= 0) return;
        player.position = Math.max(0, Math.min(1, fraction)) * length;
        position = player.position;
    }

    function toggleShuffle() { if (player?.shuffleSupported) player.shuffle = !player.shuffle; }

    function cycleLoop() {
        if (!player?.loopSupported) return;
        const s = player.loopState;
        player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist
                         : s === MprisLoopState.Playlist ? MprisLoopState.Track
                         : MprisLoopState.None;
    }

    function setVolume(v) { if (player?.volumeSupported) player.volume = Math.max(0, Math.min(1, v)); }

    function raise() {
        if (player?.canRaise) player.raise();
        else Quickshell.execDetached(["spotify-launcher"]);
    }

    function fmt(sec) {
        if (!isFinite(sec) || sec < 0) sec = 0;
        const m = Math.floor(sec / 60);
        const s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }
}
