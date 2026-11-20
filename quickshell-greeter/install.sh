#!/bin/sh
# PASO 1 — Instala greetd + greeter de Quickshell en MODO PRUEBA (VT 7).
# NO cambia el gestor de inicio: GDM sigue arrancando como siempre.
# Uso:  sudo sh ~/.config/quickshell-greeter/install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "Ejecuta con sudo"; exit 1; }
SRC="$(cd "$(dirname "$0")" && pwd)"
STAMP=$(date +%Y%m%d-%H%M%S)

echo "==> Paquetes (greetd, cage)"
pacman -S --needed --noconfirm greetd cage
# Parar solo una prueba en VT 7; si greetd ya es el gestor de inicio, NO (cerraría tu sesión)
systemctl is-enabled greetd >/dev/null 2>&1 || systemctl stop greetd 2>/dev/null || true

echo "==> Copias de seguridad en /etc/greetd/backup-$STAMP"
mkdir -p "/etc/greetd/backup-$STAMP"
[ -f /etc/greetd/config.toml ] && cp -a /etc/greetd/config.toml "/etc/greetd/backup-$STAMP/"
[ -f /etc/pam.d/greetd ] && cp -a /etc/pam.d/greetd "/etc/greetd/backup-$STAMP/pam-greetd"

echo "==> Greeter en /etc/greetd/quickshell"
rm -rf /etc/greetd/quickshell
install -d -m 755 /etc/greetd/quickshell
install -m 644 "$SRC/shell.qml" "$SRC/wallpaper.jpg" /etc/greetd/quickshell/
install -m 755 "$SRC/start.sh" "$SRC/launch.sh" /etc/greetd/quickshell/

echo "==> Configuración (vt = 7, modo prueba) y PAM"
install -m 644 "$SRC/config.toml" /etc/greetd/config.toml
install -m 644 "$SRC/pam-greetd" /etc/pam.d/greetd

echo "==> Comprobaciones"
id greeter >/dev/null && echo "   usuario greeter: ok"
command -v agreety >/dev/null && echo "   agreety (respaldo de texto): ok"
systemctl is-enabled gdm >/dev/null 2>&1 && echo "   GDM sigue habilitado: ok"
echo
echo "Listo. Para PROBAR sin cambiar nada del arranque:"
echo "   sudo systemctl start greetd      # aparece el greeter en Ctrl+Alt+F7"
echo "Para volver a tu sesión actual:      Ctrl+Alt+F2"
echo "Para quitar la prueba:               sudo systemctl stop greetd"
