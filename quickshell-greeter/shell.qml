//@ pragma IconTheme Papirus-Dark
// Greeter (pantalla de inicio de sesión) para greetd, hecho con Quickshell.
// Lo ejecuta el usuario "greeter" dentro de cage:  cage -s -- qs -p /etc/greetd/quickshell
// Sin greetd (Greetd.available = false) funciona como VISTA PREVIA: no inicia sesión.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

ShellRoot {
    id: shell

    // ───────────── Tema (igual que tu escritorio) ─────────────
    QtObject {
        id: theme
        readonly property color bg: "#0b1426"
        readonly property color fg: "#e6ecf7"
        readonly property color dim: "#8692ad"
        readonly property color accent: "#ff8a3d"
        readonly property color accent2: "#ff4f6d"
        readonly property color red: "#ff5c5c"
        readonly property color yellow: "#ffd166"
        readonly property string sans: "Noto Sans"
        readonly property string icons: "JetBrainsMono Nerd Font"
    }

    readonly property bool preview: !Greetd.available
    readonly property var es: Qt.locale("es_ES")

    // ───────────── Usuarios (UID 1000–59999 con shell válida) ─────────────
    property var users: []
    property int userIndex: 0
    readonly property string user: users[userIndex]?.name ?? ""
    readonly property string userLabel: {
        const u = users[userIndex];
        if (!u) return "";
        const n = u.gecos || u.name;
        return n.charAt(0).toUpperCase() + n.slice(1);
    }

    FileView {
        path: "/etc/passwd"
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                const f = line.split(":");
                if (f.length < 7) continue;
                const uid = Number(f[2]);
                if (uid < 1000 || uid >= 60000) continue;
                if (/(nologin|false)$/.test(f[6])) continue;
                out.push({ name: f[0], gecos: (f[4] || "").split(",")[0], home: f[5] });
            }
            shell.users = out;
        }
    }

    // ───────────── Sesiones (/usr/share/wayland-sessions) ─────────────
    property var sessions: []
    property int sessionIndex: 0
    readonly property var session: sessions[sessionIndex] ?? null

    Process {
        running: true
        command: ["sh", "-c",
            'for f in /usr/share/wayland-sessions/*.desktop; do [ -r "$f" ] || continue; ' +
            'printf "%s\\t%s\\t%s\\t%s\\n" "$(basename "$f" .desktop)" ' +
            '"$(grep -m1 "^Name=" "$f" | cut -d= -f2-)" "$(grep -m1 "^Exec=" "$f" | cut -d= -f2-)" ' +
            '"$(grep -m1 "^DesktopNames=" "$f" | cut -d= -f2-)"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(l => l).map(l => {
                    const [id, name, exec, names] = l.split("\t");
                    return { id, name: name || id, exec, desktopNames: (names || id).replace(/;+$/, "").replace(/;/g, ":") };
                }).filter(s => s.exec);
                // labwc primero (tu escritorio)
                list.sort((a, b) => (b.id === "labwc") - (a.id === "labwc") || a.name.localeCompare(b.name));
                shell.sessions = list;
            }
        }
    }

    // greetd une el comando con espacios y lo pasa a "sh -c": por eso solo se envía
    // la ruta del lanzador y un id sin espacios (launch.sh resuelve el resto)
    function launchCommand(s) {
        const id = /^[A-Za-z0-9._-]+$/.test(s.id) ? s.id : "labwc";
        return ["/etc/greetd/quickshell/launch.sh", id];
    }

    function launchEnv(s) {
        return ["XDG_SESSION_TYPE=wayland",
                "XDG_SESSION_DESKTOP=" + s.id,
                "XDG_CURRENT_DESKTOP=" + s.desktopNames,
                "DESKTOP_SESSION=" + s.id];
    }

    // ───────────── Autenticación ─────────────
    property bool busy: false
    property bool launching: false
    property string message: ""
    property bool messageIsError: false
    property string _password: ""
    property bool _awaitingExtra: false     // PAM pidió un segundo dato (raro)
    signal failed()

    function submit(text) {
        if (busy || launching || text === "" || !user || !session) return;
        if (_awaitingExtra) {               // respuesta a una pregunta extra de PAM
            _awaitingExtra = false;
            busy = true;
            Greetd.respond(text);
            return;
        }
        busy = true;
        message = "Comprobando…";
        messageIsError = false;
        if (preview) { previewTimer.restart(); return; }
        _password = text;
        watchdog.restart();
        Greetd.createSession(user);
    }

    function fail(text) {
        watchdog.stop();
        _password = "";
        _awaitingExtra = false;
        busy = false;
        message = text;
        messageIsError = true;
        failed();
    }

    Connections {
        target: Greetd
        enabled: !shell.preview

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                if (shell._password !== "") {
                    Greetd.respond(shell._password);
                    shell._password = "";
                } else {
                    // Segunda pregunta (p. ej. otro factor): se la mostramos al usuario
                    shell.busy = false;
                    shell._awaitingExtra = true;
                    shell.message = message;
                    shell.messageIsError = false;
                }
            } else if (message) {
                shell.message = message;
                shell.messageIsError = error;
            }
        }
        function onAuthFailure(message) {
            shell.fail(/fail|incorrect|denied|authentication/i.test(message) || !message
                ? "Contraseña incorrecta" : message);
        }
        function onReadyToLaunch() {
            watchdog.stop();
            shell.launching = true;
            shell.message = "Iniciando " + shell.session.name + "…";
            shell.messageIsError = false;
            Greetd.launch(shell.launchCommand(shell.session), shell.launchEnv(shell.session));
        }
        function onError(error) {
            Greetd.cancelSession();
            shell.launching = false;
            shell.fail("Error de greetd: " + error);
        }
    }

    // Si greetd no contesta, liberar para reintentar
    Timer {
        id: watchdog
        interval: 30000
        onTriggered: {
            if (!shell.busy) return;
            Greetd.cancelSession();
            shell.fail("No hubo respuesta, inténtalo de nuevo");
        }
    }

    Timer {
        id: previewTimer
        interval: 900
        onTriggered: {
            shell.busy = false;
            shell.message = "Vista previa: aquí se iniciaría " + (shell.session?.name ?? "la sesión");
            shell.messageIsError = false;
        }
    }

    // ───────────── Energía ─────────────
    property string confirmPower: ""
    Timer { id: confirmTimer; interval: 3000; onTriggered: shell.confirmPower = "" }
    function power(action) {
        if (confirmPower !== action) { confirmPower = action; confirmTimer.restart(); return; }
        confirmPower = "";
        if (preview) { message = "Vista previa: aquí se ejecutaría «systemctl " + action + "»"; messageIsError = false; return; }
        Quickshell.execDetached(["systemctl", action]);
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ───────────── Ventana ─────────────
    FloatingWindow {
        id: win
        visible: true
        color: theme.bg
        implicitWidth: 1280
        implicitHeight: 800
        title: "Inicio de sesión"

        Item {
            id: root
            anchors.fill: parent
            focus: true

            function focusInput() { input.forceActiveFocus(); }
            Component.onCompleted: { focusInput(); enter.start(); }

            // Fondo
            Image {
                id: wall
                anchors.fill: parent
                source: "file://" + Quickshell.shellDir + "/wallpaper.jpg"
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 1280
                asynchronous: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: wall
                visible: wall.status === Image.Ready
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 0.7
                blurMax: 48
                brightness: -0.12
                saturation: 0.1
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.02, 0.04, 0.09, 0.55) }
                    GradientStop { position: 0.45; color: Qt.rgba(0.02, 0.04, 0.09, 0.25) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.04, 0.09, 0.85) }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.focusInput() }

            Item {
                id: content
                anchors.fill: parent
                opacity: 0
                property real lift: 30
                transform: Translate { y: content.lift }
                ParallelAnimation {
                    id: enter
                    NumberAnimation { target: content; property: "opacity"; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
                    NumberAnimation { target: content; property: "lift"; from: 30; to: 0; duration: 700; easing.type: Easing.OutCubic }
                }

                // Aviso de vista previa
                Glass {
                    visible: shell.preview
                    anchors.top: parent.top
                    anchors.topMargin: 24
                    anchors.horizontalCenter: parent.horizontalCenter
                    tint: theme.yellow
                    Label { text: "\u{F0208}"; font.family: theme.icons; color: theme.yellow }
                    Label { text: "Vista previa · sin greetd no inicia sesión · Esc para salir"; color: theme.yellow; font.pixelSize: 13 }
                }

                // Fecha y reloj
                ColumnLayout {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: parent.height * 0.1
                    spacing: -18
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: shell.es.toString(clock.date, "dddd  ·  d 'de' MMMM").toUpperCase()
                        font.pixelSize: 17
                        font.weight: Font.Medium
                        font.letterSpacing: 5
                        color: Qt.rgba(1, 1, 1, 0.75)
                    }
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6
                        Label { text: Qt.formatDateTime(clock.date, "HH"); font.pixelSize: 190; font.weight: Font.Bold }
                        Label {
                            text: ":"
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -12
                            font.pixelSize: 150
                            font.weight: Font.Light
                            color: theme.accent
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 1000; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 1000; easing.type: Easing.InOutSine }
                            }
                        }
                        Label { text: Qt.formatDateTime(clock.date, "mm"); font.pixelSize: 190; font.weight: Font.ExtraLight }
                    }
                }

                // Usuario, sesión y contraseña
                ColumnLayout {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: parent.height * 0.12
                    spacing: 14

                    transform: Translate { id: shakeT; x: 0 }
                    SequentialAnimation {
                        id: shake
                        NumberAnimation { target: shakeT; property: "x"; to: -14; duration: 50 }
                        NumberAnimation { target: shakeT; property: "x"; to: 12; duration: 70 }
                        NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 70 }
                        NumberAnimation { target: shakeT; property: "x"; to: 5; duration: 60 }
                        NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 50 }
                    }
                    Connections {
                        target: shell
                        function onFailed() { shake.restart(); input.text = ""; root.focusInput(); }
                        function onBusyChanged() { if (!shell.busy) root.focusInput(); }
                    }

                    // Avatar con anillo (gira mientras comprueba)
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 76
                        implicitHeight: 76
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            gradient: Gradient {
                                GradientStop { position: 0; color: theme.accent }
                                GradientStop { position: 1; color: theme.accent2 }
                            }
                            RotationAnimation on rotation {
                                running: shell.busy || shell.launching
                                loops: Animation.Infinite
                                from: 0; to: 360; duration: 1200
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: width / 2
                            color: Qt.rgba(0.05, 0.08, 0.16, 0.92)
                            Label {
                                anchors.centerIn: parent
                                text: shell.userLabel.charAt(0)
                                font.pixelSize: 32
                                font.weight: Font.Bold
                            }
                        }
                    }

                    // Nombre (con flechas si hay varios usuarios)
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10
                        IconButton {
                            visible: shell.users.length > 1
                            icon: "\u{F0141}"
                            onClicked: shell.userIndex = (shell.userIndex - 1 + shell.users.length) % shell.users.length
                        }
                        Label { text: shell.userLabel; font.pixelSize: 18; font.weight: Font.DemiBold }
                        IconButton {
                            visible: shell.users.length > 1
                            icon: "\u{F0142}"
                            onClicked: shell.userIndex = (shell.userIndex + 1) % shell.users.length
                        }
                    }

                    // Campo de contraseña
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 360
                        implicitHeight: 54
                        radius: 27
                        color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.11 : 0.07)
                        border.width: 1
                        border.color: shell.messageIsError ? Qt.rgba(1, 0.36, 0.36, 0.75)
                                    : input.activeFocus ? Qt.rgba(1, 0.54, 0.24, 0.55) : Qt.rgba(1, 1, 1, 0.14)
                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 22
                            anchors.rightMargin: 8
                            spacing: 12

                            Label {
                                text: "\u{F033E}"
                                font.family: theme.icons
                                font.pixelSize: 17
                                color: shell.busy ? theme.dim : theme.accent
                            }

                            TextInput {
                                id: input
                                Layout.fillWidth: true
                                focus: true
                                enabled: !shell.busy && !shell.launching
                                echoMode: shell._awaitingExtra ? TextInput.Normal : TextInput.Password
                                passwordCharacter: "●"
                                color: theme.fg
                                font.family: theme.sans
                                font.pixelSize: 17
                                font.letterSpacing: 3
                                clip: true
                                selectByMouse: false
                                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText

                                Label {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: input.text === ""
                                    text: shell.launching ? "Iniciando…" : shell.busy ? "Comprobando…" : "Introduce tu contraseña"
                                    font.pixelSize: 15
                                    color: Qt.rgba(1, 1, 1, 0.42)
                                }

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        shell.submit(input.text);
                                        input.text = "";
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Escape) {
                                        if (input.text !== "") input.text = "";
                                        else if (shell.preview) Qt.quit();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Tab && shell.sessions.length > 1) {
                                        shell.sessionIndex = (shell.sessionIndex + 1) % shell.sessions.length;
                                        event.accepted = true;
                                    }
                                }
                            }

                            Rectangle {
                                implicitWidth: 40
                                implicitHeight: 40
                                radius: 20
                                readonly property bool ready: input.text !== "" && !shell.busy
                                color: ready ? theme.accent : goArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Label {
                                    anchors.centerIn: parent
                                    text: "\u{F0054}"
                                    font.family: theme.icons
                                    font.pixelSize: 18
                                    color: parent.ready ? "#1a0f05" : theme.dim
                                }
                                MouseArea {
                                    id: goArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { shell.submit(input.text); input.text = ""; root.focusInput(); }
                                }
                            }
                        }
                    }

                    // Mensaje
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredHeight: 18
                        text: shell.message
                        font.pixelSize: 13
                        color: shell.messageIsError ? theme.red : Qt.rgba(1, 1, 1, 0.6)
                    }
                }

                // Sesión (abajo a la izquierda): clic o Tab para cambiar
                Glass {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 28
                    hoverable: shell.sessions.length > 1
                    onClicked: { shell.sessionIndex = (shell.sessionIndex + 1) % shell.sessions.length; root.focusInput(); }
                    Label { text: "\u{F0379}"; font.family: theme.icons; color: theme.accent; font.pixelSize: 16 }
                    Label { text: shell.session?.name ?? "—"; font.weight: Font.DemiBold }
                    Label {
                        visible: shell.sessions.length > 1
                        text: "Tab"
                        color: theme.dim
                        font.pixelSize: 11
                    }
                }

                // Energía (abajo a la derecha): pulsar dos veces para confirmar
                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 28
                    spacing: 10
                    Repeater {
                        model: [
                            { action: "suspend",  icon: "\u{F0904}", label: "Suspender" },
                            { action: "reboot",   icon: "\u{F0709}", label: "Reiniciar" },
                            { action: "poweroff", icon: "\u{F0425}", label: "Apagar" }
                        ]
                        delegate: Glass {
                            id: pw
                            required property var modelData
                            readonly property bool confirming: shell.confirmPower === pw.modelData.action
                            hoverable: true
                            tint: confirming ? theme.red : "white"
                            onClicked: { shell.power(pw.modelData.action); root.focusInput(); }
                            Label {
                                text: pw.modelData.icon
                                font.family: theme.icons
                                font.pixelSize: 16
                                color: pw.confirming ? theme.red : theme.fg
                            }
                            Label {
                                visible: pw.confirming || pw.hovered
                                text: pw.confirming ? "¿" + pw.modelData.label + "? Pulsa otra vez" : pw.modelData.label
                                font.pixelSize: 12
                                color: pw.confirming ? theme.red : theme.fg
                            }
                        }
                    }
                }
            }
        }
    }

    // ───────────── Componentes ─────────────
    component Label: Text {
        color: theme.fg
        font.family: theme.sans
        font.pixelSize: 14
        verticalAlignment: Text.AlignVCenter
    }

    component Glass: Rectangle {
        id: g
        default property alias content: gRow.data
        property color tint: "white"
        property bool hoverable: false
        readonly property bool hovered: gArea.containsMouse
        signal clicked()
        implicitWidth: gRow.implicitWidth + 28
        implicitHeight: 36
        radius: 18
        color: Qt.rgba(tint.r, tint.g, tint.b, hoverable && gArea.containsMouse ? 0.16 : 0.08)
        border.width: 1
        border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.16)
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        RowLayout { id: gRow; anchors.centerIn: parent; spacing: 8 }
        MouseArea {
            id: gArea
            anchors.fill: parent
            enabled: g.hoverable
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: g.clicked()
        }
    }

    component IconButton: Rectangle {
        id: ib
        property string icon: ""
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        color: ibArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
        Text {
            anchors.centerIn: parent
            text: ib.icon
            font.family: theme.icons
            font.pixelSize: 16
            color: theme.fg
        }
        MouseArea { id: ibArea; anchors.fill: parent; hoverEnabled: true; onClicked: ib.clicked() }
    }
}
