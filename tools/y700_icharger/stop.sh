#!/usr/bin/env bash
# 停掉试跑的 y700_icharger（只按 cmdline 精确匹配，不用 pkill/pgrep -f 的误伤面）
DEV="${DEV:-192.0.2.10:5555}"
adb -s "$DEV" shell "su -c 'for p in /proc/[0-9]*; do if tr \"\\0\" \" \" < \$p/cmdline 2>/dev/null | grep -q com.y700.icharger.Main; then echo kill \$(basename \$p); kill \$(basename \$p); fi; done'"
