import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// Fondo de escritorio dibujado por Quickshell (uno por monitor) con transiciones animadas.
// Capa "Bottom": encima de swaybg (que queda debajo como red de seguridad) y debajo de las ventanas.
// No recibe clics: el clic derecho sobre el escritorio sigue llegando a labwc.
PanelWindow {
    id: win

    required property var modelData
    screen: modelData
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    color: "black"

    property string kind: "fade"
    property bool animating: false
    readonly property real diag: Math.sqrt(width * width + height * height)

    function src(p) { return p ? "file://" + p : ""; }

    // Primer fondo, sin transición
    Component.onCompleted: oldImg.source = src(Wallpaper.current)
    Connections {
        target: Wallpaper
        function onCurrentChanged() { if (!win.animating && !oldImg.source.toString()) oldImg.source = win.src(Wallpaper.current); }
        function onChanged(path, kind) {
            anim.stop();
            win.swapping = false;
            // Si había una transición a medias, el fondo "viejo" pasa a ser el que se estaba mostrando
            if (win.animating && newImg.source.toString()) oldImg.source = newImg.source;
            win.kind = kind;
            win.resetReveal();
            newImg.source = win.src(path);
            win.animating = true;
            if (newImg.status === Image.Ready) anim.restart();
        }
    }

    function resetReveal() {
        newImg.opacity = kind === "circle" || kind === "wipe" ? 1 : 0;
        newImg.scale = kind === "zoom" ? 1.12 : 1;
        circle.r = 0;
        wipeClip.width = kind === "wipe" ? 0 : width;
    }

    property bool swapping: false
    function finishSwap() {
        if (!swapping || oldImg.status !== Image.Ready) return;
        swapping = false;
        animating = false;
        newImg.source = "";
    }

    // ───── Fondo anterior (debajo) ─────
    Image {
        id: oldImg
        onStatusChanged: win.finishSwap()
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: win.width
        asynchronous: true
        cache: true            // el cambio final reutiliza la imagen ya decodificada
    }

    // ───── Fondo nuevo (encima, se va revelando) ─────
    Item {
        id: reveal
        anchors.fill: parent
        visible: win.animating
        // Máscara circular solo durante la transición "circle"
        layer.enabled: win.animating && win.kind === "circle"
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: circleMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Item {
            id: wipeClip
            height: parent.height
            width: parent.width
            clip: true

            Image {
                id: newImg
                width: reveal.width
                height: reveal.height
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: win.width
                asynchronous: true
                cache: true            // el cambio final reutiliza la imagen ya decodificada
                onStatusChanged: if (status === Image.Ready && win.animating && !anim.running) anim.restart()
            }
            // Borde suave del barrido
            Rectangle {
                visible: win.kind === "wipe"
                x: parent.width - width
                width: 60
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.alpha(Theme.accent, 0.35) }
                }
            }
        }
    }

    // Máscara del círculo (invisible): crece desde el punto de origen hasta cubrir la pantalla
    Item {
        id: circleMask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle {
            id: circle
            property real r: 0
            readonly property real ox: Wallpaper.origin.x >= 0 ? Wallpaper.origin.x : win.width / 2
            readonly property real oy: Wallpaper.origin.y >= 0 ? Wallpaper.origin.y : win.height / 2
            x: ox - r
            y: oy - r
            width: r * 2
            height: r * 2
            radius: r
            antialiasing: true
        }
    }

    // ───── Animaciones ─────
    ParallelAnimation {
        id: anim
        NumberAnimation {
            target: circle; property: "r"
            to: win.diag; duration: win.kind === "circle" ? 900 : 0
            easing.type: Easing.InOutCubic
        }
        NumberAnimation {
            target: newImg; property: "opacity"
            to: 1; duration: win.kind === "fade" ? 700 : win.kind === "zoom" ? 650 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: newImg; property: "scale"
            to: 1; duration: win.kind === "zoom" ? 900 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: wipeClip; property: "width"
            to: win.width; duration: win.kind === "wipe" ? 850 : 0
            easing.type: Easing.InOutCubic
        }
        onFinished: {
            // El nuevo pasa a ser el de debajo; la capa de arriba se oculta cuando el de abajo
            // ya está cargado (si no, se vería un instante negro)
            win.swapping = true;
            oldImg.source = newImg.source;
            win.finishSwap();
        }
    }
}
