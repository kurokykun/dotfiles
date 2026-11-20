import QtQuick
import Quickshell
import qs.config

// Barras de ecualizador (se congelan en pausa).
// Ligero a propósito: cambia de altura a saltos 8 veces por segundo en vez de animar a la tasa
// de la pantalla (144 Hz), y solo mientras su ventana está visible (los paneles ocultos no gastan).
Row {
    id: eq
    property bool playing: false
    property color color: Theme.accent
    property int barCount: 3
    property int barWidth: 3
    property int maxHeight: 12

    readonly property bool windowShown: QsWindow.window ? QsWindow.window.visible : true
    readonly property bool active: playing && windowShown && visible

    spacing: 2
    height: maxHeight

    // Patrón fijo por barra (parece música y no depende de números aleatorios)
    readonly property var pattern: [0.9, 0.35, 0.7, 0.5, 1.0, 0.3, 0.8, 0.45, 0.6, 0.25]
    property int step: 0
    Timer {
        interval: 125
        repeat: true
        running: eq.active
        onTriggered: eq.step = (eq.step + 1) % 1000
    }

    Repeater {
        model: eq.barCount
        Rectangle {
            required property int index
            anchors.bottom: parent.bottom
            width: eq.barWidth
            radius: width / 2
            color: eq.color
            height: eq.active
                ? eq.maxHeight * eq.pattern[(eq.step * (index + 2) + index * 3) % eq.pattern.length]
                : eq.maxHeight * 0.35
        }
    }
}
