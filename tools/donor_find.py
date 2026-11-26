#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""donor_find.py — 在供体 EROFS 镜像里按名字递归找文件/目录（只读）。

用法:
  python donor_find.py <image> <关键字> [关键字2 ...]
自证: 关键字用 "apk" 或 "etc"，命中 0 条说明遍历有问题。
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from erofs_read import Erofs

TYP = {0: "?", 1: "f", 2: "d", 3: "c", 4: "b", 5: "p", 6: "s", 7: "l"}
stats = {"dirs": 0, "files": 0, "skipped": {}, "depth_max": 0}


def walk(img, nid, path, keys, hits, depth=0):
    if depth > 10:
        return
    try:
        inode = img.inode(nid)
    except Exception as e:
        stats["skipped"]["inode:" + str(e)[:40]] = stats["skipped"].get("inode:" + str(e)[:40], 0) + 1
        return
    try:
        entries = list(img.list_dir(inode))
    except NotImplementedError as e:
        k = "list_dir:" + str(e)[:48]
        stats["skipped"][k] = stats["skipped"].get(k, 0) + 1
        return
    except Exception as e:
        k = "list_dir:" + type(e).__name__
        stats["skipped"][k] = stats["skipped"].get(k, 0) + 1
        return
    stats["dirs"] += 1
    stats["depth_max"] = max(stats["depth_max"], depth)
    for name, child, ft in entries:
        if name in (".", ".."):
            continue
        full = path + "/" + name
        low = name.lower()
        if ft == 2:
            walk(img, child, full, keys, hits, depth + 1)
        else:
            stats["files"] += 1
        if any(k in low for k in keys):
            hits.append((TYP.get(ft, "?"), full))


def main():
    img = Erofs(sys.argv[1])
    keys = [k.lower() for k in sys.argv[2:]]
    hits = []
    walk(img, img.rootnid, "", keys, hits)
    print(f"== {os.path.basename(sys.argv[1])} 遍历目录={stats['dirs']} 文件={stats['files']} "
          f"最大深度={stats['depth_max']} 跳过={sum(stats['skipped'].values())} ==")
    for k, v in list(stats["skipped"].items())[:5]:
        print(f"   跳过原因 x{v}: {k}")
    for t, p in hits:
        print(f"[{t}] {p}")


if __name__ == "__main__":
    main()
