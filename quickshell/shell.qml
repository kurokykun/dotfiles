//@ pragma UseQApplication
//@ pragma IconTheme Papirus-Dark
// Punto de entrada de Quickshell. Se recarga solo al guardar cualquier .qml.
import Quickshell
import Quickshell.Io
import qs.modules.audio
import qs.modules.bar
import qs.modules.battery
import qs.modules.calendar
import qs.modules.clipboard
import qs.modules.dock
import qs.modules.idle
import qs.modules.launcher
import qs.modules.lock
import qs.modules.media
import qs.modules.network
import qs.modules.notifications
import qs.modules.osd
import qs.modules.power
import qs.modules.screenshot
import qs.modules.wallpaper
import qs.config
import qs.services

ShellRoot {
    // Fondo de escritorio (uno por monitor; swaybg queda debajo como respaldo)
    Variants {
        model: Quickshell.screens
        WallpaperLayer {}
    }
    // Carga perezosa: solo existe mientras está abierto (o terminando su animación de cierre)
    LazyLoader {
        id: wallpaperLoader
        active: Ui.wallpaperOpen || (item ? item.shown : false)
        WallpaperPicker {}
    }

    // Una barra por monitor
    Variants {
        model: Quickshell.screens
        Bar {}
    }

    Dock {}
    NetworkPopup {}
    Notifications {}
    DateMenu {}
    MediaPanel {}
    AudioPanel {}
    BatteryPanel {}
    // Siempre cargado: se usa a diario y debe abrir al instante (medido: la carga perezosa
    // lo hacía 2–4× más lento en un equipo modesto)
    PowerMenu { }
    // Siempre cargado: se usa a diario y debe abrir al instante (medido: la carga perezosa
    // lo hacía 2–4× más lento en un equipo modesto)
    Launcher { id: launcher }
    OsdPopup {}
    WorkspaceOsd {}
    IdleInhibit {}
    // Capa de capturas: solo mientras se está capturando
    LazyLoader {
        active: Screenshot.active
        ScreenshotOverlay {}
    }
    ShotToast {}
    ShotCountdown {}
    LockScreen {}
    // Siempre cargado: se usa a diario y debe abrir al instante (medido: la carga perezosa
    // lo hacía 2–4× más lento en un equipo modesto)
    ClipboardPanel { id: clipboardPanel }

    // qs ipc call media toggle | playpause | next | previous
    IpcHandler {
        target: "media"
        function toggle(): void { Ui.mediaOpen = !Ui.mediaOpen; }
        function playpause(): void { Media.toggle(); }
        function next(): void { Media.next(); }
        function previous(): void { Media.previous(); }
    }

    // Lanzador de aplicaciones (tecla Super)
    IpcHandler {
        target: "launcher"
        function toggle(): void { Ui.launcherOpen = !Ui.launcherOpen; }
        function close(): void { Ui.launcherOpen = false; }
        // Abrir con texto: "=" calculadora · ":" emoji · "/" archivos · ">" comando · "?" web
        function open(text: string): void { launcher.openWith(text); }
    }

    // Menú de apagado (Super+Esc)
    IpcHandler {
        target: "power"
        function toggle(): void { Ui.powerOpen = !Ui.powerOpen; }
        function close(): void { Ui.powerOpen = false; }
    }

    IpcHandler {
        target: "audio"
        function toggle(): void { Ui.audioOpen = !Ui.audioOpen; }
        function close(): void { Ui.audioOpen = false; }
    }

    IpcHandler {
        target: "battery"
        function toggle(): void { Ui.batteryOpen = !Ui.batteryOpen; }
        function close(): void { Ui.batteryOpen = false; }
    }

    IpcHandler {
        target: "calendar"
        function toggle(): void { Ui.dateOpen = !Ui.dateOpen; }
        function close(): void { Ui.dateOpen = false; }
    }

    // qs ipc call keyboard next
    IpcHandler {
        target: "keyboard"
        function next(): void { Keyboard.next(); }
    }

    // Control desde terminal/atajos:  qs ipc call network toggle | open wifi | close
    IpcHandler {
        target: "network"
        function toggle(): void { Ui.networkOpen = !Ui.networkOpen; }
        function open(page: string): void { Ui.openNetwork(page); }
        function openWith(page: string, arg: string): void { Ui.openNetwork(page, arg); }
        function close(): void { Ui.networkOpen = false; }
    }

    // Los atajos de brillo llaman a esto después de brightnessctl:
    //   qs ipc call brightness changed | set 0.5
    IpcHandler {
        target: "brightness"
        function changed(): void { Brightness.refresh(); }
        function set(v: real): void { Brightness.set(v); }
    }

    // Prueba del OSD: qs ipc call osd test
    IpcHandler {
        target: "osd"
        function test(): void { Osd.show("volume", Icons.volumeHigh, "66%", 0.66, false); }
        function hide(): void { Osd.hide(); }
    }

    // Pantalla de bloqueo
    //   qs ipc call lock preview   → vista previa (NO bloquea; Esc para salir)
    //   qs ipc call lock lock      → bloquear de verdad
    //   qs ipc call lock isLocked  → "true" cuando el compositor confirmó el bloqueo
    IpcHandler {
        target: "lock"
        function preview(): void { Lock.startPreview(); }
        function closePreview(): void { Lock.cancelPreview(); }   // solo la vista previa
        function lock(): void { Lock.lock(); }
        function isLocked(): bool { return Lock.locked && Lock.secure; }
    }

    // Portapapeles (Super+V)
    //   qs ipc call clipboard toggle | open | close
    //   qs ipc call clipboard pause | resume | togglePause   (modo incógnito)
    IpcHandler {
        target: "clipboard"
        function toggle(): void { Ui.clipboardOpen = !Ui.clipboardOpen; }
        function open(): void { Ui.clipboardOpen = true; }
        function close(): void { Ui.clipboardOpen = false; }
        function pause(): void { Clipboard.setPaused(true); }
        function resume(): void { Clipboard.setPaused(false); }
        function togglePause(): void { Clipboard.setPaused(!Clipboard.paused); }
        function transform(): void { clipboardPanel.openTransform(); }   // acciones sobre lo último copiado
        function pinLatest(): void { Clipboard.togglePin(Clipboard.history[0]); }   // fija lo último copiado
    }

    // Luz nocturna:  qs ipc call nightlight toggle | on | off | mode auto|schedule|always
    IpcHandler {
        target: "nightlight"
        function toggle(): void { NightLight.setEnabled(!NightLight.enabled); }
        function on(): void { NightLight.setEnabled(true); }
        function off(): void { NightLight.setEnabled(false); }
        function mode(m: string): void { if (["auto", "schedule", "always"].includes(m)) NightLight.setMode(m); }
        function status(): string { return NightLight.status; }
    }

    // Cafeína (no bloquear ni apagar la pantalla):  qs ipc call caffeine toggle | on | off | status
    IpcHandler {
        target: "caffeine"
        function toggle(): void { Caffeine.toggle(); }
        function on(): void { Caffeine.setManual(true); }
        function off(): void { Caffeine.setManual(false); }
        function status(): string { return Caffeine.active ? "activa (" + Caffeine.status + ")" : "inactiva"; }
        function auto(on: bool): void { Caffeine.setAutoMedia(on); }   // activarse sola con música o vídeo
    }

    // Capturas:  qs ipc call screenshot region | screen | cancel
    IpcHandler {
        target: "screenshot"
        function region(): void { Screenshot.start(null); }      // capa de selección (pantalla congelada)
        function screen(): void { Screenshot.screenNow(null); }  // pantalla completa al instante
        function cancel(): void { Screenshot.cancel(); Screenshot.cancelCountdown(); }
        function record(): void { Screenshot.toggleRecording(); }   // grabar/detener la pantalla completa
        function stopRecording(): void { Screenshot.stopRecording(); }
    }

    // Escritorios:  qs ipc call workspaces next | previous | go 2
    IpcHandler {
        target: "workspaces"
        function next(): void { Workspaces.next(); }
        function previous(): void { Workspaces.previous(); }
        function go(n: int): void { Workspaces.activate(n - 1); }
    }

    // Fondos:  qs ipc call wallpaper toggle | next | prev | random | set /ruta/imagen.jpg
    IpcHandler {
        target: "wallpaper"
        function toggle(): void { Ui.wallpaperOpen = !Ui.wallpaperOpen; }
        function next(): void { Wallpaper.next(); }
        function prev(): void { Wallpaper.prev(); }
        function random(): void { Wallpaper.random(); }
        function set(path: string): void { Wallpaper.set(path); }
        function current(): string { return Wallpaper.current; }
    }

    // Tema automático desde el fondo:  qs ipc call theme auto true|false | regenerate | status
    IpcHandler {
        target: "theme"
        function auto(on: bool): void { ThemeEngine.setAuto(on); }
        function regenerate(): void { ThemeEngine.source = ""; ThemeEngine.generate(Wallpaper.current); }
        function status(): string { return (ThemeEngine.auto ? "automático" : "fijo") + " · " + JSON.stringify(ThemeEngine.last); }
    }
    // Arrancar el motor de tema con el shell (los singletons se crean al usarlos)
    readonly property bool themeEngineActive: ThemeEngine.auto
}
