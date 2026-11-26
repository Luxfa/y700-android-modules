#!/system/bin/sh
# 桥：盯页面写的 system_dolby_category，映射成杜比档位并让它真实生效
#
# 实测约束（21:2x 阶梯测试得出，勿改回重做法）：
#   1) 写档后【只重启 dms-hal】即可换杜比处理模式：档0→ProcessingMode=1、档4→10，双向各复现一次。
#   2) 只重启 vendor.audio-hal-aidl 无效；只靠暂停再播放重建会话也无效——别退回那两种做法。
#   3) 页面值与杜比档位不是一套编号：0/4 恰好撞上杜比的 Dynamic/SpatialAudio，5/6 不是，
#      所以映射表由本脚本定义，不能照抄页面值。
#   4) 自定义模式页面写的是 10 段均衡器，杜比是 20 段，本版不搬均衡器，故自定义=不动档位。
MODDIR=/data/adb/modules/y700_dolby_bridge
STAMP="$MODDIR/.applied_profile"
LOG=/data/local/tmp/y700_dolby_bridge.log
say() { echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"; }

map() {
  case "$1" in
    0) echo 0 ;;   # 智能   → Dynamic
    4) echo 4 ;;   # 沉浸   → SpatialAudio
    5) echo 2 ;;   # 保真   → Music（该档 ieq_amount 各档最高，对应"高音质听感"）
    6) echo "" ;;  # 自定义 → 不动作（它语义是"我自己调均衡器"，均衡器未接通前不该偷换档位）
    *) echo 0 ;;
  esac
}

[ -f "$STAMP" ] || echo "" > "$STAMP"
while true; do
  c=$(settings get system system_dolby_category 2>/dev/null | tr -d ' \r\n')
  if [ -n "$c" ]; then
    p=$(map "$c")
    applied=$(cat "$STAMP" 2>/dev/null)
    if [ -z "$p" ]; then
      :   # 自定义模式：本版不动档位，避免与智能撞在一起造成"切了没反应"的假象
    elif [ "$p" != "$applied" ]; then
      say "页面模式键=$c → 杜比档位=$p（原已应用=${applied:-无}）"
      if sh "$MODDIR/apply_profile.sh" "$p"; then
        echo "$p" > "$STAMP"
        setprop ctl.restart dms-hal
        say "已重启杜比服务使其生效"
      fi
    fi
  fi
  sleep 2
done
