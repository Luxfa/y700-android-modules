#!/usr/bin/env python
# -*- coding: utf-8 -*-
# analyze_c17.py — C17 移植包关键镜像解剖：vbmeta 标志 / GPT 分区表 / 内核指纹
# 用法: python analyze_c17.py <分析目录(含 vbmeta_a/b.img, gpt_main0.bin, init_boot_b.img)>
import struct, sys, os, re

base = sys.argv[1]

print("=" * 60)
print("1) vbmeta 验证标志（决定锁 BL 能否启动）")
for name in ["vbmeta_a", "vbmeta_b"]:
    p = os.path.join(base, name + ".img")
    if not os.path.exists(p):
        print(f"  {name}: 缺失")
        continue
    d = open(p, "rb").read()
    magic = d[0:4]
    flags = struct.unpack("<I", d[0x7C:0x80])[0]
    sig_size = struct.unpack("<Q", d[0x38:0x40])[0]
    meanings = []
    if flags & 1: meanings.append("hashtree已禁用")
    if flags & 2: meanings.append("验证已禁用")
    if not meanings: meanings.append("完全验证(官方锁定态)")
    print(f"  {name}: magic={magic}, flags={flags} [{','.join(meanings)}], sig={sig_size}B")

print("=" * 60)
print("2) GPT 分区表（与设备 by-name 比对）")
gpt = os.path.join(base, "gpt_main0.bin")
d = open(gpt, "rb").read()
sig = d[512:520].decode("ascii", "ignore")
print("  GPT签名:", sig)
if sig == "EFI PART":
    pe_lba = struct.unpack("<Q", d[512 + 72:512 + 80])[0]
    num = struct.unpack("<I", d[512 + 80:512 + 84])[0]
    size = struct.unpack("<I", d[512 + 84:512 + 88])[0]
    names = []
    for i in range(num):
        off = pe_lba * 512 + i * size
        e = d[off:off + size]
        n = e[56:128].decode("utf-16-le", "ignore").rstrip("\x00")
        fl, ll = struct.unpack("<QQ", e[32:48])
        names.append((n, ll - fl + 1))
    print(f"  分区数: {len(names)}")
    for n, s in names:
        print(f"    {n:<24} {s:>12,} 扇区")

print("=" * 60)
print("3) init_boot 内核指纹")
ib = os.path.join(base, "init_boot_b.img")
if os.path.exists(ib):
    d = open(ib, "rb").read()
    m = re.search(rb"Linux version [\x20-\x7e]{5,120}", d)
    print("  ", m.group(0).decode("ascii", "ignore") if m else "未找到内核版本串")
    m2 = re.search(rb"KernelS(b|U)|KernelSU|ksu", d)
    print("   KSU痕迹:", "有" if m2 else "无")
    m3 = re.search(rb"AVB0", d[:0x1000])
    print("   头部AVB签名块:", "有" if m3 else "无(未签名/链式之外)")
