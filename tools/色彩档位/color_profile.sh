#!/system/bin/sh
# 色彩档位切换器（设备侧执行，作者 hutao）。
# 档位存在 /data/adb/y700_color/profile.conf。
# 分工（11-26 用户裁 A 方案）：切档位时两样都写一次（等同于你在设置页点一下）；
# 但开机重放只补饱和度 —— 色温是系统设置项，自己会留着，重放会顶掉你之后的自行修改。
# 用法：sh color_profile.sh soft|std|manual|now

DIR=/data/adb/y700_color
PRO=$DIR/profile.conf
OFF=$DIR/off
mkdir -p "$DIR"

apply() {
  ct=$(sed -n 's/^color_temp=//p' "$PRO" 2>/dev/null)
  sat=$(sed -n 's/^saturation=//p' "$PRO" 2>/dev/null)
  nm=$(sed -n 's/^name=//p' "$PRO" 2>/dev/null)
  [ -z "$ct" ] && ct="1.0,0.994,0.987"
  [ -z "$sat" ] && sat=95
  settings put secure general_color_temperature "$ct"
  cmd color_display set-saturation "$sat"
  echo "档位=$nm 色温=$ct 饱和度=$sat"
  echo "复验 色温读回=$(settings get secure general_color_temperature)"
  echo -n "复验 饱和覆盖="
  dumpsys color_display 2>/dev/null | sed -n '/Global saturation:/,+1p' | tr -d ' \n'
  echo ""
  dumpsys SurfaceFlinger 2>/dev/null | grep -ao 'colorTransformMatrix=\[[^]]*\]\[[^]]*\]\[[^]]*\]' | head -1
  echo "开机重放范围：只补饱和度 $sat；色温 $ct 由系统自己保存，模块不再顶它"
}

case "$1" in
  soft)
    rm -f "$OFF"
    printf 'name=soft\ncolor_temp=1.0,0.994,0.987\nsaturation=95\n' > "$PRO"
    apply ;;
  std)
    rm -f "$OFF"
    printf 'name=std\ncolor_temp=1.0,1.0,1.0\nsaturation=100\n' > "$PRO"
    apply ;;
  manual)
    touch "$OFF"
    echo "已交还系统：模块开机不再重放，色温/饱和度随你在设置页里怎么调怎么走。"
    echo "要收回档位：sh color_profile.sh soft" ;;
  now)
    apply ;;
  *)
    echo "用法: sh color_profile.sh soft|std|manual|now"
    echo "  soft   柔和档（色温 1.0,0.994,0.987 / 饱和度 95）= 当前定稿"
    echo "  std    原厂标准档（色温中性 / 饱和度 100 无覆盖）"
    echo "  manual 停用重放，完全交还给系统设置页"
    echo "  now    只读复验当前生效值" ;;
esac
