import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services
import qs.widgets
import "../../services/clipdetect.js" as Detect
import "../../services/cliptransforms.js" as Transforms

// Historial del portapapeles (Super+V).
// Escribe para buscar · ↑↓ moverse · Tab filtros · Enter pega · Shift+Enter solo copia
// Ctrl+P fijar · Supr borrar (con el cursor al final) · Ctrl+Shift+Supr vaciar · Esc borra / cierra
// → o Ctrl+K: acciones (transformar y pegar) · ↑↓ elegir · Enter pegar resultado · ← o Esc volver
PanelWindow {
    id: panel

    property bool shown: false
    visible: shown
    screen: Ui.popupScreen ?? Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-clipboard"
    WlrLayershell.keyboardFocus: Ui.clipboardOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    property string query: ""
    property string filter: "all"
    property string targetApp: ""          // app activa al abrir: ahí se pega
    property bool confirmWipe: false

    // ───── Acciones (fase 3) ─────
    property bool actionsOpen: false
    property string actionQuery: ""
    property string savedQuery: ""
    property int actionIndex: 0
    readonly property bool canTransform: current !== null && !current.isImage
        && Clipboard.previewText !== "" && Clipboard.previewText.length < 60000
    readonly property var actions: actionsOpen && canTransform
        ? Transforms.forEntry(current.kind, Clipboard.previewText, actionQuery) : []
    readonly property var currentAction: actions[actionIndex] ?? null
    readonly property var actionResult: currentAction
        ? Transforms.apply(currentAction, Clipboard.previewText, { home: Quickshell.env("HOME") }) : null

    // Abrir el panel directamente en el menú de acciones de lo último copiado
    property bool pendingActions: false
    function openTransform() {
        pendingActions = true;
        if (!Ui.clipboardOpen) { Ui.clipboardOpen = true; return; }
        // Panel ya abierto (o recién creado por la carga perezosa): seleccionar y abrir las acciones
        selectLatest();
        if (canTransform) { pendingActions = false; openActions(); }
    }
    // "transform": seleccionar lo último copiado (aunque haya fijados encima)
    function selectLatest() {
        if (pendingActions && Clipboard.history.length > 0) {
            const key = Clipboard.history[0].key;
            const i = results.findIndex(e => e.key === key);
            if (i >= 0) list.currentIndex = i;
        }
    }
    onCanTransformChanged: if (pendingActions && canTransform) { pendingActions = false; openActions(); }

    function openActions() {
        if (!canTransform) return;
        savedQuery = search.text;
        actionsOpen = true;
        actionIndex = 0;
        search.text = "";
    }
    function closeActions() {
        actionsOpen = false;
        actionQuery = "";
        search.text = savedQuery;
        search.cursorPosition = search.text.length;
    }
    function applyAction(paste) {
        const r = actionResult;
        if (!r || r.error) return;
        Ui.clipboardOpen = false;
        if (r.open) Quickshell.execDetached(r.open);
        else Clipboard.useText(r.text, paste, targetApp);
    }

    // Cuántas entradas hay en cada filtro (para las pestañas)
    readonly property var counts: {
        const c = {};
        for (const f of Detect.FILTERS) c[f.id] = 0;
        for (const e of Clipboard.entries)
            for (const f of Detect.FILTERS) if (Detect.matches(f.id, e)) c[f.id]++;
        return c;
    }

    // Filtro + búsqueda: primero lo que contiene el texto (por recencia), luego lo difuso
    readonly property var results: {
        const list = Clipboard.entries.filter(e => Detect.matches(filter, e));
        const q = Apps.norm(query.trim());
        if (!q) return list;
        const exact = [], fuzzy = [];
        for (const e of list) {
            const t = Apps.norm((e.isImage ? "imagen " + e.info : e.preview) + " " + Detect.info(e.kind).label
                                + " " + Clipboard.appName(e.app));
            if (t.includes(q)) exact.push(e);
            else if (Apps.fuzzy(t, q) > q.length * 2) fuzzy.push(e);
        }
        return exact.concat(fuzzy);
    }
    readonly property var current: results[list.currentIndex] ?? null
    onCurrentChanged: Clipboard.loadPreview(current)

    function activate(paste) {
        const e = current;
        if (!e) return;
        Ui.clipboardOpen = false;
        Clipboard.use(e, paste, targetApp);
    }

    function moveFilter(delta) {
        const ids = Detect.FILTERS.map(f => f.id);
        filter = ids[(ids.indexOf(filter) + delta + ids.length) % ids.length];
        list.currentIndex = 0;
        list.positionViewAtBeginning();
    }

    // Color CSS (#hex, rgb(), hsl()) → color de Qt
    function cssColor(t) {
        t = (t || "").trim();
        if (t.startsWith("#")) {
            let h = t.slice(1);
            if (h.length <= 4) h = h.split("").map(c => c + c).join("");
            // CSS es #RRGGBBAA; Qt espera #AARRGGBB
            return h.length === 8 ? "#" + h.slice(6) + h.slice(0, 6) : "#" + h;
        }
        const n = (t.match(/[\d.]+%?/g) || []).map(v => v.endsWith("%") ? parseFloat(v) / 100 : parseFloat(v));
        if (/^rgb/i.test(t)) return Qt.rgba(n[0] / 255, n[1] / 255, n[2] / 255, n.length > 3 ? n[3] : 1);
        if (/^hsl/i.test(t)) return Qt.hsla(n[0] / 360, n[1], n[2], n.length > 3 ? n[3] : 1);
        return "transparent";
    }

    // ───── Abrir / cerrar ─────
    // Carga perezosa (shell.qml): el panel se crea ya abierto → ejecutar la apertura al crearse
    Component.onCompleted: if (Ui.clipboardOpen) uiConn.onClipboardOpenChanged()
    Connections {
        id: uiConn
        target: Ui
        function onClipboardOpenChanged() {
            if (Ui.clipboardOpen) {
                panel.targetApp = ToplevelManager.activeToplevel?.appId ?? "";
                panel.confirmWipe = false;
                panel.actionsOpen = false;
                panel.actionQuery = "";
                panel.savedQuery = "";
                panel.filter = "all";
                search.text = "";
                Clipboard.refresh();
                list.currentIndex = 0;
                list.positionViewAtBeginning();
                panel.selectLatest();
                Clipboard.loadPreview(panel.current);
                panel.shown = true;
                fade.from = root.opacity; fade.to = 1; fade.restart();
                search.forceActiveFocus();
            } else {
                panel.pendingActions = false;
                fade.from = root.opacity; fade.to = 0; fade.restart();
            }
        }
    }

    Timer { id: wipeTimer; interval: 3000; onTriggered: panel.confirmWipe = false }

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
            onFinished: if (!Ui.clipboardOpen) panel.shown = false
        }

        // Fondo oscurecido; clic fuera = cerrar
        Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.base, 0.55) }
        MouseArea { anchors.fill: parent; onClicked: Ui.clipboardOpen = false }

        // ───── Tarjeta ─────
        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(1100, parent.width - 120)
            height: Math.min(680, parent.height - 120)
            radius: 26
            color: Theme.bgSolid
            border.width: 1
            border.color: Theme.border
            transform: Translate { y: (1 - root.opacity) * 20 }

            MouseArea { anchors.fill: parent }    // no cerrar al hacer clic dentro

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                // ───── Buscador ─────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 50
                    radius: 25
                    color: Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1
                    border.color: search.activeFocus ? Qt.alpha(Theme.accent, 0.5) : Qt.rgba(1, 1, 1, 0.1)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 16
                        spacing: 12

                        BarText {
                            text: panel.actionsOpen ? String.fromCodePoint(0xF0674) : String.fromCodePoint(0xF0147)   // varita / portapapeles
                            font.pixelSize: 20
                            color: Theme.accent
                        }

                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 16
                            selectionColor: Theme.accent
                            clip: true
                            onTextChanged: {
                                if (panel.actionsOpen) { panel.actionQuery = text; panel.actionIndex = 0; return; }
                                panel.query = text; list.currentIndex = 0; list.positionViewAtBeginning();
                            }

                            BarText {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: search.text === ""
                                text: panel.actionsOpen ? "Filtrar acciones…  (camel, json, base64, abrir…)" : "Buscar en el portapapeles…"
                                color: Qt.rgba(1, 1, 1, 0.4)
                                font.pixelSize: 16
                            }

                            Keys.onPressed: event => {
                                const ctrl = event.modifiers & Qt.ControlModifier;
                                const shift = event.modifiers & Qt.ShiftModifier;

                                // Menú de acciones abierto
                                if (panel.actionsOpen) {
                                    switch (event.key) {
                                    case Qt.Key_Escape:
                                        if (search.text) search.text = ""; else panel.closeActions();
                                        break;
                                    case Qt.Key_Left:
                                        if (search.cursorPosition > 0) return;
                                        panel.closeActions();
                                        break;
                                    case Qt.Key_Down: panel.actionIndex = Math.min(panel.actions.length - 1, panel.actionIndex + 1); break;
                                    case Qt.Key_Up: panel.actionIndex = Math.max(0, panel.actionIndex - 1); break;
                                    case Qt.Key_PageDown: panel.actionIndex = Math.min(panel.actions.length - 1, panel.actionIndex + 6); break;
                                    case Qt.Key_PageUp: panel.actionIndex = Math.max(0, panel.actionIndex - 6); break;
                                    case Qt.Key_Return:
                                    case Qt.Key_Enter:
                                        panel.applyAction(!shift);
                                        break;
                                    case Qt.Key_Tab:
                                    case Qt.Key_Backtab:
                                        break;
                                    default: return;
                                    }
                                    event.accepted = true;
                                    return;
                                }

                                switch (event.key) {
                                case Qt.Key_Escape:
                                    if (search.text) search.text = ""; else Ui.clipboardOpen = false;
                                    break;
                                case Qt.Key_Return:
                                case Qt.Key_Enter:
                                    panel.activate(!shift);
                                    break;
                                case Qt.Key_Down: list.incrementCurrentIndex(); break;
                                case Qt.Key_Up: list.decrementCurrentIndex(); break;
                                case Qt.Key_PageDown: list.currentIndex = Math.min(list.count - 1, list.currentIndex + 8); break;
                                case Qt.Key_PageUp: list.currentIndex = Math.max(0, list.currentIndex - 8); break;
                                case Qt.Key_Tab: panel.moveFilter(1); break;
                                case Qt.Key_Right:
                                    if (search.cursorPosition < search.text.length) return;
                                    panel.openActions();
                                    break;
                                case Qt.Key_K:
                                    if (!ctrl) return;
                                    panel.openActions();
                                    break;
                                case Qt.Key_Backtab: panel.moveFilter(-1); break;
                                case Qt.Key_P:
                                    if (!ctrl) return;
                                    Clipboard.togglePin(panel.current);
                                    break;
                                case Qt.Key_Delete:
                                    if (ctrl && shift) {
                                        if (panel.confirmWipe) { panel.confirmWipe = false; Clipboard.wipe(); }
                                        else { panel.confirmWipe = true; wipeTimer.restart(); }
                                    } else if (search.cursorPosition === search.text.length && panel.current) {
                                        const i = list.currentIndex;
                                        Clipboard.remove(panel.current);
                                        list.currentIndex = Math.min(i, panel.results.length - 1);
                                    } else return;
                                    break;
                                default: return;
                                }
                                event.accepted = true;
                            }
                        }

                        Rectangle {
                            visible: Clipboard.paused
                            implicitWidth: pausedText.implicitWidth + 20
                            implicitHeight: 26
                            radius: 13
                            color: Qt.rgba(1, 0.82, 0.4, 0.15)
                            BarText {
                                id: pausedText
                                anchors.centerIn: parent
                                text: Icons.eyeOff + "  En pausa"
                                color: Theme.yellow
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: true
                            }
                        }
                        BarText {
                            text: panel.results.length + " de " + Clipboard.entries.length
                            color: Theme.dim
                            font.pixelSize: Theme.fontSize - 1
                        }
                    }
                }

                // ───── Filtros (Tab) ─────
                Row {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: Detect.FILTERS
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool on: panel.filter === modelData.id
                            readonly property int count: panel.counts[modelData.id] ?? 0
                            visible: on || count > 0 || modelData.id === "all"
                            width: visible ? chipRow.implicitWidth + 24 : 0
                            height: 32
                            radius: 16
                            color: on ? Theme.accent : chipArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            RowLayout {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 6
                                BarText { text: String.fromCodePoint(chip.modelData.icon); font.pixelSize: 14; color: chip.on ? Theme.textOnAccent : Theme.fg }
                                BarText { text: chip.modelData.label; font.pixelSize: Theme.fontSize - 1; font.bold: chip.on; color: chip.on ? Theme.textOnAccent : Theme.fg }
                                BarText { text: chip.count; font.pixelSize: Theme.fontSize - 3; color: chip.on ? Qt.rgba(0.1, 0.06, 0.02, 0.7) : Theme.dim }
                            }
                            MouseArea {
                                id: chipArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { panel.filter = chip.modelData.id; list.currentIndex = 0; search.forceActiveFocus(); }
                            }
                        }
                    }
                }

                // ───── Lista + vista previa ─────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 14

                    ListView {
                        id: list
                        Layout.preferredWidth: 430
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: panel.results
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 0
                        currentIndex: 0

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool selected: ListView.isCurrentItem
                            readonly property var kindInfo: Detect.info(modelData.kind)
                            readonly property bool hovered: rowArea.containsMouse || pinArea.containsMouse || delArea.containsMouse
                            width: ListView.view.width
                            implicitHeight: 50
                            radius: 14
                            color: selected ? Qt.alpha(Theme.accent, 0.16)
                                 : hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                            border.width: selected ? 1 : 0
                            border.color: Qt.alpha(Theme.accent, 0.5)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 10

                                // Tipo: icono en un cuadrado de su color (o la muestra del color)
                                Rectangle {
                                    implicitWidth: 30
                                    implicitHeight: 30
                                    radius: 9
                                    color: row.modelData.kind === "color" ? panel.cssColor(row.modelData.preview)
                                         : Qt.alpha(row.kindInfo.color, 0.16)
                                    border.width: row.modelData.kind === "color" ? 1 : 0
                                    border.color: Qt.rgba(1, 1, 1, 0.25)
                                    BarText {
                                        anchors.centerIn: parent
                                        visible: row.modelData.kind !== "color"
                                        text: Detect.glyph(row.modelData.kind)
                                        color: row.kindInfo.color
                                        font.pixelSize: 15
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    BarText {
                                        Layout.fillWidth: true
                                        text: row.modelData.isImage ? "Imagen · " + row.modelData.info
                                                                    : row.modelData.preview.replace(/\s+/g, " ").trim()
                                        font.pixelSize: Theme.fontSize - 1
                                        color: row.selected ? Theme.fg : Qt.rgba(0.9, 0.93, 0.97, 0.85)
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                    BarText {
                                        Layout.fillWidth: true
                                        text: [row.kindInfo.label, Clipboard.appName(row.modelData.app), Detect.ago(row.modelData.time)]
                                              .filter(s => s).join(" · ")
                                        font.pixelSize: Theme.fontSize - 3
                                        color: Theme.dim
                                        elide: Text.ElideRight
                                    }
                                }

                                // Fijar (siempre visible si está fijado)
                                Rectangle {
                                    visible: row.modelData.pinned || row.hovered
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    radius: 14
                                    color: pinArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                    BarText {
                                        anchors.centerIn: parent
                                        text: row.modelData.pinned ? String.fromCodePoint(0xF0403) : String.fromCodePoint(0xF0931)
                                        font.pixelSize: 15
                                        color: row.modelData.pinned ? Theme.accent : Theme.dim
                                    }
                                    MouseArea {
                                        id: pinArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { search.forceActiveFocus(); Clipboard.togglePin(row.modelData); }
                                    }
                                }
                                // Borrar
                                Rectangle {
                                    visible: row.hovered
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    radius: 14
                                    color: delArea.containsMouse ? Qt.rgba(1, 0.36, 0.36, 0.2) : "transparent"
                                    BarText {
                                        anchors.centerIn: parent
                                        text: Icons.trash
                                        font.pixelSize: 14
                                        color: delArea.containsMouse ? Theme.red : Theme.dim
                                    }
                                    MouseArea {
                                        id: delArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { search.forceActiveFocus(); Clipboard.remove(row.modelData); }   // foco antes: la fila se destruye
                                    }
                                }
                            }

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                anchors.rightMargin: 72
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    list.currentIndex = row.index;
                                    panel.activate(!(mouse.modifiers & Qt.ShiftModifier));
                                }
                            }
                        }

                        // Vacío
                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: list.count === 0
                            spacing: 8
                            BarText { Layout.alignment: Qt.AlignHCenter; text: String.fromCodePoint(0xF0147); font.pixelSize: 44; color: Qt.rgba(1, 1, 1, 0.2) }
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                text: panel.query ? "Nada coincide con «" + panel.query + "»"
                                    : panel.filter === "pinned" ? "Sin fijados · Ctrl+P fija la entrada seleccionada"
                                    : "Nada por aquí todavía"
                                color: Theme.dim
                            }
                        }
                    }

                    // ───── Vista previa ─────
                    Rectangle {
                        id: previewBox
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 18
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)
                        clip: true

                        readonly property var e: panel.current
                        readonly property bool isColor: e?.kind === "color"

                        // Cabecera: tipo · app · hora · fijado
                        RowLayout {
                            id: previewHeader
                            visible: previewBox.e !== null
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 8
                            Rectangle {
                                implicitWidth: kindRow.implicitWidth + 18
                                implicitHeight: 26
                                radius: 13
                                color: Qt.alpha(Detect.info(previewBox.e?.kind).color, 0.16)
                                RowLayout {
                                    id: kindRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    BarText { text: Detect.glyph(previewBox.e?.kind); color: Detect.info(previewBox.e?.kind).color; font.pixelSize: 13 }
                                    BarText { text: Detect.info(previewBox.e?.kind).label; color: Detect.info(previewBox.e?.kind).color; font.pixelSize: Theme.fontSize - 2; font.bold: true }
                                }
                            }
                            BarText {
                                visible: !!previewBox.e?.pinned
                                text: String.fromCodePoint(0xF0403) + " Fijado"
                                color: Theme.accent
                                font.pixelSize: Theme.fontSize - 2
                            }
                            Item { Layout.fillWidth: true }
                            BarText {
                                text: [Clipboard.appName(previewBox.e?.app), Detect.ago(previewBox.e?.time)].filter(s => s).join(" · ")
                                color: Theme.dim
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }

                        // Muestra grande de color
                        ColumnLayout {
                            visible: previewBox.isColor
                            anchors.centerIn: parent
                            spacing: 14
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 180
                                implicitHeight: 180
                                radius: 28
                                color: panel.cssColor(Clipboard.previewText)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.2)
                            }
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Clipboard.previewText.trim()
                                font.pixelSize: 20
                                font.bold: true
                            }
                        }

                        // Imagen
                        Image {
                            anchors.fill: parent
                            anchors.margins: 16
                            anchors.topMargin: 52
                            anchors.bottomMargin: 44
                            visible: previewBox.e?.isImage ?? false
                            source: visible && Clipboard.previewImage ? "file://" + Clipboard.previewImage : ""
                            fillMode: Image.PreserveAspectFit
                            // Decodificar al tamaño del recuadro, no a resolución completa:
                            // una captura 1920x1080 serían ~8 MB de textura por selección
                            // (la iGPU Intel usa la RAM del sistema). Qt mantiene la proporción.
                            sourceSize: Qt.size(Math.round(width), Math.round(height))
                            asynchronous: true
                            cache: false
                            smooth: true
                        }

                        // Texto
                        Flickable {
                            id: textFlick
                            anchors.fill: parent
                            anchors.margins: 16
                            anchors.topMargin: 52
                            anchors.bottomMargin: 44
                            visible: previewBox.e !== null && !previewBox.e.isImage && !previewBox.isColor
                            contentWidth: width
                            contentHeight: previewText.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            TextEdit {
                                id: previewText
                                width: textFlick.width
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                textFormat: TextEdit.PlainText
                                text: Clipboard.previewText
                                color: Theme.fg
                                selectionColor: Theme.accent
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                            }
                        }

                        // ───── Menú de acciones (→) ─────
                        Rectangle {
                            id: actionsView
                            anchors.fill: parent
                            visible: panel.actionsOpen
                            radius: parent.radius
                            color: Theme.bgSolid
                            z: 5

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                ListView {
                                    id: actionList
                                    Layout.preferredWidth: 290
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 2
                                    model: panel.actions
                                    currentIndex: panel.actionIndex
                                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                                    highlightMoveDuration: 0
                                    boundsBehavior: Flickable.StopAtBounds
                                    delegate: Item {
                                        id: act
                                        required property var modelData
                                        required property int index
                                        readonly property bool selected: index === panel.actionIndex
                                        // Título del grupo cuando cambia respecto a la fila anterior
                                        readonly property bool header: index === 0 || panel.actions[index - 1]?.group !== modelData.group
                                        width: ListView.view.width
                                        implicitHeight: 34 + (header ? 24 : 0)

                                        BarText {
                                            visible: act.header
                                            anchors { left: parent.left; top: parent.top; leftMargin: 8; topMargin: 8 }
                                            text: act.modelData.group.toUpperCase()
                                            color: Theme.dim
                                            font.pixelSize: Theme.fontSize - 4
                                            font.bold: true
                                            font.letterSpacing: 1.5
                                        }

                                        Rectangle {
                                            id: actBg
                                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                            height: 34
                                            radius: 10
                                            color: act.selected ? Qt.alpha(Theme.accent, 0.16)
                                                 : actArea.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                                        }
                                        RowLayout {
                                            anchors.fill: actBg
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 8
                                            spacing: 9
                                            BarText {
                                                text: String.fromCodePoint(act.modelData.icon)
                                                color: act.selected ? Theme.accent : Theme.dim
                                                font.pixelSize: 14
                                            }
                                            BarText {
                                                Layout.fillWidth: true
                                                text: act.modelData.label
                                                font.pixelSize: Theme.fontSize - 1
                                                font.bold: act.selected
                                                elide: Text.ElideRight
                                            }
                                            BarText {
                                                visible: !!act.modelData.opens
                                                text: Icons.openExternal
                                                color: Theme.dim
                                                font.pixelSize: 12
                                            }
                                        }
                                        MouseArea {
                                            id: actArea
                                            anchors.fill: actBg
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: panel.actionIndex = act.index
                                            onClicked: mouse => panel.applyAction(!(mouse.modifiers & Qt.ShiftModifier))
                                        }
                                    }

                                    BarText {
                                        anchors.centerIn: parent
                                        visible: actionList.count === 0
                                        text: "Sin acciones para «" + panel.actionQuery + "»"
                                        color: Theme.dim
                                    }
                                }

                                // Resultado en vivo
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 14
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    border.width: 1
                                    border.color: panel.actionResult?.error ? Qt.rgba(1, 0.36, 0.36, 0.5) : Qt.rgba(1, 1, 1, 0.06)

                                    BarText {
                                        id: resultTitle
                                        anchors { left: parent.left; top: parent.top; margins: 14 }
                                        text: panel.actionResult?.error ? "No se puede aplicar"
                                            : panel.actionResult?.open ? "Se abrirá" : "Resultado"
                                        color: panel.actionResult?.error ? Theme.red : Theme.accent
                                        font.pixelSize: Theme.fontSize - 2
                                        font.bold: true
                                    }

                                    Flickable {
                                        id: resultFlick
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        anchors.topMargin: 38
                                        anchors.bottomMargin: 34
                                        contentWidth: width
                                        contentHeight: resultText.implicitHeight
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        TextEdit {
                                            id: resultText
                                            width: resultFlick.width
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: TextEdit.WrapAnywhere
                                            textFormat: TextEdit.PlainText
                                            text: {
                                                const r = panel.actionResult;
                                                if (!r) return "";
                                                if (r.error) return r.error;
                                                if (r.open) return r.open[r.open.length - 1];
                                                return r.text.length > 20000 ? r.text.slice(0, 20000) + "\n…" : r.text;
                                            }
                                            color: panel.actionResult?.error ? Theme.red : Theme.fg
                                            selectionColor: Theme.accent
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize
                                        }
                                    }

                                    BarText {
                                        anchors { left: parent.left; bottom: parent.bottom; margins: 14 }
                                        visible: !!panel.actionResult?.text
                                        text: (panel.actionResult?.text?.length ?? 0) + " caracteres"
                                        color: Theme.dim
                                        font.pixelSize: Theme.fontSize - 2
                                    }
                                }
                            }
                        }

                        // Pista: hay acciones disponibles
                        Rectangle {
                            visible: !panel.actionsOpen && panel.canTransform
                            anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
                            implicitWidth: hintRow.implicitWidth + 20
                            implicitHeight: 26
                            radius: 13
                            color: hintArea.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.accent, 0.12)
                            RowLayout {
                                id: hintRow
                                anchors.centerIn: parent
                                spacing: 6
                                BarText { text: String.fromCodePoint(0xF0674); color: Theme.accent; font.pixelSize: 13 }
                                BarText { text: "Acciones  →"; color: Theme.accent; font.pixelSize: Theme.fontSize - 2; font.bold: true }
                            }
                            MouseArea {
                                id: hintArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { panel.openActions(); search.forceActiveFocus(); }
                            }
                        }

                        // Pie
                        BarText {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 16
                            text: {
                                const e = previewBox.e;
                                if (!e) return "";
                                if (e.isImage) return "Imagen · " + e.info;
                                const t = Clipboard.previewText;
                                const lines = t ? t.split("\n").length : 0;
                                return t.length + (t.length >= 60000 ? "+" : "") + " caracteres · " + lines + (lines === 1 ? " línea" : " líneas");
                            }
                            color: Theme.dim
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }

                // ───── Ayuda ─────
                BarText {
                    Layout.alignment: Qt.AlignHCenter
                    text: panel.confirmWipe
                        ? "Pulsa Ctrl+Shift+Supr otra vez para VACIAR el historial (los fijados se conservan)"
                        : panel.actionsOpen
                        ? "↑↓ elegir acción · Enter pegar resultado · Shift+Enter solo copiar · escribe para filtrar · ← o Esc volver"
                        : "Enter pegar · Shift+Enter copiar · → acciones · Tab filtros · Ctrl+P fijar · Supr borrar · Ctrl+Shift+Supr vaciar · Esc cerrar"
                    color: panel.confirmWipe ? Theme.red : Qt.rgba(1, 1, 1, 0.35)
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }
}
