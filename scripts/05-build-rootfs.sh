#!/bin/bash
# Baixa tarball Arch Linux ARM aarch64 e gera imagem ext4 3 GiB com label "rootfs".
# Precisa sudo (mount loop + bsdtar preservando perms).
#
# Saída: $ROOTFS_IMG (em $BUILD)

source "$(dirname "$0")/lib.sh"
check_cmd bsdtar
check_cmd mkfs.ext4
check_cmd wget

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

case "$FLAVOR" in
    headless) IMG_SIZE=3G ;;
    desktop)  IMG_SIZE=6G ;;
    mini)     IMG_SIZE=2G ;;
esac
rm -f "$ROOTFS_IMG"
msg "criando imagem ext4 $IMG_SIZE (FLAVOR=$FLAVOR) com LABEL=rootfs..."
truncate -s "$IMG_SIZE" "$ROOTFS_IMG"
mkfs.ext4 -L rootfs -F "$ROOTFS_IMG" >/dev/null

msg "extraindo Arch Linux ARM tarball..."
mount -o loop "$ROOTFS_IMG" "$MNT"
bsdtar -xpf "$ARCH_TARBALL" -C "$MNT"

# Verifica se arch-chroot + qemu-aarch64 funcionam de verdade (nao so existem).
# No WSL o binfmt pode estar registrado mas o flag F (fix-binary) ausente, fazendo
# os binarios aarch64 falharem dentro do chroot mesmo com qemu-aarch64-static presente.
CHROOT_WORKS=0
if command -v arch-chroot >/dev/null && [ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    QEMU_STATIC=$(command -v qemu-aarch64-static 2>/dev/null || echo "")
    if [ -n "$QEMU_STATIC" ]; then
        mkdir -p "$MNT/usr/bin"
        cp "$QEMU_STATIC" "$MNT/usr/bin/qemu-aarch64-static"
    fi
    # Teste real: tenta executar /bin/true do rootfs aarch64
    if arch-chroot "$MNT" /bin/true 2>/dev/null; then
        CHROOT_WORKS=1
    fi
fi

# Fallback para hosts sem arch-chroot funcional e sem pacman nativo:
# baixa pacotes Arch Linux ARM conhecidos e extrai direto no rootfs.
# Isto e usado apenas para o userspace Wi-Fi critico; nao tenta resolver
# dependencias genericamente.
alarm_direct_install() {
    local pkg repo file cache_dir url
    cache_dir="$BUILD/alarm-pkg-cache"
    mkdir -p "$cache_dir"

    for pkg in "$@"; do
        case "$pkg" in
            wpa_supplicant) repo=core;  file="wpa_supplicant-2:2.11-5-aarch64.pkg.tar.xz" ;;
            iw)             repo=core;  file="iw-6.17-1-aarch64.pkg.tar.xz" ;;
            dhcpcd)         repo=extra; file="dhcpcd-10.3.2-1-aarch64.pkg.tar.xz" ;;
            pcsclite)       repo=extra; file="pcsclite-2.5.0-1-aarch64.pkg.tar.xz" ;;
            *) warn "fallback direto nao conhece pacote: $pkg"; return 1 ;;
        esac

        url="http://os.archlinuxarm.org/aarch64/$repo/$file"
        if [ ! -s "$cache_dir/$file" ]; then
            msg "baixando pacote ALARM direto: $file"
            wget -O "$cache_dir/$file" "$url" || return 1
        fi

        msg "extraindo pacote ALARM direto: $file"
        bsdtar -xpf "$cache_dir/$file" -C "$MNT" \
            --exclude .BUILDINFO --exclude .INSTALL --exclude .MTREE --exclude .PKGINFO \
            || return 1
    done
}

# Funcao auxiliar: instala pacotes via arch-chroot (se funcionar) ou
# pacman --root com SigLevel=Never como fallback (sem scripts pos-instalacao).
pacman_install() {
    local pkgs="$*"
    if [ "$CHROOT_WORKS" = "1" ]; then
        arch-chroot "$MNT" pacman -Sy --noconfirm --needed $pkgs
    else
        if ! command -v pacman >/dev/null; then
            warn "pacman nativo indisponivel no host"
            return 1
        fi
        warn "arch-chroot indisponivel — instalando via pacman --root (sem scripts pos-install)"
        local tmpconf
        tmpconf=$(mktemp)
        # Usa config do target mas sobrepoe SigLevel pois o keyring ainda nao foi init
        sed 's/^SigLevel.*/SigLevel = Never/' "$MNT/etc/pacman.conf" > "$tmpconf"
        pacman --root "$MNT" --dbpath "$MNT/var/lib/pacman" \
            --config "$tmpconf" --cachedir /tmp/pacman-cache-arm \
            --noscriptlet --noconfirm --needed -Sy $pkgs
        local rc=$?
        rm -f "$tmpconf"
        return "$rc"
    fi
}

# Locale: edicao de texto puro, feita direto no host (nao precisa de chroot).
# locale-gen requer aarch64; deferido para primeiro boot se chroot nao funcionar.
msg "habilitando locale pt_BR.UTF-8 + en_US.UTF-8..."
sed -i \
    -e 's/^#\(pt_BR.UTF-8 UTF-8\)/\1/' \
    -e 's/^#\(en_US.UTF-8 UTF-8\)/\1/' \
    "$MNT/etc/locale.gen"
if [ "$CHROOT_WORKS" = "1" ]; then
    msg "inicializando pacman keyring (via arch-chroot + qemu-aarch64)..."
    arch-chroot "$MNT" pacman-key --init >/dev/null 2>&1 || warn "pacman-key --init falhou"
    arch-chroot "$MNT" pacman-key --populate archlinuxarm >/dev/null 2>&1 \
        || warn "pacman-key --populate archlinuxarm falhou"
    arch-chroot "$MNT" locale-gen >/dev/null 2>&1 || warn "locale-gen falhou"
else
    warn "arch-chroot nao funciona — keyring e locale-gen serao inicializados no primeiro boot"
    # Fallback: service que inicializa keyring + locale no primeiro boot
    cat > "$MNT/etc/systemd/system/pacman-keyring-init.service" <<'EOF'
[Unit]
Description=Inicializa pacman keyring e locale (apenas uma vez)
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/etc/pacman.d/gnupg/pubring.gpg

[Service]
Type=oneshot
ExecStart=/usr/bin/pacman-key --init
ExecStart=/usr/bin/pacman-key --populate archlinuxarm
ExecStart=/usr/bin/locale-gen
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
    ln -sf /etc/systemd/system/pacman-keyring-init.service \
        "$MNT/etc/systemd/system/multi-user.target.wants/pacman-keyring-init.service"
fi

# Samba: util pros flavors headless/desktop. Mini nao inclui.
if [ "$FLAVOR" != "mini" ]; then
    msg "instalando samba (sem habilitar smb/nmb)..."
    pacman_install samba || warn "samba nao instalado neste build (pacman/chroot indisponivel)"
fi

# Wi-Fi userspace: wpa_supplicant (WPA2/WPA3 4-way handshake),
# iw (scan/management), dhcpcd (IP por DHCP). pcsclite fornece
# libpcsclite.so.1, linkada pelo wpa_supplicant do Arch Linux ARM.
# Sem acesso a internet no device (USB ECM instavel), tem que vir embutido.
msg "instalando wpa_supplicant iw dhcpcd pcsclite..."
if ! pacman_install wpa_supplicant iw dhcpcd pcsclite; then
    warn "pacman/chroot falhou para Wi-Fi; usando fallback direto ALARM"
    alarm_direct_install wpa_supplicant iw dhcpcd pcsclite \
        || die "falha instalando userspace Wi-Fi via fallback direto"
fi

if [ "$FLAVOR" = "mini" ]; then
    if [ "$CHROOT_WORKS" != "1" ]; then
        die "FLAVOR=mini requer arch-chroot + qemu-aarch64 funcionando no host"
    fi
    msg "instalando pacotes mini (nginx, nftables, evtest)..."
    arch-chroot "$MNT" pacman -Sy --noconfirm --needed \
        nginx nftables evtest \
        || die "pacman -S do stack mini falhou"

    msg "habilitando nginx e nftables..."
    arch-chroot "$MNT" systemctl enable nginx.service >/dev/null
    arch-chroot "$MNT" systemctl enable nftables.service >/dev/null
    arch-chroot "$MNT" systemctl enable wpa_supplicant@wlan0.service >/dev/null

    msg "baixando cloudflared arm64..."
    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    CF_BIN="$MNT/usr/local/bin/cloudflared"
    if curl -fsSL -o "$CF_BIN" "$CF_URL"; then
        chmod +x "$CF_BIN"
        msg "cloudflared instalado em /usr/local/bin/cloudflared"
    else
        warn "falha ao baixar cloudflared — instale manualmente depois"
    fi
fi

if [ "$FLAVOR" = "desktop" ]; then
    if [ "$CHROOT_WORKS" != "1" ]; then
        die "FLAVOR=desktop requer arch-chroot + qemu-aarch64 funcionando no host"
    fi
    msg "instalando stack desktop (weston + xwayland + mesa) via arch-chroot..."
    # Instala dois compositores: phosh (default, shell mobile) +
    # weston (alternativa minimalista). Decisao de qual usar e via
    # systemctl enable/disable. Default no overlay e phosh.
    arch-chroot "$MNT" pacman -Sy --noconfirm --needed \
        phoc phosh squeekboard \
        weston \
        seatd libdisplay-info \
        xorg-xwayland mesa mesa-utils mesa-demos \
        ttf-dejavu noto-fonts \
        || die "pacman -S do stack desktop falhou"
    arch-chroot "$MNT" systemctl enable seatd.service >/dev/null
fi

# Expansao do filesystem na primeira boot. A imagem ext4 e gerada com 3 GiB
# fixos (truncate + mkfs), mas o fastboot grava ela numa particao userdata
# de ~24 GiB — sem resize2fs sobrariam ~21 GiB inutilizados e a / lota
# rapido (pacman -Syu enche). Oneshot que se auto-desativa via marker em
# /var/lib/sanders-rootfs-expanded.
msg "instalando sanders-rootfs-expand.service (resize2fs no primeiro boot)..."
cat > "$MNT/etc/systemd/system/sanders-rootfs-expand.service" <<'EOF'
[Unit]
Description=Expande o filesystem root para ocupar toda a particao (apenas uma vez)
DefaultDependencies=no
After=systemd-remount-fs.service
Before=local-fs.target sysinit.target
ConditionPathExists=!/var/lib/sanders-rootfs-expanded

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'ROOT=$(findmnt -no SOURCE /); echo "expanding $ROOT"; /usr/sbin/resize2fs "$ROOT"'
ExecStartPost=/bin/sh -c 'mkdir -p /var/lib && touch /var/lib/sanders-rootfs-expanded'

[Install]
WantedBy=sysinit.target
EOF
mkdir -p "$MNT/etc/systemd/system/sysinit.target.wants"
ln -sf /etc/systemd/system/sanders-rootfs-expand.service \
    "$MNT/etc/systemd/system/sysinit.target.wants/sanders-rootfs-expand.service"

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

# Rede USB (NCM gadget): IP estatico 10.42.0.2/24 em usb0 via systemd-networkd.
# Host fica com 10.42.0.1/24. Match por MAC pra nao depender do nome da iface.
msg "configurando systemd-networkd em usb0 (10.42.0.2/24)..."
mkdir -p "$MNT/etc/systemd/network"
cat > "$MNT/etc/systemd/network/10-usb0.network" <<'EOF'
[Match]
MACAddress=02:55:44:33:22:11

[Network]
Address=10.42.0.2/24
Gateway=10.42.0.1
DNS=8.8.8.8
DNS=1.1.1.1
ConfigureWithoutCarrier=yes

[Route]
Destination=0.0.0.0/0
Gateway=10.42.0.1
# Metrica alta pra nao competir com wlan se um dia tiver — usb gadget eh
# rede de servico, nao a saida primaria.
Metric=100
EOF
# resolv.conf gerenciado por systemd-resolved (que pega DNS do networkd)
ln -sf /run/systemd/resolve/stub-resolv.conf "$MNT/etc/resolv.conf"
ln -sf /usr/lib/systemd/system/systemd-resolved.service \
    "$MNT/etc/systemd/system/multi-user.target.wants/systemd-resolved.service"
mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
mkdir -p "$MNT/etc/systemd/system/sockets.target.wants"
ln -sf /usr/lib/systemd/system/systemd-networkd.service \
    "$MNT/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
ln -sf /usr/lib/systemd/system/systemd-networkd.socket \
    "$MNT/etc/systemd/system/sockets.target.wants/systemd-networkd.socket"

# SSH: permite login root com senha (padrao Arch ARM eh "root"). Habilita sshd.
msg "habilitando sshd com PermitRootLogin yes..."
mkdir -p "$MNT/etc/ssh/sshd_config.d"
cat > "$MNT/etc/ssh/sshd_config.d/10-sanders.conf" <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
EOF
ln -sf /usr/lib/systemd/system/sshd.service \
    "$MNT/etc/systemd/system/multi-user.target.wants/sshd.service"

# Firmware proprietario (Wi-Fi pronto + iris cal). Sem isso o
# remoteproc do wcnss falha em carregar e o wcn36xx nao traz iface up.
# Use scripts/09-extract-firmware.sh pra extrair do flashfile stock.
check_wcnss_firmware
msg "instalando firmware Wi-Fi (wcnss) no rootfs..."
mkdir -p "$MNT/lib/firmware/wlan/prima"
cp -v "$REPO/firmware"/wcnss.* "$MNT/lib/firmware/" | tail -3
if [ -f "$REPO/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin" ]; then
    cp "$REPO/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin" \
        "$MNT/lib/firmware/wlan/prima/"
else
    warn "WCNSS_qcom_wlan_nv.bin ausente — Wi-Fi nao vai funcionar"
    warn "Extrai-lo de /persist do device. Veja docs/."
fi

# Keepalive do link USB: ping no host (10.42.0.1) a cada 60s.
# Sem trafego o cdc_ether/dwc3 ocasionalmente reseta a iface no host
# (a iface re-enumera, perde IP). Com ping leve continuo o link aguenta
# indefinidamente (testado 150s a 5s, 60s continuo, zero drops).
msg "instalando usb-keepalive.timer..."
cat > "$MNT/etc/systemd/system/usb-keepalive.service" <<'EOF'
[Unit]
Description=Ping no host (10.42.0.1) pra manter o link USB ativo
After=systemd-networkd.service
Wants=systemd-networkd.service

[Service]
Type=oneshot
ExecStart=/usr/bin/ping -c 1 -W 1 10.42.0.1
EOF
cat > "$MNT/etc/systemd/system/usb-keepalive.timer" <<'EOF'
[Unit]
Description=Dispara usb-keepalive a cada 60s

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF
mkdir -p "$MNT/etc/systemd/system/timers.target.wants"
ln -sf /etc/systemd/system/usb-keepalive.timer \
    "$MNT/etc/systemd/system/timers.target.wants/usb-keepalive.timer"

# Overlays: common/ aplica nos dois flavors; $FLAVOR/ aplica so no escolhido.
# cp -a preserva symlinks (incluindo os de multi-user.target.wants).
for ov in common "$FLAVOR"; do
    OVERLAY="$REPO/rootfs-overlay/$ov"
    if [ -d "$OVERLAY" ]; then
        msg "aplicando overlay $ov ($OVERLAY)..."
        cp -a "$OVERLAY"/. "$MNT"/
    fi
done

# Desktop: weston.service substitui getty@tty1. Remove o drop-in de
# autologin pra evitar conflito (weston.service tem Conflicts=getty@tty1).
if [ "$FLAVOR" = "desktop" ]; then
    rm -rf "$MNT/etc/systemd/system/getty@tty1.service.d"
fi

sync
umount "$MNT"
rmdir "$MNT"

msg "OK: $ROOTFS_IMG ($(du -h "$ROOTFS_IMG" | cut -f1)) [FLAVOR=$FLAVOR]"
msg "Login default Arch ARM: root/root  ou  alarm/alarm"
