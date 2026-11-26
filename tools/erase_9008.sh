#!/usr/bin/env bash
# erase 专用：直接 fh_loader（不重握手），参数形态照抄 flash_9008.sh 成功路径
set -u
CLI="D:/Ai Work/Y700五代移植ColorOS/00_救生包/tools/violet-cli"
XMLDIR="D:/Ai Work/Y700五代移植ColorOS/06_二期自制移植/产出/candidate_v1"
cd "$XMLDIR"
"$CLI/fh_loader.exe" --port="\\\\.\\COM5" --sendxml="$1" --search_path="$XMLDIR" --memoryname=ufs --zlpawarehost=1 --noprompt
