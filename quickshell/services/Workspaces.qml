pragma Singleton
import QtQuick
import Quickshell
import Quickshell.WindowManager

// Escritorios de labwc vía el protocolo ext-workspace (Quickshell.WindowManager).
// La lista llega de forma asíncrona un instante después de arrancar.
Singleton {
    id: root

    readonly property var list: WindowManager.windowsets.filter(w => w.shouldDisplay !== false)
    readonly property int count: list.length
    readonly property int activeIndex: list.findIndex(w => w.active)
    readonly property var active: activeIndex >= 0 ? list[activeIndex] : null

    // "Escritorio 3" → "3" (para etiquetas cortas)
    function shortName(w) { const m = (w?.name ?? "").match(/(\d+)\s*$/); return m ? m[1] : (w?.name ?? ""); }

    function activate(i) {
        const w = list[i];
        if (w && w.canActivate && !w.active) w.activate();
    }
    // Siguiente / anterior (sin dar la vuelta, como labwc por defecto con la rueda)
    function next() { if (activeIndex < count - 1) activate(activeIndex + 1); }
    function previous() { if (activeIndex > 0) activate(activeIndex - 1); }

    // Aviso al cambiar (lo pinta modules/osd/WorkspaceOsd.qml); no al arrancar
    signal switched(int index)
    property int _last: -1
    onActiveIndexChanged: {
        if (activeIndex < 0) return;
        if (_last >= 0 && activeIndex !== _last) switched(activeIndex);
        _last = activeIndex;
    }
}
