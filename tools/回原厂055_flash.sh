#!/usr/bin/env bash
#===============================================================================
# flash055.sh — 回原厂 2.5.10.055 全量刷写（照抄 11-23 已跑通的 phaseI 命令面）
# 依据：01_计划书/回原厂055_施工单.md §二；命令形态逐条取自 临时存档/phaseI/phaseI_control.sh
# 差异：IMG 指向 临时存档/flash055_20261126 的新解包目录（救生包内解包树已于 11-24 删除）
#
# 用法：sh flash055.sh GO-CONFIRMED      ← 必须带这个参数，否则直接退出（防误触）
#       sh flash055.sh --dry-run         ← 只打印不执行
#
# 纪律：高危写操作，总管发起 + 用户在场复核后执行；任何一步 FAIL 立即停，不复位不重试
#===============================================================================
set -u
MODE="${1:-}"
R="D:/Ai Work/Y700五代移植ColorOS"
CLI="$R/00_救生包/tools/violet-cli"
IMG="$R/临时存档/flash055_20261126/TB323_ZUXOS_2.5.10.055_Tool/image"
P="$R/临时存档/flash055_20261126"
QS="$CLI/QSaharaServer.exe"; FH="$CLI/fh_loader.exe"
PORT='\\.\COM5'
LOG="$P/run.log"; DRY=0

if [ "$MODE" = "--dry-run" ]; then DRY=1
elif [ "$MODE" != "GO-CONFIRMED" ]; then
  echo "拒绝执行：需要参数 GO-CONFIRMED（见 --help）。本脚本会清空 userdata，不可逆。"; exit 2
fi
mkdir -p "$P"; [ $DRY -eq 1 ] && P="$P/dryrun" && LOG="$P/run.log" && mkdir -p "$P"; [ $DRY -eq 0 ] && : > "$LOG"
say(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
run(){ if [ $DRY -eq 1 ]; then echo "DRY> $*"; else "$@"; fi; }
ok(){ iconv -f GBK -t UTF-8 -c < "$1" 2>/dev/null | grep -aq "All Finished"; }
fail(){ say "$1 —— **停手**，设备停在当前状态不复位。日志：$2"; exit 1; }

[ -d "$IMG" ] || { echo "解包目录不存在: $IMG"; exit 1; }
[ -f "$IMG/prog_firehose_ddr.elf" ] || { echo "firehose 缺失"; exit 1; }

say "0 前置检查"
if [ $DRY -eq 0 ]; then
  PORTS=$(powershell -NoProfile -Command '[System.IO.Ports.SerialPort]::getportnames()' 2>/dev/null | tr -d '\r')
  echo "$PORTS" | grep -aq 'COM5' || { echo "看不到 COM5 ⇒ 设备不在 9008。先执行 adb -s 192.0.2.10:5555 reboot edl（屏黑为正常）"; exit 1; }
  say "COM5 在位"
fi

say "1/5 Sahara 握手（官方 8 映射 + -b 搜索路径）"
run "$QS" -p "$PORT" \
  -s 36:"$IMG/multi_image_qti.mbn" -s 37:"$IMG/multi_image.mbn" -s 21:"$IMG/xbl_sc.elf" \
  -s 60:"$IMG/signed_firmware_soc_view.elf" -s 59:"$IMG/sequencer_ram.elf" -s 61:"$IMG/tme_config.elf" \
  -s 13:"$IMG/prog_firehose_ddr.elf" -s 38:"$IMG/xbl_config_devprg.elf" -b "$IMG/" > "$P/sahara.log" 2>&1
[ $DRY -eq 1 ] || { grep -aq "Sahara protocol completed" "$P/sahara.log" || fail "SAHARA_FAIL" "$P/sahara.log"; say "SAHARA_OK"; }

say "2/5 写前只读取证（uefivarstore/logfs/misc 基线，失败不阻塞）"
cp -f "$R/临时存档/phaseH/read_vars.xml" "$P/read_vars.xml" 2>/dev/null
run "$FH" --port="$PORT" --sendxml=read_vars.xml --search_path="$P" --mainoutputdir="$P" --memoryname=ufs --noprompt --zlpawarehost=1 > "$P/vars.log" 2>&1
[ $DRY -eq 1 ] || { ok "$P/vars.log" && say "取证读完成" || say "取证读失败（不阻塞，继续）"; }

say "3/5 官方全量写入（约 7~9 分钟，**唯一分区写操作**）"
say "     写面=官方 rp0 裁剪版(保留 persist)+rp1-5+patch0-5+官方 GPT，含 --setactivepartition=1"
cd "$IMG" || exit 1
run "$FH" --port="$PORT" --search_path="$IMG" \
  --sendxml=rawprogram_save_persist_unsparse0.xml,rawprogram1.xml,rawprogram2.xml,rawprogram3.xml,rawprogram4.xml,rawprogram5.xml \
  --sendxml=patch0.xml,patch1.xml,patch2.xml,patch3.xml,patch4.xml,patch5.xml \
  --mainoutputdir="$P" --setactivepartition=1 --memoryname=ufs --showpercentagecomplete --zlpawarehost=1 --noprompt \
  > "$P/prog.log" 2>&1
if [ $DRY -eq 0 ]; then
  say "PROG_EXIT=$?"
  ok "$P/prog.log" || { iconv -f GBK -t UTF-8 -c < "$P/prog.log" | tail -12 > "$P/prog_tail.txt"; fail "PROG_FAIL" "$P/prog_tail.txt"; }
  iconv -f GBK -t UTF-8 -c < "$P/prog.log" | grep -a "All Finished\|Overall to target" | tail -2 | tee -a "$LOG"
  say "PROG_OK"
fi

say "4/5 擦 userdata + metadata（**不可逆，数据在此清空**）"
cd "$P" || exit 1
cp -f "$R/临时存档/phaseI/erase_userdata_v1.xml" "$P/" 2>/dev/null
run "$FH" --port="$PORT" --sendxml=erase_userdata_v1.xml --search_path="$P" --memoryname=ufs --noprompt > "$P/erase.log" 2>&1
[ $DRY -eq 1 ] || { ok "$P/erase.log" && say "ERASE_OK" || say "ERASE_FAIL(继续，首启会自行格式化)"; }
cp -f "$R/临时存档/gptfix/misc_write.xml" "$R/临时存档/gptfix/misc_zero.bin" "$R/临时存档/gptfix/power_reset.xml" "$P/" 2>/dev/null
run "$FH" --port="$PORT" --sendxml=misc_write.xml --search_path="$P" --memoryname=ufs --noprompt --zlpawarehost=1 > "$P/misc.log" 2>&1
[ $DRY -eq 1 ] || { ok "$P/misc.log" && say "MISC_OK" || say "MISC_FAIL(继续)"; }

say "5/5 复位（不用官方 --reset，用已验证的 power_reset.xml）"
run "$FH" --port="$PORT" --sendxml=power_reset.xml --search_path="$P" --memoryname=ufs --noprompt --zlpawarehost=1 > "$P/reset.log" 2>&1
[ $DRY -eq 1 ] || { ok "$P/reset.log" && say "RESET_ISSUED" || say "RESET_FAIL"; }
say "DONE —— 判定窗口 2~6 分钟：守候脚本应看到 VID_17EF&PID_7FE1（MTP+真 SN），不得停在 9008 或 fastboot"
if [ $DRY -eq 1 ]; then say "以上为 dry-run，未执行任何命令"; fi
exit 0
