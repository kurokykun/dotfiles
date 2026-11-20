# Quickshell — estructura

```
shell.qml        Punto de entrada: instancia los módulos y los IpcHandler
config/          Theme (colores, tamaños, animaciones) · Icons (glifos Nerd Font)
services/        Singletons SIN interfaz: estado y lógica (Apps, Audio, Brightness, Caffeine, Clipboard, Keyboard, NightLight, Screenshot, ThemeEngine, Wallpaper, Workspaces,
                 Lock, Media, Network, Notifs, Osd, Ui, Weather, Cntlm)
widgets/         Piezas reutilizables (Pill, BarText, ActionButton, ListRow, FormField, QuickTile, PanelPopup…)
modules/<x>/     Una carpeta por componente visible (bar, dock, launcher, osd…)
scripts/         Scripts de shell auxiliares
*.json           Datos persistentes (frecuentes del lanzador, ubicación del clima)
```

## Reglas
- Los archivos de la misma carpeta se ven entre sí sin `import`.
- Entre carpetas: `import qs.config`, `import qs.services`, `import qs.widgets`,
  `import qs.modules.<x>`.
- `services/` no importa `widgets/` ni `modules/` (la lógica no depende de la UI).
- Rutas a archivos: siempre relativas a `Quickshell.shellDir`, nunca a la carpeta del .qml.
- Un componente nuevo = `modules/<nombre>/` + una línea en `shell.qml`.

## IPC útiles
```
qs ipc call launcher toggle      qs ipc call brightness changed
qs ipc call launcher open "="    (abre en calculadora; también ":" "/" ">" "?")
qs ipc call power toggle         qs ipc call osd test
qs ipc call media playpause      qs ipc show   # lista todo
```

## Lanzador
- Prefijos: `=` calculadora · `>` comando · `/` archivos · `:` emoji · `?` web.
  Las operaciones (`2+2`, `200*15%`) se detectan sin `=`.
- Ocultar apps: `hiddenApps` en `services/Apps.qml` (se respeta OnlyShowIn/NotShowIn;
  `forceShow` fuerza mostrar alguna).

## Lock screen (modules/lock, services/Lock.qml)
- `qs ipc call lock preview` → vista previa sin bloquear (Esc con el campo vacío para salir).
- `scripts/lock.sh` → bloqueo real, con swaylock de respaldo si Quickshell no responde.
- PAM: `modules/lock/pam/lockscreen` (solo pam_unix, sin faillock).

### Si algo falla estando bloqueado (recuperación)
1. `Ctrl+Alt+F3` → inicia sesión en la TTY con tu usuario.
2. Ejecuta:
   ```
   pkill -x quickshell
   WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$(id -u) swaylock
   ```
   labwc deja que swaylock reemplace el bloqueo abandonado.
3. `Ctrl+Alt+F2` → vuelve a tu sesión y desbloquea con swaylock.
4. Relanza la barra: `quickshell &` (o Super+N).
Último recurso: `loginctl terminate-session <id>` (cierra la sesión, se pierde lo no guardado).

## Portapapeles (services/Clipboard.qml, modules/clipboard)
- Super+V abre el historial. Enter pega en la ventana activa (Ctrl+Shift+V en terminales),
  Shift+Enter solo copia, Supr borra, Ctrl+Shift+Supr vacía (pide confirmación).
- Captura: `wl-paste --watch scripts/clip-store.sh` (texto e imágenes) desde el autostart de labwc,
  independiente de Quickshell. Backend: cliphist (`~/.cache/cliphist/db`, sin cifrar), 500 entradas.
- Fase 2: Tab cambia de filtro (Todo, Fijados, Texto, Código, Enlaces, Colores, Imágenes), Ctrl+P fija.
  Fijados y metadatos (hora, app de origen) en `~/.local/share/quickshell/clipboard/`;
  detección de tipos en `services/clipdetect.js`. `qs ipc call clipboard pinLatest` fija lo último copiado.
- No se guarda: contenido marcado como sensible (gestores de contraseñas) ni nada mientras está en pausa
  (`qs ipc call clipboard togglePause`).
- Fase 3: → o Ctrl+K abre las acciones sobre la entrada (formatear JSON, camelCase/snake_case, Base64,
  URL encode, colores hex/rgb/hsl, abrir enlaces y rutas…) con el resultado en vivo; Enter pega el resultado.
  `qs ipc call clipboard transform` abre las acciones de lo último copiado. Lógica en `services/cliptransforms.js`.

### Portapapeles: pendiente (por si se retoma)
Decisiones ya tomadas por el usuario: Enter pega · historial de 500 · secretos ocultos y con caducidad.
- **Fase 4 – Snippets:** plantillas con nombre y variables (`{fecha}`, `{hora}`, `{portapapeles}`, `{uuid}`),
  búsqueda también desde el launcher (prefijo `;`), pegar varias entradas unidas (salto de línea / coma).
- **Fase 5 – Privacidad:** detectar secretos (`ghp_…`, `sk-…`, claves AWS, JWT) → guardarlos OCULTOS en la
  lista y que CADUQUEN a los ~5 min; indicador en la barra (icono, pausa/incógnito con un clic) y aviso
  "Copiado" con el OSD.
- **Fase 6 – Extras:** OCR de imágenes (tesseract), guardar una imagen del historial como archivo,
  sincronizar la selección primaria.
- **Atajo:** `qs ipc call clipboard transform` en Super+Shift+V (no está puesto en rc.xml).

## Energía y pantalla (modules/battery, services/NightLight.qml, services/Caffeine.qml)
- **Luz nocturna** (wlsunset): automática por atardecer/amanecer con la ubicación del clima, horario fijo
  o siempre; calidez 2500–5500 K. Config en `~/.local/state/quickshell/nightlight.json`.
  `qs ipc call nightlight toggle | mode auto|schedule|always | status`
- **Cafeína**: impide bloquear/apagar la pantalla (protocolo idle-inhibit, `modules/idle/IdleInhibit.qml`).
  Se activa sola mientras suena música o vídeo (MPRIS). `qs ipc call caffeine toggle | auto true|false | status`
- Barra: pastilla de indicadores (luz nocturna, cafeína, no molestar, portapapeles en pausa) solo si hay alguno activo.
- Calendario: sin notificaciones y con música sonando, muestra el reproductor en el espacio libre.

## Capturas (services/Screenshot.qml, modules/screenshot)
- `Print` / `Super+Shift+S`: capa de selección sobre la pantalla CONGELADA (grim a `$XDG_RUNTIME_DIR/qs-shot/frozen.png`).
  Arrastrar = región · tiradores/flechas ajustan · R última región · F o "Pantalla" = todo · Enter/doble clic captura.
- `Shift+Print`: pantalla completa al instante. Respaldo en labwc: `~/.config/labwc/screenshot.sh` si Quickshell no responde.
- Al terminar: guarda en `~/Pictures/Capturas/captura-FECHA.png`, copia al portapapeles (entra en Super+V) y muestra
  la miniatura con Editar (satty) · Abrir · Carpeta (Thunar con el archivo seleccionado) · Borrar.
- Pendiente: fase 2 (satty, temporizador, puntero, cuentagotas) y fase 3 (ventana, OCR con tesseract, grabación con wf-recorder).
- Fase 2: E capturar y editar (satty, `~/.config/satty/config.toml` con la paleta del escritorio; Enter copia+guarda),
  T temporizador 3/5/10 s (captura EN VIVO tras la cuenta atrás), P incluir puntero, C cuentagotas (copia `#hex`).
  Tras cambios grandes en estos módulos, reiniciar Quickshell (Super+N): la recarga en caliente puede dejar código viejo.

## Escritorios (services/Workspaces.qml, modules/osd/WorkspaceOsd.qml)
- Protocolo ext-workspace (`Quickshell.WindowManager`); la lista llega asíncrona tras arrancar.
- Barra izquierda: un punto por escritorio (el activo se alarga). Clic = ir, rueda = siguiente/anterior.
  Sustituye al antiguo botón del launcher (el launcher sigue en la tecla Super y en el dock).
- Aviso al cambiar: pastilla centrada. El de labwc está desactivado (`rc.xml`: `<popupTime>0</popupTime>`,
  prefijo "Escritorio"). `qs ipc call workspaces next | previous | go N`
- Fase 3: W elegir ventana (miniaturas reales; `scripts/list-windows.py` habla ext-foreign-toplevel-list y
  `grim -T` captura la ventana aunque esté tapada) · O OCR (tesseract spa+eng, local, ×2 antes de reconocer)
  · G grabar región o pantalla (wf-recorder H.264 por CPU → `~/Videos/Grabaciones`; indicador rojo en la barra,
  clic = detener; la ruta queda en el portapapeles). `qs ipc call screenshot record | stopRecording`

## Fondos (services/Wallpaper.qml, modules/wallpaper)
- Quickshell dibuja el fondo (capa Bottom, uno por monitor) con transiciones: círculo (desde el clic), fundido,
  zoom, barrido o aleatoria. swaybg queda DEBAJO con el mismo fondo como respaldo.
- `~/.local/state/quickshell/wallpaper` = enlace al fondo actual (lo usan autostart, lock.sh y el lock).
- Super+W: selector (franja inferior). ← → aplica al detenerse · Enter acepta · Esc vuelve al de antes
  · R aleatorio · T transición. Fondos en `~/Pictures/Wallpapers` (miniaturas en `~/.cache/quickshell/wallthumbs`).
- `qs ipc call wallpaper toggle | next | prev | random | set RUTA | current`
- Pendiente: fase 2 (matugen → tema dinámico), fase 3 (Wallhaven), fase 4 (apps y shaders). El greeter no cambia solo.

## Tema automático (services/ThemeEngine.qml → config/Theme.qml)
- Al cambiar el fondo, matugen (`--prefer saturation -b wal`) genera la paleta → `~/.local/state/quickshell/colors.json`.
  Mapeo: base/paneles = base16 base00 (oscuro dominante) · acento = primaria tono 70 · acento 2 = terciaria tono 70
  · texto = neutral 95 / variante 70 · texto sobre acento = primaria tono 10 (`Theme.textOnAccent`).
- Theme.qml anima los cambios (0,8 s). Rojo/verde/amarillo/azul son fijos (tienen significado).
- Interruptor "Tema automático" en el selector de fondos. `qs ipc call theme auto true|false | regenerate | status`
- No usar nombres de propiedad que empiecen por "on" + mayúscula (QML los toma como manejadores de señal).
- Fase 3: pestaña Wallhaven en el selector (Tab). `scripts/wallhaven.py` busca (solo contenido apto, ≥1920x1080,
  16:9/16:10) y guarda miniaturas en `~/.cache/quickshell/wallhaven` (≈22 KB, nunca se repiten). La imagen completa
  solo se descarga al elegirla → `~/Pictures/Wallpapers/wallhaven-ID.ext`. Cada tarjeta muestra su peso; contador
  de datos de la sesión. Filtros guardados en `~/.local/state/quickshell/wallhaven.json`.

## Rendimiento (filosofía: bonito sin necesitar hardware potente)
- Nada de animaciones continuas: con pantalla de 144 Hz cada fotograma obliga a labwc a recomponer.
  El ecualizador va a 8 fps a saltos; las barras de progreso de la canción no se animan.
- Animaciones en ventanas ocultas: condicionar `running` a que se vean (Equalizer, reloj del lock).
- Procesos que lanza Quickshell (wl-paste, wlsunset) se limpian al arrancar para no dejar huérfanos.
- Medición en reposo con música: quickshell ~3 % CPU, labwc ~4 % (antes 38 % y 19,5 %).

## Ventanas: plantillas y tema de labwc
- Plantillas (rc.xml `<regions>`): arrastra una ventana MANTENIENDO Shift (o Ctrl/Alt) → mitades, tercios, ⅔+⅓,
  cuadrantes. Con Super también, pero al soltarla se abre el launcher. Sin modificador: bordes/esquinas/arriba.
- El tema de labwc (bordes, menús, Alt+Tab, vista previa) sigue al tema automático:
  edita `~/.config/labwc/themerc-override.template`; `scripts/labwc-theme.py` genera themerc-override.
