#!/usr/bin/env bash
# 遮光响应测试 v2：原生(mode=1)接管下，每 4 秒记一次 (raw lux / finalLux / 系统亮度)
# v1 教训：后台任务 PATH 里没有 seq，for 循环被整体跳过 —— 改用 bash 内置 C 型循环
DEV="${DEV:-192.0.2.10:5555}"
N="${N:-45}"
export MSYS2_ARG_CONV_EXCL='*'
OUT="$(dirname "$0")/../../临时存档/亮度/shutter_test.txt"
A(){ adb -s "$DEV" shell "su -c \"$1\"" 2>&1 | tr -d '\r'; }

p=$(A "cat /data/local/tmp/y700_ab.pid" | head -1 | tr -dc '0-9')
A "kill $p" >/dev/null; sleep 3
n=$(A "ps -A -o PID,ARGS" | grep -c 'daemon.sh')
adb -s "$DEV" shell 'settings put system screen_brightness_mode 1' >/dev/null 2>&1
{ echo "守护实例=$n（应为0） mode=1 已置，开始取样 ${N} 轮 × 4s"; } >"$OUT"

for ((i=1; i<=N; i++)); do
  line=$(adb -s "$DEV" shell 'dumpsys display | grep -E "Display Brightness=" | head -1; dumpsys display | grep -A1 CurrentLuxResult | tail -1; dumpsys sensorservice | awk "/Ambient Light Sensor Non-wakeup: last/{f=1;next} f==1{ if(\$0 ~ /wall=/){l=\$0} else if(l!=\"\"){exit} } END{print l}"' 2>&1 | tr -d '\r')
  b=$(echo "$line" | grep -oE 'Brightness=[0-9.]+' | head -1 | sed 's/.*=//')
  fl=$(echo "$line" | grep -oE 'finalLux=[0-9.]+' | head -1 | sed 's/.*=//')
  raw=$(echo "$line" | grep -oE '\) [0-9.]+' | head -1 | tr -d ') ')
  pct=$(awk -v x="${b:-0}" 'BEGIN{printf "%.0f%%", x/8191*100}')
  echo "t+$((i*4))s raw=${raw} finalLux=${fl} 系统亮度=${b} (${pct})" >>"$OUT"
  sleep 4
done

echo "=== 收尾：mode=0 并恢复守护 ===" >>"$OUT"
adb -s "$DEV" shell 'settings put system screen_brightness_mode 0' >/dev/null 2>&1
A "setsid nohup sh /data/adb/modules/y700_auto_brightness/daemon.sh >> /data/local/tmp/y700_auto_brightness.log 2>&1 &" >/dev/null
sleep 4
echo "守护实例=$(A "ps -A -o PID,ARGS" | grep -c 'daemon.sh')" >>"$OUT"
