#!/bin/bash
# Setup de rede no HOST (PC) pra que o phone (sanders) tenha:
#  - IP estatico do lado do host (10.42.0.1/24)
#  - NAT/MASQUERADE pra saida pela interface WAN do host
#  - FORWARD liberado entre a iface do gadget e a WAN
#
# Roda no host, nao no phone. Precisa sudo. Idempotente (regras
# duplicadas sao detectadas).
#
# Uso:
#   ./scripts/08-host-net.sh                # detecta wan automaticamente
#   ./scripts/08-host-net.sh enp0s20f0u4i2 br0   # iface gadget + wan explicitos

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

GADGET_IFACE="${1:-}"
WAN_IFACE="${2:-}"

# Auto-detecta a iface do gadget pelo MAC que setamos no initramfs.
if [ -z "$GADGET_IFACE" ]; then
    GADGET_IFACE=$(ip -o link | awk -F': ' '/02:11:22:33:44:55/ {print $2}' | head -1)
fi
[ -z "$GADGET_IFACE" ] && { echo "ERRO: gadget iface nao encontrada. Phone esta conectado e bootado?"; exit 1; }

# Auto-detecta WAN pela default route.
if [ -z "$WAN_IFACE" ]; then
    WAN_IFACE=$(ip -4 route show default | awk '{print $5; exit}')
fi
[ -z "$WAN_IFACE" ] && { echo "ERRO: WAN iface nao detectada (sem default route)."; exit 1; }

echo "[host-net] gadget=$GADGET_IFACE  wan=$WAN_IFACE"

ip link set "$GADGET_IFACE" up
ip addr replace 10.42.0.1/24 dev "$GADGET_IFACE"

sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Adiciona regras so se nao existirem (-C testa, retorna 0 se existe).
iptables -t nat -C POSTROUTING -s 10.42.0.0/24 -o "$WAN_IFACE" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -s 10.42.0.0/24 -o "$WAN_IFACE" -j MASQUERADE
iptables -C FORWARD -i "$GADGET_IFACE" -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -i "$GADGET_IFACE" -j ACCEPT
iptables -C FORWARD -o "$GADGET_IFACE" -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -o "$GADGET_IFACE" -j ACCEPT

echo "[host-net] OK. ping 10.42.0.2 e teste internet no phone."
