pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Distribución de teclado de labwc. La activa es la primera de XKB_DEFAULT_LAYOUT
// en ~/.config/labwc/environment.d/keyboard.env; el archivo se vigila, así que la
// barra se actualiza sola al cambiar con Super+Espacio (kbd-layout.sh).
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/labwc/kbd-layout.sh"
    property var layouts: []
    readonly property string current: layouts.length > 0 ? layouts[0] : ""
    // Nombre corto en la barra (código xkb → etiqueta); si no está aquí se muestra el código en mayúsculas
    readonly property var names: ({ us: "EN", gb: "EN", latam: "ES", es: "ES" })
    readonly property string label: names[current] ?? current.toUpperCase()

    function next() { Quickshell.execDetached([script]); }

    FileView {
        path: Quickshell.env("HOME") + "/.config/labwc/environment.d/keyboard.env"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = text().match(/^XKB_DEFAULT_LAYOUT=(.*)$/m);
            root.layouts = m ? m[1].trim().split(",").map(s => s.trim()).filter(s => s) : [];
        }
    }
}
