import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.config
import qs.services
import qs.widgets

// Contenido de la pantalla de bloqueo (igual en el bloqueo real y en la vista previa).
// Escribir en cualquier momento va al campo de contraseña · Enter desbloquea · Esc borra.
Item {
    id: root
    anchors.fill: parent

    property bool preview: false
    readonly property string userName: {
        const u = Quickshell.env("USER") || "usuario";
        return u.charAt(0).toUpperCase() + u.slice(1);
    }
    readonly property string sans: "Noto Sans"

    function focusInput() { input.forceActiveFocus(); }
    Component.onCompleted: { focusInput(); enter.restart(); }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ───── Fondo: wallpaper suavemente desenfocado + degradado ─────
    Rectangle { anchors.fill: parent; color: Theme.bgSolid }
    Image {
        id: wall
        anchors.fill: parent
        source: "file://" + Ui.wallpaper
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1280
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        visible: wall.status === Image.Ready
        blurEnabled: true
        blur: 0.7
        blurMax: 48
        brightness: -0.12
        saturation: 0.1
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(Theme.base, 0.55) }
            GradientStop { position: 0.45; color: Qt.alpha(Theme.base, 0.25) }
            GradientStop { position: 1.0; color: Qt.alpha(Theme.base, 0.85) }
        }
    }

    // Clic en cualquier parte = volver al campo de contraseña
    MouseArea { anchors.fill: parent; onClicked: root.focusInput() }

    // ───── Entrada animada ─────
    Item {
        id: content
        anchors.fill: parent
        opacity: 0
        property real lift: 30
        transform: Translate { y: content.lift }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: content; property: "opacity"; from: 0; to: 1; duration: 550; easing.type: Easing.OutCubic }
            NumberAnimation { target: content; property: "lift"; from: 30; to: 0; duration: 650; easing.type: Easing.OutCubic }
        }
        Connections {
            target: Lock
            function onActiveChanged() { if (Lock.active) enter.restart(); }
        }

        // ───── Aviso de vista previa ─────
        GlassPill {
            visible: root.preview
            anchors.top: parent.top
            anchors.topMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
            tint: Theme.yellow
            BarText {
                text: Icons.eye + "   Vista previa · no bloquea la sesión · Esc para salir"
                color: Theme.yellow
                font.pixelSize: Theme.fontSize - 1
            }
        }

        // ───── Fecha y reloj ─────
        ColumnLayout {
            id: clockBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.1
            spacing: -18

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.locale().toString(clock.date, "dddd  ·  d 'de' MMMM").toUpperCase()
                font.family: root.sans
                font.pixelSize: 17
                font.weight: Font.Medium
                font.letterSpacing: 5
                color: Qt.rgba(1, 1, 1, 0.75)
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                Text {
                    text: Qt.formatDateTime(clock.date, "HH")
                    font.family: root.sans
                    font.pixelSize: 190
                    font.weight: Font.Bold
                    color: Theme.fg
                }
                Text {
                    text: ":"
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -12
                    font.family: root.sans
                    font.pixelSize: 150
                    font.weight: Font.Light
                    color: Theme.accent
                    // Parpadeo suave de los dos puntos (solo con el lock a la vista: si no, gasta CPU en vano)
                    SequentialAnimation on opacity {
                        running: Lock.active
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 1000; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 1000; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    text: Qt.formatDateTime(clock.date, "mm")
                    font.family: root.sans
                    font.pixelSize: 190
                    font.weight: Font.ExtraLight
                    color: Theme.fg
                }
            }
        }

        // ───── Reproduciendo ahora ─────
        Rectangle {
            id: mediaCard
            visible: Media.active
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: clockBox.bottom
            anchors.topMargin: 28
            width: 440
            height: 112
            radius: 26
            color: Qt.rgba(1, 1, 1, 0.06)

            // Portada desenfocada de fondo
            Image {
                id: artBg
                anchors.fill: parent
                source: Media.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            // Paso 1: portada desenfocada (sin márgenes extra del desenfoque)
            // Paso 2: la capa completa se recorta con la forma redondeada de la tarjeta
            Item {
                anchors.fill: parent
                visible: artBg.status === Image.Ready
                opacity: 0.7
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: cardMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
                MultiEffect {
                    anchors.fill: parent
                    source: artBg
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 64
                    saturation: 0.3
                    brightness: -0.35
                }
            }
            Item {
                id: cardMask
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                visible: false
                Rectangle { anchors.fill: parent; radius: mediaCard.radius; antialiasing: true }
            }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 16

                // Portada
                Rectangle {
                    Layout.preferredWidth: 84
                    Layout.preferredHeight: 84
                    radius: 18
                    color: Theme.surface
                    Image {
                        id: art
                        anchors.fill: parent
                        source: Media.art
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: art
                        visible: art.status === Image.Ready
                        autoPaddingEnabled: false
                        maskEnabled: true
                        maskSource: artMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                    Item {
                        id: artMask
                        anchors.fill: parent
                        layer.enabled: true
                        layer.smooth: true
                        visible: false
                        Rectangle { anchors.fill: parent; radius: 18; antialiasing: true }
                    }
                    BarText {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: Icons.musicNote
                        font.pixelSize: 32
                        color: Theme.dim
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    RowLayout {
                        spacing: 6
                        Equalizer {
                            visible: Media.playing
                            playing: Media.playing
                            maxHeight: 10
                        }
                        Text {
                            text: Media.playing ? "REPRODUCIENDO" : "EN PAUSA"
                            font.family: root.sans
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 2
                            color: Theme.accent
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Media.title
                        font.family: root.sans
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        color: Theme.fg
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Media.artist
                        font.family: root.sans
                        font.pixelSize: 13
                        color: Qt.rgba(1, 1, 1, 0.65)
                        elide: Text.ElideRight
                    }
                    // Progreso
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        implicitHeight: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.15)
                        visible: Media.length > 0
                        Rectangle {
                            width: parent.width * Media.progress
                            height: parent.height
                            radius: 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Theme.accent }
                                GradientStop { position: 1; color: Theme.accent2 }
                            }
                            // Sin animación: avanza a saltos de 1 s (animarla redibujaba la barra 144 veces por segundo)
                        }
                    }
                }

                // Controles
                RowLayout {
                    spacing: 2
                    MediaButton { icon: Icons.previous; onClicked: Media.previous() }
                    MediaButton { icon: Media.playing ? Icons.pause : Icons.play; big: true; onClicked: Media.toggle() }
                    MediaButton { icon: Icons.next; onClicked: Media.next() }
                }
            }
        }

        // ───── Usuario y contraseña ─────
        ColumnLayout {
            id: authBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.12
            spacing: 14

            // Sacudida al fallar
            transform: Translate { id: shakeT; x: 0 }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeT; property: "x"; to: -14; duration: 50 }
                NumberAnimation { target: shakeT; property: "x"; to: 12; duration: 70 }
                NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 70 }
                NumberAnimation { target: shakeT; property: "x"; to: 5; duration: 60 }
                NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 50 }
            }
            Connections {
                target: Lock
                function onFailed() { shake.restart(); input.text = ""; root.focusInput(); }
            }

            // Avatar con anillo degradado
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 76
                implicitHeight: 76
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: Theme.accent2 }
                    }
                    // Gira mientras se comprueba la contraseña
                    RotationAnimation on rotation {
                        running: Lock.busy
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 1200
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: width / 2
                    color: Qt.alpha(Theme.bgSolid, 0.92)
                    Text {
                        anchors.centerIn: parent
                        text: root.userName.charAt(0)
                        font.family: root.sans
                        font.pixelSize: 32
                        font.weight: Font.Bold
                        color: Theme.fg
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.userName
                font.family: root.sans
                font.pixelSize: 18
                font.weight: Font.DemiBold
                color: Theme.fg
            }

            // Campo de contraseña (cristal)
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 360
                implicitHeight: 54
                radius: 27
                color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.11 : 0.07)
                border.width: 1
                border.color: Lock.messageIsError ? Qt.rgba(1, 0.36, 0.36, 0.75)
                            : input.activeFocus ? Qt.alpha(Theme.accent, 0.55) : Qt.rgba(1, 1, 1, 0.14)
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 8
                    spacing: 12

                    BarText {
                        text: Icons.lock
                        font.pixelSize: 17
                        color: Lock.busy ? Theme.dim : Theme.accent
                    }

                    TextInput {
                        id: input
                        Layout.fillWidth: true
                        focus: true
                        enabled: !Lock.busy
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        color: Theme.fg
                        font.family: root.sans
                        font.pixelSize: 17
                        font.letterSpacing: 3
                        clip: true
                        // Sin portapapeles ni selección: es un campo de contraseña
                        selectByMouse: false
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: input.text === ""
                            text: Lock.busy ? "Comprobando…" : "Introduce tu contraseña"
                            font.family: root.sans
                            font.pixelSize: 15
                            color: Qt.rgba(1, 1, 1, 0.42)
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                Lock.submit(input.text);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                if (input.text !== "") input.text = "";
                                else if (root.preview) Lock.cancelPreview();
                                event.accepted = true;
                            }
                        }
                    }

                    // Botón desbloquear
                    Rectangle {
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: 20
                        readonly property bool ready: input.text !== "" && !Lock.busy
                        color: ready ? Theme.accent : goArea.containsMouse ? Theme.surfaceHover : Qt.rgba(1, 1, 1, 0.06)
                        scale: goArea.pressed ? 0.9 : 1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on scale { NumberAnimation { duration: Theme.animFast } }
                        BarText {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF0054)   // flecha →
                            font.pixelSize: 18
                            color: parent.ready ? Theme.textOnAccent : Theme.dim
                        }
                        MouseArea {
                            id: goArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Lock.submit(input.text); root.focusInput(); }
                        }
                    }
                }
            }

            // Mensaje (error / comprobando)
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: 18
                text: Lock.message
                font.family: root.sans
                font.pixelSize: 13
                color: Lock.messageIsError ? Theme.red : Qt.rgba(1, 1, 1, 0.6)
            }
        }

        // ───── Esquinas: batería y distribución de teclado ─────
        GlassPill {
            id: batPill
            readonly property var bat: UPower.displayDevice
            readonly property bool charging: bat !== null && bat.state === UPowerDeviceState.Charging
            visible: bat !== null && bat.isLaptopBattery
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 28
            BarText {
                text: batPill.charging ? Icons.batteryCharging : Icons.battery
                color: batPill.charging ? Theme.green : Theme.fg
                font.pixelSize: 16
            }
            BarText { text: batPill.bat ? Math.round(batPill.bat.percentage * 100) + "%" : "" }
        }

        // La distribución importa al escribir la contraseña
        GlassPill {
            visible: Keyboard.label !== ""
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 28
            BarText { text: Icons.keyboard; color: Theme.accent; font.pixelSize: 16 }
            BarText { text: Keyboard.label; font.bold: true }
        }
    }

    // Cuando la comprobación termina, devolver el foco al campo
    Connections {
        target: Lock
        function onBusyChanged() { if (!Lock.busy) root.focusInput(); }
        // Al desbloquear / cerrar la vista previa no queda nada escrito
        function onActiveChanged() { input.text = ""; if (Lock.active) root.focusInput(); }
    }

    // ───── Componentes internos ─────
    component GlassPill: Rectangle {
        id: pill
        default property alias content: pillRow.data
        property color tint: "white"
        implicitWidth: pillRow.implicitWidth + 28
        implicitHeight: 36
        radius: 18
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.08)
        border.width: 1
        border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.16)
        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 8
        }
    }

    component MediaButton: Rectangle {
        id: mb
        property string icon: ""
        property bool big: false
        signal clicked()
        implicitWidth: big ? 42 : 34
        implicitHeight: implicitWidth
        radius: implicitWidth / 2
        color: big ? Qt.rgba(1, 1, 1, mbArea.containsMouse ? 0.25 : 0.16)
                   : mbArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
        scale: mbArea.pressed ? 0.9 : 1
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast } }
        BarText {
            anchors.centerIn: parent
            text: mb.icon
            font.pixelSize: mb.big ? 20 : 17
        }
        MouseArea {
            id: mbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { mb.clicked(); root.focusInput(); }
        }
    }
}
