#!/bin/bash
# soft_domain_tune.sh - 分域调度调优工具
# 用法:
#   soft_domain_tune.sh check docker|process [WHITELIST]        检查环境
#   soft_domain_tune.sh backup docker|process [WHITELIST]       备份当前状态
#   soft_domain_tune.sh apply docker|process WHITELIST [CPU_NUM]  应用调优
#   soft_domain_tune.sh status docker|process [WHITELIST]       查看当前状态
#   soft_domain_tune.sh rollback                                用最近一次备份回滚
#   soft_domain_tune.sh oeaware enable|rollback [WHITELIST] [CPU_NUM]  集成 oeaware

set -euo pipefail

BACKUP_DIR="/var/tmp/soft_domain_backups"
BACKUP_FILE="${BACKUP_DIR}/backup_$(date +%s).lst"
OEAWARE_CONFIG="/etc/oeAware/plugin/soft_domain.yaml"
ROLLBACK_SCRIPT="/var/tmp/soft_domain_backups/rollback_soft_domain.sh"

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

get_soft_domain_state() {
    local sf
    sf=$(get_sched_features_path)
    if [ -z "$sf" ]; then
        echo "UNKNOWN"
        return
    fi
    if grep -qow 'SOFT_DOMAIN' "$sf" 2>/dev/null; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

get_cpu_per_numa() {
    local nodes
    nodes=$(lscpu 2>/dev/null | awk -F: '/^NUMA node\(s\):/{gsub(/ /, "", $2); print $2}')
    [ -z "$nodes" ] && nodes=$(numactl --hardware 2>/dev/null | grep -c '^node ' || echo "1")
    [ "$nodes" -eq 0 ] && nodes=1

    local node0_cpus
    node0_cpus=$(lscpu 2>/dev/null | awk -F: '/^NUMA node0 CPU\(s\):/{gsub(/ /, "", $2); print $2}' | tr ',' '\n' | wc -l)
    if [ "$node0_cpus" -gt 0 ]; then
        echo "$node0_cpus"
        return
    fi

    local total_cpus
    total_cpus=$(nproc 2>/dev/null)
    if [ -n "$total_cpus" ] && [ "$nodes" -gt 0 ]; then
        echo $((total_cpus / nodes))
        return
    fi

    echo "0"
}

get_arch() {
    uname -m
}

match_whitelist() {
    local target="$1"
    local pattern="$2"

    if [ -z "$pattern" ]; then
        return 0
    fi

    # 支持 | 分隔的多模式匹配（如 "mysql-ks|redis-ks|nginx"）
    if [[ "$pattern" == *"|"* ]]; then
        local IFS='|'
        local part
        for part in $pattern; do
            if match_whitelist "$target" "$part"; then
                return 0
            fi
        done
        return 1
    fi

    if [[ "$pattern" == *[\[*?\]]* ]]; then
        [[ "$target" == $pattern ]]
        return $?
    fi

    [[ "$target" == *"$pattern"* ]]
    return $?
}

get_docker_containers() {
    local whitelist="$1"
    docker ps --no-trunc --format '{{.ID}} {{.Names}}' 2>/dev/null | while read -r CID CNAME; do
        [ -z "$CID" ] && continue
        if match_whitelist "$CNAME" "$whitelist"; then
            echo "$CID $CNAME"
        fi
    done
}

# 查找容器 cgroup cpu 路径（支持 docker/containerd/systemd 等多种运行时）
# 返回路径（如 /sys/fs/cgroup/cpu/docker/<cid>），不存在则返回空
get_container_cgroup() {
    local cid="$1"

    # 方式一：传统 docker cgroup v1 路径
    if [ -d "/sys/fs/cgroup/cpu/docker/${cid}" ]; then
        echo "/sys/fs/cgroup/cpu/docker/${cid}"
        return
    fi

    # 方式二：通过 /proc/<container_pid>/cgroup 获取精确路径
    local pid
    pid=$(docker inspect --format '{{.State.Pid}}' "$cid" 2>/dev/null || echo "")
    if [ -n "$pid" ] && [ "$pid" != "0" ]; then
        local cgroup_line cgroup_abs
        cgroup_line=$(grep ':cpu[,:]\|:cpu,' /proc/"$pid"/cgroup 2>/dev/null | head -1 || true)
        if [ -z "$cgroup_line" ]; then
            # cgroup v2 统一层级
            cgroup_line=$(grep '^0::' /proc/"$pid"/cgroup 2>/dev/null | head -1 || true)
        fi
        if [ -n "$cgroup_line" ]; then
            # 格式: <hierarchy_id>:<subsystems>:<path>
            local cgroup_path
            cgroup_path=$(echo "$cgroup_line" | cut -d: -f3-)
            cgroup_abs="/sys/fs/cgroup/cpu${cgroup_path}"
            if [ -d "$cgroup_abs" ]; then
                echo "$cgroup_abs"
                return
            fi
            # cgroup v2: /sys/fs/cgroup/<path>
            cgroup_abs="/sys/fs/cgroup${cgroup_path}"
            if [ -d "$cgroup_abs" ]; then
                echo "$cgroup_abs"
                return
            fi
        fi
    fi

    # 方式三：搜索 cpu cgroup 目录中与 cid 匹配的路径
    local found
    found=$(find /sys/fs/cgroup/cpu/ -maxdepth 3 -type d -name "*${cid}*" 2>/dev/null | head -1 || true)
    if [ -d "$found" ]; then
        echo "$found"
        return
    fi

    # 方式四：cgroup v2 搜索
    found=$(find /sys/fs/cgroup/ -maxdepth 3 -type d -name "*${cid}*" -name "*.scope" -o -name "*${cid}*" 2>/dev/null | head -1 || true)
    if [ -d "$found" ]; then
        echo "$found"
        return
    fi

    echo ""
}

get_matched_pids() {
    local pattern="$1"
    local result=""
    while IFS= read -r pid; do
        local comm
        comm=$(ps -p "$pid" -o comm= 2>/dev/null || echo "")
        if [ -n "$comm" ] && match_whitelist "$comm" "$pattern"; then
            result="${result} ${pid}"
        fi
    done < <(ps -eo pid,comm --no-headers 2>/dev/null | while read -r pid comm; do
        if match_whitelist "$comm" "$pattern"; then
            echo "$pid"
        fi
    done)
    echo "$result" | xargs
}

get_container_quota_cpu() {
    local cg="$1"
    local quota period obj_cpu
    quota=$(cat "$cg/cpu.cfs_quota_us" 2>/dev/null || echo -1)
    period=$(cat "$cg/cpu.cfs_period_us" 2>/dev/null || echo 100000)
    if [ "$quota" -le 0 ] || [ "$period" -le 0 ]; then
        echo "0"
        return
    fi
    obj_cpu=$((quota / period))
    [ "$obj_cpu" -le 0 ] && obj_cpu=1
    echo "$obj_cpu"
}

test_cgroup_writable() {
    local cg="$1"
    local file="$2"
    if [ -f "$cg/$file" ] && [ -w "$cg/$file" ]; then
        return 0
    fi
    if [ -f "$cg/$file" ] && [ ! -w "$cg/$file" ]; then
        echo "  错误: $cg/$file 不可写" >&2
        return 1
    fi
    echo "  错误: $cg/$file 不存在" >&2
    return 1
}

generate_rollback_script() {
    local mode="$1"
    local whitelist="$2"
    local sf_path="$3"

    cat > "$ROLLBACK_SCRIPT" << RBEOF
#!/bin/bash
# soft_domain 自动回滚脚本
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
set -euo pipefail

echo "=== soft_domain 回滚 ==="

MODE="${mode}"
WHITELIST="${whitelist}"

RBEOF

    if [ "$mode" = "docker" ]; then
        cat >> "$ROLLBACK_SCRIPT" << 'RBEOF'
get_container_cgroup() {
    local cid="$1"
    [ -d "/sys/fs/cgroup/cpu/docker/${cid}" ] && { echo "/sys/fs/cgroup/cpu/docker/${cid}"; return; }
    local pid
    pid=$(docker inspect --format '{{.State.Pid}}' "$cid" 2>/dev/null || echo "")
    if [ -n "$pid" ] && [ "$pid" != "0" ]; then
        local cgroup_line cgroup_abs
        cgroup_line=$(grep ':cpu[,:]\|:cpu,\|^0::' /proc/"$pid"/cgroup 2>/dev/null | head -1 || true)
        if [ -n "$cgroup_line" ]; then
            local cgroup_path
            cgroup_path=$(echo "$cgroup_line" | cut -d: -f3-)
            cgroup_abs="/sys/fs/cgroup/cpu${cgroup_path}"
            [ -d "$cgroup_abs" ] && { echo "$cgroup_abs"; return; }
            cgroup_abs="/sys/fs/cgroup${cgroup_path}"
            [ -d "$cgroup_abs" ] && { echo "$cgroup_abs"; return; }
        fi
    fi
    echo ""
}

get_docker_containers() {
    local pattern="$1"
    docker ps --no-trunc --format '{{.ID}} {{.Names}}' 2>/dev/null | while read -r CID CNAME; do
        [ -z "$CID" ] && continue
        if [[ "$CNAME" == *"$pattern"* ]]; then
            echo "$CID $CNAME"
        fi
    done
}

echo "1. 清空 Docker 容器 cgroup 配置"
while read -r CID CNAME; do
    [ -z "$CID" ] && continue
    CG=$(get_container_cgroup "$CID")
    if [ -n "$CG" ] && [ -d "$CG" ]; then
        echo 0 > "$CG/cpu.soft_domain" 2>/dev/null || true
        echo 0 > "$CG/cpu.soft_domain_nr_cpu" 2>/dev/null || true
        echo "  $CNAME($CID): 已清空"
    fi
done < <(get_docker_containers "$WHITELIST")

RBEOF
    elif [ "$mode" = "process" ]; then
        cat >> "$ROLLBACK_SCRIPT" << 'RBEOF'
ROOT_CG="/sys/fs/cgroup/cpu"

echo "1. 清理 process 模式创建的 cgroup"
for CG in ${ROOT_CG}/soft_domain_*; do
    [ -d "$CG" ] || continue
    if [ -f "$CG/tasks" ] && [ -f "${ROOT_CG}/tasks" ]; then
        echo "  迁回 PID: $(cat "$CG/tasks" | tr '\n' ' ')"
        while read -r PID; do
            [ -n "$PID" ] && echo "$PID" > "${ROOT_CG}/tasks" 2>/dev/null || true
        done < "$CG/tasks"
    fi
    rmdir "$CG" 2>/dev/null && echo "  已删除 $(basename "$CG")" || echo "  无法删除 $(basename "$CG")"
done

RBEOF
    fi

    cat >> "$ROLLBACK_SCRIPT" << RBEOF

echo "2. 关闭 SOFT_DOMAIN 总开关"
if [ -n "${sf_path}" ] && [ -w "${sf_path}" ]; then
    echo NO_SOFT_DOMAIN > "${sf_path}" 2>/dev/null && echo "  已写入 NO_SOFT_DOMAIN" || echo "  写入失败"
elif sf=\$(find /sys/kernel/debug -name 'sched_features' -o -name 'features' 2>/dev/null | head -1); then
    [ -w "\$sf" ] && echo NO_SOFT_DOMAIN > "\$sf" 2>/dev/null && echo "  已写入 NO_SOFT_DOMAIN (\$sf)"
fi

echo "回滚完成"
RBEOF

    chmod +x "$ROLLBACK_SCRIPT"
    echo "  回滚脚本已生成: ${ROLLBACK_SCRIPT}"
}

# ---------- check ----------
do_check() {
    local mode="${1:-docker}"
    local whitelist="${2:-}"
    local errors=0

    echo "=== 分域调度环境检查 ==="

    local arch
    arch=$(get_arch)
    echo "架构: ${arch}"
    if [ "$arch" != "aarch64" ]; then
        echo "  注意: 分域调度推荐在 aarch64 架构上使用"
    fi

    local sf
    sf=$(get_sched_features_path)
    if [ -z "$sf" ]; then
        echo "  错误: 未找到 sched_features 文件" >&2
        errors=1
    else
        [ -w "$sf" ] && echo "  sched_features: ${sf} (可写)" || { echo "  错误: ${sf} 不可写" >&2; errors=1; }
    fi

    local sd_state
    sd_state=$(get_soft_domain_state)
    echo "  SOFT_DOMAIN 状态: ${sd_state}"
    if [ "$sd_state" = "UNKNOWN" ]; then
        echo "  错误: 无法读取 SOFT_DOMAIN 状态" >&2
        errors=1
    fi

    if [ -n "$sf" ] && ! grep -q 'SOFT_DOMAIN' "$sf" 2>/dev/null; then
        echo "  错误: 内核不支持 SOFT_DOMAIN 特性" >&2
        errors=1
    fi

    local cpu_per_numa
    cpu_per_numa=$(get_cpu_per_numa)
    echo "单 NUMA CPU 数: ${cpu_per_numa}"
    if [ "$cpu_per_numa" -eq 0 ]; then
        echo "  警告: 无法获取单 NUMA CPU 数"
    fi

    if [ "$mode" = "docker" ]; then
        echo ""
        echo "Docker 模式检查:"
        local found=0
        while read -r CID CNAME; do
            [ -z "$CID" ] && continue
            found=1
            local CG
            CG=$(get_container_cgroup "$CID")
            if [ -n "$CG" ] && [ -d "$CG" ]; then
                local ok=1
                test_cgroup_writable "$CG" "cpu.soft_domain" || ok=0
                test_cgroup_writable "$CG" "cpu.soft_domain_nr_cpu" || ok=0
                local quota_cpu
                quota_cpu=$(get_container_quota_cpu "$CG")
                local status=""
                [ "$ok" -eq 1 ] && status="可配置" || status="不可配置"
                echo "  ${CNAME}(${CID}): ${status}, 配额CPU数=${quota_cpu}, cgroup=${CG}"
            else
                echo "  ${CNAME}(${CID}): cgroup 目录未找到（已尝试 docker/inspect/proc cgroup 搜索）" >&2
                errors=1
            fi
        done < <(get_docker_containers "$whitelist")

        if [ -n "$whitelist" ] && [ "$found" -eq 0 ]; then
            echo "  错误: 未找到匹配 '"${whitelist}"' 的容器" >&2
            errors=1
        fi
    elif [ "$mode" = "process" ]; then
        echo ""
        echo "Process 模式检查:"
        local root_cg="/sys/fs/cgroup/cpu"
        test_cgroup_writable "$root_cg" "tasks" || errors=1

        local safe_name="soft_domain_${whitelist//[^a-zA-Z0-9_-]/_}"
        local target_cg="${root_cg}/${safe_name}"
        echo "  目标 cgroup: ${target_cg}"

        if [ -n "$whitelist" ]; then
            local pids
            pids=$(get_matched_pids "$whitelist")
            if [ -z "$pids" ]; then
                echo "  错误: 未找到匹配 '"${whitelist}"' 的进程" >&2
                errors=1
            else
                echo "  匹配进程: $(echo "$pids" | wc -w) 个"
                for pid in $pids; do
                    local comm
                    comm=$(ps -p "$pid" -o comm= 2>/dev/null || echo "?")
                    echo "    PID=${pid} (${comm})"
                done
            fi
        else
            echo "  错误: process 模式需要提供进程名匹配模式" >&2
            errors=1
        fi
    else
        echo "  错误: mode 仅支持 docker 或 process" >&2
        errors=1
    fi

    if [ "$errors" -gt 0 ]; then
        exit 1
    fi
    echo ""
    echo "环境检查通过"
}

# ---------- backup ----------
do_backup() {
    local mode="${1:-docker}"
    local whitelist="${2:-}"

    init_backup_dir
    echo "备份当前状态到 ${BACKUP_FILE}"

    local sf
    sf=$(get_sched_features_path)
    local sd_state
    sd_state=$(get_soft_domain_state)

    echo "sched_features_path=${sf}" > "$BACKUP_FILE"
    echo "soft_domain_state=${sd_state}" >> "$BACKUP_FILE"
    echo "mode=${mode}" >> "$BACKUP_FILE"
    echo "whitelist=${whitelist}" >> "$BACKUP_FILE"

    echo "  SOFT_DOMAIN 状态: ${sd_state}"

    if [ "$mode" = "docker" ]; then
        while read -r CID CNAME; do
            [ -z "$CID" ] && continue
            local CG
            CG=$(get_container_cgroup "$CID")
            [ -n "$CG" ] && [ -d "$CG" ] || continue
            local sd_val nr_val
            sd_val=$(cat "$CG/cpu.soft_domain" 2>/dev/null || echo "0")
            nr_val=$(cat "$CG/cpu.soft_domain_nr_cpu" 2>/dev/null || echo "0")
            echo "docker_${CID}_soft_domain=${sd_val}" >> "$BACKUP_FILE"
            echo "docker_${CID}_soft_domain_nr_cpu=${nr_val}" >> "$BACKUP_FILE"
            echo "docker_${CID}_name=${CNAME}" >> "$BACKUP_FILE"
            echo "  容器 ${CNAME}(${CID}): soft_domain=${sd_val}, nr_cpu=${nr_val}"
        done < <(get_docker_containers "$whitelist")
    elif [ "$mode" = "process" ]; then
        local safe_name="soft_domain_${whitelist//[^a-zA-Z0-9_-]/_}"
        local CG="/sys/fs/cgroup/cpu/$safe_name"
        if [ -d "$CG" ]; then
            local sd_val nr_val
            sd_val=$(cat "$CG/cpu.soft_domain" 2>/dev/null || echo "0")
            nr_val=$(cat "$CG/cpu.soft_domain_nr_cpu" 2>/dev/null || echo "0")
            echo "process_${safe_name}_soft_domain=${sd_val}" >> "$BACKUP_FILE"
            echo "process_${safe_name}_soft_domain_nr_cpu=${nr_val}" >> "$BACKUP_FILE"
            if [ -f "$CG/tasks" ]; then
                echo "process_${safe_name}_tasks=$(cat "$CG/tasks" 2>/dev/null | tr '\n' ',' | sed 's/,$//')" >> "$BACKUP_FILE"
            fi
            echo "  进程 cgroup ${safe_name}: soft_domain=${sd_val}, nr_cpu=${nr_val}"
        else
            echo "  进程 cgroup ${safe_name} 不存在（将在 apply 时创建）"
        fi
    fi

    echo "备份完成"
}

# ---------- apply ----------
do_apply() {
    local mode="${1:-docker}"
    local whitelist="${2:-}"
    local cpu_num="${3:-0}"
    local numa_id="${4:-1}"

    if [ -z "$whitelist" ]; then
        echo "错误: 缺少名称匹配模式 (whitelist)" >&2
        exit 1
    fi

    local sf
    sf=$(get_sched_features_path)
    if [ -z "$sf" ]; then
        echo "错误: 未找到 sched_features 文件" >&2
        exit 1
    fi

    if [ -z "$(grep 'SOFT_DOMAIN' "$sf" 2>/dev/null)" ]; then
        echo "错误: 内核不支持 SOFT_DOMAIN 特性" >&2
        exit 1
    fi

    local cpu_per_numa
    cpu_per_numa=$(get_cpu_per_numa)
    if [ "$cpu_per_numa" -eq 0 ]; then
        echo "错误: 无法读取 CPU/NUMA 拓扑" >&2
        exit 1
    fi

    if [ "$cpu_num" -gt 0 ] && [ "$cpu_num" -gt "$cpu_per_numa" ]; then
        echo "错误: cpu_num=${cpu_num} 超过单 NUMA CPU 数 ${cpu_per_numa}" >&2
        exit 1
    fi

    echo "=== 分域调度预检 ==="
    echo "模式: ${mode}"
    echo "匹配模式: ${whitelist}"
    echo "CPU宽度: ${cpu_num} (0=使用配额值)"
    echo "目标NUMA: ${numa_id}"
    echo "单NUMA CPU数: ${cpu_per_numa}"
    echo ""

    local plan_file="${BACKUP_DIR}/apply_plan_$(date +%s).txt"
    {
        echo "=== 分域调度执行计划 ==="
        echo "生成时间: $(date)"
        echo "模式: ${mode}"
        echo "匹配模式: ${whitelist}"
        echo "CPU宽度: ${cpu_num}"
        echo "目标NUMA: ${numa_id}"
        echo ""
        echo "--- 将要执行的操作 ---"
    } > "$plan_file"

    if [ "$mode" = "docker" ]; then
        echo "1. 启用 SOFT_DOMAIN 总开关" | tee -a "$plan_file"
        echo "2. 配置 Docker 容器 cgroup:" | tee -a "$plan_file"

        local found=0
        while read -r CID CNAME; do
            [ -z "$CID" ] && continue
            found=1
            local CG
            CG=$(get_container_cgroup "$CID")
            [ -n "$CG" ] && [ -d "$CG" ] || { echo "  跳过 ${CNAME}(${CID}): cgroup 路径未找到" | tee -a "$plan_file"; continue; }

            local quota_cpu nr_cpu
            quota_cpu=$(get_container_quota_cpu "$CG")
            if [ "$cpu_num" -gt 0 ]; then
                nr_cpu=$cpu_num
            elif [ "$quota_cpu" -gt 0 ]; then
                nr_cpu=$quota_cpu
            else
                echo "  跳过 ${CNAME}(${CID}): 无 CPU 配额且未指定 cpu_num" | tee -a "$plan_file"
                continue
            fi

            [ "$nr_cpu" -gt "$cpu_per_numa" ] && nr_cpu=$cpu_per_numa

            if ! test_cgroup_writable "$CG" "cpu.soft_domain"; then
                echo "  错误: 容器 ${CNAME} cgroup 不可写，中止" >&2
                exit 1
            fi
            if ! test_cgroup_writable "$CG" "cpu.soft_domain_nr_cpu"; then
                echo "  错误: 容器 ${CNAME} cgroup 不可写，中止" >&2
                exit 1
            fi

            echo "  ${CNAME}(${CID}): nr_cpu=${nr_cpu}, numa=${numa_id}" | tee -a "$plan_file"
        done < <(get_docker_containers "$whitelist")

        if [ "$found" -eq 0 ]; then
            echo "  未找到匹配模式 '"${whitelist}"' 的容器" | tee -a "$plan_file"
            exit 1
        fi

    elif [ "$mode" = "process" ]; then
        local pids
        pids=$(get_matched_pids "$whitelist")
        if [ -z "$pids" ]; then
            echo "错误: 未找到匹配 '"${whitelist}"' 的进程" >&2
            exit 1
        fi

        if [ "$cpu_num" -le 0 ] || [ "$cpu_num" -gt "$cpu_per_numa" ]; then
            echo "错误: process 模式需指定有效的 cpu_num (1~${cpu_per_numa})" >&2
            exit 1
        fi

        echo "1. 启用 SOFT_DOMAIN 总开关" | tee -a "$plan_file"
        echo "2. 创建 cgroup 并迁入匹配进程 (${cpu_num} 核 / NUMA ${numa_id}):" | tee -a "$plan_file"
        for pid in $pids; do
            local comm
            comm=$(ps -p "$pid" -o comm= 2>/dev/null || echo "?")
            echo "  PID=${pid} (${comm})" | tee -a "$plan_file"
        done
    else
        echo "错误: mode 仅支持 docker 或 process" >&2
        exit 1
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

    do_backup "$mode" "$whitelist"

    echo ""
    echo "=== 执行调优 ==="

    echo "1. 启用 SOFT_DOMAIN 总开关"
    local sd_state
    sd_state=$(get_soft_domain_state)
    if [ "$sd_state" != "enabled" ]; then
        echo "SOFT_DOMAIN" > "$sf"
        echo "  已写入 SOFT_DOMAIN → ${sf}"
    else
        echo "  SOFT_DOMAIN 已启用，跳过"
    fi

    echo "2. 配置 cgroup 软调度域参数"

    if [ "$mode" = "docker" ]; then
        while read -r CID CNAME; do
            [ -z "$CID" ] && continue
            local CG
            CG=$(get_container_cgroup "$CID")
            [ -n "$CG" ] && [ -d "$CG" ] || continue

            local quota_cpu nr_cpu
            quota_cpu=$(get_container_quota_cpu "$CG")
            if [ "$cpu_num" -gt 0 ]; then
                nr_cpu=$cpu_num
            else
                nr_cpu=$quota_cpu
            fi
            [ "$nr_cpu" -gt "$cpu_per_numa" ] && nr_cpu=$cpu_per_numa
            [ "$nr_cpu" -le 0 ] && continue

            echo "$nr_cpu" > "$CG/cpu.soft_domain_nr_cpu"
            echo "$numa_id" > "$CG/cpu.soft_domain"
            echo "  ${CNAME}(${CID}): soft_domain=${numa_id}, nr_cpu=${nr_cpu}"
        done < <(get_docker_containers "$whitelist")

    elif [ "$mode" = "process" ]; then
        local safe_name="soft_domain_${whitelist//[^a-zA-Z0-9_-]/_}"
        local CG="/sys/fs/cgroup/cpu/$safe_name"
        mkdir -p "$CG"

        [ -f "$CG/cpu.soft_domain_nr_cpu" ] && echo "$cpu_num" > "$CG/cpu.soft_domain_nr_cpu" || true
        [ -f "$CG/cpu.soft_domain" ] && echo "$numa_id" > "$CG/cpu.soft_domain" || true
        echo "  cgroup: ${CG}, soft_domain=${numa_id}, nr_cpu=${cpu_num}"

        for pid in $(get_matched_pids "$whitelist"); do
            echo "$pid" > "$CG/tasks" 2>/dev/null || echo "  警告: 无法迁移 PID=${pid}"
            echo "  已迁入 PID=${pid}"
        done
    fi

    generate_rollback_script "$mode" "$whitelist" "$sf"

    echo ""
    echo "调优已生效"
    echo "回滚方法: bash ${ROLLBACK_SCRIPT}"
}

# ---------- status ----------
do_status() {
    local mode="${1:-docker}"
    local whitelist="${2:-}"

    echo "=== 分域调度当前状态 ==="

    local sf
    sf=$(get_sched_features_path)
    local sd_state
    sd_state=$(get_soft_domain_state)

    echo "sched_features: ${sf:-未找到}"
    echo "SOFT_DOMAIN: ${sd_state}"
    echo "架构: $(get_arch)"
    echo "单 NUMA CPU 数: $(get_cpu_per_numa)"
    echo ""

    if [ "$mode" = "docker" ]; then
        echo "Docker 容器 soft_domain 配置:"
        while read -r CID CNAME; do
            [ -z "$CID" ] && continue
            local CG
            CG=$(get_container_cgroup "$CID")
            [ -n "$CG" ] && [ -d "$CG" ] || { echo "  ${CNAME}(${CID}): cgroup 路径未找到"; continue; }
            local sd_val nr_val
            sd_val=$(cat "$CG/cpu.soft_domain" 2>/dev/null || echo "N/A")
            nr_val=$(cat "$CG/cpu.soft_domain_nr_cpu" 2>/dev/null || echo "N/A")
            local quota_cpu
            quota_cpu=$(get_container_quota_cpu "$CG")
            echo "  ${CNAME}(${CID}): soft_domain=${sd_val}, nr_cpu=${nr_val}, quota_cpu=${quota_cpu}"
        done < <(get_docker_containers "$whitelist")
    elif [ "$mode" = "process" ]; then
        if [ -n "$whitelist" ]; then
            local safe_name="soft_domain_${whitelist//[^a-zA-Z0-9_-]/_}"
            local CG="/sys/fs/cgroup/cpu/$safe_name"
            echo "进程 cgroup: ${CG}"
            if [ -d "$CG" ]; then
                local sd_val nr_val
                sd_val=$(cat "$CG/cpu.soft_domain" 2>/dev/null || echo "N/A")
                nr_val=$(cat "$CG/cpu.soft_domain_nr_cpu" 2>/dev/null || echo "N/A")
                echo "  soft_domain=${sd_val}, nr_cpu=${nr_val}"
                if [ -f "$CG/tasks" ]; then
                    local task_count
                    task_count=$(wc -l < "$CG/tasks" 2>/dev/null || echo "0")
                    echo "  任务数: ${task_count}"
                fi
            else
                echo "  cgroup 不存在"
            fi
        else
            echo "进程 cgroup 列表:"
            for CG in /sys/fs/cgroup/cpu/soft_domain_*; do
                [ -d "$CG" ] || continue
                local sd_val nr_val
                sd_val=$(cat "$CG/cpu.soft_domain" 2>/dev/null || echo "N/A")
                nr_val=$(cat "$CG/cpu.soft_domain_nr_cpu" 2>/dev/null || echo "N/A")
                local task_count=0
                [ -f "$CG/tasks" ] && task_count=$(wc -l < "$CG/tasks" 2>/dev/null || echo "0")
                echo "  $(basename "$CG"): soft_domain=${sd_val}, nr_cpu=${nr_val}, 任务数=${task_count}"
            done
        fi
    fi
}

# ---------- rollback ----------
do_rollback() {
    local latest
    latest=$(ls -t "${BACKUP_DIR}"/backup_*.lst 2>/dev/null | head -1)

    echo "=== 分域调度回滚 ==="

    if [ -n "$latest" ]; then
        echo "使用备份文件: ${latest}"
        local sf_path saved_sd saved_mode
        sf_path=$(grep ^sched_features_path= "$latest" | cut -d= -f2-)
        saved_sd=$(grep ^soft_domain_state= "$latest" | cut -d= -f2-)
        saved_mode=$(grep ^mode= "$latest" | cut -d= -f2-)
    else
        echo "未找到备份文件，执行清理回滚"
        local sf_path
        sf_path=$(get_sched_features_path)
        saved_sd="disabled"
        saved_mode="docker"
    fi

    echo "1. 清空 Docker 容器 cgroup 配置"
    local -A rollback_cgs=()
    if [ -n "$latest" ] && [ -f "$latest" ]; then
        # 优先从备份文件提取需要回滚的容器 cgroup 路径
        while IFS= read -r line; do
            if [[ "$line" =~ ^docker_([a-f0-9]+)_soft_domain= ]]; then
                local rbid="${BASH_REMATCH[1]}"
                local rbcg
                rbcg=$(get_container_cgroup "$rbid")
                [ -n "$rbcg" ] && rollback_cgs["$rbcg"]=1
            fi
        done < "$latest"
    fi
    if ((${#rollback_cgs[@]} == 0)); then
        # 回退：搜索所有含 cpu.soft_domain 的 cgroup
        while IFS= read -r f; do
            local dir
            dir=$(dirname "$f")
            rollback_cgs["$dir"]=1
        done < <(find /sys/fs/cgroup/cpu/ -maxdepth 3 -name "cpu.soft_domain" -type f 2>/dev/null || true)
    fi

    for CG in "${!rollback_cgs[@]}"; do
        [ -d "$CG" ] || continue
        local CID
        CID=$(basename "$CG")
        if [ -f "$CG/cpu.soft_domain" ]; then
            if [ -n "$latest" ] && [ -f "$latest" ]; then
                local saved_val
                saved_val=$(grep "^docker_${CID}_soft_domain=" "$latest" 2>/dev/null | cut -d= -f2-)
                [ -n "$saved_val" ] && echo "$saved_val" > "$CG/cpu.soft_domain" 2>/dev/null || echo 0 > "$CG/cpu.soft_domain" 2>/dev/null || true
            else
                echo 0 > "$CG/cpu.soft_domain" 2>/dev/null || true
            fi
        fi
        if [ -f "$CG/cpu.soft_domain_nr_cpu" ]; then
            if [ -n "$latest" ] && [ -f "$latest" ]; then
                local saved_val
                saved_val=$(grep "^docker_${CID}_soft_domain_nr_cpu=" "$latest" 2>/dev/null | cut -d= -f2-)
                [ -n "$saved_val" ] && echo "$saved_val" > "$CG/cpu.soft_domain_nr_cpu" 2>/dev/null || echo 0 > "$CG/cpu.soft_domain_nr_cpu" 2>/dev/null || true
            else
                echo 0 > "$CG/cpu.soft_domain_nr_cpu" 2>/dev/null || true
            fi
        fi
    done
    echo "  已处理 ${#rollback_cgs[@]} 个 cgroup"

    echo "2. 清理 process 模式创建的 cgroup"
    local root_cg="/sys/fs/cgroup/cpu"
    for CG in ${root_cg}/soft_domain_*; do
        [ -d "$CG" ] || continue
        if [ -f "$CG/tasks" ] && [ -f "${root_cg}/tasks" ]; then
            while read -r PID; do
                [ -n "$PID" ] && echo "$PID" > "${root_cg}/tasks" 2>/dev/null || true
            done < "$CG/tasks"
        fi
        if [ -f "$CG/cpu.soft_domain" ]; then
            echo 0 > "$CG/cpu.soft_domain" 2>/dev/null || true
        fi
        if [ -f "$CG/cpu.soft_domain_nr_cpu" ]; then
            echo 0 > "$CG/cpu.soft_domain_nr_cpu" 2>/dev/null || true
        fi
        rmdir "$CG" 2>/dev/null && echo "  已删除 $(basename "$CG")" || echo "  无法删除 $(basename "$CG")"
    done

    echo "3. 恢复 SOFT_DOMAIN 总开关"
    local sf
    if [ -n "${sf_path:-}" ] && [ -w "$sf_path" ]; then
        sf="$sf_path"
    else
        sf=$(get_sched_features_path)
    fi

    if [ -n "$sf" ] && [ -w "$sf" ]; then
        if [ "${saved_sd:-disabled}" = "enabled" ]; then
            echo "SOFT_DOMAIN" > "$sf" 2>/dev/null || true
            echo "  恢复 SOFT_DOMAIN 状态: enabled"
        else
            echo "NO_SOFT_DOMAIN" > "$sf" 2>/dev/null || true
            echo "  恢复 SOFT_DOMAIN 状态: disabled"
        fi
    else
        echo "  警告: 无法写入 sched_features，跳过"
    fi

    if [ -x "$ROLLBACK_SCRIPT" ]; then
        rm -f "$ROLLBACK_SCRIPT"
    fi

    echo ""
    echo "回滚完成"
}

# ---------- oeaware ----------
do_oeaware() {
    local action="${1:-enable}"
    local whitelist="${2:-}"
    local cpu_num="${3:-0}"
    local numa_id="${4:-1}"

    if ! command -v oeawarectl &>/dev/null; then
        echo "错误: oeawarectl 不可用" >&2
        exit 1
    fi

    local cfg_dir
    cfg_dir=$(dirname "$OEAWARE_CONFIG")
    mkdir -p "$cfg_dir"

    if [ "$action" = "enable" ]; then
        echo "生成 oeaware 配置: ${OEAWARE_CONFIG}"

        cat > "$OEAWARE_CONFIG" << EOF
# soft_domain 分域调度 oeaware 插件配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 匹配模式: ${whitelist}
# CPU宽度: ${cpu_num} (0=使用配额)
# 目标NUMA: ${numa_id}

plugin: soft_domain_tune
enabled: true
parameters:
  mode: "${MODE:-docker}"
  whitelist: "${whitelist}"
  cpu_num: ${cpu_num}
  numa_id: ${numa_id}
EOF

        echo "执行: oeawarectl -e soft_domain_tune"
        oeawarectl -e soft_domain_tune 2>/dev/null && echo "  oeaware 插件已使能" || echo "  警告: oeawarectl -e 执行失败"
    elif [ "$action" = "rollback" ]; then
        echo "执行: oeawarectl -d soft_domain_tune"
        oeawarectl -d soft_domain_tune 2>/dev/null && echo "  oeaware 插件已禁用" || echo "  警告: oeawarectl -d 执行失败"
        rm -f "$OEAWARE_CONFIG"
        echo "  已删除 ${OEAWARE_CONFIG}"
    else
        echo "错误: oeaware action 仅支持 enable 或 rollback" >&2
        exit 1
    fi
}

# ---------- 主入口 ----------
parse_args() {
    MODE="docker"
    WHITELIST=""
    CPU_NUM="0"
    NUMA_ID="1"

    local cmd="$1"; shift
    if [ "$#" -ge 1 ]; then
        case "${1:-}" in
            docker|process) MODE="$1"; shift ;;
        esac
    fi
    WHITELIST="${1:-}"; shift 2>/dev/null || true
    CPU_NUM="${1:-0}"; shift 2>/dev/null || true
    NUMA_ID="${1:-1}"; shift 2>/dev/null || true
}

if [ $# -lt 1 ]; then
    echo "用法: $0 {check|backup|apply|status|rollback|oeaware} [参数...]"
    echo ""
    echo "命令:"
    echo "  check   docker|process [WHITELIST]           检查环境"
    echo "  backup  docker|process [WHITELIST]           备份状态"
    echo "  apply   docker|process WHITELIST [CPU_NUM]   应用调优（CPU_NUM=0为使用配额）"
    echo "  status  docker|process [WHITELIST]           查看状态"
    echo "  rollback                                     执行回滚"
    echo "  oeaware enable|rollback [WHITELIST] [CPU_NUM] oeaware集成"
    echo ""
    echo "示例:"
    echo "  $0 apply docker myapp        # 对名称匹配 myapp 的容器使能"
    echo "  $0 apply process redis-* 8   # 对匹配 redis-* 的进程使能，8核软域"
    exit 1
fi

command=$1
shift

case "$command" in
    check)
        MODE="${1:-docker}"; WHITELIST="${2:-}"
        do_check "$MODE" "$WHITELIST"
        ;;
    backup)
        MODE="${1:-docker}"; WHITELIST="${2:-}"
        do_backup "$MODE" "$WHITELIST"
        ;;
    apply)
        MODE="${1:-docker}"; WHITELIST="${2:-}"; CPU_NUM="${3:-0}"; NUMA_ID="${4:-1}"
        do_apply "$MODE" "$WHITELIST" "$CPU_NUM" "$NUMA_ID"
        ;;
    status)
        MODE="${1:-docker}"; WHITELIST="${2:-}"
        do_status "$MODE" "$WHITELIST"
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