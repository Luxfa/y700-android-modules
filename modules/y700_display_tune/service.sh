#!/system/bin/sh
# 开机等系统起稳后重放显示色彩参数。逻辑都在 apply.sh，这里只管时机。

MODDIR=/data/adb/modules/y700_display_tune
LOG=/data/local/tmp/y700_display_tune.log
say() { echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"; }

i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  i=$((i + 1))
  [ $i -gt 90 ] && break
  sleep 2
done

# 显示服务与 ColorDisplayService 起稳前下命令可能被开机流程覆盖；15 秒是待重启实测的初值。
sleep 15
say "service 触发（boot_completed 等待 $((i * 2)) 秒 + 15 秒缓冲）"
sh "$MODDIR/apply.sh"
