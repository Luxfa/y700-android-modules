#!/usr/bin/env python
# -*- coding: utf-8 -*-
# erofs_read.py — 只读 EROFS 解析（005d 修正版 2026-11-22；005f 多 pcluster 扩展 2026-11-23）
# 005d 修正点：
#   1. superblock: blocks@36, meta_blkaddr@40（原版错读 32/36，把 build_time_nsec 当 blocks）
#   2. meta_base = meta_blkaddr * bsize（本包 system/product 等 meta_blkaddr=0）
#   3. xattr 区大小 = 8 + 4*icount（实测根目录=20B），带 12+4*icount 回退
#   4. datalayout 用上游新枚举：0=FLAT_PLAIN 2=FLAT_INLINE（1/3=z_erofs 压缩）
#   5. dirent = {nid:le64, nameoff:le16, type:u8, rsvd:u8}，nameoff 相对本数据块起点
#      名字无 NUL 结尾，长度 = 下一 dirent 的 nameoff 之差
# 005f 扩展（多 pcluster，实证反推，详见 06_二期自制移植/适配工作区/005f 报告）：
#   6. 压缩索引区（round8(base+8) 起，8B 单元）中，每单元 +4 处的 u32 若为合法块号
#      且单调不减、≤ 首 marker+i_blocks，则为 pcluster 边界 marker；
#      序列 = [p0_start, p1_start, ..., pN_start? , END(=start+i_blocks)]
#      （单 pcluster 文件 = [start, END]；多 pcluster 文件同结构，marker 会在
#        相邻若干单元重复出现——每 pcluster 占若干"索引组"，去重连续重复即可）
#   7. 每个 pcluster = 连续整块分配 [blk_k, blk_{k+1})；LZ4 流在分配内**尾对齐**、
#      头部零填充（中间 pcluster 恰好填满，填充长 0；与 005d 单 pcluster 发现一致）
#   8. 各 pcluster 独立 LZ4 流（无字典），顺序拼接、按 inode size 截断即全文
# 用法:
#   python erofs_read.py <image> info
#   python erofs_read.py <image> ls [路径]
#   python erofs_read.py <image> cat <路径> [输出文件]
import struct, sys, os

def lz4_block(src):
    """纯 Python LZ4 块解压；出错返回 None"""
    out = bytearray(); i = 0; n = len(src)
    while i < n:
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while i < n:
                b = src[i]; i += 1; lit += b
                if b != 255: break
        if i + lit > n: return None
        out += src[i:i+lit]; i += lit
        if i >= n: break
        off = src[i] | (src[i+1] << 8); i += 2
        if off == 0 or off > len(out): return None
        ml = token & 15
        if ml == 15:
            while i < n:
                b = src[i]; i += 1; ml += b
                if b != 255: break
        ml += 4
        st = len(out) - off
        for k in range(ml):
            out.append(out[st + k])
    return bytes(out)

def lz4_block_tolerant(src):
    """宽松版：返回 (已解码输出, 是否正常消耗完输入)。
    尾零区触发 off==0 时返回已有输出（用于流后可能有零垫的场景）。"""
    out = bytearray(); i = 0; n = len(src)
    while i < n:
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while i < n:
                b = src[i]; i += 1; lit += b
                if b != 255: break
        if i + lit > n: return bytes(out), False
        out += src[i:i+lit]; i += lit
        if i >= n: break
        off = src[i] | (src[i+1] << 8); i += 2
        if off == 0:
            # 零垫尾巴：剩余必须全零才算正常结束
            return bytes(out), not any(src[i-2:])
        if off > len(out): return bytes(out), False
        ml = token & 15
        if ml == 15:
            while i < n:
                b = src[i]; i += 1; ml += b
                if b != 255: break
        ml += 4
        st = len(out) - off
        for k in range(ml):
            out.append(out[st + k])
    return bytes(out), True

class Erofs:
    def __init__(self, path):
        self.f = open(path, "rb")
        self.f.seek(1024)
        sb = self.f.read(128)
        assert struct.unpack("<I", sb[0:4])[0] == 0xE0F5E1E2, "not erofs"
        self.blkszbits = sb[12]
        self.bsize = 1 << self.blkszbits
        self.rootnid = struct.unpack("<H", sb[14:16])[0]
        self.inos = struct.unpack("<Q", sb[16:24])[0]
        self.blocks = struct.unpack("<I", sb[36:40])[0]
        self.meta_blkaddr = struct.unpack("<I", sb[40:44])[0]
        self.feat_incompat = struct.unpack("<I", sb[76:80])[0]
        self.meta_base = self.meta_blkaddr * self.bsize

    def read(self, off, n):
        self.f.seek(off)
        return self.f.read(n)

    def nid_off(self, nid):
        return self.meta_base + nid * 32

    def inode(self, nid):
        d = self.read(self.nid_off(nid), 64)
        fmt = struct.unpack("<H", d[0:2])[0]
        extended = fmt & 1
        datalayout = (fmt >> 1) & 0x7
        xattr_icount = struct.unpack("<H", d[2:4])[0]
        mode = struct.unpack("<H", d[4:6])[0]
        if extended:
            size = struct.unpack("<Q", d[8:16])[0]
            blkaddr = struct.unpack("<I", d[16:20])[0]
            inosize = 64
        else:
            size = struct.unpack("<I", d[8:12])[0]
            blkaddr = struct.unpack("<I", d[16:20])[0]
            inosize = 32
        return {"nid": nid, "mode": mode, "size": size, "datalayout": datalayout,
                "blkaddr": blkaddr, "xattr_icount": xattr_icount, "inosize": inosize}

    def _xattr_sizes(self, inode):
        # 候选：8+4*icount（实测）与 12+4*icount（内核头 12B 解释）
        ic = inode["xattr_icount"]
        if ic == 0:
            return [0]
        return [8 + 4 * ic, 12 + 4 * ic]

    def _xattr_size(self, inode):
        return (8 + 4 * inode["xattr_icount"]) if inode["xattr_icount"] else 0

    def _pcluster_markers(self, inode):
        """扫描压缩索引区（8B 单元），提取 pcluster 边界块号序列。
        规则（005f 实证）：单元 +4 的 u32 若为合法块号、单调不减、且不超过
        首 marker+i_blocks，则是 marker；收集到 END=首 marker+i_blocks 为止。
        返回 [start0, start1, ..., END]（相邻重复已去重）。"""
        base = self.nid_off(inode["nid"]) + inode["inosize"] + self._xattr_size(inode)
        idx = (base + 8 + 7) & ~7
        ib = inode["blkaddr"]  # 压缩数据总块数（005d 实证）
        markers = []
        start0 = None
        pos = idx
        for _ in range(1 << 16):  # 安全上限
            unit = self.read(pos, 8)
            if len(unit) < 8:
                break
            m = struct.unpack("<I", unit[4:8])[0]
            pos += 8
            if m == 0 or m >= self.blocks:
                continue  # advise-only 单元（多 pcluster 索引中大量出现），跳过
            if start0 is None:
                start0 = m
                markers.append(m)
                continue
            if m < markers[-1] or m > start0 + ib:
                continue  # 越序/超界视为 advise 噪声，跳过（终点由 == start0+ib 判定）
            if m == markers[-1]:
                continue  # 同 pcluster 的重复 marker
            markers.append(m)
            if m == start0 + ib:
                break
        if markers and markers[-1] != markers[0] + ib:
            markers.append(markers[0] + ib)  # 单单元索引（2 lcluster 文件）无显式 END，补隐式终点
        if len(markers) < 2 or markers[-1] != markers[0] + ib:
            raise NotImplementedError(
                f"pcluster marker 扫描失败 nid={inode['nid']} markers={markers[:8]}... i_blocks={ib}")
        return markers

    def _read_compressed(self, inode):
        """z_erofs COMPACT 多 pcluster walk（005f 实证规则）：
        markers 给出 pcluster 物理边界；每个 pcluster 内 LZ4 流尾对齐、头零填充、
        流恰好消耗到分配末尾（中间 pcluster 填充长 0）；各流独立、顺序拼接。"""
        size = inode["size"]
        markers = self._pcluster_markers(inode)
        out = bytearray()
        for k in range(len(markers) - 1):
            a, b = markers[k], markers[k + 1]
            raw = self.read(a * self.bsize, (b - a) * self.bsize)
            nz = next((i for i, x in enumerate(raw) if x), len(raw))
            if nz == len(raw):
                raise ValueError(f"pcluster 全零 nid={inode['nid']} blk={a}")
            seg, ok = lz4_block_tolerant(raw[nz:])
            if not ok:
                raise ValueError(f"pcluster 解码异常 nid={inode['nid']} blk=[{a},{b})")
            out += seg
            if len(out) >= size and k < len(markers) - 2:
                raise ValueError(f"输出提前达标但 pcluster 未走完 nid={inode['nid']}")
        if len(out) < size:
            raise ValueError(f"压缩流解码不足 nid={inode['nid']} ({len(out)} < {size})")
        return bytes(out[:size])

    def data_off(self, inode):
        return self.meta_base + inode["blkaddr"] * self.bsize

    def read_file(self, inode):
        dl = inode["datalayout"]
        size = inode["size"]
        if size == 0:
            return b""
        if dl == 3:
            return self._read_compressed(inode)
        if dl not in (0, 2):
            raise NotImplementedError(f"datalayout={dl} nid={inode['nid']}")
        data_off = self.data_off(inode)
        whole = (size // self.bsize) * self.bsize
        out = bytearray()
        if whole:
            out += self.read(data_off, whole)
        tail = size - whole
        if tail:
            if dl == 2:
                # inline 尾在 inode+xattr 之后；xattr 大小取候选中较小者（文件一般无 xattr 歧义）
                xs = self._xattr_sizes(inode)[0]
                out += self.read(self.nid_off(inode["nid"]) + inode["inosize"] + xs, tail)
            else:
                out += self.read(data_off + whole, tail)
        return bytes(out)

    def list_dir(self, inode):
        dl = inode["datalayout"]
        size = inode["size"]
        if dl not in (0, 2):
            raise NotImplementedError(f"dir datalayout={dl} nid={inode['nid']}")
        data_off = self.data_off(inode)
        nwhole = size // self.bsize
        tail = size % self.bsize
        entries = []
        # 整块部分
        for b in range(nwhole):
            blk = self.read(data_off + b * self.bsize, self.bsize)
            entries += self._parse_dir_block(blk, self.bsize)
        # 尾部
        if tail:
            if dl == 2:
                ok = False
                for xs in self._xattr_sizes(inode):
                    blk = self.read(self.nid_off(inode["nid"]) + inode["inosize"] + xs, tail)
                    try:
                        entries += self._parse_dir_block(blk, tail)
                        ok = True
                        break
                    except ValueError:
                        continue
                if not ok:
                    raise ValueError(f"目录尾块解析失败 nid={inode['nid']}")
            else:
                blk = self.read(data_off + nwhole * self.bsize, tail)
                entries += self._parse_dir_block(blk, tail)
        return entries

    def _parse_dir_block(self, blk, blklen):
        # dirent 12B: nid(8) nameoff(2) type(1) rsvd(1)；名字区在 dirent 数组之后
        recs = []
        pos = 0
        while pos + 12 <= blklen and pos + 12 <= len(blk):
            nid, nameoff, ftype, rsvd = struct.unpack("<QHBB", blk[pos:pos+12])
            if nid == 0 or nid * 32 >= self.blocks * self.bsize:
                break
            if nameoff < 12 or nameoff >= blklen:
                break
            recs.append((nid, nameoff, ftype))
            pos += 12
            if nameoff <= pos:  # 名字区与数组重叠保护
                break
        if not recs:
            raise ValueError("no dirents")
        # 校验：首个 nameoff 应等于 12*N（N=本块 dirent 数）
        n = recs[0][1] // 12
        if n < 1 or n > len(recs) and recs[0][1] != 12 * len(recs):
            # 宽松：若恰好解析到 n 条前停下也可接受
            pass
        recs = recs[:n] if n <= len(recs) else recs
        out = []
        for i, (nid, nameoff, ftype) in enumerate(recs):
            end = recs[i+1][1] if i + 1 < len(recs) else blklen
            if end <= nameoff or end > blklen:
                end = blklen
            name = blk[nameoff:end].decode("utf-8", "replace")
            out.append((name, nid, ftype))
        return out

    def resolve(self, path):
        parts = [p for p in path.strip("/").split("/") if p]
        inode = self.inode(self.rootnid)
        for p in parts:
            if (inode["mode"] & 0o170000) == 0o120000:
                # 符号链接：读目标（仅支持绝对/相对简单拼接）
                tgt = self.read_file(inode).decode()
                if tgt.startswith("/"):
                    inode = self.resolve(tgt)
                else:
                    raise NotImplementedError(f"相对符号链接 {p} -> {tgt}")
                continue
            entries = self.list_dir(inode)
            hit = [e for e in entries if e[0] == p]
            if not hit:
                raise FileNotFoundError(path)
            inode = self.inode(hit[0][1])
        return inode

def main():
    img = Erofs(sys.argv[1])
    cmd = sys.argv[2]
    if cmd == "info":
        print(f"bsize={img.bsize} blocks={img.blocks} inos={img.inos} rootnid={img.rootnid} meta_blkaddr={img.meta_blkaddr} feat_incompat={hex(img.feat_incompat)}")
    elif cmd == "ls":
        path = sys.argv[3] if len(sys.argv) > 3 else "/"
        inode = img.resolve(path)
        for name, nid, ft in img.list_dir(inode):
            t = {0:"?",1:"f",2:"d",3:"c",4:"b",5:"p",6:"s",7:"l"}.get(ft, str(ft))
            print(f"[{t}] {name}")
    elif cmd == "cat":
        path = sys.argv[3]
        inode = img.resolve(path)
        data = img.read_file(inode)
        if len(sys.argv) > 4:
            open(sys.argv[4], "wb").write(data)
            print(f"写出 {len(data):,} B -> {sys.argv[4]}")
        else:
            sys.stdout.buffer.write(data)

if __name__ == "__main__":
    main()
