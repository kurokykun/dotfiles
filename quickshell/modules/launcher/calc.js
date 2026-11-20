.pragma library

// Calculadora del lanzador: parser recursivo (sin eval).
// Soporta + - * / ^ %, paréntesis, coma o punto decimal, × ÷,
// constantes pi y e, y funciones: sqrt sin cos tan asin acos atan log ln abs round floor ceil.
// "15%" = 0.15 · "200 * 15%" = 30 · "2^10" = 1024

var FUNCS = {
    sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
    sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
    log: Math.log10, ln: Math.log, exp: Math.exp
};
var CONSTS = { pi: Math.PI, "π": Math.PI, e: Math.E };

function tokenize(s) {
    var t = [], i = 0;
    s = s.replace(/×/g, "*").replace(/÷/g, "/").replace(/\*\*/g, "^");
    while (i < s.length) {
        var c = s[i];
        if (/\s/.test(c)) { i++; continue; }
        var num = s.slice(i).match(/^(\d+([.,]\d*)?|[.,]\d+)([eE][+-]?\d+)?/);
        if (num) { t.push({ k: "n", v: parseFloat(num[0].replace(",", ".")) }); i += num[0].length; continue; }
        var id = s.slice(i).match(/^[a-zA-Zπ]+/);
        if (id) { t.push({ k: "id", v: id[0].toLowerCase() }); i += id[0].length; continue; }
        if ("+-*/^%()".indexOf(c) >= 0) { t.push({ k: c }); i++; continue; }
        throw "carácter no válido";
    }
    return t;
}

function parse(tokens) {
    var p = 0;
    function peek() { return tokens[p]; }
    function eat(k) { if (peek() && peek().k === k) { p++; return true; } return false; }

    function expr() {          // + -
        var v = term();
        for (;;) {
            if (eat("+")) v += term();
            else if (eat("-")) v -= term();
            else return v;
        }
    }
    function term() {          // * /
        var v = unary();
        for (;;) {
            if (eat("*")) v *= unary();
            else if (eat("/")) v /= unary();
            else if (peek() && (peek().k === "(" || peek().k === "id" || peek().k === "n")) v *= unary(); // 2pi, 3(4+1)
            else return v;
        }
    }
    function unary() {         // el signo va después de la potencia: -2^2 = -4
        if (eat("-")) return -unary();
        if (eat("+")) return unary();
        return power();
    }
    function power() {         // ^ (asociativo por la derecha; admite 2^-1)
        var b = postfix();
        if (eat("^")) return Math.pow(b, unary());
        return b;
    }
    function postfix() {       // 15%
        var v = atom();
        while (eat("%")) v /= 100;
        return v;
    }
    function atom() {
        var t = peek();
        if (!t) throw "incompleto";
        if (t.k === "n") { p++; return t.v; }
        if (eat("(")) { var v = expr(); if (!eat(")")) throw "falta )"; return v; }
        if (t.k === "id") {
            p++;
            if (FUNCS[t.v]) {
                if (!eat("(")) return FUNCS[t.v](unary());   // "sqrt 16"
                var a = expr(); if (!eat(")")) throw "falta )";
                return FUNCS[t.v](a);
            }
            if (CONSTS[t.v] !== undefined) return CONSTS[t.v];
        }
        throw "no válido";
    }

    var v = expr();
    if (p < tokens.length) throw "sobra texto";
    return v;
}

// Devuelve el número o null si la expresión no es válida
function evaluate(s) {
    try {
        var v = parse(tokenize(s));
        return isFinite(v) ? v : null;
    } catch (e) {
        return null;
    }
}

// ¿Parece una operación? (para detectarla sin el prefijo "=")
function looksLikeMath(s) {
    return /^[\d(.,πa-z\s-]/i.test(s) && /[\d)πe]\s*[+\-*/^×÷%]|^\s*(sqrt|sin|cos|tan|log|ln|abs)\b/i.test(s)
        && evaluate(s) !== null;
}

function format(v) {
    if (Math.abs(v) >= 1e15 || (Math.abs(v) < 1e-6 && v !== 0)) return v.toExponential(6).replace(/\.?0+e/, "e");
    return String(parseFloat(v.toPrecision(12)));
}
