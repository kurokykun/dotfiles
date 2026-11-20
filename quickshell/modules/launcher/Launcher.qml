import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.services
import qs.widgets
import "calc.js" as Calc

// Lanzador a pantalla completa con el fondo desenfocado.
// Escribe para buscar apps · flechas para moverte · Enter abre · Tab cambia de categoría · Esc borra / cierra.
// Prefijos:  = calculadora · > comando · / archivos · : emoji · ? web
// (las operaciones como "2+2" se detectan solas, sin "=")
PanelWindow {
    id: launcher

    property bool shown: false
    visible: shown
    screen: Ui.popupScreen ?? Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.keyboardFocus: Ui.launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    // ───────────── Categorías ─────────────
    readonly property var categories: [
        { id: "all",      label: "Todas",       icon: Icons.apps,      match: [] },
        { id: "internet", label: "Internet",    icon: Icons.globe,     match: ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging"] },
        { id: "media",    label: "Multimedia",  icon: Icons.musicNote, match: ["AudioVideo", "Audio", "Video", "Music", "Player"] },
        { id: "graphics", label: "Gráficos",    icon: String.fromCodePoint(0xF03D8), match: ["Graphics", "Photography", "2DGraphics", "3DGraphics"] },
        { id: "dev",      label: "Desarrollo",  icon: String.fromCodePoint(0xF0169), match: ["Development", "IDE", "TextEditor"] },
        { id: "games",    label: "Juegos",      icon: Icons.gamepad,   match: ["Game"] },
        { id: "office",   label: "Oficina",     icon: String.fromCodePoint(0xF0219), match: ["Office", "Education", "Science"] },
        { id: "system",   label: "Sistema",     icon: Icons.cog,       match: ["System", "Settings", "Monitor", "PackageManager", "TerminalEmulator", "HardwareSettings"] },
        { id: "utils",    label: "Utilidades",  icon: String.fromCodePoint(0xF1064), match: ["Utility", "Accessories", "FileManager", "FileTools", "Archiving"] }
    ]

    property string category: "all"
    property string query: ""

    function inCategory(e, catId) {
        if (catId === "all") return true;
        const c = categories.find(x => x.id === catId);
        return c ? (e.categories ?? []).some(k => c.match.includes(k)) : true;
    }

    // Solo las categorías que tienen alguna app
    readonly property var visibleCategories: categories.filter(c => c.id === "all" || Apps.all.some(e => inCategory(e, c.id)))

    // ───────────── Modos ─────────────
    readonly property var modes: ({
        "=": { id: "calc",  label: "Calculadora", icon: String.fromCodePoint(0xF00EC) },
        ">": { id: "cmd",   label: "Comando",     icon: String.fromCodePoint(0xF018D) },
        "/": { id: "files", label: "Archivos",    icon: String.fromCodePoint(0xF0968) },
        ":": { id: "emoji", label: "Emoji",       icon: String.fromCodePoint(0xF01F5) },
        "?": { id: "web",   label: "Web",         icon: Icons.globe }
    })
    readonly property var prefixMode: modes[query.charAt(0)] ?? null
    // Una operación escrita sin "=" también activa la calculadora
    readonly property bool autoCalc: prefixMode === null && Calc.looksLikeMath(query)
    readonly property string mode: prefixMode ? prefixMode.id : autoCalc ? "calc" : "apps"
    readonly property var modeInfo: prefixMode ?? (autoCalc ? modes["="] : null)
    readonly property string arg: (prefixMode ? query.slice(1) : query).trim()
    readonly property bool appsMode: mode === "apps"

    readonly property var results: Apps.search(Apps.all.filter(e => inCategory(e, category)), query)

    // Elementos de la lista para los modos que no son de apps:
    // { glyph | icon, title, subtitle, run(alt) }
    readonly property var items: {
        switch (mode) {
        case "calc": {
            if (!arg) return [hint("Escribe una operación", "2+2 · 200*15% · sqrt(2) · 2^10 · sin(pi/2)")];
            const v = Calc.evaluate(arg);
            if (v === null) return [hint("Operación no válida", arg)];
            const r = Calc.format(v);
            return [{ glyph: "=", title: r, subtitle: arg + "   ·   Enter copia el resultado",
                      run: () => copy(r) }];
        }
        case "cmd":
            if (!arg) return [hint("Escribe un comando", "Enter ejecuta · Shift+Enter lo abre en la terminal")];
            return [{ glyph: modes[">"].icon, title: arg, subtitle: "Enter ejecutar · Shift+Enter en la terminal",
                      run: alt => alt ? Quickshell.execDetached(["kitty", "--hold", "sh", "-c", arg])
                                      : Quickshell.execDetached(["sh", "-c", arg]) }];
        case "web":
            if (!arg) return [hint("Escribe lo que quieres buscar", "Se abre en el navegador")];
            return [{ glyph: Icons.globe, title: "Buscar «" + arg + "»", subtitle: "Google · Enter abrir en el navegador",
                      run: () => Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(arg)]) }];
        case "emoji": {
            const words = Apps.norm(arg).split(/\s+/).filter(w => w);
            const list = words.length === 0 ? emojis.slice(0, 120)
                : emojis.filter(e => words.every(w => e[1].includes(w)))
                        // Primero el nombre exacto, luego palabras completas, luego los nombres cortos
                        .map(e => ({ e, s: (e[1] === words.join(" ") ? 0 : e[1].split(" ").some(x => words.includes(x)) ? 1 : 2) * 1000 + e[1].length }))
                        .sort((a, b) => a.s - b.s).map(x => x.e).slice(0, 120);
            if (list.length === 0) return [hint("Sin emojis para «" + arg + "»", "Los nombres están en inglés: heart, fire, smile…")];
            return list.map(e => ({ glyph: e[0], emoji: true, title: e[1], subtitle: "Enter copiar",
                                    run: () => copy(e[0]) }));
        }
        case "files":
            if (arg.length < 2) return [hint("Escribe al menos 2 letras", "Busca en tu carpeta personal · Enter abre · Shift+Enter abre la carpeta")];
            if (fileSearch.running && fileResults.length === 0) return [hint("Buscando…", "")];
            if (fileResults.length === 0) return [hint("No hay archivos con «" + arg + "»", "")];
            return fileResults;
        }
        return [];
    }

    function hint(t, s) { return { glyph: Icons.info, title: t, subtitle: s, run: null }; }
    function copy(t) { Quickshell.execDetached(["wl-copy", "--", t]); Ui.launcherOpen = false; }

    function activate(alt) {
        if (appsMode) { launch(results[grid.currentIndex]); return; }
        const it = items[list.currentIndex];
        if (!it || !it.run) return;
        it.run(alt);
        Ui.launcherOpen = false;
    }

    function launch(e) {
        if (!e) return;
        Ui.launcherOpen = false;
        Apps.launch(e);
    }

    // ───── Emojis (modules/launcher/emoji.json, nombres Unicode) ─────
    property var emojis: []
    FileView {
        path: Quickshell.shellDir + "/modules/launcher/emoji.json"
        onLoaded: { try { launcher.emojis = JSON.parse(text()); } catch (e) {} }
    }

    // ───── Búsqueda de archivos (find en $HOME, sin carpetas ocultas) ─────
    property var fileResults: []
    property string fileQuery: ""         // la consulta que se está ejecutando

    onArgChanged: if (mode === "files") { fileResults = []; fileTimer.restart(); }
    onModeChanged: if (mode === "files") fileTimer.restart();

    Timer {
        id: fileTimer
        interval: 220
        onTriggered: {
            if (launcher.mode !== "files" || launcher.arg.length < 2) return;
            if (fileSearch.running) { fileSearch.running = false; restart(); return; }
            launcher.fileQuery = launcher.arg;
            fileSearch.running = true;
        }
    }

    Process {
        id: fileSearch
        command: ["sh", "-c",
            'find "$HOME" -mindepth 1 -maxdepth 6 \\( -name ".*" -o -name node_modules -o -name __pycache__ \\) -prune ' +
            '-o -iname "*$1*" -printf "%y\\t%p\\n" 2>/dev/null | head -n 400',
            "sh", launcher.fileQuery]
        stdout: StdioCollector {
            onStreamFinished: {
                if (launcher.fileQuery !== launcher.arg) return;   // resultado viejo
                const home = Quickshell.env("HOME");
                const q = Apps.norm(launcher.arg);
                launcher.fileResults = text.split("\n").filter(l => l).map(l => {
                    const tab = l.indexOf("\t");
                    const type = l.slice(0, tab), path = l.slice(tab + 1);
                    const name = path.slice(path.lastIndexOf("/") + 1);
                    const dir = path.slice(0, path.lastIndexOf("/"));
                    return { type, path, name, dir,
                             depth: path.split("/").length,
                             exact: Apps.norm(name).startsWith(q) };
                })
                // Primero los que empiezan por la búsqueda, luego los menos profundos
                .sort((a, b) => (b.exact - a.exact) || (a.depth - b.depth) || a.name.localeCompare(b.name))
                .slice(0, 60)
                .map(f => ({
                    icon: Quickshell.iconPath(launcher.fileIcon(f), "text-x-generic"),
                    title: f.name,
                    subtitle: f.dir.replace(home, "~"),
                    run: alt => Quickshell.execDetached(["xdg-open", alt ? f.dir : f.path])
                }));
            }
        }
    }

    function fileIcon(f) {
        if (f.type === "d") return "folder";
        const ext = (f.name.match(/\.([^.]+)$/)?.[1] ?? "").toLowerCase();
        if (["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "avif"].includes(ext)) return "image-x-generic";
        if (["mp4", "mkv", "webm", "avi", "mov"].includes(ext)) return "video-x-generic";
        if (["mp3", "flac", "ogg", "wav", "m4a", "opus"].includes(ext)) return "audio-x-generic";
        if (ext === "pdf") return "application-pdf";
        if (["zip", "tar", "gz", "xz", "zst", "7z", "rar"].includes(ext)) return "package-x-generic";
        if (["sh", "py", "js", "ts", "qml", "c", "cpp", "rs", "go", "java", "json", "xml", "html", "css"].includes(ext)) return "text-x-script";
        if (["doc", "docx", "odt"].includes(ext)) return "x-office-document";
        if (["xls", "xlsx", "ods", "csv"].includes(ext)) return "x-office-spreadsheet";
        return "text-x-generic";
    }

    // ───────────── Abrir / cerrar ─────────────
    // Carga perezosa (shell.qml): el panel se crea ya abierto → ejecutar la apertura al crearse
    Component.onCompleted: if (Ui.launcherOpen) uiConn.onLauncherOpenChanged()
    Connections {
        id: uiConn
        target: Ui
        function onLauncherOpenChanged() {
            if (Ui.launcherOpen) {
                launcher.query = "";
                launcher.category = "all";
                search.text = "";
                grid.currentIndex = 0;
                grid.positionViewAtBeginning();
                launcher.shown = true;
                fade.from = root.opacity; fade.to = 1; fade.restart();
                search.forceActiveFocus();
            } else {
                fade.from = root.opacity; fade.to = 0; fade.restart();
            }
        }
    }

    // Abrir con texto ya escrito (qs ipc call launcher open "=")
    function openWith(t) {
        Ui.launcherOpen = true;
        search.text = t;
        search.cursorPosition = t.length;
    }

    function moveCategory(delta) {
        const cats = visibleCategories;
        const i = cats.findIndex(c => c.id === category);
        category = cats[(i + delta + cats.length) % cats.length].id;
        grid.currentIndex = 0;
    }

    // ───────────── Interfaz ─────────────
    Item {
        id: root
        anchors.fill: parent
        opacity: 0

        NumberAnimation {
            id: fade
            target: root
            property: "opacity"
            duration: Theme.animNormal
            easing.type: Easing.OutCubic
            onFinished: if (!Ui.launcherOpen) launcher.shown = false
        }

        BlurBackdrop { anchors.fill: parent; darken: 0.5 }

        // Clic en zona vacía = cerrar
        MouseArea {
            anchors.fill: parent
            onClicked: Ui.launcherOpen = false
        }

        ColumnLayout {
            id: content
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 70
            anchors.bottomMargin: 30
            width: Math.min(1180, parent.width - 160)
            spacing: 22

            // Entrada: baja y se aclara
            transform: Translate { y: (1 - root.opacity) * -24 }

            // ───── Buscador ─────
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 620
                implicitHeight: 56
                radius: 28
                color: Qt.rgba(1, 1, 1, 0.09)
                border.width: 1
                border.color: search.activeFocus ? Qt.alpha(Theme.accent, 0.6) : Qt.rgba(1, 1, 1, 0.12)
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 18
                    spacing: 14

                    BarText {
                        text: launcher.modeInfo ? launcher.modeInfo.icon : Icons.search
                        font.pixelSize: 22
                        color: Theme.accent
                    }

                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 19
                        selectByMouse: true
                        selectionColor: Theme.accent
                        clip: true
                        onTextChanged: {
                            launcher.query = text;
                            grid.currentIndex = 0; grid.positionViewAtBeginning();
                            list.currentIndex = 0; list.positionViewAtBeginning();
                        }

                        BarText {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: search.text === ""
                            text: "Buscar aplicaciones…"
                            color: Qt.rgba(1, 1, 1, 0.4)
                            font.pixelSize: 19
                        }

                        Keys.onPressed: event => {
                            const apps = launcher.appsMode;
                            switch (event.key) {
                            case Qt.Key_Escape:
                                if (search.text) search.text = ""; else Ui.launcherOpen = false;
                                break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter:
                                launcher.activate(event.modifiers & Qt.ShiftModifier);
                                break;
                            case Qt.Key_Down: apps ? grid.moveCurrentIndexDown() : list.incrementCurrentIndex(); break;
                            case Qt.Key_Up: apps ? grid.moveCurrentIndexUp() : list.decrementCurrentIndex(); break;
                            case Qt.Key_Right: if (!apps) return; grid.moveCurrentIndexRight(); break;
                            case Qt.Key_Left: if (!apps) return; grid.moveCurrentIndexLeft(); break;
                            case Qt.Key_PageDown:
                                if (apps) grid.currentIndex = Math.min(grid.count - 1, grid.currentIndex + grid.columns * 3);
                                else list.currentIndex = Math.min(list.count - 1, list.currentIndex + 8);
                                break;
                            case Qt.Key_PageUp:
                                if (apps) grid.currentIndex = Math.max(0, grid.currentIndex - grid.columns * 3);
                                else list.currentIndex = Math.max(0, list.currentIndex - 8);
                                break;
                            case Qt.Key_Tab: if (!apps) return; launcher.moveCategory(1); break;
                            case Qt.Key_Backtab: if (!apps) return; launcher.moveCategory(-1); break;
                            default: return;
                            }
                            event.accepted = true;
                        }
                    }

                    // Etiqueta del modo o número de resultados
                    Rectangle {
                        visible: launcher.modeInfo !== null
                        implicitWidth: modeText.implicitWidth + 20
                        implicitHeight: 26
                        radius: 13
                        color: Qt.alpha(Theme.accent, 0.18)
                        BarText {
                            id: modeText
                            anchors.centerIn: parent
                            text: launcher.modeInfo?.label ?? ""
                            color: Theme.accent
                            font.bold: true
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                    BarText {
                        visible: launcher.appsMode && search.text !== ""
                        text: launcher.results.length + (launcher.results.length === 1 ? " resultado" : " resultados")
                        color: Theme.dim
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }

            // ───── Categorías ─────
            Flow {
                visible: launcher.appsMode
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: content.width
                spacing: 8

                Repeater {
                    model: launcher.visibleCategories
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool on: launcher.category === modelData.id
                        width: chipRow.implicitWidth + 28
                        height: 36
                        radius: 18
                        color: on ? Theme.accent : chipArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 7
                            BarText { text: chip.modelData.icon; font.pixelSize: 15; color: chip.on ? Theme.textOnAccent : Theme.fg }
                            BarText {
                                text: chip.modelData.label
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: chip.on
                                color: chip.on ? Theme.textOnAccent : Theme.fg
                            }
                        }
                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { launcher.category = chip.modelData.id; grid.currentIndex = 0; search.forceActiveFocus(); }
                        }
                    }
                }
            }

            // ───── Frecuentes ─────
            ColumnLayout {
                visible: launcher.query === "" && launcher.category === "all" && Apps.frequent.length > 0
                Layout.fillWidth: true
                spacing: 10

                BarText {
                    text: "Frecuentes"
                    color: Theme.dim
                    font.bold: true
                    font.pixelSize: Theme.fontSize - 1
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: Apps.frequent
                        delegate: Rectangle {
                            id: fav
                            required property var modelData
                            Layout.preferredWidth: 128
                            implicitHeight: 64
                            radius: 18
                            color: favArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
                            scale: favArea.pressed ? 0.95 : 1
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on scale { NumberAnimation { duration: Theme.animFast } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10
                                IconImage {
                                    implicitSize: 36
                                    source: Apps.iconFor(fav.modelData)
                                }
                                BarText {
                                    Layout.fillWidth: true
                                    text: fav.modelData.name
                                    font.pixelSize: Theme.fontSize - 2
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                id: favArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: launcher.launch(fav.modelData)
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            // ───── Cuadrícula de apps ─────
            BarText {
                visible: launcher.query === ""
                text: launcher.visibleCategories.find(c => c.id === launcher.category)?.label === "Todas"
                    ? "Todas las aplicaciones" : launcher.visibleCategories.find(c => c.id === launcher.category)?.label ?? ""
                color: Theme.dim
                font.bold: true
                font.pixelSize: Theme.fontSize - 1
                Layout.bottomMargin: -12
            }

            GridView {
                id: grid
                visible: launcher.appsMode
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: launcher.appsMode ? launcher.results : []
                readonly property int columns: Math.max(1, Math.floor(width / 140))
                cellWidth: Math.floor(width / columns)
                cellHeight: 132
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationWraps: false
                currentIndex: 0

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool selected: GridView.isCurrentItem
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 6
                        radius: 22
                        color: cell.selected ? Qt.alpha(Theme.accent, 0.18)
                             : cellArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                        border.width: cell.selected ? 1 : 0
                        border.color: Qt.alpha(Theme.accent, 0.55)
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 20
                        spacing: 8

                        IconImage {
                            Layout.alignment: Qt.AlignHCenter
                            implicitSize: 58
                            source: Apps.iconFor(cell.modelData)
                            scale: cellArea.pressed ? 0.9 : (cellArea.containsMouse || cell.selected) ? 1.08 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }
                        }
                        BarText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData.name
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: cell.selected
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: launcher.launch(cell.modelData)
                    }
                }

                // Sin resultados: sugerir buscar en la web
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: grid.count === 0
                    spacing: 10
                    BarText { Layout.alignment: Qt.AlignHCenter; text: Icons.search; font.pixelSize: 48; color: Qt.rgba(1, 1, 1, 0.2) }
                    BarText { Layout.alignment: Qt.AlignHCenter; text: "No hay aplicaciones que coincidan con «" + launcher.query + "»"; color: Theme.dim }
                    BarText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Escribe «?» delante para buscarlo en la web o «/» para buscar archivos"
                        color: Qt.rgba(1, 1, 1, 0.35)
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }

            // ───── Lista de resultados (calculadora, comandos, archivos, emoji, web) ─────
            ListView {
                id: list
                visible: !launcher.appsMode
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 720
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: launcher.appsMode ? [] : launcher.items
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                currentIndex: 0

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: ListView.isCurrentItem && modelData.run !== null
                    readonly property bool big: launcher.mode === "calc" && modelData.run !== null
                    width: ListView.view.width
                    implicitHeight: big ? 92 : 62
                    radius: 18
                    color: selected ? Qt.alpha(Theme.accent, 0.18)
                         : rowArea.containsMouse && modelData.run ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
                    border.width: selected ? 1 : 0
                    border.color: Qt.alpha(Theme.accent, 0.55)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 16

                        Item {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            IconImage {
                                anchors.centerIn: parent
                                visible: !!row.modelData.icon
                                implicitSize: 36
                                source: row.modelData.icon ?? ""
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !row.modelData.icon
                                text: row.modelData.glyph ?? ""
                                // Los emojis con la fuente de color; el resto con la Nerd Font
                                font.family: row.modelData.emoji ? "Noto Color Emoji" : Theme.font
                                font.pixelSize: row.modelData.emoji ? 30 : 24
                                color: row.modelData.run ? Theme.accent : Theme.dim
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            BarText {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                font.pixelSize: row.big ? 34 : Theme.fontSize + 2
                                font.bold: row.big || row.selected
                                color: row.modelData.run ? Theme.fg : Theme.dim
                                elide: Text.ElideMiddle
                            }
                            BarText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: row.modelData.subtitle ?? ""
                                color: Theme.dim
                                font.pixelSize: Theme.fontSize - 2
                                elide: Text.ElideMiddle
                            }
                        }
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: row.modelData.run ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: mouse => {
                            list.currentIndex = row.index;
                            launcher.activate(mouse.modifiers & Qt.ShiftModifier);
                        }
                    }
                }
            }

            // ───── Ayuda ─────
            BarText {
                Layout.alignment: Qt.AlignHCenter
                text: launcher.appsMode
                    ? "Enter abrir · ↑ ↓ ← → moverse · Tab categorías · Esc cerrar      = calcular · > comando · / archivos · : emoji · ? web"
                    : "Enter " + (launcher.mode === "calc" || launcher.mode === "emoji" ? "copiar" : "abrir")
                      + " · ↑ ↓ moverse · Esc borrar"
                color: Qt.rgba(1, 1, 1, 0.35)
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }
}
