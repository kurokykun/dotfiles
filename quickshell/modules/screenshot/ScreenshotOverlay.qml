import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.services
import qs.widgets

// Capa de selección de capturas: muestra la pantalla congelada y deja elegir una región.
// Ratón: arrastrar = nueva región · arrastrar dentro = mover · tiradores = redimensionar · doble clic = capturar
// Teclado: Enter capturar (sin región: pantalla completa) · E capturar y editar (satty) · Esc cancelar
//          F pantalla completa · R última región · T temporizador · P puntero · C cuentagotas
//          W elegir ventana · O copiar el texto de la región (OCR) · G grabar (región o pantalla)
//          flechas mover 1 px (Shift: 10) · Ctrl+flechas redimensionar
PanelWindow {
    id: win

    visible: Screenshot.active
    screen: Screenshot.screen ?? Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-screenshot"
    WlrLayershell.keyboardFocus: Screenshot.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "black"

    // ───── Selección (coordenadas lógicas de pantalla) ─────
    property real selX: 0
    property real selY: 0
    property real selW: 0
    property real selH: 0
    readonly property bool hasSel: selW >= 2 && selH >= 2
    property string dragMode: ""          // "" | new | move | n s e w ne nw se sw
    property real pressX: 0
    property real pressY: 0
    property var startSel: null

    // Píxeles reales / lógicos (1 con escala 1; 2 en una pantalla HiDPI a 200 %)
    readonly property real pxScale: frozenImg.implicitWidth > 0 ? frozenImg.implicitWidth / width : 1

    function clearSel() { selX = selY = selW = selH = 0; }
    function setSel(x, y, w, h) {
        // Normalizar (ancho/alto positivos) y limitar a la pantalla
        if (w < 0) { x += w; w = -w; }
        if (h < 0) { y += h; h = -h; }
        x = Math.max(0, Math.min(x, width));
        y = Math.max(0, Math.min(y, height));
        selX = Math.round(x);
        selY = Math.round(y);
        selW = Math.round(Math.min(w, width - x));
        selH = Math.round(Math.min(h, height - y));
    }
    function confirm(edit) {
        if (hasSel) Screenshot.finish({ x: selX, y: selY, w: selW, h: selH }, pxScale, edit);
        else Screenshot.finishFull(edit);
    }

    // ───── Ventana, OCR y grabación ─────
    property bool windowMode: false
    property int winIndex: 0
    property string flash: ""               // aviso breve en la ayuda
    Timer { id: flashTimer; interval: 2200; onTriggered: win.flash = "" }
    function say(t) { flash = t; flashTimer.restart(); }

    function toggleWindowMode() {
        windowMode = !windowMode;
        picking = false;
        if (windowMode) { winIndex = 0; Screenshot.loadWindows(); }
    }
    function doOcr() {
        if (!hasSel) { say("Selecciona primero la zona con texto"); return; }
        Screenshot.ocr({ x: selX, y: selY, w: selW, h: selH }, pxScale);
    }
    function record() {
        Screenshot.startRecording(hasSel ? { x: selX, y: selY, w: selW, h: selH } : null);
    }

    // ───── Cuentagotas ─────
    property bool picking: false
    property real cursorX: -100
    property real cursorY: -100
    property string pickHex: ""
    function updatePick() {
        if (!picking || !colorCanvas.ready) return;
        const px = Math.round(cursorX * pxScale), py = Math.round(cursorY * pxScale);
        const d = colorCanvas.getContext("2d").getImageData(px, py, 1, 1).data;
        pickHex = "#" + [d[0], d[1], d[2]].map(v => ("0" + v.toString(16)).slice(-2)).join("");
    }
    function togglePicking() {
        picking = !picking;
        if (picking) {
            // Posición actual del ratón (la capa la conoce aunque no se haya movido)
            if (mouse.containsMouse) { cursorX = mouse.mouseX; cursorY = mouse.mouseY; }
            else { cursorX = width / 2; cursorY = height / 2; }
            colorCanvas.prepare();
            updatePick();
        }
    }
    function useLast() {
        const r = Screenshot.lastRegion;
        if (r) setSel(r.x, r.y, r.w, r.h);
    }

    // Carga perezosa (shell.qml): la capa se crea ya activa → foco del teclado al crearse
    Component.onCompleted: keys.forceActiveFocus()
    Connections {
        target: Screenshot
        function onActiveChanged() {
            if (!Screenshot.active) return;
            win.clearSel();
            win.dragMode = "";
            win.picking = false;
            win.windowMode = false;
            win.flash = "";
            keys.forceActiveFocus();
        }
    }

    // ───── Pantalla congelada ─────
    Image {
        id: frozenImg
        anchors.fill: parent
        source: Screenshot.frozenRev > 0 ? "file://" + Screenshot.frozen + "?" + Screenshot.frozenRev : ""
        cache: false
        smooth: false
        fillMode: Image.Stretch
    }

    // Copia invisible de la imagen para leer colores (solo se carga al usar el cuentagotas)
    Canvas {
        id: colorCanvas
        property bool ready: false
        property string loadedSrc: ""
        width: frozenImg.implicitWidth
        height: frozenImg.implicitHeight
        opacity: 0
        enabled: false
        function prepare() {
            const src = frozenImg.source.toString();
            if (loadedSrc === src) return;
            ready = false;
            loadedSrc = src;
            loadImage(src);
        }
        onImageLoaded: requestPaint()
        onPaint: {
            if (!isImageLoaded(loadedSrc)) return;
            const ctx = getContext("2d");
            ctx.drawImage(loadedSrc, 0, 0);
            ready = true;
            win.updatePick();
        }
    }

    // Oscurecer todo menos la selección (4 rectángulos alrededor)
    readonly property color shade: Qt.alpha(Theme.base, 0.65)
    Rectangle { color: win.shade; x: 0; y: 0; width: parent.width; height: win.hasSel ? win.selY : parent.height }
    Rectangle { visible: win.hasSel; color: win.shade; x: 0; y: win.selY + win.selH; width: parent.width; height: parent.height - y }
    Rectangle { visible: win.hasSel; color: win.shade; x: 0; y: win.selY; width: win.selX; height: win.selH }
    Rectangle { visible: win.hasSel; color: win.shade; x: win.selX + win.selW; y: win.selY; width: parent.width - x; height: win.selH }

    // Borde de la selección
    Rectangle {
        visible: win.hasSel
        x: win.selX - 1
        y: win.selY - 1
        width: win.selW + 2
        height: win.selH + 2
        color: "transparent"
        border.width: 2
        border.color: Theme.accent
    }

    // Tiradores (esquinas y lados)
    Repeater {
        model: win.hasSel && win.dragMode !== "new" ? ["nw", "n", "ne", "e", "se", "s", "sw", "w"] : []
        delegate: Rectangle {
            required property string modelData
            width: 12
            height: 12
            radius: 6
            color: "white"
            border.width: 2
            border.color: Theme.accent
            x: (modelData.includes("w") ? win.selX : modelData.includes("e") ? win.selX + win.selW : win.selX + win.selW / 2) - 6
            y: (modelData.includes("n") ? win.selY : modelData.includes("s") ? win.selY + win.selH : win.selY + win.selH / 2) - 6
        }
    }

    // Tamaño de la selección
    Rectangle {
        visible: win.hasSel
        x: Math.min(win.selX, win.width - width - 4)
        y: win.selY > 34 ? win.selY - 30 : win.selY + win.selH + 6
        implicitWidth: sizeText.implicitWidth + 16
        implicitHeight: 24
        radius: 8
        color: Qt.alpha(Theme.bgSolid, 0.9)
        BarText {
            id: sizeText
            anchors.centerIn: parent
            text: Math.round(win.selW * win.pxScale) + " × " + Math.round(win.selH * win.pxScale)
            font.pixelSize: Theme.fontSize - 1
            font.bold: true
        }
    }

    // ───── Ratón ─────
    function hitTest(x, y) {
        if (!hasSel) return "new";
        const m = 10;
        const l = Math.abs(x - selX) < m, r = Math.abs(x - (selX + selW)) < m;
        const t = Math.abs(y - selY) < m, b = Math.abs(y - (selY + selH)) < m;
        const inX = x > selX - m && x < selX + selW + m, inY = y > selY - m && y < selY + selH + m;
        if (t && l) return "nw";
        if (t && r) return "ne";
        if (b && l) return "sw";
        if (b && r) return "se";
        if (t && inX) return "n";
        if (b && inX) return "s";
        if (l && inY) return "w";
        if (r && inY) return "e";
        if (x > selX && x < selX + selW && y > selY && y < selY + selH) return "move";
        return "new";
    }
    function cursorFor(mode) {
        switch (mode) {
        case "move": return Qt.SizeAllCursor;
        case "n": case "s": return Qt.SizeVerCursor;
        case "e": case "w": return Qt.SizeHorCursor;
        case "nw": case "se": return Qt.SizeFDiagCursor;
        case "ne": case "sw": return Qt.SizeBDiagCursor;
        }
        return Qt.CrossCursor;
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: win.picking ? Qt.CrossCursor : win.cursorFor(pressed ? win.dragMode : win.hitTest(mouseX, mouseY))

        onPressed: m => {
            if (win.picking) {
                if (m.button === Qt.RightButton) { win.picking = false; return; }
                if (win.pickHex) Screenshot.pickColor(win.pickHex);
                return;
            }
            if (m.button === Qt.RightButton) { win.clearSel(); return; }   // clic derecho: deshacer selección
            win.dragMode = win.hitTest(m.x, m.y);
            win.pressX = m.x;
            win.pressY = m.y;
            win.startSel = { x: win.selX, y: win.selY, w: win.selW, h: win.selH };
            if (win.dragMode === "new") win.setSel(m.x, m.y, 0, 0);
        }
        onPositionChanged: m => {
            if (win.picking) { win.cursorX = m.x; win.cursorY = m.y; win.updatePick(); return; }
            if (!pressed || !win.dragMode) return;
            const dx = m.x - win.pressX, dy = m.y - win.pressY, s = win.startSel;
            switch (win.dragMode) {
            case "new": win.setSel(win.pressX, win.pressY, dx, dy); break;
            case "move":
                win.setSel(Math.max(0, Math.min(s.x + dx, win.width - s.w)),
                           Math.max(0, Math.min(s.y + dy, win.height - s.h)), s.w, s.h);
                break;
            default: {
                let x = s.x, y = s.y, w = s.w, h = s.h;
                if (win.dragMode.includes("w")) { x += dx; w -= dx; }
                if (win.dragMode.includes("e")) w += dx;
                if (win.dragMode.includes("n")) { y += dy; h -= dy; }
                if (win.dragMode.includes("s")) h += dy;
                win.setSel(x, y, w, h);
            }
            }
        }
        onReleased: {
            win.dragMode = "";
            if (!win.hasSel) win.clearSel();
        }
        onDoubleClicked: m => { if (!win.picking && win.hitTest(m.x, m.y) === "move") win.confirm(false); }
    }

    // Muestra del color bajo el cursor (cuentagotas)
    Rectangle {
        visible: win.picking && win.pickHex !== ""
        x: win.cursorX + 18 + width > win.width ? win.cursorX - 18 - width : win.cursorX + 18
        y: win.cursorY + 18 + height > win.height ? win.cursorY - 18 - height : win.cursorY + 18
        implicitWidth: pickRow.implicitWidth + 20
        implicitHeight: 38
        radius: 19
        color: Theme.bgSolid
        border.width: 1
        border.color: Theme.border
        RowLayout {
            id: pickRow
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                implicitWidth: 22
                implicitHeight: 22
                radius: 11
                color: win.pickHex || "transparent"
                border.width: 2
                border.color: "white"
            }
            BarText { text: win.pickHex.toUpperCase(); font.bold: true }
        }
    }

    // ───── Selector de ventanas (W) ─────
    Rectangle {
        anchors.fill: parent
        visible: win.windowMode
        color: Qt.alpha(Theme.base, 0.8)
        MouseArea { anchors.fill: parent; onClicked: win.windowMode = false }   // clic fuera: volver

        BarText {
            anchors.centerIn: parent
            visible: Screenshot.windowsLoading || Screenshot.windows.length === 0
            text: Screenshot.windowsLoading ? "Capturando ventanas…" : "No hay ventanas abiertas"
            color: Theme.dim
            font.pixelSize: Theme.fontSize + 2
        }

        GridView {
            id: winGrid
            anchors.centerIn: parent
            readonly property int cols: Math.max(1, Math.min(4, Screenshot.windows.length))
            width: cols * cellWidth
            height: Math.min(parent.height - 220, Math.ceil(Screenshot.windows.length / cols) * cellHeight)
            cellWidth: 340
            cellHeight: 250
            clip: true
            interactive: contentHeight > height
            model: Screenshot.windows
            currentIndex: win.winIndex

            delegate: Item {
                id: wcell
                required property var modelData
                required property int index
                readonly property bool selected: index === win.winIndex
                width: winGrid.cellWidth
                height: winGrid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 10
                    radius: 18
                    color: wcell.selected ? Qt.alpha(Theme.accent, 0.16) : wArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                    border.width: wcell.selected ? 2 : 1
                    border.color: wcell.selected ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        Image {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            source: "file://" + wcell.modelData.file
                            sourceSize.width: 480
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            IconImage {
                                implicitSize: 20
                                source: Apps.iconFor(DesktopEntries.heuristicLookup(wcell.modelData.app_id))
                            }
                            BarText {
                                Layout.fillWidth: true
                                text: wcell.modelData.title || wcell.modelData.app_id
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: wcell.selected
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                MouseArea {
                    id: wArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: win.winIndex = wcell.index
                    onClicked: Screenshot.pickWindow(wcell.index, false)
                }
            }
        }
    }

    // ───── Barra de herramientas ─────
    Rectangle {
        id: toolbar
        anchors.horizontalCenter: parent.horizontalCenter
        // Abajo, salvo que la selección ocupe esa zona
        y: win.hasSel && win.selY + win.selH > win.height - 110 && win.selY > 110 ? 36 : win.height - height - 36
        implicitWidth: toolRow.implicitWidth + 16
        implicitHeight: 50
        radius: 25
        color: Theme.bgSolid
        border.width: 1
        border.color: Theme.border

        MouseArea { anchors.fill: parent }   // que los clics no lleguen a la selección

        RowLayout {
            id: toolRow
            anchors.centerIn: parent
            spacing: 4

            ToolButton {
                icon: String.fromCodePoint(0xF0A6D)     // md-selection_drag
                label: "Región"
                active: true
                tip: "Arrastra para seleccionar"
            }
            ToolButton {
                icon: Icons.monitor
                label: "Pantalla"
                tip: "Toda la pantalla (F)"
                onClicked: { win.clearSel(); win.confirm(false); }
            }
            ToolButton {
                icon: String.fromCodePoint(0xF05AF)     // md-window_maximize
                label: "Ventana"
                active: win.windowMode
                tip: "Elegir una ventana (W)"
                onClicked: win.toggleWindowMode()
            }
            ToolButton {
                icon: String.fromCodePoint(0xF0459)     // repetir
                label: "Última"
                enabled: Screenshot.lastRegion !== null
                tip: "Repetir la última región (R)"
                onClicked: win.useLast()
            }

            Rectangle { implicitWidth: 1; implicitHeight: 26; color: Theme.border; Layout.leftMargin: 4; Layout.rightMargin: 4 }

            ToolButton {
                icon: Icons.timer
                label: Screenshot.delay > 0 ? Screenshot.delay + " s" : "Sin espera"
                active: Screenshot.delay > 0
                tip: "Temporizador (T): 3, 5 o 10 s"
                onClicked: Screenshot.cycleDelay()
            }
            ToolButton {
                icon: String.fromCodePoint(0xF01C0)     // md-cursor_default
                label: Screenshot.pointer ? "Con puntero" : "Sin puntero"
                active: Screenshot.pointer
                tip: "Incluir el puntero del ratón (P)"
                onClicked: Screenshot.togglePointer()
            }
            ToolButton {
                icon: String.fromCodePoint(0xF020A)     // md-eyedropper
                label: "Color"
                active: win.picking
                tip: "Cuentagotas (C): clic copia el color"
                onClicked: win.togglePicking()
            }

            Rectangle { implicitWidth: 1; implicitHeight: 26; color: Theme.border; Layout.leftMargin: 4; Layout.rightMargin: 4 }

            ToolButton {
                icon: String.fromCodePoint(0xF113D)     // md-text_recognition
                label: "Texto"
                tip: "Copiar el texto de la región (O)"
                onClicked: win.doOcr()
            }
            ToolButton {
                icon: String.fromCodePoint(0xF0EC2)     // md-record_circle
                label: "Grabar"
                tip: "Grabar la región o la pantalla (G)"
                onClicked: win.record()
            }

            Rectangle { implicitWidth: 1; implicitHeight: 26; color: Theme.border; Layout.leftMargin: 4; Layout.rightMargin: 4 }

            ToolButton {
                icon: Icons.pencil
                tip: "Capturar y editar (E)"
                onClicked: win.confirm(true)
            }
            ToolButton {
                icon: Icons.check
                label: win.hasSel ? "Capturar" : "Capturar todo"
                primary: true
                tip: "Enter o doble clic en la región"
                onClicked: win.confirm(false)
            }
            ToolButton {
                icon: Icons.close
                tip: "Cancelar (Esc)"
                onClicked: Screenshot.cancel()
            }
        }
    }

    // Ayuda
    BarText {
        anchors.horizontalCenter: parent.horizontalCenter
        y: toolbar.y > win.height / 2 ? toolbar.y - 26 : toolbar.y + toolbar.height + 8
        text: win.flash !== "" ? win.flash
            : win.windowMode
            ? "Clic o Enter capturar la ventana · E capturar y editar · flechas elegir · Esc o W volver"
            : win.picking
            ? "Clic para copiar el color · clic derecho o C para volver"
            : win.hasSel
            ? "Enter capturar · E capturar y editar · arrastra para mover · tiradores para ajustar · flechas 1 px (Shift 10) · Ctrl+flechas tamaño"
            : "Arrastra para seleccionar · Enter o F pantalla · W ventana · E editar · O texto · G grabar · R última · T temporizador · P puntero · C color · Esc cancelar"
        color: Qt.rgba(1, 1, 1, 0.75)
        font.pixelSize: Theme.fontSize - 2
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.6)
    }

    // ───── Teclado ─────
    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            const shift = event.modifiers & Qt.ShiftModifier;
            const ctrl = event.modifiers & Qt.ControlModifier;
            const step = shift ? 10 : 1;

            // Selector de ventanas
            if (win.windowMode) {
                const n = Screenshot.windows.length, cols = winGrid.cols;
                switch (event.key) {
                case Qt.Key_Escape: case Qt.Key_W: win.windowMode = false; break;
                case Qt.Key_Left: win.winIndex = Math.max(0, win.winIndex - 1); break;
                case Qt.Key_Right: win.winIndex = Math.min(n - 1, win.winIndex + 1); break;
                case Qt.Key_Up: win.winIndex = Math.max(0, win.winIndex - cols); break;
                case Qt.Key_Down: win.winIndex = Math.min(n - 1, win.winIndex + cols); break;
                case Qt.Key_Return: case Qt.Key_Enter: Screenshot.pickWindow(win.winIndex, false); break;
                case Qt.Key_E: Screenshot.pickWindow(win.winIndex, true); break;
                default: return;
                }
                event.accepted = true;
                return;
            }
            const arrow = { [Qt.Key_Left]: [-step, 0], [Qt.Key_Right]: [step, 0], [Qt.Key_Up]: [0, -step], [Qt.Key_Down]: [0, step] }[event.key];
            if (arrow && win.hasSel) {
                if (ctrl) win.setSel(win.selX, win.selY, Math.max(2, win.selW + arrow[0]), Math.max(2, win.selH + arrow[1]));
                else win.setSel(Math.max(0, Math.min(win.selX + arrow[0], win.width - win.selW)),
                                Math.max(0, Math.min(win.selY + arrow[1], win.height - win.selH)), win.selW, win.selH);
                event.accepted = true;
                return;
            }
            switch (event.key) {
            case Qt.Key_Escape: if (win.picking) win.picking = false; else Screenshot.cancel(); break;
            case Qt.Key_Return:
            case Qt.Key_Enter: if (!win.picking) win.confirm(false); break;
            case Qt.Key_E: if (!win.picking) win.confirm(true); break;
            case Qt.Key_F: if (!win.picking) { win.clearSel(); win.confirm(false); } break;
            case Qt.Key_R: win.useLast(); break;
            case Qt.Key_T: Screenshot.cycleDelay(); break;
            case Qt.Key_P: Screenshot.togglePointer(); break;
            case Qt.Key_C: win.togglePicking(); break;
            case Qt.Key_W: win.toggleWindowMode(); break;
            case Qt.Key_O: if (!win.picking) win.doOcr(); break;
            case Qt.Key_G: if (!win.picking) win.record(); break;
            default: return;
            }
            event.accepted = true;
        }
    }

    // ───── Botón de la barra ─────
    component ToolButton: Rectangle {
        id: tb
        property string icon: ""
        property string label: ""
        property string tip: ""
        property bool active: false
        property bool primary: false
        signal clicked()
        opacity: enabled ? 1 : 0.4
        implicitWidth: tbRow.implicitWidth + (label ? 26 : 22)
        implicitHeight: 38
        radius: 19
        color: primary ? (tbArea.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
             : active ? Qt.alpha(Theme.accent, 0.18)
             : tbArea.containsMouse ? Theme.surfaceHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        RowLayout {
            id: tbRow
            anchors.centerIn: parent
            spacing: 7
            BarText { text: tb.icon; font.pixelSize: 16; color: tb.primary ? Theme.textOnAccent : tb.active ? Theme.accent : Theme.fg }
            BarText {
                visible: tb.label !== ""
                text: tb.label
                font.pixelSize: Theme.fontSize - 1
                font.bold: tb.primary || tb.active
                color: tb.primary ? Theme.textOnAccent : tb.active ? Theme.accent : Theme.fg
            }
        }
        MouseArea {
            id: tbArea
            anchors.fill: parent
            enabled: tb.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.clicked()
        }
    }
}
