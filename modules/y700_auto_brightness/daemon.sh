#!/system/bin/sh
LOG=/data/local/tmp/y700_auto_brightness.log
say(){
  echo "$(date "+%m-%d %H:%M:%S") $*" >> "$LOG"
  # 日志轮转：超 1MB 只保留尾部 256KB
  [ "$(stat -c %s "$LOG" 2>/dev/null)" -gt 1048576 ] && { tail -c 262144 "$LOG" >"$LOG.t" 2>/dev/null && mv "$LOG.t" "$LOG"; }
}
PIDF=/data/local/tmp/y700_ab.pid
if [ -f "$PIDF" ]; then
  p=$(cat "$PIDF" 2>/dev/null)
  case "$(tr '\0' ' ' </proc/$p/cmdline 2>/dev/null)" in *daemon.sh*) exit 0 ;; esac
fi
echo $$ >"$PIDF"
i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  i=$((i + 1))
  [ $i -gt 90 ] && break
  sleep 2
done
sleep 10
# 值域自适应：本机标定是 0-8191（背光=值*0.4，sys.oplus.multibrightness=8191）。
# 不直接照搬系统报的 max —— 万一它是 0-255 那类另一套标度，混用会把亮度写错。
# 做法：确认报来的 max 可信（数字、不小于当前值、不低于 100）才采用，然后所有
# 步长/阈值都按 MAX 等比推导，保证同一标度内自洽。
MAXR=$(settings get system screen_brightness_max 2>/dev/null)
CURV=$(settings get system screen_brightness 2>/dev/null)
case "$MAXR" in '' | *[!0-9]*) MAXR=0 ;; esac
case "$CURV" in '' | *[!0-9]*) CURV=0 ;; esac
if [ "$MAXR" -ge 100 ] && [ "$MAXR" -ge "$CURV" ]; then MAX=$MAXR; else MAX=8191; fi
MINR=$(settings get system screen_brightness_min 2>/dev/null)
case "$MINR" in '' | *[!0-9]*) MINR=0 ;; esac
if [ "$MINR" -gt 0 ] && [ "$MINR" -lt "$MAX" ]; then MIN=$MINR; else MIN=$((MAX / 37)); fi
[ "$MIN" -lt 1 ] && MIN=1
DEADBAND=$((MAX / 68))
STEP=$((MAX / 16))
[ "$DEADBAND" -lt 1 ] && DEADBAND=1
[ "$STEP" -lt 1 ] && STEP=1
HOLD=120
dsys(){ timeout 5 dumpsys "$@" 2>/dev/null; }
GAMECONF=/data/adb/modules/y700_auto_brightness/games.conf
say "start pid=$$ max=$MAX min=$MIN"

get_lux(){
  dsys sensorservice | awk '/Ambient Light Sensor Non-wakeup: last/{f=1;next} f==1{ if($0 ~ /wall=/){line=$0} else if(line!=""){exit} } END{ if(line!=""){ sub(/.*\)/,"",line); sub(/,.*/,"",line); gsub(/[ ,]/,"",line); print line } }'
}

map_lux(){
  awk -v l="$1" -v mn="$MIN" -v mx="$MAX" 'BEGIN{
    split("0 10 30 60 100 150 210 255 999999", X, " ")
    split("0.027 0.06 0.14 0.26 0.42 0.62 0.78 1.0 1.0", Y, " ")
    r = Y[9]
    for (i = 1; i < 9; i++) { if (l <= X[i+1]) { r = Y[i] + (Y[i+1]-Y[i]) * (l-X[i]) / (X[i+1]-X[i]); break } }
    v = r * mx
    if (v < mn) v = mn
    if (v > mx) v = mx
    printf "%d", v
  }'
}

# 前台是否游戏：命中 games.conf 就完全不动亮度（游戏空间自己会锁）
# 每轮只做一次 dumpsys window 落盘再查文件：避免三连全量 dump 拖慢循环，
# 也避免 `grep -m1` 提前关闭管道把 dumpsys 打成 broken pipe 丢数据。
WINF=/data/local/tmp/y700_ab.win
in_game(){
  dsys window >"$WINF"
  # 锁屏态 mFocusedApp 不更新，会残留上一个游戏包；此时不参与游戏判定，交给环境光继续跟随
  grep -a 'isKeyguardShowing=true' "$WINF" >/dev/null 2>&1 && return 1
  t=$(grep -a -m1 'mFocusedApp=' "$WINF" | tr ' ' '\n' | grep -m1 -E '[A-Za-z0-9._]+/[A-Za-z0-9.$]')
  [ -z "$t" ] && t=$(grep -a -m1 'mCurrentFocus' "$WINF" | tr ' ' '\n' | grep -m1 -E '[A-Za-z0-9._]+/[A-Za-z0-9.$]')
  fg=${t%%/*}
  [ -z "$fg" ] && return 1
  grep -qxF "$fg" "$GAMECONF" 2>/dev/null && return 0
  return 1
}

# settings get 在键未设时返回字符串 null，必须挡在算术之前，否则 $((cur-last)) 会误判成手动让路
num(){ case "$1" in ''|*[!0-9]*) echo "$2" ;; *) echo "$1" ;; esac; }

# 记录"模块介入前"的自动调节开关，供卸载时恢复。
# 注意：`settings get` 失败时会把 "cmd: Failure calling service settings..." 打到 **stdout**，
# 直接重定向进文件就会存下垃圾（实测踩过），所以必须先取回并只接受 0/1。
ORIGST=/data/adb/y700_ab.orig_mode
if [ ! -f "$ORIGST" ]; then
  v=$(settings get system screen_brightness_mode 2>/dev/null)
  case "$v" in
    0 | 1) echo "$v" >"$ORIGST" ;;
  esac
fi
settings put system screen_brightness_mode 0
last=$(num "$(settings get system screen_brightness)" "$MIN")
hold=0
ingamewas=0
while true; do
  w=$(dsys power | grep -m1 'mWakefulness=' | cut -d= -f2)
  if [ "$w" != "Awake" ]; then sleep 3; continue; fi
  # 系统"自动调节"若被手动打开会与本执行器打架，每轮强制归零
  if [ "$(settings get system screen_brightness_mode)" != "0" ]; then
    settings put system screen_brightness_mode 0
    say "系统自动调节被打开 -> 已强制关闭"
  fi
  if in_game; then
    if [ "$ingamewas" != "1" ]; then say "game foreground=$fg -> hold brightness"; ingamewas=1; fi
    sleep 3; continue
  fi
  if [ "$ingamewas" = "1" ]; then
    say "game exited -> resume"
    ingamewas=0
    last=$(num "$(settings get system screen_brightness)" "$last")
  fi
  cur=$(num "$(settings get system screen_brightness)" "$last")
  if [ -n "$cur" ] && [ "$cur" != "null" ]; then
    d=$((cur - last)); [ $d -lt 0 ] && d=$((-d))
    if [ $d -gt 5 ]; then
      say "manual override cur=$cur last=$last -> hold ${HOLD}s"
      hold=$((HOLD/3)); last=$cur
    fi
  fi
  if [ $hold -gt 0 ]; then hold=$((hold-1)); sleep 3; continue; fi
  lux=$(get_lux)
  if [ -z "$lux" ]; then sleep 3; continue; fi
  tgt=$(map_lux "$lux")
  diff=$((tgt - last)); [ $diff -lt 0 ] && nd=$((-diff)) || nd=$diff
  if [ "$nd" -ge "$DEADBAND" ]; then
    if [ "$nd" -gt "$STEP" ]; then
      if [ "$diff" -gt 0 ]; then nv=$((last + STEP)); else nv=$((last - STEP)); fi
    else
      nv=$tgt
    fi
    [ $nv -lt $MIN ] && nv=$MIN
    [ $nv -gt $MAX ] && nv=$MAX
    settings put system screen_brightness "$nv"
    say "lux=$lux target=$tgt applied=$nv (was $last)"
    last=$nv
  fi
  sleep 3
done
