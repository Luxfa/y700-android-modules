#!/usr/bin/env python
# -*- coding: utf-8 -*-
# ext4_read.py — 只读 ext4 解析（extent 树 + 目录遍历 + 文件提取）
# 用途：无 7-Zip 环境下读取 super 逻辑分区镜像内的文件
# 用法:
#   python ext4_read.py <image> ls [路径]        # 列目录
#   python ext4_read.py <image> cat <路径> [输出文件]
import struct, sys, os

class Ext4:
    def __init__(self, path):
        self.f = open(path, "rb")
        self.f.seek(1024)
        sb = self.f.read(1024)
        assert struct.unpack("<H", sb[56:58])[0] == 0xEF53, "not ext4"
        self.inodes_count = struct.unpack("<I", sb[0:4])[0]
        self.blocks_count = struct.unpack("<I", sb[4:8])[0] | (struct.unpack("<I", sb[0x150:0x154])[0] << 32)
        self.log_block = struct.unpack("<I", sb[24:28])[0]
        self.bsize = 1024 << self.log_block
        self.blocks_per_group = struct.unpack("<I", sb[32:36])[0]
        self.inodes_per_group = struct.unpack("<I", sb[40:44])[0]
        self.first_ino = struct.unpack("<I", sb[84:88])[0]
        self.inode_size = struct.unpack("<H", sb[88:90])[0]
        feat_incompat = struct.unpack("<I", sb[100:104])[0]
        self.desc_size = struct.unpack("<H", sb[254:256])[0] if feat_incompat & 0x80 else 32
        self.meta_csum = bool(feat_incompat & 0x400)
        self.ngroups = (self.blocks_count + self.blocks_per_group - 1) // self.blocks_per_group
        # group descriptors
        gd_off = self.bsize if self.bsize == 1024 else self.bsize  # gdt 在 superblock 所在块之后
        gd_off = (1024 // self.bsize + 1) * self.bsize if self.bsize > 1024 else 2048
        self.f.seek(gd_off)
        gdt = self.f.read(self.ngroups * self.desc_size)
        self.gdt = gdt
    def _gdt(self, idx):
        e = self.gdt[idx*self.desc_size:(idx+1)*self.desc_size]
        it_lo = struct.unpack("<I", e[8:12])[0]
        it_hi = struct.unpack("<I", e[40:44])[0] if self.desc_size >= 44 else 0
        return (it_hi << 32) | it_lo
    def read_block(self, blk, n=1):
        self.f.seek(blk * self.bsize)
        return self.f.read(n * self.bsize)
    def inode(self, ino):
        g = (ino - 1) // self.inodes_per_group
        i = (ino - 1) % self.inodes_per_group
        tbl = self._gdt(g)
        self.f.seek(tbl * self.bsize + i * self.inode_size)
        d = self.f.read(self.inode_size)
        mode = struct.unpack("<H", d[0:2])[0]
        size = struct.unpack("<I", d[4:8])[0] | (struct.unpack("<I", d[108:112])[0] << 32)
        flags = struct.unpack("<I", d[32:36])[0]
        block = d[40:100]
        return {"mode": mode, "size": size, "flags": flags, "block": block, "ino": ino}
    def _extents(self, inode):
        # 解析 extent 树，产出 (lblock, pblock, count)
        out = []
        def parse(buf):
            magic, entries, max_, depth = struct.unpack("<HHHH", buf[0:8])
            assert magic == 0xF30A
            if depth == 0:
                for i in range(entries):
                    ee = buf[12 + i*12: 24 + i*12]
                    # ext4_extent: ee_block(4) ee_len(2) ee_start_hi(2) ee_start_lo(4)
                    lblk, cnt, phi, plo = struct.unpack("<IHHI", ee)
                    cnt_real = cnt if cnt <= 32768 else cnt - 32768
                    out.append((lblk, (phi << 32) | plo, cnt_real))
            else:
                for i in range(entries):
                    ee = buf[12 + i*12: 24 + i*12]
                    lblk, plo, phi = struct.unpack("<IIH", ee[:10])
                    parse(self.read_block((phi << 32) | plo))
        parse(inode["block"])
        return out
    def read_file(self, inode):
        exts = self._extents(inode)
        size = inode["size"]
        buf = bytearray()
        for lblk, pblk, cnt in sorted(exts):
            buf += self.read_block(pblk, cnt)
            if len(buf) >= size:
                break
        return bytes(buf[:size])
    def list_dir(self, inode):
        exts = self._extents(inode)
        entries = []
        for lblk, pblk, cnt in sorted(exts):
            data = self.read_block(pblk, cnt)
            pos = 0
            while pos + 8 <= len(data):
                ino, rec_len, name_len, ftype = struct.unpack("<IHBB", data[pos:pos+8])
                if rec_len < 8 or pos + rec_len > len(data):
                    break
                if ino != 0:
                    name = data[pos+8:pos+8+name_len].decode("utf-8", "replace")
                    entries.append((name, ino, ftype))
                pos += rec_len
                if rec_len == 0:
                    break
        return entries
    def resolve(self, path):
        parts = [p for p in path.strip("/").split("/") if p]
        ino = 2
        inode = self.inode(2)
        for p in parts:
            entries = self.list_dir(inode)
            hit = [e for e in entries if e[0] == p]
            if not hit:
                raise FileNotFoundError(path)
            ino = hit[0][1]
            inode = self.inode(ino)
        return inode

def main():
    img = Ext4(sys.argv[1])
    cmd = sys.argv[2]
    if cmd == "ls":
        path = sys.argv[3] if len(sys.argv) > 3 else "/"
        inode = img.resolve(path)
        for name, ino, ft in img.list_dir(inode):
            t = {1:"f",2:"d",7:"l"}.get(ft, str(ft))
            print(f"  [{t}] {name}")
    elif cmd == "cat":
        path = sys.argv[3]
        inode = img.resolve(path)
        if (inode["mode"] & 0o170000) == 0o120000:
            data = img.read_file(inode)
            print("SYMLINK ->", data.decode())
            return
        data = img.read_file(inode)
        if len(sys.argv) > 4:
            open(sys.argv[4], "wb").write(data)
            print(f"写出 {len(data):,} B -> {sys.argv[4]}")
        else:
            sys.stdout.buffer.write(data)

if __name__ == "__main__":
    main()
