# Sanders Linux Mainline — Contexto para Claude/Codex

## Objetivo
Mini-servidor Wi-Fi: Motorola XT1802 (sanders, MSM8953/Snapdragon 625) rodando Arch Linux ARM.
Flow: **Wi-Fi → SSH → gerenciar remotamente**.

## ✅ DEPLOY COMPLETO — 2026-06-14 (SSH via Wi-Fi funcionando)

Arch Linux ARM na eMMC (p54) com **SSH por chave**:
`ssh -i ~/.ssh/id_ed25519 root@<IP-Wi-Fi>` (DHCP; ex. 192.168.1.12). root pw = root/root.
**Device SEM TELA** → navegação só por enumeração USB (nunca "olhe a tela").

### Procedimento de flash + boot (o que FUNCIONOU)
1. Device → fastboot Motorola (`22b8:2e80`). **Motorola RECUSA `flash`** ("flash
   permission denied") → flash só pelo **fastboot do lk2nd**.
2. `python.exe C:\Temp\lk2nd_probe.py` boota lk2nd (libusb Steam). **Segurar Vol-Down**
   contínuo até o lk2nd subir → fastboot do lk2nd (`18d1:d00d`, libusbK). Às cegas; ~2 tentativas.
3. `usbipd.exe attach --wsl --busid 2-4` (já "Shared" → sem admin).
4. **Flash pelo fastboot nativo do WSL** (lk2nd permite; WSL c/ 7.8GB RAM não OOMa; auto-sparse):
   `sudo fastboot flash userdata build/rootfs-arch-headless.img` (~196s).
5. `sudo fastboot boot build/out/boot-sanders.img` → initramfs acha `LABEL=rootfs` na p54 → switch_root → Arch.

### Acesso serial — CANAL CONFIÁVEL = COM4 do Windows COM DTR ASSERIDO
- USB ECM (rede usb0) é **INVIÁVEL**: WSL vhci dropa (`urb->status -104`, sem carrier);
  Windows não tem driver CDC-ECM. **Não usar nc|dd pela rede USB.**
- Serial WSL `/dev/ttyACM0` (usbip) instável p/ interativo.
- ✅ Confiável: **COM4 nativa do Windows com DTR/RTS asseridos** (u_serial só TX com DTR).
  Ferramentas novas (boas): `C:\Temp\win_serial_run.py` (loga root/root, roda comandos),
  `C:\Temp\win_wifi_setup.py` (config Wi-Fi: PSK PBKDF2 calculado LOCAL, senha nunca sai do PC),
  `C:\Temp\flash_userdata.py` (sparse via pyusb — só serve no fastboot do lk2nd).
  Detach do WSL antes (`usbipd.exe detach --busid 2-4`) p/ liberar a COM4. 1 processo por vez.

### WCNSS firmware — recovery OBRIGATÓRIO p/ wlan0
- A firmware baked `/lib/firmware/wcnss.*` está **ERRADA** (md5 9e6d59) → boot dá `error -22
  initializing firmware wcnss.mdt`, sem wlan0. Correta = a do **modem** `/dev/mmcblk0p19`
  (`/image/wcnss.*`, md5 e40494). Recovery: montar modem ro, copiar p/ /lib/firmware,
  `echo stop;echo start > /sys/class/remoteproc/remoteproc0/state`.
- Serviço **`sanders-wcnss-recovery.service`** (enabled) faz isso no boot antes do wpa.
- TODO build: corrigir a firmware baked no `05-build-rootfs.sh` (usar a do modem).

### Estado persistido (sobrevive reboot)
- Enabled: sshd, systemd-networkd, wpa_supplicant@wlan0, sanders-wcnss-recovery.
- `/root/.ssh/authorized_keys` = chave ed25519 do host. `20-wlan0.network` (DHCP).
  `wpa_supplicant-wlan0.conf` (PSK hasheado). fs já em 24G (resize feito).
- Falhas benignas (status "degraded", cosmético): usb-keepalive, sanders-bt-mac, networkd-wait-online.

### 🔜 Falta p/ STANDALONE (cold boot sem host) — Phase 3
- **Sem `/boot/extlinux/`** → lk2nd não auto-boota; todo cold boot exige lk2nd→`fastboot boot`
  manual. Para autonomia: criar `extlinux.conf` + kernel/dtb/initramfs em /boot do rootfs e
  `fastboot flash lk2nd lk2nd.img` (única flash permitida; backup `fetch` antes — ver
  `docs/DEPLOY_FINAL_ARCH_MINI.md`).

---

## ✅ MINI-SERVIDOR HTTPS + storage — no ar (2026-06-14)

Objetivo: transformar o sanders em mini-servidor web HTTPS + storage. Provedor
sob **CGNAT** (sem IP público) → **Cloudflare Tunnel** (outbound, fura CGNAT).
Stack: **nginx** (web + reverse_proxy) + **cloudflared** (túnel) + **filebrowser**
(storage, config pendente). `caddy` instalado mas ocioso (TLS termina na borda CF,
basta UM servidor HTTP local). Detalhes completos: `docs/MINI_SERVER.md`.

- **Público:** `https://cloudflared.stratyconfig.com` — `/` = página estática
  (`/srv/www/sanders/index.html`), `/api/` = backend demo Python (:3000).
- Serviços enabled (sobrevivem reboot): `nginx`, `sanders-demo-backend`,
  `cloudflared` (criado por `cloudflared service install <TOKEN>` — fluxo dashboard;
  hostname/rota ficam no painel Cloudflare, não em config.yml local).
- Túnel via DASHBOARD (token), não CLI. **Token é credencial** — nunca em log.
- Boot agora limpo: `is-system-running` = running, 0 failed (limpeza de
  usb-keepalive.timer, wait-online só-wlan0, bt-mac não-fatal).

### Gotchas resolvidos no bring-up do servidor
- **Egress IPv4 morto:** `10-usb0.network` tinha `Gateway=`+rota default; com usb0
  `linkdown` o kernel jogava toda saída no buraco (não ignora rota linkdown por
  padrão). Removido Gateway/[Route] do usb0 → default só via wlan0. Sem isso pacman
  não baixa nada. (backup `.bak` no device)
- **Posse rootfs:** `/ /etc /usr` vinham `owned by alarm` → quebrava hooks do pacman.
  Corrigido p/ root:root. TODO build: extrair rootfs como root no 05-build-rootfs.
- Python não vinha no rootfs → instalado `python`.

### 🔜 Próximo: filebrowser (storage)
Binário em `/usr/local/bin/filebrowser` (v2.63.15). Falta: diretório de dados,
admin, unit systemd, expor atrás do nginx (path `/files/` ou subdomínio próprio
no túnel, ex. `files.stratyconfig.com`).

---

## Checkpoint mais recente — 2026-06-08

### ✅ Wi-Fi FUNCIONANDO

**Root cause resolvido:** o driver mainline usava `INIT_HAL_MSG_V1` (HAL
message VERSION1) nos dois únicos comandos `CONFIG_BSS_V1` e `CONFIG_STA_V1`
quando `rf_id == RF_IRIS_WCN3680`.  O firmware Pronto 1.5.1.2 rejeita essas
mensagens com VERSION1, retornando `MEM_FAIL=5`.  Todos os outros comandos HAL
já usavam VERSION0 e funcionavam.  O caminho WCN3620/potter para as mesmas
funções usava VERSION0 + `len -= DIFF_NOVHT` — que funciona.

Segundo fix: mainline enviava JOIN antes de CONFIG_BSS.  Os drivers vendor
(prima/qcacld) enviam CONFIG_BSS primeiro.  Invertendo a ordem (CONFIG_BSS → JOIN)
o firmware aloca o contexto BSS antes de sintonizar o canal.

**Resultado validado no device (2026-06-08):**
```
wlan0: associated
DHCP: 192.168.x.x/24
ping 8.8.8.8: 27ms RTT, 0% loss
```

**Patches gerados (upstream-ready):**
- `kernel/0005-wcn36xx-fix-hal-msg-version-for-CONFIG-BSS-STA-on-WCN3680.patch`
- `kernel/0006-wcn36xx-send-CONFIG-BSS-before-JOIN.patch`

**Código limpo:** todo o código EXPERIMENTAL/NOT-FINAL (HT/VHT/rate forcing,
bssid_index=0, AMPDU reject) foi removido de `smd.c` e `main.c`. O kernel
atual aplica apenas os fixes reais.

**Próximo passo:** rebuild do kernel e reteste com código limpo (HT/VHT
re-habilitados) para confirmar que o fix de VERSION0 é suficiente sem as
restrições experimentais de capabilities.

---

## Estado atual (2026-06-08)

### O que funciona
- lk2nd flashado; Arch Linux ARM bootando via `fastboot boot`
- Shell serial: `sudo picocom -b 115200 /dev/ttyACM0`
- `wlan0` sobe após recovery de firmware (ver seção abaixo)
- Scan 2.4 GHz e 5 GHz funcionam
- **Wi-Fi associação + DHCP + ping funcionando** ✅

### Fluxo de teste
```sh
# (No WSL, após usbipd attach)
sudo fastboot boot build/out/boot-sanders.img
# (Após re-attach usbipd)
sudo python3 scripts/serial_test.py
```

O script `serial_test.py` está estável: firmware recovery automático, espera
até 90s pelo NV download, `debug_mask=0x100`, wpa_supplicant, detecção de
resultado em 30s.

---

## Estrutura do projeto

```
~/git/sanders-linux-mainline/
├── build/
│   ├── linux/                    # kernel tree (git clone do linux + patches aplicados)
│   │   └── drivers/net/wireless/ath/wcn36xx/
│   │       ├── smd.c             # MODIFICADO: VHT fix linha 1719 + debug lines
│   │       └── ...
│   └── out/
│       ├── boot-sanders.img      # kernel+DTB+initramfs, pronto para fastboot boot
│       └── lk2nd.img             # bootloader (flashado)
├── dts/
│   └── msm8953-motorola-sanders.dts  # DTS fonte (wcnss_iris compatible = "qcom,wcn3680")
├── firmware/                     # gitignored — firmware wcnss (stock sanders do modem)
│   └── wlan/prima/WCNSS_qcom_wlan_nv.bin  # 31KB, correto
├── kernel/
│   ├── 0002-wcn36xx-fixes-for-wcn3680.patch
│   └── 0003-msm8953-fix-wcnss-reserved-mem-base-address.patch  # untracked
├── scripts/
│   ├── 02-build-kernel.sh        # rebuild kernel
│   ├── 04-build-initramfs.sh     # embute firmware/ no initramfs
│   └── 06-build-boot.sh          # cria boot-sanders.img
└── docs/
    └── HARDWARE_STATUS.md        # status detalhado do hardware
```

---

## Recovery de firmware (necessário a cada boot)

O initramfs causa -22 EINVAL na inicialização precoce (antes do systemd). Workaround manual:
```sh
mkdir -p /mnt/modem
mount -o ro /dev/disk/by-partlabel/modem /mnt/modem
cp -v /mnt/modem/image/wcnss.mdt /mnt/modem/image/wcnss.b* /lib/firmware/
echo stop  > /sys/class/remoteproc/remoteproc0/state 2>/dev/null; true
echo start > /sys/class/remoteproc/remoteproc0/state
sleep 5
```
Esperado: `remote processor is now up` + `WCNSS Version 1.5 1.2` + `wcn36xx: mac address: 02:00:ee:c0:68:14`

---

## Sequência de boot (WSL/Windows)

1. Device em fastboot (Vol- + Power)
2. PowerShell (admin): `usbipd attach --wsl --busid <busid>`
3. WSL: `sudo fastboot boot build/out/lk2nd.img`
4. PowerShell: re-attach usbipd (device re-enumera)
5. WSL: `sudo fastboot boot build/out/boot-sanders.img`
6. PowerShell: re-attach usbipd
7. WSL: `sudo picocom -b 115200 /dev/ttyACM0`
8. No shell Arch: recovery de firmware (acima)

---

## Debug mask corretos para wcn36xx (CONFIG_WCN36XX=y, built-in)
```
WCN36XX_DBG_DXE       = 0x001
WCN36XX_DBG_DXE_DUMP  = 0x002  ← estava sendo usado ERRONEAMENTE como "HAL debug"
WCN36XX_DBG_SMD       = 0x004
WCN36XX_DBG_SMD_DUMP  = 0x008  ← dump hex de cada mensagem HAL (verboso)
WCN36XX_DBG_HAL       = 0x100  ← CORRETO para ver debug lines de config_bss/sta
WCN36XX_DBG_MAC       = 0x400
```
Path: `/sys/module/wcn36xx/parameters/debug_mask`

**EVITAR 0xff** — causou crash do sistema kernel.

---

## Constraint de segurança (PERMANENTE)
- **NUNCA** colocar senha de Wi-Fi em qualquer comando, log ou relatório
- Apenas `fastboot boot` (NUNCA `fastboot flash` sem confirmação explícita do usuário)
- Todas as operações devem ser reversíveis
