#!/bin/bash
# Instala dependências de build no host (Arch Linux x86_64).
# Para outras distros, traduza os pacotes equivalentes.

set -euo pipefail

if ! command -v pacman >/dev/null; then
    cat <<EOF
Esse script foi escrito para Arch Linux x86_64.

Pacotes equivalentes em outras distros:
  Debian/Ubuntu: gcc-aarch64-linux-gnu gcc-arm-none-eabi binutils-arm-none-eabi \\
                 libnewlib-arm-none-eabi android-sdk-platform-tools \\
                 device-tree-compiler bsdtar cpio gzip curl git
  Fedora:        gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \\
                 arm-none-eabi-gcc-cs arm-none-eabi-binutils-cs newlib \\
                 android-tools dtc bsdtar cpio gzip curl git
EOF
    exit 1
fi

PKGS=(
    aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils
    arm-none-eabi-gcc arm-none-eabi-binutils arm-none-eabi-newlib
    android-tools
    dtc
    bsdtar cpio gzip curl git
    bc flex bison
    libelf openssl
)

echo "Instalando: ${PKGS[*]}"
sudo pacman -S --needed "${PKGS[@]}"
