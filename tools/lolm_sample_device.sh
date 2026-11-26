#!/system/bin/sh
# 英雄联盟手游对局采样器：跑在设备侧后台，避免 adb 往返抖动影响被测对象
# 轻字段每 5s（纯 sysfs/settings 读）；重组件每 15s（4 次 dumpsys），其余行沿用上次值
OUT=/data/local/tmp/y700_lolm_sample.csv
PIDF=/data/local/tmp/y700_lolm_sample.pid
# GPU 瞬时频率节点（gpuclk/clock_mhz）在这颗内核上恒报地板 160MHz（Adreno 帧间打盹回落），
# 不可用作"实际频率"；真实分布看这个旁路：gpu_clock_stats 是 18 档各自的驻留时间，
# 与 gpu_available_frequencies 一一对应，离线做相邻两次差值即可算驻留加权频率。
GPUD=/data/local/tmp/y700_lolm_gpustats.log
PKG=com.tencent.lolm
N=0

[ -f "$PIDF" ] && { p=$(cat "$PIDF" 2>/dev/null); case "$(tr '\0' ' ' </proc/$p/cmdline 2>/dev/null)" in *lolm_sample*) exit 0 ;; esac; }
echo $$ >"$PIDF"

HDR="epoch,seq,fg_pkg,fps_win,frames_total,janky_total,janky_pct,cpu0,cpu3,cpu6,cpu7,gpu_hz,gpu_busy,gpu_total,thermal_status,skin1,skin2,batt_temp,batt_level,refresh_req,brightness,bmode"
[ -f "$OUT" ] || echo "$HDR" >"$OUT"

fps=0; frames=0; janky=0; jpct=0.0
ptherm="-1,0,0"; pbatt="0,0"; fg="-"; refresh=0
pframes=0

while true; do
  N=$((N + 1))
  e=$(date +%s)

  c0=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
  c3=$(cat /sys/devices/system/cpu/cpu3/cpufreq/scaling_cur_freq 2>/dev/null)
  c6=$(cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_cur_freq 2>/dev/null)
  c7=$(cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq 2>/dev/null)
  ghz=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null)
  set -- $(cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null)
  busy=${1:-0}; tot=${2:-0}
  br=$(settings get system screen_brightness 2>/dev/null)
  bm=$(settings get system screen_brightness_mode 2>/dev/null)

  if [ $((N % 3)) -eq 1 ]; then
    g=$(dumpsys gfxinfo "$PKG" 2>/dev/null)
    frames=$(echo "$g" | grep -m1 "Total frames rendered" | grep -oE "[0-9]+")
    janky=$(echo "$g" | grep -m1 "Janky frames" | awk '{print $3}')
    jpct=$(echo "$g" | grep -m1 "Janky frames" | awk '{print $4}' | tr -cd '0-9.')
    [ -z "$frames" ] && frames=0
    [ -z "$janky" ] && janky=0
    [ -z "$jpct" ] && jpct=0.0
    d=$((frames - pframes)); [ $d -lt 0 ] && d=0
    fps=$((d / 15)); pframes=$frames

    t=$(dumpsys thermalservice 2>/dev/null)
    ts=$(echo "$t" | grep -m1 "Thermal Status" | grep -oE "[0-9]+")
    # 只要 mType=3（SKIN）那两条；同名多条是历史值，取各名字最后一条才是现值
    sk=$(echo "$t" | grep "Temperature{" | grep "mType=3" | grep -oE "mValue=[0-9.]+" | cut -d= -f2 | tail -2 | tr '\n' ',' | sed 's/,$//')
    [ -z "$ts" ] && ts=-1
    case "$sk" in *,*) ;; *) sk="${sk:-0},0" ;; esac
    ptherm="$ts,$sk"

    b=$(dumpsys battery 2>/dev/null)
    bt=$(echo "$b" | grep -m1 "temperature:" | grep -oE "[0-9]+")
    bl=$(echo "$b" | grep -m1 "^  level:" | grep -oE "[0-9]+")
    pbatt="${bt:-0},${bl:-0}"

    fg=$(dumpsys window 2>/dev/null | grep -m1 "mCurrentFocus=" | tr ' ' '\n' | grep -m1 -E '[A-Za-z0-9._]+/' | cut -d/ -f1)
    [ -z "$fg" ] && fg="-"

    refresh=$(dumpsys display 2>/dev/null | grep -m1 -oE "mAppRequestBaseModeRefreshRate=[0-9.]+" | grep -oE "[0-9.]+")
    [ -z "$refresh" ] && refresh=0

    echo "$(date +%s) $(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null | tr -cd '0-9') $(cat /sys/class/kgsl/kgsl-3d0/gpu_clock_stats 2>/dev/null | tr '\n' ' ')" >>"$GPUD"
  fi

  echo "$e,$N,$fg,$fps,$frames,$janky,$jpct,$c0,$c3,$c6,$c7,$ghz,$busy,$tot,$ptherm,$pbatt,$refresh,$br,$bm" >>"$OUT"
  sleep 5
done
