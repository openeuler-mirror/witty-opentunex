#!/bin/bash
# collect_mem_metrics.sh - Collect memory metrics for bottleneck analysis
# Usage: collect_mem_metrics.sh [PID]

TARGET_PID=${1:-}

echo "=== Memory Metrics Collection ==="
if [ -n "$TARGET_PID" ]; then
    echo "Target PID: $TARGET_PID"
fi
echo ""

# System overview
echo "=== System Overview ==="
uname -r
echo "CPU Count: $(nproc)"
echo "Memory Total: $(free -h | awk '/^Mem:/{print $2}')"
echo ""

# Memory PSI - with enable hint if unavailable
echo "=== Memory Pressure (PSI) ==="
if [ -f /proc/pressure/mem ]; then
    cat /proc/pressure/mem
else
    echo "/proc/pressure/mem not available."
    echo "To enable: Add psi=1 to kernel boot params in /etc/default/grub,"
    echo "           then run: grub2-mkconfig -o /boot/grub2/grub.cfg && reboot"
fi
echo ""

# Memory usage
echo "=== Memory Usage ==="
free -h
echo ""

# VM OOM stats
echo "=== VM OOM Stats ==="
oom_stats=$(cat /proc/vmstat | grep -E 'oom_kill|pgmajfault')
if [ -n "$oom_stats" ]; then
    echo "$oom_stats"
else
    echo "No OOM kills or major page faults recorded"
fi
echo ""

# Swap configuration
echo "=== Swap Configuration ==="
swapon -s 2>/dev/null || cat /proc/swaps
echo ""

# Slab info
echo "=== Slab Info ==="
if [ -r /proc/slabinfo ]; then
    head -30 /proc/slabinfo
else
    echo "/proc/slabinfo not readable (requires root)"
fi
echo ""

# Vmalloc region
echo "=== Vmalloc Region ==="
cat /proc/meminfo | grep -E "VmallocTotal|VmallocUsed"
echo ""

# Memory allocation and reclaim stats
echo "=== Memory Allocation/Reclaim Stats ==="
cat /proc/vmstat | grep -E "pgfault|pgmajflt|pgalloc|pgfree|pgscank|pgscand|pgsteal|pgrotated" | head -20
echo ""

# Memory details from meminfo
echo "=== Memory Details (meminfo) ==="
cat /proc/meminfo | grep -E "Active:|Inactive:|SReclaimable|SUnreclaim|Shmem:|VmallocUsed:|Committed_AS:"
echo ""

# HugePages configuration
echo "=== HugePages Configuration ==="
cat /proc/sys/vm/nr_hugepages 2>/dev/null
cat /proc/meminfo | grep -E "HugePages_Total|HugePages_Free|HugePages_Rsvd|Hugepagesize:"
echo "transparent_hugepage: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo 'N/A')"
echo ""

# OOM configuration
echo "=== OOM Configuration ==="
echo "oom_kill_allocating_task: $(cat /proc/sys/vm/oom_kill_allocating_task 2>/dev/null || echo 'N/A')"
echo "oom_dump_tasks: $(cat /proc/sys/vm/oom_dump_tasks 2>/dev/null || echo 'N/A')"
echo ""

# KSM (Kernel Samepage Merging)
echo "=== KSM Configuration ==="
if [ -f /sys/kernel/mm/ksm/run ]; then
    echo "ksm.run: $(cat /sys/kernel/mm/ksm/run)"
    echo "ksm.pages_shared: $(cat /sys/kernel/mm/ksm/pages_shared 2>/dev/null || echo 'N/A')"
    echo "ksm.pages_sharing: $(cat /sys/kernel/mm/ksm/pages_sharing 2>/dev/null || echo 'N/A')"
else
    echo "KSM not available"
fi
echo ""

# NUMA balancing
echo "=== NUMA Balancing ==="
echo "numa_balancing: $(cat /proc/sys/kernel/numa_balancing 2>/dev/null || echo 'N/A')"
echo ""

# Memory cgroup limits (v1)
echo "=== Memory CGroup Limits ==="
if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    echo "memory.limit_in_bytes: $(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)"
    echo "memory.soft_limit_in_bytes: $(cat /sys/fs/cgroup/memory/memory.soft_limit_in_bytes 2>/dev/null)"
    echo "memory.usage_in_bytes: $(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null)"
elif [ -f /sys/fs/cgroup/memory.max ]; then
    # cgroup v2
    echo "memory.max: $(cat /sys/fs/cgroup/memory.max 2>/dev/null)"
    echo "memory.current: $(cat /sys/fs/cgroup/memory.current 2>/dev/null)"
    echo "memory.low: $(cat /sys/fs/cgroup/memory.low 2>/dev/null)"
else
    echo "Memory cgroup limits not available"
fi
echo ""

# Memory watermarks
echo "=== Memory Watermarks ==="
echo "watermark_scale_factor: $(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null || echo 'N/A')"
echo "watermark_boost_factor: $(cat /proc/sys/vm/watermark_boost_factor 2>/dev/null || echo 'N/A')"
echo ""

# Memory zone info (per NUMA node)
echo "=== Memory Zone Info (per node) ==="
cat /proc/zoneinfo 2>/dev/null | grep -E "Node|zone" | head -30
echo ""

# jemalloc configuration (if enabled)
echo "=== jemalloc Configuration ==="
jemalloc_in_use=0

# Check if target process actually links jemalloc
if [ -n "$TARGET_PID" ] && [ -f /proc/$TARGET_PID/maps ]; then
    jemap=$(grep -i jemalloc /proc/$TARGET_PID/maps 2>/dev/null | head -1)
    if [ -n "$jemap" ]; then
        echo "jemalloc detected in target process:"
        echo "$jemap"
        jemalloc_in_use=1
    else
        echo "Target process does NOT use jemalloc"
    fi
elif [ -n "$TARGET_PID" ]; then
    echo "Target process /proc/$TARGET_PID/maps not available"
else
    echo "No target PID provided; skipping process mapping check"
fi

# Show relevant jemalloc env vars regardless of whether in use
echo ""
echo "--- jemalloc Environment Variables ---"
echo "MALLOC_ARENA_MAX: ${MALLOC_ARENA_MAX:-not set}"
echo "MALLOC_CONF: ${MALLOC_CONF:-not set}"

# Parse key MALLOC_CONF tunables
if [ -n "$MALLOC_CONF" ]; then
    echo ""
    echo "--- MALLOC_CONF breakdown ---"
    for key in background_thread dirty_decay_ms muzzy_decay_ms narenas percpu_arena \
               oversize_threshold metadata_thp lg_extent_max_active_fit \
               tcache lg_tcache_max prof prof_active stats_print; do
        val=$(echo "$MALLOC_CONF" | grep -oP "${key}:\K[^,]+")
        if [ -n "$val" ]; then
            echo "  $key=$val"
        fi
    done
fi
echo ""

# NUMA statistics (system-wide)
echo "=== NUMA Statistics (system-wide) ==="
cat /proc/vmstat | grep -E "numa_hit|numa_miss|numa_foreign|numa_local|numa_other" | head -20
echo ""

# NUMA statistics (per-process)
if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
    echo "=== Process NUMA Memory Distribution ==="
    if command -v numastat &> /dev/null; then
        numastat -p $TARGET_PID
    elif [ -f /proc/$TARGET_PID/numa_maps ]; then
        echo "(numastat not available)"
    else
        echo "numastat not available"
    fi

    # Dominant node vs CPU node check
    if [ -f /proc/$TARGET_PID/numa_maps ]; then
        dom=$(awk '{
            for(i=1;i<=NF;i++) if($i ~ "^N[0-9]+=") {
                split($i,a,"="); sum[a[1]]+=a[2]
            }
        } END {
            for(n in sum) if(sum[n] > max) {max=sum[n]; dom=n}
            print dom
        }' /proc/$TARGET_PID/numa_maps)
        cpu_node=$(awk '$1==pid {print $NF}' pid=$TARGET_PID /proc/$TARGET_PID/stat 2>/dev/null)
        numa_of_cpu="unknown"
        if [ -n "$cpu_node" ]; then
            numa_of_cpu=$(lscpu -p=cpu,node 2>/dev/null | awk -F, -v cpu="$cpu_node" '$1==cpu {print $2}')
        fi
        dom_num=$(echo "$dom" | sed 's/^N//')
        echo ""
        echo "  Memory dominant node: ${dom_num:-?}  |  CPU node: ${numa_of_cpu:-?}  |  CPU: ${cpu_node:-?}"
        if [ -n "$dom_num" ] && [ "$numa_of_cpu" != "unknown" ] && [ "$dom_num" != "$numa_of_cpu" ]; then
            echo "  WARNING: memory on node $dom_num but process on node $numa_of_cpu (remote access)"
        fi
    fi
    echo ""
fi

# NUMA node layout and distances
echo "=== NUMA Node Layout ==="
if command -v numactl &> /dev/null; then
    numactl --hardware 2>/dev/null
    echo ""
    echo "=== NUMA Current Policy ==="
    numactl --show 2>/dev/null
else
    echo "numactl not available"
fi
echo ""

# NUMA node count from lscpu
echo "=== NUMA Nodes ==="
lscpu | grep "NUMA" 2>/dev/null || echo "N/A"
echo ""

# Memory per NUMA node
echo "=== Memory per NUMA Node ==="
cat /proc/buddyinfo 2>/dev/null || echo "N/A"
echo ""

# Recent OOM events
echo "=== Recent OOM Events ==="
oom_events=$(dmesg -T 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10)
if [ -z "$oom_events" ] && command -v journalctl &> /dev/null; then
    oom_events=$(journalctl -k 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10)
fi
if [ -n "$oom_events" ]; then
    echo "$oom_events"
else
    echo "No recent OOM events found"
fi
echo ""
