#!/bin/bash
# Baixa tarball Arch Linux ARM aarch64 e gera imagem ext4 3 GiB com label "rootfs".
# Precisa sudo (mount loop + bsdtar preservando perms).
#
# Saída: $ROOTFS_IMG (em $BUILD)

source "$(dirname "$0")/lib.sh"
check_cmd bsdtar
check_cmd mkfs.ext4

if [ "$(id -u)" -ne 0 ]; then
    msg "este script precisa de sudo. Reexecutando..."
    exec sudo -E bash "$0" "$@"
fi

cd "$BUILD"

if [ ! -f "$ARCH_TARBALL" ]; then
    msg "baixando $ARCH_TARBALL_URL..."
    curl -fLO "$ARCH_TARBALL_URL"
fi

MNT="$BUILD/_rootfs_mnt"
mountpoint -q "$MNT" && umount "$MNT" || true
rm -rf "$MNT"
mkdir -p "$MNT"

rm -f "$ROOTFS_IMG"
msg "criando imagem ext4 3 GiB com LABEL=rootfs..."
truncate -s 3G "$ROOTFS_IMG"
mkfs.ext4 -L rootfs -F "$ROOTFS_IMG" >/dev/null

msg "extraindo Arch Linux ARM tarball..."
mount -o loop "$ROOTFS_IMG" "$MNT"
bsdtar -xpf "$ARCH_TARBALL" -C "$MNT"

# Permite login root via console serial
echo "ttyMSM0" >> "$MNT/etc/securetty" 2>/dev/null || true
echo "ttyGS0"  >> "$MNT/etc/securetty" 2>/dev/null || true

# Autologin root no tty1 (framebuffer console) — sem teclado USB ainda,
# então pelo menos garantimos shell ativo na tela em vez de prompt parado.
msg "instalando autologin root no tty1..."
mkdir -p "$MNT/etc/systemd/system/getty@tty1.service.d"
cat > "$MNT/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 38400 linux
EOF

# Habilita serial-getty@ttyGS0 com autologin root. Sem isso, o systemd nao
# spawna getty no CDC ACM (so spawna em ttyS*/ttyMSM* por padrao) e o tty
# fica brigado entre o shell do initramfs e nada — daí trava.
msg "instalando serial-getty@ttyGS0 com autologin root..."
mkdir -p "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d"
cat > "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d/autologin.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --keep-baud 115200,57600,38400,9600 %I $TERM
# CDC ACM nao tem flow control de hardware — desliga pra evitar travas
TTYReset=no
TTYVHangup=no
TTYVTDisallocate=no
EOF
mkdir -p "$MNT/etc/systemd/system/getty.target.wants"
ln -sf /usr/lib/systemd/system/serial-getty@.service \
    "$MNT/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service"

# Desliga USB autosuspend para o gadget (evita o controller suspender com a
# sessao ACM ativa, o que aparece como "trava" no host).
msg "desligando USB autosuspend via udev rule..."
mkdir -p "$MNT/etc/udev/rules.d"
cat > "$MNT/etc/udev/rules.d/50-usb-gadget-noautosuspend.rules" <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"
EOF

sync
umount "$MNT"
rmdir "$MNT"

msg "OK: $ROOTFS_IMG ($(du -h "$ROOTFS_IMG" | cut -f1))"
msg "Login default Arch ARM: root/root  ou  alarm/alarm"
