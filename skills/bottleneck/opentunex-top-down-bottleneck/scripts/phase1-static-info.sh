#!/bin/bash
# =============================================================================
# phase1-static-info.sh — Phase 1: System Environment Static Information
# =============================================================================
# Usage: bash phase1-static-info.sh
# No parameters required. Must run as root for dmidecode/ethtool.
# All commands are lightweight (read-only), but serialized for simplicity.
# =============================================================================


collect_static_info() {
    echo "============================================================"
    echo "Phase 1: System Environment Static Information Collection"
    echo "============================================================"
    echo ""

    echo "========== Hardware Specifications =========="

    echo "--- CPU Model, Sockets, Cores, Threads, Cache ---"
    lscpu

    echo ""
    echo "--- NUMA Topology ---"
    numactl --hardware 2>/dev/null || true

    echo ""
    echo "--- Memory DIMM Info ---"
    dmidecode -t memory 2>/dev/null | grep -E "Size|Speed|Type|Locator|^$" | grep -Ev "None|Unknown" || true

    echo ""
    echo "--- Physical Memory Summary ---"
    cat /proc/meminfo | grep -E "MemTotal|SwapTotal|HugePages_Total|HugePages_Free"

    echo ""
    echo "--- Disk Devices and Topology (ROTA=1=HDD, ROTA=0=SSD) ---"
    lsblk -o NAME,SIZE,TYPE,ROTA,MOUNTPOINT

    echo ""
    echo "--- SCSI Device Info ---"
    cat /proc/scsi/scsi 2>/dev/null || true

    echo ""
    echo "--- NIC Models ---"
    lspci | grep -i eth || true

    echo ""
    echo "--- NIC Driver and Firmware ---"
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        echo "=== $iface ==="
        ethtool -i "$iface" 2>/dev/null || true
    done

    echo ""
    echo "--- Hardware Model ---"
    cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true
    dmidecode -t system 2>/dev/null | grep -E "Manufacturer|Product Name|Version" || true

    echo ""
    echo "--- CPU Frequency Scaling ---"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true
    cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || true

    echo ""
    echo "========== Software Versions =========="

    echo "--- OS Release ---"
    cat /etc/os-release

    echo ""
    echo "--- Kernel Version ---"
    uname -r

    echo ""
    echo "--- libgcc Version ---"
    rpm -qa libgcc 2>/dev/null | head -1 || true

    echo ""
    echo "--- glibc Version ---"
    rpm -qa glibc 2>/dev/null | head -1 || true

    echo ""
    echo "========== Kernel Boot Parameters =========="

    echo "--- Kernel Command Line ---"
    cat /proc/cmdline

    echo ""
    echo "--- Performance-Related sysctl: vm.* ---"
    sysctl -a 2>/dev/null | grep -E "^vm\.(swappiness|dirty_ratio|dirty_background_ratio|dirty_writeback_centisecs|min_free_kbytes|vfs_cache_pressure|overcommit_memory|overcommit_ratio|nr_hugepages|zone_reclaim_mode|numa_balancing)" || true

    echo ""
    echo "--- Performance-Related sysctl: net.* ---"
    sysctl -a 2>/dev/null | grep -E "^net\.(core\.(somaxconn|netdev_max_backlog|netdev_budget|rmem_max|wmem_max)|ipv4\.(tcp_tw_reuse|tcp_max_syn_backlog|tcp_rmem|tcp_wmem|tcp_syncookies|tcp_fin_timeout|tcp_fastopen))" || true

    echo ""
    echo "--- Performance-Related sysctl: kernel.sched*/numa/threads ---"
    sysctl -a 2>/dev/null | grep -E "^kernel\.(sched_(min_granularity_ns|wakeup_granularity_ns|migration_cost_ns|cfs_bandwidth_slice_us|autogroup_enabled)|numa_balancing|threads-max)" || true

    echo ""
    echo "--- Performance-Related sysctl: fs.* ---"
    sysctl -a 2>/dev/null | grep -E "^fs\.(file-max|aio-max-nr|nr_open|inotify\.)" || true

    echo ""
    echo "--- Performance-Relevant Kernel Modules ---"
    lsmod 2>/dev/null | grep -iE "kvm|nvme|mlx|io_uring|dpdk|vfio|iommu|intel_cstate|intel_uncore|acpi_cpufreq|cpufreq|tuned" || true

    echo ""
    echo "--- Kernel Tickless / nohz / Preempt Config ---"
    cat /boot/config-$(uname -r) 2>/dev/null | grep -E "NO_HZ|HZ_1000|PREEMPT" || true

    echo ""
    echo "--- Transparent Hugepage Status ---"
    cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true

    echo ""
    echo "--- I/O Scheduler per Block Device ---"
    for dev in $(ls /sys/block/); do
        if [ -f /sys/block/$dev/queue/scheduler ]; then
            echo "$dev: $(cat /sys/block/$dev/queue/scheduler 2>/dev/null)"
        else
            echo "$dev: (no scheduler file, e.g. dm device)"
        fi
    done

    echo ""
    echo "--- Default IRQ Affinity ---"
    cat /proc/irq/default_smp_affinity 2>/dev/null || true

    echo ""
    echo "============================================================"
    echo "Phase 1: Static Information Collection Complete"
    echo "============================================================"
}

parse_param "$@"
collect_static_info
