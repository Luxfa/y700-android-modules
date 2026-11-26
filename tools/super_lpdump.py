#!/usr/bin/env python
# -*- coding: utf-8 -*-
# super_lpdump.py — super 镜像 LP 元数据解析（等效 lpdump）
# 支持两种输入：
#   1) 原始 super.img（非稀疏，如 C17 包）
#   2) Android sparse 分包系列（如官方包 super_1.img..super_N.img，自动拼接虚拟地址空间）
# 用法:
#   python super_lpdump.py <super.img>
#   python super_lpdump.py --sparse <super_1.img> [super_2.img ...]
import struct, sys, glob

class RawReader:
    def __init__(self, path):
        self.f = open(path, "rb")
    def read(self, off, n):
        self.f.seek(off)
        return self.f.read(n)
    def size(self):
        import os; return os.fstat(self.f.fileno()).st_size

class SparseReader:
    """多个 Android sparse 文件按序拼接成虚拟连续空间（不解压落盘）"""
    def __init__(self, paths):
        self.maps = []   # (vstart, vend, kind, source)  kind: 'raw'/'skip'/'fill'
        vaddr = 0
        for p in paths:
            d = open(p, "rb")
            hdr = d.read(28)
            magic, major, minor, fhdr, chdr, blk_sz, total_blks, total_chunks, csum = struct.unpack("<IHHHHIIII", hdr)
            assert magic == 0xED26FF3A, f"{p} 不是 sparse 文件"
            for _ in range(total_chunks):
                ch = d.read(12)
                ctype, res, blk_count, total_sz = struct.unpack("<HHII", ch)
                data_sz = total_sz - 12
                vsz = blk_count * blk_sz
                if ctype == 0xCAC1:      # raw
                    self.maps.append((vaddr, vaddr + vsz, "raw", (p, d.tell())))
                    d.seek(data_sz, 1)
                elif ctype == 0xCAC2:    # fill
                    self.maps.append((vaddr, vaddr + vsz, "fill", None))
                elif ctype == 0xCAC3:    # don't care
                    self.maps.append((vaddr, vaddr + vsz, "skip", None))
                vaddr += vsz
            d.close()
        self.vsize = vaddr
        self._fh = {}
    def read(self, off, n):
        out = bytearray()
        while n > 0:
            for (vs, ve, kind, src) in self.maps:
                if vs <= off < ve:
                    take = min(n, ve - off)
                    if kind == "raw":
                        p, foff = src
                        if p not in self._fh: self._fh[p] = open(p, "rb")
                        fh = self._fh[p]
                        fh.seek(foff + (off - vs))
                        out += fh.read(take)
                    else:
                        out += b"\x00" * take
                    off += take; n -= take
                    break
            else:
                raise IOError(f"offset {off} 不在 sparse 覆盖范围")
        return bytes(out)
    def size(self):
        return self.vsize

class CatReader:
    """多个原始文件按序拼接成虚拟连续空间（官方 unsparse 分包 super）"""
    def __init__(self, paths):
        import os
        self.files = []
        v = 0
        for p in paths:
            s = os.path.getsize(p)
            self.files.append((v, v + s, p))
            v += s
        self.vsize = v
        self._fh = {}
    def read(self, off, n):
        out = bytearray()
        while n > 0:
            for (vs, ve, p) in self.files:
                if vs <= off < ve:
                    take = min(n, ve - off)
                    if p not in self._fh: self._fh[p] = open(p, "rb")
                    fh = self._fh[p]
                    fh.seek(off - vs)
                    out += fh.read(take)
                    off += take; n -= take
                    break
            else:
                raise IOError(f"offset {off} 超出拼接范围")
        return bytes(out)
    def size(self):
        return self.vsize

def parse_lp(reader, label):
    geom = reader.read(0x1000, 4096)
    magic = struct.unpack("<I", geom[0:4])[0]
    if magic != 0x616C4467:
        print(f"[{label}] 0x1000 处无 LP geometry（magic={hex(magic)}）——可能不是动态分区 super")
        return
    meta_max, meta_slots, lblk = struct.unpack("<III", geom[40:52])
    print(f"[{label}] LP geometry: metadata_max={meta_max} slots={meta_slots} logical_block={lblk}")
    # metadata header 可能在 0x2000（仅主几何）或 0x3000（主+备份几何都在头部），扫描定位
    hoff = None
    for cand in (0x2000, 0x3000, 0x4000):
        if struct.unpack("<I", reader.read(cand, 4))[0] == 0x414C5030:
            hoff = cand
            break
    assert hoff is not None, "未找到 LP metadata header (0x414C5030)"
    print(f"[{label}] LP metadata header @ {hex(hoff)}")
    hdr = reader.read(hoff, 256)
    hmagic = struct.unpack("<I", hdr[0:4])[0]
    assert hmagic == 0x414C5030, f"LP metadata header magic 错误: {hex(hmagic)}"
    major, minor = struct.unpack("<HH", hdr[4:8])
    hdr_sz = struct.unpack("<I", hdr[8:12])[0]
    tbl_sz = struct.unpack("<I", hdr[12:16])[0]
    # table descriptors 位于 header 偏移 0x50（magic4+ver4+hdr_sz4+hdr_cksum32+tbl_sz4+tbl_cksum32 之后）
    tables = []
    for i in range(4):
        off_, num, esz = struct.unpack("<III", hdr[80 + i*12: 92 + i*12])
        tables.append((off_, num, esz))
    base = hoff + hdr_sz
    def table_bytes(idx):
        off_, num, esz = tables[idx]
        return reader.read(base + off_, num * esz), num, esz
    pdata, pnum, pesz = table_bytes(0)
    edata, enum_, eesz = table_bytes(1)
    gdata, gnum, gesz = table_bytes(2)
    bdata, bnum, besz = table_bytes(3)
    print(f"[{label}] LP metadata v{major}.{minor}: partitions={pnum} extents={enum_} groups={gnum} block_devices={bnum}")
    groups = []
    for i in range(gnum):
        e = gdata[i*gesz:(i+1)*gesz]
        name = e[0:36].split(b"\x00")[0].decode()
        maxsz = struct.unpack("<Q", e[36:44])[0]
        gflags = struct.unpack("<I", e[44:48])[0]
        groups.append(name)
        print(f"  group[{i}] {name} max_size={maxsz:,} flags={gflags}")
    bdevs = []
    for i in range(bnum):
        e = bdata[i*besz:(i+1)*besz]
        fls, align, align_off, size = struct.unpack("<QIIQ", e[0:24])
        name = e[24:60].split(b"\x00")[0].decode()
        bflags = struct.unpack("<I", e[60:64])[0]
        bdevs.append(name)
        print(f"  block_device[{i}] {name} size={size:,} first_logical_sector={fls} slot_flag={bflags}")
    parts = []
    total = 0
    for i in range(pnum):
        e = pdata[i*pesz:(i+1)*pesz]
        name = e[0:36].split(b"\x00")[0].decode()
        attrs, first_ext, num_ext, grp = struct.unpack("<IIII", e[36:52])
        sz = 0
        ext_list = []
        for j in range(num_ext):
            ee = edata[(first_ext+j)*eesz:(first_ext+j+1)*eesz]
            nsec, ttype, tdata, tsrc = struct.unpack("<QIQI", ee[0:24])
            sz += nsec * 512
            ext_list.append((nsec*512, ttype, tdata))
        total += sz
        parts.append((name, sz, attrs, groups[grp] if grp < len(groups) else str(grp), ext_list))
        attr_s = []
        if attrs & 1: attr_s.append("READONLY")
        if attrs & 2: attr_s.append("SLOT_SUFFIXED")
        print(f"  part[{i:02d}] {name:<22} {sz:>14,} B  group={groups[grp] if grp<len(groups) else grp} attrs={','.join(attr_s) or '0'} extents={num_ext}")
    print(f"  合计: {total:,} B ({total/1024/1024/1024:.2f} GiB)")
    return parts

if __name__ == "__main__":
    if sys.argv[1] == "--sparse":
        r = SparseReader(sys.argv[2:])
        parse_lp(r, "+".join(sys.argv[2:]))
    elif sys.argv[1] == "--cat":
        r = CatReader(sys.argv[2:])
        parse_lp(r, "+".join(sys.argv[2:]))
    else:
        parse_lp(RawReader(sys.argv[1]), sys.argv[1])
