pragma Singleton
import QtQuick
import Quickshell

// Iconos Material Design de JetBrainsMono Nerd Font
Singleton {
    readonly property string wifi0: String.fromCodePoint(0xF092F)
    readonly property string wifi1: String.fromCodePoint(0xF091F)
    readonly property string wifi2: String.fromCodePoint(0xF0922)
    readonly property string wifi3: String.fromCodePoint(0xF0925)
    readonly property string wifi4: String.fromCodePoint(0xF0928)
    readonly property string wifiOff: String.fromCodePoint(0xF05AA)
    readonly property string ethernet: String.fromCodePoint(0xF0200)
    readonly property string lan: String.fromCodePoint(0xF0318)
    readonly property string lanOff: String.fromCodePoint(0xF0319)
    readonly property string vpn: String.fromCodePoint(0xF0582)
    readonly property string shieldLock: String.fromCodePoint(0xF099D)
    readonly property string shieldOff: String.fromCodePoint(0xF099E)
    readonly property string shield: String.fromCodePoint(0xF0499)
    readonly property string airplane: String.fromCodePoint(0xF001D)
    readonly property string airplaneOff: String.fromCodePoint(0xF001E)
    readonly property string chevronRight: String.fromCodePoint(0xF0142)
    readonly property string chevronLeft: String.fromCodePoint(0xF0141)
    readonly property string cog: String.fromCodePoint(0xF0493)
    readonly property string plus: String.fromCodePoint(0xF0415)
    readonly property string trash: String.fromCodePoint(0xF01B4)
    readonly property string refresh: String.fromCodePoint(0xF0450)
    readonly property string eye: String.fromCodePoint(0xF0208)
    readonly property string eyeOff: String.fromCodePoint(0xF0209)
    readonly property string check: String.fromCodePoint(0xF012C)
    readonly property string close: String.fromCodePoint(0xF0156)
    readonly property string lock: String.fromCodePoint(0xF033E)
    readonly property string fileImport: String.fromCodePoint(0xF0220)
    readonly property string info: String.fromCodePoint(0xF02FD)
    readonly property string key: String.fromCodePoint(0xF0306)
    readonly property string account: String.fromCodePoint(0xF0004)
    readonly property string pencil: String.fromCodePoint(0xF03EB)
    readonly property string globe: String.fromCodePoint(0xF01E7)

    // Clima
    readonly property string sun: String.fromCodePoint(0xF0599)
    readonly property string moon: String.fromCodePoint(0xF0594)
    readonly property string partlyCloudy: String.fromCodePoint(0xF0595)
    readonly property string partlyCloudyNight: String.fromCodePoint(0xF0F31)
    readonly property string cloudy: String.fromCodePoint(0xF0590)
    readonly property string fog: String.fromCodePoint(0xF0591)
    readonly property string rain: String.fromCodePoint(0xF0597)
    readonly property string pouring: String.fromCodePoint(0xF0596)
    readonly property string lightning: String.fromCodePoint(0xF0593)
    readonly property string thunderRain: String.fromCodePoint(0xF067E)
    readonly property string snow: String.fromCodePoint(0xF0598)
    readonly property string snowRain: String.fromCodePoint(0xF067F)
    readonly property string hail: String.fromCodePoint(0xF0592)
    readonly property string humidity: String.fromCodePoint(0xF058E)
    readonly property string wind: String.fromCodePoint(0xF059D)
    readonly property string thermometer: String.fromCodePoint(0xF050F)
    readonly property string mapMarker: String.fromCodePoint(0xF034E)
    readonly property string search: String.fromCodePoint(0xF0349)

    // Notificaciones / calendario
    readonly property string bell: String.fromCodePoint(0xF009A)
    readonly property string bellOff: String.fromCodePoint(0xF009B)
    readonly property string calendar: String.fromCodePoint(0xF00ED)
    readonly property string broom: String.fromCodePoint(0xF00E2)

    // Multimedia
    readonly property string play: String.fromCodePoint(0xF040A)
    readonly property string pause: String.fromCodePoint(0xF03E4)
    readonly property string next: String.fromCodePoint(0xF04AD)
    readonly property string previous: String.fromCodePoint(0xF04AE)
    readonly property string shuffle: String.fromCodePoint(0xF049D)
    readonly property string shuffleOff: String.fromCodePoint(0xF049E)
    readonly property string repeat: String.fromCodePoint(0xF0456)
    readonly property string repeatOff: String.fromCodePoint(0xF0457)
    readonly property string repeatOnce: String.fromCodePoint(0xF0458)
    readonly property string spotify: String.fromCodePoint(0xF04C7)
    readonly property string musicNote: String.fromCodePoint(0xF0387)
    readonly property string volumeHigh: String.fromCodePoint(0xF057E)
    readonly property string volumeLow: String.fromCodePoint(0xF057F)
    readonly property string volumeOff: String.fromCodePoint(0xF0581)
    readonly property string openExternal: String.fromCodePoint(0xF03CC)
    readonly property string album: String.fromCodePoint(0xF0025)

    // Bluetooth / dispositivos
    readonly property string bluetooth: String.fromCodePoint(0xF00AF)
    readonly property string bluetoothOff: String.fromCodePoint(0xF00B2)
    readonly property string bluetoothConnected: String.fromCodePoint(0xF00B1)
    readonly property string headphones: String.fromCodePoint(0xF02CB)
    readonly property string mouse: String.fromCodePoint(0xF037D)
    readonly property string keyboard: String.fromCodePoint(0xF030C)
    readonly property string phone: String.fromCodePoint(0xF03F2)
    readonly property string speaker: String.fromCodePoint(0xF04C3)
    readonly property string laptop: String.fromCodePoint(0xF0322)
    readonly property string gamepad: String.fromCodePoint(0xF0296)
    readonly property string monitor: String.fromCodePoint(0xF0502)
    readonly property string printer: String.fromCodePoint(0xF042A)
    readonly property string devices: String.fromCodePoint(0xF0FB0)
    readonly property string battery: String.fromCodePoint(0xF0079)

    // Proxy
    readonly property string proxy: String.fromCodePoint(0xF048D)
    readonly property string radioOn: String.fromCodePoint(0xF043E)
    readonly property string radioOff: String.fromCodePoint(0xF043D)
    readonly property string flask: String.fromCodePoint(0xF0668)

    // Icono según el tipo de dispositivo Bluetooth (BlueZ "icon")
    function btDevice(icon) {
        const i = icon || "";
        if (i.includes("headset") || i.includes("headphone") || i.includes("audio-card")) return headphones;
        if (i.includes("speaker") || i.includes("audio")) return speaker;
        if (i.includes("mouse")) return mouse;
        if (i.includes("keyboard")) return keyboard;
        if (i.includes("phone")) return phone;
        if (i.includes("computer") || i.includes("laptop")) return laptop;
        if (i.includes("gaming") || i.includes("joystick")) return gamepad;
        if (i.includes("video") || i.includes("display")) return monitor;
        if (i.includes("printer")) return printer;
        return bluetooth;
    }

    // Energía / audio
    readonly property string leaf: String.fromCodePoint(0xF032A)
    readonly property string balance: String.fromCodePoint(0xF05D1)
    readonly property string rocket: String.fromCodePoint(0xF14DE)
    readonly property string mic: String.fromCodePoint(0xF036C)
    readonly property string micOff: String.fromCodePoint(0xF036D)
    readonly property string chevronDown: String.fromCodePoint(0xF0140)
    readonly property string chevronUp: String.fromCodePoint(0xF0143)
    readonly property string batteryCharging: String.fromCodePoint(0xF0084)
    readonly property string batteryAlert: String.fromCodePoint(0xF0083)
    readonly property string plug: String.fromCodePoint(0xF06A5)
    readonly property string heartPulse: String.fromCodePoint(0xF05F6)
    readonly property string flash: String.fromCodePoint(0xF0241)
    readonly property string hdmi: String.fromCodePoint(0xF0841)
    readonly property string tune: String.fromCodePoint(0xF062E)
    readonly property string apps: String.fromCodePoint(0xF003B)
    readonly property string timer: String.fromCodePoint(0xF051B)
    readonly property string waveform: String.fromCodePoint(0xF147D)
    readonly property string coffee: String.fromCodePoint(0xF0176)
    readonly property string coffeeOff: String.fromCodePoint(0xF0F76)
    readonly property string brightnessLow: String.fromCodePoint(0xF00DE)
    readonly property string brightnessMid: String.fromCodePoint(0xF00DF)
    readonly property string brightnessHigh: String.fromCodePoint(0xF00E0)

    function wifi(signal) {
        return signal >= 80 ? wifi4 : signal >= 60 ? wifi3 : signal >= 40 ? wifi2 : signal >= 20 ? wifi1 : wifi0;
    }
}
