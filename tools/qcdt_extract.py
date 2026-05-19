#!/usr/bin/env python3
import struct, sys, os
p = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "qcdt_out"
os.makedirs(out, exist_ok=True)
with open(p, "rb") as f: d = f.read()
assert d[:4] == b"QCDT"
ver = struct.unpack("<I", d[4:8])[0]
n = struct.unpack("<I", d[8:12])[0]
print(f"version=0x{ver:x} num_dtbs={n}")
# v3 entry: msm-id, board-id-major(variant), subtype, soc_rev, pmic0..3, offset, size = 10*u32 = 40B
ent_sz = 40
for i in range(n):
    e = d[12 + i*ent_sz : 12 + (i+1)*ent_sz]
    if len(e) < ent_sz: break
    msm, var, sub, rev, p0, p1, p2, p3, off, sz = struct.unpack("<10I", e)
    if off == 0 and sz == 0: continue
    name = f"msm-{msm}_board-{var:08x}_sub-{sub:08x}_rev-{rev}"
    out_path = f"{out}/{i:02d}_{name}.dtb"
    blob = d[off:off+sz]
    if blob[:4] == b'\xd0\x0d\xfe\xed':
        with open(out_path, "wb") as f: f.write(blob)
        print(f"[{i}] msm={msm} var=0x{var:08x} sub=0x{sub:08x} rev={rev} -> {out_path} ({sz} B)")
    else:
        print(f"[{i}] msm={msm} var=0x{var:08x} sub=0x{sub:08x} rev={rev} -> NOT a DTB at offset {off}")
