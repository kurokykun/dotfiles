.pragma library

// Detección del tipo de contenido del portapapeles.
// kind: image | url | email | color | uuid | path | json | number | command | code | text

var COMMANDS = ["sudo", "git", "npm", "npx", "pnpm", "yarn", "bun", "node", "deno", "cd", "ls", "docker",
    "kubectl", "pacman", "yay", "paru", "systemctl", "journalctl", "curl", "wget", "python", "python3", "pip",
    "cargo", "rustup", "make", "cmake", "flutter", "dart", "adb", "ssh", "scp", "rsync", "chmod", "chown",
    "rm", "cp", "mv", "mkdir", "cat", "grep", "rg", "find", "fd", "echo", "export", "source", "go", "gradle",
    "mvn", "java", "tar", "unzip", "code", "nano", "vim", "nvim", "qs", "labwc", "wl-copy", "brightnessctl"];

var CODE_HINTS = /(\bfunction\b|\bconst\b|\blet\b|\bvar\b|\breturn\b|\bdef\b|\bclass\b|\bimport\b|\bfrom\b|#include|=>|\bpublic\b|\bprivate\b|\bstatic\b|\bvoid\b|\bfn\b|\bimpl\b|\bpackage\b|\binterface\b|\bproperty\b|\bif\s*\(|\bfor\s*\(|\bwhile\s*\(|<\/?[a-zA-Z][\w-]*[^>]*>)/;

function isColor(t) {
    return /^#([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t)
        || /^rgba?\(\s*\d{1,3}%?\s*,?\s*\d{1,3}%?\s*,?\s*\d{1,3}%?\s*([,/]\s*[\d.]+%?\s*)?\)$/i.test(t)
        || /^hsla?\(\s*\d{1,3}(deg)?\s*,?\s*\d{1,3}%\s*,?\s*\d{1,3}%\s*([,/]\s*[\d.]+%?\s*)?\)$/i.test(t);
}

// text: el contenido (o su vista previa); truncated: true si no es el texto completo
function detect(text, isImage, truncated) {
    if (isImage) return "image";
    var t = (text || "").trim();
    if (!t) return "text";
    var oneLine = t.indexOf("\n") < 0;

    if (oneLine) {
        if (/^(https?|ftp):\/\/\S+$/i.test(t) || /^www\.\S+\.\S+$/i.test(t)) return "url";
        if (/^[\w.+-]+@[\w-]+(\.[\w-]+)+$/.test(t)) return "email";
        if (isColor(t)) return "color";
        if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(t)) return "uuid";
        if (/^-?\d+([.,]\d+)?$/.test(t)) return "number";
        if (/^(~|\.{1,2})?\/[^\s]*$/.test(t) && t.length > 1) return "path";
    }

    // JSON: si el texto está completo, se valida de verdad
    var c0 = t.charAt(0);
    if (c0 === "{" || c0 === "[") {
        if (!truncated) {
            try { JSON.parse(t); return "json"; } catch (e) {}
        } else if (/^[\[{]\s*["{\[]/.test(t)) {
            return "json";
        }
    }

    var first = t.split("\n")[0].trim().replace(/^\$\s+/, "");
    var word = first.split(/\s+/)[0];
    if (t.length < 600 && (COMMANDS.indexOf(word) >= 0 || /^\$\s/.test(t)) && !/[;{}]\s*$/.test(first)) return "command";

    if (CODE_HINTS.test(t) && (/[;{}()=]/.test(t))) return "code";
    return "text";
}

// Nombre, icono (Nerd Font) y color de cada tipo
var INFO = {
    text:    { label: "Texto",   icon: 0xF09A8, color: "#8692ad" },
    image:   { label: "Imagen",  icon: 0xF02E9, color: "#c792ea" },
    url:     { label: "Enlace",  icon: 0xF0337, color: "#5aa9ff" },
    email:   { label: "Email",   icon: 0xF01EE, color: "#5aa9ff" },
    color:   { label: "Color",   icon: 0xF03D8, color: "#ff8a3d" },
    uuid:    { label: "UUID",    icon: 0xF0071, color: "#7ee0a1" },
    path:    { label: "Ruta",    icon: 0xF024B, color: "#ffd166" },
    json:    { label: "JSON",    icon: 0xF0626, color: "#ffd166" },
    number:  { label: "Número",  icon: 0xF03A0, color: "#7ee0a1" },
    command: { label: "Comando", icon: 0xF018D, color: "#7ee0a1" },
    code:    { label: "Código",  icon: 0xF0169, color: "#ff4f6d" }
};

function info(kind) { return INFO[kind] || INFO.text; }
function glyph(kind) { return String.fromCodePoint(info(kind).icon); }

// Filtros (pestañas) del panel
var FILTERS = [
    { id: "all",    label: "Todo",     icon: 0xF0147, kinds: null },
    { id: "pinned", label: "Fijados",  icon: 0xF0403, kinds: null },
    { id: "text",   label: "Texto",    icon: 0xF09A8, kinds: ["text", "number", "uuid", "email"] },
    { id: "code",   label: "Código",   icon: 0xF0169, kinds: ["code", "json", "command", "path"] },
    { id: "links",  label: "Enlaces",  icon: 0xF0337, kinds: ["url", "email"] },
    { id: "colors", label: "Colores",  icon: 0xF03D8, kinds: ["color"] },
    { id: "images", label: "Imágenes", icon: 0xF02E9, kinds: ["image"] }
];

function matches(filterId, e) {
    if (filterId === "all") return true;
    if (filterId === "pinned") return !!e.pinned;
    for (var i = 0; i < FILTERS.length; i++)
        if (FILTERS[i].id === filterId) return FILTERS[i].kinds.indexOf(e.kind) >= 0;
    return true;
}

// Igual que la vista previa de cliphist: espacios colapsados y recortada
function previewOf(text, width) {
    var s = (text || "").split(/\s+/).join(" ").trim();
    return s.length > width ? s.slice(0, width) : s;
}

// "ahora", "hace 5 min", "hace 2 h", "ayer 14:30", "3 nov 09:12"
function ago(ms) {
    if (!ms) return "";
    var d = (Date.now() - ms) / 1000;
    if (d < 45) return "ahora";
    if (d < 3600) return "hace " + Math.round(d / 60) + " min";
    var date = new Date(ms);
    var hm = ("0" + date.getHours()).slice(-2) + ":" + ("0" + date.getMinutes()).slice(-2);
    if (d < 6 * 3600) return "hace " + Math.round(d / 3600) + " h";
    var today = new Date(); today.setHours(0, 0, 0, 0);
    if (ms >= today.getTime()) return "hoy " + hm;
    if (ms >= today.getTime() - 86400000) return "ayer " + hm;
    var months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
    return date.getDate() + " " + months[date.getMonth()] + " " + hm;
}
