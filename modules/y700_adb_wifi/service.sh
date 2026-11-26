#!/system/bin/sh
# 开机把 adb 切到 TCP 端口，拔线后也能连（作者 hutao）。
# 端口取自 /data/adb/y700_adb_wifi/port，缺省 5555；有 off 文件则整个跳过。
# 只做一件事，且逐条记 旧值→新值（本项目吃过"静默没生效"的亏）。

DIR=/data/adb/y700_adb_wifi
PORTF=$DIR/port
OFF=$DIR/off
LOG=/data/local/tmp/y700_adb_wifi.log
DEFPORT=5555

say() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"
  [ "$(wc -l <"$LOG")" -gt 120 ] && { tail -n 120 "$LOG" >"$LOG.t" && mv "$LOG.t" "$LOG"; }
}

listening() {
  ss -ltn 2>/dev/null | grep -aq ":$PORT " || netstat -ltn 2>/dev/null | grep -aq ":$PORT "
}

i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  i=$((i + 1))
  [ $i -gt 90 ] && break
  sleep 2
done
sleep 8

if [ -f "$OFF" ]; then say "开关=off，不开无线 adb"; exit 0; fi
PORT=$(cat "$PORTF" 2>/dev/null | tr -dc '0-9')
if [ -z "$PORT" ]; then mkdir -p "$DIR"; echo "$DEFPORT" > "$PORTF"; PORT=$DEFPORT; say "端口文件缺失，按默认 $PORT 建档"; fi

old=$(getprop service.adb.tcp.port)
say "触发（等开机 ${i}x2 秒 + 8 秒缓冲）目标端口=$PORT 旧值 service.adb.tcp.port=[$old]"

n=0
while [ $n -lt 5 ]; do
  n=$((n + 1))
  setprop service.adb.tcp.port "$PORT"
  stop adbd
  sleep 1
  start adbd
  sleep 3
  now=$(getprop service.adb.tcp.port)
  if [ "$now" = "$PORT" ] && listening; then
    say "无线 adb 就位：端口 $PORT 在听（第 $n 次，旧值[$old]→新值[$now]）"
    exit 0
  fi
  say "第 $n 次核对不过（prop=[$now] 在听=$(listening; echo $?)），重试"
done
say "五次都没起监听 —— 别当已生效"
