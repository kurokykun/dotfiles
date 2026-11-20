import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.modules.notifications
import qs.services
import qs.widgets

// Panel de fecha estilo GNOME: notificaciones (izquierda) + fecha, calendario y clima (derecha).
// Se abre al hacer clic en la hora de la barra.
Scope {
    id: root

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property var loc: Qt.locale()

    // Mes visible en el calendario
    property int viewYear: clock.date.getFullYear()
    property int viewMonth: clock.date.getMonth()
    property bool editingLocation: false

    function goToday() {
        viewYear = clock.date.getFullYear();
        viewMonth = clock.date.getMonth();
    }

    function shiftMonth(delta) {
        const d = new Date(viewYear, viewMonth + delta, 1);
        viewYear = d.getFullYear();
        viewMonth = d.getMonth();
    }

    // 42 celdas (6 semanas) empezando en lunes
    readonly property var cells: {
        const first = new Date(viewYear, viewMonth, 1);
        const offset = (first.getDay() + 6) % 7;
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(viewYear, viewMonth, 1 - offset + i);
            out.push({ day: d.getDate(), inMonth: d.getMonth() === viewMonth,
                       today: d.toDateString() === clock.date.toDateString(),
                       weekend: d.getDay() === 0 || d.getDay() === 6 });
        }
        return out;
    }

    function capitalize(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

    Connections {
        target: Ui
        function onDateOpenChanged() {
            if (Ui.dateOpen) {
                root.goToday();
                root.editingLocation = !Weather.hasLocation;
                // Si aún no se pudo descargar (no había red), intentarlo al abrir
                Weather.refreshIfFirst();
            }
        }
    }

    // ───────────── Ventanas ─────────────

    // Capa invisible: clic fuera = cerrar
    PanelWindow {
        visible: Ui.dateOpen
        screen: Ui.popupScreen ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-date-backdrop"
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            onClicked: Ui.dateOpen = false
        }
    }

    PanelWindow {
        id: popup
        visible: Ui.dateOpen
        screen: Ui.popupScreen ?? Quickshell.screens[0]
        anchors { top: true; right: true }
        margins {
            top: Theme.barHeight + Theme.gap
            right: Theme.gap
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-date"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        implicitWidth: card.implicitWidth
        implicitHeight: card.implicitHeight
        color: "transparent"

        Rectangle {
            id: card
            anchors.fill: parent
            implicitWidth: layout.implicitWidth + 32
            implicitHeight: layout.implicitHeight + 32
            radius: 22
            color: Theme.bgSolid
            border.width: 1
            border.color: Theme.border
            focus: true
            Keys.onEscapePressed: {
                if (root.editingLocation && Weather.hasLocation) root.editingLocation = false;
                else Ui.dateOpen = false;
            }

            // Animación de apertura
            opacity: 0
            transform: Translate { id: drop; y: -12 }
            Connections {
                target: popup
                function onVisibleChanged() { if (popup.visible) openAnim.restart(); }
            }
            ParallelAnimation {
                id: openAnim
                NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Theme.animNormal }
                NumberAnimation { target: drop; property: "y"; from: -12; to: 0; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }

            RowLayout {
                id: layout
                anchors { left: parent.left; top: parent.top; margins: 16 }
                spacing: 16

                // ═════════════ NOTIFICACIONES ═════════════
                ColumnLayout {
                    Layout.preferredWidth: 400
                    Layout.fillHeight: true
                    spacing: 10

                    // Sonando ahora (fijo arriba; el reproductor completo está en la barra)
                    Rectangle {
                    visible: Media.active
                        Layout.fillWidth: true
                                                    implicitHeight: 64
                        radius: 16
                        color: Theme.surface
                        border.width: 1
                        border.color: Theme.border
                        clip: true

                        // Clic en la tarjeta: abrir el panel de música
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Ui.mediaOpen = true
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 12
                            spacing: 12

                            ClippingRectangle {
                                implicitWidth: 44
                                implicitHeight: 44
                                radius: 10
                                color: Theme.bgSolid
                                Image {
                                    id: miniArt
                                    anchors.fill: parent
                                    source: Media.art
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                BarText {
                                    anchors.centerIn: parent
                                    visible: miniArt.status !== Image.Ready
                                    text: Icons.musicNote
                                    color: Theme.dim
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                BarText {
                                    Layout.fillWidth: true
                                    text: Media.title
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                BarText {
                                    Layout.fillWidth: true
                                    text: Media.artist
                                    color: Theme.dim
                                    font.pixelSize: Theme.fontSize - 2
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                implicitWidth: 34
                                implicitHeight: 34
                                radius: 17
                                color: miniPlay.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
                                BarText {
                                    anchors.centerIn: parent
                                    text: Media.playing ? Icons.pause : Icons.play
                                    color: Theme.textOnAccent
                                    font.pixelSize: 16
                                }
                                MouseArea {
                                    id: miniPlay
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Media.toggle()
                                }
                            }
                        }

                        // Progreso: línea fina abajo, dentro de las esquinas redondeadas
                    Rectangle {
                        visible: Media.length > 0
                        x: 16
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        height: 2
                        radius: 1
                        width: (parent.width - 32) * Media.progress
                        color: Theme.accent
                        // Sin animación: avanza a saltos de 1 s (animarla redibujaba la barra 144 veces por segundo)
                    }
                }

                    Flickable {
                        id: notifFlick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 420
                        contentHeight: notifList.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: notifList
                            width: parent.width
                            spacing: 8

                            Repeater {
                                model: Notifs.list.slice().reverse()
                                delegate: NotifCard {
                                    required property var modelData
                                    notif: modelData
                                    now: clock.date
                                }
                            }
                        }

                        // Vacío: campana (centrada en la zona visible; el contenido mide 0 de alto)
                        ColumnLayout {
                            x: (notifFlick.width - width) / 2
                            y: Math.max(0, (notifFlick.height - height) / 2)
                            visible: Notifs.count === 0
                            spacing: 10
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Notifs.dnd ? Icons.bellOff : Icons.bell
                                font.pixelSize: 54
                                color: Qt.rgba(1, 1, 1, 0.15)
                            }
                            BarText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "No hay notificaciones"
                                color: Theme.dim
                            }
                        }

                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        BarText {
                            text: Notifs.dnd ? Icons.bellOff : Icons.bell
                            color: Notifs.dnd ? Theme.accent : Theme.dim
                            font.pixelSize: 16
                        }
                        BarText { text: "No molestar"; font.pixelSize: Theme.fontSize - 1 }
                        Toggle {
                            checked: Notifs.dnd
                            onToggled: Notifs.dnd = !Notifs.dnd
                        }
                        Item { Layout.fillWidth: true }
                        ActionButton {
                            text: "Limpiar"
                            icon: Icons.broom
                            enabled: Notifs.count > 0
                            onClicked: Notifs.clearAll()
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    color: Theme.border
                }

                // ═════════════ FECHA · CALENDARIO · CLIMA ═════════════
                ColumnLayout {
                    Layout.preferredWidth: 320
                    Layout.alignment: Qt.AlignTop
                    spacing: 12

                    // Fecha de hoy (clic: volver al mes actual)
                    ColumnLayout {
                        spacing: 0
                        BarText {
                            text: root.capitalize(root.loc.toString(clock.date, "dddd"))
                            color: Theme.accent
                            font.bold: true
                        }
                        BarText {
                            text: root.loc.toString(clock.date, "d 'de' MMMM 'de' yyyy")
                            font.pixelSize: Theme.fontSize + 5
                            font.bold: true
                        }
                    }

                    // ───── Calendario ─────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: calCol.implicitHeight + 20
                        radius: 16
                        color: Theme.surface

                        ColumnLayout {
                            id: calCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                ActionButton { kind: "icon"; icon: Icons.chevronLeft; onClicked: root.shiftMonth(-1) }
                                BarText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    font.bold: true
                                    text: root.capitalize(root.loc.standaloneMonthName(root.viewMonth, Locale.LongFormat))
                                        + (root.viewYear !== clock.date.getFullYear() ? " " + root.viewYear : "")
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.goToday()
                                    }
                                }
                                ActionButton { kind: "icon"; icon: Icons.chevronRight; onClicked: root.shiftMonth(1) }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 7
                                columnSpacing: 0
                                rowSpacing: 2

                                // Iniciales de los días (L M X J V S D)
                                Repeater {
                                    model: [1, 2, 3, 4, 5, 6, 0]
                                    delegate: BarText {
                                        required property int modelData
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.loc.standaloneDayName(modelData, Locale.NarrowFormat).toUpperCase()
                                        color: Theme.dim
                                        font.pixelSize: Theme.fontSize - 2
                                        font.bold: true
                                    }
                                }

                                Repeater {
                                    model: root.cells
                                    delegate: Item {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 34

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: parent.modelData.today ? Theme.accent
                                                 : dayArea.containsMouse ? Theme.surfaceHover : "transparent"
                                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                        }
                                        BarText {
                                            anchors.centerIn: parent
                                            text: parent.modelData.day
                                            font.bold: parent.modelData.today
                                            color: parent.modelData.today ? Theme.textOnAccent
                                                 : !parent.modelData.inMonth ? Qt.rgba(1, 1, 1, 0.25)
                                                 : parent.modelData.weekend ? Theme.dim : Theme.fg
                                        }
                                        MouseArea {
                                            id: dayArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ───── Clima ─────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: weatherCol.implicitHeight + 24
                        radius: 16
                        color: Theme.surface

                        ColumnLayout {
                            id: weatherCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 10

                            // Encabezado: ubicación
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                BarText { text: Icons.mapMarker; color: Theme.accent; font.pixelSize: 15 }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    BarText {
                                        Layout.fillWidth: true
                                        text: Weather.hasLocation ? Weather.city : "Clima"
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    BarText {
                                        Layout.fillWidth: true
                                        visible: Weather.hasLocation && !root.editingLocation
                                        text: Weather.error !== "" ? Weather.error
                                            : Weather.loading ? "Actualizando…"
                                            : Weather.current ? "Actualizado " + Qt.formatTime(Weather.updated, "HH:mm") : ""
                                        color: Weather.error !== "" ? Theme.red : Theme.dim
                                        font.pixelSize: Theme.fontSize - 3
                                        elide: Text.ElideRight
                                    }
                                }
                                ActionButton {
                                    visible: Weather.hasLocation && !root.editingLocation
                                    kind: "icon"
                                    icon: Icons.refresh
                                    busy: Weather.loading
                                    onClicked: Weather.refresh()
                                }
                                ActionButton {
                                    visible: Weather.hasLocation
                                    kind: "icon"
                                    icon: root.editingLocation ? Icons.close : Icons.pencil
                                    onClicked: root.editingLocation = !root.editingLocation
                                }
                            }

                            // Búsqueda de ubicación
                            ColumnLayout {
                                visible: root.editingLocation
                                Layout.fillWidth: true
                                spacing: 6

                                FormField {
                                    id: citySearch
                                    placeholder: "Buscar ciudad…"
                                    onTextChanged: searchDelay.restart()
                                    onAccepted: Weather.search(text)
                                    onVisibleChanged: if (visible) { clear(); Qt.callLater(focusInput); }
                                }
                                Timer {
                                    id: searchDelay
                                    interval: 400
                                    onTriggered: Weather.search(citySearch.text)
                                }
                                BarText {
                                    visible: Weather.searching || (citySearch.text.length >= 2 && Weather.searchResults.length === 0)
                                    text: Weather.searching ? "Buscando…" : "Sin resultados"
                                    color: Theme.dim
                                    font.pixelSize: Theme.fontSize - 2
                                }
                                Repeater {
                                    model: Weather.searchResults
                                    delegate: ListRow {
                                        required property var modelData
                                        icon: Icons.mapMarker
                                        iconColor: Theme.accent
                                        title: modelData.name
                                        subtitle: [modelData.admin1, modelData.country].filter(x => x).join(", ")
                                        onClicked: { const place = modelData; root.editingLocation = false; Weather.setLocation(place); }
                                    }
                                }
                            }

                            // Tiempo actual
                            RowLayout {
                                visible: !root.editingLocation && Weather.current !== null
                                Layout.fillWidth: true
                                spacing: 12
                                BarText {
                                    text: Weather.current ? Weather.icon(Weather.current.code, Weather.current.isDay) : ""
                                    font.pixelSize: 44
                                    color: Theme.accent
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    BarText {
                                        text: Weather.current ? Math.round(Weather.current.temp) + "°" : ""
                                        font.pixelSize: 30
                                        font.bold: true
                                    }
                                    BarText {
                                        Layout.fillWidth: true
                                        text: Weather.current ? Weather.describe(Weather.current.code) : ""
                                        color: Theme.dim
                                        elide: Text.ElideRight
                                    }
                                }
                                ColumnLayout {
                                    spacing: 2
                                    BarText {
                                        Layout.alignment: Qt.AlignRight
                                        text: Weather.today ? "↑ " + Math.round(Weather.today.max) + "°  ↓ " + Math.round(Weather.today.min) + "°" : ""
                                        font.pixelSize: Theme.fontSize - 2
                                    }
                                    BarText {
                                        Layout.alignment: Qt.AlignRight
                                        text: Weather.current ? Icons.thermometer + " Sensación " + Math.round(Weather.current.feels) + "°" : ""
                                        color: Theme.dim
                                        font.pixelSize: Theme.fontSize - 3
                                    }
                                    BarText {
                                        Layout.alignment: Qt.AlignRight
                                        text: Weather.current ? Icons.humidity + " " + Weather.current.humidity + "%   "
                                            + Icons.wind + " " + Math.round(Weather.current.wind) + " km/h" : ""
                                        color: Theme.dim
                                        font.pixelSize: Theme.fontSize - 3
                                    }
                                }
                            }

                            // Próximas horas
                            RowLayout {
                                visible: !root.editingLocation && Weather.hourly.length > 0
                                Layout.fillWidth: true
                                spacing: 0
                                Repeater {
                                    model: Weather.hourly
                                    delegate: ColumnLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1   // reparto en columnas iguales
                                        Layout.minimumWidth: 48
                                        spacing: 2
                                        BarText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.label
                                            color: Theme.dim
                                            font.pixelSize: Theme.fontSize - 3
                                        }
                                        BarText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: Weather.icon(modelData.code, modelData.isDay)
                                            font.pixelSize: 20
                                        }
                                        BarText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: Math.round(modelData.temp) + "°"
                                            font.pixelSize: Theme.fontSize - 1
                                        }
                                    }
                                }
                            }

                            // Sin ubicación todavía
                            BarText {
                                visible: !Weather.hasLocation && !root.editingLocation
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: "Elige tu ciudad para ver el clima."
                                color: Theme.dim
                            }
                        }
                    }
                }
            }
        }
    }
}
