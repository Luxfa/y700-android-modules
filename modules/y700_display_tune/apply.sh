#!/system/bin/sh
# 把用户选定的显示色彩参数落回系统。可重复执行（开机自动跑，也可手动重放）。
#
# 只走两条系统自带通道，不写分区、不启停任何 HAL：
#   饱和度 → ColorDisplayService 的 shell 命令（面板后处理层，截图与图层矩阵都看不到效果）
#   色温   → ColorOS 自己的自定义取色键（用户在设置里拖色温盘写的就是这两个键）
#
# 三条实测约束，改动前先看这里：
#   1) 切色彩模式会把自定义色温清零（实测 eyeprotect_rgb 回到 1000,1000,1000、取色盘回中心）。
#      所以用户换档之后要重放本脚本，色温才会回来；饱和度不受换档影响。
#   2) 色彩模式档位本身**不由本模块设置**：实测 settings put oplus_last_color_mode 成功过一次、
#      之后连续四次不生效，而用户在设置里点选每次都灵。写键不可靠，故不依赖它。
#   3) 判据只能用服务侧读数或用户肉眼，不能用截图像素或 SurfaceFlinger 的 colorTransform。

SAT=83
RGB="1000,982,918,1,1"
BALL=3
LOG=/data/local/tmp/y700_display_tune.log
say() { echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"; }

say "== apply 开始 sat=$SAT rgb=$RGB ball=$BALL"

settings put system eyeprotect_rgb "$RGB"
settings put system color_temperate_ball_mode "$BALL"
got=$(settings get system eyeprotect_rgb)
[ "$got" = "$RGB" ] && say "色温写入确认 $got" || say "色温写入异常 期望=$RGB 实得=$got"

i=0
while [ $i -lt 3 ]; do
  i=$((i + 1))
  cmd color_display set-saturation "$SAT"
  sleep 2
  st=$(dumpsys color_display 2>/dev/null | sed -n '/Global saturation/,+1p' | tail -1 | tr -d ' ')
  case "$st" in
    *Activated:true*) say "饱和度落地 $SAT（第 $i 次，服务侧 $st）"; break ;;
    *) say "饱和度第 $i 次未生效：$st" ;;
  esac
done

say "== apply 结束"
