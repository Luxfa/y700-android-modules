import sys, struct
sys.stdout.reconfigure(encoding="utf-8")

path = sys.argv[1]
d = open(path, "rb").read()
print("文件 %s 大小 %d" % (path, len(d)))

# PTBL 头
print("\n=== PTBL 头 ===")
print("magic=%s ver=%s header_size=%d ?=%d ?=%d ?=%d" % (
    d[0:4], struct.unpack("<HH", d[4:8]), struct.unpack("<I", d[8:12])[0],
    struct.unpack("<I", d[12:16])[0], struct.unpack("<I", d[16:20])[0], struct.unpack("<I", d[20:24])[0]))

recs = [i for i in range(len(d) - 8) if d[i:i+4] == b"VAR2"]
print("\n=== VAR2 变量记录 %d 条 ===" % len(recs))
for i in recs:
    try:
        ver_maj, ver_min = struct.unpack("<HH", d[i+4:i+8])
        total, data_off, attr_a, name_off = struct.unpack("<IIII", d[i+8:i+24])
        vguid = d[i+24:i+40]
        g = "%08x-%04x-%04x-%s" % (struct.unpack("<I", vguid[0:4])[0], struct.unpack("<H", vguid[4:6])[0],
                                   struct.unpack("<H", vguid[6:8])[0], vguid[8:16].hex())
        # 名字：UTF-16LE 到 NUL；再往后是数据
        nm = d[i+40:i+40+200]
        # 有些记录在名字前还有 u32 属性与 u16 名称长度
        attr = struct.unpack("<I", d[i+40:i+44])[0]
        nlen = struct.unpack("<H", d[i+44:i+46])[0]
        name = d[i+46:i+46+max(nlen, 2)].decode("utf-16-le", "replace").split("\x00")[0]
        if not (2 <= len(name) <= 64 and name.isprintable()):
            nlen = struct.unpack("<H", d[i+40:i+42])[0]
            name = d[i+42:i+42+max(nlen, 2)].decode("utf-16-le", "replace").split("\x00")[0]
            attr = None
        # 数据区：记录尾
        body = d[i:i+total] if 16 <= total <= 0x4000 and i+total <= len(d) else d[i:i+64]
        dat = body[-32:] if len(body) > 32 else body
        print("@0x%05x total=%-6d attr=%-10s name=%-24s vendorGUID=%s  尾32B=%s" %
              (i, total, str(attr), name[:24], g, dat.hex()))
    except Exception as e:
        print("@0x%05x 解析失败 %s" % (i, e))

print("\n=== DStr 记录（数据流）%d 条 ===" % sum(1 for i in range(len(d)-4) if d[i:i+4] == b"DStr"))
for i in [k for k in range(len(d) - 4) if d[k:k+4] == b"DStr"][:20]:
    print("@0x%05x %s" % (i, d[i:i+40].hex()))
