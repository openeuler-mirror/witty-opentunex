#!/bin/bash
# collect_mem_metrics.sh - Collect memory metrics for bottleneck analysis
#
# Usage:
#   bash collect_mem_metrics.sh [--pid <PID>]
#
# Parameters:
#   --pid — Target process PID (optional)
#
# Examples:
#   # System-wide collection:
#   bash collect_mem_metrics.sh
#
#   # Target process collection:
#   bash collect_mem_metrics.sh --pid 12345
#
# Save output to file:
#   bash collect_mem_metrics.sh --pid 12345 > mem_result.txt 2>&1

TARGET_PID=""

parse_param() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pid)
                if [ -z "$2" ] || [[ "$2" == --* ]]; then
                    echo "Error: --pid requires a value" >&2
                    echo "Usage: bash $0 [--pid <PID>]" >&2
                    exit 1
                fi
                TARGET_PID="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Usage: bash $0 [--pid <PID>]" >&2
                exit 1
                ;;
        esac
    done

    if [ -n "$TARGET_PID" ]; then
        if ! [[ "$TARGET_PID" =~ ^[0-9]+$ ]]; then
            echo "Error: --pid must be a numeric value, got: $TARGET_PID" >&2
            exit 1
        fi

        if [ ! -d "/proc/$TARGET_PID" ]; then
            echo "Error: Process with PID $TARGET_PID does not exist" >&2
            exit 1
        fi
    fi
}

collect_mem_metrics() {
    echo "=== Memory Metrics Collection ==="
    if [ -n "$TARGET_PID" ]; then
        echo "Target PID: $TARGET_PID"
    fi
    echo ""

    echo "=== System Overview ==="
    uname -r
    echo "CPU Count: $(nproc)"
    echo "Memory Total: $(free -h | awk '/^Mem:/{print $2}')"
    echo ""

    echo "=== Memory Pressure (PSI) ==="
    if [ -f /proc/pressure/mem ]; then
        cat /proc/pressure/mem
    else
        echo "/proc/pressure/mem not available."
        echo "To enable: Add psi=1 to kernel boot params in /etc/default/grub,"
        echo "           then run: grub2-mkconfig -o /boot/grub2/grub.cfg && reboot"
    fi
    echo ""

    echo "=== Memory Usage ==="
    free -h
    echo ""

    echo "=== VM OOM Stats ==="
    oom_stats=$(cat /proc/vmstat | grep -E 'oom_kill|pgmajfault')
    if [ -n "$oom_stats" ]; then
        echo "$oom_stats"
    else
        echo "No OOM kills or major page faults recorded"
    fi
    echo ""

    echo "=== Swap Configuration ==="
    swapon -s 2>/dev/null || cat /proc/swaps
    echo ""

    echo "=== Slab Info ==="
    if [ -r /proc/slabinfo ]; then
        head -30 /proc/slabinfo
    else
        echo "/proc/slabinfo not readable (requires root)"
    fi
    echo ""

    echo "=== Vmalloc Region ==="
    cat /proc/meminfo | grep -E "VmallocTotal|VmallocUsed"
    echo ""

    echo "=== Memory Allocation/Reclaim Stats ==="
    cat /proc/vmstat | grep -E "pgfault|pgmajflt|pgalloc|pgfree|pgscank|pgscand|pgsteal|pgrotated" | head -20
    echo ""

    echo "=== Memory Details (meminfo) ==="
    cat /proc/meminfo | grep -E "Active:|Inactive:|SReclaimable|SUnreclaim|Shmem:|VmallocUsed:|Committed_AS:"
    echo ""

    echo "=== HugePages Configuration ==="
    cat /proc/sys/vm/nr_hugepages 2>/dev/null
    cat /proc/meminfo | grep -E "HugePages_Total|HugePages_Free|HugePages_Rsvd|Hugepagesize:"
    echo "transparent_hugepage: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo 'N/A')"
    echo ""

    echo "=== OOM Configuration ==="
    echo "oom_kill_allocating_task: $(cat /proc/sys/vm/oom_kill_allocating_task 2>/dev/null || echo 'N/A')"
    echo "oom_dump_tasks: $(cat /proc/sys/vm/oom_dump_tasks 2>/dev/null || echo 'N/A')"
    echo ""

    echo "=== KSM Configuration ==="
    if [ -f /sys/kernel/mm/ksm/run ]; then
        echo "ksm.run: $(cat /sys/kernel/mm/ksm/run)"
        echo "ksm.pages_shared: $(cat /sys/kernel/mm/ksm/pages_shared 2>/dev/null || echo 'N/A')"
        echo "ksm.pages_sharing: $(cat /sys/kernel/mm/ksm/pages_sharing 2>/dev/null || echo 'N/A')"
    else
        echo "KSM not available"
    fi
    echo ""

    echo "=== NUMA Balancing ==="
    echo "numa_balancing: $(cat /proc/sys/kernel/numa_balancing 2>/dev/null || echo 'N/A')"
    echo ""

    echo "=== Memory CGroup Limits ==="
    if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        echo "memory.limit_in_bytes: $(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)"
        echo "memory.soft_limit_in_bytes: $(cat /sys/fs/cgroup/memory/soft_limit_in_bytes 2>/dev/null)"
        echo "memory.usage_in_bytes: $(cat /sys/fs/cgroup/memory/usage_in_bytes 2>/dev/null)"
    elif [ -f /sys/fs/cgroup/memory.max ]; then
        echo "memory.max: $(cat /sys/fs/cgroup/memory.max 2>/dev/null)"
        echo "memory.current: $(cat /sys/fs/cgroup/memory.current 2>/dev/null)"
        echo "memory.low: $(cat /sys/fs/cgroup/memory.low 2>/dev/null)"
    else
        echo "Memory cgroup limits not available"
    fi
    echo ""

    echo "=== Memory Watermarks ==="
    echo "watermark_scale_factor: $(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null || echo 'N/A')"
    echo "watermark_boost_factor: $(cat /proc/sys/vm/watermark_boost_factor 2>/dev/null || echo 'N/A')"
    echo ""

    echo "=== Memory Zone Info (per node) ==="
    cat /proc/zoneinfo 2>/dev/null | grep -E "Node|zone" | head -30
    echo ""

    echo "=== jemalloc Configuration ==="
    jemalloc_in_use=0

    if [ -n "$TARGET_PID" ] && [ -f "/proc/$TARGET_PID/maps" ]; then
        jemap=$(grep -i jemalloc "/proc/$TARGET_PID/maps" 2>/dev/null | head -1)
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

    echo ""
    echo "--- jemalloc Environment Variables ---"
    echo "MALLOC_ARENA_MAX: ${MALLOC_ARENA_MAX:-not set}"
    echo "MALLOC_CONF: ${MALLOC_CONF:-not set}"

    if [ -n "$MALLOC_CONF" ]; then
        echo ""
        echo "--- MALLOC_CONF breakdown ---"
        for key in background_thread dirty_decay_ms muzzy_decay_ms narenas percpu_arena \
                   oversize_threshold metadata_thp lg_extent_max_active_fit \
                   tcache lg_tcache_max prof prof_active stats_print; do
            val=$(echo "$MALLOC_CONF" | sed -n "s/.*${key}:\([^,]*\).*/\1/p")
            if [ -n "$val" ]; then
                echo "  $key=$val"
            fi
        done
    fi
    echo ""

    echo "=== NUMA Statistics (system-wide) ==="
    cat /proc/vmstat | grep -E "numa_hit|numa_miss|numa_foreign|numa_local|numa_other" | head -20
    echo ""

    if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
        echo "=== Process NUMA Memory Distribution ==="
        if command -v numastat &> /dev/null; then
            numastat -p "$TARGET_PID"
        elif [ -f "/proc/$TARGET_PID/numa_maps" ]; then
            echo "(numastat not available)"
        else
            echo "numastat not available"
        fi

        if [ -f "/proc/$TARGET_PID/numa_maps" ]; then
            dom=$(awk '{
                for(i=1;i<=NF;i++) if($i ~ "^N[0-9]+=") {
                    split($i,a,"="); sum[a[1]]+=a[2]
                }
            } END {
                for(n in sum) if(sum[n] > max) {max=sum[n]; dom=n}
                if(max==0) {print "none"; exit}
                print dom
            }' "/proc/$TARGET_PID/numa_maps")
            cpu_node=$(awk '$1==pid {print $NF}' pid="$TARGET_PID" "/proc/$TARGET_PID/stat" 2>/dev/null)
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

    echo "=== NUMA Nodes ==="
    lscpu | grep "NUMA" 2>/dev/null || echo "N/A"
    echo ""

    echo "=== Memory per NUMA Node ==="
    cat /proc/buddyinfo 2>/dev/null || echo "N/A"
    echo ""

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
}

parse_param "$@"
collect_mem_metrics
