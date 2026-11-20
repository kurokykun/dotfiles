#!/bin/sh
# Arranque de la sesión labwc desde el greeter (greetd + Quickshell).
# Reproduce el entorno que daba GDM:
#   · idioma y formatos de /etc/locale.conf (LANG, LC_TIME=es_CU…)
#   · variables de ~/.config/environment.d (ANDROID_HOME, PATH…)
#   · shell de login (zsh -l → /etc/profile, ~/.zshenv, ~/.local/bin)
# Prueba sin arrancar nada:  SESSION_DRYRUN=1 ~/.config/labwc/session.sh

set -a
[ -r /etc/locale.conf ] && . /etc/locale.conf
# Mismo orden que systemd: sistema → /etc → usuario
# (/usr/lib/environment.d trae CUDA_DISABLE_PERF_BOOST del paquete de NVIDIA)
for f in /usr/lib/environment.d/*.conf /etc/environment.d/*.conf "$HOME"/.config/environment.d/*.conf; do
    [ -r "$f" ] && . "$f"
done
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=labwc
XDG_CURRENT_DESKTOP=labwc:wlroots
DESKTOP_SESSION=labwc
set +a

# Registro: greetd descarta la salida de la sesión, así que va a un archivo
# (el anterior se conserva como .old)
if [ -z "$SESSION_DRYRUN" ]; then
    LOG="$HOME/.local/state/labwc-session.log"
    mkdir -p "$HOME/.local/state"
    [ -f "$LOG" ] && mv -f "$LOG" "$LOG.old"
    exec >"$LOG" 2>&1
    echo "== $(date '+%F %T') session.sh"
    echo "   SHELL=$SHELL XDG_SEAT=$XDG_SEAT XDG_VTNR=$XDG_VTNR XDG_SESSION_ID=$XDG_SESSION_ID"
    echo "   XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WLR_DRM_DEVICES=$WLR_DRM_DEVICES"
fi

if [ -n "$SESSION_DRYRUN" ]; then
    exec "${SHELL:-/bin/sh}" -l -c 'env | sort'
fi

exec "${SHELL:-/bin/sh}" -l -c 'exec labwc'
