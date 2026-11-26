#!/system/bin/sh
# 必须在 thermal-engine 第一次启动之前把阈值文件盖好，否则重启 daemon 会丢掉"场景 0"
# （实测：ctl.restart thermal-engine 之后 ss_algo_init: No SS's configured.，CPU/GPU 直接跑到 boost 档不限频）
MODDIR=${0%/*}
LOG=/data/local/tmp/y700_thermal_tune.log
CONF=$MODDIR/confs
# bind mount 会把源文件的 SELinux 标签一起带过去。Magisk 装完模块里的文件是 system_file，
# 而 thermal-engine 域只被允许读 vendor_configs_file —— 标签不对它不会报错，只会"静默没加载"
# （现象：日志里 ss_algo_init: No SS's configured.，CPU/GPU 一路跑到 boost 档不限频）。
chcon u:object_r:vendor_configs_file:s0 "$CONF"/*.conf 2>/dev/null
umount /vendor/etc/thermal-engine_cpu_0.conf 2>/dev/null
umount /vendor/etc/thermal-engine_gpu_0.conf 2>/dev/null
for n in cpu gpu; do
  case $n in
    cpu) f=thermal-engine_cpu_0.conf ;;
    gpu) f=thermal-engine_gpu_0.conf ;;
  esac
  if mount -o bind "$CONF/$f" "/vendor/etc/$f" 2>/dev/null; then
    echo "$(date '+%H:%M:%S') 已覆盖 $f" >> $LOG
  else
    echo "$(date '+%H:%M:%S') 覆盖失败 $f" >> $LOG
  fi
done
