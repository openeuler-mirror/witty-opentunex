#!/bin/bash
# collect_mem_metrics.sh - Collect memory metrics for bottleneck analysis
# Usage: collect_mem_metrics.sh

echo "=== Memory Metrics Collection ==="
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
cat /proc/vmstat | grep -E 'oom|pgmajfault'
echo ""

# Swap configuration
echo "=== Swap Configuration ==="
swapon -s 2>/dev/null || cat /proc/swaps
echo ""

# Slab info
echo "=== Slab Info ==="
cat /proc/slabinfo 2>/dev/null | head -30
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

# Memory cgroup limits (if in cgroup)
echo "=== Memory CGroup Limits ==="
if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    echo "memory.limit_in_bytes: $(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo 'N/A')"
    echo "memory.soft_limit_in_bytes: $(cat /sys/fs/cgroup/memory/memory.soft_limit_in_bytes 2>/dev/null || echo 'N/A')"
    echo "memory.usage_in_bytes: $(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null || echo 'N/A')"
else
    echo "Not in memory cgroup or limits not set"
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
if [ -n "$MALLOC_ARENA_MAX" ]; then
    echo "MALLOC_ARENA_MAX: $MALLOC_ARENA_MAX"
else
    echo "jemalloc using default arena settings"
fi
if [ -f /proc/self/maps ]; then
    grep -i jemalloc /proc/self/maps 2>/dev/null | head -5 || echo "No jemalloc mappings found"
fi
echo ""

# NUMA statistics
echo "=== NUMA Statistics ==="
cat /proc/vmstat | grep -E "numa_hit|numa_miss|numa_foreign|numa_local|numa_other" | head -20
echo ""

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
dmesg -T 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10 || journalctl -k 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10
echo ""
