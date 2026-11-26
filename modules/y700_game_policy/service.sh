#!/system/bin/sh
MODDIR=/data/adb/modules/y700_game_policy
MP=/product/bin/magiskpolicy
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
LOG=/data/local/tmp/y700_game_policy.log
n=0; b=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  if "$MP" --live "$line" >/dev/null 2>&1; then n=$((n+1)); else b=$((b+1)); fi
done < "$MODDIR/sepolicy.rule"
echo "$(date '+%m-%d %H:%M:%S') policy applied ok=$n fail=$b" >> "$LOG"
