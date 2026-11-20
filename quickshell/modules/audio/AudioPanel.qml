import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.config
import qs.services
import qs.widgets

// Panel de sonido (clic en el volumen de la barra).
// Salida y entrada con elección de dispositivo, medidor del micrófono y volumen por aplicación.
PanelPopup {
    id: root
    name: "audio"
    panelWidth: 400
    open: Ui.audioOpen
    onCloseRequested: Ui.audioOpen = false

    property bool outputsOpen: false
    property bool inputsOpen: false

    onOpenChanged: if (!open) { outputsOpen = false; inputsOpen = false; }

    BarText {
        text: "Sonido"
        font.bold: true
        font.pixelSize: Theme.fontSize + 3
        Layout.bottomMargin: -4
    }

    // Salida
    VolumeRow {
        node: Audio.sink
        input: false
        expanded: root.outputsOpen
        onToggleExpand: { root.outputsOpen = !root.outputsOpen; root.inputsOpen = false; }
    }

    DeviceList {
        visible: root.outputsOpen
        title: "Salida de sonido"
        devices: Audio.sinks
        current: Audio.sink
        input: false
        onPicked: n => { Audio.setDefaultSink(n); root.outputsOpen = false; }
    }

    // Entrada (micrófono) con medidor de nivel
    VolumeRow {
        node: Audio.source
        input: true
        expanded: root.inputsOpen
        onToggleExpand: { root.inputsOpen = !root.inputsOpen; root.outputsOpen = false; }
    }

    // Nivel del micrófono en tiempo real
    Item {
        Layout.fillWidth: true
        Layout.leftMargin: 46
        Layout.rightMargin: 46
        Layout.topMargin: -10
        implicitHeight: 4
        visible: Audio.sourceReady && !Audio.micMuted

        PwNodePeakMonitor {
            id: micPeak
            node: Audio.source
            enabled: Ui.audioOpen && !Audio.micMuted
        }
        Rectangle {
            anchors.fill: parent
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.06)
        }
        Rectangle {
            height: parent.height
            radius: 2
            width: parent.width * Math.min(1, Math.sqrt(micPeak.peak))
            color: Theme.green
            Behavior on width { NumberAnimation { duration: 80 } }
        }
    }

    DeviceList {
        visible: root.inputsOpen
        title: "Entrada de sonido"
        devices: Audio.sources
        current: Audio.source
        input: true
        onPicked: n => { Audio.setDefaultSource(n); root.inputsOpen = false; }
    }

    // Volumen por aplicación
    ColumnLayout {
        visible: Audio.streams.length > 0
        Layout.fillWidth: true
        spacing: 8

        BarText {
            text: "Aplicaciones"
            color: Theme.dim
            font.pixelSize: Theme.fontSize - 2
        }

        Repeater {
            model: Audio.streams
            delegate: RowLayout {
                id: appRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 10

                Item {
                    implicitWidth: 36
                    implicitHeight: 36
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 26
                        source: Audio.appIcon(appRow.modelData)
                        opacity: appRow.modelData.audio?.muted ? 0.4 : 1
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.toggleMute(appRow.modelData)
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    BarText {
                        Layout.fillWidth: true
                        text: Audio.appName(appRow.modelData)
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.dim
                        elide: Text.ElideRight
                    }
                    MediaSlider {
                        Layout.fillWidth: true
                        trackHeight: 4
                        live: true
                        value: appRow.modelData.audio?.muted ? 0 : Math.min(1, appRow.modelData.audio?.volume ?? 0)
                        onMoved: v => {
                            if (appRow.modelData.audio.muted) appRow.modelData.audio.muted = false;
                            Audio.setVolume(appRow.modelData, v);
                        }
                    }
                }
                BarText {
                    Layout.preferredWidth: 38
                    horizontalAlignment: Text.AlignRight
                    text: appRow.modelData.audio?.muted ? "mute" : Math.round((appRow.modelData.audio?.volume ?? 0) * 100) + "%"
                    color: Theme.dim
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }

    ActionButton {
        Layout.fillWidth: true
        icon: Icons.tune
        text: "Configuración de sonido avanzada"
        onClicked: { Ui.audioOpen = false; Quickshell.execDetached(["pavucontrol"]); }
    }

    // ───────────── Componentes internos ─────────────

    // Fila de volumen: icono (silenciar) + barra + % + flecha para elegir dispositivo
    component VolumeRow: ColumnLayout {
        id: vr
        property var node: null
        property bool input: false
        property bool expanded: false
        signal toggleExpand()

        readonly property bool ready: node !== null && node !== undefined && node.audio !== null
        readonly property real vol: ready ? node.audio.volume : 0
        readonly property bool mute: ready ? node.audio.muted : true

        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Botón silenciar
            Rectangle {
                implicitWidth: 36
                implicitHeight: 36
                radius: 18
                color: vr.mute ? Qt.rgba(1, 0.36, 0.36, 0.18) : muteArea.containsMouse ? Theme.surfaceHover : Theme.surface
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                BarText {
                    anchors.centerIn: parent
                    text: vr.input ? (vr.mute ? Icons.micOff : Icons.mic) : Audio.volumeIcon(vr.vol, vr.mute)
                    color: vr.mute ? Theme.red : Theme.fg
                    font.pixelSize: 18
                }
                MouseArea {
                    id: muteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Audio.toggleMute(vr.node)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                BarText {
                    Layout.fillWidth: true
                    text: vr.ready ? Audio.label(vr.node) : (vr.input ? "Sin micrófono" : "Sin salida de audio")
                    font.pixelSize: Theme.fontSize - 2
                    color: Theme.dim
                    elide: Text.ElideRight
                }
                MediaSlider {
                    Layout.fillWidth: true
                    live: true
                    interactive: vr.ready
                    value: vr.mute ? 0 : Math.min(1, vr.vol)
                    onMoved: v => {
                        if (vr.node.audio.muted) vr.node.audio.muted = false;
                        Audio.setVolume(vr.node, v);
                    }
                }
            }

            BarText {
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
                text: vr.mute ? "mute" : Math.round(vr.vol * 100) + "%"
                color: Theme.dim
                font.pixelSize: Theme.fontSize - 2
            }

            // Elegir dispositivo
            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: vr.expanded ? Theme.accent : expArea.containsMouse ? Theme.surfaceHover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                BarText {
                    anchors.centerIn: parent
                    text: Icons.chevronRight
                    rotation: vr.expanded ? 90 : 0
                    color: vr.expanded ? Theme.textOnAccent : Theme.fg
                    font.pixelSize: 18
                    Behavior on rotation { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    id: expArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vr.toggleExpand()
                }
            }
        }
    }

    // Lista de dispositivos para elegir salida/entrada
    component DeviceList: Rectangle {
        id: dl
        property string title: ""
        property var devices: []
        property var current: null
        property bool input: false
        signal picked(var node)

        Layout.fillWidth: true
        implicitHeight: dlCol.implicitHeight + 16
        radius: 14
        color: Theme.surface

        ColumnLayout {
            id: dlCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 2

            BarText {
                Layout.leftMargin: 6
                Layout.bottomMargin: 2
                text: dl.title
                font.bold: true
                font.pixelSize: Theme.fontSize - 1
            }

            Repeater {
                model: dl.devices
                delegate: ListRow {
                    id: devRow
                    required property var modelData
                    readonly property bool selected: dl.current !== null && dl.current.id === modelData.id
                    icon: Audio.icon(modelData, dl.input)
                    iconColor: selected ? Theme.accent : Theme.fg
                    title: Audio.label(modelData)
                    subtitle: Audio.sublabel(modelData)
                    highlighted: selected
                    onClicked: dl.picked(modelData)
                    BarText {
                        visible: devRow.selected
                        text: Icons.check
                        color: Theme.accent
                        font.pixelSize: 18
                    }
                }
            }
        }
    }
}
