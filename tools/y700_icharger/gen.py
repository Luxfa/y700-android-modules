#!/usr/bin/env python3
# 从已还原的 AIDL 码表生成 ICharger 应答服务源码（手写 onTransact，不依赖 aidl 工具链）
# 输入：临时存档/icharger/method_table.txt（code<TAB>名<TAB>返回<TAB>参数）
# 输出：src/com/y700/icharger/Main.java
import io
import os

BASE = os.path.dirname(os.path.abspath(__file__))
TABLE_LOCAL = os.path.join(BASE, 'method_table.tsv')
TABLE = TABLE_LOCAL if os.path.exists(TABLE_LOCAL) else os.path.join(BASE, '..', '..', '临时存档', 'icharger', 'method_table.txt')
OUT = os.path.join(BASE, 'src', 'com', 'y700', 'icharger', 'Main.java')
TPL = os.path.join(BASE, 'Main.java.tpl')

rows = []
for line in io.open(TABLE, encoding='utf-8'):
    p = line.rstrip('\n').split('\t')
    if len(p) < 3 or not p[0].isdigit():
        continue
    rows.append((int(p[0]), p[1], p[2], p[3] if len(p) > 3 else ''))


def case_block(code, toks):
    """逐参数读入临时变量，同时准备 args（原始值）与 shown（日志用字符串）。"""
    decl, objs, shown = [], [], []
    for i, t in enumerate(toks):
        v = 'v%d' % i
        if t == 'int':
            decl.append('int %s = data.readInt();' % v)
            objs.append(v)
            shown.append('String.valueOf(%s)' % v)
        elif t == 'boolean':
            decl.append('int %s = data.readInt();' % v)
            objs.append(v)
            shown.append('String.valueOf(%s != 0)' % v)
        elif t == 'String':
            decl.append('String %s = data.readString();' % v)
            objs.append(v)
            shown.append(v)
        else:
            objs.append('null')
            shown.append('"<%s>"' % t)
    if not toks:
        return '        case %d: args = new Object[0]; shown = new String[0]; break;' % code
    lines = ['        case %d: {' % code]
    for d in decl:
        lines.append('            %s' % d)
    lines.append('            args = new Object[]{ %s };' % ', '.join(objs))
    lines.append('            shown = new String[]{ %s };' % ', '.join(shown))
    lines.append('        } break;')
    return '\n'.join(lines)


case_read = []
names = {}
for code, name, _ret, params in rows:
    names[code] = name
    case_read.append(case_block(code, [t for t in params.split(',') if t]))

src = io.open(TPL, encoding='utf-8').read()
src = src.replace('@@READ_CASES@@', '\n'.join(case_read))
src = src.replace('@@NAME_MAP@@',
                  '\n'.join('        NAMES.put(%d, "%s");' % (c, n) for c, n in sorted(names.items())))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
io.open(OUT, 'w', encoding='utf-8', newline='\n').write(src)
print('生成 %s：方法 %d 个，码 1..%d' % (OUT, len(rows), max(names)))
