import QtQuick
import qs.config

Text {
    color: Theme.fg
    font.family: Theme.font
    font.pixelSize: Theme.fontSize
    verticalAlignment: Text.AlignVCenter
    // Texto plano por defecto: con AutoText, un contenido que "parezca" HTML
    // (p. ej. <img src="file://…"> copiado al portapapeles) se renderiza como
    // HTML y carga la imagen a tamaño completo encima de todo. Quien quiera
    // formato lo pide explícitamente (Bar: título multimedia; NotifCard: cuerpo).
    textFormat: Text.PlainText
}
