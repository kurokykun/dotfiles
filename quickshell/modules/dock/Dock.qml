import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.services
import qs.widgets

// Dock vertical a la izquierda (como "esquivar ventanas maximizadas" de Plank):
//  · visible siempre, también con ventanas normales abiertas
//  · se esconde si la ventana activa está maximizada (y reaparece al llevar el ratón al borde izquierdo)
//  · oculto del todo con la ventana activa a pantalla completa
//  labwc no expone la geometría de las ventanas, así que una ventana flotante encima del dock no lo aparta.
PanelWindow {
    id: dock

    screen: Quickshell.screens.find(s => s.name === Ui.dockMonitor) ?? Quickshell.screens[0]
    anchors.left: true
    // No reserva franja: las ventanas usan todo el ancho y el dock se aparta
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-dock"
    // Pegado al borde: la ventana mide el dock + las dos esquinas cóncavas (arriba y abajo)
    readonly property int fillet: 18          // radio de las esquinas cóncavas (se funden con el borde)
    readonly property int corner: 18          // radio de las esquinas del lado del escritorio
    implicitWidth: panel.width + 2
    implicitHeight: panel.height + fillet * 2
    color: "transparent"

    readonly property int iconSize: 38
    readonly property var toplevels: ToplevelManager.toplevels.values
    readonly property var pinnedMatches: Ui.pinnedApps.reduce((acc, a) => acc.concat(a.match), [])

    // ───── Ocultamiento inteligente (como "esquivar ventanas maximizadas" de Plank) ─────
    // Visible siempre, salvo que la ventana activa esté maximizada (tapa el dock) o a pantalla completa.
    // labwc no comparte la posición de las ventanas, así que una ventana flotante encima del dock no lo aparta.
    readonly property var activeWin: ToplevelManager.activeToplevel
    readonly property bool activeHere: activeWin !== null && activeWin !== undefined
        && activeWin.activated && !activeWin.minimized
        && (activeWin.screens.length === 0
            || activeWin.screens.some(s => s && dock.screen && s.name === dock.screen.name))
    readonly property bool fullscreen: activeHere && activeWin.fullscreen
    readonly property bool overlapped: activeHere && (activeWin.maximized || activeWin.fullscreen)
    readonly property bool hovered: panelHover.hovered || edgeHover.hovered
    property bool peeking: false
    readonly property bool revealed: !fullscreen && (!overlapped || peeking)

    onHoveredChanged: {
        if (hovered) {
            hideTimer.stop();
            peeking = true;
        } else {
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 600
        onTriggered: dock.peeking = false
    }

    // Solo recibe ratón donde se ve el dock; oculto, solo una franja de 3 px en el borde
    mask: Region {
        item: panel
        Region { item: edge }
    }

    Item {
        id: edge
        width: dock.fullscreen ? 0 : 3
        height: parent.height
        HoverHandler { id: edgeHover }
    }

    // ───── Apps ─────
    readonly property var unpinned: {
        const ids = [];
        for (const t of toplevels) {
            const id = (t.appId || "").toLowerCase();
            if (id && !pinnedMatches.includes(id) && !ids.includes(id)) ids.push(id);
        }
        return ids;
    }

    function windowsFor(match) {
        return toplevels.filter(t => match.includes((t.appId || "").toLowerCase()));
    }

    function lookup(id) {
        DesktopEntries.applications.values;   // dependencia: reevaluar cuando carguen las apps
        return DesktopEntries.byId(id)
            ?? (DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(id) : null);
    }

    function iconFor(entry, fallbackName) {
        const icon = entry?.icon || fallbackName;
        if (icon.startsWith("/")) return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }

    // ───── Silueta: pegada al borde izquierdo, con esquinas cóncavas que se funden con él ─────
    // Forma estática (se dibuja una vez): sin coste en reposo. Sigue la animación del panel.
    Shape {
        id: silhouette
        x: panel.x
        y: 0
        width: panel.width
        height: panel.height + dock.fillet * 2
        opacity: panel.opacity
        preferredRendererType: Shape.CurveRenderer       // bordes suaves

        readonly property real f: dock.fillet
        readonly property real r: dock.corner
        readonly property real w: width
        readonly property real h: height

        // Relleno: mismo color que la barra superior (parecen el mismo marco)
        ShapePath {
            fillColor: Theme.bar
            strokeWidth: -1
            startX: 0; startY: 0
            PathArc { x: silhouette.f; y: silhouette.f; radiusX: silhouette.f; radiusY: silhouette.f; direction: PathArc.Counterclockwise }
            PathLine { x: silhouette.w - silhouette.r; y: silhouette.f }
            PathArc { x: silhouette.w; y: silhouette.f + silhouette.r; radiusX: silhouette.r; radiusY: silhouette.r }
            PathLine { x: silhouette.w; y: silhouette.h - silhouette.f - silhouette.r }
            PathArc { x: silhouette.w - silhouette.r; y: silhouette.h - silhouette.f; radiusX: silhouette.r; radiusY: silhouette.r }
            PathLine { x: silhouette.f; y: silhouette.h - silhouette.f }
            PathArc { x: 0; y: silhouette.h; radiusX: silhouette.f; radiusY: silhouette.f; direction: PathArc.Counterclockwise }
            PathLine { x: 0; y: 0 }
        }
        // Contorno fino solo en el lado visible (no sobre el borde de la pantalla)
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.border
            strokeWidth: 1
            startX: 0; startY: 0.5
            PathArc { x: silhouette.f; y: silhouette.f + 0.5; radiusX: silhouette.f; radiusY: silhouette.f; direction: PathArc.Counterclockwise }
            PathLine { x: silhouette.w - silhouette.r - 0.5; y: silhouette.f + 0.5 }
            PathArc { x: silhouette.w - 0.5; y: silhouette.f + silhouette.r; radiusX: silhouette.r; radiusY: silhouette.r }
            PathLine { x: silhouette.w - 0.5; y: silhouette.h - silhouette.f - silhouette.r }
            PathArc { x: silhouette.w - silhouette.r - 0.5; y: silhouette.h - silhouette.f - 0.5; radiusX: silhouette.r; radiusY: silhouette.r }
            PathLine { x: silhouette.f; y: silhouette.h - silhouette.f - 0.5 }
            PathArc { x: 0; y: silhouette.h - 0.5; radiusX: silhouette.f; radiusY: silhouette.f; direction: PathArc.Counterclockwise }
        }
    }

    Rectangle {
        id: panel
        width: dock.iconSize + 24
        height: column.implicitHeight + 20
        y: dock.fillet
        x: dock.revealed ? 0 : -width - 4
        opacity: dock.revealed ? 1 : 0
        color: "transparent"           // el fondo lo dibuja la silueta

        Behavior on x { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
        Behavior on height { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

        HoverHandler { id: panelHover }

        ColumnLayout {
            id: column
            anchors.centerIn: parent
            spacing: 6

            Repeater {
                model: Ui.pinnedApps
                delegate: DockItem {
                    required property var modelData
                    iconSize: dock.iconSize
                    entry: dock.lookup(modelData.id)
                    windows: dock.windowsFor(modelData.match)
                    iconSource: dock.iconFor(entry, modelData.id)
                }
            }

            Rectangle {
                visible: dock.unpinned.length > 0
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: dock.iconSize - 8
                implicitHeight: 1
                color: Theme.border
            }

            Repeater {
                model: dock.unpinned
                delegate: DockItem {
                    required property var modelData
                    iconSize: dock.iconSize
                    entry: dock.lookup(modelData)
                    windows: dock.windowsFor([modelData])
                    iconSource: dock.iconFor(entry, modelData)
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: dock.iconSize - 8
                implicitHeight: 1
                color: Theme.border
            }

            // Botón "mostrar aplicaciones"
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: dock.iconSize + 8
                implicitHeight: dock.iconSize + 8
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: appsArea.containsMouse ? Theme.surfaceHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }
                BarText {
                    anchors.centerIn: parent
                    text: ""
                    font.pixelSize: 20
                    scale: appsArea.pressed ? 0.85 : appsArea.containsMouse ? 1.12 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    id: appsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { Ui.popupScreen = dock.screen; Ui.launcherOpen = true; }
                }
            }
        }
    }
}
