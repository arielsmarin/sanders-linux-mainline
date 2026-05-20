# Hardware status

Última atualização: 2026-05-20.

## Visão geral

| Componente | Status | Notas |
|---|---|---|
| Kernel mainline boot | ✅ | Linux master (~v6.x), defconfig + fragment |
| eMMC | ✅ | `mmcblk0` 29.1 GiB, GPT, todas 54 partições visíveis |
| ext4 rootfs | ✅ | Montado via `blkid -L rootfs` (sem udev no initramfs) |
| systemd / userspace Arch ARM | ✅ | Boot até shell root (autologin no tty1 via drop-in `getty@tty1.service.d/autologin.conf`) |
| Framebuffer console | ✅ | `simple-framebuffer` do bootloader; rotated portrait |
| USB CDC ACM (console serial via cabo USB) | ✅ | Autologin root via `serial-getty@ttyGS0` do systemd. Estável após drop-in com `TTYReset/Hangup/VTDisallocate=no` + udev no-autosuspend. |
| USB CDC ECM (rede sobre cabo USB) | ✅ | `usb0` no phone @ 10.42.0.2/24, host @ 10.42.0.1/24, SSH `root@10.42.0.2` OK. NAT no host via `scripts/08-host-net.sh`. **Ordem das functions no initramfs importa**: ECM tem que ser registrada *antes* da ACM (kernel 7.1.0-rc4 faz TX stuck do ECM se ACM vier primeiro — qdisc enche e tx_packets fica em 0). Veja TROUBLESHOOTING #13. |
| Touchscreen Focaltech FT5436 | ✅ | Reportando eventos ABS/KEY/SYN limpos. Probe via patch (driver mainline `edt-ft5x06` precisa skip-identify). |
| Wi-Fi (QCA WCN3680B / pronto) | ⚠️ | Hardware OK (scan funciona). Auth+assoc completam. 4-way handshake WPA2 falha com `hal_config_bss MEM_FAIL=5` (limitacao conhecida wcn36xx em msm8953). Veja secao "Wi-Fi WCN3680B" abaixo. |
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

### Wi-Fi WCN3680B (parcial)

O msm8953 usa o chip QCA WCN3680B (pronto) integrado, controlado pelo
driver mainline `wcn36xx` via `qcom-wcnss-pil` (Peripheral Image Loader).

**O que ja foi feito:**

1. DTS (`dts/msm8953-motorola-sanders.dts`): habilitado `&wcnss` com
   `vddpx-supply = &pm8953_l5` e `&wcnss_iris` com `compatible = "qcom,wcn3680"`
   + supplies (`vddxo` -> `pm8953_l7`, `vddrfa` -> `pm8953_l19`,
   `vddpa` -> `pm8953_l9`, `vdddig` -> `pm8953_l5`). Voltagens
   extraidas do DTB stock Android.
2. Kernel (`kernel/sanders.config.fragment`): toda a cascata builtin —
   `CFG80211`, `MAC80211`, `WCN36XX`, `QCOM_WCNSS_PIL`, `QCOM_WCNSS_CTRL`,
   `QCOM_SYSMON`, `QRTR`, `RPMSG_QCOM_*`, `RFKILL`. Cada um precisa ser
   `=y` por causa de `depends on FOO || FOO=n` em cascata.
3. Firmware:
   - Pronto: `wcnss.mdt` + `wcnss.b0X` (~4MB) extraidos do
     `NON-HLOS.bin` do flashfile stock 7.1.1. Vao em
     `/lib/firmware/wcnss.*` E **TAMBEM** no initramfs (em
     `/lib/firmware/`) porque o probe acontece antes do switch_root.
   - NV cal: `WCNSS_qcom_wlan_nv.bin` baixado do repo LineageOS
     `alissonlauffer/proprietary_vendor_motorola_sanders` (branch `ten`,
     md5 `7784365e9db784737ed3eb613d0c705e`). **Nao** vem no flashfile
     do device e o `/persist/wifi` esta vazio (Android nunca foi inicializado
     no device modificado). O `WCNSS_cfg.dat` em `/vendor/firmware/wlan/prima/`
     do device tem outro formato (header `01 0c 03 0b` vs `ff ff ff ff be ba fe ca`
     do wlan_nv real).

**O que funciona:**
- Pronto firmware carrega no boot: `WCN v2.0 RadioPhy vIris_TSMC_4.0 with 48MHz XO`
- `wcn36xx: firmware API 1.5.1.2, 41 stations, 2 bssids`
- `wlan0` (mac `02:00:7f:53:68:74`) + `phy0` criados
- Scan funcional, vendo redes 2.4G e 5G (~-22dBm pra AP proximo)
- Auth + associate completam contra AP WPA2

**O que NAO funciona ainda:**
- **4-way handshake WPA2 falha**: ap envia EAPOL frames mas chip nao
  consegue configurar BSS/STA. dmesg mostra:
  ```
  wcn36xx: WARNING hal config bss response failure: 5
  wcn36xx: ERROR hal_config_bss response failed err=-5
  wcn36xx: WARNING hal config sta response failure: 5
  wcn36xx: ERROR hal_config_sta response failed err=-5
  wlan0: associated
  wlan0: deauthenticated (Reason: 15=4WAY_HANDSHAKE_TIMEOUT)
  ```
  `err=5` = `WCN36XX_FW_MSG_RESULT_MEM_FAIL` (chip diz que falta memoria
  para o BSS/STA context). Reproduz com WPA, WPA2, 2.4G e 5G, com
  diferentes ciphers (CCMP/TKIP). NAO se resolve com mudancas de config.
- Suspeitos:
  - Pronto firmware do stock 7.1.1 + NV cal do Lineage 10 podem ter
    incompatibilidade de versao.
  - Pode haver bug no driver wcn36xx que precisa patch (postmarketOS
    community tem patches nao-mainline para msm8953/wcn3680b).
  - DT esta com warning `supply vddmx not found, using dummy regulator` —
    pode estar relacionado.
- Proximos passos: tentar firmware do LineageOS 18.1+/pmOS, ou patches do
  pmOS-linux-msm8953 (`linux-postmarketos-qcom-msm8953`).

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
