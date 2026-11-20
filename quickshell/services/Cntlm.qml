pragma Singleton
import QtQuick
import Quickshell

// Perfiles de cntlm en ~/.config/cntlm/<nombre>.conf
// Cada perfil se ejecuta como servicio de usuario cntlm@<nombre>.service (ver ~/.config/systemd/user/cntlm@.service).
// Solo un perfil activo a la vez; el activo arranca solo al iniciar sesión.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/cntlm"

    property var profiles: []        // [{name, username, domain, auth, password, hasHash, proxies, listen, noProxy, extra}]
    property string active: ""       // perfil en ejecución
    property string state: ""        // active | activating | failed | ""
    property string failed: ""       // perfil que falló al arrancar
    property string error: ""
    property bool busy: false
    property string testResult: ""   // texto del último "Probar conexión"
    property bool testing: false

    readonly property var activeProfile: profiles.find(p => p.name === active) ?? null

    function validName(n) { return /^[A-Za-z0-9._-]+$/.test(n); }

    // ───── Lectura ─────
    function refresh() {
        Network.run(["sh", "-c",
            "for f in \"$HOME\"/.config/cntlm/*.conf; do [ -f \"$f\" ] || continue; " +
            "printf '\\036%s\\n' \"$(basename \"$f\" .conf)\"; cat \"$f\"; echo; done"], (code, out) => {
            const list = [];
            for (const chunk of out.split("\x1e")) {
                if (!chunk.trim()) continue;
                const nl = chunk.indexOf("\n");
                list.push(parse(chunk.slice(0, nl).trim(), chunk.slice(nl + 1)));
            }
            list.sort((a, b) => a.name.localeCompare(b.name));
            profiles = list;
        });

        Network.run(["systemctl", "--user", "list-units", "cntlm@*", "--all", "--plain", "--no-legend"], (code, out) => {
            let act = "", st = "", fail = "";
            for (const line of out.split("\n")) {
                const m = line.trim().match(/^cntlm@(.+)\.service\s+\S+\s+(\S+)\s+(\S+)/);
                if (!m) continue;
                const name = m[1].replace(/\\x2d/g, "-");
                if (m[2] === "active" || m[2] === "activating") { act = name; st = m[2]; }
                else if (m[2] === "failed") fail = name;
            }
            active = act;
            state = act ? st : (fail ? "failed" : "");
            failed = fail;
        });
    }

    function parse(name, text) {
        const p = { name, username: "", domain: "", auth: "NTLMv2", password: "", hasHash: false,
                    proxies: [], listen: "3128", noProxy: "", extra: [] };
        for (const raw of text.split("\n")) {
            const line = raw.trim();
            const m = line.match(/^([A-Za-z0-9]+)\s+(.*)$/);
            if (!line || line.startsWith("#") || !m) {
                if (line && !line.startsWith("# Perfil cntlm")) p.extra.push(raw);
                continue;
            }
            const key = m[1].toLowerCase(), val = m[2].trim();
            if (key === "username") p.username = val;
            else if (key === "domain") p.domain = val;
            else if (key === "auth") p.auth = val;
            else if (key === "password") p.password = val;
            else if (key === "proxy") p.proxies.push(val);
            else if (key === "listen") p.listen = val;
            else if (key === "noproxy") p.noProxy = val;
            else if (key.startsWith("pass")) { p.hasHash = true; p.extra.push(raw); }   // PassNTLMv2/PassNT/PassLM
            else p.extra.push(raw);
        }
        return p;
    }

    function serialize(p) {
        const pad = k => (k + "            ").slice(0, 12);
        const lines = ["# Perfil cntlm (editado desde Quickshell)"];
        lines.push(pad("Username") + p.username);
        lines.push(pad("Domain") + p.domain);
        lines.push(pad("Auth") + p.auth);
        if (p.password) lines.push(pad("Password") + p.password);
        for (const px of p.proxies) lines.push(pad("Proxy") + px);
        lines.push(pad("Listen") + p.listen);
        if (p.noProxy) lines.push(pad("NoProxy") + p.noProxy);
        for (const e of p.extra) lines.push(e);
        return lines.join("\n") + "\n";
    }

    // URL del proxy local de un perfil ("3128" o "127.0.0.1:3128" → http://127.0.0.1:3128)
    function localUrl(p) {
        const l = (p?.listen || "3128").trim();
        return "http://" + (l.includes(":") ? l : "127.0.0.1:" + l);
    }

    // ───── Guardar / borrar ─────
    // data: {name, username, domain, auth, password ("" = mantener), proxies, listen, noProxy}
    function save(oldName, data, cb) {
        if (!validName(data.name)) { cb(false, "Nombre no válido (solo letras, números, . _ -)"); return; }
        if (data.name !== oldName && profiles.some(p => p.name === data.name)) { cb(false, "Ya existe un perfil con ese nombre"); return; }
        const prev = profiles.find(p => p.name === oldName);
        const p = Object.assign({ extra: prev ? prev.extra : [] }, data);
        if (!p.password && prev) p.password = prev.password;
        const wasActive = oldName !== "" && oldName === active;

        // Escritura con permisos 600; el contenido va por variable de entorno (no en la línea de comandos)
        const script = "umask 077; mkdir -p \"$HOME/.config/cntlm\"; f=\"$HOME/.config/cntlm/$1.conf\"; " +
            "printf '%s' \"$QS_CNTLM_CONF\" > \"$f.tmp\" && mv \"$f.tmp\" \"$f\" || exit 1; " +
            "if [ -n \"$2\" ] && [ \"$2\" != \"$1\" ]; then rm -f \"$HOME/.config/cntlm/$2.conf\"; fi";
        busy = true;
        Network.run(["sh", "-c", script, "sh", p.name, oldName], (code, o, e) => {
            busy = false;
            if (code !== 0) { cb(false, e.trim() || "No se pudo guardar"); return; }
            if (wasActive) activate(p.name);   // reiniciar con la nueva configuración
            else refresh();
            cb(true, "");
        }, { QS_CNTLM_CONF: serialize(p) });
    }

    function remove(name, cb) {
        const doRemove = () => Network.run(["rm", "-f", dir + "/" + name + ".conf"], code => {
            refresh();
            cb(code === 0, code === 0 ? "" : "No se pudo borrar");
        });
        if (name === active) deactivate(doRemove); else doRemove();
    }

    // ───── Activar / desactivar ─────
    // Para y deshabilita cualquier instancia anterior, luego habilita y arranca la elegida
    readonly property string stopAll:
        "for u in $(systemctl --user list-units 'cntlm@*' --all --plain --no-legend | awk '{print $1}') " +
        "$(cd \"$HOME/.config/systemd/user/default.target.wants\" 2>/dev/null && ls cntlm@*.service 2>/dev/null); do " +
        "systemctl --user disable --now \"$u\" >/dev/null 2>&1; systemctl --user reset-failed \"$u\" >/dev/null 2>&1; done; "

    function activate(name) {
        busy = true;
        error = "";
        testResult = "";
        Ui.lastProxy = name;
        Network.run(["sh", "-c", stopAll +
            "systemctl --user enable --now \"cntlm@$1.service\" || exit 1; sleep 1.5; " +
            "systemctl --user is-active --quiet \"cntlm@$1.service\" || { journalctl --user -u \"cntlm@$1.service\" -n 4 -o cat --no-pager >&2; exit 2; }",
            "sh", name], (code, o, e) => {
            busy = false;
            if (code !== 0) {
                error = (e.trim().split("\n").filter(l => l).pop()) || "cntlm no pudo arrancar";
                Network.notify("Proxy " + name + ": error", error, true);
            }
            refresh();
        });
    }

    function deactivate(cb) {
        busy = true;
        testResult = "";
        Network.run(["sh", "-c", stopAll], () => {
            busy = false;
            refresh();
            if (typeof cb === "function") cb();
        });
    }

    // ───── Probar ─────
    function test() {
        if (!activeProfile) return;
        testing = true;
        testResult = "";
        Network.run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code} %{time_total}", "-m", "12",
                     "-x", localUrl(activeProfile), "http://connectivitycheck.gstatic.com/generate_204"], (code, out) => {
            testing = false;
            const [http, time] = out.trim().split(" ");
            const ms = Math.round(parseFloat(time || "0") * 1000);
            if (http === "204" || http === "200") testResult = "ok:Funciona · " + ms + " ms";
            else if (http === "407") testResult = "err:Credenciales rechazadas por el proxy (407)";
            else if (http === "000") testResult = "err:Sin respuesta del proxy";
            else testResult = "err:El proxy respondió " + http;
        });
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
