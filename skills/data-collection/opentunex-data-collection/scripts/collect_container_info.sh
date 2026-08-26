#!/bin/bash
set -uo pipefail

# ====================================================================
# 参数初始化
# ====================================================================
OBSERVATION_WINDOW=10
SAMPLE_INTERVAL=2
SKIP_MULTI=0

usage() {
    echo "Usage: $0 [--no-multi] [-w <observation_window_sec>] [-i <sample_interval_sec>] [<batch_dir>]"
    echo "  --no-multi  跳过末尾的多采样容器 CPU 观测窗口"
    echo "  -w  多采样观测窗口总时长（秒），默认 10"
    echo "  -i  多采样间隔（秒），默认 2"
    echo "  <batch_dir>  批次根目录，默认 ${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/<timestamp>"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-multi)
            SKIP_MULTI=1
            shift
            ;;
        -w)
            OBSERVATION_WINDOW="$2"
            shift 2
            ;;
        -i)
            SAMPLE_INTERVAL="$2"
            shift 2
            ;;
        -h)
            usage
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "未知选项: $1"
            usage
            ;;
        *)
            break
            ;;
    esac
done

DEFAULT_TS=$(date +%Y%m%d_%H%M%S)
BATCH_DIR="${1:-${WORK_DIR:-/srv/opentunex/${DEFAULT_TS}}/collect/}"
REPORT_FILE="${BATCH_DIR}/container-collection_report.txt"

# 验证参数
if ! [[ "$OBSERVATION_WINDOW" =~ ^[0-9]+$ ]] || [ "$OBSERVATION_WINDOW" -lt 2 ]; then
    echo "错误: 观测窗口至少 2 秒"
    exit 1
fi
if ! [[ "$SAMPLE_INTERVAL" =~ ^[0-9]+$ ]] || [ "$SAMPLE_INTERVAL" -lt 1 ]; then
    echo "错误: 采样间隔至少 1 秒"
    exit 1
fi

# ====================================================================
# 检测 cgroup 版本与 v2 根路径
# ====================================================================
detect_cgroup_version() {
    if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
        echo "v2"
    elif [ -f "/sys/fs/cgroup/unified/cgroup.controllers" ]; then
        echo "v2_unified_mount"
    else
        echo "v1"
    fi
}
get_cgroup_root() {
    if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
        echo "/sys/fs/cgroup"
    elif [ -f "/sys/fs/cgroup/unified/cgroup.controllers" ]; then
        echo "/sys/fs/cgroup/unified"
    else
        echo ""
    fi
}

CGROUP_VER=$(detect_cgroup_version)
CGROUP_V2_ROOT=$(get_cgroup_root)

# ====================================================================
# 辅助函数：从 cgroup 目录名中提取纯容器 ID（去除运行时前缀/后缀）
# ====================================================================
extract_container_id() {
    local basename="$1"
    # 去掉 .scope 后缀
    local name="${basename%.scope}"
    # 去掉常见运行时前缀（docker-、containerd-、cri-containerd-、libpod-）
    # 注意：containerd 可能有两种格式：containerd-<id> 和 cri-containerd-<id>
    if [[ "$name" == docker-* ]]; then
        name="${name#docker-}"
    elif [[ "$name" == containerd-* ]]; then
        name="${name#containerd-}"
    elif [[ "$name" == cri-containerd-* ]]; then
        name="${name#cri-containerd-}"
    elif [[ "$name" == libpod-* ]]; then
        name="${name#libpod-}"
    fi
    # 如果清理后仍是空或和原来一样，返回原值；否则返回清理后的 ID
    [ -n "$name" ] && echo "$name" || echo "$basename"
}

# ====================================================================
# 改进的 get_cgroup_path：直接使用完整 basename 查找
# ====================================================================
get_cgroup_path() {
    local subsys="$1"   # v1 子系统名，v2 下忽略
    local cid="$2"      # 现在 cid 是 cgroup 目录的完整 basename（可能含 scope）
    local path

    # v2 统一层级
    if [ -n "$CGROUP_V2_ROOT" ]; then
        # 直接尝试拼接常见位置
        for scope_dir in \
            "${CGROUP_V2_ROOT}/system.slice/${cid}" \
            "${CGROUP_V2_ROOT}/kubepods.slice"/*/"${cid}"; do
            if [ -d "$scope_dir" ]; then
                echo "$scope_dir"
                return 0
            fi
        done
        # 在 kubepods 下递归查找该 basename（较慢，但能兜底）
        while IFS= read -r d; do
            if [ -d "$d" ] && [ "$(basename "$d")" = "$cid" ]; then
                echo "$d"
                return 0
            fi
        done < <(find "${CGROUP_V2_ROOT}/kubepods.slice" -type d -name "$cid" 2>/dev/null)
        return 0
    fi

    # v1: 按子系统查找
    local base="/sys/fs/cgroup/${subsys}"
    [ -d "$base" ] || return 0

    # 尝试直接拼接目录
    for path in \
        "${base}/docker/${cid}" \
        "${base}/system.slice/${cid}" \
        "${base}/kubepods/${cid}" \
        "${base}/kubepods.slice/${cid}" \
        "${base}/kubepods.slice/"*"/${cid}"; do
        if [ -d "$path" ]; then
            echo "$path"
            return 0
        fi
    done

    # 在 kubepods 下递归查找
    if [ -d "${base}/kubepods" ]; then
        while IFS= read -r d; do
            if [ -d "$d" ] && [ "$(basename "$d")" = "$cid" ]; then
                echo "$d"
                return 0
            fi
        done < <(find "${base}/kubepods" -mindepth 2 -maxdepth 4 -type d -name "$cid" 2>/dev/null)
    fi

    return 0
}

# ====================================================================
# 日志与报告目录初始化
# ====================================================================
mkdir -p "$BATCH_DIR"
> "$REPORT_FILE"

LOG_DIR="${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/collect_log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/container-collection_$(date '+%Y%m%d_%H%M%S').log"

# 重定向：fd 3 指向原始终端，stdout/stderr 写入日志
exec 3>&1
exec >"$LOG_FILE" 2>&1

# 抑制无害错误时的 ERR trap
trap 'echo "[FAIL] container-collection line $LINENO exit $?" >&3' ERR

echo "[BUSY] container-collection 开始采集 → $BATCH_DIR" >&3

# --- 开始采集 ---
{
    echo "============================================================"
    echo "容器资源监控采集"
    echo "采集时间: $(date)"
    echo "Cgroup 版本检测中..."
    echo "============================================================"
    echo ""
    echo "Cgroup 版本: $CGROUP_VER"
    [ -n "$CGROUP_V2_ROOT" ] && echo "Cgroup v2 根: $CGROUP_V2_ROOT"
    echo ""
} | tee -a "$REPORT_FILE"

# ======================================================================
# 1. 容器发现（返回完整 basename）
# ======================================================================
echo "=== 容器发现 ===" | tee -a "$REPORT_FILE"

CONTAINER_IDS=()
discover_containers() {
    local cids=()
    if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
        local base="$CGROUP_V2_ROOT"
        # system.slice 下所有以 docker-、containerd-、libpod- 开头的 scope 目录
        for scope in "$base"/system.slice/docker-*.scope \
                     "$base"/system.slice/containerd-*.scope \
                     "$base"/system.slice/libpod-*.scope; do
            [ -d "$scope" ] || continue
            cids+=("$(basename "$scope")")
        done
        # kubepods.slice 下所有 scope 目录
        while IFS= read -r d; do
            [ -d "$d" ] || continue
            cids+=("$(basename "$d")")
        done < <(find "$base/kubepods.slice" -name "*.scope" -type d 2>/dev/null)
    else
        for subsys in cpu blkio memory; do
            local base="/sys/fs/cgroup/$subsys"
            [ -d "$base" ] || continue
            # docker 直接子目录（无 scope 后缀）
            if [ -d "$base/docker" ]; then
                for d in "$base/docker"/*/; do
                    [ -d "$d" ] || continue
                    cids+=("$(basename "$d")")
                done
            fi
            # system.slice 下的 scope 目录
            for scope in "$base"/system.slice/docker-*.scope \
                         "$base"/system.slice/containerd-*.scope \
                         "$base"/system.slice/libpod-*.scope; do
                [ -d "$scope" ] || continue
                cids+=("$(basename "$scope")")
            done
            # kubepods 目录（非 systemd）
            if [ -d "$base/kubepods" ]; then
                while IFS= read -r d; do
                    [ -d "$d" ] || continue
                    cids+=("$(basename "$d")")
                done < <(find "$base/kubepods" -mindepth 2 -maxdepth 4 -type d 2>/dev/null)
            fi
            # systemd 风格的 kubepods.slice
            for scope in "$base"/kubepods.slice/*.slice/*.scope \
                         "$base"/kubepods.slice/*.scope; do
                [ -d "$scope" ] || continue
                cids+=("$(basename "$scope")")
            done
        done
    fi
    printf '%s\n' "${cids[@]}" | sort -u
}

while IFS= read -r cid; do
    [ -n "$cid" ] && CONTAINER_IDS+=("$cid")
done < <(discover_containers)

# 若 Docker 可用，用长 ID 补全（通过 compare 提取的 ID）
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    docker_ids=$(docker ps --no-trunc -q 2>/dev/null || true)
    for dcid in $docker_ids; do
        # 检查是否已存在（通过提取的纯 ID 比较）
        FOUND=0
        for cid in "${CONTAINER_IDS[@]}"; do
            pure_cid=$(extract_container_id "$cid")
            if [ "$pure_cid" = "$dcid" ]; then
                FOUND=1
                break
            fi
        done
        if [ "$FOUND" -eq 0 ]; then
            # 尝试用长 ID 构建可能的 cgroup 目录名（docker-<dcid>.scope）
            possible_scope="docker-${dcid}.scope"
            # 检查该 scope 是否真的存在（至少在一个子系统中）
            path_found=0
            for subsys in cpu memory blkio; do
                if [ -d "/sys/fs/cgroup/${subsys}/system.slice/${possible_scope}" ] || \
                   [ -d "/sys/fs/cgroup/${subsys}/docker/${dcid}" ]; then
                    path_found=1
                    break
                fi
            done
            # v2 下也检查
            if [ "$path_found" -eq 0 ] && [ -n "$CGROUP_V2_ROOT" ]; then
                if [ -d "${CGROUP_V2_ROOT}/system.slice/${possible_scope}" ]; then
                    path_found=1
                fi
            fi
            if [ "$path_found" -eq 1 ]; then
                CONTAINER_IDS+=("$possible_scope")
            else
                # 若找不到，仍加入 docker-<dcid>.scope 作为候选（get_cgroup_path 会尝试）
                CONTAINER_IDS+=("$possible_scope")
            fi
        fi
    done
fi

if [ ${#CONTAINER_IDS[@]} -gt 0 ]; then
    echo "发现 ${#CONTAINER_IDS[@]} 个容器" | tee -a "$REPORT_FILE"
    printf '%s\n' "${CONTAINER_IDS[@]}" | tee -a "$REPORT_FILE"
else
    echo "未发现运行中的容器" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# ======================================================================
# 2. 宿主机全局 CPU 快照
# ======================================================================
echo "## 宿主机 /proc/stat (cpu 行)" | tee -a "$REPORT_FILE"
cat /proc/stat | grep '^cpu ' | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# ======================================================================
# 3. 逐容器遍历
# ======================================================================
for CID in "${CONTAINER_IDS[@]}"; do
    echo "" | tee -a "$REPORT_FILE"
    echo "===== 容器: $CID =====" | tee -a "$REPORT_FILE"
    # 提取纯容器 ID 用于展示（可选）
    PURE_ID=$(extract_container_id "$CID")
    [ "$PURE_ID" != "$CID" ] && echo "（纯容器 ID: $PURE_ID）" | tee -a "$REPORT_FILE"

    # 获取各个子系统路径
    CGROUP_CPU_PATH=$(get_cgroup_path cpu "$CID")
    CGROUP_MEM_PATH=$(get_cgroup_path memory "$CID")
    CGROUP_BLKIO_PATH=$(get_cgroup_path blkio "$CID")
    CGROUP_CPUSET_PATH=$(get_cgroup_path cpuset "$CID")
    CGROUP_CPUACCT_PATH=$(get_cgroup_path cpuacct "$CID")  # v1 专用

    # 3a. CPU 限额
    if [ -n "$CGROUP_CPU_PATH" ]; then
        echo "## CPU 限额" | tee -a "$REPORT_FILE"
        if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
            if [ -f "$CGROUP_CPU_PATH/cpu.max" ]; then
                read max period < "$CGROUP_CPU_PATH/cpu.max"
                echo "  cpu.max = $max $period" | tee -a "$REPORT_FILE"
                if [ "$max" != "max" ] && [ "$period" -gt 0 ] 2>/dev/null; then
                    cpus=$(awk -v m="$max" -v p="$period" 'BEGIN { printf "%.2f", m/p }')
                    echo "  可用 CPU 数: $cpus" | tee -a "$REPORT_FILE"
                else
                    echo "  可用 CPU 数: 无限制" | tee -a "$REPORT_FILE"
                fi
            fi
            [ -f "$CGROUP_CPU_PATH/cpu.weight" ] && echo "  cpu.weight = $(cat "$CGROUP_CPU_PATH/cpu.weight")" | tee -a "$REPORT_FILE"
        else
            for f in cpu.cfs_period_us cpu.cfs_quota_us cpu.cfs_burst_us cpu.shares cpu.stat; do
                [ -f "$CGROUP_CPU_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_CPU_PATH/$f")" | tee -a "$REPORT_FILE"
            done
            [ -f "$CGROUP_CPU_PATH/cpu.soft_domain" ] && echo "  cpu.soft_domain = $(cat "$CGROUP_CPU_PATH/cpu.soft_domain")" | tee -a "$REPORT_FILE"
            if [ -f "$CGROUP_CPU_PATH/cpu.cfs_period_us" ] && [ -f "$CGROUP_CPU_PATH/cpu.cfs_quota_us" ]; then
                period=$(cat "$CGROUP_CPU_PATH/cpu.cfs_period_us")
                quota=$(cat "$CGROUP_CPU_PATH/cpu.cfs_quota_us")
                if [ "$quota" -gt 0 ] 2>/dev/null; then
                    cpus=$(awk -v q="$quota" -v p="$period" 'BEGIN { if (p>0) printf "%.2f", q/p; else print "无限制" }')
                    echo "  可用 CPU 数: $cpus" | tee -a "$REPORT_FILE"
                else
                    echo "  可用 CPU 数: 无限制 (quota=-1)" | tee -a "$REPORT_FILE"
                fi
            fi
        fi
    else
        echo "## CPU 限额 — 未找到 cgroup 路径" | tee -a "$REPORT_FILE"
    fi
    echo "" | tee -a "$REPORT_FILE"

    # 3b. CPU 累计使用
    if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
        if [ -n "$CGROUP_CPU_PATH" ] && [ -f "$CGROUP_CPU_PATH/cpu.stat" ]; then
            echo "## CPU 累计使用 (cpu.stat)" | tee -a "$REPORT_FILE"
            usage_usec=$(awk '/^usage_usec /{print $2}' "$CGROUP_CPU_PATH/cpu.stat" 2>/dev/null || true)
            if [ -n "$usage_usec" ]; then
                usage_ns=$(( usage_usec * 1000 ))
                usage_s=$(awk -v ns="$usage_ns" 'BEGIN { printf "%.3f", ns/1000000000 }')
                echo "  usage_usec = $usage_usec us  (≈ $usage_s s)" | tee -a "$REPORT_FILE"
            fi
            cat "$CGROUP_CPU_PATH/cpu.stat" 2>/dev/null | tee -a "$REPORT_FILE" || true
        fi
    else
        if [ -n "$CGROUP_CPUACCT_PATH" ]; then
            echo "## CPU 累计使用 (cpuacct)" | tee -a "$REPORT_FILE"
            if [ -f "$CGROUP_CPUACCT_PATH/cpuacct.usage" ]; then
                USAGE_NS=$(cat "$CGROUP_CPUACCT_PATH/cpuacct.usage" 2>/dev/null || echo 0)
                USAGE_S=$(awk -v ns="$USAGE_NS" 'BEGIN { printf "%.3f", ns/1000000000 }')
                echo "  cpuacct.usage = $USAGE_NS ns ($USAGE_S s)" | tee -a "$REPORT_FILE"
            fi
            [ -f "$CGROUP_CPUACCT_PATH/cpuacct.usage_percpu" ] && echo "  usage_percpu (ns): $(cat "$CGROUP_CPUACCT_PATH/cpuacct.usage_percpu")" | tee -a "$REPORT_FILE"
        fi
    fi
    echo "" | tee -a "$REPORT_FILE"

    # 3c. NUMA/CPU 亲和性
    if [ -n "$CGROUP_CPUSET_PATH" ]; then
        echo "## NUMA/CPU 亲和性" | tee -a "$REPORT_FILE"
        if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
            for f in cpuset.cpus cpuset.mems cpuset.cpus.effective cpuset.mems.effective; do
                [ -f "$CGROUP_CPUSET_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_CPUSET_PATH/$f")" | tee -a "$REPORT_FILE"
            done
        else
            for f in cpuset.cpus cpuset.mems cpuset.cpu_exclusive cpuset.mem_exclusive cpuset.memory_migrate cpuset.sched_relax_domain_level; do
                [ -f "$CGROUP_CPUSET_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_CPUSET_PATH/$f")" | tee -a "$REPORT_FILE"
            done
        fi
    fi
    echo "" | tee -a "$REPORT_FILE"

    # 3d. 内存配置与使用
    if [ -n "$CGROUP_MEM_PATH" ]; then
        echo "## 内存配置与使用" | tee -a "$REPORT_FILE"
        if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
            [ -f "$CGROUP_MEM_PATH/memory.max" ] && echo "  memory.max = $(cat "$CGROUP_MEM_PATH/memory.max")" | tee -a "$REPORT_FILE"
            if [ -f "$CGROUP_MEM_PATH/memory.current" ]; then
                usage=$(cat "$CGROUP_MEM_PATH/memory.current")
                echo "  memory.current = $usage" | tee -a "$REPORT_FILE"
                limit=$(cat "$CGROUP_MEM_PATH/memory.max" 2>/dev/null || echo "max")
                if [ "$limit" != "max" ] && [ "$limit" -gt 0 ] 2>/dev/null; then
                    LIMIT_GB=$(awk -v l="$limit" 'BEGIN { printf "%.2f", l/1073741824 }')
                    USAGE_GB=$(awk -v u="$usage" 'BEGIN { printf "%.2f", u/1073741824 }')
                    echo "  内存限额: $LIMIT_GB GB, 使用: $USAGE_GB GB" | tee -a "$REPORT_FILE"
                else
                    echo "  内存限额: 无限制" | tee -a "$REPORT_FILE"
                fi
            fi
            [ -f "$CGROUP_MEM_PATH/memory.stat" ] && { echo "  memory.stat (前5行):"; head -5 "$CGROUP_MEM_PATH/memory.stat" | tee -a "$REPORT_FILE"; }
        else
            for f in memory.limit_in_bytes memory.usage_in_bytes memory.max_usage_in_bytes memory.stat memory.kmem.usage_in_bytes memory.kmem.limit_in_bytes memory.oom_control; do
                [ -f "$CGROUP_MEM_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_MEM_PATH/$f" | head -5)" | tee -a "$REPORT_FILE"
            done
            if [ -f "$CGROUP_MEM_PATH/memory.limit_in_bytes" ] && [ -f "$CGROUP_MEM_PATH/memory.usage_in_bytes" ]; then
                LIMIT=$(cat "$CGROUP_MEM_PATH/memory.limit_in_bytes")
                USAGE=$(cat "$CGROUP_MEM_PATH/memory.usage_in_bytes")
                if [ "$LIMIT" -gt 0 ] 2>/dev/null && [ "$LIMIT" != "9223372036854771712" ]; then
                    LIMIT_GB=$(awk -v l="$LIMIT" 'BEGIN { printf "%.2f", l/1073741824 }')
                    USAGE_GB=$(awk -v u="$USAGE" 'BEGIN { printf "%.2f", u/1073741824 }')
                    echo "  内存限额: $LIMIT_GB GB, 使用: $USAGE_GB GB" | tee -a "$REPORT_FILE"
                else
                    echo "  内存限额: 无限制" | tee -a "$REPORT_FILE"
                fi
            fi
        fi
    fi
    echo "" | tee -a "$REPORT_FILE"

    # 3e. blkio 限速
    if [ -n "$CGROUP_BLKIO_PATH" ]; then
        echo "## blkio 限速" | tee -a "$REPORT_FILE"
        if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
            [ -f "$CGROUP_BLKIO_PATH/io.max" ] && echo "  io.max = $(cat "$CGROUP_BLKIO_PATH/io.max")" | tee -a "$REPORT_FILE"
        else
            for f in blkio.throttle.read_bps_device blkio.throttle.write_bps_device blkio.throttle.read_iops_device blkio.throttle.write_iops_device blkio.io_service_bytes blkio.io_serviced blkio.weight; do
                [ -f "$CGROUP_BLKIO_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_BLKIO_PATH/$f" | head -5)" | tee -a "$REPORT_FILE"
            done
        fi
    fi
    echo "" | tee -a "$REPORT_FILE"

    # 3f. 任务列表
    if [ -n "$CGROUP_CPU_PATH" ]; then
        tasks_file=""
        [ -f "$CGROUP_CPU_PATH/cgroup.threads" ] && tasks_file="$CGROUP_CPU_PATH/cgroup.threads"
        [ -z "$tasks_file" ] && [ -f "$CGROUP_CPU_PATH/tasks" ] && tasks_file="$CGROUP_CPU_PATH/tasks"
        if [ -n "$tasks_file" ]; then
            TASK_COUNT=$(wc -l < "$tasks_file" 2>/dev/null || echo 0)
            echo "## 任务列表" | tee -a "$REPORT_FILE"
            echo "  线程总数: $TASK_COUNT" | tee -a "$REPORT_FILE"
            echo "  前20个TID映射:" | tee -a "$REPORT_FILE"
            head -20 "$tasks_file" 2>/dev/null | while read tid; do
                comm=$(cat "/proc/$tid/comm" 2>/dev/null || echo "?")
                tpid=$(awk '/^Tgid:/{print $2}' "/proc/$tid/status" 2>/dev/null || echo "?")
                echo "    TID=$tid COMM=$comm PID=$tpid" | tee -a "$REPORT_FILE"
            done || true
        fi
    fi
    echo "" | tee -a "$REPORT_FILE"
done

# ======================================================================
# 4. /proc/stat 第二次快照 (间隔1秒)
# ======================================================================
sleep 1
echo "## 宿主机 /proc/stat 第二次快照 (间隔1s)" | tee -a "$REPORT_FILE"
cat /proc/stat | grep '^cpu ' | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# ======================================================================
# 5. Docker Daemon 辅助信息（使用纯容器 ID）
# ======================================================================
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    echo "## Docker Daemon 信息" | tee -a "$REPORT_FILE"
    docker info 2>/dev/null | grep -E "Server Version|Storage Driver|Cgroup Driver|Cgroup Version|Total Memory|Operating System" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    for CID in "${CONTAINER_IDS[@]}"; do
        PURE_ID=$(extract_container_id "$CID")
        echo "## 容器元数据 (ID: $PURE_ID)" | tee -a "$REPORT_FILE"
        if docker inspect "$PURE_ID" >/dev/null 2>&1; then
            docker inspect "$PURE_ID" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)[0]
name = data.get('Name', '?').lstrip('/')
s = data.get('State', {})
print(f'Name: {name}')
print(f'Image: {data.get(\"Config\", {}).get(\"Image\", \"?\")}')
print(f'Status: {s.get(\"Status\", \"?\")}')
hc = data.get('HostConfig', {})
print(f'CpuQuota: {hc.get(\"CpuQuota\", \"N/A\")}')
print(f'CpuPeriod: {hc.get(\"CpuPeriod\", \"N/A\")}')
print(f'CpuShares: {hc.get(\"CpuShares\", \"N/A\")}')
print(f'NanoCpus: {hc.get(\"NanoCpus\", \"N/A\")}')
print(f'CpusetCpus: {hc.get(\"CpusetCpus\", \"N/A\")}')
print(f'Memory: {hc.get(\"Memory\", \"N/A\")}')
" | tee -a "$REPORT_FILE" || {
                echo "python 解析失败" | tee -a "$REPORT_FILE"
                docker inspect "$PURE_ID" >> "$REPORT_FILE" 2>/dev/null || true
            }
        else
            echo "docker inspect 不可用（可能非 Docker 容器或无权限）" | tee -a "$REPORT_FILE"
        fi
        echo "" | tee -a "$REPORT_FILE"
    done
fi
echo "" | tee -a "$REPORT_FILE"

# ======================================================================
# 6. 容器 CPU 多采样观测窗口（使用完整 CID 寻找路径）
# ======================================================================
if [ "$SKIP_MULTI" -eq 0 ] && [ ${#CONTAINER_IDS[@]} -gt 0 ]; then
    NUM_SAMPLES=$(( OBSERVATION_WINDOW / SAMPLE_INTERVAL + 1 ))
    [ "$NUM_SAMPLES" -lt 2 ] && NUM_SAMPLES=2

    echo "[BUSY] container-collection: 多采样 ${OBSERVATION_WINDOW}s..." >&3
    echo "## 容器 CPU 多采样观测 (${OBSERVATION_WINDOW}s, ${SAMPLE_INTERVAL}s 间隔)" | tee -a "$REPORT_FILE"

    for ((i=1; i<=NUM_SAMPLES; i++)); do
        TS_EPOCH=$(date +%s.%N)
        {
            echo "=== SAMPLE $i ==="
            echo "=== TIMESTAMP $TS_EPOCH ==="
            for CID in "${CONTAINER_IDS[@]}"; do
                CGROUP_CPU_PATH=$(get_cgroup_path cpu "$CID")
                if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                    USAGE_NS="0"
                    PERIOD_US="0"
                    QUOTA_US="0"
                    BURST_US="0"
                    SOFT_QUOTA=0
                    if [ -n "$CGROUP_CPU_PATH" ]; then
                        if [ -f "$CGROUP_CPU_PATH/cpu.max" ]; then
                            read max period < "$CGROUP_CPU_PATH/cpu.max" 2>/dev/null || true
                            PERIOD_US="$period"
                            QUOTA_US="$max"
                            if [ "$max" != "max" ] && [ "$period" -gt 0 ] 2>/dev/null; then
                                if [ -f "$CGROUP_CPU_PATH/cpu.max.burst" ]; then
                                    BURST_US=$(cat "$CGROUP_CPU_PATH/cpu.max.burst" 2>/dev/null || echo 0)
                                    [ -n "$BURST_US" ] && [ "$BURST_US" -gt 0 ] 2>/dev/null && SOFT_QUOTA=1
                                fi
                            fi
                        fi
                        if [ -f "$CGROUP_CPU_PATH/cpu.stat" ]; then
                            usec=$(awk '/^usage_usec /{print $2}' "$CGROUP_CPU_PATH/cpu.stat" 2>/dev/null || echo 0)
                            [ -n "$usec" ] && USAGE_NS=$(( usec * 1000 ))
                        fi
                    fi
                else
                    CGROUP_CPUACCT_PATH=$(get_cgroup_path cpuacct "$CID")
                    PERIOD_US=""
                    QUOTA_US=""
                    USAGE_NS=""
                    BURST_US=""
                    SOFT_QUOTA=0
                    if [ -n "$CGROUP_CPU_PATH" ]; then
                        [ -f "$CGROUP_CPU_PATH/cpu.cfs_period_us" ] && PERIOD_US=$(cat "$CGROUP_CPU_PATH/cpu.cfs_period_us")
                        [ -f "$CGROUP_CPU_PATH/cpu.cfs_quota_us" ] && QUOTA_US=$(cat "$CGROUP_CPU_PATH/cpu.cfs_quota_us")
                        [ -f "$CGROUP_CPU_PATH/cpu.cfs_burst_us" ] && BURST_US=$(cat "$CGROUP_CPU_PATH/cpu.cfs_burst_us")
                        if [ -f "$CGROUP_CPU_PATH/cpu.soft_quota" ]; then
                            SOFT_QUOTA=$(cat "$CGROUP_CPU_PATH/cpu.soft_quota")
                        elif [ -n "$BURST_US" ] && [ "$BURST_US" -gt 0 ] 2>/dev/null; then
                            SOFT_QUOTA=1
                        fi
                    fi
                    if [ -n "$CGROUP_CPUACCT_PATH" ] && [ -f "$CGROUP_CPUACCT_PATH/cpuacct.usage" ]; then
                        USAGE_NS=$(cat "$CGROUP_CPUACCT_PATH/cpuacct.usage" 2>/dev/null || echo 0)
                    fi
                fi
                echo "--- CONTAINER ---"
                echo "id=$CID"
                echo "cfs_period_us=${PERIOD_US:-0}"
                echo "cfs_quota_us=${QUOTA_US:-0}"
                echo "cpuacct_usage=${USAGE_NS:-0}"
                echo "soft_quota=$SOFT_QUOTA"
                echo "timestamp=$TS_EPOCH"
                echo "--- END CONTAINER ---"
            done
            echo ""
        } | tee -a "$REPORT_FILE"
        if [ "$i" -lt "$NUM_SAMPLES" ]; then
            sleep "$SAMPLE_INTERVAL"
        fi
    done
fi

# ======================================================================
# 完成
# ======================================================================
echo "[OK] container-collection: 采集完成，报告 $REPORT_FILE" >&3