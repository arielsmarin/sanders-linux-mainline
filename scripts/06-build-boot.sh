#!/bin/bash
# Empacota Image.gz + DTB + initramfs em Android boot.img.
# Pre-requisitos: 02 e 04 ja rodaram.
#
# Saida: $OUT/boot-sanders.img

source "$(dirname "$0")/lib.sh"
check_cmd mkbootimg

KERNEL="$LINUX_SRC/arch/arm64/boot/Image.gz"
DTB="$LINUX_SRC/arch/arm64/boot/dts/qcom/msm8953-motorola-sanders.dtb"
INITRAMFS="$OUT/initramfs.cpio.gz"

for f in "$KERNEL" "$DTB" "$INITRAMFS"; do
    [ -f "$f" ] || die "faltando: $f"
done

msg "concatenando Image.gz + DTB (appended-dtb style esperado pelo lk2nd)..."
cat "$KERNEL" "$DTB" > "$OUT/kernel-dtb"

msg "gerando boot-sanders.img..."
mkbootimg \
    --kernel "$OUT/kernel-dtb" \
    --ramdisk "$INITRAMFS" \
    --cmdline "$KERNEL_CMDLINE" \
    --base "$BOOT_BASE" \
    --kernel_offset "$BOOT_KERNEL_OFFSET" \
    --ramdisk_offset "$BOOT_RAMDISK_OFFSET" \
    --tags_offset "$BOOT_TAGS_OFFSET" \
    --pagesize "$BOOT_PAGESIZE" \
    --header_version 0 \
    -o "$OUT/boot-sanders.img"

msg "OK: $OUT/boot-sanders.img ($(du -h "$OUT/boot-sanders.img" | cut -f1))"
