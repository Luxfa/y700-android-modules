#!/system/bin/sh
# 单一变量：只把音乐流后处理多加一行 apply effect="dap"，其余全交回原厂
MODDIR=/data/adb/modules/y700_dolby_min
CFG="$MODDIR/audio_effects_config.xml"
TGT=/vendor/etc/audio/sku_canoe/audio_effects_config.xml
LOG=/data/local/tmp/y700_dolby_min.log
say() { echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"; }

chmod 644 "$CFG"
chcon u:object_r:vendor_configs_file:s0 "$CFG" 2>/dev/null

if grep -aq 'apply effect="dap"' "$TGT"; then
  say "已在位，不重复挂载"
else
  if mount -o bind "$CFG" "$TGT"; then
    say "覆盖挂载完成（早于音频服务启动）"
  else
    say "覆盖挂载失败，保持原厂原状"
  fi
fi
