#!/bin/sh
# Uso: vpn-toggle.sh up|down UUID
# Activa una VPN usando la contraseña guardada en el llavero (la misma que usa GNOME),
# así no hace falta ningún agente de NetworkManager en labwc.
# Al activar una VPN se desactivan las demás (solo una a la vez). Si la nueva falla,
# se vuelve a conectar la anterior para no quedarse sin VPN.
action=$1
uuid=$2

if [ "$action" = down ]; then
    exec nmcli connection down uuid "$uuid"
fi

# Conecta una VPN (sin terminal). Devuelve el código de nmcli.
connect() {
    t=$(nmcli -g connection.type connection show uuid "$1" 2>/dev/null)
    if [ "$t" = vpn ]; then
        p=$(secret-tool lookup connection-uuid "$1" setting-name vpn setting-key password 2>/dev/null)
        if [ -n "$p" ]; then
            nmcli connection up uuid "$1" passwd-file /dev/stdin <<EOF
vpn.secrets.password:$p
EOF
            return $?
        fi
        return 2   # sin contraseña en el llavero
    fi
    nmcli connection up uuid "$1"
}

# VPNs activas distintas de la que se quiere activar
prev=$(nmcli -t -f UUID,TYPE connection show --active |
       awk -F: -v u="$uuid" '($2=="vpn" || $2=="wireguard") && $1!=u {print $1}')

for p in $prev; do
    nmcli connection down uuid "$p" >/dev/null 2>&1
done

connect "$uuid"
rc=$?

if [ $rc -eq 2 ]; then
    # Sin contraseña en el llavero: pedirla en una terminal
    kitty --title "Conectar VPN" sh -c 'nmcli --ask connection up uuid "$1" || { echo; read -p "Pulsa Enter para cerrar" x; exit 1; }' sh "$uuid"
    rc=$?
fi

if [ $rc -ne 0 ] && [ -n "$prev" ]; then
    # Falló la nueva: restaurar la anterior
    for p in $prev; do
        connect "$p" >/dev/null 2>&1 && { echo "No se pudo conectar; se restauró la VPN anterior" >&2; break; }
    done
fi

exit $rc
