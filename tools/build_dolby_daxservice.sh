#!/usr/bin/env bash
# 从 ZUI 官方原包抽取原厂杜比服务四件，装配成可刷入的模块 zip。
# 二进制不入库（见 05_备份索引/大件再生命令与指纹.md），本脚本负责按需再生。
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/00_救生包/ZUI官方包_2.5.10.055/TB323_ZUXOS_2.5.10.055_Tool.7z"
MOD="$ROOT/03_脚本与模块/modules/y700_dolby_daxservice"
WORK="$ROOT/临时存档/zui_dolby"
SEVENZ="/c/Program Files/7-Zip/7z.exe"
[ -x "$SEVENZ" ] || SEVENZ="$(command -v 7z)"
PASS="$(grep -aoE 'FC\(fv:SknR' "$ROOT/02_调研/20261122_官方包2.5.10.055解剖.md" | head -1)"
[ -n "$PASS" ] || { echo "没在原包解剖文档里找到解压密码，先补上再跑"; exit 1; }

SYS="$WORK/raw/TB323_ZUXOS_2.5.10.055_Tool/image/super_4.img"     # system_a
SE="$WORK/raw/TB323_ZUXOS_2.5.10.055_Tool/image/super_6.img"      # system_ext_a

SRC=(
  "$SYS|system/lib64/libdolbyeffect.so"
  "$SYS|system/lib64/libdolbyproxyandroid.so"
  "$SYS|system/lib64/libdolbyui.so"
  "$SE|priv-app/daxService/daxService.apk|system_ext/priv-app/daxService/daxService.apk"
)
for it in "${SRC[@]}"; do
  img="${it%%|*}"; rest="${it#*|}"
  if [[ "$rest" == *"|"* ]]; then f="${rest%%|*}"; rel="${rest#*|}"; else f="$rest"; rel="$rest"; fi
  [ -f "$img" ] || { echo "缺分片 $(basename "$img")，先跑本脚本末尾的再生命令"; exit 1; }
  out="$MOD/system/$rel"
  mkdir -p "$(dirname "$out")"
  "$SEVENZ" e "$img" "$f" -o"$(dirname "$out")" -y >/dev/null || { echo "抽取失败：$f"; exit 1; }
  echo "已取 $rel"
done

# 白名单用仓库里补全过的版本（原厂那份在 ColorOS 的 enforce 模式下会导致开机失败）
mkdir -p "$MOD/system/system_ext/etc/permissions"
cp "$ROOT/03_脚本与模块/privapp/com.dolby.daxservice.xml" "$MOD/system/system_ext/etc/permissions/"
echo "已放置补全白名单"

chmod 755 "$MOD/service.sh"
chmod 644 "$MOD"/system/lib64/*.so "$MOD"/system/system_ext/priv-app/daxService/daxService.apk \
	"$MOD"/system/system_ext/etc/permissions/com.dolby.daxservice.xml "$MOD/module.prop"

echo "=== 装配完成，指纹如下（须与 05_备份索引 记录一致）==="
find "$MOD" -type f -printf "%10s  %P\n" | sort -k2
for f in "$MOD"/system/lib64/*.so "$MOD"/system/system_ext/priv-app/daxService/daxService.apk; do
	echo "$(sha256sum "$f" | cut -c1-16)  $(basename "$f")"
done
echo
echo "分片再生命令（只需 system 与 system_ext 两片）："
echo "  \"$SEVENZ\" x \"$PKG\" \"TB323_ZUXOS_2.5.10.055_Tool/image/super_4.img\" \"TB323_ZUXOS_2.5.10.055_Tool/image/super_6.img\" -o\"$WORK/raw\" -y \"-p$PASS\""
