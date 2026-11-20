import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.config
import qs.services
import qs.widgets

// Tarjeta de notificación (aviso flotante y centro de notificaciones)
Rectangle {
    id: card
    required property var notif
    property date now: new Date()
    property bool popup: false
    signal timedOut()

    readonly property bool critical: notif.urgency === NotificationUrgency.Critical
    readonly property string iconSource: Notifs.iconFor(notif)
    readonly property var buttons: notif.actions.filter(a => a.identifier !== "default")

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 24
    radius: 14
    color: popup ? Theme.bgSolid : hover.hovered ? Theme.surfaceHover : Theme.surface
    border.width: popup || critical ? 1 : 0
    border.color: critical ? Theme.red : Theme.border
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    HoverHandler { id: hover }

    // Los avisos flotantes desaparecen solos (salvo críticos o con el ratón encima);
    // la notificación sigue en el centro de notificaciones.
    Timer {
        running: card.popup && !card.critical && !hover.hovered
        interval: card.notif.expireTimeout > 0 ? Math.min(card.notif.expireTimeout * 1000, 10000) : 5000
        onTriggered: card.timedOut()
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Notifs.activate(card.notif)
    }

    RowLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 12

        Item {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 36
            implicitHeight: 36
            IconImage {
                anchors.fill: parent
                visible: card.iconSource !== ""
                source: card.iconSource
            }
            Rectangle {
                anchors.fill: parent
                visible: card.iconSource === ""
                radius: 10
                color: Qt.alpha(Theme.accent, 0.16)
                BarText {
                    anchors.centerIn: parent
                    text: Icons.bell
                    color: Theme.accent
                    font.pixelSize: 18
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                BarText {
                    Layout.fillWidth: true
                    text: card.notif.appName || "Notificación"
                    color: Theme.dim
                    font.pixelSize: Theme.fontSize - 2
                    elide: Text.ElideRight
                }
                BarText {
                    text: Notifs.timeLabel(card.notif, card.now)
                    color: Theme.dim
                    font.pixelSize: Theme.fontSize - 2
                }
                // Cerrar
                Rectangle {
                    implicitWidth: 20
                    implicitHeight: 20
                    radius: 10
                    color: closeArea.containsMouse ? Theme.surfaceHover : "transparent"
                    BarText {
                        anchors.centerIn: parent
                        text: Icons.close
                        font.pixelSize: 13
                        color: Theme.dim
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.notif.dismiss()
                    }
                }
            }

            BarText {
                Layout.fillWidth: true
                text: card.notif.summary
                font.bold: true
                elide: Text.ElideRight
            }

            BarText {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.notif.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: card.popup ? 3 : 5
                elide: Text.ElideRight
                color: Qt.rgba(0.9, 0.93, 0.97, 0.85)
                font.pixelSize: Theme.fontSize - 1
            }

            // Botones de acción
            RowLayout {
                visible: card.buttons.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 6
                Repeater {
                    model: card.buttons
                    delegate: ActionButton {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.text
                        onClicked: {
                            modelData.invoke();
                            if (!card.notif.resident) card.notif.dismiss();
                        }
                    }
                }
            }
        }
    }
}
