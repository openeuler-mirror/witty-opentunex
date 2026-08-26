#!/bin/bash
set -euo pipefail

# ====================================================================
# 参数与路径初始化
# ====================================================================
# 用法:
#   collect_mem_info.sh [batch_dir] [duration] [pids]
#   环境变量: WORK_DIR / DURATION / PIDS
DEFAULT_TS=$(date +%Y%m%d_%H%M%S)
BATCH_DIR="${1:-${WORK_DIR:-/srv/opentunex/${DEFAULT_TS}}/collect/}"
REPORT_FILE="${BATCH_DIR}/mem-collection_report.txt"
DURATION="${2:-${DURATION:-5}}"
INTERVAL=1
PIDS="${PIDS:-}"

mkdir -p "$BATCH_DIR"
> "$REPORT_FILE"

LOG_DIR="${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/collect_log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/mem-collection_$(date '+%Y%m%d_%H%M%S').log"

# 重定向：保留 fd3 指向原始终端，之后 stdout/stderr 写入日志
exec 3>&1
exec >"$LOG_FILE" 2>&1

trap 'echo "[FAIL] mem-collection line $LINENO exit $?" >&3' ERR
echo "[BUSY] mem-collection 开始采集 → $BATCH_DIR" >&3

# ====================================================================
# 采集开始 — 头部块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "Phase: Memory Metrics for Bottleneck Analysis"
    echo "============================================================"
    echo "采集时间: $(date)"
    if [ -n "$PIDS" ]; then
        echo "目标进程: $PIDS"
    fi
    echo ""
} | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# System Overview
# --------------------------------------------------------------------
echo "=== System Overview ===" | tee -a "$REPORT_FILE"
echo "Kernel: $(uname -r)" | tee -a "$REPORT_FILE"
echo "CPU Count: $(nproc)" | tee -a "$REPORT_FILE"
echo "Memory Total: $(free -h | awk '/^Mem:/{print $2}')" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Memory Pressure (PSI)
# --------------------------------------------------------------------
echo "=== Memory Pressure (PSI) ===" | tee -a "$REPORT_FILE"
if [ -f /proc/pressure/mem ] && [ -r /proc/pressure/mem ]; then
    cat /proc/pressure/mem 2>/dev/null | tee -a "$REPORT_FILE"
else
    echo "/proc/pressure/mem not available." | tee -a "$REPORT_FILE"
    echo "To enable: Add psi=1 to kernel boot params in /etc/default/grub," | tee -a "$REPORT_FILE"
    echo "           then run: grub2-mkconfig -o /boot/grub2/grub.cfg && reboot" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Memory Usage
# --------------------------------------------------------------------
echo "=== Memory Usage ===" | tee -a "$REPORT_FILE"
free -h 2>/dev/null | tee -a "$REPORT_FILE" || echo "free 不可用" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# VM OOM Stats
# --------------------------------------------------------------------
echo "=== VM OOM Stats ===" | tee -a "$REPORT_FILE"
if [ -r /proc/vmstat ]; then
    oom_stats=$(cat /proc/vmstat 2>/dev/null | grep -E 'oom_kill|pgmajfault' || true)
    if [ -n "$oom_stats" ]; then
        echo "$oom_stats" | tee -a "$REPORT_FILE"
    else
        echo "No OOM kills or major page faults recorded" | tee -a "$REPORT_FILE"
    fi
else
    echo "Cannot read /proc/vmstat" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Swap Configuration
# --------------------------------------------------------------------
echo "=== Swap Configuration ===" | tee -a "$REPORT_FILE"
if swapon -s 2>/dev/null | tee -a "$REPORT_FILE"; then
    :
elif cat /proc/swaps 2>/dev/null | tee -a "$REPORT_FILE"; then
    :
else
    echo "No swap configured or cannot read swap info" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Slab Info
# --------------------------------------------------------------------
echo "=== Slab Info ===" | tee -a "$REPORT_FILE"
if [ -r /proc/slabinfo ]; then
    head -30 /proc/slabinfo 2>/dev/null | tee -a "$REPORT_FILE"
else
    echo "/proc/slabinfo not readable (requires root)" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Vmalloc Region
# --------------------------------------------------------------------
echo "=== Vmalloc Region ===" | tee -a "$REPORT_FILE"
cat /proc/meminfo 2>/dev/null | grep -E "VmallocTotal|VmallocUsed" | tee -a "$REPORT_FILE" || echo "无法读取" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Memory Allocation/Reclaim Stats
# --------------------------------------------------------------------
echo "=== Memory Allocation/Reclaim Stats ===" | tee -a "$REPORT_FILE"
cat /proc/vmstat 2>/dev/null | grep -E "pgfault|pgmajflt|pgalloc|pgfree|pgscank|pgscand|pgsteal|pgrotated" | head -20 | tee -a "$REPORT_FILE" || echo "无数据" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Memory Details (meminfo)
# --------------------------------------------------------------------
echo "=== Memory Details (meminfo) ===" | tee -a "$REPORT_FILE"
cat /proc/meminfo 2>/dev/null | grep -E "Active:|Inactive:|SReclaimable|SUnreclaim|Shmem:|VmallocUsed:|Committed_AS:" | tee -a "$REPORT_FILE" || echo "无数据" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# HugePages Configuration
# --------------------------------------------------------------------
echo "=== HugePages Configuration ===" | tee -a "$REPORT_FILE"
if [ -r /proc/sys/vm/nr_hugepages ]; then
    echo "nr_hugepages: $(cat /proc/sys/vm/nr_hugepages 2>/dev/null)" | tee -a "$REPORT_FILE"
fi
cat /proc/meminfo 2>/dev/null | grep -E "HugePages_Total|HugePages_Free|HugePages_Rsvd|Hugepagesize:" | tee -a "$REPORT_FILE"
if [ -r /sys/kernel/mm/transparent_hugepage/enabled ]; then
    echo "transparent_hugepage: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# OOM Configuration
# --------------------------------------------------------------------
echo "=== OOM Configuration ===" | tee -a "$REPORT_FILE"
if [ -r /proc/sys/vm/oom_kill_allocating_task ]; then
    echo "oom_kill_allocating_task: $(cat /proc/sys/vm/oom_kill_allocating_task 2>/dev/null)" | tee -a "$REPORT_FILE"
fi
if [ -r /proc/sys/vm/oom_dump_tasks ]; then
    echo "oom_dump_tasks: $(cat /proc/sys/vm/oom_dump_tasks 2>/dev/null)" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# KSM Configuration
# --------------------------------------------------------------------
echo "=== KSM Configuration ===" | tee -a "$REPORT_FILE"
if [ -f /sys/kernel/mm/ksm/run ] && [ -r /sys/kernel/mm/ksm/run ]; then
    echo "ksm.run: $(cat /sys/kernel/mm/ksm/run 2>/dev/null)" | tee -a "$REPORT_FILE"
    echo "ksm.pages_shared: $(cat /sys/kernel/mm/ksm/pages_shared 2>/dev/null || echo 'N/A')" | tee -a "$REPORT_FILE"
    echo "ksm.pages_sharing: $(cat /sys/kernel/mm/ksm/pages_sharing 2>/dev/null || echo 'N/A')" | tee -a "$REPORT_FILE"
else
    echo "KSM not available" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# NUMA Balancing
# --------------------------------------------------------------------
echo "=== NUMA Balancing ===" | tee -a "$REPORT_FILE"
if [ -r /proc/sys/kernel/numa_balancing ]; then
    echo "numa_balancing: $(cat /proc/sys/kernel/numa_balancing 2>/dev/null)" | tee -a "$REPORT_FILE"
else
    echo "numa_balancing: N/A" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Memory CGroup Limits
# --------------------------------------------------------------------
echo "=== Memory CGroup Limits ===" | tee -a "$REPORT_FILE"
if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ] && [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    echo "memory.limit_in_bytes: $(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)" | tee -a "$REPORT_FILE"
    echo "memory.soft_limit_in_bytes: $(cat /sys/fs/cgroup/memory/memory.soft_limit_in_bytes 2>/dev/null)" | tee -a "$REPORT_FILE"
    echo "memory.usage_in_bytes: $(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null)" | tee -a "$REPORT_FILE"
elif [ -f /sys/fs/cgroup/memory.max ] && [ -r /sys/fs/cgroup/memory.max ]; then
    # cgroup v2
    echo "memory.max: $(cat /sys/fs/cgroup/memory.max 2>/dev/null)" | tee -a "$REPORT_FILE"
    echo "memory.current: $(cat /sys/fs/cgroup/memory.current 2>/dev/null)" | tee -a "$REPORT_FILE"
    echo "memory.low: $(cat /sys/fs/cgroup/memory.low 2>/dev/null)" | tee -a "$REPORT_FILE"
else
    echo "Memory cgroup limits not available" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Memory Watermarks
# --------------------------------------------------------------------
echo "=== Memory Watermarks ===" | tee -a "$REPORT_FILE"
if [ -r /proc/sys/vm/watermark_scale_factor ]; then
    echo "watermark_scale_factor: $(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null)" | tee -a "$REPORT_FILE"
fi
if [ -r /proc/sys/vm/watermark_boost_factor ]; then
    echo "watermark_boost_factor: $(cat /proc/sys/vm/watermark_boost_factor 2>/dev/null)" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Memory Zone Info (per node)
# --------------------------------------------------------------------
echo "=== Memory Zone Info (per node) ===" | tee -a "$REPORT_FILE"
if [ -r /proc/zoneinfo ]; then
    cat /proc/zoneinfo 2>/dev/null | grep -E "Node|zone" | head -30 | tee -a "$REPORT_FILE"
else
    echo "无法读取 /proc/zoneinfo" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# jemalloc Configuration（如果指定了 PID）
# --------------------------------------------------------------------
echo "=== jemalloc Configuration ===" | tee -a "$REPORT_FILE"
if [ -n "$PIDS" ]; then
    IFS=',' read -ra pid_array <<< "$PIDS"
    for single_pid in "${pid_array[@]}"; do
        single_pid=$(echo "$single_pid" | xargs || true)
        if [ -f "/proc/$single_pid/maps" ] && [ -r "/proc/$single_pid/maps" ]; then
            jemap=$(grep -i jemalloc /proc/$single_pid/maps 2>/dev/null | head -1 || true)
            if [ -n "$jemap" ]; then
                echo "jemalloc detected in target process (PID $single_pid):" | tee -a "$REPORT_FILE"
                echo "$jemap" | tee -a "$REPORT_FILE"
            else
                echo "Target process $single_pid does NOT use jemalloc" | tee -a "$REPORT_FILE"
            fi
        elif [ -n "$single_pid" ]; then
            echo "Target process /proc/$single_pid/maps not available" | tee -a "$REPORT_FILE"
        fi
    done
else
    echo "No target PID provided; skipping process mapping check" | tee -a "$REPORT_FILE"
fi

echo "" | tee -a "$REPORT_FILE"
echo "--- jemalloc Environment Variables ---" | tee -a "$REPORT_FILE"
echo "MALLOC_ARENA_MAX: ${MALLOC_ARENA_MAX:-not set}" | tee -a "$REPORT_FILE"
echo "MALLOC_CONF: ${MALLOC_CONF:-not set}" | tee -a "$REPORT_FILE"

if [ -n "${MALLOC_CONF:-}" ]; then
    echo "" | tee -a "$REPORT_FILE"
    echo "--- MALLOC_CONF breakdown ---" | tee -a "$REPORT_FILE"
    for key in background_thread dirty_decay_ms muzzy_decay_ms narenas percpu_arena \
               oversize_threshold metadata_thp lg_extent_max_active_fit \
               tcache lg_tcache_max prof prof_active stats_print; do
        val=$(echo "${MALLOC_CONF:-}" | grep -oP "${key}:\K[^,]+" 2>/dev/null || true)
        if [ -n "$val" ]; then
            echo "  $key=$val" | tee -a "$REPORT_FILE"
        fi
    done
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# NUMA Statistics (system-wide)
# --------------------------------------------------------------------
echo "=== NUMA Statistics (system-wide) ===" | tee -a "$REPORT_FILE"
if [ -r /proc/vmstat ]; then
    cat /proc/vmstat 2>/dev/null | grep -E "numa_hit|numa_miss|numa_foreign|numa_local|numa_other" | head -20 | tee -a "$REPORT_FILE" || echo "无数据" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Process NUMA Memory Distribution（如果指定了 PID）
# --------------------------------------------------------------------
if [ -n "$PIDS" ]; then
    IFS=',' read -ra pid_array <<< "$PIDS"
    for single_pid in "${pid_array[@]}"; do
        single_pid=$(echo "$single_pid" | xargs || true)
        if [ -d "/proc/$single_pid" ]; then
            echo "=== Process NUMA Memory Distribution (PID: $single_pid) ===" | tee -a "$REPORT_FILE"
            if command -v numastat &> /dev/null; then
                numastat -p "$single_pid" 2>/dev/null | tee -a "$REPORT_FILE" || echo "numastat failed" | tee -a "$REPORT_FILE"
            elif [ -f "/proc/$single_pid/numa_maps" ] && [ -r "/proc/$single_pid/numa_maps" ]; then
                echo "numastat not available, see /proc/$single_pid/numa_maps for details" | tee -a "$REPORT_FILE"
            else
                echo "numastat not available" | tee -a "$REPORT_FILE"
            fi

            # 检查内存节点 vs CPU节点亲和性
            if [ -f "/proc/$single_pid/numa_maps" ] && [ -r "/proc/$single_pid/numa_maps" ]; then
                dom=$(awk '{
                    for(i=1;i<=NF;i++) if($i ~ "^N[0-9]+=") {
                        split($i,a,"="); sum[a[1]]+=a[2]
                    }
                } END {
                    for(n in sum) if(sum[n] > max) {max=sum[n]; dom=n}
                    print dom
                }' /proc/$single_pid/numa_maps 2>/dev/null)
                cpu_node=$(ps -o psr -p "$single_pid" --no-headers | xargs || true)
                numa_of_cpu="unknown"
                if [ -n "$cpu_node" ] && command -v lscpu &> /dev/null; then
                    numa_of_cpu=$(lscpu -p=cpu,node 2>/dev/null | awk -F, -v cpu="$cpu_node" '$1==cpu {print $2}' || true)
                fi
                dom_num=$(echo "$dom" | sed 's/^N//' || true)
                echo "" | tee -a "$REPORT_FILE"
                echo "  Memory dominant node: ${dom_num:-?}  |  CPU node: ${numa_of_cpu:-?}  |  CPU: ${cpu_node:-?}" | tee -a "$REPORT_FILE"
                if [ -n "$dom_num" ] && [ "$numa_of_cpu" != "unknown" ] && [ "$dom_num" != "$numa_of_cpu" ]; then
                    echo "  WARNING: memory on node $dom_num but process on node $numa_of_cpu (remote access)" | tee -a "$REPORT_FILE"
                fi
            fi
            echo "" | tee -a "$REPORT_FILE"
        fi
    done
fi

# --------------------------------------------------------------------
# NUMA Node Layout
# --------------------------------------------------------------------
echo "=== NUMA Node Layout ===" | tee -a "$REPORT_FILE"
if command -v numactl &> /dev/null; then
    numactl --hardware 2>/dev/null | tee -a "$REPORT_FILE"
else
    echo "numactl not available" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# NUMA Current Policy
# --------------------------------------------------------------------
echo "=== NUMA Current Policy ===" | tee -a "$REPORT_FILE"
if command -v numactl &> /dev/null; then
    numactl --show 2>/dev/null | tee -a "$REPORT_FILE"
else
    echo "numactl not available" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# NUMA Nodes
# --------------------------------------------------------------------
echo "=== NUMA Nodes ===" | tee -a "$REPORT_FILE"
if command -v lscpu &> /dev/null; then
    lscpu 2>/dev/null | grep "NUMA" | tee -a "$REPORT_FILE" || echo "无 NUMA 信息" | tee -a "$REPORT_FILE"
else
    echo "lscpu not available" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Memory per NUMA Node
# --------------------------------------------------------------------
echo "=== Memory per NUMA Node ===" | tee -a "$REPORT_FILE"
if [ -r /proc/buddyinfo ]; then
    cat /proc/buddyinfo 2>/dev/null | tee -a "$REPORT_FILE"
else
    echo "Cannot read /proc/buddyinfo" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Recent OOM Events
# --------------------------------------------------------------------
echo "=== Recent OOM Events ===" | tee -a "$REPORT_FILE"
oom_events_success=false
if command -v dmesg &> /dev/null; then
    oom_events=$(dmesg -T 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10 || true)
    if [ -n "$oom_events" ]; then
        echo "$oom_events" | tee -a "$REPORT_FILE"
        oom_events_success=true
    fi
fi
if [ "$oom_events_success" = false ] && command -v journalctl &> /dev/null; then
    oom_events=$(journalctl -k 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10 || true)
    if [ -n "$oom_events" ]; then
        echo "$oom_events" | tee -a "$REPORT_FILE"
        oom_events_success=true
    fi
fi
[ "$oom_events_success" = false ] && echo "No recent OOM events found" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Memory Optimization Recommendations
# --------------------------------------------------------------------
echo "=== Memory Optimization Recommendations ===" | tee -a "$REPORT_FILE"

# 检查 swap 使用
if command -v free &> /dev/null; then
    swap_used=$(free 2>/dev/null | awk '/^Swap:/ {print $3}' || true)
    swap_total=$(free 2>/dev/null | awk '/^Swap:/ {print $2}' || true)
    if [ -n "$swap_used" ] && [ -n "$swap_total" ] && [ "$swap_total" -gt 0 ] 2>/dev/null; then
        swap_pct=$((swap_used * 100 / swap_total))
        if [ "$swap_pct" -gt 50 ]; then
            echo "⚠ WARNING: High swap usage ($swap_pct%). Consider increasing memory or reducing memory pressure." | tee -a "$REPORT_FILE"
        fi
    fi
fi

# 检查 OOM kill
if [ -r /proc/vmstat ]; then
    oom_kills=$(cat /proc/vmstat 2>/dev/null | grep oom_kill | awk '{print $2}' || true)
    if [ -n "$oom_kills" ] && [ "$oom_kills" -gt 0 ] 2>/dev/null; then
        echo "⚠ WARNING: $oom_kills OOM kills detected. System is memory constrained." | tee -a "$REPORT_FILE"
    fi
fi

# 检查大页使用
if [ -r /proc/meminfo ]; then
    hugepage_total=$(cat /proc/meminfo 2>/dev/null | grep HugePages_Total | awk '{print $2}' || true)
    if [ -n "$hugepage_total" ] && [ "$hugepage_total" -gt 0 ] 2>/dev/null; then
        hugepage_free=$(cat /proc/meminfo 2>/dev/null | grep HugePages_Free | awk '{print $2}' || true)
        hugepage_used=$((hugepage_total - hugepage_free))
        if [ "$hugepage_used" -eq 0 ] 2>/dev/null; then
            echo "💡 TIP: HugePages configured but not used. Check application support or adjust allocation." | tee -a "$REPORT_FILE"
        fi
    fi
fi

# 检查 NUMA 平衡
if [ -r /proc/sys/kernel/numa_balancing ]; then
    numa_balancing=$(cat /proc/sys/kernel/numa_balancing 2>/dev/null)
    if [ "$numa_balancing" = "0" ]; then
        echo "ℹ INFO: NUMA balancing is disabled. For NUMA systems, consider enabling (echo 1 > /proc/sys/kernel/numa_balancing)" | tee -a "$REPORT_FILE"
    fi
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 完整 /proc/meminfo（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 完整 /proc/meminfo ===" | tee -a "$REPORT_FILE"
cat /proc/meminfo 2>/dev/null | tee -a "$REPORT_FILE" || echo "无法读取 /proc/meminfo" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 完整 /proc/vmstat（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 完整 /proc/vmstat ===" | tee -a "$REPORT_FILE"
cat /proc/vmstat 2>/dev/null | tee -a "$REPORT_FILE" || echo "无法读取 /proc/vmstat" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 系统内存页大小（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 系统内存页大小 ===" | tee -a "$REPORT_FILE"
if command -v getconf &>/dev/null; then
    getconf PAGE_SIZE 2>/dev/null | tee -a "$REPORT_FILE" || echo "获取失败" | tee -a "$REPORT_FILE"
else
    grep -i "Hugepagesize" /proc/meminfo | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 大页目录详情（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 大页目录详情 ===" | tee -a "$REPORT_FILE"
if [ -d /sys/kernel/mm/hugepages ]; then
    for d in /sys/kernel/mm/hugepages/hugepages-*; do
        [ -d "$d" ] && echo "$(basename "$d"): nr_hugepages=$(cat "$d/nr_hugepages" 2>/dev/null || echo "?"), free=$(cat "$d/free_hugepages" 2>/dev/null || echo "?")" | tee -a "$REPORT_FILE"
    done
else
    echo "hugepages 目录不存在" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# NUMA 节点内存详情（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== NUMA 节点内存详情 ===" | tee -a "$REPORT_FILE"
if [ -d /sys/devices/system/node ]; then
    for node in /sys/devices/system/node/node*; do
        [ -d "$node" ] || continue
        node_name=$(basename "$node")
        echo "--- $node_name ---" | tee -a "$REPORT_FILE"
        if [ -f "$node/meminfo" ]; then
            grep -E "MemTotal|MemFree|Active|Inactive|Dirty|Writeback|FilePages|Mapped|AnonPages|Shmem|KernelStack|PageTables" "$node/meminfo" 2>/dev/null | tee -a "$REPORT_FILE"
        else
            echo "meminfo 不可用" | tee -a "$REPORT_FILE"
        fi
    done
else
    echo "NUMA 节点信息不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 进程内存占用 Top 15 (RSS)（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 进程内存占用 Top 15 (RSS) ===" | tee -a "$REPORT_FILE"
ps -eo pid,comm,rss,vsz --sort=-rss 2>/dev/null | head -16 | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# vmstat 持续采样（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== vmstat Continuous Sampling (${DURATION} seconds) ===" | tee -a "$REPORT_FILE"
echo "[BUSY] mem-collection: vmstat ${DURATION}s..." >&3
if command -v vmstat &>/dev/null; then
    vmstat -w -t "$INTERVAL" "$DURATION" 2>/dev/null | tee -a "$REPORT_FILE"
else
    echo "警告: vmstat 不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# ====================================================================
# 完成 — 结尾块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "Memory Metrics Analysis Complete"
    echo "============================================================"
} | tee -a "$REPORT_FILE"
echo "[OK] mem-collection: 采集完成，报告 $REPORT_FILE" >&3
