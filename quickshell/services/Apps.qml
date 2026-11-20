pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Catálogo de aplicaciones para el lanzador: filtrado, búsqueda, uso y lanzamiento.
Singleton {
    id: root

    // ───── Configuración ─────
    // Apps que nunca se muestran (id del .desktop sin ".desktop"). Edita a tu gusto.
    readonly property var hiddenApps: [
        "bssh", "bvnc", "avahi-discover"        // Avahi: navegadores SSH/VNC/Zeroconf
    ]
    // Apps que se muestran aunque su .desktop diga OnlyShowIn=GNOME, etc.
    readonly property var forceShow: []

    // Escritorio actual según XDG ("labwc:wlroots" → ["labwc", "wlroots"])
    readonly property var desktops: (Quickshell.env("XDG_CURRENT_DESKTOP") || "")
        .split(":").map(s => s.trim().toLowerCase()).filter(s => s)

    // ───── Restricciones leídas de los .desktop ─────
    // Quickshell no expone OnlyShowIn/NotShowIn/Hidden, así que se leen con grep.
    property var restricted: ({})      // id → true si NO debe mostrarse aquí

    Process {
        id: scan
        command: ["sh", "-c",
            'IFS=:; for d in "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do ' +
            '  [ -d "$d/applications" ] && grep -rsH -E "^(OnlyShowIn|NotShowIn|Hidden)=" "$d/applications" --include="*.desktop"; ' +
            'done; true']
        stdout: StdioCollector {
            onStreamFinished: {
                const info = {};
                for (const line of text.split("\n")) {
                    const m = line.match(/^(.*\/applications\/)(.+)\.desktop:(OnlyShowIn|NotShowIn|Hidden)=(.*)$/);
                    if (!m) continue;
                    const id = m[2].replace(/\//g, "-");
                    const r = info[id] ?? (info[id] = {});
                    const vals = m[4].split(";").map(s => s.trim().toLowerCase()).filter(s => s);
                    // El primer directorio (el del usuario) tiene prioridad
                    if (m[3] === "Hidden") r.hidden = r.hidden ?? (m[4].trim() === "true");
                    else r[m[3]] = r[m[3]] ?? vals;
                }
                const out = {};
                for (const id in info) {
                    const r = info[id];
                    const only = r.OnlyShowIn, not = r.NotShowIn;
                    if (r.hidden
                        || (only && !only.some(d => root.desktops.includes(d)))
                        || (not && not.some(d => root.desktops.includes(d))))
                        out[id] = true;
                }
                root.restricted = out;
            }
        }
    }
    function rescan() { if (!scan.running) scan.running = true; }
    Component.onCompleted: rescan()

    // Volver a leer cuando se instalan o quitan apps
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { rescanTimer.restart(); }
    }
    Timer { id: rescanTimer; interval: 500; onTriggered: root.rescan() }

    function isVisible(e) {
        if (!e || e.noDisplay || !e.name) return false;
        if (forceShow.includes(e.id)) return true;
        return !hiddenApps.includes(e.id) && !restricted[e.id];
    }

    // Todas las apps visibles, sin duplicados, ordenadas alfabéticamente
    readonly property var all: {
        const seen = {};
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (seen[e.id] || !isVisible(e)) continue;
            seen[e.id] = true;
            out.push(e);
        }
        return out.sort((a, b) => a.name.localeCompare(b.name));
    }

    // ───── Búsqueda ─────
    function norm(t) {
        let s = (t || "").toLowerCase();
        try { s = s.normalize("NFD").replace(/[̀-ͯ]/g, ""); } catch (e) {}
        return s;
    }

    // Coincidencia difusa: todas las letras en orden. Puntúa más las que caen
    // al inicio de palabra y las consecutivas ("vsc" → "Visual Studio Code").
    function fuzzy(text, q) {
        let ti = 0, score = 0, streak = 0;
        for (let qi = 0; qi < q.length; qi++) {
            const ch = q[qi];
            let found = -1;
            for (let j = ti; j < text.length; j++) if (text[j] === ch) { found = j; break; }
            if (found < 0) return 0;
            const wordStart = found === 0 || /[\s\-_.]/.test(text[found - 1]);
            streak = found === ti ? streak + 1 : 0;
            score += 1 + (wordStart ? 6 : 0) + streak * 2;
            ti = found + 1;
        }
        return score;
    }

    function score(e, q) {
        const n = norm(e.name);
        if (n === q) return 1000;
        if (n.startsWith(q)) return 900;
        const words = n.split(/[\s\-_.]+/);
        if (words.some(w => w.startsWith(q))) return 800;
        // Iniciales: "vsc" → Visual Studio Code
        if (words.map(w => w[0] ?? "").join("").startsWith(q)) return 700;
        if (n.includes(q)) return 600;
        const extra = norm([e.genericName, e.comment, (e.keywords ?? []).join(" "), e.id].join(" "));
        if (extra.split(/[\s\-_.,;]+/).some(w => w.startsWith(q))) return 500;
        if (extra.includes(q)) return 400;
        const f = fuzzy(n, q);
        return f > q.length * 2 ? 100 + f : 0;    // descarta coincidencias demasiado sueltas
    }

    function search(list, query) {
        const q = norm(query.trim());
        if (!q) return list;
        return list.map(e => ({ e, s: score(e, q) }))
                   .filter(x => x.s > 0)
                   .sort((a, b) => (b.s - a.s) || (usageOf(b.e.id) - usageOf(a.e.id)) || a.e.name.localeCompare(b.e.name))
                   .map(x => x.e);
    }

    // ───── Frecuentes (se guarda en launcher-usage.json) ─────
    property var usage: ({})
    function usageOf(id) { return usage[id]?.count ?? 0; }

    readonly property var frequent: all
        .filter(e => usageOf(e.id) > 0)
        .sort((a, b) => usageOf(b.id) - usageOf(a.id) || (usage[b.id].last - usage[a.id].last))
        .slice(0, 8)

    FileView {
        id: usageFile
        path: Quickshell.shellDir + "/launcher-usage.json"
        printErrors: false
        onLoaded: { try { root.usage = JSON.parse(text()); } catch (e) {} }
    }

    function launch(e) {
        if (!e) return;
        const u = Object.assign({}, usage);
        u[e.id] = { count: (u[e.id]?.count ?? 0) + 1, last: Date.now() };
        usage = u;
        usageFile.setText(JSON.stringify(u));

        if (e.runInTerminal)
            Quickshell.execDetached(["kitty", "-e", "sh", "-c", e.execString.replace(/%[a-zA-Z]/g, "").trim()]);
        else
            e.execute();
    }

    function iconFor(e) {
        const icon = e?.icon || "";
        if (icon.startsWith("/")) return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }
}
