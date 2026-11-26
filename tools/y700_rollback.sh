#!/system/bin/sh
# y700_rollback.sh —— 设备侧一键回退器（推送到平板后用 root 执行）
#
#   用法： sh /data/local/tmp/y700_rollback.sh [模块名 ...]
#         不给参数 = 回退全部五个 y700_* 模块
#
# 为什么需要它：Magisk 的 uninstall.sh 只在 App 内卸载时执行，而本项目的既定回退
# 姿势是"删模块目录重启"——那条路径不跑任何模块脚本，守护进程与 settings 脏值会
# 留到下次重启。本脚本补上这段缺失的清理。
#
# 注意：默认**不动 TCP adb**（那是我方的工作通道，且已改为非 persist 属性，
# 删模块 + 重启会自然关闭）。要立刻断开就显式加 --close-adb。
#
# Magisk 模块标记文件名（2026-11-24 在本机 magisk 二进制与 util_functions.sh 里核过）：
#   disable    = 保留目录但不挂载、不跑脚本（真正的"禁用"）
#   remove     = 下次启动前自删
#   skip_mount = 只跳过挂载，脚本仍执行
# 写成 disabled / removal 之类**没有任何效果**——本项目曾因此让已知危险的
# y700_dolby_bridge 在重启后自行复活，别再犯。

MODS="y700_auto_brightness y700_charge_bridge y700_game_policy y700_identity_hygiene y700_vcomm_telephony y700_display_tune y700_dolby_bridge y700_dolby_daxservice"
CLOSE_ADB=0
ARG=""
for a in "$@"; do
  case "$a" in
    --close-adb) CLOSE_ADB=1 ;;
    *) ARG="$ARG $a" ;;
  esac
done
[ -n "$ARG" ] && MODS=$(echo $ARG)

kill_by_cmdline() {
  pat=$1
  f=$2
  p=$(cat "$f" 2>/dev/null)
  case "$(tr '\0' ' ' </proc/$p/cmdline 2>/dev/null)" in
    *$pat*)
      kill "$p" 2>/dev/null && echo "  killed $pat pid=$p"
      ;;
    *) echo "  $pat 未在运行" ;;
  esac
  rm -f "$f"
}

for m in $MODS; do
  d=/data/adb/modules/$m
  [ -d "$d" ] || { echo "== $m 不存在，跳过"; continue; }
  echo "== 回退 $m"
  case "$m" in
    y700_auto_brightness)
      kill_by_cmdline daemon.sh /data/local/tmp/y700_ab.pid
      rm -f /data/local/tmp/y700_ab.win
      if [ -f /data/adb/y700_ab.orig_mode ]; then
        v=$(cat /data/adb/y700_ab.orig_mode 2>/dev/null)
        case "$v" in
          0 | 1)
            settings put system screen_brightness_mode "$v"
            echo "  screen_brightness_mode 恢复为 $v"
            ;;
        esac
        rm -f /data/adb/y700_ab.orig_mode
      fi
      ;;
    y700_charge_bridge)
      kill_by_cmdline bridge.sh /data/local/tmp/y700_charge_bridge.pid
      echo 1 >/sys/class/power_supply/battery/charging_enabled 2>/dev/null && echo "  charging_enabled 交还系统(=1)"
      ;;
    y700_vcomm_telephony)
      [ -n "$(getprop persist.adb.tcp.port)" ] && setprop persist.adb.tcp.port "" && echo "  清掉历史 persist.adb.tcp.port"
      ;;
    y700_game_policy)
      echo "  仅 sepolicy.rule，重启即完全复原"
      ;;
    y700_display_tune)
      cmd color_display set-saturation 100
      echo "  饱和度回默认 100（服务侧: $(dumpsys color_display 2>/dev/null | sed -n '/Global saturation/,+1p' | tail -1 | tr -d ' ')）"
      settings put system eyeprotect_rgb "1000,1000,1000,1,1"
      settings put system color_temperate_ball_mode 2
      echo "  色温回中性 1000,1000,1000 / 取色盘模式回 2"
      ;;
    y700_dolby_bridge)
      if [ -f /data/adb/modules/y700_dolby_bridge/apply_profile.sh ]; then
        sh /data/adb/modules/y700_dolby_bridge/apply_profile.sh 0
        echo "  杜比档位还原为出厂默认 0（Dynamic）"
      fi
      if umount /vendor/etc/audio/sku_canoe/audio_effects_config.xml 2>/dev/null; then
        echo "  已撤销音效配置覆盖挂载（分区原文件本就未改）"
      else
        echo "  未发现覆盖挂载，无需撤销"
      fi
      setprop ctl.restart vendor.audio-hal-aidl
      sleep 3
      setprop ctl.restart audioserver
      echo "  音频服务已重启，回到原厂默认（约 2 秒无声）"
      echo "  注：杜比状态库的出厂备份在 00_救生包 之外的 临时存档/audio/dolbyfx/dax_sqlite3.db.bak，如需逐字节还原请用该文件"
      ;;
    y700_dolby_daxservice)
      # 不能在运行中 kill 杜比服务：效果对象随进程消失会走同一条销毁路径，可能把音频服务一起拖住。
      # 正确做法是打 disable 标记后重启，由关机流程统一收；本模块目录保留（不删），下次开机 Magisk 跳过挂载。
      rm -f "$d/disabled" 2>/dev/null
      touch "$d/disable" 2>/dev/null
      KEEP=1
      echo "  已打 disable 标记（保留目录，便于复核）—— 必须重启一次才算完全回退（盖回的系统件随模块消失）"
      ;;
  esac
  if [ "$KEEP" = "1" ]; then
    KEEP=0
  else
    rm -rf "$d"
    echo "  已删除模块目录"
  fi
done

rm -f /data/local/tmp/y700_auto_brightness.log /data/local/tmp/y700_charge_bridge.log \
      /data/local/tmp/y700_game_policy.log /data/local/tmp/y700_identity_hygiene.log \
      /data/local/tmp/y700_display_tune.log \
      /data/local/tmp/y700_dolby_bridge.log /data/local/tmp/y700_dolby_daxservice.log 2>/dev/null

if [ "$CLOSE_ADB" = "1" ]; then
  echo "== 关闭 TCP adb"
  setprop service.adb.tcp.port ""
  setprop persist.adb.tcp.port ""
  stop adbd
  start adbd
else
  echo "（未动 TCP adb；service.adb.tcp.port=$(getprop service.adb.tcp.port) persist.adb.tcp.port=[$(getprop persist.adb.tcp.port)]，删模块后下次重启即失效）"
fi
echo "== 剩余模块：$(ls /data/adb/modules 2>/dev/null | tr '\n' ' ')"
