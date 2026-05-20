# Hardware status

Última atualização: 2026-05-19.

## Visão geral

| Componente | Status | Notas |
|---|---|---|
| Kernel mainline boot | ✅ | Linux master (~v6.x), defconfig + fragment |
| eMMC | ✅ | `mmcblk0` 29.1 GiB, GPT, todas 54 partições visíveis |
| ext4 rootfs | ✅ | Montado via `blkid -L rootfs` (sem udev no initramfs) |
| systemd / userspace Arch ARM | ✅ | Boot até shell root (autologin no tty1 via drop-in `getty@tty1.service.d/autologin.conf`) |
| Framebuffer console | ✅ | `simple-framebuffer` do bootloader; rotated portrait |
| USB CDC ACM (console serial via cabo USB) | ✅ | Autologin root via `serial-getty@ttyGS0` do systemd. Estável após drop-in com `TTYReset/Hangup/VTDisallocate=no` + udev no-autosuspend. |
| Touchscreen Focaltech FT5436 | ✅ | Reportando eventos ABS/KEY/SYN limpos. Probe via patch (driver mainline `edt-ft5x06` precisa skip-identify). |
| Wi-Fi (QCA) | ❌ | Sem firmware, sem driver builtin |
| Bluetooth | ❌ | — |
| Display "de verdade" (painel Tianma NT35596 ou DJN ILI7807D) | ❌ | Driver mainline inexistente, hoje só simple-framebuffer |
| Áudio | ❌ | — |
| Modem (telefonia/dados) | ❌ | — |
| Câmera | ❌ | — |
| Sensores (acelerômetro, giro, prox, luz) | ❌ | — |
| GPU (Adreno 506) | ❌ | freedreno provavelmente funcionaria com mais trabalho |

## Detalhes do que **não** funciona ainda

### USB DWC3 / CDC ACM — ✅ FUNCIONANDO

**Resolvido em 2026-05-19.**

Sintoma original: `dwc3: failed to initialize core` + `platform 7000000.usb:
deferred probe pending`.

Causa raíz descoberta via debug no initramfs (cat
`/sys/kernel/debug/devices_deferred`):

```
7000000.usb     platform: supplier 79000.phy not ready
```

O `dwc3` não estava falhando — estava **deferred** esperando o supplier
`79000.phy` (o USB 2.0 PHY do msm8953). O PHY nunca probava porque
`CONFIG_PHY_QCOM_QUSB2=m` (módulo no defconfig), e nosso initramfs minimal
não tem `modprobe`. Sem o driver carregado, o nó do DTS ficava órfão.

**Fix:** `CONFIG_PHY_QCOM_QUSB2=y` no `kernel/sanders.config.fragment`.

Resultado: após boot, `/sys/class/udc/7000000.usb` aparece, o initramfs
configura CDC ACM via configfs, e o host vê `/dev/ttyACM0`. Login Arch via
`picocom -b 115200 /dev/ttyACM0` (precisa apertar Enter algumas vezes pra
acordar o getty).

**Estabilidade:** resolvida em 2026-05-19 com três mudanças combinadas:

1. **Initramfs não spawna mais shell em `/dev/ttyGS0`** quando vai dar
   switch_root — o shell ficava órfão depois do `exec switch_root` e
   brigava com o `serial-getty@ttyGS0` do systemd pelo tty.
2. **`serial-getty@ttyGS0.service` habilitado no rootfs** com drop-in:
   - `--autologin root --keep-baud 115200,57600,38400,9600`
   - `TTYReset=no`, `TTYVHangup=no`, `TTYVTDisallocate=no` (CDC ACM não
     tem flow control de hardware; reset/hangup do getty deixava a
     sessão num estado ruim).
3. **Udev rule desligando USB autosuspend** (`power/control=on`) no
   gadget — sem isso o controller suspendia com a sessão ACM ativa.

Bônus: `setsid` adicionado aos symlinks busybox do initramfs (o init
chamava `/bin/setsid` mas não existia).

### Touchscreen Focaltech FT5436 — ✅ FUNCIONANDO

Diferente do irmão `potter` (Moto G5 Plus, Synaptics RMI4 @ 0x20), o
`sanders` (G5s Plus) usa **Focaltech FT5436 @ 0x38** com:
- Bus: `i2c@78b7000` (= `i2c_3` no mainline)
- IRQ: `&tlmm 65 IRQ_TYPE_EDGE_FALLING`
- Reset: GPIO 64 (fixado HIGH via `gpio-hog`)
- VDD: `pm8953_l10` @ 2.85V (`regulator-always-on`)
- VCC_I2C: `pm8953_l5` @ 1.8V
- I2C clock: 400kHz (sem DMA)

Driver: `edt-ft5x06` mainline (compatible `focaltech,ft5426`), **com patch
necessário** porque o FT5436 não expõe o registro `0xBB` que o
`edt_ft5x06_ts_identify()` lê — sem o patch o probe falha com `-110`
(ETIMEDOUT). Patch: `kernel/0001-edt-ft5x06-skip-identify-for-ft5436.patch`.

Após boot, aparece `/dev/input/event1` reportando `ABS_MT_POSITION_X/Y`
(multi-touch protocol B) + `BTN_TOUCH` + `SYN_REPORT`. Confirmado com
2659 eventos / 10s de toque (ABS=2099 KEY=24 SYN=536).

Descoberta-chave: o **endereço, chip e reguladores corretos foram
extraídos do DTB Android stock** (`SANDERS_RETAIL_7.1.1...` boot.img →
QCDT v3 LZ4-compressed → dtb individual → procurar `touch`). Sem isso,
seguíamos chutando "deve ser igual ao potter".

Para teclado virtual seria necessário stack gráfica (Weston/Phosh/Sxmo),
que é outro nível de trabalho — mas o touch em si está pronto.

### Wi-Fi

O msm8953 usa o chip QCA `wcnss`. Para funcionar:

1. Habilitar driver mainline: `CONFIG_WCN36XX=m`, `CONFIG_MAC80211=y`,
   `CONFIG_QCOM_WCNSS_CTRL=m`.
2. Firmware: copiar `wlan/prima/WCNSS_qcom_wlan_nv.bin` e
   `WCNSS_qcom_cfg.ini` de um Android stock dump para
   `/lib/firmware/wlan/prima/` no rootfs Arch.
3. Habilitar nodes no DTS — provavelmente requer também regulators e
   `smd-rpm` ativos.

### Painel de display

Nenhum driver mainline para Tianma NT35596 ou DJN ILI7807D específico
do sanders. Opções:

- Verificar drivers similares (`drivers/gpu/drm/panel/`) — pode haver
  algo compatível.
- Escrever um driver (sub-projeto significativo).
- Continuar usando simple-framebuffer (o que temos hoje).

## Métricas atuais

- Tamanho do `boot-sanders.img`: ~16 MiB (cabe na partição `boot` de
  15.5 MiB? **Não** — por isso usamos `fastboot boot` em vez de
  `fastboot flash boot`, que é bloqueado pelo bootloader Motorola
  mesmo desbloqueado).
- Tempo de cold boot (lk2nd → login prompt): ~30s.
- RAM usada por systemd em idle: não medido (sem console).
- Temperatura do device: aquece levemente (CPU sem governor adequado,
  provavelmente).
