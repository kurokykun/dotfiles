#!/bin/sh
# Abre la carpeta de un archivo en Thunar con el archivo seleccionado (si no hay Thunar, Nautilus).
f="$1"
[ -e "$f" ] || { exec xdg-open "$(dirname "$f")"; }
if command -v thunar >/dev/null; then
    uri=$(python3 -I -c 'import sys, urllib.parse as u; print("file://" + u.quote(sys.argv[1]))' "$(dirname "$f")")
    busctl --user call org.xfce.FileManager /org/xfce/FileManager org.xfce.FileManager \
        DisplayFolderAndSelect ssss "$uri" "$(basename "$f")" "" "" >/dev/null 2>&1 && exit 0
    exec thunar "$(dirname "$f")"
elif command -v nautilus >/dev/null; then
    exec nautilus --new-window --select "$f"
fi
exec xdg-open "$(dirname "$f")"
