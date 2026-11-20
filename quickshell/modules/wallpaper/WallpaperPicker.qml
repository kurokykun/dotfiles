import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.services
import qs.widgets

// Selector de fondos (Super+W): franja inferior; el escritorio se ve cambiar detrás en vivo.
// Pestañas (Tab): "Mis fondos" (~/Pictures/Wallpapers) y "Wallhaven" (buscar y descargar).
// Mis fondos: ← → elegir (se aplica al detenerse) · Enter aceptar · Esc volver al de antes · R aleatorio
// Wallhaven:  ← → elegir · Enter o clic descargar y aplicar · / buscar · al llegar al final carga más
// T cambia la transición en ambas.
PanelWindow {
    id: picker

    property bool shown: false
    visible: shown
    screen: Ui.popupScreen ?? Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-wallpaper-picker"
    WlrLayershell.keyboardFocus: Ui.wallpaperOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    property string tab: "local"              // local | wallhaven
    readonly property bool wh: tab === "wallhaven"
    property string original: ""              // fondo al abrir (Esc lo restaura)
    property int index: 0
    readonly property var model: wh ? whModel : localModel
    readonly property var transitionNames: ({ circle: "Círculo", fade: "Fundido", zoom: "Zoom", wipe: "Barrido", random: "Aleatoria" })

    function open() {
        original = Wallpaper.current;
        Wallpaper.scan();
        selectCurrent();
        shown = true;
        slide.from = sheet.offset; slide.to = 0; slide.restart();
        keys.forceActiveFocus();
    }
    function close() { slide.from = sheet.offset; slide.to = sheet.height + 40; slide.restart(); }

    function selectCurrent() {
        index = wh ? 0 : Math.max(0, Wallpaper.list.findIndex(w => w.path === Wallpaper.current));
        list.positionViewAtIndex(index, ListView.Center);
    }
    function setTab(t) {
        if (tab === t) return;
        tab = t;
        applyTimer.stop();
        selectCurrent();
        if (wh && !Wallhaven.searched) Wallhaven.search();
        keys.forceActiveFocus();
    }

    Connections {
        target: Ui
        function onWallpaperOpenChanged() { if (Ui.wallpaperOpen) picker.open(); else picker.close(); }
    }
    // ───── Modelos del carrusel ─────
    // ListModel (y no listas JavaScript): añadir resultados o marcar uno como descargado
    // NO reconstruye las tarjetas, así que el carrusel no salta ni parpadea.
    ListModel { id: localModel }
    ListModel { id: whModel }

    function syncLocal() {
        localModel.clear();
        for (const w of Wallpaper.list)
            localModel.append({ filePath: w.path, thumb: w.thumb, name: w.name, wid: "", resolution: "",
                                size: 0, category: "", favorites: 0, local: w.path });
    }
    property int seenGeneration: -1
    function syncWallhaven() {
        const items = Wallhaven.items;
        // Búsqueda nueva (o lista más corta): empezar de cero
        if (Wallhaven.generation !== seenGeneration || items.length < whModel.count) {
            seenGeneration = Wallhaven.generation;
            whModel.clear();
            if (wh) index = 0;
        }
        // Existentes: solo actualizar lo que cambió (p. ej. "descargado")
        for (let i = 0; i < whModel.count; i++)
            if (whModel.get(i).local !== (items[i].local || "")) whModel.setProperty(i, "local", items[i].local || "");
        // Nuevos: añadir al final
        for (let i = whModel.count; i < items.length; i++) {
            const it = items[i];
            whModel.append({ filePath: "", thumb: it.thumb, name: "", wid: it.id, resolution: it.resolution,
                             size: it.size, category: it.category, favorites: it.favorites, local: it.local || "" });
        }
    }
    Connections {
        target: Wallhaven
        function onItemsChanged() { picker.syncWallhaven(); }
    }
    // Carga perezosa (shell.qml): el panel se crea ya abierto → abrir al crearse
    Component.onCompleted: { syncLocal(); syncWallhaven(); if (Ui.wallpaperOpen) open(); }

    Connections {
        target: Wallpaper
        function onListChanged() {
            picker.syncLocal();
            if (picker.wh) return;
            const i = Wallpaper.list.findIndex(w => w.path === Wallpaper.current);
            if (i >= 0) { picker.index = i; list.positionViewAtIndex(i, ListView.Center); }
        }
    }

    // Mis fondos: aplicar al detenerse en una miniatura
    Timer {
        id: applyTimer
        interval: 280
        onTriggered: {
            const w = Wallpaper.list[picker.index];
            if (w) Wallpaper.set(w.path, picker.originOf(picker.index));
        }
    }
    function originOf(i) {
        const item = list.itemAtIndex(i);
        if (!item) return Qt.point(-1, -1);
        const p = item.mapToItem(null, item.width / 2, item.height / 2);
        return Qt.point(p.x, p.y);
    }
    function move(d) {
        const n = model.count;
        if (n === 0) return;
        index = Math.max(0, Math.min(n - 1, index + d));
        list.positionViewAtIndex(index, ListView.Contain);
        if (wh) { if (index >= n - 4) Wallhaven.more(); }   // Wallhaven: no descarga sola (datos)
        else applyTimer.restart();
    }
    function activate(i, origin) {
        if (wh) Wallhaven.apply(Wallhaven.items[i], origin ?? originOf(i));
        else { const w = Wallpaper.list[i]; if (w) Wallpaper.set(w.path, origin ?? originOf(i)); }
    }
    function cycleTransition() {
        const t = Wallpaper.transitions;
        Wallpaper.setTransition(t[(t.indexOf(Wallpaper.transition) + 1) % t.length]);
    }

    // Clic fuera de la franja: cerrar
    MouseArea { anchors.fill: parent; onClicked: Ui.wallpaperOpen = false }

    // ───── Franja inferior ─────
    Rectangle {
        id: sheet
        // Valor fijo (no "height + 40"): si fuera una expresión, al cambiar la altura con las
        // pestañas se recalcularía y la franja se escondería sola
        property real offset: 2000
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 24 + offset
        width: Math.min(parent.width - 48, 1500)
        height: picker.wh ? 352 : 300
        Behavior on height { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        radius: 26
        color: Qt.alpha(Theme.bgSolid, 0.88)
        border.width: 1
        border.color: Theme.border

        NumberAnimation {
            id: slide
            target: sheet; property: "offset"
            duration: Theme.animNormal + 60
            easing.type: Easing.OutCubic
            onFinished: if (!Ui.wallpaperOpen) picker.shown = false
        }
        MouseArea { anchors.fill: parent }       // los clics dentro no cierran

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // ───── Cabecera ─────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Pestañas
                Repeater {
                    model: [
                        { id: "local", label: "Mis fondos", icon: String.fromCodePoint(0xF02E9) },
                        { id: "wallhaven", label: "Wallhaven", icon: Icons.globe }
                    ]
                    delegate: Rectangle {
                        id: tabBtn
                        required property var modelData
                        readonly property bool on: picker.tab === modelData.id
                        implicitWidth: tabRow.implicitWidth + 26
                        implicitHeight: 32
                        radius: 16
                        color: on ? Theme.accent : tabArea.containsMouse ? Theme.surfaceHover : Theme.surface
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        RowLayout {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 7
                            BarText { text: tabBtn.modelData.icon; font.pixelSize: 15; color: tabBtn.on ? Theme.textOnAccent : Theme.fg }
                            BarText {
                                text: tabBtn.modelData.label
                                font.bold: tabBtn.on
                                color: tabBtn.on ? Theme.textOnAccent : Theme.fg
                            }
                        }
                        MouseArea {
                            id: tabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: picker.setTab(tabBtn.modelData.id)
                        }
                    }
                }
                BarText {
                    Layout.leftMargin: 6
                    text: picker.wh
                        ? (Wallhaven.loading && Wallhaven.items.length === 0 ? "buscando…" : Wallhaven.total ? Wallhaven.total + " resultados" : "")
                        : (Wallpaper.scanning ? "buscando…" : Wallpaper.list.length + (Wallpaper.list.length === 1 ? " fondo" : " fondos"))
                    color: Theme.dim
                    font.pixelSize: Theme.fontSize - 1
                }
                Item { Layout.fillWidth: true }

                // Tema automático
                BarText {
                    text: ThemeEngine.busy ? "Generando colores…" : "Tema automático"
                    color: Theme.dim
                    font.pixelSize: Theme.fontSize - 2
                }
                Toggle {
                    checked: ThemeEngine.auto
                    onToggled: { ThemeEngine.setAuto(!ThemeEngine.auto); keys.forceActiveFocus(); }
                }
                Rectangle { implicitWidth: 1; implicitHeight: 22; color: Theme.border; Layout.leftMargin: 4; Layout.rightMargin: 4 }

                // Transición
                Repeater {
                    model: Wallpaper.transitions
                    delegate: Chip {
                        required property string modelData
                        label: picker.transitionNames[modelData]
                        on: Wallpaper.transition === modelData
                        onClicked: { Wallpaper.setTransition(modelData); keys.forceActiveFocus(); }
                    }
                }

                Rectangle { implicitWidth: 1; implicitHeight: 22; color: Theme.border; Layout.leftMargin: 4; Layout.rightMargin: 4 }

                HeaderButton { visible: !picker.wh; icon: String.fromCodePoint(0xF049D); onClicked: Wallpaper.random() }
                HeaderButton { icon: String.fromCodePoint(0xF024B); onClicked: { Quickshell.execDetached(["thunar", Wallpaper.dir]); Ui.wallpaperOpen = false; } }
                HeaderButton { icon: Icons.refresh; onClicked: picker.wh ? Wallhaven.search() : Wallpaper.scan() }
                HeaderButton { icon: Icons.close; onClicked: Ui.wallpaperOpen = false }
            }

            // ───── Wallhaven: búsqueda y filtros ─────
            RowLayout {
                visible: picker.wh
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 300
                    implicitHeight: 34
                    radius: 17
                    color: Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1
                    border.color: searchInput.activeFocus ? Qt.alpha(Theme.accent, 0.6) : Qt.rgba(1, 1, 1, 0.1)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 8
                        BarText { text: Icons.search; color: Theme.accent; font.pixelSize: 15 }
                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            text: Wallhaven.query
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            clip: true
                            selectByMouse: true
                            BarText {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: searchInput.text === ""
                                text: "Buscar en Wallhaven (inglés)…  /"
                                color: Qt.rgba(1, 1, 1, 0.4)
                            }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    Wallhaven.query = searchInput.text;
                                    Wallhaven.search();
                                    keys.forceActiveFocus();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Tab) {
                                    keys.forceActiveFocus();
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }

                Chip { label: "General"; on: Wallhaven.general; onClicked: { Wallhaven.general = !Wallhaven.general; Wallhaven.search(); keys.forceActiveFocus(); } }
                Chip { label: "Anime"; on: Wallhaven.anime; onClicked: { Wallhaven.anime = !Wallhaven.anime; Wallhaven.search(); keys.forceActiveFocus(); } }
                Chip { label: "Personas"; on: Wallhaven.people; onClicked: { Wallhaven.people = !Wallhaven.people; Wallhaven.search(); keys.forceActiveFocus(); } }

                Rectangle { implicitWidth: 1; implicitHeight: 22; color: Theme.border; Layout.leftMargin: 4; Layout.rightMargin: 4 }

                Repeater {
                    model: Wallhaven.sortings
                    delegate: Chip {
                        required property var modelData
                        label: modelData.label
                        on: Wallhaven.sorting === modelData.id
                        onClicked: { Wallhaven.sorting = modelData.id; Wallhaven.search(); keys.forceActiveFocus(); }
                    }
                }

                Item { Layout.fillWidth: true }

                // Datos gastados en esta sesión
                BarText {
                    text: String.fromCodePoint(0xF06F4) + "  " + Wallhaven.fmtBytes(Wallhaven.sessionBytes) + " usados"
                    color: Theme.dim
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            // ───── Carrusel ─────
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                orientation: ListView.Horizontal
                spacing: 14
                clip: true
                model: picker.model
                currentIndex: picker.index
                highlightMoveDuration: 220
                boundsBehavior: Flickable.StopAtBounds
                // Wallhaven: cargar más al acercarse al final
                onAtXEndChanged: if (atXEnd && picker.wh) Wallhaven.more()

                WheelHandler { onWheel: e => list.flick(e.angleDelta.y * 6, 0) }

                delegate: Item {
                    id: card
                    required property int index
                    required property string filePath
                    required property string thumb
                    required property string name
                    required property string wid
                    required property string resolution
                    required property real size
                    required property string category
                    required property int favorites
                    required property string local
                    readonly property bool selected: index === picker.index
                    readonly property string usePath: picker.wh ? local : filePath
                    readonly property bool isCurrent: usePath !== "" && usePath === Wallpaper.current
                    readonly property bool downloading: picker.wh && Wallhaven.downloadingId === wid
                    width: 300
                    height: list.height

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        ClippingRectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 16
                            color: Theme.bgSolid
                            border.width: card.selected ? 3 : 0
                            border.color: Theme.accent
                            scale: cardArea.containsMouse || card.selected ? 1.0 : 0.95
                            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                            Image {
                                anchors.fill: parent
                                source: card.thumb ? "file://" + card.thumb : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: card.selected || cardArea.containsMouse ? 1 : 0.75
                                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                            }

                            // Wallhaven: resolución y peso (lo que costaría descargarlo)
                            Rectangle {
                                visible: picker.wh
                                anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                                implicitWidth: infoText.implicitWidth + 14
                                implicitHeight: 22
                                radius: 11
                                color: Qt.alpha(Theme.base, 0.8)
                                BarText {
                                    id: infoText
                                    anchors.centerIn: parent
                                    text: picker.wh ? card.resolution + " · "
                                          + (card.local ? "descargado" : Wallhaven.fmtBytes(card.size)) : ""
                                    font.pixelSize: Theme.fontSize - 3
                                }
                            }

                            // Fondo en uso
                            Rectangle {
                                visible: card.isCurrent
                                anchors { right: parent.right; top: parent.top; margins: 10 }
                                implicitWidth: 26
                                implicitHeight: 26
                                radius: 13
                                color: Theme.accent
                                BarText { anchors.centerIn: parent; text: Icons.check; color: Theme.textOnAccent; font.pixelSize: 14 }
                            }

                            // Descargando: barra de progreso
                            Rectangle {
                                visible: card.downloading
                                anchors.fill: parent
                                color: Qt.alpha(Theme.base, 0.55)
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width - 60
                                    spacing: 8
                                    BarText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "Descargando " + Math.round(Wallhaven.progress * 100) + " %"
                                        font.bold: true
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 5
                                        radius: 3
                                        color: Qt.rgba(1, 1, 1, 0.2)
                                        Rectangle {
                                            width: parent.width * Wallhaven.progress
                                            height: parent.height
                                            radius: 3
                                            color: Theme.accent
                                        }
                                    }
                                }
                            }
                        }
                        BarText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: picker.wh ? card.category + " · ♥ " + card.favorites : card.name
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: card.selected
                            color: card.selected ? Theme.fg : Theme.dim
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: cardArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            picker.index = card.index;
                            const p = card.mapToItem(null, mouse.x, mouse.y);
                            picker.activate(card.index, Qt.point(p.x, p.y));
                            keys.forceActiveFocus();
                        }
                    }
                }

                // Pie de la lista en Wallhaven: cargando más
                footer: Item {
                    width: picker.wh && (Wallhaven.loading || Wallhaven.hasMore) && Wallhaven.items.length > 0 ? 120 : 0
                    height: list.height
                    BarText {
                        anchors.centerIn: parent
                        visible: parent.width > 0
                        text: Wallhaven.loading ? "Cargando…" : "Más →"
                        color: Theme.dim
                    }
                }

                // Vacío / error
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    spacing: 6
                    BarText {
                        Layout.alignment: Qt.AlignHCenter
                        text: picker.wh
                            ? (Wallhaven.error ? Wallhaven.error : Wallhaven.loading ? "Buscando en Wallhaven…" : "Sin resultados")
                            : (Wallpaper.scanning ? "" : "No hay fondos en ~/Pictures/Wallpapers")
                        color: Wallhaven.error && picker.wh ? Theme.red : Theme.dim
                    }
                    BarText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !picker.wh && !Wallpaper.scanning
                        text: "Copia ahí tus imágenes o descarga fondos en la pestaña Wallhaven (Tab)"
                        color: Theme.dim
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }

            BarText {
                Layout.alignment: Qt.AlignHCenter
                text: picker.wh
                    ? (Wallhaven.error && list.count > 0 ? Wallhaven.error
                       : "← → elegir · Enter o clic descargar y aplicar (se guarda en Mis fondos) · / buscar · Tab mis fondos · T transición · Esc cerrar")
                    : "← → elegir (se aplica al detenerte) · Enter aceptar · Esc volver al anterior · R aleatorio · T transición · Tab Wallhaven"
                color: Wallhaven.error && picker.wh && list.count > 0 ? Theme.red : Qt.rgba(1, 1, 1, 0.35)
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }

    // ───── Teclado ─────
    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Left: picker.move(-1); break;
            case Qt.Key_Right: picker.move(1); break;
            case Qt.Key_Home: picker.move(-9999); break;
            case Qt.Key_End: picker.move(9999); break;
            case Qt.Key_Tab:
            case Qt.Key_Backtab: picker.setTab(picker.wh ? "local" : "wallhaven"); break;
            case Qt.Key_Slash: if (!picker.wh) picker.setTab("wallhaven"); searchInput.forceActiveFocus(); searchInput.selectAll(); break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                applyTimer.stop();
                picker.activate(picker.index);
                if (!picker.wh) Ui.wallpaperOpen = false;
                break;
            case Qt.Key_Escape:
                applyTimer.stop();
                if (!picker.wh && picker.original && picker.original !== Wallpaper.current) Wallpaper.set(picker.original);
                Ui.wallpaperOpen = false;
                break;
            case Qt.Key_R: if (!picker.wh) Wallpaper.random(); break;
            case Qt.Key_T: picker.cycleTransition(); break;
            default: return;
            }
            event.accepted = true;
        }
    }

    // ───── Componentes ─────
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        signal clicked()
        implicitWidth: chipText.implicitWidth + 22
        implicitHeight: 28
        radius: 14
        color: on ? Theme.accent : chipArea.containsMouse ? Theme.surfaceHover : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        BarText {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            font.pixelSize: Theme.fontSize - 2
            font.bold: chip.on
            color: chip.on ? Theme.textOnAccent : Theme.fg
        }
        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component HeaderButton: Rectangle {
        id: hb
        property string icon: ""
        signal clicked()
        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: hbArea.containsMouse ? Theme.surfaceHover : "transparent"
        BarText { anchors.centerIn: parent; text: hb.icon; font.pixelSize: 16 }
        MouseArea {
            id: hbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hb.clicked()
        }
    }
}
