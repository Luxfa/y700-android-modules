#!/system/bin/sh
MODDIR=/data/adb/modules/y700_auto_brightness
# setsid：脱离调用会话，手动远程拉起时不会被 su 会话回收（本会话实测踩过）
setsid sh "$MODDIR/daemon.sh" >/dev/null 2>&1 &
