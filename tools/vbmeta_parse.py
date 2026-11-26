#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vbmeta_parse.py — AVB vbmeta 镜像深度解析（适配 C17 包内 avbtool 1.3.0 变体布局）
# 实测布局要点（与上游 avbtool 不同，已在 vbmeta_b.img 上逐字节核实）：
#   - header 字段大端；descriptors 位于 256 + auth_block_size + descriptors_offset
#   - 描述符头：tag(8 BE) + num_bytes_following(8 BE)，整体按 8 对齐
#   - tag=4 为 CHAIN（本变体的链式描述符）：rloc(4) name_len(4) key_len(4) + 64B 保留 + name + RSA公钥
#   - tag=2 HASH：image_size(8) hash_alg(32) name_len(4) salt_len(4) digest_len(4) flags(4) + 60B 保留 + name + digest + salt
#   - tag=1 HASHTREE：标准头至 flags(4)（共104B） + 60B 保留 + name + root_digest + salt
# 用法: python vbmeta_parse.py <vbmeta.img> [更多img...]
import struct, sys, re

def parse(path):
    d = open(path, "rb").read()
    assert d[0:4] == b"AVB0", "not a vbmeta image"
    u32 = lambda o: struct.unpack(">I", d[o:o+4])[0]
    u64 = lambda o: struct.unpack(">Q", d[o:o+8])[0]
    auth_sz, aux_sz = u64(12), u64(20)
    algo = u32(28)
    hash_off, hash_sz = u64(32), u64(40)
    sig_off, sig_sz = u64(48), u64(56)
    pk_off, pk_sz = u64(64), u64(72)
    desc_off, desc_sz = u64(96), u64(104)
    flags = u32(120)
    rel = d[128:176].split(b"\x00")[0].decode("ascii", "replace")
    algos = {0:"NONE",1:"SHA256_RSA2048",2:"SHA256_RSA4096",3:"SHA256_RSA8192",4:"SHA256",5:"SHA512"}
    nz = sum(1 for b in d if b) * 100 // len(d)
    print(f"--- {path}")
    print(f"  algo={algos.get(algo,algo)} auth={auth_sz}B aux={aux_sz}B flags={flags} "
          f"(hashtree_disabled={'Y' if flags&1 else 'N'}, verification_disabled={'Y' if flags&2 else 'N'}) "
          f"rollback={u64(112)} release='{rel}' 非零字节占比={nz}%")
    print(f"  hash={hash_sz}B sig={sig_sz}B 内嵌公钥={pk_sz}B(公钥偏移={pk_off})")
    base = 256 + auth_sz + desc_off
    end = base + desc_sz
    off = base
    n = 0
    while off + 16 <= end:
        tag, size = struct.unpack(">QQ", d[off:off+16])
        body = d[off+16:off+16+size]
        n += 1
        if tag == 0:  # property
            klen, vlen = struct.unpack(">QQ", body[:16])
            key = body[16:16+klen].split(b"\x00")[0].decode("utf-8","replace")
            val = body[16+klen:16+klen+vlen].split(b"\x00")[0].decode("utf-8","replace")
            print(f"  [{n:02d}] PROPERTY {key} = {val}")
        elif tag == 1:  # hashtree
            dm_ver = struct.unpack(">I", body[:4])[0]
            img_sz, tree_off, tree_sz = struct.unpack(">QQQ", body[4:28])
            dbs, hbs, fecr = struct.unpack(">III", body[28:40])
            fec_off, fec_sz = struct.unpack(">QQ", body[40:56])
            halg = body[56:88].split(b"\x00")[0].decode()
            nlen, slen, rlen, hflags = struct.unpack(">IIII", body[88:104])
            name = body[164:164+nlen].decode("utf-8","replace")
            root = body[164+nlen:164+nlen+rlen]
            print(f"  [{n:02d}] HASHTREE {name:<14} image={img_sz:>12,}B dm_verity={dm_ver} alg={halg} block={dbs}/{hbs} fec_roots={fecr} flags={hflags}")
            print(f"        root_digest={root.hex()}")
        elif tag == 2:  # hash
            img_sz = struct.unpack(">Q", body[:8])[0]
            halg = body[8:40].split(b"\x00")[0].decode()
            nlen, slen, dglen, hflags = struct.unpack(">IIII", body[40:56])
            name = body[116:116+nlen].decode("utf-8","replace")
            digest = body[116+nlen:116+nlen+dglen]
            print(f"  [{n:02d}] HASH {name:<14} image={img_sz:>12,}B alg={halg} flags={hflags}")
            print(f"        digest={digest.hex()}")
        elif tag in (3, 4) and size > 500:  # chain (变体: tag=4)
            rloc, nlen, klen = struct.unpack(">III", body[:12])
            name = body[76:76+nlen].decode("utf-8","replace")
            kbits = struct.unpack(">I", body[76+nlen:76+nlen+4])[0] if len(body) >= 76+nlen+4 else 0
            print(f"  [{n:02d}] CHAIN {name:<14} rollback_location={rloc} RSA位长={kbits} 公钥{klen}B(内嵌)")
        elif tag == 4:
            kflags, clen = struct.unpack(">II", body[:8])
            print(f"  [{n:02d}] KERNEL_CMDLINE flags={kflags} '{body[8:8+clen].decode('utf-8','replace')}'")
        else:
            print(f"  [{n:02d}] UNKNOWN tag={tag} size={size}")
        off += (16 + size + 7) // 8 * 8
    if n == 0:
        print("  (无描述符)")
    print()

for p in sys.argv[1:]:
    parse(p)
