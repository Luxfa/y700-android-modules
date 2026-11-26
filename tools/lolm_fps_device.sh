#!/system/bin/sh
# 帧率专用采样器 v2
# 为什么 250ms：SurfaceFlinger --latency 每层只留 64 帧历史，144Hz 下仅 0.44 秒
#   ⇒ 采样间隔必须 < 0.44s 才不会漏帧；取 250ms 留一倍余量
# 为什么去重：相邻两次 dump 的时间戳必然重叠，按"上屏时刻唯一值"计数才是真帧数
PKG=com.tencent.lolm
OUT=/data/local/tmp/y700_lolm_fps.csv
RAW=/data/local/tmp/y700_lolm_present.raw
PIDF=/data/local/tmp/y700_lolm_fps.pid
[ -f "$PIDF" ] && { p=$(cat "$PIDF" 2>/dev/null); case "$(tr '\0' ' ' </proc/$p/cmdline 2>/dev/null)" in *lolm_fps*) exit 0 ;; esac; }
echo $$ >"$PIDF"
[ -f "$OUT" ] || echo "epoch,seq,fps,frames,p50_ms,p95_ms,worst_ms,refresh_hz" >"$OUT"
: >"$RAW"

N=0; L=""; nextres=0; acc=0; miss=0

while true; do
  e=$(date +%s)

  if [ -z "$L" ] || [ "$e" -ge "$nextres" ] || [ "$miss" -ge 4 ]; then
    # 只认真正出画的 (BLAST) 层：--list 里 "Background for …"/"Bounds for …" 排在前面，
    # 用 grep -m1 会抓到那种不产帧的层，导致 latency 只回一行、帧距全 0
    L=$(dumpsys SurfaceFlinger --list 2>/dev/null | grep -E "SurfaceView\[$PKG[^]]*\]\(BLAST\)" | head -1 \
        | sed -E 's/^RequestedLayerState\{//; s/ parentId=.*//; s/\}$//')
    [ -z "$L" ] && L=$(dumpsys SurfaceFlinger --list 2>/dev/null | grep "SurfaceView\[$PKG" \
        | grep -vE "Background for|Bounds for" | head -1 | sed -E 's/^RequestedLayerState\{//; s/ parentId=.*//; s/\}$//')
    nextres=$((e + 10))
  fi

  if [ -n "$L" ]; then
    lat=$(dumpsys SurfaceFlinger --latency "$L" 2>/dev/null)
    if [ "$(echo "$lat" | wc -l)" -ge 3 ]; then
      rhz=$(echo "$lat" | head -1 | cut -f1)
      echo "$lat" | tail -n +2 | cut -f2 >>"$RAW"
      miss=0
    else
      miss=$((miss + 1))
    fi
  fi

  acc=$((acc + 1))
  if [ "$acc" -ge 8 ]; then
    t1=$(date +%s)
    set -- $(sort -n -u "$RAW" 2>/dev/null | awk '
      { v[n++] = $1 }
      END {
        if (n < 2) { printf "0 0 0 0 0 0"; exit }
        for (i = 1; i < n; i++) { d = v[i] - v[i - 1]; if (d > 0 && d < 500000000) { a[m++] = d } }
        for (i = 1; i < m; i++) { k = a[i]; for (j = i - 1; j >= 0 && a[j] > k; j--) a[j + 1] = a[j]; a[j + 1] = k }
        p50 = m > 0 ? a[int(m * 0.5)] / 1000000 : 0
        p95 = m > 0 ? a[int(m * 0.95)] / 1000000 : 0
        w   = m > 0 ? a[m - 1] / 1000000 : 0
        # 帧率用时间戳跨度自校准：整数秒做窗口会把实际 2.9~3.2 秒截成 2 秒，直接放大 fps
        span = (v[n - 1] - v[0]) / 1000000000
        printf "%d %.3f %.3f %.3f %d %.2f", n - 1, p50, p95, w, v[n - 1], (span > 0 ? (n - 1) / span : 0)
      }')
    fr=${1:-0}; p50=${2:-0}; p95=${3:-0}; worst=${4:-0}; lastt=${5:-0}; fps=${6:-0}
    N=$((N + 1))
    echo "$t1,$N,$fps,$fr,$p50,$p95,$worst,${rhz:-0}" >>"$OUT"
    # 滚动窗口：只保留最后一次已结算的时间戳之后者，避免与下一窗重复计数
    if [ "$lastt" -gt 0 ]; then
      awk -v m="$lastt" '$1 > m' "$RAW" >"$RAW.t" 2>/dev/null && mv "$RAW.t" "$RAW"
    fi
    acc=0
  fi

  sleep 0.25
done
