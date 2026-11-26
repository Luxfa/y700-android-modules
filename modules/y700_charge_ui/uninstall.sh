#!/system/bin/sh
# 卸载/移除模块时停掉服务；SELinux 实时规则随重启自动消失
for p in /proc/[0-9]*; do
  if tr "\0" " " <"$p/cmdline" 2>/dev/null | grep -q com.y700.icharger.Main; then kill "$(basename "$p")" 2>/dev/null; fi
done
