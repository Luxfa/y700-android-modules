#!/bin/sh
# 游戏画质探针 —— 量"游戏实际渲染尺寸 + 真实合成帧率"，一把尺子前后对比
# 用法: sh 03_脚本与模块/自检取证/游戏画质探针.sh [包名关键字] [采样秒] [ip:5555]
#   默认 com.tencent.tmgp.pubgmhd / 10 秒 / 192.0.2.10:5555
# 读数必须在游戏画面内进行；营地开关拨动后需回到对局才反映到渲染尺寸。
ROOT=$(cd "$(dirname "$0")/../.." && pwd) || exit 1
cd "$ROOT" || exit 1
PKG=${1:-com.tencent.tmgp.pubgmhd}
SEC=${2:-10}
DEV=${3:-192.0.2.10:5555}

adb -s "$DEV" get-state >/dev/null 2>&1 || adb connect "$DEV" >/dev/null 2>&1
if ! adb -s "$DEV" get-state >/dev/null 2>&1; then
  echo "连不上 $DEV（息屏会掉无线 adb：先亮屏，再重试一次）"; exit 1
fi

{
  echo "PKG='$PKG'"
  echo "SEC=$SEC"
  cat <<'EOS'
#!/system/bin/sh
export PATH=/system/bin:/vendor/bin:$PATH
L="SurfaceView\\[$PKG"
FR() { dumpsys SurfaceFlinger 2>/dev/null | grep -a -A8 "$L" | grep -a -m1 -o 'frame=[0-9]*' | cut -d= -f2; }
GV() { dumpsys SurfaceFlinger 2>/dev/null | grep -a -A14 "$L" | grep -a -m1 -o "$1"; }
A=$(FR); sleep "$SEC"; B=$(FR)
echo "包名: $PKG  采样 ${SEC}s"
echo "前台: $(dumpsys window 2>/dev/null | grep -a -m1 mCurrentFocus | sed 's/.*=//;s/}.*//')"
if [ -z "$A" ] || [ -z "$B" ]; then
  echo "读数失败: 目标层不在屏上（前值=$A 后值=$B）—— 切进游戏画面再跑"; exit 1
fi
echo "渲染尺寸: $(GV 'geomBufferSize=\[[^]]*\]')"
echo "放大倍率: $(GV 'toDisplayTransform={[^}]*}')"
echo "帧计数: $A -> $B  差值=$((B - A))  ⇒ 合成 fps=$(awk -v a="$A" -v b="$B" -v s="$SEC" 'BEGIN{printf "%.1f",(b-a)/s}')"
echo "显示档: $(dumpsys SurfaceFlinger 2>/dev/null | grep -a -m1 -o 'renderRate=[0-9.]* Hz')  $(dumpsys display 2>/dev/null | grep -a -m1 -o 'mActiveModeId=[0-9]*')"
echo "判读: 1144x720=720p 桶 / 1720x1080=1080p 桶；fps 取层 frame 计数增量，只有对局内读数才算画质档证据。"
rm -f "$0"
EOS
} > 临时存档/.gq_probe.sh

export MSYS_NO_PATHCONV=1
adb -s "$DEV" push 临时存档/.gq_probe.sh /data/local/tmp/gq.sh >/dev/null 2>&1 || { echo "推送失败"; rm -f 临时存档/.gq_probe.sh; exit 1; }
adb -s "$DEV" shell su -c "sh /data/local/tmp/gq.sh; rm -f /data/local/tmp/gq.sh"
rm -f 临时存档/.gq_probe.sh
