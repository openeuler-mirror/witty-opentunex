#!/bin/bash
# coordination_burst.sh - Docker 算力统筹调优工具
# 用法:
#   coordination_burst.sh check          检查环境
#   coordination_burst.sh backup         备份当前状态
#   coordination_burst.sh apply [ratio] [container_id ...]
#                                        应用调优（ratio 默认 20，不指定容器则操作全部）
#   coordination_burst.sh status         查看当前 ratio 及容器 soft_quota
#   coordination_burst.sh rollback       用最近一次备份回滚

set -euo pipefail

RATIO_FILE="/proc/sys/kernel/sched_soft_runtime_ratio"
BACKUP_DIR="/var/tmp/coordination_burst_backups"
BACKUP_FILE="${BACKUP_DIR}/backup_$(date +%s).lst"

get_cgroup_cpu_path() {
    local cid="$1"
    local base="/sys/fs/cgroup/cpu"
    local path

    for path in \
        "${base}/system.slice/docker-${cid}.scope" \
        "${base}/docker/${cid}" \
        "${base}/container/${cid}" \
        "${base}/${cid}"; do
        if [ -d "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

get_all_containers() {
    local found=0
    if command -v docker &>/dev/null; then
        for cid in $(docker ps -q 2>/dev/null); do
            local cgpath
            cgpath=$(get_cgroup_cpu_path "$cid" 2>/dev/null) || true
            if [ -n "$cgpath" ] && [ -d "$cgpath" ]; then
                echo "${cid} ${cgpath}"
                found=1
            fi
        done
    fi
    if [ "$found" -eq 0 ]; then
        for dir in /sys/fs/cgroup/cpu/system.slice/docker-*.scope /sys/fs/cgroup/cpu/docker/*/ /sys/fs/cgroup/cpu/container/*/; do
            [ -d "$dir" ] || continue
            local cgpath="${dir%/}"
            local dirname
            dirname=$(basename "$cgpath")
            local cid="${dirname#docker-}"
            cid="${cid%.scope}"
            if [ -n "$cid" ] && [ -f "${cgpath}/cpu.soft_quota" ]; then
                echo "${cid} ${cgpath}"
                found=1
            fi
        done
    fi
}

init_backup_dir() {
    mkdir -p "$BACKUP_DIR"
}

# ---------- check ----------
do_check() {
    local errors=0
    if [ ! -f "$RATIO_FILE" ]; then
        echo "错误: 内核不支持 sched_soft_runtime_ratio（${RATIO_FILE} 不存在）" >&2
        errors=1
    fi
    if ! command -v docker &>/dev/null; then
        echo "警告: 未找到 docker 命令，将使用 cgroup 目录扫描" >&2
    fi
    local cgroup_found=0
    for base in /sys/fs/cgroup/cpu/system.slice /sys/fs/cgroup/cpu/docker /sys/fs/cgroup/cpu/container; do
        if [ -d "$base" ]; then
            cgroup_found=1
            echo "检测到 cgroup cpu 路径: ${base}"
            break
        fi
    done
    if [ "$cgroup_found" -eq 0 ]; then
        echo "错误: 未找到任何容器 cgroup cpu 路径" >&2
        errors=1
    fi
    if [ "$errors" -gt 0 ]; then
        exit 1
    fi
    echo "环境检查通过"
}

# ---------- backup ----------
do_backup() {
    init_backup_dir
    echo "备份当前状态到 ${BACKUP_FILE}"
    local ratio
    ratio=$(cat "$RATIO_FILE")
    echo "global_ratio=${ratio}" > "$BACKUP_FILE"
    while read -r cid cgpath; do
        [ -z "$cid" ] && continue
        local sq_file="${cgpath}/cpu.soft_quota"
        if [ -f "$sq_file" ]; then
            local val
            val=$(cat "$sq_file")
            echo "container ${cid} soft_quota=${val} path=${cgpath}" >> "$BACKUP_FILE"
        fi
    done < <(get_all_containers)
    echo "备份完成"
}

# ---------- apply ----------
do_apply() {
    local ratio=${1:-20}
    shift || true
    local ids=("$@")

    if ! [[ "$ratio" =~ ^[0-9]+$ ]] || [ "$ratio" -lt 1 ] || [ "$ratio" -gt 20 ]; then
        echo "错误: ratio 必须在 1~20 之间" >&2
        exit 1
    fi

    do_backup

    echo "=== 应用调优 ==="
    echo "1. 设置全局 sched_soft_runtime_ratio = ${ratio}"
    echo "$ratio" > "$RATIO_FILE"

    local containers=()
    if [ ${#ids[@]} -gt 0 ]; then
        for cid in "${ids[@]}"; do
            local cgpath
            cgpath=$(get_cgroup_cpu_path "$cid" 2>/dev/null) || true
            if [ -n "$cgpath" ] && [ -d "$cgpath" ]; then
                containers+=("${cid} ${cgpath}")
            else
                echo "警告: 未找到容器 ${cid} 的 cgroup cpu 路径，跳过" >&2
            fi
        done
    else
        while read -r cid cgpath; do
            [ -z "$cid" ] && continue
            containers+=("${cid} ${cgpath}")
        done < <(get_all_containers)
    fi

    if [ ${#containers[@]} -eq 0 ]; then
        echo "没有可操作的容器"
        exit 1
    fi

    echo "2. 对以下容器启用 soft_quota = 1"
    for entry in "${containers[@]}"; do
        read -r cid cgpath <<< "$entry"
        local sq_file="${cgpath}/cpu.soft_quota"
        if [ -f "$sq_file" ]; then
            echo "   ${cid}: ${sq_file} -> 1"
            echo 1 > "$sq_file"
        else
            echo "   ${cid}: ${sq_file} 不存在，跳过" >&2
        fi
    done
    echo "调优已生效"
}

# ---------- status ----------
do_status() {
    echo "全局 sched_soft_runtime_ratio: $(cat "$RATIO_FILE")"
    echo "容器 soft_quota 状态:"
    while read -r cid cgpath; do
        [ -z "$cid" ] && continue
        local sq_file="${cgpath}/cpu.soft_quota"
        if [ -f "$sq_file" ]; then
            echo "  ${cid}: $(cat "$sq_file")"
        else
            echo "  ${cid}: 文件不存在"
        fi
    done < <(get_all_containers)
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
    local global_ratio
    global_ratio=$(grep ^global_ratio= "$latest" | cut -d= -f2)
    if [ -n "$global_ratio" ]; then
        echo "恢复全局 ratio = ${global_ratio}"
        echo "$global_ratio" > "$RATIO_FILE"
    fi
    while IFS= read -r line; do
        if [[ "$line" =~ ^container\ ([a-f0-9]+)\ soft_quota=([0-9]+)\ path=(.+)$ ]]; then
            local cid="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            local path="${BASH_REMATCH[3]}"
            local sq_file="${path}/cpu.soft_quota"
            if [ -f "$sq_file" ]; then
                echo "恢复 ${cid}: ${sq_file} -> ${val}"
                echo "$val" > "$sq_file"
            else
                echo "警告: ${cid} 的 cgroup 文件已不存在，跳过" >&2
            fi
        fi
    done < "$latest"
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