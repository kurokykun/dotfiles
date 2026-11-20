pragma Singleton
import QtQuick
import Quickshell

// Estado compartido de la interfaz
Singleton {
    id: ui

    // Panel de red
    property bool networkOpen: false
    property var popupScreen: null
    property string netPage: "main"     // main | wired | wifi | wifi-password | wifi-hidden | wifi-details | vpn | vpn-edit | bluetooth | cntlm | cntlm-edit
    property string netArg: ""          // SSID o UUID según la página
    property bool vpnJustImported: false
    property string lastVpn: ""
    property string lastProxy: ""

    function openNetwork(page, arg) {
        // Primero el argumento: la página lo lee al cambiar
        netArg = arg || "";
        const p = page || "main";
        if (netPage === p) netPageChanged(); else netPage = p;
        networkOpen = true;
    }

    onNetworkOpenChanged: {
        if (networkOpen) closeOthers("network");
        else { netPage = "main"; netArg = ""; vpnJustImported = false; }
    }

    // Panel de fecha (calendario, notificaciones, clima). Solo un panel abierto a la vez.
    property bool dateOpen: false
    onDateOpenChanged: if (dateOpen) closeOthers("date")

    // Panel de música
    property bool mediaOpen: false
    onMediaOpenChanged: if (mediaOpen) closeOthers("media")

    // Panel de sonido
    property bool audioOpen: false
    onAudioOpenChanged: if (audioOpen) closeOthers("audio")

    // Panel de batería
    property bool batteryOpen: false
    onBatteryOpenChanged: if (batteryOpen) closeOthers("battery")

    // Menú de apagado (pantalla completa)
    property bool powerOpen: false
    onPowerOpenChanged: if (powerOpen) closeOthers("power")

    // Lanzador de aplicaciones (pantalla completa)
    property bool launcherOpen: false
    onLauncherOpenChanged: if (launcherOpen) closeOthers("launcher")

    // Historial del portapapeles (Super+V)
    property bool clipboardOpen: false
    onClipboardOpenChanged: if (clipboardOpen) closeOthers("clipboard")

    // Selector de fondos (Super+W)
    property bool wallpaperOpen: false
    onWallpaperOpenChanged: if (wallpaperOpen) closeOthers("wallpaper")

    // Solo un panel abierto a la vez
    function closeOthers(keep) {
        if (keep !== "network") networkOpen = false;
        if (keep !== "date") dateOpen = false;
        if (keep !== "media") mediaOpen = false;
        if (keep !== "audio") audioOpen = false;
        if (keep !== "battery") batteryOpen = false;
        if (keep !== "power") powerOpen = false;
        if (keep !== "launcher") launcherOpen = false;
        if (keep !== "clipboard") clipboardOpen = false;
        if (keep !== "wallpaper") wallpaperOpen = false;
    }

    // Apps fijadas en el dock.
    // id = nombre del .desktop · match = app_id de sus ventanas (en minúsculas)
    readonly property var pinnedApps: [
        { id: "google-chrome",        match: ["google-chrome", "google-chrome-stable"] },
        { id: "kitty",                match: ["kitty"] },
        { id: "thunar",               match: ["thunar", "org.xfce.thunar"] },
        { id: "spotify-launcher",     match: ["spotify", "spotify-launcher"] },
        { id: "steam",                match: ["steam"] },
        { id: "com.microsoft.VSCode", match: ["code", "code-url-handler", "com.microsoft.vscode", "visual-studio-code"] }
    ]

    // Fondo de pantalla actual (services/Wallpaper.qml)
    readonly property string wallpaper: Wallpaper.current || (Quickshell.env("HOME") + "/.local/state/quickshell/wallpaper")

    // Monitor del dock (como en GNOME: la pantalla del portátil)
    readonly property string dockMonitor: "eDP-1"
}
