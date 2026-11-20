# Greeter de Quickshell (greetd)

Pantalla de inicio de sesión con el mismo diseño que el lock screen.
Esta carpeta es la fuente; `install.sh` la copia a `/etc/greetd/quickshell`
(el usuario `greeter` no puede leer tu `$HOME`). Tras editar `shell.qml`, vuelve a ejecutar `install.sh`.

| Archivo | Qué es |
|---|---|
| `shell.qml` | El greeter. Sin greetd funciona como vista previa: `qs -p ~/.config/quickshell-greeter` |
| `start.sh` | Lo lanza greetd: cage + Quickshell. Si falla, cae a `agreety` (login de texto) |
| `config.toml` | `/etc/greetd/config.toml` (vt 7 = prueba; `activate.sh` lo pone en 1) |
| `pam-greetd` | `/etc/pam.d/greetd`: igual que GDM, con gnome-keyring |
| `install.sh` | Paso 1: instala en modo prueba, sin tocar el arranque |
| `activate.sh` | Paso 2: greetd sustituye a GDM (GDM queda instalado) |
| `revert.sh` | Volver a GDM |

La sesión labwc arranca con `~/.config/labwc/session.sh`, que reproduce el entorno de GDM
(idioma de `/etc/locale.conf`, `environment.d`, shell de login).

## Rescate
- Greeter roto → `start.sh` muestra el login de texto automáticamente.
- Nada funciona → `Ctrl+Alt+F3`, entra con tu usuario y:
  `sudo sh ~/.config/quickshell-greeter/revert.sh && sudo reboot`
