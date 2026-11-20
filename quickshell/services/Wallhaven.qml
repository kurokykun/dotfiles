pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wallhaven en el selector de fondos (scripts/wallhaven.py hace las peticiones).
// Ahorro de datos: las miniaturas (~22 KB) quedan en caché para siempre; la imagen completa
// (~1–8 MB) solo se descarga al elegirla y se guarda en ~/Pictures/Wallpapers (no se repite).
Singleton {
    id: root

    // ───── Filtros (se guardan) ─────
    property string query: ""
    property bool general: true
    property bool anime: true
    property bool people: false
    property string sorting: "toplist"      // toplist | date_added | random | favorites
    readonly property var sortings: [
        { id: "toplist", label: "Destacados" },
        { id: "date_added", label: "Recientes" },
        { id: "favorites", label: "Favoritos" },
        { id: "random", label: "Aleatorio" }
    ]
    readonly property string categories: (general ? "1" : "0") + (anime ? "1" : "0") + (people ? "1" : "0")

    // ───── Resultados ─────
    property var items: []
    property int page: 0
    property int lastPage: 0
    property int total: 0
    property string seed: ""
    property bool loading: false
    property string error: ""
    property bool searched: false
    readonly property bool hasMore: page > 0 && page < lastPage

    // Datos gastados en esta sesión (miniaturas + respuestas + imágenes completas)
    property real sessionBytes: 0
    function fmtBytes(b) { return b >= 1e6 ? (b / 1e6).toFixed(1) + " MB" : Math.round(b / 1024) + " KB"; }

    readonly property string script: Quickshell.shellDir + "/scripts/wallhaven.py"

    // Cambia en cada búsqueda nueva: el selector solo vuelve al principio en ese caso
    // (al cargar más resultados o al terminar una descarga mantiene la posición)
    property int generation: 0

    function search() {
        generation++;
        items = [];
        page = 0;
        seed = "";
        _fetch(1);
    }
    function more() { if (hasMore && !loading) _fetch(page + 1); }

    function _fetch(p) {
        if (loading) return;
        loading = true;
        error = "";
        searched = true;
        const opts = {
            q: query.trim(),
            categories: categories === "000" ? "110" : categories,
            sorting: query.trim() && sorting === "toplist" ? "relevance" : sorting,
            page: p,
            atleast: "1920x1080"
        };
        if (sorting === "random" && seed) opts.seed = seed;
        searcher.command = ["python3", "-I", script, "search", JSON.stringify(opts)];
        searcher.running = true;
        saveState();
    }
    Process {
        id: searcher
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                let d;
                try { d = JSON.parse(text); } catch (e) { root.error = "Respuesta no válida de Wallhaven"; return; }
                if (d.error) { root.error = d.error.includes("timed out") || d.error.includes("urlopen") ? "Sin conexión con Wallhaven" : d.error; return; }
                root.sessionBytes += d.bytes || 0;
                root.items = (d.page > 1 ? root.items : []).concat(d.items);
                root.page = d.page;
                root.lastPage = d.lastPage;
                root.total = d.total;
                if (d.seed) root.seed = d.seed;
            }
        }
    }

    // ───── Descargar y aplicar ─────
    property string downloadingId: ""
    property real progress: 0                // 0..1
    property var _pendingApply: null

    function apply(item, origin) {
        if (!item) return;
        if (item.local) { Wallpaper.set(item.local, origin); return; }
        if (downloader.running) return;
        downloadingId = item.id;
        progress = 0;
        _pendingApply = { item, origin };
        downloader.command = ["python3", "-I", script, "download", item.id, item.url];
        downloader.running = true;
    }
    Process {
        id: downloader
        property real lastBytes: 0
        onStarted: lastBytes = 0
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(" ");
                if (parts[0] === "P") {
                    const done = Number(parts[1]), tot = Number(parts[2]);
                    root.sessionBytes += done - downloader.lastBytes;
                    downloader.lastBytes = done;
                    root.progress = tot > 0 ? done / tot : 0;
                } else if (parts[0] === "OK") {
                    const path = line.slice(3);
                    const p = root._pendingApply;
                    // Marcar como descargado en la lista
                    root.items = root.items.map(i => i.id === root.downloadingId ? Object.assign({}, i, { local: path }) : i);
                    root.downloadingId = "";
                    root._pendingApply = null;
                    Wallpaper.scan();
                    Wallpaper.set(path, p ? p.origin : undefined);
                } else if (parts[0] === "ERR") {
                    root.error = "No se pudo descargar: " + line.slice(4);
                    root.downloadingId = "";
                }
            }
        }
        onExited: code => { if (code !== 0 && root.downloadingId) { root.error = "La descarga falló"; root.downloadingId = ""; } }
    }

    // ───── Estado ─────
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/quickshell/wallhaven.json"
    function saveState() { stateView.setText(JSON.stringify({ query, general, anime, people, sorting })); }
    FileView {
        id: stateView
        path: root.stateFile
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.query = s.query ?? "";
                root.general = s.general ?? true;
                root.anime = s.anime ?? true;
                root.people = s.people ?? false;
                root.sorting = s.sorting ?? "toplist";
            } catch (e) {}
        }
    }
}
