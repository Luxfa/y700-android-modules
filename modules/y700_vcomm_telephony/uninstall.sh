#!/system/bin/sh
# Magisk 从 App 内卸载本模块时执行。
# 本模块唯一留下的非模块态是历史上写过的 persist.adb.tcp.port（v7 起已不再写）。
[ -n "$(getprop persist.adb.tcp.port)" ] && setprop persist.adb.tcp.port ""
setprop service.adb.tcp.port ""
stop adbd
start adbd
