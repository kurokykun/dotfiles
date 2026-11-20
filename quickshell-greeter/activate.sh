#!/bin/sh
# PASO 2 — Usa greetd como gestor de inicio en lugar de GDM (GDM queda instalado).
# Uso:  sudo sh ~/.config/quickshell-greeter/activate.sh   y después reinicia.
set -eu
[ "$(id -u)" = 0 ] || { echo "Ejecuta con sudo"; exit 1; }
[ -x /etc/greetd/quickshell/start.sh ] || { echo "Primero ejecuta install.sh"; exit 1; }
systemctl stop greetd 2>/dev/null || true          # parar la prueba en VT 7
sed -i 's/^vt = .*/vt = 1/' /etc/greetd/config.toml
grep -q '^vt = 1' /etc/greetd/config.toml
systemctl disable gdm
systemctl enable greetd
echo
echo "greetd activado (GDM sigue instalado). Reinicia para usarlo."
echo "Si algo falla al arrancar: Ctrl+Alt+F3, entra con tu usuario y ejecuta"
echo "   sudo sh ~/.config/quickshell-greeter/revert.sh && sudo reboot"
