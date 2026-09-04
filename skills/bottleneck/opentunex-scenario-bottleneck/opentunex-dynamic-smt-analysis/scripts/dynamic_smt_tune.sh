#!/bin/bash
# dynamic_smt_tune.sh - 动态 SMT（同步多线程）调优工具
# 用法:
#   dynamic_smt_tune.sh check               检查环境
#   dynamic_smt_tune.sh apply [THRESHOLD]   使能动态SMT（THRESHOLD: 0-100, 默认100）
#   dynamic_smt_tune.sh status              查看当前状态
#   dynamic_smt_tune.sh rollback            回退动态SMT配置
#   dynamic_smt_tune.sh oeaware enable|disable [THRESHOLD]  oeaware集成

set -euo pipefail

BACKUP_DIR="/var/tmp/dynamic_smt_backups"
BACKUP_FILE="${BACKUP_DIR}/backup_$(date +%s).lst"
UTIL_RATIO_FILE="/proc/sys/kernel/sched_util_ratio"
UTIL_RATIO_BAK="/tmp/sched_util_ratio.bak"
OEAWARE_CONFIG="/etc/oeAware/plugin/dynamic_smt.yaml"

init_backup_dir() {
    mkdir -p "$BACKUP_DIR"
}

get_sched_features_path() {
    if [ -w "/sys/kernel/debug/sched_features" ]; then
        echo "/sys/kernel/debug/sched_features"
    elif [ -w "/sys/kernel/debug/sched/features" ]; then
        echo "/sys/kernel/debug/sched/features"
    elif [ -f "/sys/kernel/debug/sched_features" ]; then
        echo "/sys/kernel/debug/sched_features"
    elif [ -f "/sys/kernel/debug/sched/features" ]; then
        echo "/sys/kernel/debug/sched/features"
    else
        echo ""
    fi
}

get_keep_on_core_state() {
    local sf
    sf=$(get_sched_features_path)
    if [ -z "$sf" ]; then
        echo "UNKNOWN"
        return
    fi
    if grep -qow 'KEEP_ON_CORE' "$sf" 2>/dev/null; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

get_util_ratio() {
    if [ -f "$UTIL_RATIO_FILE" ] && [ -r "$UTIL_RATIO_FILE" ]; then
        cat "$UTIL_RATIO_FILE" 2>/dev/null || echo "N/A"
    else
        echo "N/A"
    fi
}

# ---------- check ----------
do_check() {
    local errors=0
    local sf
    sf=$(get_sched_features_path)

    echo "=== 动态 SMT 环境检查 ==="

    if [ "$EUID" -ne 0 ]; then
        echo "  错误: 需要 root 权限" >&2
        errors=1
    else
        echo "  用户权限: root (OK)"
    fi

    if [ -z "$sf" ]; then
        echo "  错误: 未找到可写的 sched_features 文件" >&2
        errors=1
    else
        echo "  sched_features: ${sf} (可写)"
    fi

    if [ -n "$sf" ] && ! grep -q 'KEEP_ON_CORE' "$sf" 2>/dev/null; then
        echo "  警告: 内核可能不支持 KEEP_ON_CORE 特性"
    fi

    if [ -f "$UTIL_RATIO_FILE" ] && [ -w "$UTIL_RATIO_FILE" ]; then
        echo "  sched_util_ratio: ${UTIL_RATIO_FILE} (可写), 当前值=$(get_util_ratio)"
    else
        echo "  错误: ${UTIL_RATIO_FILE} 不可写" >&2
        errors=1
    fi

    local koc_state
    koc_state=$(get_keep_on_core_state)
    echo "  KEEP_ON_CORE 状态: ${koc_state}"

    if command -v oeawarectl &>/dev/null; then
        echo "  oeawarectl: 可用"
    else
        echo "  oeawarectl: 不可用（将使用独立脚本）"
    fi

    if [ "$errors" -gt 0 ]; then
        exit 1
    fi
    echo ""
    echo "环境检查通过"
}

# ---------- apply ----------
do_apply() {
    local threshold="${1:-100}"

    if [ "$EUID" -ne 0 ]; then
        echo "错误: 需要 root 权限" >&2
        exit 1
    fi

    if ! [[ "$threshold" =~ ^[0-9]+$ ]] || [ "$threshold" -lt 0 ] || [ "$threshold" -gt 100 ]; then
        echo "错误: threshold 必须为 0-100 之间的整数" >&2
        exit 1
    fi

    local sf
    sf=$(get_sched_features_path)
    if [ -z "$sf" ]; then
        echo "错误: 未找到可写的 sched_features 文件" >&2
        exit 1
    fi

    local koc_state
    koc_state=$(get_keep_on_core_state)

    init_backup_dir

    echo "=== 动态 SMT 使能 ==="
    echo "threshold: ${threshold}"
    echo "KEEP_ON_CORE 当前状态: ${koc_state}"
    echo ""

    local plan_file="${BACKUP_DIR}/apply_plan_$(date +%s).txt"
    {
        echo "=== 动态 SMT 执行计划 ==="
        echo "生成时间: $(date)"
        echo "action: enable"
        echo "threshold: ${threshold}"
        echo ""
        echo "--- 将要执行的操作 ---"
        echo "1. 备份 /proc/sys/kernel/sched_util_ratio -> ${UTIL_RATIO_BAK}"
        echo "2. 写入 sched_util_ratio = ${threshold}"
        echo "3. 写入 KEEP_ON_CORE -> ${sf}"
    } > "$plan_file"

    if [ "$koc_state" = "enabled" ]; then
        echo "KEEP_ON_CORE 已启用，将仅更新 sched_util_ratio" | tee -a "$plan_file"
    fi

    echo ""
    echo "执行计划已保存至: ${plan_file}"
    echo "---"
    echo "确认执行以上操作? (y/N)"
    read -r confirm
    if [ "${confirm,,}" != "y" ] && [ "${confirm,,}" != "yes" ]; then
        echo "已取消"
        exit 0
    fi

    echo "sched_features_path=${sf}" > "$BACKUP_FILE"
    echo "original_koc_state=${koc_state}" >> "$BACKUP_FILE"
    echo "original_util_ratio=$(get_util_ratio)" >> "$BACKUP_FILE"
    echo "applied_threshold=${threshold}" >> "$BACKUP_FILE"

    if [ -f "$UTIL_RATIO_FILE" ] && [ -r "$UTIL_RATIO_FILE" ]; then
        cat "$UTIL_RATIO_FILE" > "$UTIL_RATIO_BAK" 2>/dev/null || true
        echo "  已备份 sched_util_ratio -> ${UTIL_RATIO_BAK}"
    fi

    echo "$threshold" > "$UTIL_RATIO_FILE"
    echo "  sched_util_ratio = ${threshold}"

    if [ "$koc_state" != "enabled" ]; then
        echo "KEEP_ON_CORE" > "$sf"
        echo "  KEEP_ON_CORE 已启用"
    else
        echo "  KEEP_ON_CORE 已启用（跳过）"
    fi

    echo ""
    echo "Enabled dynamic_smt_tune with threshold=${threshold}"
}

# ---------- status ----------
do_status() {
    echo "=== 动态 SMT 当前状态 ==="

    local sf
    sf=$(get_sched_features_path)
    echo "sched_features: ${sf:-未找到}"

    local koc_state
    koc_state=$(get_keep_on_core_state)
    echo "KEEP_ON_CORE: ${koc_state}"

    echo "sched_util_ratio: $(get_util_ratio)"

    if [ -f "$UTIL_RATIO_BAK" ]; then
        echo "备份文件: ${UTIL_RATIO_BAK} ($(cat "$UTIL_RATIO_BAK" 2>/dev/null))"
    else
        echo "备份文件: 不存在"
    fi

    if command -v oeawarectl &>/dev/null; then
        echo "oeawarectl: 可用"
    else
        echo "oeawarectl: 不可用"
    fi
}

# ---------- rollback ----------
do_rollback() {
    echo "=== 动态 SMT 回退 ==="

    local sf
    sf=$(get_sched_features_path)
    if [ -z "$sf" ]; then
        echo "警告: 未找到可写的 sched_features 文件" >&2
    fi

    if [ -n "$sf" ] && [ -w "$sf" ]; then
        echo "NO_KEEP_ON_CORE" > "$sf"
        echo "  已写入 NO_KEEP_ON_CORE"
    else
        echo "  跳过: sched_features 不可写" >&2
    fi

    if [ -f "$UTIL_RATIO_BAK" ]; then
        local bak_val
        bak_val=$(cat "$UTIL_RATIO_BAK" 2>/dev/null)
        if [ -n "$bak_val" ] && [ -w "$UTIL_RATIO_FILE" ]; then
            echo "$bak_val" > "$UTIL_RATIO_FILE"
            echo "  已恢复 sched_util_ratio = ${bak_val}"
        else
            echo "  警告: 无法恢复 sched_util_ratio（${UTIL_RATIO_FILE} 不可写）" >&2
        fi
    else
        echo "  未找到备份文件 ${UTIL_RATIO_BAK}，跳过sched_util_ratio恢复"
    fi

    echo ""
    echo "Disabled dynamic_smt_tune, restored original sched_util_ratio if backup existed"
}

# ---------- oeaware ----------
do_oeaware() {
    local action="${1:-enable}"
    local threshold="${2:-100}"

    if ! command -v oeawarectl &>/dev/null; then
        echo "错误: oeawarectl 不可用" >&2
        exit 1
    fi

    local cfg_dir
    cfg_dir=$(dirname "$OEAWARE_CONFIG")
    mkdir -p "$cfg_dir"

    if [ "$action" = "enable" ]; then
        if ! [[ "$threshold" =~ ^[0-9]+$ ]] || [ "$threshold" -lt 0 ] || [ "$threshold" -gt 100 ]; then
            echo "错误: threshold 必须为 0-100 之间的整数" >&2
            exit 1
        fi

        echo "生成 oeaware 配置: ${OEAWARE_CONFIG}"

        cat > "$OEAWARE_CONFIG" << EOF
# dynamic_smt 动态 SMT oeaware 插件配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# threshold: ${threshold}

plugin: dynamic_smt_tune
enabled: true
parameters:
  threshold: ${threshold}
EOF

        echo "执行: oeawarectl -e dynamic_smt_tune"
        oeawarectl -e dynamic_smt_tune 2>/dev/null && echo "  oeaware 插件已使能" || echo "  警告: oeawarectl -e 执行失败"
    elif [ "$action" = "disable" ]; then
        echo "执行: oeawarectl -d dynamic_smt_tune"
        oeawarectl -d dynamic_smt_tune 2>/dev/null && echo "  oeaware 插件已禁用" || echo "  警告: oeawarectl -d 执行失败"
        rm -f "$OEAWARE_CONFIG"
        echo "  已删除 ${OEAWARE_CONFIG}"
    else
        echo "错误: oeaware action 仅支持 enable 或 disable" >&2
        exit 1
    fi
}

# ---------- 主入口 ----------
if [ $# -lt 1 ]; then
    echo "用法: $0 {check|apply|status|rollback|oeaware} [参数...]"
    echo ""
    echo "命令:"
    echo "  check                检查环境"
    echo "  apply [THRESHOLD]    使能动态SMT（THRESHOLD: 0-100, 默认100）"
    echo "  status               查看当前状态"
    echo "  rollback             回退动态SMT配置"
    echo "  oeaware enable|disable [THRESHOLD]  oeaware集成"
    echo ""
    echo "示例:"
    echo "  $0 check                # 检查环境"
    echo "  $0 apply                # 使能，使用默认阈值100"
    echo "  $0 apply 80             # 使能，阈值设为80"
    echo "  $0 rollback             # 回退配置"
    echo "  $0 oeaware enable 90    # 通过oeaware使能，阈值90"
    echo ""
    echo "验证命令:"
    echo "  cat /proc/sys/kernel/sched_util_ratio"
    echo "  grep -E 'KEEP_ON_CORE|NO_KEEP_ON_CORE' /sys/kernel/debug/sched/features"
    exit 1
fi

command=$1
shift

case "$command" in
    check)
        do_check
        ;;
    apply)
        THRESHOLD="${1:-100}"
        do_apply "$THRESHOLD"
        ;;
    status)
        do_status
        ;;
    rollback)
        do_rollback
        ;;
    oeaware)
        do_oeaware "$@"
        ;;
    *)
        echo "未知命令: $command"
        exit 1
        ;;
esac