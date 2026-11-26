#!/usr/bin/env bash
# GPU 频率地板实验：抬高最低档，验证"掉帧是否来自升频滞后"
# 状态：用户 11-24 17:1x 裁定**不启用**（144Hz 档实测满帧，无需抬地板）。脚本保留备查，不要随手跑
# 只写 /sys/class/kgsl 运行时节点，不动分区；revert 或重启即复原
# 用法：bash gpu_floor.sh status | set 7 | revert
set -u
export PATH="$PATH:/d/platform-tools"
export MSYS_NO_PATHCONV=1
DEV="${DEV:-192.0.2.10:5555}"
D=/sys/class/kgsl/kgsl-3d0
ORIG=/data/local/tmp/y700_gpu_floor.orig
A(){ adb -s "$DEV" shell "su -c \"$1\"" 2>&1 | tr -d '\r'; }

snap(){
  A "echo -n 'min_pwrlevel='; cat $D/min_pwrlevel; echo -n 'max_pwrlevel='; cat $D/max_pwrlevel
     echo -n 'clock_mhz='; cat $D/clock_mhz; echo -n 'busy='; cat $D/gpu_busy_percentage
     echo -n 'thermal_pwrlevel='; cat $D/thermal_pwrlevel; echo -n 'throttling='; cat $D/throttling
     echo -n 'temp='; cat $D/temp"
}

case "${1:-status}" in
  status)
    echo "=== 当前 GPU 档位状态 ==="; snap
    echo "=== 18 档频率表（索引 0=最高频）==="; A "cat $D/gpu_available_frequencies"
    ;;
  set)
    idx="${2:-7}"
    # 原始值只在第一次写之前存一次，保证 revert 总能回到本轮起点
    A "[ -f $ORIG ] || cat $D/min_pwrlevel >$ORIG; echo 存档原值=\$(cat $ORIG)"
    echo "写入前："; snap
    A "echo $idx > $D/min_pwrlevel; echo 写入后 min_pwrlevel=\$(cat $D/min_pwrlevel)"
    echo "--- 10 秒后回读（看地板是否真的抬起来、有没有异常复位）---"; sleep 10; snap
    A "echo reset_count=\$(cat $D/reset_count)"
    # 语义保险：本驱动 min_pwrlevel=17/max_pwrlevel=0 与主线 kgsl 的命名相反，写入后必须看效果
    #   地板被抬高  ⇒ clock_mhz 不再低于表上第 idx 档，属预期
    #   反被封顶  ⇒ clock_mhz 一直钉在第 idx 档或以下且 busy 顶到 95%+，说明语义相反，立刻 revert
    echo "--- 最近 10 个帧距窗口（对照掉帧是否变化）---"
    A "tail -10 /data/local/tmp/y700_lolm_fps.csv"
    echo "回退：bash gpu_floor.sh revert"
    ;;
  revert)
    A "if [ -f $ORIG ]; then cp $ORIG $D/min_pwrlevel; echo 已回退为 \$(cat $D/min_pwrlevel); rm -f $ORIG; else echo 无存档，未改动; fi"
    snap
    ;;
  *) echo "用法：status | set <档位索引> | revert"; exit 1 ;;
esac
