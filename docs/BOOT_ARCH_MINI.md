# Bootar o Arch Mini (sanders) — runbook correto

Procedimento **validado em 2026-06-14** para subir o Arch na eMMC depois de um
reboot/cold boot. Hoje o boot **exige host (WSL) + intervenção física (Vol-Down)**
— a autonomia (cold boot sem host) está na seção final, ainda não fechada.

## Regra de ouro

> **O `fastboot boot <kernel>` do bootloader NATIVO da Motorola NÃO funciona** —
> o device fica **vibrando em loop** (a aboot da Motorola não digere nosso boot
> image com DTB anexado). O kernel só sobe quando bootado **pelo fastboot do
> lk2nd**. E o lk2nd só entra no fastboot dele se for bootado com **Vol-Down
> segurado** (senão ele tenta auto-bootar extlinux; como não existe extlinux
> ainda, ele cai de volta no fastboot da Motorola).

## Identidades USB (usbipd `2-4`)

| Estágio                    | VID:PID     | Nome no usbipd            |
|----------------------------|-------------|---------------------------|
| Fastboot nativo Motorola   | `22b8:2e80` | `Fastboot sanders S`      |
| Fastboot do lk2nd          | `18d1:d00d` | `Android` / `fastboot`    |
| Arch no ar (USB gadget)    | (CDC ECM)   | `CDC ECM ... (COM4)` / `sanders-proofoflife` |

## Passo a passo

### 0. Levar o device ao fastboot da Motorola
- Se estiver **travado/vibrando** (loop de um boot que falhou): segure **Power
  ~12s** para forçar reboot e, ao mesmo tempo, segure **Vol-Down** → cai no
  fastboot da Motorola (`22b8:2e80`).
- Confirmar no WSL: `fastboot devices` → `Motorola Fastboot Interface`.

### 1. Anexar ao WSL (usbipd)
```bash
usbipd.exe attach --wsl --busid 2-4
fastboot devices            # deve listar o device
```
- Se disser *"not shared"*: rodar **uma vez** num PowerShell **admin**:
  `usbipd bind --busid 2-4` (o bind persiste; depois disso, attach não pede mais
  admin).

### 2. Bootar o lk2nd — SEGURANDO Vol-Down
```bash
sudo fastboot boot build/out/lk2nd.img
```
- **Mantenha o Vol-Down pressionado** durante e depois deste comando, até o
  lk2nd aparecer como `18d1:d00d`. (Sem Vol-Down, ele volta pro fastboot da
  Motorola.)

### 3. Re-anexar o lk2nd e bootar o Arch
```bash
usbipd.exe attach --wsl --busid 2-4    # device re-enumerou como 18d1:d00d
# (pode soltar o Vol-Down agora — lk2nd já está no fastboot dele)
sudo fastboot boot build/out/boot-sanders.img
```

### 4. Esperar o boot e conectar
- ~60s: initramfs acha `LABEL=rootfs` (p54) → switch_root → Arch →
  `sanders-wcnss-recovery` → `wpa_supplicant@wlan0` → DHCP → sshd.
- O device enumera o USB gadget (proof-of-life). Conectar via Wi-Fi:
```bash
ssh -i ~/.ssh/id_ed25519 root@192.168.1.12   # DHCP; IP pode variar
```
- Saúde: `systemctl is-system-running` (= `running`, 0 failed),
  serviços `nginx sshd sanders-wcnss-recovery wpa_supplicant@wlan0
  sanders-demo-backend cloudflared` todos `active`.

---

## Energia / 24-7

- `/sys/class/power_supply/` está **vazio**: o mainline não tem driver de
  carga/bateria. O device roda na tomada pelo **power-path do PMIC** (alimenta o
  SoC direto da entrada VBUS), mas **não há leitura de bateria nem garantia de
  carga**.
- Trocar do cabo do PC para o carregador de parede: fazer **rápido** (o gap sem
  VBUS pode desligar se a bateria estiver baixa). Carregador real (≥1A).
- **Enquanto não houver autonomia, qualquer reboot/queda de energia exige
  repetir o ritual acima com cabo USB.** Manter em tomada estável.

---

## Autonomia (cold boot sem host) — Phase 3, NÃO testada

Objetivo: `reboot` pelo terminal volta sozinho ao Arch, sem cabo nem Vol-Down.

O lk2nd **já auto-boota extlinux** quando ele existe (é por isso que sem
extlinux ele cai no fastboot). Faltam **duas** peças:

1. **`/extlinux/extlinux.conf` no rootfs** (p54) apontando para o kernel/DTB/
   initramfs reais de `/boot`. ⚠️ O template `rootfs-overlay/mini/extlinux/
   extlinux.conf` referencia `/boot/msm8953-motorola-sanders.dtb` e
   `/boot/initramfs.cpio.gz`, que **não existem** com esses nomes no device
   (lá tem `/boot/Image.gz`, `/boot/dtbs/...`, `/boot/initramfs-linux.img`) —
   corrigir os caminhos antes.
2. **lk2nd persistente na partição `lk2nd`** (512 KiB, `0x80000`), para rodar
   no cold boot sem precisarmos bootá-lo. Esta é a **única flash permitida** no
   sanders (`fastboot flash boot` é rejeitado por AVB; `flash lk2nd` é o caminho).

**Premissa ainda não verificada:** que a aboot stock da Motorola faça
chainload da partição `lk2nd`. Cadeia esperada:
`Motorola aboot → lk2nd (partição) → scan /extlinux/extlinux.conf → /boot →
switch_root → Arch`.

### Plano de teste (reversível — exige go-ahead explícito)
```bash
# backup do que existe na partição lk2nd (do fastboot do lk2nd):
fastboot fetch lk2nd build/out/lk2nd-orig-backup.img
# garantir /extlinux/extlinux.conf correto no rootfs (passo 1 acima)
# flash (ÚNICA permitida):
fastboot flash lk2nd build/out/lk2nd.img
# reboot SEM host conectado e observar se volta sozinho
```
Rollback: `fastboot flash lk2nd build/out/lk2nd-orig-backup.img`. A partição
`boot` nunca é tocada → fastboot da Motorola continua acessível pela combinação
de teclas; o device não pode ser brickado por este passo.
