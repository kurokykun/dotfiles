#!/bin/sh
# Uso: screenshot.sh full|area  -> guarda en Imágenes/Capturas y copia al portapapeles
dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Capturas"
mkdir -p "$dir"
file="$dir/captura-$(date +%F_%H-%M-%S).png"

case "$1" in
  area) geom=$(slurp) || exit 0; grim -g "$geom" "$file" ;;
  *)    grim "$file" ;;
esac

wl-copy < "$file"
notify-send -i "$file" "Captura guardada" "$file" 2>/dev/null
