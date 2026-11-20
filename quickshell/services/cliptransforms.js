.pragma library

// Transformaciones del portapapeles.
// Cada acción: { id, label, group, icon, when(kind, text) → bool, run(text) → string | { open: [...] } }
// run() lanza un Error con un mensaje legible si no se puede aplicar.

// ───────────── Utilidades ─────────────
function words(s) {
    // "fooBar-baz qux_X" → ["foo", "bar", "baz", "qux", "x"]
    return s.replace(/([a-z0-9])([A-Z])/g, "$1 $2")
            .replace(/([A-Z]+)([A-Z][a-z])/g, "$1 $2")
            .split(/[^A-Za-z0-9À-ɏ]+/)
            .filter(function (w) { return w; })
            .map(function (w) { return w.toLowerCase(); });
}
function cap(w) { return w.charAt(0).toUpperCase() + w.slice(1); }
function perLine(text, fn) { return text.split("\n").map(fn).join("\n"); }
function isOneLine(t) { return t.trim().indexOf("\n") < 0; }
function naming(k, t) { return (k === "text" || k === "code" || k === "command") && isOneLine(t) && t.length < 200; }

// UTF-8 ⇄ bytes y Base64 propios (no dependen de btoa/atob)
function utf8Encode(s) {
    var out = [];
    for (var i = 0; i < s.length; i++) {
        var c = s.codePointAt(i);
        if (c > 0xFFFF) i++;
        if (c < 0x80) out.push(c);
        else if (c < 0x800) out.push(0xC0 | c >> 6, 0x80 | c & 63);
        else if (c < 0x10000) out.push(0xE0 | c >> 12, 0x80 | c >> 6 & 63, 0x80 | c & 63);
        else out.push(0xF0 | c >> 18, 0x80 | c >> 12 & 63, 0x80 | c >> 6 & 63, 0x80 | c & 63);
    }
    return out;
}
function utf8Decode(b) {
    var s = "", i = 0;
    while (i < b.length) {
        var c = b[i++], n = 0, cp;
        if (c < 0x80) { s += String.fromCharCode(c); continue; }
        else if ((c & 0xE0) === 0xC0) { n = 1; cp = c & 31; }
        else if ((c & 0xF0) === 0xE0) { n = 2; cp = c & 15; }
        else if ((c & 0xF8) === 0xF0) { n = 3; cp = c & 7; }
        else throw new Error("El resultado no es texto UTF-8");
        for (var k = 0; k < n; k++) {
            if (i >= b.length || (b[i] & 0xC0) !== 0x80) throw new Error("El resultado no es texto UTF-8");
            cp = cp << 6 | b[i++] & 63;
        }
        s += String.fromCodePoint(cp);
    }
    return s;
}
var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
function b64encode(s) {
    var b = utf8Encode(s), out = "";
    for (var i = 0; i < b.length; i += 3) {
        var n = b[i] << 16 | (b[i + 1] || 0) << 8 | (b[i + 2] || 0);
        out += B64[n >> 18 & 63] + B64[n >> 12 & 63]
             + (i + 1 < b.length ? B64[n >> 6 & 63] : "=") + (i + 2 < b.length ? B64[n & 63] : "=");
    }
    return out;
}
function b64decode(s) {
    var t = s.replace(/\s+/g, "").replace(/-/g, "+").replace(/_/g, "/");   // también base64url
    if (!/^[A-Za-z0-9+/]*={0,2}$/.test(t)) throw new Error("No es Base64 válido");
    t = t.replace(/=+$/, "");
    var bytes = [], buf = 0, bits = 0;
    for (var i = 0; i < t.length; i++) {
        buf = buf << 6 | B64.indexOf(t[i]);
        bits += 6;
        if (bits >= 8) { bits -= 8; bytes.push(buf >> bits & 0xFF); }
    }
    return utf8Decode(bytes);
}
function looksBase64(t) {
    var s = t.trim();
    return s.length >= 8 && s.length % 4 !== 1 && /^[A-Za-z0-9+/_-]+={0,2}$/.test(s) && /[0-9+/=]|[A-Z].*[a-z]/.test(s);
}

// Colores: cualquier formato → [r, g, b, a] (0–255, a 0–1)
function parseColor(t) {
    t = t.trim();
    var m;
    if ((m = t.match(/^#([0-9a-f]{3,8})$/i))) {
        var h = m[1];
        if (h.length === 3 || h.length === 4) h = h.split("").map(function (c) { return c + c; }).join("");
        if (h.length !== 6 && h.length !== 8) throw new Error("Color no válido");
        return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16),
                h.length === 8 ? parseInt(h.slice(6, 8), 16) / 255 : 1];
    }
    var n = (t.match(/[\d.]+%?/g) || []).map(function (v) { return v; });
    var num = function (v, max) { return v.slice(-1) === "%" ? parseFloat(v) / 100 * max : parseFloat(v); };
    var alpha = n.length > 3 ? num(n[3], 1) : 1;
    if (/^rgb/i.test(t)) return [num(n[0], 255), num(n[1], 255), num(n[2], 255), alpha];
    if (/^hsl/i.test(t)) {
        var hh = parseFloat(n[0]) / 360, ss = parseFloat(n[1]) / 100, ll = parseFloat(n[2]) / 100;
        var f = function (k) {
            var kk = (k + hh * 12) % 12, a = ss * Math.min(ll, 1 - ll);
            return Math.round(255 * (ll - a * Math.max(-1, Math.min(kk - 3, 9 - kk, 1))));
        };
        return [f(0), f(8), f(4), alpha];
    }
    throw new Error("Color no válido");
}
function hex2(v) { return ("0" + Math.round(v).toString(16)).slice(-2); }
function toHex(c) { return "#" + hex2(c[0]) + hex2(c[1]) + hex2(c[2]) + (c[3] < 1 ? hex2(c[3] * 255) : ""); }
function toRgb(c) {
    var r = Math.round(c[0]), g = Math.round(c[1]), b = Math.round(c[2]);
    return c[3] < 1 ? "rgba(" + r + ", " + g + ", " + b + ", " + +c[3].toFixed(2) + ")" : "rgb(" + r + ", " + g + ", " + b + ")";
}
function toHsl(c) {
    var r = c[0] / 255, g = c[1] / 255, b = c[2] / 255;
    var max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, h = 0, s = 0;
    if (max !== min) {
        var d = max - min;
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
        h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
        h /= 6;
    }
    var out = Math.round(h * 360) + ", " + Math.round(s * 100) + "%, " + Math.round(l * 100) + "%";
    return c[3] < 1 ? "hsla(" + out + ", " + +c[3].toFixed(2) + ")" : "hsl(" + out + ")";
}

// Abre el gestor de archivos sin depender de xdg-open: Thunar (si no está, Nautilus).
// open_fm CARPETA · open_fm --select ARCHIVO (abre su carpeta con el archivo seleccionado)
var FILEMANAGER =
    'open_fm() {\n' +
    '  sel=; [ "$1" = --select ] && { sel=1; shift; }\n' +
    '  if command -v thunar >/dev/null; then\n' +
    '    if [ -n "$sel" ]; then\n' +
    '      uri=$(python3 -I -c "import sys, urllib.parse as u; print(\'file://\' + u.quote(sys.argv[1]))" "$(dirname "$1")")\n' +
    '      busctl --user call org.xfce.FileManager /org/xfce/FileManager org.xfce.FileManager \\\n' +
    '        DisplayFolderAndSelect ssss "$uri" "$(basename "$1")" "" "" >/dev/null 2>&1 && exit 0\n' +
    '      exec thunar "$(dirname "$1")"\n' +
    '    fi\n' +
    '    exec thunar "$1"\n' +
    '  elif command -v nautilus >/dev/null; then\n' +
    '    if [ -n "$sel" ]; then exec nautilus --new-window --select "$1"; else exec nautilus --new-window "$1"; fi\n' +
    '  else\n' +
    '    if [ -n "$sel" ]; then exec xdg-open "$(dirname "$1")"; else exec xdg-open "$1"; fi\n' +
    '  fi\n' +
    '}\n';

function expandHome(p, home) { return p.trim().replace(/^~(?=\/|$)/, home); }

// ───────────── Acciones ─────────────
var ACTIONS = [
    // Formato
    { id: "trim", group: "Formato", icon: 0xF0B6B, label: "Quitar espacios al inicio y al final",
      when: function (k, t) { return t !== t.trim(); }, run: function (t) { return t.trim(); } },
    { id: "squash", group: "Formato", icon: 0xF0A6E, label: "Unir en una sola línea",
      when: function (k, t) { return !isOneLine(t); }, run: function (t) { return t.split(/\s+/).join(" ").trim(); } },
    { id: "noblank", group: "Formato", icon: 0xF0B6B, label: "Quitar líneas vacías",
      when: function (k, t) { return /\n\s*\n/.test(t); },
      run: function (t) { return t.split("\n").filter(function (l) { return l.trim(); }).join("\n"); } },
    { id: "trimlines", group: "Formato", icon: 0xF0B6B, label: "Quitar espacios al final de cada línea",
      when: function (k, t) { return /[ \t]+\n/.test(t); }, run: function (t) { return perLine(t, function (l) { return l.replace(/\s+$/, ""); }); } },
    { id: "dedent", group: "Formato", icon: 0xF0277, label: "Quitar la sangría común",
      when: function (k, t) { return !isOneLine(t) && /^[ \t]+\S/m.test(t); },
      run: function (t) {
          var lines = t.split("\n");
          var min = Infinity;
          lines.forEach(function (l) { if (l.trim()) min = Math.min(min, l.match(/^[ \t]*/)[0].length); });
          return lines.map(function (l) { return l.slice(min === Infinity ? 0 : min); }).join("\n");
      } },
    { id: "sort", group: "Formato", icon: 0xF04BA, label: "Ordenar líneas (A→Z)",
      when: function (k, t) { return !isOneLine(t); },
      run: function (t) { return t.split("\n").sort(function (a, b) { return a.localeCompare(b); }).join("\n"); } },
    { id: "unique", group: "Formato", icon: 0xF04BA, label: "Quitar líneas duplicadas",
      when: function (k, t) { return !isOneLine(t); },
      run: function (t) { var seen = {}; return t.split("\n").filter(function (l) { return seen[l] ? false : (seen[l] = true); }).join("\n"); } },

    // Mayúsculas y nombres
    { id: "camel", group: "Nombres", icon: 0xF0B34, label: "camelCase",
      when: naming,
      run: function (t) { var w = words(t); return w.length ? w[0] + w.slice(1).map(cap).join("") : t; } },
    { id: "pascal", group: "Nombres", icon: 0xF0B34, label: "PascalCase",
      when: naming, run: function (t) { return words(t).map(cap).join(""); } },
    { id: "snake", group: "Nombres", icon: 0xF0B34, label: "snake_case",
      when: naming, run: function (t) { return words(t).join("_"); } },
    { id: "constant", group: "Nombres", icon: 0xF0B34, label: "CONSTANT_CASE",
      when: naming, run: function (t) { return words(t).join("_").toUpperCase(); } },
    { id: "kebab", group: "Nombres", icon: 0xF0B34, label: "kebab-case",
      when: naming, run: function (t) { return words(t).join("-"); } },
    { id: "upper", group: "Nombres", icon: 0xF0B34, label: "MAYÚSCULAS",
      when: function (k, t) { return (k === "text" || k === "code") && t !== t.toUpperCase(); }, run: function (t) { return t.toUpperCase(); } },
    { id: "lower", group: "Nombres", icon: 0xF0B34, label: "minúsculas",
      when: function (k, t) { return (k === "text" || k === "code" || k === "color" || k === "uuid") && t !== t.toLowerCase(); }, run: function (t) { return t.toLowerCase(); } },
    { id: "title", group: "Nombres", icon: 0xF0B34, label: "Tipo Título",
      when: function (k, t) { return k === "text"; },
      run: function (t) { return t.toLowerCase().replace(/(^|[\s\-_(])(\S)/g, function (m, a, b) { return a + b.toUpperCase(); }); } },

    // JSON
    { id: "jsonfmt", group: "JSON", icon: 0xF0626, label: "Formatear JSON",
      when: function (k) { return k === "json"; },
      run: function (t) { try { return JSON.stringify(JSON.parse(t), null, 2); } catch (e) { throw new Error("JSON no válido: " + e.message); } } },
    { id: "jsonmin", group: "JSON", icon: 0xF0626, label: "Minificar JSON",
      when: function (k) { return k === "json"; },
      run: function (t) { try { return JSON.stringify(JSON.parse(t)); } catch (e) { throw new Error("JSON no válido: " + e.message); } } },
    { id: "jsonsort", group: "JSON", icon: 0xF0626, label: "Formatear JSON con claves ordenadas",
      when: function (k) { return k === "json"; },
      run: function (t) {
          var sortKeys = function (v) {
              if (Array.isArray(v)) return v.map(sortKeys);
              if (v && typeof v === "object") {
                  var o = {};
                  Object.keys(v).sort().forEach(function (key) { o[key] = sortKeys(v[key]); });
                  return o;
              }
              return v;
          };
          try { return JSON.stringify(sortKeys(JSON.parse(t)), null, 2); } catch (e) { throw new Error("JSON no válido: " + e.message); }
      } },
    { id: "jsonstr", group: "JSON", icon: 0xF0626, label: "Escapar como cadena JSON",
      when: function () { return true; }, run: function (t) { return JSON.stringify(t); } },
    { id: "jsonunstr", group: "JSON", icon: 0xF0626, label: "Desescapar cadena JSON",
      when: function (k, t) { return /^\s*".*"\s*$/.test(t); },
      run: function (t) { var v = JSON.parse(t.trim()); if (typeof v !== "string") throw new Error("No es una cadena JSON"); return v; } },

    // Codificar
    { id: "b64enc", group: "Codificar", icon: 0xF0B2E, label: "Codificar en Base64",
      when: function () { return true; }, run: b64encode },
    { id: "b64dec", group: "Codificar", icon: 0xF0B2E, label: "Decodificar Base64",
      when: function (k, t) { return looksBase64(t); }, run: b64decode },
    { id: "urlenc", group: "Codificar", icon: 0xF0337, label: "Codificar para URL (%20…)",
      when: function (k, t) { return /[^A-Za-z0-9\-_.~]/.test(t); }, run: function (t) { return encodeURIComponent(t); } },
    { id: "urldec", group: "Codificar", icon: 0xF0337, label: "Decodificar URL",
      when: function (k, t) { return /%[0-9a-f]{2}|\+/i.test(t); },
      run: function (t) { try { return decodeURIComponent(t.replace(/\+/g, " ")); } catch (e) { throw new Error("Codificación URL no válida"); } } },
    { id: "shellq", group: "Codificar", icon: 0xF018D, label: "Entrecomillar para la shell",
      when: function () { return true; }, run: function (t) { return "'" + t.replace(/'/g, "'\\''") + "'"; } },
    { id: "htmlesc", group: "Codificar", icon: 0xF0169, label: "Escapar HTML (&lt; &gt; &amp;)",
      when: function (k, t) { return /[<>&"']/.test(t); },
      run: function (t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;"); } },
    { id: "htmlunesc", group: "Codificar", icon: 0xF0169, label: "Desescapar HTML",
      when: function (k, t) { return /&(lt|gt|amp|quot|#39|#x?[0-9a-f]+);/i.test(t); },
      run: function (t) {
          return t.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'")
                  .replace(/&#x([0-9a-f]+);/gi, function (m, h) { return String.fromCodePoint(parseInt(h, 16)); })
                  .replace(/&#(\d+);/g, function (m, d) { return String.fromCodePoint(parseInt(d, 10)); })
                  .replace(/&amp;/g, "&");
      } },
    { id: "md5", group: "Codificar", icon: 0xF0306, label: "Hash MD5",
      when: function () { return true; }, run: function (t) { return Qt.md5(t); } },

    // Colores
    { id: "hex", group: "Color", icon: 0xF03D8, label: "Convertir a HEX",
      when: function (k, t) { return k === "color" && !/^#/.test(t.trim()); }, run: function (t) { return toHex(parseColor(t)); } },
    { id: "rgb", group: "Color", icon: 0xF03D8, label: "Convertir a rgb()",
      when: function (k, t) { return k === "color" && !/^rgb/i.test(t.trim()); }, run: function (t) { return toRgb(parseColor(t)); } },
    { id: "hsl", group: "Color", icon: 0xF03D8, label: "Convertir a hsl()",
      when: function (k, t) { return k === "color" && !/^hsl/i.test(t.trim()); }, run: function (t) { return toHsl(parseColor(t)); } },

    // Números
    { id: "tohex", group: "Número", icon: 0xF03A0, label: "Decimal → hexadecimal",
      when: function (k, t) { return /^-?\d+$/.test(t.trim()); }, run: function (t) { return "0x" + parseInt(t, 10).toString(16).toUpperCase(); } },
    { id: "tobin", group: "Número", icon: 0xF03A0, label: "Decimal → binario",
      when: function (k, t) { return /^\d+$/.test(t.trim()); }, run: function (t) { return "0b" + parseInt(t, 10).toString(2); } },
    { id: "fromhex", group: "Número", icon: 0xF03A0, label: "Hexadecimal → decimal",
      when: function (k, t) { return /^(0x)?[0-9a-f]+$/i.test(t.trim()) && /[a-f]|^0x/i.test(t.trim()); },
      run: function (t) { return String(parseInt(t.trim().replace(/^0x/i, ""), 16)); } },
    { id: "unixdate", group: "Número", icon: 0xF00ED, label: "Timestamp Unix → fecha",
      when: function (k, t) { return /^\d{10}(\d{3})?$/.test(t.trim()); },
      run: function (t) { var n = parseInt(t, 10); return new Date(t.trim().length === 13 ? n : n * 1000).toISOString(); } },

    // Enlaces
    { id: "untrack", group: "Enlace", icon: 0xF0337, label: "Quitar parámetros de seguimiento",
      when: function (k, t) { return k === "url" && /[?&](utm_\w+|fbclid|gclid|si|ref)=/.test(t); },
      run: function (t) {
          var parts = t.trim().split("?");
          if (parts.length < 2) return t.trim();
          var hash = parts[1].split("#");
          var q = hash[0].split("&").filter(function (p) { return !/^(utm_\w+|fbclid|gclid|si|ref)=/.test(p); });
          return parts[0] + (q.length ? "?" + q.join("&") : "") + (hash[1] ? "#" + hash[1] : "");
      } },
    { id: "domain", group: "Enlace", icon: 0xF01E7, label: "Solo el dominio",
      when: function (k) { return k === "url"; },
      run: function (t) { var m = t.trim().match(/^(?:\w+:\/\/)?([^\/?#:]+)/); return m ? m[1] : t; } },
    { id: "openurl", group: "Abrir", icon: 0xF03CC, label: "Abrir en el navegador", opens: true,
      when: function (k) { return k === "url"; },
      run: function (t) { var u = t.trim(); return { open: ["xdg-open", /^\w+:\/\//.test(u) ? u : "https://" + u] }; } },
    { id: "mailto", group: "Abrir", icon: 0xF01EE, label: "Escribir un correo", opens: true,
      when: function (k) { return k === "email"; }, run: function (t) { return { open: ["xdg-open", "mailto:" + t.trim()] }; } },

    // Rutas
    { id: "basename", group: "Ruta", icon: 0xF0214, label: "Solo el nombre del archivo",
      when: function (k) { return k === "path"; }, run: function (t) { return t.trim().replace(/\/+$/, "").split("/").pop(); } },
    { id: "dirname", group: "Ruta", icon: 0xF024B, label: "Solo la carpeta",
      when: function (k) { return k === "path"; },
      run: function (t) { var p = t.trim().replace(/\/+$/, ""); var i = p.lastIndexOf("/"); return i > 0 ? p.slice(0, i) : "/"; } },
    { id: "abspath", group: "Ruta", icon: 0xF024B, label: "Ruta absoluta (expandir ~)",
      when: function (k, t) { return k === "path" && /^~/.test(t.trim()); },
      run: function (t, ctx) { return expandHome(t, ctx.home); } },
    { id: "openpath", group: "Abrir", icon: 0xF024B, label: "Abrir con la app predeterminada", opens: true,
      when: function (k) { return k === "path"; },
      run: function (t, ctx) {
          // Las carpetas, siempre en el gestor de archivos (xdg-open puede tener mal la asociación)
          return { open: ["sh", "-c", FILEMANAGER + '[ -d "$1" ] && open_fm "$1" || exec xdg-open "$1"', "sh", expandHome(t, ctx.home)] };
      } },
    { id: "openfolder", group: "Abrir", icon: 0xF0770, label: "Mostrar en el gestor de archivos", opens: true,
      when: function (k) { return k === "path"; },
      run: function (t, ctx) {
          // Carpeta → se abre · Archivo → se abre su carpeta con el archivo seleccionado
          // · Ruta que no existe → la carpeta más cercana que sí exista
          return { open: ["sh", "-c", FILEMANAGER +
              'p="${1%/}"; [ -z "$p" ] && p=/\n' +
              'while [ ! -e "$p" ] && [ "$p" != / ]; do p=$(dirname "$p"); done\n' +
              'if [ -d "$p" ]; then open_fm "$p"; else open_fm --select "$p"; fi',
              "sh", expandHome(t, ctx.home)] };
      } },
    { id: "opencode", group: "Abrir", icon: 0xF0A1E, label: "Abrir en VS Code", opens: true,
      when: function (k) { return k === "path"; },
      run: function (t, ctx) { return { open: ["code", expandHome(t, ctx.home)] }; } }
];

// Grupos que van primero según el tipo de contenido
var PRIORITY = {
    url: ["Abrir", "Enlace"], email: ["Abrir"], path: ["Abrir", "Ruta"], color: ["Color"],
    json: ["JSON"], number: ["Número"], code: ["Formato", "Nombres"], command: ["Codificar"], text: ["Nombres", "Formato"]
};

// Acciones aplicables a un texto, opcionalmente filtradas por búsqueda
function forEntry(kind, text, query) {
    if (kind === "image" || !text) return [];
    var q = (query || "").toLowerCase().trim();
    var prio = PRIORITY[kind] || [];
    var rank = function (a) { var i = prio.indexOf(a.group); return i < 0 ? prio.length : i; };
    return ACTIONS.filter(function (a) {
        try { if (!a.when(kind, text)) return false; } catch (e) { return false; }
        if (!q) return true;
        return (a.label + " " + a.group + " " + a.id).toLowerCase().indexOf(q) >= 0;
    }).map(function (a, i) { return { a: a, i: i }; })
      .sort(function (x, y) { return rank(x.a) - rank(y.a) || x.i - y.i; })   // orden estable
      .map(function (x) { return x.a; });
}

// Ejecuta una acción: { text } | { open } | { error }
function apply(action, text, ctx) {
    try {
        var r = action.run(text, ctx || {});
        if (r && r.open) return { open: r.open };
        return { text: String(r) };
    } catch (e) {
        return { error: e.message || String(e) };
    }
}
