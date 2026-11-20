import QtQuick
import qs.config

// Barra deslizante (progreso de la canción / volumen).
// Muestra la vista previa al arrastrar y emite moved(valor) al soltar.
Item {
    id: slider
    property real value: 0                 // 0..1
    property bool interactive: true
    property bool live: false          // emitir moved() mientras se arrastra (volumen)
    property int trackHeight: 5
    readonly property bool dragging: area.pressed
    readonly property real shown: dragging ? dragValue : value
    property real dragValue: 0
    signal moved(real value)

    implicitHeight: 18

    function valueAt(x) { return Math.max(0, Math.min(1, x / width)); }

    // Pista
    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: area.containsMouse || slider.dragging ? slider.trackHeight + 2 : slider.trackHeight
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.15)
        Behavior on height { NumberAnimation { duration: Theme.animFast } }

        // Relleno con degradado naranja → rosa
        Rectangle {
            width: Math.max(track.height, track.width * slider.shown)
            height: parent.height
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.accent }
                GradientStop { position: 1; color: Theme.accent2 }
            }
        }
    }

    // Tirador
    Rectangle {
        visible: slider.interactive
        width: 14
        height: 14
        radius: 7
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: slider.width * slider.shown - width / 2
        scale: area.containsMouse || slider.dragging ? 1 : 0
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        enabled: slider.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => slider.dragValue = slider.valueAt(mouse.x)
        onPositionChanged: mouse => {
            if (!pressed) return;
            slider.dragValue = slider.valueAt(mouse.x);
            if (slider.live) slider.moved(slider.dragValue);
        }
        onReleased: mouse => slider.moved(slider.valueAt(mouse.x))
        onWheel: wheel => slider.moved(Math.max(0, Math.min(1, slider.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
