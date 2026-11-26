#!/usr/bin/env bash
# 原生自动亮度行为取样：杀守护 -> mode=1 -> 每 10 秒记 (finalLux, Display Brightness) 共 12 次
DEV="${DEV:-192.0.2.10:5555}"
export MSYS2_ARG_CONV_EXCL='*'
S(){ adb -s "$DEV" shell "$1" 2>&1 | tr -d '\r'; }
A(){ adb -s "$DEV" shell "su -c \"$1\"" 2>&1 | tr -d '\r'; }
LOG=/data/local/tmp/y700_auto_brightness.log

p=$(A "cat /data/local/tmp/y700_ab.pid" | head -1 | tr -dc '0-9')
A "kill $p"; sleep 3
echo "守护实例=$(S "su -c 'ps -A -o PID,ARGS'" | grep -c 'daemon.sh')  已置 mode=1"
S "settings put system screen_brightness_mode 1"
for i in $(seq 1 12); do
  sleep 10
  b=$(S "dumpsys display | grep -m1 'Display Brightness='" | head -1 | sed 's/.*=//;s/[^0-9.]//g')
  lx=$(S "dumpsys display | grep -A1 CurrentLuxResult | tail -1" | head -1)
  fl=$(echo "$lx" | sed 's/.*finalLux=//;s/ .*//')
  rl=$(echo "$lx" | sed 's/.*realTimeLux=//;s/ .*//')
  st=$(S "dumpsys display | grep -m1 'mAppliedAutoBrightness='" | head -1 | sed 's/.*=//')
  pct=$(awk -v x="$b" 'BEGIN{printf "%.1f%%", x/8191*100}')
  echo "  t+$((i*10))s 亮度=${b} (${pct}) realLux=${rl} finalLux=${fl} appliedAuto=${st}"
done
echo "=== 收尾：mode=0 并恢复守护 ==="
S "settings put system screen_brightness_mode 0"
A "setsid nohup sh /data/adb/modules/y700_auto_brightness/daemon.sh >> $LOG 2>&1 &"
sleep 4
echo "守护实例=$(S "su -c 'ps -A -o PID,ARGS'" | grep -c 'daemon.sh')"
