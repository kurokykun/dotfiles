import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.services
import qs.widgets

// Aviso flotante tras una captura: miniatura + acciones.
// Se oculta solo a los 6 s (no mientras el ratón esté encima). Clic en la miniatura = abrir.
PanelWindow {
    id: toast

    property string file: ""
    property bool shown: false
    property bool deleted: false
    property string colorHex: ""           // aviso del cuentagotas
    property string ocrText: ""            // aviso del OCR
    property string videoFile: ""          // aviso de grabación
    property int videoSeconds: 0
    function reset() { file = ""; colorHex = ""; ocrText = ""; videoFile = ""; deleted = false; }
    function fmtTime(sec) { return Math.floor(sec / 60) + ":" + ("0" + sec % 60).slice(-2); }

    visible: shown || card.opacity > 0
    screen: Screenshot.screen ?? Quickshell.screens[0]
    anchors { bottom: true; right: true }
    margins { bottom: 24; right: 24 }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-screenshot-toast"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    implicitWidth: 340
    implicitHeight: card.implicitHeight
    color: "transparent"

    Connections {
        target: Screenshot
        function onSaved(f) {
            toast.reset();
            toast.file = f;
            toast.shown = true;
            hideTimer.interval = 6000;
            hideTimer.restart();
        }
        function onTextCopied(t) {
            toast.reset();
            toast.ocrText = t;
            toast.shown = true;
            hideTimer.interval = 5000;
            hideTimer.restart();
        }
        function onRecordingSaved(f, secs) {
            toast.reset();
            toast.videoFile = f;
            toast.videoSeconds = secs;
            toast.shown = true;
            hideTimer.interval = 8000;
            hideTimer.restart();
        }
        function onColorPicked(hex) {
            toast.reset();
            toast.colorHex = hex;
            toast.shown = true;
            hideTimer.interval = 3000;
            hideTimer.restart();
        }
        function onFailed(reason) {
            toast.reset();
            toast.deleted = false;
            failText.text = reason;
            toast.shown = true;
            hideTimer.restart();
        }
        function onActiveChanged() { if (Screenshot.active) toast.shown = false; }   // nueva captura: fuera
    }

    Timer {
        id: hideTimer
        interval: 6000
        onTriggered: if (!hover.hovered) toast.shown = false; else restart()
    }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: col.implicitHeight + 24
        radius: 20
        color: Theme.bgSolid
        border.width: 1
        border.color: Theme.border
        opacity: toast.shown ? 1 : 0
        transform: Translate { x: toast.shown ? 0 : 30; Behavior on x { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }

        HoverHandler { id: hover }

        // Clic derecho en cualquier parte del aviso: cerrarlo
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: toast.shown = false
        }

        // Botón de cerrar (encima de la miniatura, esquina superior derecha)
        Rectangle {
            z: 10
            anchors { top: parent.top; right: parent.right; margins: 18 }
            implicitWidth: 26
            implicitHeight: 26
            radius: 13
            color: closeArea.containsMouse ? Qt.rgba(1, 0.36, 0.36, 0.85) : Qt.alpha(Theme.bgSolid, 0.8)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            BarText {
                anchors.centerIn: parent
                text: Icons.close
                font.pixelSize: 13
                color: Theme.fg
            }
            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: toast.shown = false
            }
        }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10

            // Color copiado (cuentagotas)
            RowLayout {
                visible: toast.colorHex !== ""
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: 12
                    color: toast.colorHex || "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.25)
                }
                ColumnLayout {
                    spacing: 1
                    BarText { text: toast.colorHex.toUpperCase(); font.bold: true; font.pixelSize: Theme.fontSize + 2 }
                    BarText { text: Icons.check + "  Color copiado al portapapeles"; color: Theme.dim; font.pixelSize: Theme.fontSize - 2 }
                }
            }

            // Texto copiado (OCR)
            ColumnLayout {
                visible: toast.ocrText !== ""
                Layout.fillWidth: true
                spacing: 8
                RowLayout {
                    spacing: 8
                    BarText { text: String.fromCodePoint(0xF113D); color: Theme.accent; font.pixelSize: 18 }
                    BarText { text: "Texto copiado"; font.bold: true }
                    BarText {
                        text: toast.ocrText.length + " caracteres"
                        color: Theme.dim
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: ocrPreview.implicitHeight + 16
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.05)
                    BarText {
                        id: ocrPreview
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                        text: toast.ocrText
                        wrapMode: Text.Wrap
                        maximumLineCount: 5
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }

            // Grabación guardada
            ColumnLayout {
                visible: toast.videoFile !== ""
                Layout.fillWidth: true
                spacing: 10
                RowLayout {
                    spacing: 10
                    Rectangle {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: 12
                        color: Qt.rgba(1, 0.36, 0.36, 0.15)
                        BarText { anchors.centerIn: parent; text: String.fromCodePoint(0xF0567); color: Theme.red; font.pixelSize: 22 }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        BarText {
                            text: toast.deleted ? "Grabación borrada" : "Grabación guardada · " + toast.fmtTime(toast.videoSeconds)
                            font.bold: true
                        }
                        BarText {
                            Layout.fillWidth: true
                            visible: !toast.deleted
                            text: toast.videoFile.replace(Quickshell.env("HOME"), "~")
                            color: Theme.dim
                            font.pixelSize: Theme.fontSize - 3
                            elide: Text.ElideMiddle
                        }
                    }
                }
                RowLayout {
                    visible: !toast.deleted
                    Layout.fillWidth: true
                    spacing: 6
                    ToastButton { icon: Icons.play; label: "Abrir"; onClicked: { Screenshot.open(toast.videoFile); toast.shown = false; } }
                    ToastButton { icon: String.fromCodePoint(0xF024B); label: "Carpeta"; onClicked: { Screenshot.showInFolder(toast.videoFile); toast.shown = false; } }
                    ToastButton {
                        icon: Icons.trash
                        danger: true
                        onClicked: { Screenshot.remove(toast.videoFile); toast.deleted = true; hideTimer.interval = 2000; hideTimer.restart(); }
                    }
                }
            }

            // Error
            BarText {
                id: failText
                visible: toast.file === "" && toast.colorHex === "" && toast.ocrText === "" && toast.videoFile === ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.red
            }

            // Miniatura
            ClippingRectangle {
                visible: toast.file !== "" && !toast.deleted
                Layout.fillWidth: true
                implicitHeight: Math.min(190, width * (Screenshot.lastH > 0 ? Screenshot.lastH / Math.max(1, Screenshot.lastW) : 0.5625))
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.05)
                Image {
                    anchors.fill: parent
                    source: toast.file ? "file://" + toast.file : ""
                    sourceSize.width: 640                 // miniatura ligera
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { Screenshot.open(toast.file); toast.shown = false; }
                }
            }

            // Estado
            RowLayout {
                visible: toast.file !== ""
                Layout.fillWidth: true
                spacing: 8
                BarText {
                    text: toast.deleted ? Icons.trash : Icons.check
                    color: toast.deleted ? Theme.red : Theme.green
                    font.pixelSize: 16
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    BarText {
                        text: toast.deleted ? "Captura borrada" : "Copiada y guardada"
                        font.bold: true
                        font.pixelSize: Theme.fontSize - 1
                    }
                    BarText {
                        Layout.fillWidth: true
                        visible: !toast.deleted
                        text: (Screenshot.lastW > 0 ? Screenshot.lastW + " × " + Screenshot.lastH + " · " : "")
                              + toast.file.replace(Quickshell.env("HOME"), "~")
                        color: Theme.dim
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideMiddle
                    }
                }
            }

            // Acciones
            RowLayout {
                visible: toast.file !== "" && !toast.deleted
                Layout.fillWidth: true
                spacing: 6
                ToastButton { icon: Icons.pencil; label: "Editar"; onClicked: { Screenshot.edit(toast.file); toast.shown = false; } }
                ToastButton { icon: Icons.openExternal; label: "Abrir"; onClicked: { Screenshot.open(toast.file); toast.shown = false; } }
                ToastButton { icon: String.fromCodePoint(0xF024B); label: "Carpeta"; onClicked: { Screenshot.showInFolder(toast.file); toast.shown = false; } }
                ToastButton {
                    icon: Icons.trash
                    danger: true
                    onClicked: { Screenshot.remove(toast.file); toast.deleted = true; hideTimer.interval = 2000; hideTimer.restart(); }
                }
            }
        }
    }

    component ToastButton: Rectangle {
        id: btn
        property string icon: ""
        property string label: ""
        property bool danger: false
        signal clicked()
        Layout.fillWidth: label !== ""
        implicitWidth: btnRow.implicitWidth + 20
        implicitHeight: 32
        radius: 10
        color: btnArea.containsMouse ? (danger ? Qt.rgba(1, 0.36, 0.36, 0.2) : Theme.surfaceHover) : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        RowLayout {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6
            BarText { text: btn.icon; font.pixelSize: 14; color: btn.danger ? Theme.red : Theme.fg }
            BarText { visible: btn.label !== ""; text: btn.label; font.pixelSize: Theme.fontSize - 2 }
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
