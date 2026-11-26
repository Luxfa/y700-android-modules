#!/system/bin/sh
# 兜底：post-fs-data 没赶在音频服务前挂上时补挂一次，并只重启音频相关服务
MODDIR=/data/adb/modules/y700_dolby_min
TGT=/vendor/etc/audio/sku_canoe/audio_effects_config.xml
LOG=/data/local/tmp/y700_dolby_min.log
say() { echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"; }

i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  i=$((i + 1)); [ $i -gt 90 ] && break; sleep 2
done
sleep 10

if grep -aq 'apply effect="dap"' "$TGT"; then
  say "开机检查：DAP 登记在位"
else
  sh "$MODDIR/post-fs-data.sh"
  if grep -aq 'apply effect="dap"' "$TGT"; then
    say "晚到覆盖完成，重启音频服务重读配置"
    setprop ctl.restart vendor.audio-hal-aidl
    sleep 3
    setprop ctl.restart audioserver
  else
    say "覆盖仍未成功，本次开机保持原厂原状"
  fi
fi
