#!/usr/bin/env bash
# 亮度改走系统原生：停守护 -> 给模块打 disable 标记（可一键恢复，不删文件）-> 打开原生自动调节 -> 验证不复关
DEV="${DEV:-192.0.2.10:5555}"
export MSYS2_ARG_CONV_EXCL='*'
A(){ adb -s "$DEV" shell "su -c \"$1\"" 2>&1 | tr -d '\r'; }
S(){ adb -s "$DEV" shell "$1" 2>&1 | tr -d '\r'; }

echo "=== 1. 精确停守护（pidfile）==="
p=$(A "cat /data/local/tmp/y700_ab.pid" | head -1 | tr -dc '0-9')
A "kill $p" >/dev/null; sleep 3
echo "守护实例数=$(A "ps -A -o PID,ARGS" | grep -c 'daemon.sh')（应为 0）"

echo "=== 2. 打 disable 标记（开机不再拉起，文件全留）==="
A "touch /data/adb/modules/y700_auto_brightness/disable"
A "ls /data/adb/modules/y700_auto_brightness" | tr ' ' '\n' | grep -E 'disable|remove' || echo "（没看到标记？）"

echo "=== 3. 打开系统原生自动调节 ==="
S "settings put system screen_brightness_mode 1"
S "settings get system screen_brightness_mode"

echo "=== 4. 验证 90 秒内不被复关（每 10 秒一次）==="
for ((i=1; i<=9; i++)); do
  sleep 10
  m=$(S "settings get system screen_brightness_mode" | head -1)
  b=$(S "settings get system screen_brightness" | head -1)
  echo "  t+$((i*10))s mode=$m 亮度=$b"
done

echo "=== 5. 收尾读数 ==="
S "dumpsys display | grep -m1 'mAppliedAutoBrightness='" | head -1
S "dumpsys display | grep -A1 CurrentLuxResult | tail -1" | head -1
A "tail -3 /data/local/tmp/y700_auto_brightness.log"
