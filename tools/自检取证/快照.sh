#!/system/bin/sh
# 自检快照：一条命令抓全"必须用户实际用到才能判"的 14 类证据（全程只读，不改任何设置）
# 用法见同目录 抓快照.sh。每节末尾"判读"是给读的人的口径，不是结论；结论要写进自检表并按日期署名。
# 注意：设备侧是 toybox sh，不能用 <(...) 进程替换、不能用 [[ ]]、数组。
export PATH=/system/bin:/vendor/bin:$PATH
L=/data/local/tmp/y700_selfcheck_report.txt
BT=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
CRASH() { logcat -d -b crash 2>/dev/null | grep -a -c "$1"; }

echo "===== Y700 五代移植 C17 自检快照 =====" > "$L"
echo "抓取时间 : $(date '+%Y-%m-%d %H:%M:%S')" >> "$L"
echo "开机至今 : ${BT}s" >> "$L"
echo "身份     : $(getprop ro.product.model) / $(getprop ro.build.displayid)" >> "$L"
echo "模块     : $(ls /data/adb/modules 2>/dev/null | tr '\n' ' ')" >> "$L"
echo "崩溃计数 : audioserver=$(CRASH audioserver) system_server=$(CRASH system_server) surfaceflinger=$(CRASH surfaceflinger)" >> "$L"
echo "音频门禁 : pm 特性 dolby 命中=$(pm list features 2>/dev/null | grep -a -c dolby) effect.type=$(getprop ro.oplus.audio.effect.type)" >> "$L"

sec() { echo "" >> "$L"; echo "===== $1 =====" >> "$L"; }

sec "1 蓝牙通话（HFP / EARPIECE）"
dumpsys bluetooth_manager 2>/dev/null | grep -a -E 'ConnectionState: STATE_CONNECTED|mBluetoothHeadsetDevice|[Hh]eadset' | head -6 >> "$L"
echo "-- 最近缓冲内 no EARPIECE 条数 = $(logcat -d 2>/dev/null | grep -a -c 'no EARPIECE')" >> "$L"
logcat -d 2>/dev/null | grep -a -i 'EARPIECE' | tail -2 | cut -c1-150 >> "$L"
echo "-- 当前可用于通话的设备" >> "$L"
cmd audio getDevicesAvailableForCommunication 2>/dev/null | head -6 >> "$L"
echo "判读：通话中此处出现 BT SCO/HEADSET 且 no EARPIECE 不再新增 ⇒ 蓝牙通话路由可用" >> "$L"

sec "2 蓝牙回连稳定性"
dumpsys bluetooth_manager 2>/dev/null | grep -a -E 'Name:|Address:|Bond state|ConnectionState|State:' | head -12 >> "$L"
echo "判读：对照开机时长，若同一设备在本次开机内已多次 STATE_CONNECTED 且无配对丢失 ⇒ 回连稳；只看一次连接不能判稳" >> "$L"

sec "3 Wi-Fi 频段与速率"
cmd wifi status 2>/dev/null | grep -a -E 'Wifi is connected|Frequency|Link speed|standard' | head -4 >> "$L"
iw dev wlan0 link 2>/dev/null | grep -a -E 'freq|signal|SSID' | head -3 >> "$L"
echo "判读：freq<2500=2.4G、>=5000=5G。只测到 5G 时 2.4G 那半仍算未验" >> "$L"

sec "4 热点（SoftAP）"
dumpsys wifi 2>/dev/null | grep -a -E 'SoftAP|ApStatus|numConnected|IfaceState|mIfaceName|ap info' | head -8 >> "$L"
echo "-- 热点能力位" >> "$L"
cmd wifi get-softap-supported-features 2>/dev/null | head -8 >> "$L"
echo "判读：有已连站点数>0 且频段=5G ⇒ 热点 5G 实测通过；否则只是能力在位" >> "$L"

sec "5 定位（GNSS/网络）"
dumpsys location 2>/dev/null | grep -a -E 'provider=|last location|hasAnyLocationProvider|enabled' | head -10 >> "$L"
echo "判读：last location 落在最近几分钟且有经纬度 ⇒ 定位可用（室内常拿不到，别据此判死）" >> "$L"

sec "6 陀螺仪（是否真有数据流）"
dumpsys sensorservice 2>/dev/null | grep -a -E 'Gyroscope' | head -4 >> "$L"
dumpsys sensorservice 2>/dev/null | grep -a -A4 'lsm6dsv Gyroscope Non-wakeup: last' | head -6 >> "$L"
echo "-- 陀螺 handle 订阅情况" >> "$L"
dumpsys sensorservice 2>/dev/null | grep -a '0x00000029' | head -2 >> "$L"
echo "判读：active-count>0 且 last events 有非零角速度 ⇒ 实战可用（要开相机录像或游戏时抓才有人订阅）" >> "$L"

sec "7 霍尔 / 皮套"
dumpsys sensorservice 2>/dev/null | grep -a -A3 'Hall Effect Sensor Wakeup: last' | head -5 >> "$L"
dumpsys power 2>/dev/null | grep -a -E 'mLidState|getLidBehavior|mDockMode' | head -3 >> "$L"
echo "判读：传感器值 1.00=周围无磁；贴磁套后应变 0.00。mLidState=LID_ABSENT 说明 PowerManager 那路没接（它读输入设备 SW_LID，不是这个 sensor）" >> "$L"

sec "8 手写笔"
pm list packages 2>/dev/null | grep -a -E 'ipe|pencil|stylus|scribe' | head -5 >> "$L"
echo "-- 输入设备名册（笔看 NVTCapacitivePen 之类）" >> "$L"
getevent -p 2>/dev/null | grep -a -E 'name:' | head -12 >> "$L"
echo "-- 笔相关私有键" >> "$L"
settings list secure 2>/dev/null | grep -a -i -E 'pencil|stylus' | head -4 >> "$L"
echo "判读：名册里有 *Pen* 输入设备 + ipemanager 在位 ⇒ 系统侧支持；笔身是否工作必须真笔（本机已见 NVTCapacitivePen）" >> "$L"

sec "9 DRM / Widevine"
getprop 2>/dev/null | grep -a -i -E 'widevine|wv|drm' | head -6 >> "$L"
echo "-- 当前缓冲内 media.drm 读数" >> "$L"
dumpsys media.drm 2>/dev/null | head -12 >> "$L"
echo "判读：等级要播一条付费高清内容时抓才准；persist.sys.oplus.wvrestricted=2 是移植包系统层加的键（原厂包搜不到）" >> "$L"

sec "10 HDR / 视频链路"
getprop 2>/dev/null | grep -a -i -E 'hdr|uhd|color_mode' | head -8 >> "$L"
dumpsys SurfaceFlinger 2>/dev/null | grep -a -E 'renderRate|Dataspace:.*HDR|Draw ' | head -4 >> "$L"
echo "判读：播放 HDR 片源时若出现 HDR dataspace / Hdr layer ⇒ 链路真在走 HDR，属性在位不算通过" >> "$L"

sec "11 游戏画质与帧率"
echo "-- 自动分辨率/画质成对开关 = $(settings get secure oplus_games_auto_resolution_switch_key)" >> "$L"
dumpsys SurfaceFlinger 2>/dev/null | grep -a -m1 renderRate >> "$L"
dumpsys window 2>/dev/null | grep -a -E 'mCurrentFocus|mFocusedApp' | head -2 >> "$L"
echo "判读：该键=1 表示画质与帧率由游戏助手成对下发，帧率上不去先动它再怪游戏档位表" >> "$L"

sec "12 跟手与观感（客观旁证）"
TOP=$(dumpsys window 2>/dev/null | grep -a -m1 mCurrentFocus | sed -n 's/.*Window\{[^ ]* \([^ /]*\)\/.*/\1/p')
[ -z "$TOP" ] && TOP=$(dumpsys window 2>/dev/null | grep -a -m1 mFocusedApp | sed -n 's/.* \([^ /]*\)\/.*/\1/p')
echo "-- 前台包：$TOP" >> "$L"
dumpsys gfxinfo "$TOP" 2>/dev/null | grep -a -E 'Total frames rendered|Janky frames' | head -3 >> "$L"
echo "判读：Janky 比例 <5% 时，主观'不跟手'更可能撞在 315~330Hz 触控采样上限（本机已证不可提升），不是移植缺陷" >> "$L"

sec "13 音量分路与设备路由"
dumpsys audio 2>/dev/null | grep -a -E '^ +Stream|ringer mode' | head -12 >> "$L"
settings list system 2>/dev/null | grep -a -E '^volume_' | head -10 >> "$L"
echo "判读：多条 Stream 各自有独立音量键值 ⇒ 分路在；通话/通知被一起改动才算缺陷" >> "$L"

sec "14 触感流水与双马达证据（震动二期复验专用）"
echo "-- 仍被丢弃的反馈条数 = $(dumpsys vibrator_manager 2>/dev/null | grep -a -c 'ignored_unsupported')" >> "$L"
dumpsys vibrator_manager 2>/dev/null | grep -a -o 'constant=[0-9]*' | sort | uniq -c | sort -rn | head -6 >> "$L"
echo "-- 触感类输入设备" >> "$L"
getevent -p 2>/dev/null | grep -a -E 'name:' | grep -a -i -E 'haptic|hv' >> "$L"
echo "-- 谁持有这些节点（看是否两路都在被驱动）" >> "$L"
for p in /proc/[0-9]*; do
  if ls -l "$p/fd" 2>/dev/null | grep -a -q 'input/event'; then
    CM=$(tr -d '\0' < "$p/cmdline" 2>/dev/null)
    case "$CM" in *vibrator*) echo "$(basename $p) $CM $(ls -l $p/fd 2>/dev/null | grep -a -o 'input/event[0-9]*' | tr '\n' ' ')" >> "$L";; esac
  fi
done 2>/dev/null
echo "-- AW86937 双马达关键旋钮" >> "$L"
for n in vibrator_l vibrator_r; do
  echo "[$n] dual_mode=$(cat /sys/class/leds/$n/dual_mode 2>/dev/null) double=$(cat /sys/class/leds/$n/double 2>/dev/null) auto_boost=$(cat /sys/class/leds/$n/auto_boost 2>/dev/null) gain=$(cat /sys/class/leds/$n/gain 2>/dev/null) f0=$(cat /sys/class/leds/$n/f0 2>/dev/null) res=$(cat /sys/class/leds/$n/lra_resistance 2>/dev/null) cali=$(cat /sys/class/leds/$n/cali 2>/dev/null)" >> "$L"
done 2>/dev/null
echo "判读：302/307 若仍列在丢弃里 ⇒ 震动二期未修好。两路 aw-haptic-hv 都被马达服务打开 ⇒ '只走单路'不成立，得另找弱感原因（波形表无人读 / 效果被丢弃）" >> "$L"
echo "判读：lra_resistance 是**实时测量值**，不作故障判据——11-25 18:5x 三次取样里低读数（59）先在右、后换到左，两边都出现过正常值（12879/21883/25640）⇒ 是读数竞态，不是某颗马达坏。要判马达健康只看 cali/f0/gain/dual_mode 是否有值且两边同档，并要求复现" >> "$L"

echo "" >> "$L"
echo "===== 快照结束 =====" >> "$L"
cat "$L"
