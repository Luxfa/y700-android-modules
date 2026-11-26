#!/usr/bin/env bash
# 一键退回原厂默认（两轮瘦身全部复原）。用法：sh 瘦身_复原.sh [设备序列号]
# 分区从未改动，install-existing 即可全部找回；复原后需重启一次。
set -u
DEV="${1:-YOUR_SERIAL}"
S="/debug_ramdisk/su -c"
UNINST="com.motorola.mobiledesktop com.lenovo.menu_assistant.hd com.lenovo.lfh.tianjiao.tablet com.zui.asr.sherpa com.zui.ai.lens com.zui.ai.aiservice com.zui.pengen com.lenovo.screensaver com.tblenovo.ue.config com.zui.browser com.lenovo.penservice"
echo "== 重新安装 11 个（用户级卸载过的）"
for p in $UNINST; do
  adb -s "$DEV" shell "$S \"cmd package install-existing --user 0 $p\"" 2>&1 | tr -d '\r' | sed "s/^/  /"
done
echo "== 复验 installed 状态（应全部 true）"
adb -s "$DEV" shell "$S \"for p in $UNINST; do echo -n \\\"\$p \\\"; dumpsys package \$p | grep -am1 'User 0' | grep -o 'installed=[a-z]*'; done\"" 2>&1 | tr -d '\r'
echo "== 复原后请重启：adb -s $DEV reboot"
