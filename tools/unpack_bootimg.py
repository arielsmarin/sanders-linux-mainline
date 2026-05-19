#!/usr/bin/env python3
"""Unpack Android boot.img (header v0/v1) including QCDT appended DT blob."""
import struct, sys, os

p = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "stockboot"
os.makedirs(out, exist_ok=True)

with open(p, "rb") as f:
    data = f.read()

assert data[:8] == b"ANDROID!"
hdr = struct.unpack("<8sIIIIIIIIIII16s512s32s", data[:612])
(magic, ksz, kaddr, rsz, raddr, ssz, saddr, taddr, page, dtsz, _, ver, name, cmdline, id_) = hdr
print(f"kernel_size={ksz} kernel_addr=0x{kaddr:x}")
print(f"ramdisk_size={rsz} ramdisk_addr=0x{raddr:x}")
print(f"second_size={ssz}")
print(f"tags_addr=0x{taddr:x} page_size={page}")
print(f"dt_size={dtsz}")
print(f"header_version={ver}")
print(f"cmdline={cmdline.rstrip(b' ').rstrip(bytes([0])).decode(errors='replace')}")

off = page
def slice_(sz):
    global off
    n = (sz + page - 1) // page * page
    blob = data[off:off+sz]
    off += n
    return blob

kernel = slice_(ksz)
ramdisk = slice_(rsz)
second = slice_(ssz) if ssz else b""
dt = slice_(dtsz) if dtsz else b""

for name, blob in [("kernel", kernel), ("ramdisk", ramdisk), ("second", second), ("dt", dt)]:
    if blob:
        with open(f"{out}/{name}", "wb") as f:
            f.write(blob)
        print(f"wrote {out}/{name} ({len(blob)} bytes)")
