#!/system/bin/sh
MODDIR=${0%/*}
LOG=/data/local/tmp/y700_thermal_tune.log
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 10
{
  echo "===== $(date '+%H:%M:%S') 开机后自检"
  echo "覆盖条数=$(cat /proc/mounts | grep -ac thermal-engine_cpu_0.conf)"
  echo "thermal-engine=$(pidof thermal-engine-v2) svc=$(getprop init.svc.thermal-engine)"
  echo "基线频率 cpu0=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq) cpu6=$(cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_max_freq) gpu=$(cat /sys/class/kgsl/kgsl-3d0/max_gpuclk)"
  echo "期望（场景0已加载）cpu0=3513600 cpu6=4512000；若出现 3628800/4608000 说明场景没接上，需处理"
} >> $LOG 2>&1
