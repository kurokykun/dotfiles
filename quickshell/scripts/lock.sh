#!/bin/sh
# Bloquea la sesión con el lock screen de Quickshell.
# Si Quickshell no responde, usa swaylock como respaldo (nunca queda sin bloquear).
# Espera a que el compositor confirme el bloqueo: importante antes de suspender.
WALL="$HOME/.local/state/quickshell/wallpaper"   # enlace al fondo actual (services/Wallpaper.qml)

if qs ipc call lock lock >/dev/null 2>&1; then
    i=0
    while [ $i -lt 30 ]; do                 # hasta 3 s
        [ "$(qs ipc call lock isLocked 2>/dev/null)" = "true" ] && exit 0
        sleep 0.1
        i=$((i + 1))
    done
fi
# Respaldo (si Quickshell ya bloqueó tarde, labwc rechaza este y no pasa nada)
exec swaylock -f -i "$WALL"
