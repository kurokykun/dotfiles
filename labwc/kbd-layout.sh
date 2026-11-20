#!/bin/sh
# Cambia a la siguiente distribución de teclado de labwc.
# Rota XKB_DEFAULT_LAYOUT (y XKB_DEFAULT_VARIANT si existe) en environment.d/keyboard.env
# y recarga labwc, que aplica la primera de la lista. La barra de Quickshell vigila el archivo.
f="$HOME/.config/labwc/environment.d/keyboard.env"
[ -f "$f" ] || exit 1

rotate() { # "a,b,c" -> "b,c,a"
    case "$1" in *,*) echo "${1#*,},${1%%,*}" ;; *) echo "$1" ;; esac
}

lay=$(sed -n 's/^XKB_DEFAULT_LAYOUT=//p' "$f")
var=$(sed -n 's/^XKB_DEFAULT_VARIANT=//p' "$f")
case "$lay" in *,*) ;; *) exit 0 ;; esac

tmp="$f.tmp"
sed -e "s/^XKB_DEFAULT_LAYOUT=.*/XKB_DEFAULT_LAYOUT=$(rotate "$lay")/" \
    -e "s/^XKB_DEFAULT_VARIANT=.*/XKB_DEFAULT_VARIANT=$(rotate "$var")/" "$f" > "$tmp" && mv "$tmp" "$f"

labwc --reconfigure
