#!/usr/bin/env bash
# 实验：本机在 screen_brightness_mode=1 下，系统自己会不会驱动亮度（会不会与模块抢写面）
# 步骤：停模块守护 -> 记基线 -> 置 mode=1 -> 每 5 秒采样共 40 秒 -> 恢复 mode=0 并重启守护
DEV="${DEV:-192.0.2.10:5555}"
export MSYS2_ARG_CONV_EXCL='*'
A(){ adb -s "$DEV" shell "su -c '$1'" 2>&1 | tr -d '\r'; }
S(){ adb -s "$DEV" shell "$1" 2>&1 | tr -d '\r'; }

echo "=== 1. 停模块守护（按 cmdline 精确匹配）==="
A 'for p in /proc/[0-9]*; do if tr "\0" " " < $p/cmdline 2>/dev/null | grep -q y700_auto_brightness/daemon.sh; then echo kill $(basename $p); kill $(basename $p); fi; done'

echo "=== 2. 基线 ==="
S 'settings get system screen_brightness_mode; settings get system screen_brightness'
S "dumpsys display | grep -E 'mAmbientLux=|mAppliedAutoBrightness=' | head -3"
S "dumpsys display | grep -A1 CurrentLuxResult | tail -1"

echo "=== 3. 打开 mode=1，采样 8 次共 40 秒 ==="
S 'settings put system screen_brightness_mode 1'
for i in 1 2 3 4 5 6 7 8; do
  sleep 5
  b=$(S 'settings get system screen_brightness' | head -1)
  ap=$(S "dumpsys display | grep -m1 -E 'mAppliedAutoBrightness='" | head -1)
  al=$(S "dumpsys display | grep -m1 'mAmbientLux='" | head -1)
  lx=$(S "dumpsys display | grep -A1 CurrentLuxResult | tail -1" | head -1)
  raw=$(S "dumpsys sensorservice" 2>/dev/null | awk '/Ambient Light Sensor Non-wakeup: last/{f=1;next} f==1{ if($0 ~ /wall=/){line=$0} else if(line!=""){exit} } END{ sub(/.*\)/,"",line); sub(/,.*/,"",line); gsub(/[ ,]/,"",line); print line }')
  echo "  t+$((i*5))s 亮度=$b raw_lux=$raw ${al} ${ap}"
  echo "          ${lx}"
done

echo "=== 4. 恢复：mode=0 并重启守护 ==="
S 'settings put system screen_brightness_mode 0'
A 'setsid nohup sh /data/adb/modules/y700_auto_brightness/daemon.sh >>/data/local/tmp/y700_auto_brightness.log 2>&1 &'
sleep 4
A 'for p in /proc/[0-9]*; do if tr "\0" " " < $p/cmdline 2>/dev/null | grep -q y700_auto_brightness/daemon.sh; then echo "守护已回 pid=$(basename $p)"; fi; done'
S 'settings get system screen_brightness_mode; settings get system screen_brightness'
