#!/usr/bin/env bash
#===============================================================================
# backup_partitions.sh — TB323FU（序列号 YOUR_SERIAL）关键分区 dd 全量备份
#
# 用法（Git Bash，Windows 侧运行）：
#   ./backup_partitions.sh [--dry-run] [--full] [--out <目录>]
#     --dry-run   只打印将执行的命令，不执行、不检查设备
#     --full      在必做清单基础上追加：super(20GB)、devcfg_a、modem_a、init_boot_a
#     --out DIR   备份输出目录（默认：当前目录下 backup_YYYYMMDD_HHMMSS）
#
# 依赖：
#   - adb（在 PATH 中，且只有一个设备在线）
#   - 设备已解锁 + 已 root（adb shell su -c id 返回 uid=0）
#   - bash + coreutils（Git Bash 自带 sha256sum/head/tr/wc）
#
# 数据来源（2026-11-22 实测存档，05_备份索引/）：
#   分区节点：分区表_byname_20261122.txt
#   期望大小：fastboot_getvar_all_20261122.txt（partition-size）
#
# 风险与纪律：
#   - 本脚本只读取设备分区，不写设备；但 dd 读错节点仍可能出错，清单已按存档逐字核对
#   - 仅供本机 YOUR_SERIAL（ZUXOS 2.0.12.043_ST）使用，禁止将本机备份刷入他人设备
#   - 备份文件含 persist（WiFi/传感器校准）与 modemst/fsg（基带），属敏感物料，勿外传
#   - super 约 20GB，确保输出盘有足够空间且用 USB3 直连
#===============================================================================
set -u

DRY_RUN=0
FULL=0
OUT_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --full)    FULL=1 ;;
        --out)     shift; OUT_DIR="${1:-}" ;;
        --out=*)   OUT_DIR="${1#--out=}" ;;
        -h|--help) grep '^#' "$0" | head -30; exit 0 ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
    shift
done

# --- 备份清单：名称:设备节点:期望大小(十六进制，来自 getvar 存档) ---
# 必做（当前活动槽位 A（ZUXOS 2.5.10.055，2026-11-23 实测 by-name/blockdev）+ 无槽位关键分区）
REQUIRED_LIST="
persist:/dev/block/sda3:0x2000000
oemowninfo:/dev/block/sda1:0x100000
modemst1:/dev/block/sdf2:0x400000
modemst2:/dev/block/sdf3:0x400000
fsg:/dev/block/sdf4:0x400000
fsc:/dev/block/sdf5:0x20000
metadata:/dev/block/sda10:0x4000000
init_boot_a:/dev/block/sde29:0x800000
boot_a:/dev/block/sde12:0x6000000
vendor_boot_a:/dev/block/sde24:0x6000000
dtbo_a:/dev/block/sde16:0x4800000
vbmeta_a:/dev/block/sde15:0x10000
vbmeta_system_a:/dev/block/sda8:0x10000
devcfg_a:/dev/block/sde13:0x20000
modem_a:/dev/block/sde6:0x15E00000
"
# 可选（--full）：super + b 槽对照（043 时代旧件）
OPTIONAL_LIST="
super:/dev/block/sda7:0x500000000
init_boot_b:/dev/block/sde70:0x800000
boot_b:/dev/block/sde54:0x6000000
vendor_boot_b:/dev/block/sde66:0x6000000
dtbo_b:/dev/block/sde58:0x4800000
vbmeta_b:/dev/block/sde57:0x10000
vbmeta_system_b:/dev/block/sda9:0x10000
devcfg_b:/dev/block/sde55:0x20000
modem_b:/dev/block/sde48:0x15E00000
"

BACKUP_LIST="$REQUIRED_LIST"
[ "$FULL" -eq 1 ] && BACKUP_LIST="$REQUIRED_LIST $OPTIONAL_LIST"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "===== DRY-RUN：将执行以下备份（不实际执行）====="
    echo "清单条目数：$(echo "$BACKUP_LIST" | grep -c ':')"
    echo "$BACKUP_LIST" | tr ' ' '\n' | grep -v '^$' | while IFS=: read -r name node size_hex; do
        size_dec=$((size_hex))
        file="${name}.img"
        printf '%-16s 节点=%-16s 期望大小=%12d 字节 (%s)\n' "$name" "$node" "$size_dec" "$size_hex"
        echo "  命令: adb exec-out \"su -c 'dd if=$node 2>/dev/null'\" > $file"
    done
    echo "================================================"
    echo "校验步骤（执行时）：大小比对 getvar 存档 -> sha256sum -> 试读前1KB确认非全零"
    exit 0
fi

# ---------- 前置检查 ----------
command -v adb >/dev/null 2>&1 || { echo "错误：找不到 adb，请先配置 PATH" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "错误：找不到 sha256sum（Git Bash 应自带）" >&2; exit 1; }

adb get-state 2>/dev/null | grep -q "^device$" || { echo "错误：没有 adb 设备在线（需开机且已授权调试）" >&2; exit 1; }

SU_ID=$(adb shell su -c id 2>/dev/null | tr -d '\r')
echo "$SU_ID" | grep -q "uid=0" || { echo "错误：su 未获得 root（$SU_ID）。设备须已解锁并刷入 Magisk 等 root" >&2; exit 1; }
echo "设备在线，root 确认：$SU_ID"

[ -n "$OUT_DIR" ] || OUT_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR" || { echo "错误：无法创建输出目录 $OUT_DIR" >&2; exit 1; }
echo "输出目录：$OUT_DIR"

CSV_FILE="$OUT_DIR/backup_log.csv"
echo "备份项,文件路径,大小,SHA256,试读验证,电脑位置,云盘位置,日期" > "$CSV_FILE"
DATE_STR=$(date +%F)

FAIL=0
echo "$BACKUP_LIST" | tr ' ' '\n' | grep -v '^$' | while IFS=: read -r name node size_hex; do
    size_dec=$((size_hex))
    file="$OUT_DIR/${name}.img"
    echo "----> 备份 $name（$node，期望 $size_dec 字节）"
    if ! adb exec-out "su -c 'dd if=$node 2>/dev/null'" > "$file"; then
        echo "错误：dd 读取出错（$name）" >&2
        echo "$name,$file,FAILED,,失败,$OUT_DIR,,$DATE_STR" >> "$CSV_FILE"
        continue
    fi
    # 校验 1：实际大小 vs getvar 存档
    actual=$(stat -c %s "$file")
    if [ "$actual" -ne "$size_dec" ]; then
        echo "错误：$name 大小不符，实际 $actual，期望 $size_dec（已保留文件待人工核对）" >&2
        echo "$name,$file,$actual,,失败(大小不符),$OUT_DIR,,$DATE_STR" >> "$CSV_FILE"
        continue
    fi
    # 校验 2：试读前 1KB 确认非全零
    nonzero=$(head -c 1024 "$file" | tr -d '\0' | wc -c)
    read_ok="失败(全零)"
    [ "$nonzero" -gt 0 ] && read_ok="通过"
    # 校验 3：SHA256
    sha=$(sha256sum "$file" | awk '{print $1}')
    echo "      OK  $name  $actual 字节  SHA256=$sha  试读=$read_ok"
    echo "$name,$file,$actual,$sha,$read_ok,$OUT_DIR,,$DATE_STR" >> "$CSV_FILE"
done

# while 循环在子 shell 中，重新统计失败项
grep -c "失败" "$CSV_FILE" >/dev/null 2>&1 && FAIL=$(grep -c "失败" "$CSV_FILE")
TOTAL=$(tail -n +2 "$CSV_FILE" | wc -l)
echo "================================================"
echo "完成：$TOTAL 个分区已登记，$FAIL 个失败/异常。登记表：$CSV_FILE"
echo "下一步：将登记表内容誊入 05_备份索引/备份登记表.md，并完成云盘双备份。"
