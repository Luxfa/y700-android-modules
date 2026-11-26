#!/bin/sh
# 营地开关 A/B 指纹取样：sh 临时存档/ab_take.sh <A|B> [ip:5555]
# 只读取证（不写设备任何配置），产物落 /data/local/tmp/ab_<tag>.txt 并拉回 临时存档/
ROOT=$(cd "$(dirname "$0")/.." && pwd) || exit 1
cd "$ROOT" || exit 1
TAG=${1:-A}
DEV=${2:-192.0.2.10:5555}
[ -d 临时存档 ] || mkdir -p 临时存档

adb -s "$DEV" get-state >/dev/null 2>&1 || adb connect "$DEV" >/dev/null 2>&1
adb -s "$DEV" get-state >/dev/null 2>&1 || { echo "连不上 $DEV（先亮屏再重试）"; exit 1; }

{
  echo "TAG='$TAG'"
  cat <<'EOS'
#!/system/bin/sh
export PATH=/system/bin:/vendor/bin:$PATH
PKG=com.tencent.tmgp.pubgmhd
OUT=/data/local/tmp/ab_$TAG.txt
L="SurfaceView\\[$PKG"
SFL=$(dumpsys SurfaceFlinger 2>/dev/null)
{
echo "### 0 时间与前台"
date '+%F %T'
dumpsys window 2>/dev/null | grep -a -m1 -E 'mCurrentFocus'
echo "### 1 游戏渲染层（完整块）"
echo "$SFL" | grep -a -A16 "$L" | grep -a -E 'geomBufferSize|geomContentCrop|toDisplayTransform|frame=|bounds=|desiredHdr|colorTransform|hasProtected|outputLayer' | head -14
echo "### 2 显示档与刷新率"
echo "$SFL" | grep -a -m1 -o 'renderRate=[0-9.]* Hz'
dumpsys display 2>/dev/null | grep -a -m1 -o 'mActiveModeId=[0-9]*'
dumpsys display 2>/dev/null | grep -a -m1 -o 'mPhysicalDisplayMode=[0-9]*'
echo "### 3 帧计数（10 秒增量）"
A=$(echo "$SFL" | grep -a -A8 "$L" | grep -a -m1 -o 'frame=[0-9]*' | cut -d= -f2)
sleep 10
B=$(dumpsys SurfaceFlinger 2>/dev/null | grep -a -A8 "$L" | grep -a -m1 -o 'frame=[0-9]*' | cut -d= -f2)
echo "frame $A -> $B  delta=$((B - A))"
echo "### 4 游戏侧文件指纹（大小+mtime，营地权益落地处）"
find /data/data/$PKG -maxdepth 3 \( -name 'hawk*' -o -name '*.ini' -o -name '*.json' -o -name '*.xml' -o -name '*config*' -o -name '*settings*' \) 2>/dev/null | head -40 | while read f; do
  stat -c '%s %y %n' "$f" 2>/dev/null
done
echo "### 5 营地侧文件指纹"
find /data/data/com.tencent.gamehelper.pg -maxdepth 3 -type f 2>/dev/null | head -30 | while read f; do
  stat -c '%s %y %n' "$f" 2>/dev/null
done
echo "### 6 游戏与营地的版本/uid/flags"
dumpsys package $PKG 2>/dev/null | grep -a -m1 -E 'versionName'
dumpsys package com.tencent.gamehelper.pg 2>/dev/null | grep -a -m1 -E 'versionName'
echo "### 7 相关 settings 键"
for k in app_auto_resolution oplus_games_auto_resolution_switch_key screen_brightness_mode; do
  echo "$k = $(settings get system $k 2>/dev/null) / $(settings get global $k 2>/dev/null)"
done
echo "### 8 相关属性（含游戏/画质/帧率关键字）"
getprop 2>/dev/null | grep -a -E 'game|frame_rate|resolution|perf|gpu' | sort > /data/local/tmp/ab_${TAG}_prop.txt
wc -l < /data/local/tmp/ab_${TAG}_prop.txt
grep -a -E 'game_default_frame_rate|frame_rate_override|perf_level|gpu' /data/local/tmp/ab_${TAG}_prop.txt | head -12
echo "### 9 游戏进程与线程 CPU（当前负载）"
top -b -n 1 2>/dev/null | grep -a -E 'pubgmhd|GameThread|RenderThread' | head -6
echo "### 10 近期日志中的画质/档位关键词"
logcat -d -t 400 2>/dev/null | grep -a -i -E 'resolution|quality|gamehelper|GCloud|hawk|frameRate' | tail -12
echo "### 11 温度快照"
paste -sd' ' /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -c 300
echo ""
echo "### END"
} > "$OUT" 2>&1
chmod 644 "$OUT"
echo "取样完成 tag=$TAG -> $OUT ($(stat -c %s "$OUT") B)"
EOS
} > 临时存档/.ab_take.sh

export MSYS_NO_PATHCONV=1
adb -s "$DEV" push 临时存档/.ab_take.sh /data/local/tmp/ab_take.sh >/dev/null 2>&1 || { echo "推送失败"; exit 1; }
adb -s "$DEV" shell su -c "sh /data/local/tmp/ab_take.sh" 2>&1 | tail -2
adb -s "$DEV" shell su -c "cp /data/local/tmp/ab_$TAG.txt /data/local/tmp/ab_${TAG}_keep.txt" 2>/dev/null
adb -s "$DEV" pull /data/local/tmp/ab_$TAG.txt 临时存档/ab_$TAG.txt >/dev/null 2>&1 && echo "已拉回 临时存档/ab_$TAG.txt"
rm -f 临时存档/.ab_take.sh
