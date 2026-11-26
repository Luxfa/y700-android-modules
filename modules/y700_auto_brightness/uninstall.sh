#!/system/bin/sh
# Magisk 从 App 内卸载本模块时执行。
# 注意：手工 rm -rf 模块目录不会触发本脚本，那种情况下需自行杀掉 daemon.sh 并恢复 screen_brightness_mode。
p=$(cat /data/local/tmp/y700_ab.pid 2>/dev/null)
case "$(tr '\0' ' ' </proc/$p/cmdline 2>/dev/null)" in *daemon.sh*) kill "$p" ;; esac
rm -f /data/local/tmp/y700_ab.pid /data/local/tmp/y700_ab.win
ORIGST=/data/adb/y700_ab.orig_mode
if [ -f "$ORIGST" ]; then
  v=$(cat "$ORIGST" 2>/dev/null)
  case "$v" in 0 | 1) settings put system screen_brightness_mode "$v" ;; esac
  rm -f "$ORIGST"
fi
