#!/bin/sh
# Lanza el greeter de Quickshell dentro de cage (lo ejecuta greetd como usuario "greeter").
# Si el greeter gráfico falla, cae a agreety (login de texto) para no quedarse sin acceso.

# Datos temporales de Quickshell en el runtime dir del greeter (su $HOME es "/")
RUNDIR="${XDG_RUNTIME_DIR:-/tmp/greeter-$(id -u)}"
mkdir -p "$RUNDIR"
export XDG_CACHE_HOME="$RUNDIR/cache" XDG_STATE_HOME="$RUNDIR/state" XDG_DATA_HOME="$RUNDIR/data"
LOG="$RUNDIR/greeter.log"            # salida de cage y Quickshell (no a la consola)

# Igual que tu sesión: GPU integrada (no se toca nada de NVIDIA), teclado y cursor
[ -e /dev/dri/igpu ] && export WLR_DRM_DEVICES=/dev/dri/igpu
export XKB_DEFAULT_LAYOUT=us
export XCURSOR_THEME=Bibata-Modern-Classic XCURSOR_SIZE=24
export QT_QPA_PLATFORM=wayland
# Sin barra de título ni bordes de ventana
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Consola limpia y sin cursor (no se ve texto en las transiciones)
clear_tty() { printf '\033[2J\033[3J\033[H\033[?25l'; }
clear_tty

# -s: permite Ctrl+Alt+Fn (TTY de rescate) · -d: sin decoraciones de ventana
if cage -s -d -- qs -p /etc/greetd/quickshell >"$LOG" 2>&1; then
    clear_tty
    exit 0
fi

# Respaldo: login de texto (mismo lanzador que el greeter gráfico)
printf '\033[2J\033[H\033[?25h'
echo "El greeter gráfico falló (registro: $LOG). Inicio de sesión en modo texto:"
exec agreety --cmd "/etc/greetd/quickshell/launch.sh labwc"
