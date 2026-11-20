import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// Pantalla de bloqueo.
//  · Bloqueo real: protocolo ext-session-lock (WlSessionLock). El compositor no muestra
//    nada más ni pasa el teclado a otras apps hasta que Lock.locked vuelve a false.
//  · Vista previa: la misma interfaz en una capa normal; no bloquea nada.
// Ver services/Lock.qml para la autenticación y las notas de seguridad.
Scope {
    WlSessionLock {
        id: sessionLock
        locked: Lock.locked
        onSecureChanged: Lock.secure = secure

        // Una superficie por monitor
        WlSessionLockSurface {
            color: Theme.bgSolid
            LockSurface {}
        }
    }

    // Vista previa: solo existe mientras se usa (carga perezosa)
    LazyLoader {
        active: Lock.preview
        PanelWindow {
        visible: Lock.preview
        screen: Ui.popupScreen ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-lock-preview"
        WlrLayershell.keyboardFocus: Lock.preview ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: Theme.bgSolid

        LockSurface { preview: true }
    }
    }
}
