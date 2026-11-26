#!/system/bin/sh
# Keep a plain-TCP adb listener alive across reboots so the porting bench can
# reconnect without re-pairing on screen.
# 11-24 审计修正：不再写 persist.adb.tcp.port —— persist 属性不归模块管，
# 删了模块也永不复原，等于给 TCP adb 开了永久敞口。改成每次开机由本模块
# 重新设定非持久属性，删模块 + 重启即自然关闭；同时清掉历史版本留下的 persist 值。
i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  i=$((i + 1))
  [ $i -gt 90 ] && break
  sleep 2
done
sleep 5
setprop service.adb.tcp.port 5555
if [ -n "$(getprop persist.adb.tcp.port)" ]; then
  setprop persist.adb.tcp.port ""
fi
stop adbd
start adbd
