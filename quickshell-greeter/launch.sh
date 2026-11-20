#!/bin/sh
# Lo ejecuta greetd COMO TU USUARIO al iniciar sesión:  launch.sh <id-de-sesión>
# greetd une los argumentos con espacios y los pasa a "sh -c", así que aquí solo
# llega un id simple (labwc, gnome…) y todo lo demás se resuelve en este script.
id="$1"
case "$id" in *[!A-Za-z0-9._-]*|"") id=labwc ;; esac

# Consola limpia mientras arranca la sesión (no se ve texto de fondo)
printf '\033[2J\033[3J\033[H\033[?25l'

# labwc: session.sh reproduce el entorno que daba GDM (y guarda su propio registro)
if [ "$id" = labwc ] && [ -x "$HOME/.config/labwc/session.sh" ]; then
    exec "$HOME/.config/labwc/session.sh"
fi

# Otras sesiones: el Exec= de su .desktop, desde la shell de login
cmd=$(grep -m1 '^Exec=' "/usr/share/wayland-sessions/$id.desktop" 2>/dev/null | cut -d= -f2-)
[ -n "$cmd" ] || cmd=labwc
mkdir -p "$HOME/.local/state"
exec >"$HOME/.local/state/session-$id.log" 2>&1
exec "${SHELL:-/bin/sh}" -l -c "exec $cmd"
