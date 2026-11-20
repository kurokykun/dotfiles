#!/bin/sh
# Guarda en el historial (cliphist) lo que se copia. Lo lanzan dos procesos
# "wl-paste --watch" desde ~/.config/labwc/autostart (uno para texto y otro para imágenes),
# así la captura sigue funcionando aunque Quickshell se reinicie.
#
# No se guarda nada si:
#  · la app marca el contenido como sensible (gestores de contraseñas)  → CLIPBOARD_STATE=sensitive
#  · el portapapeles se vació                                           → CLIPBOARD_STATE=nil|clear
#  · el historial está en pausa (modo incógnito)                         → existe $PAUSE

PAUSE="${XDG_RUNTIME_DIR:-/tmp}/quickshell-clipboard.paused"
MAX_ITEMS=500

case "${CLIPBOARD_STATE:-data}" in
    sensitive|nil|clear) cat >/dev/null; exit 0 ;;
esac
if [ -e "$PAUSE" ]; then
    cat >/dev/null
    exit 0
fi

exec cliphist -max-items "$MAX_ITEMS" store
