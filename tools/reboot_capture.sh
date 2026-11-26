#!/usr/bin/env bash
# 重启取证：从 adb 一上线起就反复把 logcat 落盘，专抓 boot 期 /system/bin/init 第二实例 SIGABRT 的成因
# 上一轮实况：init abort 在 15:25:22，sys.boot_completed 在 15:25:38 —— 等开机完成再抓就晚了
set -u
export PATH="$PATH:/d/platform-tools"
export MSYS_NO_PATHCONV=1
DEV="${DEV:-192.0.2.10:5555}"
OUT="$(dirname "$0")/../04_日志与分析/开机取证_20261124"
mkdir -p "$OUT"
A(){ adb -s "$DEV" shell "$1" 2>/dev/null | tr -d '\r'; }

echo "=== 重启前 tombstone 快照（用于事后辨认新增）==="
A "su -c 'ls /data/tombstones | grep -E \"^tombstone_[0-9]+\$\" | sort'" >"$OUT/tombstones_before.txt"
echo "已存 $OUT/tombstones_before.txt（$(wc -l <"$OUT/tombstones_before.txt") 件）"
A "date '+%m-%d %H:%M:%S 重启前设备时刻'"
adb -s "$DEV" reboot
echo "reboot 已发出，开始等 adb 上线"

for ((i=1; i<=60; i++)); do
  st=$(adb -s "$DEV" get-state 2>/dev/null | tr -d '\r')
  [ "$st" = "device" ] && { echo "第 ${i} 次轮询：adb 上线"; break; }
  sleep 4
done

# 上线后每 12 秒抢一次全量 logcat，共 10 次（覆盖 boot 前后约 2 分钟）
for ((k=1; k<=10; k++)); do
  f="$OUT/logcat_k${k}.txt"
  A "logcat -d -b all" >"$f"
  n=$(wc -l <"$f")
  bc=$(A "getprop sys.boot_completed")
  echo "采样 $k：$n 行  boot_completed=$bc  $(date '+%H:%M:%S')"
  [ "$bc" = "1" ] && [ "$k" -ge 6 ] && break
  sleep 12
done

echo "=== 合并去重后找 init / crash_dump 现场 ==="
cat "$OUT"/logcat_k*.txt | sort -u >"$OUT/logcat_merged.txt"
grep -nE "Fatal signal|crash_dump|Cmdline|abort message|>>> /system/bin/init|init *:.*(Could not|cannot|failed|Unable)" "$OUT/logcat_merged.txt" \
  | grep -viE "grep -|adbd service requested" | head -40
echo "=== 新增 tombstone ==="
A "su -c 'ls /data/tombstones | grep -E \"^tombstone_[0-9]+\$\" | sort'" >"$OUT/tombstones_after.txt"
comm -13 "$OUT/tombstones_before.txt" "$OUT/tombstones_after.txt"
