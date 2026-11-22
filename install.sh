#!/bin/sh
# Enlaza esta configuración en ~/.config. No necesita sudo.
# Si ya existe algo en el destino (y no es el enlace correcto), lo renombra a
# <nombre>.pre-dotfiles-<fecha> en lugar de borrarlo.
#
# Uso:  sh ~/dotfiles/install.sh
# El login (greetd) va aparte, con sudo; ver README.md → "Login".
set -eu

DOT="$(cd "$(dirname "$0")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP=$(date +%Y%m%d-%H%M%S)

link() {  # link <origen en el repo> <destino>
    src="$DOT/$1"; dst="$2"
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        echo "   ok       $dst"
        return
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mv "$dst" "$dst.pre-dotfiles-$STAMP"
        echo "   copia    $dst → $dst.pre-dotfiles-$STAMP"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    echo "   enlace   $dst → $src"
}

echo "==> Enlazando en $CFG"
link quickshell                 "$CFG/quickshell"
link quickshell-greeter         "$CFG/quickshell-greeter"
link labwc                      "$CFG/labwc"
link systemd/user/cntlm@.service "$CFG/systemd/user/cntlm@.service"

# Distribución de teclado: no va en git (kbd-layout.sh la reescribe); se crea desde la plantilla
kbd="$DOT/labwc/environment.d/keyboard.env"
if [ ! -e "$kbd" ]; then
    cp "$kbd.example" "$kbd"
    echo "   creado   $kbd (desde keyboard.env.example)"
fi

mkdir -p "$HOME/.local/state/quickshell" "$HOME/Pictures/Wallpapers"
chmod +x "$DOT"/quickshell/scripts/*.sh "$DOT"/quickshell/scripts/*.py \
         "$DOT"/labwc/*.sh "$DOT"/quickshell-greeter/*.sh 2>/dev/null || true

if grep -q '^WLR_DRM_DEVICES=/dev/dri/igpu' "$DOT/labwc/environment" && [ ! -e /dev/dri/igpu ]; then
    echo
    echo "!! AVISO: labwc/environment usa WLR_DRM_DEVICES=/dev/dri/igpu y ese dispositivo no existe."
    echo "   labwc NO arrancará así. Instala la regla udev (README → GPU) o comenta esa línea."
fi

echo
echo "Listo. Pendiente (una sola vez, ver README.md):"
echo "  · Paquetes:       packages.txt"
echo "  · GPUs (opcional): regla udev de labwc/extras/99-gpu-symlinks.rules"
echo "  · Login:          sudo sh ~/.config/quickshell-greeter/install.sh"
