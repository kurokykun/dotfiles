pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Servidor de notificaciones + historial (centro de notificaciones) + No molestar.
Singleton {
    id: root

    property bool dnd: false
    property var popups: []        // notificaciones mostrándose como aviso flotante
    property var times: ({})       // id -> Date de llegada

    readonly property var list: server.trackedNotifications.values
    readonly property int count: list.length

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            const t = Object.assign({}, root.times);
            t[n.id] = new Date();
            root.times = t;
            // Con "No molestar" solo pasan los críticos
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                root.popups = [n].concat(root.popups).slice(0, 4);
            n.closed.connect(() => root.hidePopup(n));
        }
    }

    function hidePopup(n) {
        if (popups.includes(n)) popups = popups.filter(p => p !== n);
    }

    function clearAll() {
        popups = [];
        for (const n of list.slice()) { try { n.dismiss(); } catch (e) {} }
    }

    // Acción por defecto (clic en la notificación) y luego cerrarla
    function activate(n) {
        const def = n.actions.find(a => a.identifier === "default");
        if (def) def.invoke();
        if (!n.resident) n.dismiss();
    }

    function iconFor(n) {
        if (n.image) return n.image;
        const icon = n.appIcon || n.desktopEntry || "";
        if (!icon) return "";
        if (icon.startsWith("/")) return "file://" + icon;
        if (icon.startsWith("file:") || icon.startsWith("image:")) return icon;
        return Quickshell.iconPath(icon, true);
    }

    // "ahora", "hace 5 min", "14:32", "ayer 09:10"…
    function timeLabel(n, now) {
        const t = times[n.id];
        if (!t) return "";
        const mins = Math.floor((now - t) / 60000);
        if (mins < 1) return "ahora";
        if (mins < 60) return "hace " + mins + " min";
        const sameDay = t.toDateString() === now.toDateString();
        const hhmm = Qt.formatTime(t, "HH:mm");
        if (sameDay) return hhmm;
        const y = new Date(now); y.setDate(now.getDate() - 1);
        if (t.toDateString() === y.toDateString()) return "ayer " + hhmm;
        return Qt.formatDate(t, "d MMM") + " " + hhmm;
    }
}
