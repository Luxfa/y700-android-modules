#!/system/bin/sh
# 开机只重放"原厂存不住"的那一样：饱和度覆盖。
# 色温不在此重放 —— 它是系统设置项（secure:general_color_temperature），自己会留着；
# 重放反而会在下次开机顶掉用户之后在设置页里的自行修改（11-26 用户裁定走 A 方案）。
# 判据只看运行态：Global saturation 的 Activated（100 档时它是 false，所以这个判据能证伪）。

DIR=/data/adb/y700_color
PRO=$DIR/profile.conf
OFF=$DIR/off
LOG=/data/local/tmp/y700_color_tune.log
SAY_DEFAULT_SAT=95

say() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"
  [ "$(wc -l <"$LOG")" -gt 200 ] && { tail -n 200 "$LOG" >"$LOG.t" && mv "$LOG.t" "$LOG"; }
}

xf() { dumpsys SurfaceFlinger 2>/dev/null | grep -ao 'colorTransformMatrix=\[[^]]*\]\[[^]]*\]\[[^]]*\]' | head -1; }
sat_live() { dumpsys color_display 2>/dev/null | sed -n '/Global saturation:/,+1p' | grep -aq 'Activated: true'; }

i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  i=$((i + 1))
  [ $i -gt 90 ] && break
  sleep 2
done
sleep 10

if [ -f "$OFF" ]; then say "档位=manual，交还系统，本次不重放"; exit 0; fi
sat=$(sed -n 's/^saturation=//p' "$PRO" 2>/dev/null)
nm=$(sed -n 's/^name=//p' "$PRO" 2>/dev/null)
if [ -z "$sat" ]; then
  printf 'name=soft\ncolor_temp=1.0,0.994,0.987\nsaturation=95\n' > "$PRO"
  sat=$SAY_DEFAULT_SAT
  nm=soft
  say "档位文件缺失，已按默认 soft 建档"
fi
say "触发（等开机 ${i}x2 秒 + 10 秒缓冲）档位=$nm 只重放饱和度=$sat（色温不归本模块管）"

n=0
while [ $n -lt 5 ]; do
  n=$((n + 1))
  cmd color_display set-saturation "$sat"
  rc=$?
  sleep 2
  if [ "$sat" = "100" ] || sat_live; then
    say "饱和度 $sat 就位（第 $n 次，rc=$rc）矩阵: $(xf)"
    exit 0
  fi
  say "第 $n 次核对不过（rc=$rc，饱和=$sat），重试"
done
say "五次都没过 —— 别当已生效，查 ColorDisplayService"
