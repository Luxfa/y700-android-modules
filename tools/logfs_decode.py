#!/usr/bin/env python
# -*- coding: utf-8 -*-
# logfs_decode.py — 解码 9008 回读的 logfs(8MiB, FAT + 64KiB 一块的 ABL/内核逐次启动日志)
# 用法: python logfs_decode.py <rb_logfs.bin> [输出目录] [--full]
#   默认只给"每块摘要"（行数、身份指纹、Cmdline 摘要、最后 6 行=死在哪）
#   --full 另存每块全文
import os, re, sys

BLK = 64 * 1024

def runs(buf, minlen=8):
    out, cur, start = [], [], 0
    for i, b in enumerate(buf):
        if 32 <= b < 127 or b in (9, 10, 13):
            if not cur: start = i
            cur.append(b)
        else:
            if len(cur) >= minlen:
                out.append((start, bytes(cur).decode("ascii", "replace")))
            cur = []
    if len(cur) >= minlen:
        out.append((start, bytes(cur).decode("ascii", "replace")))
    return out

def split_lines(text):
    return [l.strip() for l in re.split(r"[\r\n]+", text) if len(l.strip()) >= 4]

def main(path, outdir=None, full=False):
    d = open(path, "rb").read()
    print(f"文件 {os.path.basename(path)} 大小 {len(d):,} B  非零占比 {sum(1 for b in d if b)*100//len(d)}%")
    nblk = len(d) // BLK
    used = []
    for k in range(nblk):
        buf = d[k*BLK:(k+1)*BLK]
        if not any(buf):
            continue
        rr = runs(buf)
        lines = split_lines("".join(t for _, t in rr))
        if len(lines) < 5:
            continue
        used.append((k, buf, lines))
    print(f"可读块 {len(used)} 个（共 {nblk} 格）\n")
    for k, buf, lines in used:
        head = [l for l in lines if "Booting from slot" in l]
        hwid = [l for l in lines if "SM8850" in l or "hwid" in l.lower()]
        cmd = [l for l in lines if l.startswith("Cmdline:") or "Cmdline:" in l]
        imgs = [l for l in lines if "Load Image" in l]
        errl = [l for l in lines if re.search(r"ERROR|Fail|failed|panic|abort|denied|assert", l)]
        print(f"================= 块 {k}（@0x{k*BLK:08x}，{len(lines)} 行）=================")
        print(f"  槽位  : {head[0][:80] if head else '（本块无）'}")
        print(f"  硬件  : {hwid[0][:90] if hwid else '（无）'}")
        print(f"  加载件: {len(imgs)} 条 " + " / ".join(re.sub(r'\s+total time.*', '', x.split('Load Image')[-1]) for x in imgs[:8]))
        c = cmd[0] if cmd else ""
        flag = []
        for tok in ("console=ttyMSM0", "earlycon", "selinux=permissive", "console=ttynull", "androidboot.veritymode"):
            if tok in c:
                flag.append(tok)
        print(f"  Cmdline 指纹: {' '.join(flag) if flag else '（本块无 Cmdline 行）'}")
        print(f"  可疑行 {len(errl)} 条，前 4 条：")
        for l in errl[:4]:
            print("     ! " + l[:150])
        print(f"  末 8 行（死在哪）：")
        for l in lines[-8:]:
            print("     | " + l[:160])
        print()
        if full and outdir:
            os.makedirs(outdir, exist_ok=True)
            with open(os.path.join(outdir, f"block_{k:02d}.txt"), "w", encoding="utf-8") as f:
                f.write("\n".join(lines))

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--full"]
    main(args[0], args[1] if len(args) > 1 else None, "--full" in sys.argv)
