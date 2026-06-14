#!/bin/bash
# Configura wpa_supplicant no rootfs para CASA_5G.
# Pede senha interativamente (read -s) — senha nunca aparece em comando ou log.
set -euo pipefail

ROOTFS="${1:-$(dirname "$0")/../build/rootfs-arch-headless.img}"
MNT=/tmp/rootfs-wifi-mnt

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

[ -f "$ROOTFS" ] || { echo "ERRO: $ROOTFS não encontrado"; exit 1; }

echo "Montando rootfs: $ROOTFS"
mkdir -p "$MNT"
mount -o loop "$ROOTFS" "$MNT"

mkdir -p "$MNT/etc/wpa_supplicant"

read -r -s -p "Senha Wi-Fi CASA_5G: " WIFI_PASS
echo

# wpa_passphrase gera PSK hash — senha não fica em plaintext no config
CONF=$(wpa_passphrase CASA_5G "$WIFI_PASS")
unset WIFI_PASS

# Remove linha #psk= (contém plaintext como comentário)
echo "$CONF" | grep -v '^\s*#psk=' \
    > "$MNT/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
unset CONF

echo "wpa_supplicant-wlan0.conf escrito (PSK hasheado, sem plaintext)"
ls -la "$MNT/etc/wpa_supplicant/"

sync
umount "$MNT"
rmdir "$MNT"
echo "OK — rootfs pronto."
