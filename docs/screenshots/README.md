# Screenshots — histórico do desenvolvimento (2026-05-19)

Estas fotos foram tiradas durante o desenvolvimento do proof-of-life,
em ordem cronológica das descobertas:

## `01-emergency-shell.jpg`

Primeira vez que o kernel realmente subiu até o initramfs. Antes desta
foto, `fastboot boot` retornava OKAY mas o aparelho ficava parado no
logo Motorola — descobrimos que o `lk2nd` rejeitava o DTB silenciosamente
por não bater no `qcom,board-id`. Aqui já com todas as 6 variantes
listadas no DTS.

Mostra: shell de emergência rodando, USB DWC3 falhou em probe.

## `02-kernel-boot-emmc-detected.jpg`

eMMC detectado (`mmcblk0`, 29.1 GiB, 54 partições). Init ainda não
achava rootfs porque `/dev/disk/by-partlabel` não existe sem udev.

## `03-no-rootfs-yet.jpg`

Modo proof-of-life sem rootfs flashado ainda. ROOT vazio, dropou shell.

## `04-cut-missing-bug.jpg`

Userdata já flashada com Arch ARM. Init iterando partições, mas
`/bin/cut` faltava nos symlinks busybox → parsing do LABEL falhava.

## `05-rootfs-mounted-switchroot-missing.jpg`

Bug do `cut` resolvido. `blkid` agora reporta corretamente os LABELs.
Rootfs (`mmcblk0p54`) montado com sucesso, init tentou `switch_root` —
mas `/sbin/switch_root` não existia (só `/bin/switch_root`). Kernel
panic.

Depois desta foto, com `/sbin/switch_root` linkado, o sistema bootou
até o `archlinuxarm login:`.

## `00-login.jpg` (pendente)

Foto do `archlinuxarm login:` prompt — capture e adicione quando
puder. É o marco do projeto.
