# Hardware status

Última atualização: 2026-05-19.

## Visão geral

| Componente | Status | Notas |
|---|---|---|
| Kernel mainline boot | ✅ | Linux master (~v6.x), defconfig + fragment |
| eMMC | ✅ | `mmcblk0` 29.1 GiB, GPT, todas 54 partições visíveis |
| ext4 rootfs | ✅ | Montado via `blkid -L rootfs` (sem udev no initramfs) |
| systemd / userspace Arch ARM | ✅ | Boot até `archlinuxarm login:` |
| Framebuffer console | ✅ | `simple-framebuffer` do bootloader; rotated portrait |
| USB CDC ACM (console serial via cabo USB) | ❌ | `dwc3: failed to initialize core` |
| Touchscreen Synaptics RMI4 | ❌ | DTS já descreve; drivers RMI4 desativados no defconfig |
| Wi-Fi (QCA) | ❌ | Sem firmware, sem driver builtin |
| Bluetooth | ❌ | — |
| Display "de verdade" (painel Tianma NT35596 ou DJN ILI7807D) | ❌ | Driver mainline inexistente, hoje só simple-framebuffer |
| Áudio | ❌ | — |
| Modem (telefonia/dados) | ❌ | — |
| Câmera | ❌ | — |
| Sensores (acelerômetro, giro, prox, luz) | ❌ | — |
| GPU (Adreno 506) | ❌ | freedreno provavelmente funcionaria com mais trabalho |

## Detalhes do que **não** funciona ainda

### USB DWC3 (alta prioridade)

Mensagem do kernel:
```
platform 7000000.usb: deferred probe pending: dwc3: failed to initialize core
gcc-msm8953 1000000.clock-controller: sync_state() pending due to 79000.phy
gcc-msm8953 1000000.clock-controller: sync_state() pending due to e3000.rng
```

**Impacto:** sem CDC ACM, não conseguimos console interativo via cabo USB.
Sem touchscreen e sem teclado, isso bloqueia uso real.

**Hipóteses:**
- Clock ou regulator do `hsusb_phy` (PHY USB 2.0) não está sendo
  habilitado corretamente. O DTS atual replica o do `potter.dts` —
  precisa investigar se há diferença real entre `sanders` e `potter`
  no clocking de USB.
- Driver `dwc3-qcom` mainline pode estar exigindo propriedades que
  estão presentes na DTSI do msm8953 (verificado em `msm8953.dtsi`
  upstream), mas pode haver patches específicos do potter/sanders
  ainda upstream do mainline.

**Próximos passos:**
1. Comparar com `linux-postmarketos-qcom-msm8953` (se existir em pmaports).
2. Investigar mensagens completas via `pstore`/`ramoops` — o DTS já
   reserva `ramoops@ef000000`. Após panic/reboot, ler o log gravado.
3. Tentar `dr_mode = "otg"` em vez de `"peripheral"`.
4. Habilitar `CONFIG_USB_DWC3_VERBOSE=y` e ler dmesg completo.

### Touchscreen Synaptics RMI4

DTS atual já descreve `touchscreen@20` em `&i2c_3` (copiado do potter).
Falta apenas habilitar o driver:

```
CONFIG_RMI4_CORE=y
CONFIG_RMI4_I2C=y
CONFIG_RMI4_F11=y     # 2D pointing
CONFIG_RMI4_F30=y     # GPIO/LED (opcional)
```

Após habilitar, espera-se `/dev/input/eventN` mapeando para o touch.
Para teclado virtual seria necessário stack gráfica (Weston/Phosh/Sxmo),
que é outro nível de trabalho.

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
