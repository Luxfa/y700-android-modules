import sys, struct, re
sys.stdout.reconfigure(encoding="utf-8")
p = sys.argv[1]
d = open(p, "rb").read()
print("=== %s  大小 %,d ===".replace("%,d", "{:,}").format(p, len(d)) if False else "=== %s 大小 %d ===" % (p, len(d)))

# 1) EDK2 变量记录扫描：StartId=0x55AA, State 之后是 GUID+DataSize+VendorGuid+NameSize+Name
hits = []
for i in range(len(d) - 64):
    if d[i] == 0x55 and d[i+1] == 0xAA:
        state = d[i+2]
        guid = d[i+8:i+24]
        try:
            datasize = struct.unpack("<Q", d[i+24:i+32])[0]
            namesize = struct.unpack("<Q", d[i+56:i+64])[0]
        except Exception:
            continue
        if 0 < namesize <= 256 and namesize % 2 == 0 and 0 <= datasize <= 0x20000 and i+64+namesize <= len(d):
            nm = d[i+64:i+64+namesize].decode("utf-16-le", "replace").split("\x00")[0]
            if re.fullmatch(r"[A-Za-z0-9_\-]{2,40}", nm or ""):
                hits.append((i, state, guid.hex(), nm, datasize))
print("EDK2 记录形态命中:", len(hits))
for h in hits[:60]:
    print("  @0x%06x state=0x%02x vendor=%s name=%-28s datalen=%d" % (h[0], h[1], h[2], h[3], h[4]))

# 2) 纯文本扫（ASCII 与 UTF-16LE）
def ascii_runs(buf, m=5):
    out, cur = [], []
    for i, b in enumerate(buf):
        if 32 <= b < 127: cur.append(b)
        else:
            if len(cur) >= m: out.append((i - len(cur), bytes(cur).decode("ascii")))
            cur = []
    return out
def utf16_runs(buf, m=4):
    out = []
    i = 0
    cur = []
    start = 0
    while i + 1 < len(buf):
        ch = buf[i] if buf[i+1] == 0 else None
        if ch is not None and 32 <= ch < 127:
            if not cur: start = i
            cur.append(chr(ch))
        else:
            if len(cur) >= m: out.append((start, "".join(cur)))
            cur = []
        i += 2
    return out

KW = re.compile(r"(boot|slot|retry|unboot|fail|reason|log|debug|serial|ver|active|abc|misc|lenovo|zui|hwid|sn|unlock|avb|vbmeta|rollback|sec|mode|cmd)", re.I)
print("\n=== ASCII 命中关键词的行（前 50）===")
n = 0
for off, s in ascii_runs(d):
    if KW.search(s):
        print("  @0x%06x %r" % (off, s[:120])); n += 1
    if n >= 50: break
print("=== UTF-16LE 命中关键词的行（前 50）===")
n = 0
for off, s in utf16_runs(d):
    if KW.search(s):
        print("  @0x%06x %r" % (off, s[:120])); n += 1
    if n >= 50: break
