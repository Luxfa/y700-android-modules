#!/system/bin/sh
# 把一个杜比档位写进原厂杜比的状态库：整库替换成模块内预置的档位库副本。
# 只改 configuration.Profile 一行，签名与其它表保持出厂原样。
# 用法：sh apply_profile.sh <杜比档位号 0-8>
MODDIR=/data/adb/modules/y700_dolby_bridge
P="$1"
DB=/data/vendor/dolby/dax_sqlite3.db
LOG=/data/local/tmp/y700_dolby_bridge.log
say() { echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"; }
case "$P" in 0|1|2|3|4|5|6|7|8) : ;; *) say "档位号非法 $P，忽略"; exit 1 ;; esac
SRC="$MODDIR/profiles/p$P.db"
[ -f "$SRC" ] || { say "缺档位库文件 $SRC"; exit 1; }
if cp -f "$SRC" "$DB" && chown media:audio "$DB" && chmod 600 "$DB" \
   && chcon u:object_r:vendor_data_file:s0 "$DB"; then
  say "档位写入 $P 完成"
else
  say "档位写入 $P 失败，保持原档"
fi
