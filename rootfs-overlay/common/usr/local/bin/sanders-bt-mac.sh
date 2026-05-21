#!/bin/bash
# Restaura o MAC Bluetooth de fabrica do sanders no controller hci0.
#
# Motivacao: o driver btqcomsmd nao le o MAC da NV/persist do device, entao
# o controller aparece com MAC locally-administered aleatorio (02:xx:..) a
# cada boot. Resultado: nenhum pareamento persiste, MAC nao tem OUI real.
#
# Stock Android guarda o MAC em /persist/bluetooth/.bt_nv.bin no formato
# Qualcomm NV: 9 bytes, header (type=0x01, item=0x01, len=0x06) + 6 bytes
# do MAC em little-endian (byte-reversed). Ex.: "7c 4f df 14 77 d0" no
# arquivo equivale a "D0:77:14:DF:4F:7C" como string MAC.
#
# Este script deve rodar ANTES do bluetooth.service, por isso o unit
# correspondente tem Before=bluetooth.service.

set -e

PERSIST_DEV="/dev/disk/by-partlabel/persist"
NV_FILE_REL="bluetooth/.bt_nv.bin"
MOUNT="/run/sanders-persist"

cleanup() {
    if mountpoint -q "$MOUNT" 2>/dev/null; then
        umount "$MOUNT" 2>/dev/null || true
    fi
    rmdir "$MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

if [ ! -e "$PERSIST_DEV" ]; then
    echo "sanders-bt-mac: persist partition $PERSIST_DEV not found, skipping" >&2
    exit 0
fi

mkdir -p "$MOUNT"
mount -o ro "$PERSIST_DEV" "$MOUNT" || {
    echo "sanders-bt-mac: failed to mount $PERSIST_DEV" >&2
    exit 0
}

NV="$MOUNT/$NV_FILE_REL"
if [ ! -f "$NV" ]; then
    echo "sanders-bt-mac: $NV_FILE_REL not found in persist, skipping" >&2
    exit 0
fi

# Sanity: arquivo Qualcomm NV pra item BT_ADDR tem 9 bytes (3 de header + 6
# de MAC). Header esperado: 01 01 06.
SIZE=$(stat -c %s "$NV")
if [ "$SIZE" -ne 9 ]; then
    echo "sanders-bt-mac: unexpected size $SIZE for $NV (expected 9)" >&2
    exit 0
fi

# Le 9 bytes em hex, valida header, extrai os 6 do MAC e reverte para
# formato XX:XX:XX:XX:XX:XX.
HEX=$(od -An -v -tx1 -N9 "$NV" | tr -d ' \n')
HDR=${HEX:0:6}
if [ "$HDR" != "010106" ]; then
    echo "sanders-bt-mac: unexpected NV header $HDR (expected 010106)" >&2
    exit 0
fi

# Bytes 3..8 do hex (offset 6..18 em chars), ordem reversa:
MAC=$(printf '%s:%s:%s:%s:%s:%s' \
    "${HEX:16:2}" "${HEX:14:2}" "${HEX:12:2}" \
    "${HEX:10:2}" "${HEX:8:2}" "${HEX:6:2}" | tr 'a-f' 'A-F')

if ! echo "$MAC" | grep -qE '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'; then
    echo "sanders-bt-mac: parsed MAC '$MAC' invalid" >&2
    exit 1
fi

if [ "$MAC" = "00:00:00:00:00:00" ] || [ "$MAC" = "FF:FF:FF:FF:FF:FF" ]; then
    echo "sanders-bt-mac: parsed MAC is sentinel ($MAC), skipping" >&2
    exit 0
fi

# btmgmt sob systemd nao tem TTY na stdin. Com stdin=/dev/null ele trava
# (nao da EOF clean — bug de versao da bluez-utils ou intencional pro modo
# interativo). Solucao: rodar via `script -qc` (util-linux), que aloca
# um pseudo-tty efemero e btmgmt processa o comando e sai limpo.
# Sem script: btmgmt info levaria 3s timeout e devolveria stdout vazio.
# Com script: ~50ms.
btmgmt_run() {
    script -qc "btmgmt --index 0 $*" /dev/null
}

current_mac() {
    btmgmt_run info 2>/dev/null \
        | awk '/Primary controller/ { found=1; next } found && /^[[:space:]]*addr / { print toupper($2); exit }'
}

# `set +e` localmente — btmgmt as vezes retorna erro mesmo aplicando.
set +e

CUR=$(current_mac)
if [ "$CUR" = "$MAC" ]; then
    echo "sanders-bt-mac: hci0 ja esta com $MAC"
    exit 0
fi

echo "sanders-bt-mac: applying $MAC to hci0 (estava $CUR)"

btmgmt_run power off       >/dev/null 2>&1
btmgmt_run public-addr "$MAC" >/dev/null 2>&1

# public-addr pode re-criar o controller; espera hci0 voltar (ate 5s).
for _ in 1 2 3 4 5; do
    [ -e /sys/class/bluetooth/hci0 ] && break
    sleep 1
done

btmgmt_run power on >/dev/null 2>&1

# Validacao final.
CUR=$(current_mac)
if [ "$CUR" = "$MAC" ]; then
    echo "sanders-bt-mac: hci0 agora com $MAC"
    exit 0
fi

echo "sanders-bt-mac: aplicou public-addr mas info reporta '$CUR'" >&2
exit 1
