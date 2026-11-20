pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Tema del escritorio.
// Los colores principales salen del fondo (services/ThemeEngine.qml → matugen) y se leen de
// ~/.local/state/quickshell/colors.json. Al cambiar, TODA la interfaz transita suavemente (0,8 s).
// Sin ese archivo se usa la paleta original (cielo azul noche + horizonte naranja).
Singleton {
    id: theme

    // ───── Colores dinámicos (vienen del fondo) ─────
    property color base: "#060c1a"          // el más oscuro: velos y sombras
    property color bgSolid: "#0b1426"       // paneles opacos
    property color fg: "#e6ecf7"            // texto principal
    property color dim: "#8692ad"           // texto secundario
    property color accent: "#ff8a3d"        // acento principal
    property color accent2: "#ff4f6d"       // acento secundario
    property color textOnAccent: "#1a0f05"      // texto sobre el acento

    readonly property int colorAnim: 800
    Behavior on base { ColorAnimation { duration: theme.colorAnim; easing.type: Easing.InOutQuad } }
    Behavior on bgSolid { ColorAnimation { duration: theme.colorAnim; easing.type: Easing.InOutQuad } }
    Behavior on fg { ColorAnimation { duration: theme.colorAnim; easing.type: Easing.InOutQuad } }
    Behavior on dim { ColorAnimation { duration: theme.colorAnim; easing.type: Easing.InOutQuad } }
    Behavior on accent { ColorAnimation { duration: theme.colorAnim; easing.type: Easing.InOutQuad } }
    Behavior on accent2 { ColorAnimation { duration: theme.colorAnim; easing.type: Easing.InOutQuad } }
    Behavior on textOnAccent { ColorAnimation { duration: theme.colorAnim; easing.type: Easing.InOutQuad } }

    // Derivados (siguen a los dinámicos)
    readonly property color bar: Qt.alpha(bgSolid, 0.97)    // fondo de la barra (casi opaco)
    readonly property color bg: Qt.alpha(bgSolid, 0.92)     // dock y paneles

    // ───── Neutros (capas blancas translúcidas: valen con cualquier fondo) ─────
    readonly property color pill: Qt.rgba(1, 1, 1, 0.06)
    readonly property color surface: Qt.rgba(1, 1, 1, 0.08)
    readonly property color surfaceHover: Qt.rgba(1, 1, 1, 0.14)
    readonly property color border: Qt.rgba(1, 1, 1, 0.08)

    // ───── Colores con significado (fijos a propósito) ─────
    readonly property color blue: "#5aa9ff"
    readonly property color green: "#7ee0a1"
    readonly property color yellow: "#ffd166"
    readonly property color red: "#ff5c5c"

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 13
    readonly property int barHeight: 38
    readonly property int pillHeight: 28
    readonly property int gap: 8
    readonly property int radius: 10

    // Animaciones
    readonly property int animFast: 140
    readonly property int animNormal: 260

    // ───── Lectura de los colores generados ─────
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text()).colors;
                if (!c) return;
                for (const k of ["base", "bgSolid", "fg", "dim", "accent", "accent2", "textOnAccent"])
                    if (c[k]) theme[k] = c[k];
            } catch (e) {}
        }
    }
}
