#!/system/bin/sh
# 只处理"普通 app 真能读到"的联想残留；不可逆区与网络身份(btaddr/wifiaddr)一律不动。
LOG=/data/local/tmp/y700_identity_hygiene.log
say(){ echo "$(date "+%m-%d %H:%M:%S") $*" >> "$LOG"; }
RP=""
i=0
while [ $i -lt 30 ]; do
  for c in /product/bin/resetprop /debug_ramdisk/resetprop /data/adb/magisk/resetprop; do
    [ -x "$c" ] && RP="$c" && break
  done
  [ -n "$RP" ] && break
  sleep 2; i=$((i+1))
done
if [ -z "$RP" ]; then say "FATAL resetprop not found"; exit 1; fi
j=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  j=$((j + 1))
  [ $j -gt 90 ] && break
  sleep 2
done
say "start rp=$RP"
for kv in brand:OPPO manufacturer:OPPO model:OPD2511 device:OP6546L1 name:OPD2511; do
  k="ro.product.vendor_dlkm.${kv%%:*}"; v="${kv#*:}"
  cur=$(getprop "$k")
  [ -z "$cur" ] && continue
  [ "$cur" = "$v" ] && continue
  if "$RP" -n "$k" "$v"; then say "$k $cur -> $v"; else say "FAILED $k"; fi
done
for k in ro.boot.lenovo.psn ro.boot.lenovo.gsn persist.debug.zui_battery_debug; do
  [ -n "$(getprop "$k")" ] || continue
  if "$RP" --delete "$k"; then say "delete $k"; else say "FAILED del $k"; fi
done
say "done left=$(getprop | grep -ciE 'lenovo|tb323|legion|zui')"
