#!/bin/sh
# Actualiza SOLO los archivos del greeter en /etc/greetd/quickshell.
# No para greetd ni toca config.toml / PAM: es seguro con la sesión abierta.
# Los cambios se ven la próxima vez que aparezca el greeter (al cerrar sesión o reiniciar).
# Uso:  sudo sh ~/.config/quickshell-greeter/update.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "Ejecuta con sudo"; exit 1; }
SRC="$(cd "$(dirname "$0")" && pwd)"
install -m 644 "$SRC/shell.qml" "$SRC/wallpaper.jpg" /etc/greetd/quickshell/
install -m 755 "$SRC/start.sh" "$SRC/launch.sh" /etc/greetd/quickshell/
echo "Greeter actualizado. Se verá en el próximo inicio de sesión."
