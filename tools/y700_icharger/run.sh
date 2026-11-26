#!/usr/bin/env bash
# 试跑：把 y700_icharger 起在设备上（不装模块，kill 即还原）
set -e
cd "$(dirname "$0")"
DEV="${DEV:-192.0.2.10:5555}"
JAR=/data/local/tmp/y700_icharger.jar
LOG=/data/local/tmp/y700_icharger_calls.log
OUT=/data/local/tmp/y700_icharger.out
SVC=vendor.oplus.hardware.charger.ICharger/default

adb -s "$DEV" push y700_icharger.jar "$JAR" >/dev/null
bash stop.sh >/dev/null 2>&1 || true
adb -s "$DEV" shell "su -c 'rm -f $LOG $OUT'"

# 服务名不在 service_contexts 里，落 default_android_service；SELinux 类名是 service_manager（不是 service）
# magiskpolicy 绝对路径 + 兜底，和模块 service.sh 保持一致，避免 PATH 差异导致静默不生效
POL='MP=/product/bin/magiskpolicy
[ -x "$MP" ] || MP=/data/adb/magisk/magiskpolicy
[ -x "$MP" ] || { echo "NO magiskpolicy"; exit 1; }
"$MP" --live \
  "allow magisk default_android_service service_manager add" \
  "allow system_server default_android_service service_manager find" \
  "allow platform_app default_android_service service_manager find" \
  "allow system_app default_android_service service_manager find" \
  "allow shell default_android_service service_manager find" \
  "allow magisk system_server binder call" \
  "allow system_server magisk binder call"'
adb -s "$DEV" shell "su -c '$POL'"

adb -s "$DEV" shell "su -c 'setsid nohup app_process -Djava.class.path=$JAR /system/bin com.y700.icharger.Main >$OUT 2>&1 &' "
sleep 3
echo "=== 服务注册 ==="
adb -s "$DEV" shell "service check $SVC"
echo "=== 进程 ==="
adb -s "$DEV" shell "su -c 'ps -A -o PID,NAME | grep -i app_process | head -3; cat $OUT 2>/dev/null | head -5'"
echo "=== 调用日志（前 20 行）==="
adb -s "$DEV" shell "su -c 'head -20 $LOG 2>/dev/null || echo （暂无调用）'"
