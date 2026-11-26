#!/system/bin/sh
MODDIR=/data/adb/modules/y700_charge_bridge
i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  i=$((i + 1))
  [ $i -gt 90 ] && break
  sleep 2
done
sleep 8
# setsid：脱离调用会话，防止手动远程拉起时随 su 会话被回收
setsid sh "$MODDIR/bridge.sh" >/dev/null 2>&1 &
