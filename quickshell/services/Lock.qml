pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pam

// Estado y autenticación del lock screen.
//
// Seguridad:
//  · El estado "locked" sobrevive a las recargas de Quickshell (PersistentProperties):
//    guardar un .qml mientras está bloqueado NO desbloquea.
//  · Si Quickshell se cae bloqueado, labwc mantiene la sesión bloqueada y deja que
//    otro bloqueador la reemplace ("replacing abandoned lock"). Recuperación desde TTY:
//      WAYLAND_DISPLAY=wayland-0 swaylock
//  · Solo se desbloquea con PamResult.Success.
//  · preview = la misma pantalla en una ventana normal (sin bloquear nada) para probar.
Singleton {
    id: root

    PersistentProperties {
        id: persist
        reloadableId: "lockState"
        property bool locked: false
    }

    readonly property bool locked: persist.locked
    property bool preview: false
    readonly property bool active: locked || preview

    // Lo pone LockScreen.qml: true cuando el compositor confirma que la sesión está bloqueada
    property bool secure: false

    property bool busy: false           // comprobando la contraseña
    property string message: ""
    property bool messageIsError: false
    property int failures: 0
    signal failed()                     // para la animación de "sacudida"

    function lock() {
        if (persist.locked) return;
        reset();
        preview = false;
        Ui.closeOthers("");             // cerrar launcher, paneles y menús abiertos
        persist.locked = true;
    }

    function startPreview() {
        if (persist.locked) return;
        reset();
        preview = true;
    }

    function cancelPreview() { if (preview) { preview = false; reset(); } }

    function reset() {
        busy = false;                   // antes de abort(): así se ignoran sus señales
        if (pam.active) pam.abort();
        _password = "";
        message = "";
        messageIsError = false;
        failures = 0;
    }

    // ───── Autenticación ─────
    property string _password: ""

    function submit(password) {
        if (busy || !active) return;
        if (password === "") return;
        _password = password;
        busy = true;
        message = "Comprobando…";
        messageIsError = false;
        if (!pam.start()) {
            _password = "";
            busy = false;
            message = "No se pudo iniciar la autenticación (PAM)";
            messageIsError = true;
        } else {
            watchdog.restart();
        }
    }

    function _succeeded() {
        _password = "";
        busy = false;
        message = "";
        failures = 0;
        if (preview) preview = false;
        else persist.locked = false;
    }

    function _failed(text) {
        _password = "";
        busy = false;
        failures++;
        message = text;
        messageIsError = true;
        failed();
    }

    PamContext {
        id: pam
        configDirectory: Quickshell.shellDir + "/modules/lock/pam"
        config: "lockscreen"
        user: Quickshell.env("USER")

        onPamMessage: {
            if (!responseRequired) {
                // Mensajes informativos de PAM (raro con pam_unix)
                if (message) { root.message = message; root.messageIsError = messageIsError; }
                return;
            }
            if (root._password === "") { abort(); return; }
            respond(root._password);
            root._password = "";        // no guardar la contraseña más de lo necesario
        }

        onCompleted: result => {
            watchdog.stop();
            if (!root.busy) return;     // abortado a propósito (reset)
            if (result === PamResult.Success) root._succeeded();
            else if (result === PamResult.MaxTries) root._failed("Demasiados intentos");
            else if (result === PamResult.Failed) root._failed("Contraseña incorrecta");
            else root._failed("Error de autenticación");
        }

        onError: err => {
            watchdog.stop();
            if (!root.busy) return;
            root._failed("Error de PAM: " + PamError.toString(err));
        }
    }

    // Si PAM se queda colgado, liberar para poder reintentar
    Timer {
        id: watchdog
        interval: 20000
        onTriggered: {
            if (!root.busy) return;
            root.busy = false;          // primero: se ignoran las señales de abort()
            if (pam.active) pam.abort();
            root._failed("La autenticación tardó demasiado, inténtalo de nuevo");
        }
    }
}
