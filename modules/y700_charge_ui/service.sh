#!/system/bin/sh
# y700_charge_ui —— 起 ICharger 应答服务（只回真实值），并按需放行 SELinux
# 只注册一个 binder 服务 + 只读 sysfs，不写任何分区；删除模块目录即完全回退。
MODDIR=/data/adb/modules/y700_charge_ui
JAR=$MODDIR/y700_icharger.jar
SVC=vendor.oplus.hardware.charger.ICharger/default
LOG=/data/local/tmp/y700_icharger_calls.log

say() {
  echo "$(date '+%m-%d %H:%M:%S') [service] $*" >>"$LOG"
  [ "$(stat -c %s "$LOG" 2>/dev/null)" -gt 1048576 ] && { tail -c 262144 "$LOG" >"$LOG.t" 2>/dev/null && mv "$LOG.t" "$LOG"; }
}

# 已有实例就退出（按 cmdline 精确匹配，不用 pgrep -f 的误伤面）
for p in /proc/[0-9]*; do
  if tr '\0' ' ' <"$p/cmdline" 2>/dev/null | grep -q com.y700.icharger.Main; then
    exit 0
  fi
done

[ -f "$JAR" ] || { say "FATAL 缺 $JAR —— 模块不完整"; exit 1; }

i=0
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  i=$((i + 1))
  [ $i -gt 90 ] && break
  sleep 2
done
sleep 15

# 服务名不在 service_contexts 里，落 default_android_service；类名是 service_manager（不是 service）
# magiskpolicy 用绝对路径：service.sh 的 PATH 由 Magisk 拼装，不保证含 /product/bin，
# 裸命令名找不到时整条策略静默失败 —— 表现是服务起了但 system_server 查不到，很难查。
MP=""
for c in /product/bin/magiskpolicy /debug_ramdisk/magiskpolicy /data/adb/magisk/magiskpolicy; do
  [ -x "$c" ] && MP=$c && break
done
if [ -z "$MP" ]; then
  say "WARN 三处候选路径都没有 magiskpolicy —— 跳过放行，服务大概率注册失败"
else
  "$MP" --live \
    "allow magisk default_android_service service_manager add" \
    "allow magisk default_android_service service_manager find" \
    "allow system_server default_android_service service_manager find" \
    "allow platform_app default_android_service service_manager find" \
    "allow system_app default_android_service service_manager find" \
    "allow magisk system_server binder call" \
    "allow system_server magisk binder call" >>"$LOG" 2>&1
  say "SELinux 放行完成 bin=$MP rc=$?"
fi

setsid nohup app_process -Djava.class.path="$JAR" /system/bin com.y700.icharger.Main >>"$LOG" 2>&1 &

# 日志封顶已移进 jar 内部（Main.log）：下面这条外部巡查循环在 11-25 16:29 重启后实测根本没起来
# （设备侧只剩 jar 进程，日志 4 小时涨到 8.67MB），外部兜底不可依赖，故删除。

sleep 3
# 注册回读（坑 21）：addService 是 oneway，服务端拒绝也不会抛异常，只能主动查
found=$(service check "$SVC" 2>/dev/null)
say "拉起完成 $found"
case "$found" in *'not found'*) say "WARN 服务未注册 —— 查 $LOG" ;; esac
