import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.config
import qs.services
import qs.widgets

// Panel de reproducción (clic en la canción del centro de la barra).
// Fondo con la portada desenfocada, portada grande, progreso con arrastre y controles.
Scope {
    id: root

    // Capa invisible: clic fuera = cerrar
    PanelWindow {
        visible: Ui.mediaOpen
        screen: Ui.popupScreen ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-media-backdrop"
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            onClicked: Ui.mediaOpen = false
        }
    }

    PanelWindow {
        id: popup
        visible: Ui.mediaOpen
        screen: Ui.popupScreen ?? Quickshell.screens[0]
        anchors.top: true                     // sin left/right: centrado bajo la barra
        margins.top: Theme.barHeight + Theme.gap
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-media"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        implicitWidth: 460
        implicitHeight: card.implicitHeight
        color: "transparent"

        readonly property var player: Media.player

        // ClippingRectangle: recorta el contenido (y el fondo desenfocado) con las esquinas redondeadas
        ClippingRectangle {
            id: card
            anchors.fill: parent
            implicitHeight: content.implicitHeight + 40
            radius: 26
            color: Theme.bgSolid
            focus: true

            // Teclado: Espacio = reproducir/pausar · ←/→ = anterior/siguiente · Esc = cerrar
            Keys.onEscapePressed: Ui.mediaOpen = false
            Keys.onSpacePressed: Media.toggle()
            Keys.onLeftPressed: Media.previous()
            Keys.onRightPressed: Media.next()

            // Animación de apertura
            opacity: 0
            transform: Translate { id: drop; y: -14 }
            Connections {
                target: popup
                function onVisibleChanged() { if (popup.visible) openAnim.restart(); }
            }
            ParallelAnimation {
                id: openAnim
                NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Theme.animNormal }
                NumberAnimation { target: drop; property: "y"; from: -14; to: 0; duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }

            // ───── Fondo: portada desenfocada ─────
            Image {
                id: bgArt
                anchors.fill: parent
                source: Media.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: bgArt
                visible: bgArt.status === Image.Ready
                blurEnabled: true
                blur: 1.0
                blurMax: 64
                saturation: 0.2
                brightness: -0.4
                opacity: 0.55
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.bgSolid, 0.55) }
                    GradientStop { position: 1.0; color: Qt.alpha(Theme.bgSolid, 0.95) }
                }
            }

            // Borde fino (encima del fondo)
            Rectangle {
                anchors.fill: parent
                z: 10
                radius: card.radius
                color: "transparent"
                border.width: 1
                border.color: Theme.border
            }

            ColumnLayout {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 16

                // ───── Encabezado ─────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    BarText { text: Icons.spotify; color: "#1ed760"; font.pixelSize: 18 }
                    BarText {
                        Layout.fillWidth: true
                        text: popup.player ? (Media.playing ? "Reproduciendo en " : "En pausa · ") + (popup.player.identity || "Spotify") : "Spotify"
                        color: Theme.dim
                        font.pixelSize: Theme.fontSize - 1
                    }
                    ActionButton {
                        kind: "icon"
                        icon: Icons.openExternal
                        onClicked: { Ui.mediaOpen = false; Media.raise(); }
                    }
                }

                // ───── Nada sonando ─────
                ColumnLayout {
                    visible: !Media.active
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    Layout.bottomMargin: 10
                    spacing: 12
                    BarText { Layout.alignment: Qt.AlignHCenter; text: Icons.musicNote; font.pixelSize: 54; color: Qt.rgba(1, 1, 1, 0.18) }
                    BarText { Layout.alignment: Qt.AlignHCenter; text: "No se está reproduciendo nada"; color: Theme.dim }
                    ActionButton {
                        Layout.alignment: Qt.AlignHCenter
                        kind: "primary"
                        icon: Icons.spotify
                        text: "Abrir Spotify"
                        onClicked: { Ui.mediaOpen = false; Media.raise(); }
                    }
                }

                // ───── Portada + datos ─────
                RowLayout {
                    visible: Media.active
                    Layout.fillWidth: true
                    spacing: 18

                    Item {
                        implicitWidth: 150
                        implicitHeight: 150

                        // Sombra
                        RectangularShadow {
                            anchors.fill: artFrame
                            radius: artFrame.radius
                            blur: 30
                            spread: 2
                            offset.y: 8
                            color: Qt.rgba(0, 0, 0, 0.55)
                        }

                        ClippingRectangle {
                            id: artFrame
                            anchors.fill: parent
                            radius: 18
                            color: Theme.surface

                            Image {
                                id: art
                                anchors.fill: parent
                                source: Media.art
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 300
                                sourceSize.height: 300
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 350 } }
                            }
                            BarText {
                                anchors.centerIn: parent
                                visible: art.status !== Image.Ready
                                text: Icons.album
                                font.pixelSize: 54
                                color: Qt.rgba(1, 1, 1, 0.2)
                            }
                        }

                        // Al cambiar de canción, la portada "rebota"
                        Connections {
                            target: Media
                            function onTitleChanged() { artBounce.restart(); }
                        }
                        SequentialAnimation {
                            id: artBounce
                            NumberAnimation { target: artFrame; property: "scale"; to: 0.92; duration: 120; easing.type: Easing.OutQuad }
                            NumberAnimation { target: artFrame; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 6

                        Equalizer {
                            playing: Media.playing
                            maxHeight: 14
                            barCount: 4
                            Layout.bottomMargin: 4
                        }
                        BarText {
                            Layout.fillWidth: true
                            text: Media.title
                            font.pixelSize: Theme.fontSize + 6
                            font.bold: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        BarText {
                            Layout.fillWidth: true
                            text: Media.artist
                            color: Theme.accent
                            font.pixelSize: Theme.fontSize + 1
                            elide: Text.ElideRight
                        }
                        BarText {
                            Layout.fillWidth: true
                            visible: Media.album !== ""
                            text: Icons.album + "  " + Media.album
                            color: Theme.dim
                            font.pixelSize: Theme.fontSize - 1
                            elide: Text.ElideRight
                        }
                    }
                }

                // ───── Progreso ─────
                ColumnLayout {
                    visible: Media.active
                    Layout.fillWidth: true
                    spacing: 4

                    MediaSlider {
                        id: progress
                        Layout.fillWidth: true
                        value: Media.progress
                        interactive: popup.player?.canSeek ?? false
                        onMoved: v => Media.seekTo(v)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        BarText {
                            text: Media.fmt(progress.dragging ? progress.dragValue * Media.length : Media.position)
                            color: Theme.dim
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Item { Layout.fillWidth: true }
                        BarText {
                            text: Media.fmt(Media.length)
                            color: Theme.dim
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }

                // ───── Controles ─────
                RowLayout {
                    visible: Media.active
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 18

                    MediaButton {
                        icon: Icons.shuffle
                        active: popup.player?.shuffle ?? false
                        enabled: popup.player?.shuffleSupported ?? false
                        onClicked: Media.toggleShuffle()
                    }
                    MediaButton {
                        icon: Icons.previous
                        size: 26
                        enabled: popup.player?.canGoPrevious ?? false
                        onClicked: Media.previous()
                    }

                    // Reproducir / pausar
                    Rectangle {
                        implicitWidth: 62
                        implicitHeight: 62
                        radius: 31
                        gradient: Gradient {
                            GradientStop { position: 0; color: Theme.accent }
                            GradientStop { position: 1; color: Theme.accent2 }
                        }
                        scale: playArea.pressed ? 0.9 : playArea.containsMouse ? 1.06 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }

                        BarText {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: Media.playing ? 0 : 2
                            text: Media.playing ? Icons.pause : Icons.play
                            font.pixelSize: 30
                            color: Theme.textOnAccent
                        }
                        MouseArea {
                            id: playArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Media.toggle()
                        }
                    }

                    MediaButton {
                        icon: Icons.next
                        size: 26
                        enabled: popup.player?.canGoNext ?? false
                        onClicked: Media.next()
                    }
                    MediaButton {
                        readonly property int loop: popup.player?.loopState ?? MprisLoopState.None
                        icon: loop === MprisLoopState.Track ? Icons.repeatOnce : Icons.repeat
                        active: loop !== MprisLoopState.None
                        enabled: popup.player?.loopSupported ?? false
                        onClicked: Media.cycleLoop()
                    }
                }

                // ───── Volumen de Spotify ─────
                RowLayout {
                    visible: Media.active && (popup.player?.volumeSupported ?? false)
                    Layout.fillWidth: true
                    Layout.bottomMargin: 2
                    spacing: 10

                    readonly property real vol: popup.player?.volume ?? 0

                    BarText {
                        text: parent.vol <= 0.01 ? Icons.volumeOff : parent.vol < 0.5 ? Icons.volumeLow : Icons.volumeHigh
                        color: Theme.dim
                        font.pixelSize: 18
                    }
                    MediaSlider {
                        Layout.fillWidth: true
                        trackHeight: 4
                        value: parent.vol
                        onMoved: v => Media.setVolume(v)
                    }
                    BarText {
                        Layout.preferredWidth: 36
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(parent.vol * 100) + "%"
                        color: Theme.dim
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }
        }
    }

    // Botón redondo de control (aleatorio, anterior, siguiente, repetir)
    component MediaButton: Item {
        id: mb
        property string icon: ""
        property bool active: false
        property int size: 20
        signal clicked()

        implicitWidth: 42
        implicitHeight: 42
        opacity: enabled ? 1 : 0.35

        Rectangle {
            anchors.fill: parent
            radius: 21
            color: mbArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
        BarText {
            anchors.centerIn: parent
            text: mb.icon
            font.pixelSize: mb.size
            color: mb.active ? Theme.accent : Theme.fg
            scale: mbArea.pressed ? 0.85 : 1
            Behavior on scale { NumberAnimation { duration: Theme.animFast } }
        }
        // Punto bajo los botones activos (aleatorio/repetir)
        Rectangle {
            visible: mb.active
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: 4
            height: 4
            radius: 2
            color: Theme.accent
        }
        MouseArea {
            id: mbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mb.clicked()
        }
    }
}
