#!/system/bin/sh
# Magisk 从 App 内卸载本模块时执行。
p=$(cat /data/local/tmp/y700_charge_bridge.pid 2>/dev/null)
case "$(tr '\0' ' ' </proc/$p/cmdline 2>/dev/null)" in *bridge.sh*) kill "$p" ;; esac
rm -f /data/local/tmp/y700_charge_bridge.pid
# 交还给系统自己的充电判断：恢复充电（本模块唯一写面就是这个节点）
echo 1 >/sys/class/power_supply/battery/charging_enabled 2>/dev/null
