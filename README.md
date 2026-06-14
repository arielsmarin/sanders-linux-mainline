# sanders-linux-mainline

**Linux kernel mainline + Arch Linux ARM bootando no Motorola Moto G5s Plus (codename `sanders`).**

Este é, até onde sabemos, o **primeiro porte conhecido** do `sanders` para
o kernel Linux mainline upstream. Não há porte oficial em
[postmarketOS](https://postmarketos.org/),
[Mobian](https://mobian-project.org/) ou outras distros para mobile.

> ✅ **Estado: mini-servidor headless via Wi-Fi, no ar na internet.** Arch
> Linux ARM persistente na eMMC → **Wi-Fi nativo (WCN3680B) associando WPA2 +
> DHCP** → **SSH por chave via Wi-Fi** (`ssh -i ~/.ssh/id_ed25519 root@<ip>`)
> → **nginx + dashboard de status**, com HTTPS público **mesmo atrás de CGNAT**
> via Cloudflare Tunnel. Bluetooth (WCN3680B) também funcional. Pendências:
> storage (filebrowser) a configurar, boot standalone (extlinux), áudio, painel
> real.
> Veja [`docs/HARDWARE_STATUS.md`](docs/HARDWARE_STATUS.md) e
> [`docs/MINI_SERVER.md`](docs/MINI_SERVER.md).

| | |
|---|---|
| **Device** | Motorola Moto G5s Plus |
| **Codename** | `sanders` |
| **SoC** | Qualcomm Snapdragon 625 (`msm8953`) |
| **Bootloader** | [lk2nd](https://github.com/msm8916-mainline/lk2nd) (fork [playday3008](https://github.com/playday3008/lk2nd) — único com DTSI do sanders) |
| **Kernel** | Linux mainline (`master`, ~v6.x) |
| **Distro testada** | Arch Linux ARM aarch64 |

---

## Demo

![Foto da tela mostrando archlinuxarm login:](docs/screenshots/login.jpg)

(systemd subiu, getty ativo no `tty0`/framebuffer — embora ainda sem
teclado para digitar)

---

## TL;DR — como reproduzir

Pré-requisitos: Arch Linux x86_64 (ou adaptar pacotes), bootloader do
aparelho **desbloqueado** (`fastboot oem unlock`), cabo USB.

```bash
git clone https://github.com/<você>/sanders-linux-mainline.git
cd sanders-linux-mainline

./scripts/00-setup-host.sh      # instala toolchain aarch64/arm-none-eabi/android-tools
./scripts/01-build-lk2nd.sh     # ~3 min — bootloader 2º estágio
./scripts/02-build-kernel.sh    # ~15-30 min — clona linux mainline, aplica DTS, compila
./scripts/03-build-busybox.sh   # ~2 min — initramfs userspace
./scripts/04-build-initramfs.sh # <1 min — empacota cpio
sudo ./scripts/05-build-rootfs.sh                # headless (default): SSH/SAMBA/server, ~3 GiB
# OU:
sudo FLAVOR=desktop ./scripts/05-build-rootfs.sh # desktop: Weston + Xwayland + mesa, ~5 GiB
./scripts/06-build-boot.sh      # <1 min — Android boot.img (mesmo para os 2 flavors)

# Aparelho em fastboot mode:
./scripts/07-flash-and-boot.sh --flash    # ⚠️ APAGA /data do Android
```

Após ~60s na tela do aparelho: `archlinuxarm login:`.

Veja [`docs/STEP_BY_STEP.md`](docs/STEP_BY_STEP.md) para detalhes de cada etapa
e o que esperar.

---

## Por que isso é difícil

O `sanders` (Moto G5s Plus) era um vácuo no Linux mobile open source:

- **lk2nd:** existe, mas só no [fork playday3008](https://github.com/playday3008/lk2nd)
  (commit `c8b47cd`); upstream `msm8916-mainline/lk2nd` não tem o DTSI do
  sanders.
- **Kernel mainline:** tem `msm8953.dtsi` e `msm8953-motorola-potter.dts`
  (Moto G5 Plus, irmão direto), mas **não tinha sanders.dts**.
- **postmarketOS / Mobian:** sem porte.
- **Builds prontos de lk2nd não funcionam** — só compilando localmente.

Este repo resolve isso: contém o `msm8953-motorola-sanders.dts` portado a
partir do potter, o config fragment do kernel, o initramfs minimal e os
scripts que automatizam tudo.

---

## Layout do repositório

```
.
├── README.md                   # você está aqui
├── LICENSE                     # GPL-2.0
├── docs/
│   ├── STEP_BY_STEP.md         # cada etapa, o que faz e o que esperar
│   ├── HARDWARE_STATUS.md      # o que funciona e o que ainda não
│   ├── MINI_SERVER.md          # mini-servidor padrão (nginx + backend + dashboard)
│   ├── PIPELINE_STRATYCONFIG_CGNAT.md  # acesso remoto sob CGNAT (deployment próprio)
│   ├── DEPLOY_FINAL_ARCH_MINI.md  # deploy na eMMC + standalone
│   ├── LK2ND_SETUP.md          # bootloader (pré-requisito)
│   ├── TROUBLESHOOTING.md      # erros que encontramos e como resolvemos
│   └── screenshots/            # fotos do feito
├── dts/
│   └── msm8953-motorola-sanders.dts   # ★ o DTS portado
├── kernel/
│   └── sanders.config.fragment        # configs builtin necessárias
├── initramfs/
│   ├── init                           # script de init (busybox shell)
│   ├── busybox.config.fragment        # ajustes pro busybox build
│   ├── busybox-symlinks-bin.txt       # 46 symlinks em /bin
│   └── busybox-symlinks-sbin.txt      # 4 symlinks em /sbin
└── scripts/
    ├── lib.sh                  # vars + helpers
    ├── 00-setup-host.sh        # deps do host
    ├── 01-build-lk2nd.sh       # bootloader
    ├── 02-build-kernel.sh      # kernel + DTB
    ├── 03-build-busybox.sh
    ├── 04-build-initramfs.sh
    ├── 05-build-rootfs.sh      # Arch ARM ext4 image (precisa sudo)
    ├── 06-build-boot.sh        # Android boot.img
    └── 07-flash-and-boot.sh    # fastboot
```

Build artifacts vão para `build/` e `build/out/` (gitignored).

---

## O que funciona (e o que falta)

✅ **Funcional**
- Boot end-to-end do kernel mainline + boot do systemd
- **Arch Linux ARM persistente na eMMC** (rootfs na p54, ext4, resize para 24 GiB)
- **Wi-Fi nativo WCN3680B** — associação **WPA2 + DHCP + ping** funcionando.
  Root cause resolvido: o firmware Pronto 1.5.1.2 rejeitava `CONFIG_BSS/STA`
  com header VERSION1; fix = VERSION0 (patches `kernel/0005-*` e `0006-*`).
- **SSH por chave via Wi-Fi** — `ssh -i ~/.ssh/id_ed25519 root@<ip-wifi>`
  (DHCP). sshd + systemd-networkd + wpa_supplicant@wlan0 habilitados.
- **Mini-servidor HTTPS + storage** rodando e **público na internet**:
  `nginx` (web + reverse_proxy + dashboard de status) exposto via Cloudflare
  Tunnel (outbound — funciona **mesmo sob CGNAT**, sem IP público/port-forward).
  Setup genérico em [`docs/MINI_SERVER.md`](docs/MINI_SERVER.md); o deployment
  específico (domínio + acesso remoto) em
  [`docs/PIPELINE_STRATYCONFIG_CGNAT.md`](docs/PIPELINE_STRATYCONFIG_CGNAT.md).
- **Bluetooth WCN3680B** — `btqcomsmd` sobe limpo, `hci0` ativo (BR/EDR + BLE),
  MAC de fábrica restaurado de `/persist` (pareamento persiste entre boots).
- **Boot limpo** — `systemctl is-system-running` = `running` (0 unidades falhas).
- eMMC (29.1 GiB), framebuffer console, getty com **autologin root**.
- Touchscreen Focaltech FT5436 reportando eventos em `/dev/input/event1`.
- **USB CDC ACM** (`picocom /dev/ttyACM0`) + **rede USB CDC ECM** + NAT como
  canal de bring-up alternativo (`scripts/08-host-net.sh` no lado do PC).
- **Flavors de rootfs** via `FLAVOR=` no `05-build-rootfs.sh`: `headless`
  (default, server-style — usado no mini-servidor) e `desktop` (Phosh + Weston
  + Xwayland + mesa). Phosh/Squeekboard com touch e OpenGL via Xwayland +
  llvmpipe (~140 FPS) no flavor `desktop`.

🔜 **Em andamento**
- **Storage (filebrowser)** — binário instalado; falta diretório de dados,
  admin, unit systemd e expor atrás do nginx/túnel.
- **Boot standalone (cold boot sem host)** — falta `extlinux.conf` + kernel/dtb
  no `/boot` do rootfs + `fastboot flash lk2nd` (ver
  [`docs/DEPLOY_FINAL_ARCH_MINI.md`](docs/DEPLOY_FINAL_ARCH_MINI.md)).

❌ **Pendente**
- Display "de verdade" (painel Tianma NT35596 ou DJN ILI7807D — hoje só
  `simple-framebuffer` via SimpleDRM, sem aceleração GPU)
- Áudio, sensores, câmera, modem

Veja [`docs/HARDWARE_STATUS.md`](docs/HARDWARE_STATUS.md) para detalhes
e [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) para áreas onde ajuda é
bem-vinda.

---

## Contribuindo

PRs e issues são MUITO bem-vindos. Os próximos passos com maior valor:

1. **Boot standalone (extlinux)** — cold boot sem host: `extlinux.conf` +
   kernel/dtb/initramfs no `/boot` do rootfs + `fastboot flash lk2nd`.
2. **Storage (filebrowser)** — concluir a UI web de arquivos atrás do túnel.
3. **Upstream dos patches wcn36xx** (`0005`/`0006`) — fix do WCN3680.
4. **Adicionar driver do painel Tianma NT35596** — display real e brilho.

Veja [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).

---

## Licença

GPL-2.0 (compatível com Linux kernel). Veja [`LICENSE`](LICENSE).

O DTS deriva de `msm8953-motorola-potter.dts` (BSD-3-Clause, autoria
Sireesh Kodali); o cabeçalho está preservado. Scripts e docs próprios
deste repo são GPL-2.0.

---

## Créditos

- **lk2nd**: msm8916-mainline contributors + fork de
  [@playday3008](https://github.com/playday3008) (DTSI do sanders).
- **Linux msm8953 base**: postmarketOS / msm8916-mainline community,
  Sireesh Kodali (potter.dts).
- **Este port**: desenvolvido em 2026-05-19. Veja
  `docs/STEP_BY_STEP.md` para o histórico de descobertas (por que
  builds pré-compilados não funcionam, por que `fastboot flash boot` é
  rejeitado, por que `qcom,board-id` precisa de 6 entradas, etc.).
