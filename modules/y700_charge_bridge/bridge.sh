#!/system/bin/sh
# y700_charge_bridge —— 把 ColorOS 的充电开关翻译到联想唯一有效的控制面
# 只写一个 sysfs 节点，不写任何分区；删除模块目录即完全回退。
NODE=/sys/class/power_supply/battery/charging_enabled
CAP=/sys/class/power_supply/battery/capacity
LOG=/data/local/tmp/y700_charge_bridge.log
PIDF=/data/local/tmp/y700_charge_bridge.pid

say() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"
  [ "$(stat -c %s "$LOG" 2>/dev/null)" -gt 1048576 ] && { tail -c 262144 "$LOG" >"$LOG.t" 2>/dev/null && mv "$LOG.t" "$LOG"; }
}

get_sys() { settings get system "$1"; }

# 回差带宽：达到上限停充，掉到 上限-带宽 才恢复，避免在阈值附近抖振
BAND=5

enforce() {
  want=""
  bypass=$(get_sys bypass_charge_state)
  prot=$(get_sys regular_charge_protection_switch_state)
  level=$(get_sys regular_charge_protection_open_power_level)

  # 模块自有兜底开关：UI 键不可用时用这个属性
  [ "$bypass" = "1" ] && want=0

  if [ -z "$want" ]; then
    case "$prot" in
      1)
        case "$level" in ''|*[!0-9]*) level=95 ;; esac
        [ "$level" -lt 5 ] && level=5
        [ "$level" -gt 100 ] && level=100
        cap=$(cat "$CAP" 2>/dev/null)
        case "$cap" in
          ''|*[!0-9]*) say "WARN capacity 不可读/非数字 cap=[$cap] -> 本轮不动作" ;;
          *)
            low=$((level - BAND))
            if [ "$cap" -ge "$level" ]; then want=0; elif [ "$cap" -le "$low" ]; then want=1; fi
            ;;
        esac
        ;;
      *) want=1 ;;
    esac
  fi

  cur=$(cat "$NODE" 2>/dev/null)
  case "$cur" in
    ''|*[!0-9]*)
      say "WARN charging_enabled 不可读/非数字 cur=[$cur] -> 本轮不动作（节点可能随 OTA 变更）"
      return
      ;;
  esac
  if [ -z "$want" ]; then want="$cur"; fi
  if [ "$want" != "$cur" ]; then
    if echo "$want" >"$NODE" 2>/dev/null; then
      say "charging_enabled $cur -> $want (bypass=$bypass prot=$prot level=$level cap=$(cat $CAP 2>/dev/null))"
    else
      say "FAILED 写 charging_enabled=$want 被拒（权限/节点只读？）"
    fi
  fi
}

if [ -f "$PIDF" ]; then
  p=$(cat "$PIDF" 2>/dev/null)
  case "$(tr '\0' ' ' </proc/$p/cmdline 2>/dev/null)" in *bridge.sh*) exit 0 ;; esac
fi
echo $$ >"$PIDF"

if [ ! -e "$NODE" ]; then
  say "FATAL 控制节点不存在 $NODE —— 内核面变了，本模块不工作"
  exit 1
fi

i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  i=$((i + 1))
  [ $i -gt 90 ] && break
  sleep 2
done
sleep 8
say "bridge start pid=$$"
while true; do
  enforce
  sleep 5
done
