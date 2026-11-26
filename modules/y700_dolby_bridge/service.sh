#!/system/bin/sh
# 兜底：若 post-fs-data 阶段没能赶在音频服务前挂上，这里补挂并重启音频服务
MODDIR=/data/adb/modules/y700_dolby_bridge
TGT=/vendor/etc/audio/sku_canoe/audio_effects_config.xml
LOG=/data/local/tmp/y700_dolby_bridge.log
say() { echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"; }

i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  i=$((i + 1)); [ $i -gt 90 ] && break; sleep 2
done
sleep 10

if grep -aq 'apply effect="dap"' "$TGT"; then
  say "开机检查：音乐流杜比登记在位"
else
  sh "$MODDIR/post-fs-data.sh"
  if grep -aq 'apply effect="dap"' "$TGT"; then
    say "晚到覆盖完成，重启音频服务使其重新读取配置"
    setprop ctl.restart vendor.audio-hal-aidl
    sleep 3
    setprop ctl.restart audioserver
  else
    say "覆盖仍未成功，本次开机保持原厂原状"
  fi
fi

# 起档位桥监听（页面模式 → 杜比档位）
if [ -f "$MODDIR/watch_profile.sh" ]; then
  sh "$MODDIR/watch_profile.sh" >>/dev/null 2>&1 &
  echo "$(date '+%m-%d %H:%M:%S') 档位桥监听已启动" >>"$LOG"
fi
