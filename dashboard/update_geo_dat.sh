#!/bin/bash
#
# update_geo_dat.sh — 下载 v2ray-rules-dat 并用 v2dat 解包到 mosdns 数据目录
#
# 数据源: Loyalsoldier/v2ray-rules-dat
# 工具:   v2dat (IrineSistiana)
#
# 用法:
#   ./update_geo_dat.sh            # 下载并解包到默认目录
#   ./update_geo_dat.sh --check    # 仅检查 v2dat/curl 是否就绪，不下载
#   ./update_geo_dat.sh --restart  # 更新成功后自动重启 mosdns 使数据生效
#
# 可通过环境变量覆盖默认值，例如:
#   DAT_DIR=/opt/mosdns/dat ./update_geo_dat.sh
#
# cron 示例 (每天凌晨 3 点更新并重启):
#   0 3 * * * /root/mosdns_docker/dashboard/update_geo_dat.sh --restart >> /var/log/mosdns_dat_update.log 2>&1
#
set -euo pipefail

# ============ 配置 ============
# 脚本所在目录（用于定位仓库内置的 v2dat 二进制）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAT_DIR="${DAT_DIR:-$SCRIPT_DIR/mosdns/config/dat}"
REPO="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"
# geoip 需解包的 tag
GEOIP_TAGS=("private" "cn")
# geosite 需解包的 tag (注意 geolocation-!cn 用引号)
GEOSITE_TAGS=("cn" "gfw" "category-ads-all" "geolocation-!cn")

# 解析命令行参数
RESTART=false
CHECK_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --restart) RESTART=true ;;
    --check)   CHECK_ONLY=true ;;
    *) echo "[ERROR] 未知参数: $arg (可用: --check, --restart)" >&2; exit 1 ;;
  esac
done

# ============ 函数 ============
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

# 查找 v2dat: 优先环境变量 V2DAT → PATH → 仓库内置 ./v2dat
resolve_v2dat() {
  # 1. 环境变量显式指定
  if [ -n "${V2DAT:-}" ] && command -v "$V2DAT" >/dev/null 2>&1; then
    echo "$V2DAT"; return 0
  fi
  # 2. PATH 中查找
  if command -v v2dat >/dev/null 2>&1; then
    echo "v2dat"; return 0
  fi
  # 3. 仓库内置二进制（与本脚本同目录）
  if [ -x "$SCRIPT_DIR/v2dat" ]; then
    echo "$SCRIPT_DIR/v2dat"; return 0
  fi
  return 1
}

# ============ 前置检查 ============
log "前置检查..."
command -v curl  >/dev/null || die "未找到 curl"
V2DAT_BIN="$(resolve_v2dat)" || die "未找到 v2dat。请任选其一:
  1. 安装到 PATH:  sudo go install github.com/urlesistiana/v2dat@latest
  2. 放置仓库内置二进制: 把 v2dat 放到 $SCRIPT_DIR/
  3. 环境变量指定: export V2DAT=/path/to/v2dat"
[ -d "$DAT_DIR" ] || die "数据目录不存在: $DAT_DIR"

# --check: 只检查依赖，不下载
if $CHECK_ONLY; then
  log "依赖检查通过: curl=$(command -v curl), v2dat=$(command -v "$V2DAT_BIN"), DAT_DIR=$DAT_DIR"
  exit 0
fi

# ============ 下载 ============
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

log "工作目录: $WORK_DIR"
log "开始下载 geoip.dat / geosite.dat ..."

if ! curl -fsL --retry 3 --retry-delay 5 -o "$WORK_DIR/geoip.dat"   "$REPO/geoip.dat"; then
  die "下载 geoip.dat 失败"
fi
if ! curl -fsL --retry 3 --retry-delay 5 -o "$WORK_DIR/geosite.dat" "$REPO/geosite.dat"; then
  die "下载 geosite.dat 失败"
fi

# 校验: .dat 文件不能是空或过小
[ -s "$WORK_DIR/geoip.dat" ]   || die "geoip.dat 下载异常 (文件为空)"
[ -s "$WORK_DIR/geosite.dat" ] || die "geosite.dat 下载异常 (文件为空)"
log "下载完成: geoip.dat=$(stat -c%s "$WORK_DIR/geoip.dat") bytes, geosite.dat=$(stat -c%s "$WORK_DIR/geosite.dat") bytes"

# ============ 解包到临时目录 ============
OUT_DIR="$WORK_DIR/dat"
mkdir -p "$OUT_DIR"

log "开始解包..."
for tag in "${GEOIP_TAGS[@]}"; do
  "$V2DAT_BIN" unpack geoip -o "$OUT_DIR" -f "$tag" "$WORK_DIR/geoip.dat" >/dev/null \
    || die "解包 geoip:$tag 失败"
done
for tag in "${GEOSITE_TAGS[@]}"; do
  "$V2DAT_BIN" unpack geosite -o "$OUT_DIR" -f "$tag" "$WORK_DIR/geosite.dat" >/dev/null \
    || die "解包 geosite:$tag 失败"
done

# ============ 校验解包结果 ============
EXPECT=(geoip_private.txt geoip_cn.txt geosite_cn.txt geosite_gfw.txt \
        geosite_category-ads-all.txt geosite_geolocation-\!cn.txt)
for f in "${EXPECT[@]}"; do
  [ -s "$OUT_DIR/$f" ] || die "解包结果缺失或为空: $f"
done
log "解包完成，共 ${#EXPECT[@]} 个文件，校验通过"

# ============ 原子替换 ============
# 先备份当前数据，再用 mv 原子替换，任何一步失败都不影响现有数据
BACKUP_DIR="${DAT_DIR}.bak.$(date +%s)"
log "备份当前数据到: $BACKUP_DIR"
cp -a "$DAT_DIR" "$BACKUP_DIR"

log "替换数据文件..."
# 逐个替换，保留目录本身（避免影响权限/挂载）
for f in "${EXPECT[@]}"; do
  mv -f "$OUT_DIR/$f" "$DAT_DIR/$f"
done

log "更新成功。变更摘要:"
for f in "${EXPECT[@]}"; do
  new=$(stat -c%s "$DAT_DIR/$f")
  old=$(stat -c%s "$BACKUP_DIR/$f" 2>/dev/null || echo "?")
  flag=""
  if [ "$new" != "$old" ]; then flag="  <- 已变更"; fi
  printf "  %-40s %10s (原 %s)%s\n" "$f" "$new" "$old" "$flag"
done

# 备份保留 1 份即可，清理更早的备份
shopt -s nullglob
for b in "${DAT_DIR}.bak."*; do
  [ "$b" = "$BACKUP_DIR" ] && continue
  rm -rf "$b"
done

# ============ 重启 mosdns 使新数据生效 ============
if $RESTART; then
  if command -v docker >/dev/null 2>&1; then
    log "重启 mosdns 使新数据生效..."
    cd "$SCRIPT_DIR"
    if docker compose restart mosdns; then
      log "mosdns 已重启，新数据生效。"
    else
      log "警告: mosdns 重启失败，请手动执行: cd $SCRIPT_DIR && docker compose restart mosdns"
    fi
  else
    log "警告: 未找到 docker，请手动重启 mosdns: cd $SCRIPT_DIR && docker compose restart mosdns"
  fi
fi

log "完成。"
