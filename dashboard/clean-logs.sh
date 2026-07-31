#!/usr/bin/env bash
#
# clean-logs.sh — 清理 /var/log 下超过指定天数的陈旧日志
#
# === 用法 ===
#   sudo ./clean-logs.sh              # dry-run,仅展示将删除的文件(默认)
#   sudo ./clean-logs.sh --apply      # 实际执行删除
#   sudo ./clean-logs.sh --apply 30   # 自定义保留天数(默认 14)
#
# === 说明 ===
#   * 按 mtime 判断,删除超过保留天数的普通文件(含 .gz/.1 等轮转日志)。
#   * lastlog/wtmp/btmp 等二进制记账文件不删除。
#   * journal/ 目录不直接删文件,改用 journalctl --vacuum-time。
#   * private/、chrony/ 等无权限目录自动跳过。
#
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '/^# === 用法/,/^# === 说明/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

# ---------- 参数 ----------
DAYS=14
APPLY=0
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        *[!0-9]*|'') : ;;          # 非数字(已被 --apply 消费),忽略
        *) DAYS="$arg" ;;
    esac
done

LOG_DIR="${LOG_DIR:-/var/log}"

# ---------- 颜色 ----------
if [[ -t 1 ]]; then
    C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'
    C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
    C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''; C_RST=''
fi

# 受保护的二进制 / 特殊文件(按 basename 匹配,用 -name 排除更可靠)
PROTECTED_NAMES=(lastlog wtmp btmp)
exclude_args=()
for n in "${PROTECTED_NAMES[@]}"; do
    exclude_args+=( ! -name "$n" )
done

# 直接删除会出问题的目录:交给专门工具或无权限,跳过
PRUNE_DIRS=(
    "$LOG_DIR/journal"        # 用 journalctl --vacuum-time 处理
    "$LOG_DIR/private"        # syslog 私有,无权限
    "$LOG_DIR/chrony"         # chrony 自管,无权限
)

# 构造 find 的 -prune 参数
prune_args=()
for d in "${PRUNE_DIRS[@]}"; do
    prune_args+=( -path "$d" -prune -o )
done

# ---------- 收集目标文件 ----------
mapfile -t targets < <(
    find "$LOG_DIR" "${prune_args[@]}" -type f -mtime +"$DAYS" \
        "${exclude_args[@]}" -printf '%s\t%p\n' 2>/dev/null \
    | sort -t$'\t' -k2
)

# ---------- 统计 ----------
total_bytes=0
# 判断是否为"轮转产物"(有 .N / .gz / .xz / .bz2 等后缀)。
# 有后缀 → 安全 rm;无后缀(活跃日志)→ truncate 清空,避免 rsyslog 的 fd 悬空。
is_rotated() { [[ "$1" =~ \.(gz|xz|bz2|[0-9]+)(\.(gz|xz|bz2))?$ ]]; }

while IFS=$'\t' read -r size path; do
    total_bytes=$(( total_bytes + size ))
    if (( APPLY )); then
        if is_rotated "$path"; then
            rm -f -- "$path" && printf "${C_GREEN}已删除${C_RST}  %s\n" "$path"
        else
            truncate -s 0 -- "$path" && printf "${C_GREEN}已清空${C_RST}  %s\n" "$path"
        fi
    else
        verb="将删除"; is_rotated "$path" || verb="将清空"
        printf "${C_RED}%s${C_RST}  %s\n" "$verb" "$path"
    fi
done < <(printf '%s\n' "${targets[@]}") 2>/dev/null || true

# ---------- journal 单独处理 ----------
journal_msg=""
if command -v journalctl >/dev/null 2>&1; then
    if (( APPLY )); then
        journal_msg="$(journalctl --vacuum-time="${DAYS}d" 2>&1 | tail -1 || true)"
    else
        journal_msg="vacuum-time=${DAYS}d (dry-run,未执行)"
    fi
else
    journal_msg="${C_YELLOW}journalctl 未安装,跳过 journal 清理${C_RST}"
fi

# ---------- 汇总 ----------
hr() { # 字节 -> 人类可读
    local b=$1
    awk -v b="$b" 'BEGIN{
        split("B KB MB GB TB",u," ");
        i=1; while(b>=1024 && i<5){b/=1024; i++}
        printf("%.1f %s", b, u[i]) }'
}

mode="DRY-RUN${C_DIM}(未删除,加 --apply 执行)${C_RST}"
(( APPLY )) && mode="${C_GREEN}APPLY${C_RST}(已删除)"
echo
printf "保留天数      : %d 天\n" "$DAYS"
printf "模式          : %b\n" "$mode"
printf "待清理文件数  : %d\n" "${#targets[@]}"
printf "可释放空间    : %s\n" "$(hr "$total_bytes")"
printf "journal 处理  : %b\n" "$journal_msg"
