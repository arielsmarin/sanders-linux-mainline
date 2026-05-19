# Troubleshooting

Problemas encontrados durante o desenvolvimento, com causa e solução.
Refira-se a este doc quando algo travar.

## 1. `fastboot boot lk2nd.img` retorna OKAY, mas aparelho fica no logo Motorola

**Sintoma:** o lk2nd carrega e mostra sua tela. Em seguida, ao
`fastboot boot boot-sanders.img`, o aparelho mostra o logo Motorola e
fica parado indefinidamente.

**Causa:** o lk2nd faz **match estrito** entre o `qcom,msm-id` /
`qcom,board-id` do DTB anexado e o hardware real
(`platform_dt_absolute_match()` em
`platform/msm_shared/dev_tree.c:1498`). Se não bate, **rejeita o DTB
silenciosamente** — kernel nunca é chamado.

**Solução:** listar **todas as 6 variantes** do sanders em
`qcom,board-id` no DTS:

```dts
qcom,board-id = <0x4B 0x8100>,
                <0x4B 0x8200>,
                <0x4B 0x8300>,
                <0x4B 0x83B0>,
                <0x4B 0x8400>,
                <0x4C 0x8400>;
```

O lk2nd itera sobre os pares e seleciona o que bate com o
`lk2nd_dt_override` populado a partir do hardware real. Já está
aplicado no `dts/msm8953-motorola-sanders.dts` deste repo.

## 2. `fastboot flash boot ...` falha no sanders

**Sintoma:** `flash boot` retorna erro, mesmo com bootloader
desbloqueado.

**Causa:** o sanders bloqueia escrita na partição `boot` por
verificação adicional (AVB / Motorola signing) que `unlock` sozinho
não desativa.

**Solução:** use `fastboot boot` (transitório, em RAM) em vez de
`flash boot`. Outras partições (`userdata`, `system`, etc.) aceitam
flash normalmente.

> Não testado, mas provavelmente possível: gravar permanente em
> `partition-size:lk2nd: 0x80000` (512 KiB), que é uma partição própria
> do lk2nd. `fastboot flash lk2nd lk2nd.img`. Veja `LK2ND_SETUP.md`.

## 3. Busybox 1.36.1 quebra ao compilar (`tc.c`)

**Sintoma:**
```
networking/tc.c:308: error: 'TC_CBQ_MAXPRIO' undeclared
networking/tc.c:309: error: invalid use of undefined type 'struct tc_cbq_wrropt'
```

**Causa:** headers Linux modernos (~v5.18+) removeram esses símbolos do
iproute. O `tc.c` do busybox 1.36.1 não foi atualizado.

**Solução:** `# CONFIG_TC is not set` no `.config` do busybox. Já está
aplicado no `03-build-busybox.sh`.

## 4. Kernel boota, mas init falha com `/sbin/switch_root: not found`

**Sintoma:**
```
init: exec: line N: /sbin/switch_root: not found
Kernel panic - not syncing: Attempted to kill init!
```

**Causa:** busybox foi linkado só em `/bin/`, não em `/sbin/`. O script
init chamou `/sbin/switch_root`.

**Solução:** criar symlinks em `/sbin/` apontando para `../bin/busybox`.
Já está aplicado no `04-build-initramfs.sh` (lê
`initramfs/busybox-symlinks-sbin.txt`).

## 5. Init não encontra rootfs (`/dev/disk/by-partlabel/` vazio)

**Sintoma:** init imprime `[init] partlabel:` (vazio) mesmo depois de
flashar a userdata.

**Causa:** initramfs busybox-only **não tem udev**. Os symlinks em
`/dev/disk/by-partlabel/` são criados por udev/systemd, não pelo kernel.

**Solução:** o init deste repo busca o rootfs em ordem:
1. `blkid -L rootfs` (busybox blkid)
2. iteração em `/dev/mmcblk0p*` lendo `LABEL`/`TYPE` com `sed`
3. fallback: maior partição ext4 (provavelmente a userdata recém-flashada)

A imagem ext4 é criada com `mkfs.ext4 -L rootfs`, então busca por label
funciona.

## 6. Init imprime `/bin/cut: not found`

**Sintoma:** spam de `[init] line NN: /bin/cut: not found` no boot.

**Causa:** lista de symlinks busybox incompleta — faltou `cut`.

**Solução:** já corrigido em `initramfs/busybox-symlinks-bin.txt`.
Garanta que `cut`, `tr`, `xargs`, `sed`, `wc`, `basename` etc. estão
linkados.

## 7. USB DWC3 falha em probe

**Sintoma:**
```
platform 7000000.usb: deferred probe pending: dwc3: failed to initialize core
```

**Status:** sem solução ainda. Ver `HARDWARE_STATUS.md`. Esta é a
maior pendência para ter sistema interativo via cabo USB.

## 8. fastboot precisa de senha sudo

Em background o sudo falha (sem TTY). Rode os scripts que precisam de
sudo no terminal interativo:

```bash
sudo ./scripts/05-build-rootfs.sh
./scripts/07-flash-and-boot.sh     # ele faz sudo fastboot internamente
```

## 9. `dtc` ou `flex/bison` faltando

**Sintoma:**
```
HOSTCC  scripts/dtc/dtc-parser.tab.o
sh: line 1: bison: command not found
```

**Solução:** `./scripts/00-setup-host.sh` instala `flex`, `bison`, `dtc`.

## 10. Compilação do kernel sai diferente do esperado

Sempre rode `make olddefconfig` após mexer no `.config` para o kernel
expandir dependências. O script `02-build-kernel.sh` já faz isso.
