#!/system/bin/sh
# 目标：让音乐流的后处理登记里多一条杜比 DAP（apply effect="dap"）
# 约束（实测得出，勿改）：
#   1) ColorOS 音效页面要的效果名 41f6c0f4-… 必须由底层库自报，配置文件写不出来，
#      所以本模块不碰页面，只走底层登记。
#   2) 生效文件是 sku_canoe/audio_effects_config.xml（判据：dlb_music_listener 只在此文件且运行时确在）。
#   3) 全程 bind mount，分区文件不动；umount + 重启音频服务即回退。
MODDIR=/data/adb/modules/y700_dolby_bridge
CFG="$MODDIR/audio_effects_config.xml"
TGT=/vendor/etc/audio/sku_canoe/audio_effects_config.xml
LOG=/data/local/tmp/y700_dolby_bridge.log
say() { echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"; }

chmod 644 "$CFG"
chcon u:object_r:vendor_configs_file:s0 "$CFG" 2>/dev/null

if grep -aq 'apply effect="dap"' "$TGT"; then
  say "杜比登记已在位，跳过覆盖"
else
  if mount -o bind "$CFG" "$TGT"; then
    say "覆盖挂载完成（早于音频服务启动，无需重启服务）"
  else
    say "覆盖挂载失败，保持原厂原状"
  fi
fi
