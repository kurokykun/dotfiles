pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Clima vía Open-Meteo (gratis, sin clave). La ubicación se elige desde el panel
// y se guarda en ~/.config/quickshell/weather.json
Singleton {
    id: root

    // Ubicación: la guarda weather.json (no se sube a git) al elegirla con el buscador.
    // Sin ella, hasLocation es false hasta que se elija una.
    property string city: ""
    property string region: ""
    property real latitude: NaN
    property real longitude: NaN
    readonly property bool hasLocation: !isNaN(latitude) && !isNaN(longitude)

    // Datos
    property bool loading: false
    property string error: ""
    property var current: null      // {temp, feels, code, isDay, humidity, wind}
    property var hourly: []         // [{time: Date, temp, code, isDay}] próximas horas
    property var today: null        // {max, min}
    property date updated

    // Búsqueda de ciudades
    property var searchResults: []
    property bool searching: false

    // ───── Configuración guardada ─────
    FileView {
        id: config
        path: Quickshell.shellDir + "/weather.json"
        printErrors: false
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.city = c.city ?? root.city;
                root.region = c.region ?? "";
                root.latitude = c.latitude ?? root.latitude;
                root.longitude = c.longitude ?? root.longitude;
            } catch (e) {}
        }
    }

    function setLocation(place) {
        city = place.name;
        region = [place.admin1, place.country].filter(x => x).join(", ");
        latitude = place.latitude;
        longitude = place.longitude;
        searchResults = [];
        config.setText(JSON.stringify({ city, region, latitude, longitude }, null, 2));
        refresh();
    }

    // ───── Red ─────
    function get(url, cb) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try { cb(JSON.parse(xhr.responseText), null); }
                catch (e) { cb(null, "Respuesta no válida"); }
            } else {
                cb(null, xhr.status === 0 ? "Sin conexión" : "Error " + xhr.status);
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function search(text) {
        if (text.trim().length < 2) { searchResults = []; return; }
        searching = true;
        get("https://geocoding-api.open-meteo.com/v1/search?count=6&language=es&format=json&name="
            + encodeURIComponent(text.trim()), (data, err) => {
            searching = false;
            searchResults = data?.results ?? [];
        });
    }

    function refresh() {
        if (!hasLocation || loading) return;
        loading = true;
        const url = "https://api.open-meteo.com/v1/forecast?latitude=" + latitude + "&longitude=" + longitude
            + "&current=temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"
            + "&hourly=temperature_2m,weather_code,is_day"
            + "&daily=temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&forecast_days=2";
        get(url, (d, err) => {
            loading = false;
            if (!d) { error = err; return; }
            error = "";
            fetchedOnce = true;
            current = {
                temp: d.current.temperature_2m,
                feels: d.current.apparent_temperature,
                code: d.current.weather_code,
                isDay: d.current.is_day === 1,
                humidity: d.current.relative_humidity_2m,
                wind: d.current.wind_speed_10m
            };
            today = { max: d.daily.temperature_2m_max[0], min: d.daily.temperature_2m_min[0] };
            // Próximas 5 horas (la API devuelve hora local como "2026-11-04T15:00")
            const nowHour = d.current.time.slice(0, 13);
            let start = d.hourly.time.findIndex(t => t.slice(0, 13) > nowHour);
            if (start < 0) start = 0;
            const hours = [];
            for (let i = start; i < start + 5 && i < d.hourly.time.length; i++) {
                hours.push({ label: d.hourly.time[i].slice(11, 16), temp: d.hourly.temperature_2m[i],
                             code: d.hourly.weather_code[i], isDay: d.hourly.is_day[i] === 1 });
            }
            hourly = hours;
            updated = new Date();
        });
    }

    // Política de actualización: solo una vez al tener red por primera vez,
    // y después únicamente con el botón de actualizar (o al cambiar de ubicación).
    property bool fetchedOnce: false

    function refreshIfFirst() {
        if (!fetchedOnce && Network.connected) refresh();
    }

    Connections {
        target: Network
        function onConnectedChanged() { root.refreshIfFirst(); }
    }

    Component.onCompleted: Qt.callLater(refreshIfFirst)

    // ───── Códigos WMO → texto e icono ─────
    function describe(code) {
        if (code === 0) return "Despejado";
        if (code === 1) return "Mayormente despejado";
        if (code === 2) return "Parcialmente nublado";
        if (code === 3) return "Nublado";
        if (code === 45 || code === 48) return "Niebla";
        if (code >= 51 && code <= 57) return "Llovizna";
        if (code === 61 || code === 80) return "Lluvia ligera";
        if (code === 63 || code === 81) return "Lluvia";
        if (code === 65 || code === 82) return "Lluvia intensa";
        if (code === 66 || code === 67) return "Lluvia helada";
        if (code >= 71 && code <= 77) return "Nieve";
        if (code === 85 || code === 86) return "Chubascos de nieve";
        if (code === 95) return "Tormenta";
        if (code === 96 || code === 99) return "Tormenta con granizo";
        return "—";
    }

    function icon(code, isDay) {
        if (code === 0 || code === 1) return isDay ? Icons.sun : Icons.moon;
        if (code === 2) return isDay ? Icons.partlyCloudy : Icons.partlyCloudyNight;
        if (code === 3) return Icons.cloudy;
        if (code === 45 || code === 48) return Icons.fog;
        if ((code >= 51 && code <= 61) || code === 80) return Icons.rain;
        if (code === 63 || code === 65 || code === 81 || code === 82) return Icons.pouring;
        if (code === 66 || code === 67) return Icons.snowRain;
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return Icons.snow;
        if (code === 95) return Icons.thunderRain;
        if (code === 96 || code === 99) return Icons.hail;
        return Icons.cloudy;
    }
}
