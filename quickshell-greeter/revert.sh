#!/bin/sh
# VOLVER A GDM — deshace activate.sh. Uso: sudo sh ~/.config/quickshell-greeter/revert.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "Ejecuta con sudo"; exit 1; }
systemctl disable greetd 2>/dev/null || true
systemctl enable gdm
echo "GDM vuelve a ser el gestor de inicio. Reinicia: sudo reboot"
