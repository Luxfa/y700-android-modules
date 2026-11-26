#!/usr/bin/env bash
# PC 侧一键抓自检快照：连机 → 推脚本 → 跑 → 拉回本地 → 打印判读行
# 用法：sh 抓快照.sh [设备 ip:5555 或序列号] [--save]
#   默认落到 临时存档/（不进版本库，因为里面有 SSID、蓝牙设备名这类本机标识）
#   加 --save 才落到 04_日志与分析/（确认要当证据留存时用）
# 全程只读，不改设备任何设置。
set -u
DEV="192.0.2.10:5555"
SAVE=0
for a in "$@"; do
  case "$a" in
    --save) SAVE=1 ;;
    *) DEV="$a" ;;
  esac
done
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M)"
# Windows 版 adb 看不懂 /d/... 这种 POSIX 路径（MSYS_NO_PATHCONV=1 时不会被转换），
# 所以一律先 cd 到项目根再用相对路径落文件。
cd "$ROOT" || { echo "[失败] 进不去项目根 $ROOT"; exit 1; }
if [ "$SAVE" = 1 ]; then OUT="04_日志与分析/自检快照_${STAMP}.txt"; else OUT="临时存档/自检快照_${STAMP}.txt"; fi
export MSYS_NO_PATHCONV=1

if ! adb devices 2>/dev/null | grep -aq "^$DEV"; then
  echo "[连接] $DEV 不在列表，先 adb connect（息屏会掉无线 adb，这是正常现象）"
  adb connect "$DEV" >/dev/null 2>&1
  sleep 1
  if ! adb devices 2>/dev/null | grep -aq "^$DEV"; then
    echo "[失败] 连不上 $DEV。请确认手机已开机、在同一网络，或插 USB 线后用 serial 作参数"
    exit 1
  fi
fi

TMP="临时存档/_snap_dev.sh"
mkdir -p 临时存档
tr -d '\r' < "$HERE/快照.sh" > "$TMP"
adb -s "$DEV" push "$TMP" /data/local/tmp/y700_sc.sh >/dev/null 2>&1
rm -f "$TMP"

echo "[抓取] 设备侧运行中（约 10~20 秒，全程只读）"
adb -s "$DEV" shell su -c "sh /data/local/tmp/y700_sc.sh > /dev/null; rm -f /data/local/tmp/y700_sc.sh" 2>&1 | tail -2
adb -s "$DEV" pull /data/local/tmp/y700_selfcheck_report.txt "$OUT" >/dev/null 2>&1

if [ ! -s "$OUT" ]; then
  echo "[失败] 报告没拉回来。手动看设备侧文件：adb -s $DEV shell su -c 'cat /data/local/tmp/y700_selfcheck_report.txt'"
  exit 1
fi
echo "[完成] 报告已存 $OUT"
echo
echo "===== 判读要点（只列这 14 行，细节看报告文件）====="
grep -a '^判读\|崩溃计数\|开机至今\|身份\|模块  \|音频门禁' "$OUT"
