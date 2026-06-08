# Step-by-step: do zero ao login prompt

Este documento detalha cada script numerado, o que ele faz, **quanto tempo
demora** e **o que esperar de output**. Use como guia quando algo falhar.

## Pré-requisitos

- Arch Linux x86_64 (ou outra distro com pacotes equivalentes — ver
  `00-setup-host.sh`)
- ~5 GiB livres em disco (kernel mainline + builds)
- Motorola Moto G5s Plus com bootloader **desbloqueado**
  - Verifique com `sudo fastboot getvar unlocked` → deve retornar `yes`
  - Se não, ver [`LK2ND_SETUP.md`](LK2ND_SETUP.md) primeiro
- Cabo USB tipo C/micro (depende da revisão do G5s Plus)
- ~1h de tempo total (a maior parte gasta compilando kernel)

## 00. Setup do host (~2 min)

```bash
./scripts/00-setup-host.sh
```

Instala via `pacman`: cross-toolchains aarch64 (kernel) e arm-none-eabi
(lk2nd), `android-tools` (fastboot/mkbootimg), `dtc`, e utilitários
(bsdtar, cpio, etc.).

## 01. Build do lk2nd (~3 min)

```bash
./scripts/01-build-lk2nd.sh
```

Clona o **fork `playday3008/lk2nd`** (commit `c8b47cd`) — único com o
`msm8953-motorola-sanders.dtsi`. Compila o target `lk2nd-msm8953`.

Saída: `build/out/lk2nd.img` (~360 KiB).

**Por que não pode usar o upstream nem builds prontos:** o upstream
`msm8916-mainline/lk2nd` não tem o DTSI do sanders. Builds pré-compilados
publicados também não funcionam neste device (testado). Mais detalhes em
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

## 02. Build do kernel mainline (~15-30 min)

```bash
./scripts/02-build-kernel.sh
```

Primeira execução: clona Linux mainline (shallow, branch `v7.1-rc4`,
~300 MiB).

A cada execução:
1. Copia `dts/msm8953-motorola-sanders.dts` para
   `arch/arm64/boot/dts/qcom/`.
2. Adiciona entrada no `Makefile` do diretório DTS.
3. Aplica automaticamente os patches `kernel/*.patch` em ordem. Patches em
   `kernel/experiments/` nao entram aqui; aplique manualmente quando quiser
   rodar um teste nao final.
4. Aplica o config fragment `kernel/sanders.config.fragment` sobre o
   arm64 `defconfig`.
5. Compila `Image.gz` (~15 MiB) e DTBs.

**Configs builtin essenciais** (no fragment):

- `FB_SIMPLE`, `FRAMEBUFFER_CONSOLE`, `LOGO` — texto na tela
- `USB_DWC3*`, `USB_CONFIGFS_ACM`, `U_SERIAL_CONSOLE` — gadget CDC ACM
  (built-in pq o initramfs precisa criar o gadget antes do rootfs estar
  acessível)

## 03. Build do busybox aarch64 estático (~2 min)

```bash
./scripts/03-build-busybox.sh
```

Baixa `busybox-1.36.1`, aplica `defconfig + STATIC=y + #CONFIG_TC is not set`
(o `tc.c` do busybox 1.36.1 quebra com headers Linux atuais), compila.

Saída: `build/busybox-1.36.1/busybox` (~2.1 MiB, ELF aarch64 static).

## 04. Build do initramfs (~5 s)

```bash
./scripts/04-build-initramfs.sh
```

Monta `build/initramfs-root/` com:
- `/bin/busybox` (binário aarch64 estático)
- 46 symlinks em `/bin/` (`sh`, `mount`, `blkid`, `cat`, `cut`, etc.)
- 4 symlinks em `/sbin/` (`switch_root`, `init`, `mount`, `umount`)
- `/init` — nosso script (ver `initramfs/init`)
- mountpoints vazios: `/proc`, `/sys`, `/dev`, `/run`, `/tmp`, `/new_root`,
  `/sys/kernel/config`

Compacta em `build/out/initramfs.cpio.gz` (~1.1 MiB).

Antes de compactar, valida e copia explicitamente os blobs WCNSS:
`wcnss.mdt`, `wcnss.b00`, `b01`, `b02`, `b04`, `b06`, `b09`, `b10`,
`b11`, `b12`.

### O que o `init` faz

1. Monta virtuais (`proc`, `sys`, `dev`, `run`, `tmp`, `configfs`).
2. **Aguarda até 20s** o UDC (USB controller) aparecer em `/sys/class/udc/`
   — o `dwc3-qcom` sofre probe deferral. **Hoje falha** (`failed to
   initialize core`).
3. Se UDC aparecer, configura USB gadget CDC ACM via configfs e
   tenta abrir shell em `/dev/ttyGS0` (console via cabo USB).
4. Procura rootfs em ordem:
   1. `blkid -L rootfs`
   2. iteração em `/dev/mmcblk0p*` procurando `LABEL=rootfs`
   3. fallback: maior partição ext4
5. `mount` e `switch_root /sbin/init`.
6. Se algum passo falhar, dropa shell de emergência no `tty0`.

## 05. Rootfs Arch Linux ARM (~3 min, precisa sudo)

```bash
sudo ./scripts/05-build-rootfs.sh
```

1. Baixa `ArchLinuxARM-aarch64-latest.tar.gz` (~700 MiB) — só na 1ª vez.
2. Cria imagem ext4 de 3 GiB com `LABEL=rootfs`.
3. Monta loop, extrai tarball preservando perms, adiciona `ttyMSM0` e
   `ttyGS0` em `/etc/securetty`.
4. Valida e instala os mesmos blobs WCNSS do initramfs em `/lib/firmware/`.

Saída: `build/rootfs-arch-headless.img` por default, ou
`build/rootfs-arch-desktop.img` com `FLAVOR=desktop`.

**Credenciais default Arch Linux ARM:** `root/root` e `alarm/alarm`.

## 06. Empacotamento boot.img (~5 s)

```bash
./scripts/06-build-boot.sh
```

1. Concatena `Image.gz + DTB` no estilo "appended-dtb" (esperado pelo
   lk2nd).
2. `mkbootimg` com offsets msm8953 Motorola padrão:
   - base `0x80000000`, kernel `0x8000`, ramdisk `0x1000000`,
     tags `0x100`, pagesize `2048`, header v0.
3. Cmdline: `console=tty0 console=ttyGS0 console=ttyMSM0,115200n8
   earlycon ignore_loglevel printk.time=1 printk.devkmsg=on panic=30`.

Saída: `build/out/boot-sanders.img` (~16 MiB).

## 07. Flash e boot

### Primeira vez (com flash do rootfs)

```bash
./scripts/07-flash-and-boot.sh --flash
```

⚠️ **APAGA o `/data` do Android.** O script pergunta antes.

Sequência:
1. Aparelho em fastboot (power-off, depois power + vol↓).
2. Script roda `fastboot boot lk2nd.img` → tela do lk2nd.
3. Script roda `fastboot flash userdata rootfs-arch.img` (~3 min,
   sparse 5 chunks).
4. Script roda `fastboot boot boot-sanders.img`.
5. Aguarda ~60s.

### Iterações seguintes

Já flashou rootfs uma vez? Não precisa flashar de novo:

```bash
./scripts/07-flash-and-boot.sh        # só carrega lk2nd + boot do kernel
```

### O que esperar na tela

1. **Logo Motorola** (resíduo do bootloader anterior, ~2-3s).
2. **Texto rolando rapidamente** — dmesg do kernel no framebuffer
   console. Visualmente: padrão de linhas pequenas inclinadas (display
   está em portrait, console renderiza em landscape).
3. **Linhas do init:** `[init] procurando rootfs...`, `[init.blkid]
   /dev/mmcblk0pNN: LABEL=...`, `[init] ROOT=/dev/mmcblk0p54`,
   `EXT4-fs ... mounted`, `[init] switch_root...`.
4. **systemd Arch:** texto rola mais devagar, várias linhas `[ OK ]
   Started ...`.
5. **`Welcome to Arch Linux ARM`**
6. **`archlinuxarm login:`** 🎉

Veja [`screenshots/`](screenshots/) para exemplos reais.

---

## Iteração rápida (após mudar kernel/DTS/init)

```bash
./scripts/02-build-kernel.sh         # se mudou DTS ou kernel config
./scripts/04-build-initramfs.sh      # se mudou init
./scripts/06-build-boot.sh           # sempre
./scripts/07-flash-and-boot.sh       # boot transitório, sem --flash
```

`fastboot boot` é **não-destrutivo** — só carrega na RAM. Você pode
iterar dezenas de vezes sem afetar a userdata flashada anteriormente.
