#!/bin/bash
# stealtask_tune.sh - 窃取任务调度调优工具
# 用法:
#   宿主机级别:
#     stealtask_tune.sh check          检查环境
#     stealtask_tune.sh backup         备份当前状态
#     stealtask_tune.sh apply          应用调优（启用STEAL特性）
#     stealtask_tune.sh status         查看当前 STEAL 状态及 cmdline 配置
#     stealtask_tune.sh rollback       用最近一次备份回滚
#   容器级别（仅新版本内核）:
#     stealtask_tune.sh container-apply    <cgroup名>  启用指定 cgroup 的 cpu.steal_task
#     stealtask_tune.sh container-rollback <cgroup名>  禁用指定 cgroup 的 cpu.steal_task
#     stealtask_tune.sh container-status   [cgroup名]  查看 steal_task 状态

set -euo pipefail

BACKUP_DIR="/var/tmp/stealtask_backups"
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

get_steal_state() {
    local sf
    sf=$(get_sched_features_path)
    if [ -z "$sf" ]; then
        echo "UNKNOWN"
        return
    fi
    if grep -qow 'STEAL' "$sf" 2>/dev/null; then
        echo "STEAL"
    else
        echo "NO_STEAL"
    fi
}

# 通过 sched_max_steal_count 判版本：存在→旧版本，不存在→新版本
check_steal_version() {
    if [ -f /proc/sys/kernel/sched_max_steal_count ]; then
        echo "旧版本"
    else
        echo "新版本"
    fi
}

# 查找 cgroup cpu.steal_task 文件路径
# 先用快速路径尝试常见位置，再用 find 兜底处理嵌套路径和非标准挂载点
get_steal_task_cgroup_path() {
    local cgroup="$1"

    # 快速路径 1: cgroup v1，cpu 控制器直接挂载
    if [ -f "/sys/fs/cgroup/cpu/${cgroup}/cpu.steal_task" ]; then
        echo "/sys/fs/cgroup/cpu/${cgroup}/cpu.steal_task"
        return
    fi

    # 快速路径 2: cgroup v2 统一层级
    if [ -f "/sys/fs/cgroup/${cgroup}/cpu.steal_task" ]; then
        echo "/sys/fs/cgroup/${cgroup}/cpu.steal_task"
        return
    fi

    # 兜底搜索：处理嵌套 cgroup 路径（如 system.slice/docker-xxx.scope）或非标准挂载点
    find /sys/fs/cgroup/ -path "*/${cgroup}/cpu.steal_task" -type f 2>/dev/null | head -1
}

# 获取容器级 steal_task 状态
get_steal_task_state() {
    local steal_task_file="$1"
    if [ -z "$steal_task_file" ]; then
        echo "UNKNOWN"
        return
    fi
    local val
    val=$(cat "$steal_task_file" 2>/dev/null || echo "")
    case "$val" in
        1) echo "已启用" ;;
        0) echo "已禁用" ;;
        *) echo "UNKNOWN" ;;
    esac
}

get_cmdline_steal_limit() {
    if [ -f /proc/cmdline ]; then
        grep -o 'sched_steal_node_limit=[0-9]*' /proc/cmdline 2>/dev/null || echo "未配置"
    else
        echo "无法读取"
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

    if [ "$errors" -gt 0 ]; then
        exit 1
    fi

    local steal
    steal=$(get_steal_state)
    echo "当前 STEAL 状态: ${steal}"
    echo "内核版本: $(check_steal_version)"
    echo "sched_steal_node_limit: $(get_cmdline_steal_limit)"
    echo "环境检查通过"
}

# ---------- backup ----------
do_backup() {
    init_backup_dir
    echo "备份当前状态到 ${BACKUP_FILE}"

    local sf
    sf=$(get_sched_features_path)
    local steal
    steal=$(get_steal_state)
    local steal_limit
    steal_limit=$(get_cmdline_steal_limit)
    local steal_ver
    steal_ver=$(check_steal_version)

    echo "sched_features_path=${sf}" > "$BACKUP_FILE"
    echo "steal_state=${steal}" >> "$BACKUP_FILE"
    echo "sched_steal_node_limit=${steal_limit}" >> "$BACKUP_FILE"
    echo "steal_version=${steal_ver}" >> "$BACKUP_FILE"

    echo "  STEAL 状态: ${steal}"
    echo "  内核版本: ${steal_ver}"
    echo "  sched_steal_node_limit: ${steal_limit}"
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

    local steal
    steal=$(get_steal_state)
    if [ "$steal" = "STEAL" ]; then
        echo "警告: STEAL 已启用，跳过此步骤"
    fi

    do_backup

    echo "=== 应用调优 ==="

    echo "1. 启用 STEAL 特性"
    if [ "$steal" != "STEAL" ]; then
        echo "STEAL" > "$sf"
        echo "   写入 STEAL → ${sf}"
    fi

    echo ""
    echo "2. 版本与参数说明"
    local steal_ver
    steal_ver=$(check_steal_version)
    if [ "$steal_ver" = "旧版本" ]; then
        echo "   当前内核版本: 旧版本"
        echo "   当前 sched_steal_node_limit: $(get_cmdline_steal_limit)"
        echo "   注意: 旧版本需在 grub.cfg 中添加 sched_steal_node_limit=<NUMA节点数> 并重启"
        echo "   如需配置，请手动修改 /boot/efi/EFI/openEuler/grub.cfg 并重启生效"
    else
        echo "   当前内核版本: 新版本"
        echo "   新版本无需额外参数，echo STEAL > sched_features 即刻生效"
    fi

    echo "调优已生效"
}

# ---------- status ----------
do_status() {
    local sf
    sf=$(get_sched_features_path)
    local steal
    steal=$(get_steal_state)

    echo "sched_features 路径: ${sf:-未找到}"
    echo "STEAL 状态: ${steal}"
    echo "内核版本: $(check_steal_version)"
    echo "sched_steal_node_limit: $(get_cmdline_steal_limit)"
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
    local steal_state
    steal_state=$(grep ^steal_state= "$latest" | cut -d= -f2-)

    echo "1. 恢复 STEAL 状态 = ${steal_state}"
    if [ -n "$sf_path" ] && [ -w "$sf_path" ]; then
        if [ "$steal_state" = "STEAL" ]; then
            echo "STEAL" > "$sf_path"
        else
            echo "NO_STEAL" > "$sf_path"
        fi
    elif [ -n "$sf_path" ]; then
        echo "警告: ${sf_path} 不可写，跳过" >&2
    else
        local sf
        sf=$(get_sched_features_path)
        if [ -n "$sf" ] && [ -w "$sf" ]; then
            if [ "$steal_state" = "STEAL" ]; then
                echo "STEAL" > "$sf"
            else
                echo "NO_STEAL" > "$sf"
            fi
        else
            echo "警告: 无法找到可写的 sched_features 文件，跳过" >&2
        fi
    fi

    echo ""
    echo "2. 版本与参数说明"
    local saved_ver
    saved_ver=$(grep ^steal_version= "$latest" 2>/dev/null | cut -d= -f2- || echo "未知")
    if [ "$saved_ver" = "旧版本" ]; then
        local saved_limit
        saved_limit=$(grep ^sched_steal_node_limit= "$latest" | cut -d= -f2-)
        echo "   备份中的内核版本: 旧版本"
        echo "   备份中的 sched_steal_node_limit: ${saved_limit}"
        echo "   grub.cfg 参数需要手动恢复并重启，本脚本不自动修改"
    else
        echo "   备份中的内核版本: ${saved_ver:-新版本}"
        echo "   新版本无需恢复 cmdline 参数，STEAL 状态已回滚"
    fi

    echo "回滚完成"
}

# ---------- container_apply: 设置容器 cgroup cpu.steal_task ----------
do_container_apply() {
    local cgrp="$1"
    if [ -z "$cgrp" ]; then
        echo "用法: $0 container-apply <cgroup名>" >&2
        exit 1
    fi

    local steal_task_file
    steal_task_file=$(get_steal_task_cgroup_path "$cgrp")
    if [ -z "$steal_task_file" ]; then
        echo "错误: 未找到 cgroup cpu.steal_task 文件（尝试了 /sys/fs/cgroup/cpu/${cgrp}/cpu.steal_task 和 /sys/fs/cgroup/${cgrp}/cpu.steal_task）" >&2
        exit 1
    fi

    local ver
    ver=$(check_steal_version)
    if [ "$ver" != "新版本" ]; then
        echo "错误: 容器级 steal_task 仅支持新版本内核（当前: ${ver}）" >&2
        exit 1
    fi

    local state
    state=$(get_steal_task_state "$steal_task_file")
    if [ "$state" = "已启用" ]; then
        echo "警告: ${cgrp} 的 steal_task 已启用，跳过"
        exit 0
    fi

    if [ ! -w "$steal_task_file" ]; then
        echo "错误: ${steal_task_file} 不可写（需要 root 权限）" >&2
        exit 1
    fi

    echo "1" > "$steal_task_file"
    echo "容器 ${cgrp} 的 cpu.steal_task 已启用（写入 1 → ${steal_task_file}）"
}

# ---------- container_rollback: 回滚容器 cgroup cpu.steal_task ----------
do_container_rollback() {
    local cgrp="$1"
    if [ -z "$cgrp" ]; then
        echo "用法: $0 container-rollback <cgroup名>" >&2
        exit 1
    fi

    local steal_task_file
    steal_task_file=$(get_steal_task_cgroup_path "$cgrp")
    if [ -z "$steal_task_file" ]; then
        echo "错误: 未找到 cgroup cpu.steal_task 文件" >&2
        exit 1
    fi

    if [ ! -w "$steal_task_file" ]; then
        echo "错误: ${steal_task_file} 不可写（需要 root 权限）" >&2
        exit 1
    fi

    echo "0" > "$steal_task_file"
    echo "容器 ${cgrp} 的 cpu.steal_task 已禁用（写入 0 → ${steal_task_file}）"
}

# ---------- container_status: 查看容器 cgroup steal_task 状态 ----------
do_container_status() {
    local cgrp="$1"

    local steal_task_file
    if [ -n "$cgrp" ]; then
        steal_task_file=$(get_steal_task_cgroup_path "$cgrp")
        if [ -z "$steal_task_file" ]; then
            echo "错误: 未找到 cgroup ${cgrp} 的 cpu.steal_task 文件" >&2
            exit 1
        fi
        echo "cgroup: ${cgrp}"
        echo "cpu.steal_task 路径: ${steal_task_file}"
        echo "状态: $(get_steal_task_state "$steal_task_file")"
    else
        # 列出所有可访问的 cpu.steal_task
        echo "可检测的 cpu.steal_task 文件:"
        find /sys/fs/cgroup/ -name "cpu.steal_task" -type f 2>/dev/null | while IFS= read -r f; do
            local c
            c=$(dirname "$f" | sed 's|/sys/fs/cgroup/cpu/||;s|/sys/fs/cgroup/||')
            local s
            s=$(get_steal_task_state "$f")
            echo "  ${c}: ${s}"
        done
    fi
}

# ---------- 主入口 ----------
if [ $# -lt 1 ]; then
    echo "用法: $0 {check|backup|apply|status|rollback|container-apply|container-rollback|container-status} [参数...]"
    echo ""
    echo "  宿主机级别:"
    echo "    check                    检查环境"
    echo "    backup                   备份当前状态"
    echo "    apply                    应用调优（启用STEAL特性）"
    echo "    status                   查看当前 STEAL 状态"
    echo "    rollback                 用最近一次备份回滚"
    echo ""
    echo "  容器级别（仅新版本内核）:"
    echo "    container-apply   <cgrp>  启用指定 cgroup 的 cpu.steal_task"
    echo "    container-rollback <cgrp> 禁用指定 cgroup 的 cpu.steal_task"
    echo "    container-status  [cgrp]  查看容器 steal_task 状态（不指定则列出所有）"
    exit 1
fi

command=$1
shift

case "$command" in
    check)              do_check ;;
    backup)             do_backup ;;
    apply)              do_apply "$@" ;;
    status)             do_status ;;
    rollback)           do_rollback ;;
    container-apply)    do_container_apply "$@" ;;
    container-rollback) do_container_rollback "$@" ;;
    container-status)   do_container_status "$@" ;;
    *)
        echo "未知命令: $command"
        exit 1
        ;;
esac