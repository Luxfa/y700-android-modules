#!/usr/bin/env python
# -*- coding: utf-8 -*-
# lp_carve.py — 从 super 镜像按 LP metadata 切出逻辑分区（供后续 ext4 读取）
# 依赖 super_lpdump.py 的 Reader/解析逻辑
# 用法: python lp_carve.py <super.img|--cat f1 f2...> <输出目录> [分区名过滤子串,...]
import struct, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from super_lpdump import RawReader, CatReader

def load_lp(reader):
    geom = reader.read(0x1000, 4096)
    assert struct.unpack("<I", geom[0:4])[0] == 0x616C4467
    hoff = None
    for cand in (0x2000, 0x3000, 0x4000):
        if struct.unpack("<I", reader.read(cand, 4))[0] == 0x414C5030:
            hoff = cand; break
    assert hoff
    hdr = reader.read(hoff, 256)
    hdr_sz = struct.unpack("<I", hdr[8:12])[0]
    tables = []
    for i in range(4):
        tables.append(struct.unpack("<III", hdr[80 + i*12: 92 + i*12]))
    base = hoff + hdr_sz
    def tb(i):
        off_, num, esz = tables[i]
        return reader.read(base + off_, num * esz), num, esz
    pdata, pnum, pesz = tb(0)
    edata, enum_, eesz = tb(1)
    parts = []
    for i in range(pnum):
        e = pdata[i*pesz:(i+1)*pesz]
        name = e[0:36].split(b"\x00")[0].decode()
        first_ext, num_ext = struct.unpack("<II", e[40:48])
        exts = []
        for j in range(num_ext):
            ee = edata[(first_ext+j)*eesz:(first_ext+j+1)*eesz]
            nsec, ttype, tdata, tsrc = struct.unpack("<QIQI", ee[0:24])
            exts.append((nsec * 512, ttype, tdata))   # tdata: 目标设备上的扇区号
        parts.append((name, exts))
    return parts

def carve(reader, parts, outdir, filt=None):
    os.makedirs(outdir, exist_ok=True)
    CHUNK = 16 * 1024 * 1024
    for name, exts in parts:
        if filt and not any(f in name for f in filt):
            continue
        if not exts:
            print(f"  跳过 {name}（0 extent）")
            continue
        out = os.path.join(outdir, name + ".img")
        total = 0
        with open(out, "wb") as w:
            for nbytes, ttype, tdata in exts:
                if ttype != 0:
                    print(f"  [warn] {name} extent type={ttype}（非线性，按零填充）")
                    w.write(b"\x00" * nbytes)
                    total += nbytes
                    continue
                src = tdata * 512
                remain = nbytes
                while remain > 0:
                    take = min(CHUNK, remain)
                    w.write(reader.read(src, take))
                    src += take; remain -= take
                total += nbytes
        print(f"  {name}: {total:,} B -> {out}")

if __name__ == "__main__":
    args = sys.argv[1:]
    if args[0] == "--cat":
        # --cat f1..fN -- outdir [filter]
        idx = args.index("--")
        reader = CatReader(args[1:idx])
        rest = args[idx+1:]
    else:
        reader = RawReader(args[0])
        rest = args[1:]
    outdir = rest[0]
    filt = rest[1].split(",") if len(rest) > 1 else None
    parts = load_lp(reader)
    print(f"逻辑分区 {len(parts)} 个，切出过滤={filt or '全部'}")
    carve(reader, parts, outdir, filt)
