#!/usr/bin/env bash
#===============================================================================
# flash_9008.sh — 9008 刷写编排层（API）
#
# 用途：把"QSaharaServer 握手上 firehose → fh_loader 按 rawprogram 写分区"封装成
#       一条可被总管直接调用的命令。适用于 C17 刷入、088 回退刷入。
# 用法：
#   ./flash_9008.sh --port COM5 --firehose <prog_firehose路径> --xmldir <目录> \
#       [--xml rawprogram0.xml,rawprogram1.xml,...] [--dry-run]
# 参数：
#   --port       9008 串口（设备管理器里 QDLoader 的 COM 号）
#   --firehose   引导文件 .elf/.mbn（来源：088 回退包）
#   --xmldir     rawprogram*.xml 与镜像所在目录
#   --xml        逗号分隔的 xml 列表；缺省自动按 rawprogram0..5 存在的都刷
#   --dry-run    只打印将执行的命令，不执行
#
# 纪律（分工说明·证据与安全规范）：
#   - 本脚本属于高危写操作，必须总管发起、用户在场复核后执行
#   - 刷前硬性前置：043 整盘回读完成 且 GPT 占位 bin 已从刷写清单剔除
#   - 依赖：00_救生包/tools/violet-cli/（QSaharaServer、fh_loader）
#===============================================================================
set -u
CLI="D:/Ai Work/Y700五代移植ColorOS/00_救生包/tools/violet-cli"
PORT=""; FIREHOSE=""; XMLDIR=""; XMLLIST=""; DRY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --port) shift; PORT="$1";;
        --firehose) shift; FIREHOSE="$1";;
        --xmldir) shift; XMLDIR="$1";;
        --xml) shift; XMLLIST="$1";;
        --dry-run) DRY=1;;
        -h|--help) grep '^#' "$0" | head -25; exit 0;;
        *) echo "未知参数: $1" >&2; exit 2;;
    esac
    shift
done

[ -n "$PORT" ] && [ -n "$FIREHOSE" ] && [ -n "$XMLDIR" ] || { echo "缺参数，见 --help" >&2; exit 2; }
[ -f "$FIREHOSE" ] || { echo "firehose 不存在: $FIREHOSE" >&2; exit 1; }
[ -d "$XMLDIR" ] || { echo "xml 目录不存在: $XMLDIR" >&2; exit 1; }

if [ -z "$XMLLIST" ]; then
    XMLLIST=""
    for i in 0 1 2 3 4 5; do
        [ -f "$XMLDIR/rawprogram$i.xml" ] && XMLLIST="$XMLLIST,rawprogram$i.xml"
    done
    XMLLIST="${XMLLIST#,}"
fi
[ -n "$XMLLIST" ] || { echo "$XMLDIR 下没有 rawprogram*.xml" >&2; exit 1; }

echo "== 9008 刷写编排 =="
echo "串口:     $PORT"
echo "firehose: $FIREHOSE"
echo "xml目录:  $XMLDIR"
echo "xml序列:  $XMLLIST"
echo

# 安全闸：禁止把全零 GPT 占位 bin 写进设备（C17 解剖教训）
for f in "$XMLDIR"/rawprogram*.xml; do
    if grep -q 'filename="gpt_main' "$f"; then
        echo "⚠️  注意: $f 含 gpt_main/gpt_backup 刷写项"
        echo "    若对应 bin 为全零占位，必须先剔除该刷写项（编辑 xml 或用紫罗兰读分区表模式）"
    fi
done

run() { echo "+ $*"; [ "$DRY" -eq 1 ] || "$@"; }

# Sahara 引导链目录（八映射，来源官方2.5包；新版设备会索要ID59=sequencer_ram等多件，单传firehose必败）
# 11-24 起 Tool 解包目录（19G）已按用户裁定删除，只留 Tool.7z（12.2G，CRC 全验通过）⇒ 缺件时自动解包，救砖链不断。
CHAIN_DIR="D:/Ai Work/Y700五代移植ColorOS/00_救生包/ZUI官方包_2.5.10.055/TB323_ZUXOS_2.5.10.055_Tool/image"
if [ ! -f "$CHAIN_DIR/sequencer_ram.elf" ]; then
  ARCHIVE="D:/Ai Work/Y700五代移植ColorOS/00_救生包/ZUI官方包_2.5.10.055/TB323_ZUXOS_2.5.10.055_Tool.7z"
  SEVENZ="/c/Program Files/7-Zip/7z.exe"; command -v 7z >/dev/null 2>&1 && SEVENZ="$(command -v 7z)"
  [ -f "$ARCHIVE" ] && [ -x "$SEVENZ" ] || { echo "引导链缺件且无法自动解包（7z 或 $ARCHIVE 不在）: $CHAIN_DIR" >&2; exit 1; }
  echo "!! 引导链目录不在盘上，正从 7z 解包（约 19G，20–40 分钟）…"
  OUTDIR="$(dirname "$ARCHIVE")"
  # 密码含括号，必须整体加引号；-aoa 只作用于解包目标，不覆盖任何在盘物料
  "$SEVENZ" x "-p${PACK_PASSWORD}" -aoa "$ARCHIVE" "-o$OUTDIR" >/dev/null || { echo "解包失败，中止" >&2; exit 1; }
  [ -f "$CHAIN_DIR/sequencer_ram.elf" ] || { echo "解包后仍不完整: $CHAIN_DIR" >&2; exit 1; }
  echo "解包完成: $CHAIN_DIR"
fi

echo "== 阶段1: Sahara 握手 + 上传引导链（八映射，官方bat同款） =="
run "$CLI/QSaharaServer.exe" -p "\\\\.\\$PORT" \
    -s 36:"$CHAIN_DIR/multi_image_qti.mbn" \
    -s 37:"$CHAIN_DIR/multi_image.mbn" \
    -s 21:"$CHAIN_DIR/xbl_sc.elf" \
    -s 60:"$CHAIN_DIR/signed_firmware_soc_view.elf" \
    -s 59:"$CHAIN_DIR/sequencer_ram.elf" \
    -s 61:"$CHAIN_DIR/tme_config.elf" \
    -s 13:"$CHAIN_DIR/prog_firehose_ddr.elf" \
    -s 38:"$CHAIN_DIR/xbl_config_devprg.elf" \
    -b "$CHAIN_DIR/" || { echo "Sahara握手失败，中止（不进入写分区阶段）" >&2; exit 1; }

echo "== 阶段2: Firehose 写分区 =="
for x in $(echo "$XMLLIST" | tr ',' ' '); do
    echo "-- 写入 $x"
    run "$CLI/fh_loader.exe" --port="\\\\.\\$PORT" --sendxml="$x" --search_path="$XMLDIR" --memoryname=ufs --zlpawarehost=1 --noprompt || { echo "写入 $x 失败，中止后续刷写" >&2; exit 1; }
done

echo "== 完成 =="
echo "提示：刷完设备应自动重启；若 5 分钟无反应，按救砖SOP三键复位法处置。"
