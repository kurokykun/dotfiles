#!/usr/bin/env python3
"""Aplica la paleta del tema automático (colors.json) a labwc: bordes de ventana, menús, Alt+Tab y
la vista previa de ajuste. Rellena ~/.config/labwc/themerc-override.template → themerc-override
y recarga labwc. Lo llama services/ThemeEngine.qml solo cuando cambia el tema."""
import json, os, subprocess
H = os.path.expanduser("~")
c = json.load(open(H + "/.local/state/quickshell/colors.json"))["colors"]
def rgb(h): h = h.lstrip("#"); return [int(h[i:i + 2], 16) for i in (0, 2, 4)]
def hexc(v): return "#" + "".join("%02x" % max(0, min(255, round(x))) for x in v)
def mix(a, b, t): return hexc([x * (1 - t) + y * t for x, y in zip(rgb(a), rgb(b))])
vals = {
    "accent": c["accent"], "bg": c["bgSolid"], "base": c["base"], "fg": c["fg"], "dim": c["dim"],
    "onaccent": c["textOnAccent"],
    "border1": mix(c["bgSolid"], c["fg"], 0.10),   # bordes de ventanas inactivas, separadores
    "border2": mix(c["bgSolid"], c["fg"], 0.16),   # bordes de menús y pantallas emergentes
}
tpl = open(H + "/.config/labwc/themerc-override.template").read()
out = "\n".join(l for l in tpl.format_map(vals).splitlines() if not l.startswith("# PLANTILLA") and not l.startswith("# Edita ESTE"))
dst = H + "/.config/labwc/themerc-override"
if not os.path.exists(dst) or open(dst).read() != out + "\n":
    open(dst, "w").write(out + "\n")
    subprocess.run(["labwc", "--reconfigure"], check=False)
