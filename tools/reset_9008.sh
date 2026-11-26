#!/usr/bin/env bash
set -u
CLI="D:/Ai Work/Y700五代移植ColorOS/00_救生包/tools/violet-cli"
"$CLI/fh_loader.exe" --port="\\.\COM5" --power=reset,1 --memoryname=ufs --noprompt
