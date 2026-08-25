#!/bin/bash
# numa_sched_tune.sh - NUMA 调度并行调优工具
# 用法:
#   numa_sched_tune.sh check          检查环境
#   numa_sched_tune.sh backup         备份当前状态
#   numa_sched_tune.sh apply          应用调优（启用PARAL + 设置sched_util_low_pct=100）
#   numa_sched_tune.sh status         查看当前 PARAL 状态及 sched_util_low_pct 值
#   numa_sched_tune.sh rollback       用最近一次备份回滚

set -euo pipefail

UTIL_LOW_PCT_FILE="/proc/sys/kernel/sched_util_low_pct"
BACKUP_DIR="/var/tmp/numa_sched_backups"
BACKUP_FILE="${BACKUP_DIR}/backup_$(date +%s).lst"

get_sched_features_path() {
    if [ -f "/sys/kernel/debug/sched/features" ]; then
        echo "/sys/kernel/debug/sched/features"
    elif [ -f "/sys/kernel/debug/sched_features" ]; then
        echo "/sys/kernel/debug/sched_features"
    else
        echo ""
    fi
}

get_paral_state() {
    local sf
    sf=$(get_sched_features_path)
    if [ -z "$sf" ]; then
        echo "UNKNOWN"
        return
    fi
    if grep -qow 'PARAL' "$sf" 2>/dev/null; then
        echo "PARAL"
    else
        echo "NO_PARAL"
    fi
}

init_backup_dir() {
    mkdir -p "$BACKUP_DIR"
}

# ---------- check ----------
do_check() {
    local errors=0

    local sf
    sf=$(get_sched_features_path)
    if [ -z "$sf" ]; then
        echo "错误: 未找到 sched_features 文件（尝试了 /sys/kernel/debug/sched/features 和 /sys/kernel/debug/sched_features）" >&2
        errors=1
    else
        if [ -w "$sf" ]; then
            echo "sched_features 文件: ${sf} (可写)"
        else
            echo "错误: sched_features 文件不可写（${sf}，需要 root 权限）" >&2
            errors=1
        fi
    fi

    if [ ! -f "$UTIL_LOW_PCT_FILE" ]; then
        echo "错误: sched_util_low_pct 文件不存在（${UTIL_LOW_PCT_FILE}）" >&2
        errors=1
    elif [ ! -w "$UTIL_LOW_PCT_FILE" ]; then
        echo "错误: sched_util_low_pct 文件不可写（${UTIL_LOW_PCT_FILE}，需要 root 权限）" >&2
        errors=1
    fi

    if [ "$errors" -gt 0 ]; then
        exit 1
    fi

    local paral
    paral=$(get_paral_state)
    echo "当前 PARAL 状态: ${paral}"
    echo "sched_util_low_pct 当前值: $(cat "$UTIL_LOW_PCT_FILE")"
    echo "环境检查通过"
}

# ---------- backup ----------
do_backup() {
    init_backup_dir
    echo "备份当前状态到 ${BACKUP_FILE}"

    local sf
    sf=$(get_sched_features_path)
    local paral
    paral=$(get_paral_state)
    local low_pct
    low_pct=$(cat "$UTIL_LOW_PCT_FILE")

    echo "sched_features_path=${sf}" > "$BACKUP_FILE"
    echo "paral_state=${paral}" >> "$BACKUP_FILE"
    echo "sched_util_low_pct=${low_pct}" >> "$BACKUP_FILE"

    echo "  PARAL 状态: ${paral}"
    echo "  sched_util_low_pct: ${low_pct}"
    echo "备份完成"
}

# ---------- apply ----------
do_apply() {
    local sf
    sf=$(get_sched_features_path)
    if [ -z "$sf" ]; then
        echo "错误: 未找到 sched_features 文件" >&2
        exit 1
    fi

    local paral
    paral=$(get_paral_state)
    if [ "$paral" = "PARAL" ]; then
        echo "警告: PARAL 已启用，跳过此步骤"
    fi

    do_backup

    echo "=== 应用调优 ==="

    echo "1. 启用 PARAL 特性"
    if [ "$paral" != "PARAL" ]; then
        echo "PARAL" > "$sf"
        echo "   写入 PARAL → ${sf}"
    fi

    echo "2. 设置 sched_util_low_pct = 100"
    echo 100 > "$UTIL_LOW_PCT_FILE"

    echo "调优已生效"
}

# ---------- status ----------
do_status() {
    local sf
    sf=$(get_sched_features_path)
    local paral
    paral=$(get_paral_state)

    echo "sched_features 路径: ${sf:-未找到}"
    echo "PARAL 状态: ${paral}"
    echo "sched_util_low_pct: $(cat "$UTIL_LOW_PCT_FILE" 2>/dev/null || echo 无法读取)"
}

# ---------- rollback ----------
do_rollback() {
    local latest
    latest=$(ls -t "${BACKUP_DIR}"/backup_*.lst 2>/dev/null | head -1)
    if [ -z "$latest" ]; then
        echo "错误: 未找到备份文件" >&2
        exit 1
    fi
    echo "使用备份文件: ${latest}"

    local sf_path
    sf_path=$(grep ^sched_features_path= "$latest" | cut -d= -f2-)
    local paral_state
    paral_state=$(grep ^paral_state= "$latest" | cut -d= -f2-)
    local low_pct
    low_pct=$(grep ^sched_util_low_pct= "$latest" | cut -d= -f2-)

    echo "1. 恢复 sched_util_low_pct = ${low_pct}"
    if [ -w "$UTIL_LOW_PCT_FILE" ]; then
        echo "$low_pct" > "$UTIL_LOW_PCT_FILE"
    else
        echo "警告: sched_util_low_pct 不可写，跳过" >&2
    fi

    echo "2. 恢复 PARAL 状态 = ${paral_state}"
    if [ -n "$sf_path" ] && [ -w "$sf_path" ]; then
        if [ "$paral_state" = "PARAL" ]; then
            echo "PARAL" > "$sf_path"
        else
            echo "NO_PARAL" > "$sf_path"
        fi
    elif [ -n "$sf_path" ]; then
        echo "警告: ${sf_path} 不可写，跳过" >&2
    else
        local sf
        sf=$(get_sched_features_path)
        if [ -n "$sf" ] && [ -w "$sf" ]; then
            if [ "$paral_state" = "PARAL" ]; then
                echo "PARAL" > "$sf"
            else
                echo "NO_PARAL" > "$sf"
            fi
        else
            echo "警告: 无法找到可写的 sched_features 文件，跳过" >&2
        fi
    fi

    echo "回滚完成"
}

# ---------- 主入口 ----------
if [ $# -lt 1 ]; then
    echo "用法: $0 {check|backup|apply|status|rollback} [参数...]"
    exit 1
fi

command=$1
shift

case "$command" in
    check)    do_check ;;
    backup)   do_backup ;;
    apply)    do_apply "$@" ;;
    status)   do_status ;;
    rollback) do_rollback ;;
    *)
        echo "未知命令: $command"
        exit 1
        ;;
esac