pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Capturas de pantalla: estado y operaciones (sin interfaz).
//  1. start()   → congela la pantalla (grim, con y sin puntero) y abre la capa de selección
//  2. finish()  → recorta la región del PNG congelado (ffmpeg), guarda, copia y avisa
//               · con temporizador: cierra la capa, cuenta atrás y captura la pantalla EN VIVO
//               · edit = true: al terminar abre satty sobre el archivo
//  screenNow()  → pantalla completa al instante, sin capa
// Interfaz en modules/screenshot (ScreenshotOverlay, ShotToast, ShotCountdown).
Singleton {
    id: root

    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-shot"
    readonly property string frozenPlain: runDir + "/frozen.png"
    readonly property string frozenCursor: runDir + "/frozen-cursor.png"
    readonly property string frozen: pointer ? frozenCursor : frozenPlain
    readonly property string saveDir: Quickshell.env("HOME") + "/Pictures/Capturas"
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/quickshell/screenshot.json"

    property bool active: false            // capa de selección abierta
    property bool busy: false              // congelando o guardando
    property var screen: null              // ShellScreen que se captura
    property int frozenRev: 0              // cambia en cada congelado (recarga la imagen)
    property var lastRegion: null          // { x, y, w, h } lógicas

    // Opciones (se guardan entre sesiones)
    property int delay: 0                  // 0, 3, 5, 10 s
    property bool pointer: false           // incluir el puntero del ratón
    readonly property var delays: [0, 3, 5, 10]
    function cycleDelay() { delay = delays[(delays.indexOf(delay) + 1) % delays.length]; saveState(); }
    function togglePointer() { pointer = !pointer; saveState(); }

    property int countdown: 0              // segundos restantes del temporizador (0 = no hay)

    // Resultado para el aviso flotante
    property string lastFile: ""
    property int lastW: 0
    property int lastH: 0
    signal saved(string file)
    signal failed(string reason)
    signal colorPicked(string hex)
    signal textCopied(string text)          // OCR
    signal recordingSaved(string file, int seconds)

    function newName() {
        return saveDir + "/captura-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".png";
    }

    // ───── 1. Abrir la herramienta (congela la pantalla con y sin puntero) ─────
    function start(scr) {
        if (active || busy || countdown > 0) return;
        screen = scr ?? Ui.popupScreen ?? Quickshell.screens[0];
        Ui.closeOthers("");                 // que no salgan paneles en la captura
        busy = true;
        freezer.command = ["sh", "-c",
            'mkdir -p "$1" && grim -o "$2" "$3" & grim -c -o "$2" "$4"; s=$?; wait $! && [ $s = 0 ]',
            "sh", runDir, screen.name, frozenPlain, frozenCursor];
        freezer.running = true;
    }
    Process {
        id: freezer
        onExited: code => {
            root.busy = false;
            if (code !== 0) { root.failed("No se pudo capturar la pantalla (grim)"); return; }
            root.frozenRev++;
            root.active = true;
        }
    }

    function cancel() { active = false; }

    // ───── 2. Confirmar (coordenadas lógicas; scale = píxeles reales / lógicos) ─────
    function finish(rect, scale, edit) {
        if (!active) return;
        active = false;
        lastRegion = { x: rect.x, y: rect.y, w: rect.w, h: rect.h };
        saveState();
        if (delay > 0) { _startDelayed(rect, edit); return; }
        const s = scale || 1;
        const x = Math.round(rect.x * s), y = Math.round(rect.y * s);
        const w = Math.max(1, Math.round(rect.w * s)), h = Math.max(1, Math.round(rect.h * s));
        _save(newName(), edit, ["sh", "-c",
            'mkdir -p "$(dirname "$2")" && ffmpeg -loglevel error -y -i "$1" -vf "crop=$3:$4:$5:$6" "$2"',
            "sh", frozen, "$OUT", String(w), String(h), String(x), String(y)]);
    }

    // Toda la pantalla
    function finishFull(edit) {
        if (!active) return;
        active = false;
        if (delay > 0) { _startDelayed(null, edit); return; }
        _save(newName(), edit, ["sh", "-c", 'mkdir -p "$(dirname "$2")" && cp "$1" "$2"', "sh", frozen, "$OUT"]);
    }

    // ───── Temporizador: cuenta atrás y captura EN VIVO (menús, tooltips…) ─────
    property var _pending: null
    function _startDelayed(rect, edit) {
        _pending = { rect, edit };
        countdown = delay;
        countdownTimer.restart();
    }
    function cancelCountdown() { countdown = 0; countdownTimer.stop(); _pending = null; }
    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown > 0) return;
            stop();
            liveShot.restart();             // margen para que desaparezca la cuenta atrás
        }
    }
    Timer {
        id: liveShot
        interval: 250
        onTriggered: {
            const p = root._pending;
            root._pending = null;
            if (!p) return;
            const sc = root.screen ?? Quickshell.screens[0];
            const c = root.pointer ? "-c" : "";
            // grim -g usa coordenadas globales: se suma la posición del monitor
            const geom = p.rect ? (sc.x + p.rect.x) + "," + (sc.y + p.rect.y) + " " + p.rect.w + "x" + p.rect.h : "";
            root._save(root.newName(), p.edit, ["sh", "-c",
                'mkdir -p "$(dirname "$1")"; if [ -n "$3" ]; then grim $4 -g "$3" "$1"; else grim $4 -o "$2" "$1"; fi',
                "sh", "$OUT", sc.name, geom, c]);
        }
    }

    // ───── Pantalla completa al instante (Shift+Print), sin capa ─────
    function screenNow(scr) {
        if (busy || countdown > 0) return;
        const sc = scr ?? Ui.popupScreen ?? Quickshell.screens[0];
        screen = sc;
        const c = pointer ? "-c" : "";
        _save(newName(), false, ["sh", "-c", 'mkdir -p "$(dirname "$1")" && grim $3 -o "$2" "$1"', "sh", "$OUT", sc.name, c]);
    }

    // Guardar + copiar al portapapeles (entra solo en el historial de Super+V) + leer el tamaño.
    // "$OUT" en cmd se sustituye por la ruta final.
    function _save(out, edit, cmd) {
        busy = true;
        saver.out = out;
        saver.edit = !!edit;
        saver.w = 0;
        saver.h = 0;
        saver.command = ["sh", "-c",
            '"$@" || exit 1\n' +
            'wl-copy --type image/png < "$OUT"\n' +
            'ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$OUT" 2>/dev/null',
            "sh"].concat(cmd.map(a => a === "$OUT" ? out : a));
        saver.environment = { OUT: out };
        saver.running = true;
    }
    Process {
        id: saver
        property string out: ""
        property bool edit: false
        property int w: 0
        property int h: 0
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/^(\d+)x(\d+)$/);
                if (m) { saver.w = Number(m[1]); saver.h = Number(m[2]); }
            }
        }
        onExited: code => {
            root.busy = false;
            if (code !== 0) { root.failed("No se pudo guardar la captura"); return; }
            root.lastFile = saver.out;
            root.lastW = saver.w;
            root.lastH = saver.h;
            if (saver.edit) root.edit(saver.out);
            else root.saved(saver.out);
        }
    }

    // ───── Cuentagotas ─────
    function pickColor(hex) {
        active = false;
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", hex]);
        colorPicked(hex);
    }

    // ───── Ventanas (ext-foreign-toplevel-list + grim -T) ─────
    // Al entrar en el modo "Ventana" se capturan todas las ventanas en paralelo (≈125 ms):
    // las miniaturas son fotos reales y funciona aunque la ventana esté tapada por otras.
    property var windows: []                // [{ identifier, app_id, title, file }]
    property bool windowsLoading: false
    function loadWindows() {
        if (winLister.running) return;
        windows = [];
        windowsLoading = true;
        winLister.command = ["sh", "-c", 'rm -f "$2"/win-*.png; python3 -I "$1" --capture "$2"',
                             "sh", Quickshell.shellDir + "/scripts/list-windows.py", runDir];
        winLister.running = true;
    }
    Process {
        id: winLister
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.windows = JSON.parse(text); } catch (e) { root.windows = []; }
                root.windowsLoading = false;
            }
        }
    }
    function pickWindow(i, edit) {
        const w = windows[i];
        if (!w || !active) return;
        active = false;
        _save(newName(), edit, ["sh", "-c", 'mkdir -p "$(dirname "$2")" && cp "$1" "$2"', "sh", w.file, "$OUT"]);
    }

    // ───── OCR: texto de una región → portapapeles (tesseract, 100 % local) ─────
    function ocr(rect, scale) {
        if (!active) return;
        active = false;
        const s = scale || 1;
        const x = Math.round(rect.x * s), y = Math.round(rect.y * s);
        const w = Math.max(1, Math.round(rect.w * s)), h = Math.max(1, Math.round(rect.h * s));
        busy = true;
        // Ampliar ×2 mejora mucho el reconocimiento de texto pequeño de pantalla
        ocrProc.command = ["sh", "-c",
            'ffmpeg -loglevel error -y -i "$1" -vf "crop=$3:$4:$5:$6,scale=iw*2:ih*2:flags=lanczos" "$2" && ' +
            'tesseract "$2" - -l spa+eng --psm 3 2>/dev/null',
            "sh", frozen, runDir + "/ocr.png", String(w), String(h), String(x), String(y)];
        ocrProc.running = true;
    }
    Process {
        id: ocrProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                const t = text.replace(/\f/g, "").replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
                if (!t) { root.failed("No se encontró texto en esa zona"); return; }
                Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", t]);
                root.textCopied(t);
            }
        }
    }

    // ───── Grabación de pantalla (wf-recorder) ─────
    readonly property string videoDir: Quickshell.env("HOME") + "/Videos/Grabaciones"
    property bool recording: false
    property int recSeconds: 0
    property string recFile: ""
    function startRecording(rect) {
        if (recording || recorder.running) return;
        active = false;
        const sc = screen ?? Quickshell.screens[0];
        recFile = videoDir + "/grabacion-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4";
        const area = rect ? ["-g", (sc.x + rect.x) + "," + (sc.y + rect.y) + " " + (rect.w - rect.w % 2) + "x" + (rect.h - rect.h % 2)]
                          : ["-o", sc.name];
        // H.264 por CPU (sin tocar la GPU); "veryfast" para no cargar el sistema
        recorder.command = ["sh", "-c", 'mkdir -p "$1" && shift && exec wf-recorder "$@"', "sh", videoDir,
                            "-y", "-f", recFile, "-c", "libx264", "-p", "preset=veryfast", "-p", "crf=23"].concat(area);
        recStartDelay.restart();            // que la capa desaparezca antes de empezar
    }
    Timer { id: recStartDelay; interval: 300; onTriggered: { root.recSeconds = 0; recorder.running = true; } }
    // SIGINT: wf-recorder cierra el MP4 bien. Si la grabación es "adoptada" (empezó antes de
    // reiniciar Quickshell), se le manda la señal por nombre.
    function stopRecording() {
        if (recorder.running) recorder.signal(2);
        else if (_external) Quickshell.execDetached(["pkill", "-INT", "-x", "wf-recorder"]);
    }
    function toggleRecording() { if (recording) stopRecording(); else startRecording(null); }
    Timer { interval: 1000; repeat: true; running: root.recording; onTriggered: root.recSeconds++ }
    Process {
        id: recorder
        onRunningChanged: if (running) root.recording = true
        onExited: root._recordingEnded()
    }

    function _recordingEnded() {
        recording = false;
        _external = false;
        const f = recFile;
        fileCheck.command = ["sh", "-c", '[ -s "$1" ] && printf "file://%s\\n" "$1" | wl-copy --type text/uri-list && echo ok', "sh", f];
        fileCheck.running = true;
    }

    // ── Adoptar una grabación que sigue viva tras reiniciar Quickshell ──
    property bool _external: false
    Process {
        id: adoptCheck
        running: true
        command: ["sh", "-c",
            'pid=$(pgrep -x wf-recorder | head -1) || exit 0\n' +
            'f=$(tr "\\0" "\\n" < /proc/$pid/cmdline | grep -A1 -x -- -f | tail -1)\n' +
            'printf "%s|%s" "$f" "$(ps -o etimes= -p $pid | tr -d " ")"']
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/^(.+)\|(\d+)$/);
                if (!m) return;
                root.recFile = m[1];
                root.recSeconds = Number(m[2]);
                root._external = true;
                root.recording = true;
            }
        }
    }
    // Mientras la grabación adoptada siga viva, comprobar cada segundo si terminó
    Timer {
        interval: 1000
        repeat: true
        running: root._external
        onTriggered: if (!externalWatch.running) externalWatch.running = true
    }
    Process {
        id: externalWatch
        command: ["pgrep", "-x", "wf-recorder"]
        onExited: code => { if (code !== 0 && root._external) root._recordingEnded(); }
    }

    Process {
        id: fileCheck
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "ok") root.recordingSaved(root.recFile, root.recSeconds);
                else root.failed("La grabación no se pudo guardar");
            }
        }
    }

    // ───── Acciones sobre una captura ─────
    function open(file) { Quickshell.execDetached(["xdg-open", file]); }
    function showInFolder(file) { Quickshell.execDetached([Quickshell.shellDir + "/scripts/show-in-folder.sh", file]); }
    function remove(file) { Quickshell.execDetached(["rm", "-f", "--", file]); }
    // satty edita sobre el mismo archivo (config: ~/.config/satty/config.toml; Enter = copiar + guardar)
    function edit(file) {
        Quickshell.execDetached(["sh", "-c",
            'if command -v satty >/dev/null; then exec satty --filename "$1" --output-filename "$1"; else exec xdg-open "$1"; fi',
            "sh", file]);
    }

    // ───── Estado guardado ─────
    function saveState() { stateView.setText(JSON.stringify({ lastRegion, delay, pointer })); }
    FileView {
        id: stateView
        path: root.stateFile
        printErrors: false
        onLoaded: {
            try {
                const st = JSON.parse(text());
                root.lastRegion = st.lastRegion ?? null;
                root.delay = st.delay ?? 0;
                root.pointer = st.pointer ?? false;
            } catch (e) {}
        }
    }
}
