#!/usr/bin/env python
# -*- coding: utf-8 -*-
# cpio_extract.py — newc 格式 cpio 解包（ramdisk 分析用）
# 用法: python cpio_extract.py <ramdisk.cpio> <输出目录>
import sys, os

def extract(path, outdir):
    d = open(path, "rb").read()
    pos = 0
    n = 0
    while pos + 110 <= len(d):
        hdr = d[pos:pos+110]
        if hdr[:6] != b"070701":
            break
        vals = [int(hdr[6+i*8:14+i*8], 16) for i in range(13)]
        (ino, mode, uid, gid, nlink, mtime, filesize,
         devmaj, devmin, rdevmaj, rdevmin, namesize, check) = vals
        name = d[pos+110:pos+110+namesize-1].decode("utf-8", "replace")
        pos += 110 + namesize
        pos = (pos + 3) // 4 * 4
        data = d[pos:pos+filesize]
        pos += filesize
        pos = (pos + 3) // 4 * 4
        if name == "TRAILER!!!":
            break
        n += 1
        out = os.path.join(outdir, name)
        ftype = mode & 0o170000
        if ftype == 0o040000:      # dir
            os.makedirs(out, exist_ok=True)
        elif ftype == 0o120000:    # symlink
            os.makedirs(os.path.dirname(out), exist_ok=True)
            target = data.decode("utf-8", "replace")
            # Windows 下无法稳定建 symlink，写成 .symlink 文本记录
            with open(out + ".symlink", "w", encoding="utf-8") as f:
                f.write(target)
        elif ftype == 0o100000:    # regular
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "wb") as f:
                f.write(data)
        else:
            # 设备节点等，只记录元数据
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out + ".nodemeta", "w") as f:
                f.write(f"mode={oct(mode)} dev={devmaj},{devmin} rdev={rdevmaj},{rdevmin}")
    print(f"{path}: 解出 {n} 项 -> {outdir}")

if __name__ == "__main__":
    extract(sys.argv[1], sys.argv[2])
