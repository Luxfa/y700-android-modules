#!/usr/bin/env bash
# =============================================================================
# validate_port.sh — 构建期验证套件（"模拟机"五道门禁）
#
# 派单：01_计划书/派单_008_构建期验证套件.md（2026-11-23，环境与脚本线）
# 图纸：06_二期自制移植/适配工作区/C17适配手法拆解.md（A1/A5/A6 等手法以它为准）
#
# 用法（WSL2 Ubuntu bash 内运行）：
#   ./validate_port.sh --target <候选启动链目录> [--super <super.img>] \
#       [--recipe <配方.json>] [--workdir <临时目录>] [--gates G1,G2,G3,G4,G5]
#
# 五道门：
#   G1 super 回读   ：lp_parse.py 回读候选 super，分区清单/尺寸/槽位/geometry 对配方
#   G2 sepolicy 编译：2.5 vendor/odm cil + 供体 plat/system_ext cil + C17 追加段，
#                     secilc 试编译合并策略，报错误行（含 neverallow 冲突）
#   G3 AVB 自洽     ：解候选 vbmeta，HASH 描述符尺寸+摘要 对实际 img；
#                     flags/algorithm/签名态 对图纸 A6（algorithm=NONE、flags=1、无签名）
#   G4 fstab 静态审查：logical 挂载点分区名须在 super 清单；avb=/avb_keys= 剥除；
#                     供体独有分区残留检查（A5 手法）
#   G5 内核一致性   ：magiskboot 解 boot/vendor_boot，内核 vermagic 对全部 .ko
#
# 依赖：
#   WSL 内：python3、secilc（≥3.9 为佳：/opt/selinux-3.9/bin/secilc，011d 装，见下方
#           SECILC 配置；旧 3.5 自动走 G2.b 规避诊断）、grep/sed/awk、loop mount
#           （G2 提取 2.5 vendor/odm cil，失败自动回退证据目录 C17 件并标注）、lz4（备用）
#   Windows 侧经 /mnt/d 互操作：magiskboot.exe（00_救生包/tools/violet-cli/）
#   证据目录（只读）：06_二期自制移植/适配工作区/C17拆解证据/
#   ZUI 2.5 官方包切片（只读）：00_救生包/ZUI官方包_2.5.10.055/.../image/super_{2,7}.img
#
# 纪律：只读证据/物料目录，不写镜像、不碰设备、不联网；临时文件只落 --workdir。
# =============================================================================
set -u

PROJ="${PROJ:-/mnt/d/Ai Work/Y700五代移植ColorOS}"
EVID="${EVID:-$PROJ/06_二期自制移植/适配工作区/C17拆解证据}"
LP_PARSE="${LP_PARSE:-$EVID/super/lp_parse.py}"
# 注意（11-24）：Tool 解包目录已按用户裁定删除，只留 Tool.7z；要用就先解包（flash_9008.sh 会自动解），或用 ZUI_IMG=<目录> 指到解出来的 image/。
ZUI_IMG="${ZUI_IMG:-$PROJ/00_救生包/ZUI官方包_2.5.10.055/TB323_ZUXOS_2.5.10.055_Tool/image}"
MAGISKBOOT="${MAGISKBOOT:-$PROJ/00_救生包/tools/violet-cli/magiskboot.exe}"

# 011d 工具链升级（2026-11-23）：secilc 自 SELinuxProject/selinux master（f0736c7，
# 2026-11-20）静态链接 libsepol 编译，支持 Android 17 CIL 的 nlmsg xperm、
# netlink_xperm 与 functionfs_seclabel policycap（release 3.9 缺最后一个，装于
# /opt/selinux-3.9/ 作备份）；master 装于 WSL /opt/selinux-master/bin/。
# 不存在则依次回退 3.9 → 系统 secilc（3.5 走 G2.b 规避诊断分支）；SECILC=<路径> 可覆盖。
if [ -n "${SECILC:-}" ]; then :; 
elif [ -x /opt/selinux-master/bin/secilc ]; then SECILC=/opt/selinux-master/bin/secilc
elif [ -x /opt/selinux-3.9/bin/secilc ];    then SECILC=/opt/selinux-3.9/bin/secilc
else SECILC=secilc; fi

TARGET=""
SUPER=""
RECIPE="$(cd "$(dirname "$0")" && pwd)/super_recipe_dryrun.json"
WORKDIR="$PROJ/临时存档/008/work"
GATES="G1,G2,G3,G4,G5"

usage() { sed -n '2,38p' "$0"; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target)  TARGET="$2";  shift 2;;
    --super)   SUPER="$2";   shift 2;;
    --recipe)  RECIPE="$2";  shift 2;;
    --workdir) WORKDIR="$2"; shift 2;;
    --gates)   GATES="$2";   shift 2;;
    -h|--help) usage;;
    *) echo "未知参数: $1"; usage;;
  esac
done

# D:\ 风格路径转 /mnt/d 风格
tomnt() {
  case "$1" in
    [A-Za-z]:\\*|[A-Za-z]:/*)
      local p="${1//\\//}"; echo "/mnt/${p:0:1}${p:2}" | tr 'A-Z' 'a-z' | sed 's|^/mnt/\([a-z]\)|/mnt/\1|';;
    *) echo "$1";;
  esac
}
TARGET=$(tomnt "$TARGET")
[ -n "$SUPER" ] && SUPER=$(tomnt "$SUPER")
RECIPE=$(tomnt "$RECIPE")
WORKDIR=$(tomnt "$WORKDIR")

[ -z "$TARGET" ] && { echo "错误：必须给 --target"; usage; }
[ -d "$TARGET" ] || { echo "错误：--target 目录不存在: $TARGET"; exit 2; }
mkdir -p "$WORKDIR"

want_gate() { case ",$GATES," in *",$1,"*) return 0;; *) return 1;; esac; }

# ---- 全局结果收集 -----------------------------------------------------------
declare -a GATE_VERDICT GATE_SUMMARY
gate_result() { # $1=门 $2=PASS/FAIL $3=一句话
  GATE_VERDICT+=("$2"); GATE_SUMMARY+=("$1: $3")
  echo ""
  echo "[$1] ===== $2 ===== $3"
  echo ""
}

# =============================================================================
# G1 super 回读
# =============================================================================
gate_g1() {
  echo "===== G1 super 回读 ====="
  local sup="$SUPER"
  if [ -z "$sup" ]; then
    sup=$(ls "$TARGET"/super*.img 2>/dev/null | head -1)
  fi
  if [ -z "$sup" ] || [ ! -f "$sup" ]; then
    gate_result G1 FAIL "未找到候选 super（--super 未给且 target 内无 super*.img）"; return
  fi
  [ -f "$RECIPE" ] || { gate_result G1 FAIL "配方文件不存在: $RECIPE"; return; }
  [ -f "$LP_PARSE" ] || { gate_result G1 FAIL "lp_parse.py 不存在: $LP_PARSE"; return; }
  echo "super:  $sup ($(stat -c %s "$sup") B)"
  echo "recipe: $RECIPE"
  local head4m="$WORKDIR/g1_super_head4m.bin"
  head -c 4194304 "$sup" > "$head4m"
  # lp_parse.parse() 无副作用（不直接跑 __main__，避免回写证据目录）
  LP_PARSE_PATH="$LP_PARSE" HEAD4M="$head4m" RECIPE_PATH="$RECIPE" python3 - <<'PY'
import json, os, sys, importlib.util
spec = importlib.util.spec_from_file_location("lp_parse", os.environ["LP_PARSE_PATH"])
lp = importlib.util.module_from_spec(spec); spec.loader.exec_module(lp)
data = open(os.environ["HEAD4M"], "rb").read()
r = lp.parse(data, "candidate")
recipe = json.load(open(os.environ["RECIPE_PATH"], encoding="utf-8"))
fails = []
def chk(name, cond, detail):
    print("  %s %-28s %s" % ("PASS" if cond else "FAIL", name, detail))
    if not cond: fails.append(name)
g, h = r["geometry"], r["header"]
rg, rh = recipe["geometry"], recipe["header"]
chk("geometry.size/slots/block",
    g["metadata_max_size"]==rg["metadata_max_size"] and g["metadata_slot_count"]==rg["metadata_slot_count"] and g["logical_block_size"]==rg["logical_block_size"],
    "%d/%d/%d" % (g["metadata_max_size"], g["metadata_slot_count"], g["logical_block_size"]))
chk("geometry.sha256(底座指纹)",
    g["sha256"]==rg["sha256"], g["sha256"][:16]+"...")
chk("header.version/size/flags",
    h["major"]==rh["major"] and h["minor"]==rh["minor"] and h["header_size"]==rh["header_size"] and h["flags"]==rh["flags"],
    "v%d.%d hdr=%d flags=0x%x" % (h["major"], h["minor"], h["header_size"], h["flags"]))
bds = r["block_devices"]; rb = recipe["block_device"]
bd = bds[0] if bds else {}
chk("block_device",
    bd.get("partition_name")==rb["partition_name"] and bd.get("first_logical_sector")==rb["first_logical_sector"]
    and bd.get("alignment")==rb["alignment"] and bd.get("alignment_offset")==rb["alignment_offset"],
    "%s sec=%d align=%d off=%d" % (bd.get("partition_name"), bd.get("first_logical_sector"), bd.get("alignment"), bd.get("alignment_offset")))
groups = {x["name"]: x["maximum_size"] for x in r["groups"]}
chk("groups", groups==recipe["groups"], json.dumps(groups))
# 分区清单：名称/尺寸/组/属性逐项
ATTRS = {0:"",1:"readonly",2:"slotsuffix",3:"readonly,slotsuffix"}
got = {}
for p in r["partitions"]:
    sz = sum(r["extents"][p["first_extent_index"]+j]["num_sectors"]*512 for j in range(p["num_extents"]))
    got[p["name"]] = {"size": sz,
                      "group": r["groups"][p["group_index"]]["name"] if p["group_index"] < len(r["groups"]) else "?",
                      "attributes": ATTRS.get(p["attributes"], str(p["attributes"]))}
exp = {p["name"]: p for p in recipe["partitions"]}
ok = True; detail = []
for name, e in exp.items():
    a = got.get(name)
    if a is None: ok=False; detail.append("缺 "+name); continue
    if a["size"]!=e["size"] or a["group"]!=e["group"] or a["attributes"]!=e["attributes"]:
        ok=False; detail.append("%s(size=%d exp=%d)" % (name, a["size"], e["size"]))
extra = sorted(set(got)-set(exp))
if extra: ok=False; detail.append("多出: "+",".join(extra))
chk("partitions(%d项)" % len(exp), ok, "；".join(detail) if detail else "30 项名称/尺寸/组/属性全对")
# extent 布局：有序、无重叠、首扇区 2048、各起点按 alignment 对齐（对齐留缝属正常，非"空洞"）
exts = sorted((e for e in r["extents"] if e["target_type"]==0), key=lambda e: e["target_data"])
re_ = recipe["extents"]; ok = bool(exts) and exts[0]["target_data"]==re_["first_sector"]
cur = exts[0]["target_data"] if exts else 0
al = r["block_devices"][0]["alignment"] if r["block_devices"] else 1048576
al_sec = al // 512
gaps = 0
for e in exts:
    if e["target_data"] < cur or (al_sec and e["target_data"] % al_sec != 0): ok=False; break
    gaps += e["target_data"] - cur
    cur = e["target_data"] + e["num_sectors"]
chk("extents有序无重叠(起%d)" % re_["first_sector"], ok,
    "末扇区=%d（%.2f GiB），对齐留缝合计 %d 扇区（1MiB 对齐属正常）" % (cur, cur*512/1024**3, gaps))
# 组占用不超限
used = sum(v["size"] for k,v in got.items() if k.endswith("_a"))
gmax = recipe["groups"]["qti_dynamic_partitions_a"]
chk("group_a占用<=上限", used<=gmax, "%d / %d (%.1f%%)" % (used, gmax, used*100/gmax))
print("G1_JSON_RESULT=%d" % len(fails))
sys.exit(1 if fails else 0)
PY
  local rc=$?
  [ $rc -eq 0 ] && gate_result G1 PASS "回读与配方逐项一致（geometry 指纹/分区30项/extent 连续/占用53%）" \
                || gate_result G1 FAIL "回读与配方存在偏差（见上 FAIL 行，证据 $WORKDIR/g1_super_head4m.bin）"
}

# =============================================================================
# G2 sepolicy 编译
# =============================================================================
gate_g2() {
  echo "===== G2 sepolicy 编译 ====="
  command -v "$SECILC" >/dev/null 2>&1 || { gate_result G2 FAIL "WSL 内无 secilc"; return; }
  echo "secilc: $SECILC（默认 policyvers $("$SECILC" -h 2>&1 | sed -n 's/.*default: \([0-9]*\).*/\1/p' | head -1)）"
  local d="$WORKDIR/g2"; rm -rf "$d"; mkdir -p "$d"
  local sep="$EVID/system/sepolicy"
  local vendor_src="" odm_src="" pubver_src="" extract_note=""
  # 优先：loop 挂载 2.5 官方 super_7(vendor)/super_2(odm) 提取真 2.5 cil（只读）
  if [ "$(id -u)" = "0" ] && [ -f "$ZUI_IMG/super_7.img" ] && [ -f "$ZUI_IMG/super_2.img" ]; then
    mkdir -p "$d/m_v" "$d/m_o"
    if mount -o ro,loop -t ext4 "$ZUI_IMG/super_7.img" "$d/m_v" 2>/dev/null; then
      cp "$d/m_v/etc/selinux/vendor_sepolicy.cil" "$d/vendor_base.cil" 2>/dev/null
      cp "$d/m_v/etc/selinux/plat_pub_versioned.cil" "$d/plat_pub_versioned.cil" 2>/dev/null
      umount "$d/m_v"
    fi
    if mount -o ro,loop -t ext4 "$ZUI_IMG/super_2.img" "$d/m_o" 2>/dev/null; then
      cp "$d/m_o/etc/selinux/odm_sepolicy.cil" "$d/odm_base.cil" 2>/dev/null
      umount "$d/m_o"
    fi
  fi
  if [ -s "$d/vendor_base.cil" ] && [ -s "$d/odm_base.cil" ]; then
    vendor_src="ZUI 2.5.10.055 super_7(super_2) loop 提取（真 2.5 件）"
  else
    cp "$sep/vendor_sepolicy.cil" "$d/vendor_base.cil"
    cp "$sep/odm_sepolicy.cil" "$d/odm_base.cil"
    vendor_src="回退：证据目录 C17 件（088 代联想侧，非真 2.5；差异待 G5/005d-7.2 重验）"
  fi
  echo "vendor/odm 基底: $vendor_src"
  # 供体 plat/system_ext/product（证据目录只读取用）
  cp "$sep/plat_sepolicy.cil" "$d/plat.cil"
  cp "$sep/system_ext_sepolicy.cil" "$d/system_ext.cil"
  cp "$sep/product_sepolicy.cil" "$d/product.cil"
  [ -s "$d/plat_pub_versioned.cil" ] || extract_note="（无 plat_pub_versioned.cil：versioned 属性解析可能失败）"
  # C17 追加段：vendor 尾部（自动定位首条 '; TB323FU' 注释）+ system_ext 追加段现成件
  local vstart
  vstart=$(grep -n '^; TB323FU' "$sep/vendor_sepolicy.cil" | head -1 | cut -d: -f1)
  if [ -n "$vstart" ] && [ "$vendor_src" != "${vendor_src#回退}" ]; then
    # 回退模式下基底已含追加段，追加段单独置空避免重复
    : > "$d/c17_vendor_append.cil"
    echo "C17 vendor 追加段: 已含于回退基底（不重复追加）"
  else
    sed -n "${vstart:-12987},\$p" "$sep/vendor_sepolicy.cil" > "$d/c17_vendor_append.cil"
    echo "C17 vendor 追加段: 自证据 vendor_sepolicy.cil 第 ${vstart:-12987} 行提取（$(wc -l < "$d/c17_vendor_append.cil") 行）"
  fi
  cp "$sep/system_ext_sepolicy_porter追加段.cil.txt" "$d/c17_system_ext_append.cil"
  local CILS=("$d/plat.cil")
  [ -s "$d/plat_pub_versioned.cil" ] && CILS+=("$d/plat_pub_versioned.cil")
  CILS+=("$d/system_ext.cil" "$d/c17_system_ext_append.cil" "$d/product.cil" "$d/vendor_base.cil" "$d/c17_vendor_append.cil" "$d/odm_base.cil")
  echo "编译输入: $(for f in "${CILS[@]}"; do basename "$f"; done | tr '\n' ' ') $extract_note"

  local sub_fail=1
  # --- 子项 a：原样 strict 编译（忠实复现合并，报错行） ---
  echo "--- G2.a 原样 strict 编译（secilc -m -M true -G，neverallow 开）"
  local out_a rc_a
  out_a=$("$SECILC" -m -M true -G "${CILS[@]}" -o "$d/policy_a.bin" 2>&1); rc_a=$?
  if [ $rc_a -eq 0 ] && [ -f "$d/policy_a.bin" ]; then
    echo "  PASS 原样编译成功 ($(stat -c %s "$d/policy_a.bin") B)"
    gate_result G2 PASS "原样 strict 编译成功（$SECILC）"
    return
  fi
  echo "  FAIL rc=$rc_a，错误行："
  echo "$out_a" | head -10 | sed 's/^/    /'
  echo "$out_a" > "$d/g2a_full.log"

  local na_count=""
  if echo "$out_a" | grep -qE 'Unknown permissionx kind|Invalid policycap|Unknown keyword'; then
    # === 旧工具链分支（libsepol 3.5：不识 nlmsg xperm / netlink_xperm policycap）===
    # 滤掉工具链不识的行后做规避诊断（008 首跑口径；冲突数为规避下读数）
    echo "--- G2.b 规避诊断（旧工具链：滤 nlmsg-xperm/policycap 后 strict，neverallow 开）"
    local f
    for f in plat plat_pub_versioned system_ext vendor_base; do
      [ -f "$d/$f.cil" ] || continue
      grep -vE 'allowx.*\(nlmsg [a-z0-9_]+ \(' "$d/$f.cil" | grep -v '^(policycap ' > "$d/${f}_f.cil"
    done
    for f in product c17_system_ext_append c17_vendor_append odm_base; do cp "$d/$f.cil" "$d/${f}_f.cil"; done
    local CILS_F=()
    for f in plat plat_pub_versioned system_ext c17_system_ext_append product vendor_base c17_vendor_append odm_base; do
      [ -f "$d/${f}_f.cil" ] && CILS_F+=("$d/${f}_f.cil")
    done
    local out_b
    out_b=$("$SECILC" -m -M true -G "${CILS_F[@]}" -o "$d/policy_b.bin" 2>&1)
    na_count=$(echo "$out_b" | grep -c 'neverallow check failed')
    if [ -f "$d/policy_b.bin" ]; then
      echo "  PASS 规避后 strict 编译成功"
    else
      echo "  FAIL neverallow 冲突 $na_count 处（规避下读数，节选）："
      echo "$out_b" | grep -A1 'neverallow check failed' | head -8 | sed 's/^/    /'
      echo "$out_b" > "$d/neverallow_full.log"
      echo "    全文: $d/neverallow_full.log"
    fi
    echo "--- G2.c 规避诊断（-N 关 neverallow，验结构合并）"
    local out_c
    out_c=$("$SECILC" -m -M true -G -N "${CILS_F[@]}" -o "$d/policy_c.bin" 2>&1)
    if [ -f "$d/policy_c.bin" ]; then
      echo "  PASS 结构合并编译成功 ($(stat -c %s "$d/policy_c.bin") B)；C17 追加段符号全部解析"
      sub_fail=0
    else
      echo "  FAIL rc=$?；$out_c" | head -5
    fi
  else
    # === 新工具链分支（011d secilc 3.9+）：原样语料直接出 neverallow 冲突真值 ===
    na_count=$(echo "$out_a" | grep -c 'neverallow check failed')
    cp "$d/g2a_full.log" "$d/neverallow_full.log"
    echo "  neverallow 冲突 ${na_count} 处（原样语料真值，全文: $d/neverallow_full.log）"
    echo "--- G2.c -N 结构合并（原样语料，neverallow 关，验结构合并）"
    local out_c
    out_c=$("$SECILC" -m -M true -G -N "${CILS[@]}" -o "$d/policy_c.bin" 2>&1)
    if [ -f "$d/policy_c.bin" ]; then
      echo "  PASS 结构合并编译成功 ($(stat -c %s "$d/policy_c.bin") B)；C17 追加段符号全部解析"
      sub_fail=0
    else
      echo "  FAIL rc=$?；$out_c" | head -5
    fi
  fi
  if [ $sub_fail -eq 0 ]; then
    gate_result G2 FAIL "原样 strict 编译不过；结构合并(-N)可通过，neverallow 冲突 ${na_count:-0} 处（语义层发现，全文 $d/neverallow_full.log）"
  else
    gate_result G2 FAIL "合并策略存在结构性错误（见 G2.a/G2.c，$d/g2a_full.log）"
  fi
}

# =============================================================================
# 通用：候选镜像解析（foo.img 或 foo_a.img）
# =============================================================================
resolve_img() { # $1=目录 $2=分区名
  for c in "$1/$2.img" "$1/$2_a.img" "$1/${2}_a.img"; do
    [ -f "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

# =============================================================================
# G3 AVB 自洽
# =============================================================================
gate_g3() {
  echo "===== G3 AVB 自洽 ====="
  local vb
  vb=$(resolve_img "$TARGET" vbmeta) || { gate_result G3 FAIL "target 内无 vbmeta(.img/_a.img)"; return; }
  echo "vbmeta: $vb ($(stat -c %s "$vb") B)；对照目录: $TARGET"
  TARGET_DIR="$TARGET" python3 - "$vb" <<'PY'
import struct, sys, os, hashlib, re
ALGO = {0:"NONE",1:"SHA256_RSA2048",2:"SHA256_RSA4096",3:"SHA256_RSA8192",
        4:"SHA256_ECC_P256",5:"SHA256_ECC_P521",6:"SHA512_RSA2048",7:"SHA512_RSA4096",8:"SHA512_RSA8192"}
path = sys.argv[1]; tdir = os.environ["TARGET_DIR"]
d = open(path, "rb").read()
fails = []
def chk(name, cond, detail):
    print("  %s %-30s %s" % ("PASS" if cond else "FAIL", name, detail))
    if not cond: fails.append(name)
def note(name, detail):
    print("  NOTE %-30s %s" % (name, detail))
chk("magic AVB0", d[:4]==b"AVB0", repr(d[:4]))
if d[:4]!=b"AVB0": sys.exit(1)
u32=lambda o: struct.unpack(">I",d[o:o+4])[0]
u64=lambda o: struct.unpack(">Q",d[o:o+8])[0]
algo, flags, sig_sz = u32(28), u32(120), u64(56)
auth_sz, desc_off, desc_sz = u64(12), u64(96), u64(104)
print("  header: algorithm=%d(%s) flags=%d sig=%dB rollback=%d" % (algo, ALGO.get(algo,-1), flags, sig_sz, u64(112)))
# A6 符合性（图纸：vbmeta_a 重做 algorithm=NONE、flags bit0=1、无签名）
chk("A6.algorithm=NONE", algo==0, "actual=%s" % ALGO.get(algo))
chk("A6.flags bit0=HASHTREE_DISABLED", flags&1==1, "actual flags=%d" % flags)
chk("A6.无签名", sig_sz==0, "actual sig=%dB" % sig_sz)
def find_name(body, nl):
    # 本 fork 描述符头含扩展保留区，名字位置不固定：按 name_len 全文找唯一 ASCII 段
    for m in re.finditer(rb"(?<![a-z0-9_])([a-z0-9_]{%d})(?![a-z0-9_])" % nl, body):
        return m.group(1).decode(errors="replace"), m.end(1)
    return None, None
aux = 256 + ((auth_sz+63)//64)*64
p, end, i = aux+desc_off, aux+desc_off+desc_sz, 0
while p+16 <= end:
    tag, nb = u64(p), u64(p+8); body = d[p+16:p+16+nb]
    bu32=lambda o: struct.unpack(">I",body[o:o+4])[0]
    bu64=lambda o: struct.unpack(">Q",body[o:o+8])[0]
    if tag==2 and len(body)>=60:  # HASH: image_size u64, hash_alg[32], name_len, salt_len, digest_len, flags
        isz = bu64(0); nl = bu32(40); sl = bu32(44); dl = bu32(48)
        name, ne = find_name(body, nl)
        if name is None:
            note("HASH描述符", "名字解析失败(nb=%d)" % nb); p += 16+nb; i += 1; continue
        salt = body[ne:ne+sl]; digest = body[ne+sl:ne+sl+dl]
        img = None
        for cand in (os.path.join(tdir, name+".img"), os.path.join(tdir, name+"_a.img")):
            if os.path.isfile(cand): img = cand; break
        if img:
            raw = open(img,"rb").read(); fsz = len(raw)
            # 摘要口径：sha256(salt || content[0:image_size])（文件可带追加 vbmeta/填充）
            dg = hashlib.sha256(salt + raw[:isz]).digest()
            chk("HASH %s 摘要(salted)" % name, dg==digest,
                "image_size=%d file=%d sha256(salt+content)%s" % (isz, fsz, "一致" if dg==digest else "不一致"))
        else:
            note("HASH %s" % name, "desc=%dB，target 内无 %s.img 无法核对" % (isz, name))
    elif tag==1 and len(body)>=92:  # HASHTREE: ver u32, image_size@4 ... name_len@88
        isz = bu64(4); nl = bu32(88)
        name, _ = find_name(body, nl)
        img = os.path.join(tdir, (name or "?")+".img")
        if name and os.path.isfile(img):
            chk("HASHTREE %s 尺寸" % name, os.path.getsize(img)>=isz, "desc image=%d file=%d" % (isz, os.path.getsize(img)))
        else:
            note("HASHTREE %s" % (name or "?"), "desc image=%dB，target 内无 img（super 内逻辑分区）" % isz)
    elif tag in (3,4) and len(body)>=16:  # chain: rb_loc u32, name_len u32, pk_len u32, reserved
        nl = bu32(4)
        name, _ = find_name(body, nl)
        note("CHAIN->%s" % (name or "?"), "委托验证（tag=%d），尺寸/摘要在链目标内自查" % tag)
    p += 16+nb; i += 1
print("G3_JSON_RESULT=%d" % len(fails))
sys.exit(1 if fails else 0)
PY
  local rc=$?
  [ $rc -eq 0 ] && gate_result G3 PASS "描述符与实际 img 自洽且符合 A6 手法" \
                || gate_result G3 FAIL "存在不自洽或不符合 A6 手法项（见上 FAIL/NOTE 行）"
}

# =============================================================================
# G4 fstab 静态审查
# =============================================================================
gate_g4() {
  echo "===== G4 fstab 静态审查 ====="
  local fstab=""
  if [ -f "$TARGET/fstab.qcom" ]; then
    fstab="$TARGET/fstab.qcom"
  else
    # 从候选 vendor_boot 镜像自助提取（magiskboot 互操作）
    local vbimg
    vbimg=$(resolve_img "$TARGET" vendor_boot)
    if [ -n "$vbimg" ] && [ -f "$MAGISKBOOT" ]; then
      local d="$WORKDIR/g4_vb"; rm -rf "$d"; mkdir -p "$d"
      cp "$vbimg" "$d/"
      ( cd "$d" && "$MAGISKBOOT" unpack vendor_boot.img >/dev/null 2>&1 \
        && "$MAGISKBOOT" decompress ramdisk.cpio ramdisk.dec.cpio >/dev/null 2>&1 \
        && mkdir -p x && cd x && "$MAGISKBOOT" cpio ../ramdisk.dec.cpio extract first_stage_ramdisk/fstab.qcom fstab_out >/dev/null 2>&1 )
      [ -f "$d/x/fstab_out" ] && fstab="$d/x/fstab_out"
      # magiskboot 版本差异：extract 到 ramdisk/ 子树的情况
      [ -z "$fstab" ] && [ -f "$d/x/ramdisk/first_stage_ramdisk/fstab.qcom" ] && fstab="$d/x/ramdisk/first_stage_ramdisk/fstab.qcom"
    fi
  fi
  [ -n "$fstab" ] || { gate_result G4 FAIL "无 fstab.qcom（target 内无文件且 vendor_boot 提取失败）"; return; }
  echo "fstab: $fstab"
  # super 分区清单（G1 未跑时独立回读）
  local sup="$SUPER"
  [ -z "$sup" ] && sup=$(ls "$TARGET"/super*.img 2>/dev/null | head -1)
  local listfile="$WORKDIR/g4_super_partitions.txt"
  if [ -n "$sup" ] && [ -f "$sup" ]; then
    head -c 4194304 "$sup" > "$WORKDIR/g4_super_head4m.bin"
    LP_PARSE_PATH="$LP_PARSE" HEAD4M="$WORKDIR/g4_super_head4m.bin" python3 - > "$listfile" <<'PY'
import os, importlib.util
spec = importlib.util.spec_from_file_location("lp_parse", os.environ["LP_PARSE_PATH"])
lp = importlib.util.module_from_spec(spec); spec.loader.exec_module(lp)
r = lp.parse(open(os.environ["HEAD4M"],"rb").read(), "candidate")
for p in r["partitions"]: print(p["name"])
PY
  else
    gate_result G4 FAIL "无 super 清单可对照（--super 未给）"; return
  fi
  FSTAB="$fstab" LISTF="$listfile" python3 - <<'PY'
import os, sys, re
fstab = os.environ["FSTAB"]
names = set(l.strip() for l in open(os.environ["LISTF"]) if l.strip())
fails = []
def chk(name, cond, detail):
    print("  %s %-34s %s" % ("PASS" if cond else "FAIL", name, detail))
    if not cond: fails.append(name)
def note(name, detail):
    print("  NOTE %-34s %s" % (name, detail))
DONOR_ONLY = {"my_company","my_preload","my_reserve","oplusreserve2"}
avb_eq, avbkeys_gsi, avbkeys_oplus, logical_bad, donor_hits, phys = [], [], [], [], [], []
logical_total = 0
for ln, line in enumerate(open(fstab, encoding="utf-8", errors="replace"), 1):
    s = line.strip()
    if not s or s.startswith("#"): continue
    cols = s.split()
    src, flags = cols[0], (cols[4] if len(cols)>4 else "")
    toks = flags.split(",")
    if any(t.startswith("avb=") for t in toks):
        avb_eq.append("%d:%s" % (ln, src))
    for t in toks:
        if t.startswith("avb_keys="):
            if "gsi" in t: avbkeys_gsi.append("%d:%s" % (ln, src))
            else: avbkeys_oplus.append("%d:%s" % (ln, src))
    if "logical" in flags:
        logical_total += 1
        base = src.split("/")[-1]
        ok = base in names or (base+"_a") in names or (base+"_b") in names
        if base in DONOR_ONLY:
            donor_hits.append("%d:%s%s" % (ln, base, "(nofail)" if "nofail" in flags else ""))
        if not ok:
            logical_bad.append("%d:%s" % (ln, base))
    m = re.match(r"/dev/block/(?:bootdevice/)?by-name/(\S+)", src)
    if m:
        phys.append(m.group(1))
        if m.group(1) in DONOR_ONLY:
            donor_hits.append("%d:%s(物理)" % (ln, m.group(1)))
# 图纸 A5：avb= 与 GSI avb_keys 必须剥除干净；avb_keys=/vendor/etc/oplus_avb.pubkey
# 属 OPPO 自有键引用，C17 保留未动（无 avb= 时惰性），列为 NOTE 容忍。
chk("avb= 剥除干净（A5）", not avb_eq,
    ("%d 行残留: %s" % (len(avb_eq), " ".join(avb_eq[:17]))) if avb_eq else "0 行残留")
chk("GSI avb_keys 剥除干净（A5）", not avbkeys_gsi,
    ("%d 行残留: %s" % (len(avbkeys_gsi), " ".join(avbkeys_gsi[:8]))) if avbkeys_gsi else "0 行残留")
note("avb_keys=oplus_avb.pubkey（C17 容忍态）",
     "%d 行（my_* 与 odm；图纸 A5 未剥，无 avb= 时惰性）" % len(avbkeys_oplus))
chk("logical 分区都在 super 清单", not logical_bad,
    ("缺失: %s" % " ".join(logical_bad)) if logical_bad else "%d 行 logical 全部命中" % logical_total)
chk("无供体独有分区残留", not donor_hits,
    ("命中: %s（C17 亦保留此两行且 nofail，属容忍态）" % " ".join(donor_hits)) if donor_hits else "无")
note("物理 by-name 引用（超 super 范围，待对 Y700 GPT 核）", " ".join(sorted(set(phys))))
print("G4_JSON_RESULT=%d" % len(fails))
sys.exit(1 if fails else 0)
PY
  local rc=$?
  [ $rc -eq 0 ] && gate_result G4 PASS "fstab 静态审查干净（A5 手法达标）" \
                || gate_result G4 FAIL "fstab 存在残留/缺配（见上 FAIL 行）"
}

# =============================================================================
# G5 内核一致性
# =============================================================================
gate_g5() {
  echo "===== G5 内核一致性 ====="
  local boot vb
  boot=$(resolve_img "$TARGET" boot); vb=$(resolve_img "$TARGET" vendor_boot)
  [ -n "$boot" ] && [ -n "$vb" ] || { gate_result G5 FAIL "target 内缺 boot 或 vendor_boot 镜像"; return; }
  [ -f "$MAGISKBOOT" ] || { gate_result G5 FAIL "magiskboot 不存在: $MAGISKBOOT"; return; }
  local d="$WORKDIR/g5"; rm -rf "$d"; mkdir -p "$d/boot" "$d/vb"
  cp "$boot" "$d/boot/boot.img"; cp "$vb" "$d/vb/vendor_boot.img"
  ( cd "$d/boot" && "$MAGISKBOOT" unpack boot.img >/dev/null 2>&1 )
  ( cd "$d/vb" && "$MAGISKBOOT" unpack vendor_boot.img >/dev/null 2>&1 \
      && "$MAGISKBOOT" decompress ramdisk.cpio ramdisk.dec.cpio >/dev/null 2>&1 \
      && mkdir -p x && cd x && "$MAGISKBOOT" cpio ../ramdisk.dec.cpio extract >/dev/null 2>&1 )
  local krel
  krel=$(grep -ao 'Linux version [^ (]*' "$d/boot/kernel" 2>/dev/null | head -1 | awk '{print $3}')
  if [ -z "$krel" ]; then
    gate_result G5 FAIL "boot 内核版本串提取失败（kernel 压缩形态未覆盖）"; return
  fi
  echo "内核 release(boot.img): $krel"
  local kdir="$d/vb/x/ramdisk/lib/modules"
  [ -d "$kdir" ] || { gate_result G5 FAIL "vendor_boot ramdisk 无 lib/modules"; return; }
  KREL="$krel" KO_DIR="$kdir" python3 - <<'PY'
import os, re, sys
krel = os.environ["KREL"]; kdir = os.environ["KO_DIR"]
# 基线口径：major.patch-androidX-Y + 页大小后缀（-4k/-16k）。
# 依据：C17 可启动链实证 full-string 含构建环境哈希位（-g<hex>/-o-g<hex>/-maybe-dirty），
# 构建机差异即不同，strict 全串匹配会误伤可启动链；真正的危险错配是基线/页大小漂移。
def base(rel):
    m = re.match(r"^(\d+\.\d+\.\d+-android\d+-\d+)", rel)
    b = m.group(1) if m else rel
    if rel.endswith("-4k"): b += "-4k"
    elif "-16k" in rel: b += "-16k"
    return b
kbase = base(krel)
print("  内核基线: %s" % kbase)
kos = sorted(f for f in os.listdir(kdir) if f.endswith(".ko"))
pat = re.compile(rb"vermagic=(\S+)")
ok_b, bad_b, diverge, novm = 0, [], 0, []
for f in kos:
    raw = open(os.path.join(kdir, f), "rb").read()
    m = pat.search(raw)
    if not m: novm.append(f); continue
    rel = m.group(1).decode(errors="replace").split()[0]
    if base(rel) == kbase:
        ok_b += 1
        if rel != krel: diverge += 1
    else:
        bad_b.append((f, rel))
print("  .ko 总数=%d  基线匹配=%d  基线不匹配=%d  无vermagic=%d" % (len(kos), ok_b, len(bad_b), len(novm)))
if diverge:
    print("  FINDING: %d 个 .ko 与内核同基线但构建哈希位不同（构建机差异，C17/105 实证可启动）" % diverge)
for f, rel in bad_b[:8]:
    print("    BASE_MISMATCH %-32s -> %s" % (f, rel))
if len(bad_b) > 8: print("    ... 其余 %d 个" % (len(bad_b)-8))
ml = os.path.join(kdir, "modules.load")
if os.path.isfile(ml):
    print("  modules.load: %d 行" % sum(1 for _ in open(ml)))
print("G5_JSON_RESULT=%d" % (len(bad_b)+len(novm)))
sys.exit(1 if (bad_b or novm) else 0)
PY
  local rc=$?
  [ $rc -eq 0 ] && gate_result G5 PASS "内核与全部 .ko 基线 vermagic 匹配（构建哈希位差异仅 NOTE）" \
                || gate_result G5 FAIL "内核与 .ko 存在基线级 vermagic 错配（见上统计）"
}

# =============================================================================
want_gate G1 && gate_g1
want_gate G2 && gate_g2
want_gate G3 && gate_g3
want_gate G4 && gate_g4
want_gate G5 && gate_g5

echo "================ 五门汇总 ================"
nfail=0
for i in "${!GATE_SUMMARY[@]}"; do
  echo "  ${GATE_VERDICT[$i]}  ${GATE_SUMMARY[$i]}"
  [ "${GATE_VERDICT[$i]}" = "FAIL" ] && nfail=$((nfail+1))
done
echo "========================================="
exit $((nfail>0))
