#!/usr/bin/env bash
# 把"新装的三方 App"补进 Magisk 排除列表（默认全排除策略的补口）。
# 用法：sh 排除_新增应用.sh [设备序列号]
set -u
DEV="${1:-YOUR_SERIAL}"
S="/debug_ramdisk/su -c"
KEEP="com.topjohnwu.magisk com.lenovo.hyperengine com.xiaoji.egggame com.lenovo.dsa com.lenovo.hybridworkspace com.zuxos.wpslauncher com.orion.notein"
adb -s "$DEV" shell "$S \"for p in \\$(pm list packages -3 | sed 's/package://'); do echo \\\\\\\" \\$p \\\\\\\" | grep -qa ' \\\"$KEEP\\\" ' || magisk --denylist add \\$p >/dev/null 2>&1; done; echo 排除总数=\\$(magisk --denylist ls | wc -l); echo \\$(magisk --denylist status)\"" 2>&1 | tr -d '\r'
