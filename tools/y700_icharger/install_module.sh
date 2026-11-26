#!/usr/bin/env bash
# 打包并安装 y700_charge_ui 模块到设备 /data/adb/modules/
# 走"先 push 到 /data/local/tmp（带模块前缀的暂存名）再 su cp"的路子（直 push 进 modules 会被拒）
set -e
cd "$(dirname "$0")"
DEV="${DEV:-192.0.2.10:5555}"
SRC=../modules/y700_charge_ui
MOD=y700_charge_ui
T=/data/local/tmp/${MOD}

bash build.sh >/dev/null
[ -f y700_icharger.jar ] || { echo "构建产物缺失" >&2; exit 1; }

adb -s "$DEV" push y700_icharger.jar "${T}_jar" >/dev/null
adb -s "$DEV" push "$SRC/service.sh" "${T}_service.sh" >/dev/null
adb -s "$DEV" push "$SRC/uninstall.sh" "${T}_uninstall.sh" >/dev/null
adb -s "$DEV" push "$SRC/module.prop" "${T}_module.prop" >/dev/null

adb -s "$DEV" shell "su -c '
  mkdir -p /data/adb/modules/$MOD
  cp ${T}_jar        /data/adb/modules/$MOD/y700_icharger.jar
  cp ${T}_service.sh /data/adb/modules/$MOD/service.sh
  cp ${T}_uninstall.sh /data/adb/modules/$MOD/uninstall.sh
  cp ${T}_module.prop  /data/adb/modules/$MOD/module.prop
  chmod 755 /data/adb/modules/$MOD/service.sh /data/adb/modules/$MOD/uninstall.sh
  chmod 644 /data/adb/modules/$MOD/y700_icharger.jar /data/adb/modules/$MOD/module.prop
  rm -f ${T}_jar ${T}_service.sh ${T}_uninstall.sh ${T}_module.prop
  ls -l /data/adb/modules/$MOD
'"
echo "=== 无 disable/remove 标记？ ==="
adb -s "$DEV" shell "su -c 'ls /data/adb/modules/$MOD | grep -E \"disable|remove\" || echo 干净'"
