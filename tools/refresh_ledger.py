#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""一次性刷新 00_救生包/资产清单.md 里 11-24 已过期的行（数字均已磁盘实测）。"""
import io

P = "00_救生包/资产清单.md"
s = io.open(P, encoding="utf-8").read()
before = s

pairs = [
    ("| 调研报告 | 02_调研/ | 线刷包渠道/移植包渠道/搜寻实录/C17解剖/官方包解剖 共 5 份 |",
     "| 调研报告 | 02_调研/ | **共 7 份**（不含模板）：线刷包渠道 / 移植包渠道 / 搜寻实录 / C17包解剖 / 官方包2.5.10.055解剖 / 自制移植调研_修订 / 会话考古_未落盘事实。旧版写 5 份已过期 |"),
    ("| flash_9008.sh / backup_partitions.sh / analyze_c17.py | 03_脚本与模块/ | 9008 编排/dd 备份/包解剖工具 |",
     "| flash_9008.sh / backup_partitions.sh / analyze_c17.py | 03_脚本与模块/ | 9008 编排 / dd 备份 / 包解剖工具 |\n"
     "| **y700_rollback.sh** | 03_脚本与模块/ → 装机于设备 `/data/adb/y700_rollback.sh` | **模块态一键回退器**（杀守护 + 恢复 settings + 交还充电控制 + 按需清 TCP adb） |\n"
     "| donor_find.py / erofs_read.py / cpio_extract.py / vbmeta_parse.py / super_lpdump.py / lp_carve.py / ptbl_var_parse.py / uefivar_parse.py / logfs_decode.py | 03_脚本与模块/ | 只读解析工具链（供体镜像递归检索、EROFS/cpio/vbmeta/super/GPT/UEFI/logfs） |"),
    ("| 分区表+getvar | 05_备份索引/ | by-name 141 项 + getvar 326 行（043 时代存档） |",
     "| 分区表+getvar | 05_备份索引/ | by-name 141 项 + **getvar 326 行**（11-24 `wc -l` 实测确认；STATUS 旧版写的“280 项”作废。043 时代存档） |"),
    ("本地 main 分支，已提交至 `58e3719`（2.5 刷入成功全记录）。二进制大文件不入库（.gitignore），文档/脚本全量跟踪。",
     "本地 main 分支。**本文件不引用具体提交号**（历史教训：写过“已提交至 58e3719”，两天后就过期了）——要确认当前 HEAD 请现跑 `git log --oneline -1`。\n"
     "11-24 入库两批共 **1187 件文本资产**（二期拆解文档与证据、临时存档 9008/审计文本件、sepolicy cil 策略源、备份索引 getvar 与 backup_log），二进制派生件（super 镜像、ko/mbn/elf/cpio 解包树、供体包）一律不入库。"),
]
for old, new in pairs:
    if old not in s:
        print("未命中（跳过）: %s" % old[:48])
    s = s.replace(old, new, 1)

s = s + """
## 七、交付态资产（11-24 新增登记）

> 这些不属于“救砖物料”，但属于“恢复当前可用交付”所必需，丢了要重做工程，所以一并入总账。

| 资产 | 位置 | 实测核对 | 角色 |
|---|---|---|---|
| 五个 Magisk 模块 | 仓库 `03_脚本与模块/modules/`，装机于设备 `/data/adb/modules/` | 设备侧版本 `auto_brightness v5 / charge_bridge v2 / game_policy v1 / identity_hygiene v2 / vcomm_telephony v7`，均无 disable/remove 标记 | 当前交付态的行为层（亮度/充电/性能放行/身份/通信共享） |
| Telecom.apk | `05_备份索引/vcomm_apk_inuse/` | 16,939,847 B，sha256 `c9e2465e8b4570dee16a9811dc2e98f2c0294e0a58a5ecdefcf1538beff59c5e` | vcomm 模块载荷；**平板上那份是模块自己挂载的，不能作为离线来源**（相位G1-4） |
| ims.apk | `05_备份索引/vcomm_apk_inuse/` | 1,021,414 B，sha256 `93c199d707cd6dd908b82e3d24d7aa3bdc15f28aa858aae9b9b14c362ca1f48c` | 同上。两件哈希与 相位Z 记录逐字节一致 |
| 分区备份 | `分区备份_20261123.7z` | 14,358,243,927 B（`ls -l` 实测） | dd 级回退主路径 |
| sn.img | `sn.img` | 356 B，sha256 前缀实测 `df3b7645438f`（与本文 五、 所记一致） | BL 解锁料（一机一码，**禁止外传**） |

**当前两条回退路径（11-24 复核仍成立）**：① 9008 刷官方 2.5.10.055 全量（本目录 Tool.7z，实测 12,249,699,674 B）② 9008 刷 C17 锚点（移植包 zip，实测 8,843,876,836 B）。两条均在历史会话中实测过 10 分钟内可达。
"""

io.open(P, "w", encoding="utf-8").write(s)
print("已写入，字符数 %d -> %d" % (len(before), len(s)))
