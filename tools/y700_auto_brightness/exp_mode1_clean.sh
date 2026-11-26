#!/usr/bin/env bash
# 干净版实验：确认本机在 mode=1 下，系统（AOSP 或 OPLUS DDC）到底会不会自己写亮度
DEV="${DEV:-192.0.2.10:5555}"
export MSYS2_ARG_CONV_EXCL='*'
LOG=/data/local/tmp/y700_auto_brightness.log

S(){ adb -s "$DEV" shell "$1" 2>&1 | tr -d '\r'; }
A(){ adb -s "$DEV" shell "su -c \"$1\"" 2>&1 | tr -d '\r'; }

echo "=== 1. 精确杀守护（用 pidfile，不靠 cmdline 模糊匹配）==="
p=$(A "cat /data/local/tmp/y700_ab.pid" | head -1 | tr -dc '0-9')
echo "pidfile=$p  cmdline=$(A "tr '\\0' ' ' < /proc/$p/cmdline" | head -1)"
A "kill $p"
sleep 4
echo "杀后 ps 里的 daemon：$(S "su -c 'ps -A -o PID,ARGS'" | grep -c 'daemon.sh')"

echo "=== 2. 确认日志不再增长（守护真死）==="
n1=$(A "wc -l < $LOG" | head -1 | tr -dc '0-9'); sleep 8; n2=$(A "wc -l < $LOG" | head -1 | tr -dc '0-9')
echo "日志行数 $n1 -> $n2（相等即守护已停）"

echo "=== 3. 基线 ==="
S "settings get system screen_brightness_mode; settings get system screen_brightness"
S "dumpsys display | grep -m1 -E 'mAmbientLux='"
S "dumpsys display | grep -m1 -E 'mAppliedAutoBrightness='"

echo "=== 4. 打开 mode=1，观察 60 秒（守护不在，任何亮度变化都只能来自系统）==="
S "settings put system screen_brightness_mode 1"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sleep 5
  b=$(S "settings get system screen_brightness" | head -1)
  d=$(S "dumpsys display | grep -m1 'Display Brightness='")
  al=$(S "dumpsys display | grep -m1 'mAmbientLux='")
  ap=$(S "dumpsys display | grep -m1 'mAppliedAutoBrightness='")
  lx=$(S "dumpsys display | grep -A1 CurrentLuxResult | tail -1")
  echo "  t+$((i*5))s settings亮度=$b | ${d} | ${al} ${ap}"
  echo "          ${lx}"
done

echo "=== 5. 收尾：mode=0 并重启守护 ==="
S "settings put system screen_brightness_mode 0"
A "setsid nohup sh /data/adb/modules/y700_auto_brightness/daemon.sh >> $LOG 2>&1 &"
sleep 5
echo "守护实例数=$(S "su -c 'ps -A -o PID,ARGS'" | grep -c 'daemon.sh')  pidfile=$(A 'cat /data/local/tmp/y700_ab.pid' | head -1)"
