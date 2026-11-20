import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.config
import qs.services
import qs.widgets

// Panel de batería y energía (clic en la batería de la barra).
// Nivel, tiempo restante/hasta completar, consumo, modo de energía y baterías de otros dispositivos.
PanelPopup {
    id: root
    name: "battery"
    panelWidth: 420
    open: Ui.batteryOpen
    onCloseRequested: Ui.batteryOpen = false

    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: bat !== null && bat.isLaptopBattery
    readonly property int pct: bat ? Math.round(bat.percentage * 100) : 0
    readonly property bool charging: bat !== null && bat.state === UPowerDeviceState.Charging
    readonly property bool full: bat !== null && (bat.state === UPowerDeviceState.FullyCharged
        || (bat.state === UPowerDeviceState.PendingCharge && pct >= 95))
    readonly property bool onAc: !UPower.onBattery

    // Baterías de otros dispositivos (ratón, auriculares…)
    readonly property var peripherals: UPower.devices.values.filter(d =>
        !d.isLaptopBattery && d.isPresent && d.type !== UPowerDeviceType.LinePower
        && d.type !== UPowerDeviceType.Battery && d.percentage > 0)

    function duration(sec) {
        if (!sec || sec <= 0) return "";
        const h = Math.floor(sec / 3600);
        const m = Math.round((sec % 3600) / 60);
        return h > 0 ? h + " h" + (m > 0 ? " " + m + " min" : "") : m + " min";
    }

    readonly property string status: {
        if (!bat) return "";
        if (full) return onAc ? "Cargada · conectada a la corriente" : "Cargada";
        if (charging) {
            const t = duration(bat.timeToFull);
            return "Cargando" + (t ? " · " + t + " hasta completar" : "");
        }
        if (onAc) return "Conectada · sin cargar";
        const t = duration(bat.timeToEmpty);
        return t ? t + " restantes" : "Usando la batería";
    }

    readonly property color levelColor: charging || full ? Theme.green
        : pct <= 10 ? Theme.red : pct <= 25 ? Theme.yellow : Theme.fg

    function deviceIcon(d) {
        switch (d.type) {
        case UPowerDeviceType.Mouse: return Icons.mouse;
        case UPowerDeviceType.Keyboard: return Icons.keyboard;
        case UPowerDeviceType.Phone: return Icons.phone;
        case UPowerDeviceType.Headset:
        case UPowerDeviceType.Headphones: return Icons.headphones;
        case UPowerDeviceType.Speakers: return Icons.speaker;
        case UPowerDeviceType.GamingInput: return Icons.gamepad;
        default: return Icons.battery;
        }
    }

    // ───── Nivel ─────
    RowLayout {
        Layout.fillWidth: true
        spacing: 14

        // Batería dibujada con su nivel
        Item {
            implicitWidth: 58
            implicitHeight: 30
            Rectangle {
                id: body
                width: 52
                height: 30
                radius: 7
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(1, 1, 1, 0.35)

                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 4 }
                    width: Math.max(4, (parent.width - 8) * root.pct / 100)
                    radius: 3
                    color: root.levelColor
                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
                BarText {
                    anchors.centerIn: parent
                    visible: root.charging
                    text: Icons.flash
                    font.pixelSize: 18
                    color: Theme.bgSolid
                    style: Text.Outline
                    styleColor: Theme.green
                }
            }
            Rectangle {
                anchors { left: body.right; leftMargin: 1; verticalCenter: body.verticalCenter }
                width: 4
                height: 12
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.35)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            BarText {
                text: root.hasBattery ? root.pct + "%" : "Sin batería"
                font.pixelSize: 26
                font.bold: true
                color: root.levelColor
            }
            BarText {
                Layout.fillWidth: true
                text: root.status
                color: Theme.dim
                font.pixelSize: Theme.fontSize - 1
                elide: Text.ElideRight
            }
        }
    }

    // Detalles
    Rectangle {
        visible: root.hasBattery
        Layout.fillWidth: true
        implicitHeight: details.implicitHeight + 20
        radius: 14
        color: Theme.surface

        ColumnLayout {
            id: details
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 4
            Detail { label: "Consumo"; value: (root.bat?.changeRate ?? 0) > 0.1 ? root.bat.changeRate.toFixed(1) + " W" : "" }
            Detail { label: "Energía"; value: root.bat ? root.bat.energy.toFixed(1) + " / " + root.bat.energyCapacity.toFixed(1) + " Wh" : "" }
            Detail { label: "Salud"; value: root.bat?.healthSupported ? Math.round(root.bat.healthPercentage) + "%" : "" }
            Detail { label: "Alimentación"; value: root.onAc ? "Corriente" : "Batería" }
        }
    }

    // ───── Brillo (igual que la fila de volumen del panel de sonido) ─────
    // Al abrir el panel se relee el brillo real por si cambió desde fuera
    Connections {
        target: Ui
        function onBatteryOpenChanged() { if (Ui.batteryOpen) Brightness.refresh(false); }
    }

    RowLayout {
        visible: Brightness.available
        Layout.fillWidth: true
        spacing: 10

        // Botón: alterna entre el brillo mínimo cómodo (20%) y el máximo
        Rectangle {
            implicitWidth: 36
            implicitHeight: 36
            radius: 18
            color: briArea.containsMouse ? Theme.surfaceHover : Theme.surface
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            BarText {
                anchors.centerIn: parent
                text: Brightness.value < 0.34 ? Icons.brightnessLow
                    : Brightness.value < 0.67 ? Icons.brightnessMid : Icons.brightnessHigh
                color: Theme.fg
                font.pixelSize: 18
            }
            MouseArea {
                id: briArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Brightness.set(Brightness.value > 0.5 ? 0.2 : 1)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            BarText {
                Layout.fillWidth: true
                text: "Brillo de la pantalla"
                font.pixelSize: Theme.fontSize - 2
                color: Theme.dim
                elide: Text.ElideRight
            }
            MediaSlider {
                Layout.fillWidth: true
                live: true
                value: Brightness.value
                // Nunca a 0: la pantalla quedaría negra
                onMoved: v => Brightness.set(Math.max(0.01, v))
            }
        }

        BarText {
            Layout.preferredWidth: 38
            horizontalAlignment: Text.AlignRight
            text: Math.round(Brightness.value * 100) + "%"
            color: Theme.dim
            font.pixelSize: Theme.fontSize - 2
        }
    }

    // ───── Pantalla: luz nocturna y cafeína ─────
    // La flecha › de cada interruptor despliega sus ajustes aquí debajo
    property string expanded: ""           // "" | "night" | "caffeine"
    Connections {
        target: Ui
        function onBatteryOpenChanged() { if (!Ui.batteryOpen) root.expanded = ""; }
    }

    BarText {
        text: "Pantalla"
        color: Theme.dim
        font.pixelSize: Theme.fontSize - 2
        Layout.bottomMargin: -6
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 10
        rowSpacing: 10

        QuickTile {
            icon: Icons.moon
            title: "Luz nocturna"
            subtitle: NightLight.shortStatus
            checked: NightLight.enabled
            onToggled: NightLight.setEnabled(!NightLight.enabled)
            onOpened: root.expanded = root.expanded === "night" ? "" : "night"
        }
        QuickTile {
            icon: Caffeine.active ? Icons.coffee : Icons.coffeeOff
            title: "Cafeína"
            subtitle: Caffeine.shortStatus
            checked: Caffeine.active
            onToggled: Caffeine.toggle()
            onOpened: root.expanded = root.expanded === "caffeine" ? "" : "caffeine"
        }
    }

    // Ajustes de la luz nocturna
    Rectangle {
        visible: root.expanded === "night"
        Layout.fillWidth: true
        implicitHeight: nightCol.implicitHeight + 24
        radius: 14
        color: Theme.surface

        ColumnLayout {
            id: nightCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10

            // Modo
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [
                        { id: "auto", label: "Automática" },
                        { id: "schedule", label: "Horario" },
                        { id: "always", label: "Siempre" }
                    ]
                    delegate: Rectangle {
                        id: modeBtn
                        required property var modelData
                        readonly property bool on: NightLight.mode === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 10
                        color: on ? Theme.accent : modeArea.containsMouse ? Theme.surfaceHover : Qt.rgba(1, 1, 1, 0.05)
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        BarText {
                            anchors.centerIn: parent
                            text: modeBtn.modelData.label
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: modeBtn.on
                            color: modeBtn.on ? Theme.textOnAccent : Theme.fg
                        }
                        MouseArea {
                            id: modeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NightLight.setMode(modeBtn.modelData.id)
                        }
                    }
                }
            }

            // Explicación del modo
            BarText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSize - 2
                color: Theme.dim
                text: NightLight.mode === "always" ? "La pantalla queda cálida todo el tiempo."
                    : NightLight.mode === "schedule" ? "Cálida entre la hora de inicio y la de fin."
                    : NightLight.todaySunset
                        ? "Según tu ubicación del clima: atardecer " + NightLight.todaySunset + " · amanecer " + NightLight.todaySunrise + "."
                        : "Se activa al atardecer y se quita al amanecer según tu ubicación del clima."
            }

            // Horario fijo
            RowLayout {
                visible: NightLight.mode === "schedule"
                Layout.fillWidth: true
                spacing: 8
                TimeBox { label: "Desde"; value: NightLight.sunset; onCommitted: v => NightLight.setSchedule(v, NightLight.sunrise) }
                TimeBox { label: "Hasta"; value: NightLight.sunrise; onCommitted: v => NightLight.setSchedule(NightLight.sunset, v) }
            }

            // Calidez (temperatura de color)
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                BarText { text: "Calidez"; color: Theme.dim; font.pixelSize: Theme.fontSize - 2 }
                MediaSlider {
                    Layout.fillWidth: true
                    live: true
                    // 5500 K (suave) → 0 · 2500 K (muy cálida) → 1
                    value: (5500 - NightLight.temperature) / 3000
                    onMoved: v => NightLight.setTemperature(5500 - v * 3000)
                }
                BarText {
                    Layout.preferredWidth: 52
                    horizontalAlignment: Text.AlignRight
                    text: NightLight.temperature + " K"
                    color: Theme.dim
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }

    // Ajustes de la cafeína
    Rectangle {
        visible: root.expanded === "caffeine"
        Layout.fillWidth: true
        implicitHeight: cafCol.implicitHeight + 24
        radius: 14
        color: Theme.surface

        ColumnLayout {
            id: cafCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    BarText { text: "Activarse sola con música o vídeo"; font.pixelSize: Theme.fontSize - 1 }
                    BarText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "Mientras algo suene (Spotify, YouTube…) no se bloquea ni se apaga la pantalla."
                        color: Theme.dim
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
                Toggle {
                    checked: Caffeine.autoMedia
                    onToggled: Caffeine.setAutoMedia(!Caffeine.autoMedia)
                }
            }
        }
    }

    // ───── Modo de energía ─────
    BarText {
        text: "Modo de energía"
        color: Theme.dim
        font.pixelSize: Theme.fontSize - 2
        Layout.bottomMargin: -6
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: [
                { p: PowerProfile.PowerSaver, icon: Icons.leaf, label: "Ahorro" },
                { p: PowerProfile.Balanced, icon: Icons.balance, label: "Equilibrado" },
                { p: PowerProfile.Performance, icon: Icons.rocket, label: "Rendimiento" }
            ]
            delegate: Rectangle {
                id: prof
                required property var modelData
                readonly property bool on: PowerProfiles.profile === modelData.p

                visible: modelData.p !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
                Layout.fillWidth: true
                implicitHeight: 58
                radius: 14
                color: on ? Theme.accent : profArea.containsMouse ? Theme.surfaceHover : Theme.surface
                scale: profArea.pressed ? 0.95 : 1
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }
                Behavior on scale { NumberAnimation { duration: Theme.animFast } }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2
                    BarText {
                        Layout.alignment: Qt.AlignHCenter
                        text: prof.modelData.icon
                        font.pixelSize: 20
                        color: prof.on ? Theme.textOnAccent : Theme.fg
                    }
                    BarText {
                        Layout.alignment: Qt.AlignHCenter
                        text: prof.modelData.label
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: prof.on
                        color: prof.on ? Theme.textOnAccent : Theme.fg
                    }
                }
                MouseArea {
                    id: profArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: PowerProfiles.profile = prof.modelData.p
                }
            }
        }
    }

    BarText {
        visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "Rendimiento reducido: " + (PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature
            ? "temperatura alta" : "el portátil está sobre las piernas")
        color: Theme.yellow
        font.pixelSize: Theme.fontSize - 2
    }

    // ───── Otros dispositivos ─────
    ColumnLayout {
        visible: root.peripherals.length > 0
        Layout.fillWidth: true
        spacing: 6
        BarText { text: "Dispositivos"; color: Theme.dim; font.pixelSize: Theme.fontSize - 2 }
        Repeater {
            model: root.peripherals
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                BarText { text: root.deviceIcon(modelData); color: Theme.dim; font.pixelSize: 16 }
                BarText {
                    Layout.fillWidth: true
                    text: modelData.model || "Dispositivo"
                    font.pixelSize: Theme.fontSize - 1
                    elide: Text.ElideRight
                }
                BarText {
                    text: Math.round(modelData.percentage * 100) + "%"
                    color: modelData.percentage < 0.2 ? Theme.red : Theme.dim
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }

    // Campo de hora HH:MM (se aplica al pulsar Enter o al salir; si no es válida, vuelve al valor anterior)
    component TimeBox: Rectangle {
        id: tb
        property string label: ""
        property string value: "00:00"
        signal committed(string v)
        Layout.fillWidth: true
        implicitHeight: 34
        radius: 10
        color: Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: timeInput.activeFocus ? Qt.alpha(Theme.accent, 0.6) : Qt.rgba(1, 1, 1, 0.08)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            BarText { text: tb.label; color: Theme.dim; font.pixelSize: Theme.fontSize - 2 }
            Item { Layout.fillWidth: true }
            TextInput {
                id: timeInput
                text: tb.value
                inputMask: "99:99"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                selectByMouse: true
                function commit() {
                    const m = text.match(/^([01]\d|2[0-3]):([0-5]\d)$/);
                    if (m && text !== tb.value) tb.committed(text);
                    else if (!m) text = tb.value;
                }
                onEditingFinished: commit()
            }
        }
    }

    // Línea "etiqueta ........ valor"
    component Detail: RowLayout {
        id: line
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        visible: value !== ""
        BarText { text: line.label; color: Theme.dim; font.pixelSize: Theme.fontSize - 1 }
        Item { Layout.fillWidth: true }
        BarText { text: line.value; font.pixelSize: Theme.fontSize - 1 }
    }
}
