import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.widgets

// Icono del dock: apps fijadas o abiertas
Item {
    id: item
    property var entry: null
    property var windows: []
    property string iconSource: ""
    property int iconSize: 38
    property bool launching: false
    readonly property bool running: windows.length > 0
    readonly property bool focused: windows.some(w => w.activated)

    Layout.alignment: Qt.AlignHCenter
    implicitWidth: iconSize + 8
    implicitHeight: iconSize + 8

    // Aparece con animación al añadirse al dock
    opacity: 0
    scale: 0.6
    Component.onCompleted: appear.start()
    ParallelAnimation {
        id: appear
        NumberAnimation { target: item; property: "opacity"; to: 1; duration: Theme.animNormal }
        NumberAnimation { target: item; property: "scale"; to: 1; duration: Theme.animNormal; easing.type: Easing.OutBack }
    }

    onRunningChanged: if (running) launching = false

    function launch() {
        if (!entry) return;
        entry.execute();
        launching = true;
        launchTimeout.restart();
        bounce.restart();
    }

    Timer {
        id: launchTimeout
        interval: 8000
        onTriggered: item.launching = false
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: item.focused ? Theme.surfaceHover : area.containsMouse ? Theme.surface : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    IconImage {
        id: icon
        anchors.centerIn: parent
        implicitSize: item.iconSize
        source: item.iconSource
        scale: area.pressed ? 0.88 : area.containsMouse ? 1.1 : 1
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        transform: Translate { id: shift }

        // Mientras la app arranca, el icono "respira"
        SequentialAnimation on opacity {
            running: item.launching
            loops: Animation.Infinite
            NumberAnimation { to: 0.45; duration: 500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) icon.opacity = 1
        }
    }

    // Rebote hacia la derecha al abrir una app
    SequentialAnimation {
        id: bounce
        loops: 2
        NumberAnimation { target: shift; property: "x"; to: 10; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: shift; property: "x"; to: 0; duration: 340; easing.type: Easing.OutBounce }
    }

    // Indicadores (uno por ventana, máx. 4). La app enfocada se marca con una barra naranja.
    Column {
        anchors.left: parent.left
        anchors.leftMargin: -6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Repeater {
            model: Math.min(item.windows.length, 4)
            Rectangle {
                width: 4
                height: item.focused ? 10 : 4
                radius: 1
                color: item.focused ? Theme.accent : Theme.fg
                Behavior on height { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }
        }
    }

    // Nombre al pasar el ratón
    PopupWindow {
        visible: area.containsMouse && item.entry !== null
        anchor.item: item
        anchor.rect.x: item.width + 14
        anchor.rect.y: (item.height - implicitHeight) / 2
        implicitWidth: tipText.implicitWidth + 20
        implicitHeight: 28
        color: "transparent"
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Theme.bgSolid
            border.width: 1
            border.color: Theme.border
            BarText {
                id: tipText
                anchors.centerIn: parent
                font.pixelSize: Theme.fontSize - 1
                text: item.entry?.name ?? ""
            }
        }
    }

    // Clic: abrir / enfocar / minimizar (y alternar entre ventanas) · Ctrl+clic o clic central: nueva ventana
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            // Ctrl+clic o clic central: nueva ventana/instancia
            if (mouse.button === Qt.MiddleButton || (mouse.modifiers & Qt.ControlModifier) || !item.running) {
                item.launch();
                return;
            }
            const wins = item.windows;
            const idx = wins.findIndex(w => w.activated);
            if (idx === -1) {
                wins[0].activate();
            } else if (wins.length === 1) {
                wins[0].minimized = true;
            } else {
                wins[(idx + 1) % wins.length].activate();
            }
        }
    }
}
