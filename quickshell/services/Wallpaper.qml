pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Fondo de escritorio: fondo actual, lista de fondos y cambio con transición.
//  · Lo dibuja Quickshell (modules/wallpaper/WallpaperLayer.qml) para poder animar los cambios.
//  · ~/.local/state/quickshell/wallpaper es un enlace al fondo actual: lo usan el autostart (swaybg),
//    lock.sh y cualquier script, así la ruta no está escrita a mano en ningún sitio.
//  · swaybg queda DEBAJO con el mismo fondo como red de seguridad (si Quickshell se cae, no queda negro).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/Pictures/Wallpapers"
    readonly property string link: home + "/.local/state/quickshell/wallpaper"
    readonly property string thumbDir: home + "/.cache/quickshell/wallthumbs"

    property string current: ""             // ruta real del fondo actual
    property string previous: ""            // el anterior (para la transición)
    property var list: []                   // [{ path, name, thumb }]
    property bool scanning: false

    // Transición: fade | zoom | circle | wipe | random
    property string transition: "circle"
    readonly property var transitions: ["circle", "fade", "zoom", "wipe", "random"]
    property point origin: Qt.point(-1, -1) // punto de origen del círculo (-1 = centro)
    signal changed(string path, string kind)

    function set(path, originPoint) {
        if (!path || path === current) return;
        previous = current;
        current = path;
        origin = originPoint ?? Qt.point(-1, -1);
        const kinds = ["circle", "fade", "zoom", "wipe"];
        changed(path, transition === "random" ? kinds[Math.floor(Math.random() * kinds.length)] : transition);
        // Enlace + swaybg debajo con el fondo nuevo (red de seguridad). Independiente en cada cambio.
        Quickshell.execDetached(["sh", "-c",
            'ln -sfn "$1" "$2"\n' +
            'pkill -x swaybg; setsid -f swaybg -m fill -i "$1" >/dev/null 2>&1 </dev/null',
            "sh", path, link]);
        saveState();
    }

    function next() { _step(1); }
    function prev() { _step(-1); }
    function random() {
        if (list.length < 2) return;
        let p;
        do { p = list[Math.floor(Math.random() * list.length)].path; } while (p === current);
        set(p);
    }
    function _step(d) {
        if (list.length === 0) return;
        const i = list.findIndex(w => w.path === current);
        set(list[(i + d + list.length) % list.length].path);
    }
    function setTransition(t) { transition = t; saveState(); }

    // ───── Lista de fondos + miniaturas en caché (ffmpeg, 480 px) ─────
    function scan() {
        if (scanner.running) return;
        scanning = true;
        scanner.running = true;
    }
    Process {
        id: scanner
        command: ["sh", "-c",
            'mkdir -p "$1" "$2"\n' +
            'find "$1" -maxdepth 2 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) -printf "%T@\\t%p\\n" ' +
            '| sort -rn | cut -f2- | while IFS= read -r f; do\n' +
            '  t="$2/$(printf "%s" "$f" | md5sum | cut -c1-32).jpg"\n' +
            '  [ -s "$t" ] && [ "$t" -nt "$f" ] || ffmpeg -loglevel error -y -i "$f" -vf "scale=480:-2" -q:v 4 "$t" </dev/null\n' +
            '  printf "%s\\t%s\\n" "$f" "$t"\n' +
            'done',
            "sh", root.dir, root.thumbDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.list = text.split("\n").filter(l => l).map(l => {
                    const [path, thumb] = l.split("\t");
                    const name = path.slice(path.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ");
                    return { path, thumb, name };
                });
                root.scanning = false;
            }
        }
    }

    // ───── Estado ─────
    readonly property string stateFile: home + "/.local/state/quickshell/wallpaper.json"
    function saveState() { stateView.setText(JSON.stringify({ current, transition })); }
    FileView {
        id: stateView
        path: root.stateFile
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.current = s.current ?? "";
                root.transition = s.transition ?? "circle";
            } catch (e) {}
            root._resolveInitial();
        }
        onLoadFailed: root._resolveInitial()
    }
    // Sin estado guardado: el destino del enlace (o el primero de la carpeta)
    function _resolveInitial() {
        if (current) return;
        linkReader.running = true;
    }
    Process {
        id: linkReader
        command: ["readlink", "-f", root.link]
        stdout: StdioCollector { onStreamFinished: if (!root.current) root.current = text.trim() }
    }

    Component.onCompleted: scan()
}
