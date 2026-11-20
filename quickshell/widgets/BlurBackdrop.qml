import QtQuick
import QtQuick.Effects
import qs.config
import qs.services

// Fondo de pantalla desenfocado y oscurecido (menú de apagado, lanzador…)
Item {
    id: backdrop
    property real darken: 0.45      // capa oscura por encima del desenfoque
    property real brightness: -0.25

    Rectangle {
        anchors.fill: parent
        color: Theme.bgSolid
    }

    Image {
        id: wallImg
        anchors.fill: parent
        source: "file://" + Ui.wallpaper
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 960        // basta con baja resolución: se va a desenfocar
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wallImg
        visible: wallImg.status === Image.Ready
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        brightness: backdrop.brightness
        saturation: -0.2
        opacity: 0.9
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.04, 0.09, backdrop.darken)
    }
}
