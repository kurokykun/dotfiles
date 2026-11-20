pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "clipdetect.js" as Detect

// Historial del portapapeles (backend: cliphist) + fijados + metadatos.
// La captura la hacen scripts/clip-store.sh + wl-paste --watch (autostart de labwc);
// aquí se lee, se decodifica, se pega, se fija y se borra.
//
// Datos propios en ~/.local/share/quickshell/clipboard/:
//   pins.json   fijados (contenido completo; las imágenes en pins/<id>.img)
//   meta.json   hora y app de origen de cada entrada del historial (clave = vista previa)
Singleton {
    id: root

    // Entrada: { line, id, key, preview, isImage, info, kind, pinned, pinId, text, imagePath, time, app }
    property var history: []                 // de cliphist, más reciente primero
    property var pins: []                    // [{ id, isImage, text, imagePath, info, time, app }]
    property var meta: ({})                  // key → { t, app }

    // Fijados primero; del historial se ocultan los que ya están fijados
    readonly property var entries: {
        const pinKeys = {};
        const pinned = pins.map(p => {
            const key = p.isImage ? "img:" + p.info : Detect.previewOf(p.text, 400);
            pinKeys[key] = true;
            return { line: "", id: "pin-" + p.id, key, pinned: true, pinId: p.id,
                     isImage: p.isImage, info: p.info || "", preview: p.isImage ? "" : Detect.previewOf(p.text, 400),
                     text: p.text || "", imagePath: p.imagePath || "",
                     kind: Detect.detect(p.text, p.isImage, false), time: p.time, app: p.app || "" };
        });
        return pinned.concat(history.filter(e => !pinKeys[e.key]).map(e => root.withMeta(e)));
    }

    readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/quickshell/clipboard"
    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-clipboard"
    readonly property string pauseFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-clipboard.paused"
    property bool paused: false
    property bool ready: false

    // Apps donde pegar es Ctrl+Shift+V
    readonly property var terminals: ["kitty", "foot", "alacritty", "org.wezfurlong.wezterm", "com.mitchellh.ghostty",
        "xterm", "konsole", "org.kde.konsole", "gnome-terminal-server", "org.gnome.terminal", "org.gnome.console",
        "com.gexperts.tilix", "terminator", "xfce4-terminal"]
    function isTerminal(appId) { return terminals.includes((appId || "").toLowerCase()); }

    // Nombre legible de la app de origen
    function appName(appId) {
        if (!appId) return "";
        const e = DesktopEntries.heuristicLookup(appId);
        return e?.name || appId;
    }

    // ───── Archivos propios ─────
    Process {
        running: true
        command: ["mkdir", "-p", root.dataDir + "/pins"]
        onExited: { pinsFile.reload(); metaFile.reload(); }
    }
    FileView {
        id: pinsFile
        path: root.dataDir + "/pins.json"
        printErrors: false
        onLoaded: { try { root.pins = JSON.parse(text()); } catch (e) { root.pins = []; } root.ready = true; }
        onLoadFailed: root.ready = true
    }
    FileView {
        id: metaFile
        path: root.dataDir + "/meta.json"
        printErrors: false
        onLoaded: { try { root.meta = JSON.parse(text()); } catch (e) {} }
    }
    function savePins() { pinsFile.setText(JSON.stringify(pins)); }
    function saveMeta() {
        // Solo las claves que siguen en el historial
        const keep = {};
        for (const e of history) if (meta[e.key]) keep[e.key] = meta[e.key];
        meta = keep;
        metaFile.setText(JSON.stringify(keep));
    }

    // ───── Lista (cliphist) ─────
    property bool _pending: false
    function refresh() {
        if (lister.running) { _pending = true; return; }
        lister.running = true;
    }

    Process {
        id: lister
        command: ["cliphist", "list", "-preview-width", "400"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    const id = line.slice(0, tab);
                    const preview = line.slice(tab + 1);
                    const img = preview.match(/^\[\[ binary data (.+?) \]\]$/);
                    const key = img ? "img:" + img[1] : preview;
                    out.push({ line, id, key, preview: img ? "" : preview, isImage: !!img, info: img ? img[1] : "",
                               kind: Detect.detect(preview, !!img, preview.length >= 400),
                               pinned: false, time: 0, app: "" });
                }
                // Metadatos del último cambio (hora y app donde se copió)
                if (root._change && out.length > 0) {
                    const m = Object.assign({}, root.meta);
                    m[out[0].key] = { t: root._change.t, app: root._change.app };
                    root.meta = m;
                    root._change = null;
                    root.history = out;
                    root.saveMeta();
                } else {
                    root.history = out;
                }
                if (root._pending) { root._pending = false; root.refresh(); }
            }
        }
    }

    // Hora y app de cada entrada (se rellenan desde meta)
    function withMeta(e) {
        if (e.pinned) return e;
        const m = meta[e.key];
        return m ? Object.assign({}, e, { time: m.t, app: m.app || "" }) : e;
    }

    // Cada vez que cambia el portapapeles: anotar app y hora, y refrescar
    property var _change: null
    property bool _watchStarted: false
    property real _selfCopyUntil: 0           // copias hechas por el propio panel: no cambian el origen
    Process {
        running: true
        // Al reiniciar Quickshell (Super+N) el vigilante anterior quedaba huérfano: se elimina al arrancar.
        // "^wl-paste" evita que pkill se mate a sí mismo (su línea empieza por "sh").
        command: ["sh", "-c", 'pkill -f "^wl-paste --watch echo qs-clip-cambio$"; exec wl-paste --watch echo qs-clip-cambio']
        stdout: SplitParser {
            onRead: {
                if (!root._watchStarted) { root._watchStarted = true; return; }   // evento inicial
                if (Date.now() > root._selfCopyUntil)
                    root._change = { t: Date.now(), app: ToplevelManager.activeToplevel?.appId ?? "" };
                refreshTimer.restart();
            }
        }
    }
    Timer { id: refreshTimer; interval: 350; onTriggered: root.refresh() }

    // ───── Vista previa del elemento seleccionado ─────
    // Siempre se decodifica el ÚLTIMO pedido: si llega otro mientras trabaja, se encola.
    property string previewText: ""
    property string previewImage: ""
    property var _want: null

    function loadPreview(e) {
        previewText = "";
        previewImage = "";
        _want = e;
        if (!e) return;
        if (e.pinned) {                        // los fijados ya tienen el contenido
            if (e.isImage) previewImage = e.imagePath; else previewText = e.text;
            return;
        }
        _startDecode();
    }

    function _startDecode() {
        const e = _want;
        if (!e || e.pinned) return;
        if (decoder.running) { decodeRetry.restart(); return; }
        decoder.forLine = e.line;
        decoder.isImg = e.isImage;
        decoder.command = e.isImage
            ? ["sh", "-c",
               'mkdir -p "$2" && f="$2/$3.img"; [ -s "$f" ] || printf "%s" "$1" | cliphist decode > "$f"; printf "%s" "$f"',
               "sh", e.line, runDir, e.id]
            : ["sh", "-c", 'printf "%s" "$1" | cliphist decode | head -c 60000', "sh", e.line];
        decoder.running = true;
    }
    Timer { id: decodeRetry; interval: 30; onTriggered: root._startDecode() }

    Process {
        id: decoder
        property string forLine: ""
        property bool isImg: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._want && !root._want.pinned && decoder.forLine === root._want.line) {
                    if (decoder.isImg) root.previewImage = text.trim();
                    else root.previewText = text;
                } else if (root._want) {
                    decodeRetry.restart();          // la selección cambió: decodificar la nueva
                }
            }
        }
    }

    // ───── Usar (copiar y pegar) ─────
    // paste = true: pega en la ventana que estaba activa (Ctrl+V, o Ctrl+Shift+V en terminales)
    readonly property string _pasteTail:
        '[ "$2" = none ] && exit 0\n' +
        'sleep 0.2\n' +                            // que el panel se cierre y vuelva el foco
        'if [ "$2" = term ]; then wtype -M ctrl -M shift -k v -m shift -m ctrl; ' +
        'else wtype -M ctrl -k v -m ctrl; fi'

    function use(e, paste, appId) {
        if (!e) return;
        const mode = !paste ? "none" : isTerminal(appId) ? "term" : "normal";
        _selfCopyUntil = Date.now() + 1500;
        if (e.pinned && e.isImage)
            Quickshell.execDetached(["sh", "-c", 'wl-copy < "$1" || exit 1\n' + _pasteTail, "sh", e.imagePath, mode]);
        else if (e.pinned)
            Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy || exit 1\n' + _pasteTail, "sh", e.text, mode]);
        else
            Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist decode | wl-copy || exit 1\n' + _pasteTail,
                                     "sh", e.line, mode]);
    }

    // Pega (o copia) un texto cualquiera, p. ej. el resultado de una transformación
    function useText(text, paste, appId) {
        const mode = !paste ? "none" : isTerminal(appId) ? "term" : "normal";
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy || exit 1\n' + _pasteTail, "sh", text, mode]);
    }

    // ───── Fijados ─────
    function togglePin(e) {
        if (!e) return;
        if (e.pinned) { unpin(e.pinId); return; }
        // ¿Ya hay un fijado con el mismo contenido? Entonces es desfijar
        const same = pins.find(p => (p.isImage ? "img:" + p.info : Detect.previewOf(p.text, 400)) === e.key);
        if (same) { unpin(same.id); return; }
        const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
        pinner.entry = e;
        pinner.pinId = id;
        pinner.command = e.isImage
            ? ["sh", "-c", 'f="$2/pins/$3.img"; printf "%s" "$1" | cliphist decode > "$f" && printf "%s" "$f"',
               "sh", e.line, dataDir, id]
            : ["sh", "-c", 'printf "%s" "$1" | cliphist decode', "sh", e.line];
        pinner.running = true;
    }

    Process {
        id: pinner
        property var entry: null
        property string pinId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const e = pinner.entry;
                if (!e) return;
                const m = root.meta[e.key];
                const p = { id: pinner.pinId, isImage: e.isImage, info: e.info,
                            time: m?.t ?? Date.now(), app: m?.app ?? "" };
                if (e.isImage) p.imagePath = text.trim(); else p.text = text;
                if (!e.isImage && !p.text) return;
                root.pins = [p].concat(root.pins);
                root.savePins();
            }
        }
    }

    function unpin(pinId) {
        const p = pins.find(x => x.id === pinId);
        pins = pins.filter(x => x.id !== pinId);
        savePins();
        if (p?.isImage && p.imagePath) Quickshell.execDetached(["rm", "-f", p.imagePath]);
    }

    // ───── Borrar ─────
    function remove(e) {
        if (!e) return;
        if (e.pinned) { unpin(e.pinId); return; }
        history = history.filter(x => x.line !== e.line);      // al instante en la interfaz
        Quickshell.execDetached(["sh", "-c",
            'printf "%s" "$1" | cliphist delete; rm -f "$2/$3.img"', "sh", e.line, runDir, e.id]);
        refreshTimer.restart();
    }

    // Vacía el historial (los fijados se conservan)
    function wipe() {
        history = [];
        meta = {};
        metaFile.setText("{}");
        Quickshell.execDetached(["sh", "-c", 'cliphist wipe; rm -rf "$1"', "sh", runDir]);
        refreshTimer.restart();
    }

    // ───── Pausa (modo incógnito): clip-store.sh no guarda nada mientras exista el archivo ─────
    function setPaused(p) {
        paused = p;
        Quickshell.execDetached(p ? ["touch", pauseFile] : ["rm", "-f", pauseFile]);
    }
    Process {
        running: true
        command: ["test", "-e", root.pauseFile]
        onExited: code => root.paused = code === 0
    }

    Component.onCompleted: refresh()
}
