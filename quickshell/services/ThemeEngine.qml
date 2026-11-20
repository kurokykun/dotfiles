pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Tema automático desde el fondo (matugen).
// Al cambiar el fondo (si "auto" está activo) genera la paleta y la escribe en
// ~/.local/state/quickshell/colors.json; config/Theme.qml la lee y anima el cambio.
//
// Mapeo (probado para que no quede "pastel"):
//   base / paneles  ← base16 base00 de matugen (el oscuro dominante del fondo, estilo pywal)
//   acento          ← paleta primaria, tono 70 (vivo)      · texto sobre acento ← tono 10
//   acento 2        ← paleta terciaria, tono 70
//   texto / tenue   ← neutral 95 / neutral variante 70
Singleton {
    id: root

    property bool auto: true
    property string source: ""              // fondo del que salen los colores actuales
    property bool busy: false
    readonly property string file: Quickshell.env("HOME") + "/.local/state/quickshell/colors.json"
    property var last: null                 // último bloque de colores generado

    function setAuto(on) {
        auto = on;
        if (on) generate(Wallpaper.current); else save();
    }

    Connections {
        target: Wallpaper
        function onCurrentChanged() { if (root.auto && root._loaded) root.generate(Wallpaper.current); }
    }

    // ───── Generar ─────
    property string _pending: ""
    function generate(path) {
        if (!path || (path === source && last)) return;
        if (gen.running) { _pending = path; return; }
        busy = true;
        gen.forPath = path;
        gen.command = ["sh", "-c", 'cd /tmp && exec matugen image "$1" -m dark -j hex --dry-run --prefer saturation -b wal -q',
                       "sh", path];
        gen.running = true;
    }
    Process {
        id: gen
        property string forPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                try {
                    const c = root.map(JSON.parse(text));
                    root.last = c;
                    root.source = gen.forPath;
                    root.save();
                } catch (e) {
                    console.warn("ThemeEngine: no se pudo generar la paleta de", gen.forPath, e);
                }
                if (root._pending) { const p = root._pending; root._pending = ""; root.generate(p); }
            }
        }
    }

    // ───── Mapeo matugen → colores del escritorio ─────
    function hex2rgb(h) { h = h.replace("#", ""); return [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16)); }
    function rgb2hex(c) { return "#" + c.map(v => ("0" + Math.round(Math.max(0, Math.min(255, v))).toString(16)).slice(-2)).join(""); }
    function mix(a, b, t) { return a.map((v, i) => v * (1 - t) + b[i] * t); }
    function lum(c) { return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255; }

    function map(j) {
        const P = j.palettes;
        const tone = (pal, n) => P[pal][String(n)].color;
        let base = hex2rgb(j.base16.base00.dark.color);
        // Fondos claros: oscurecer la base para que los paneles sigan siendo legibles
        while (lum(base) > 0.07) base = mix(base, [0, 0, 0], 0.35);
        const solid = mix(base, [255, 255, 255], 0.04);
        return {
            base: rgb2hex(base),
            bgSolid: rgb2hex(solid),
            fg: tone("neutral", 95),
            dim: tone("neutral_variant", 70),
            accent: tone("primary", 70),
            accent2: tone("tertiary", 70),
            textOnAccent: tone("primary", 10)
        };
    }

    // ───── Guardar / cargar ─────
    function save() {
        out.setText(JSON.stringify({ auto, source, colors: last }, null, 2));
        if (last) labwcTimer.restart();
    }
    // labwc (bordes, menús, Alt+Tab, vista previa al ajustar ventanas) sigue la misma paleta.
    // Margen para que colors.json ya esté escrito cuando el script lo lea.
    Timer {
        id: labwcTimer
        interval: 400
        onTriggered: Quickshell.execDetached(["python3", "-I", Quickshell.shellDir + "/scripts/labwc-theme.py"])
    }
    property bool _loaded: false
    FileView {
        id: out
        path: root.file
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.auto = s.auto ?? true;
                root.source = s.source ?? "";
                root.last = s.colors ?? null;
            } catch (e) {}
            root._loaded = true;
            root._initial();
        }
        onLoadFailed: { root._loaded = true; root._initial(); }
    }
    // Al arrancar: si el fondo actual no es del que salieron los colores, regenerar
    function _initial() {
        if (auto && Wallpaper.current && Wallpaper.current !== source) generate(Wallpaper.current);
    }
}
