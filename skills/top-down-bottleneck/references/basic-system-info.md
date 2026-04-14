---
name: basic-system-info
description: Collect system environment static information (hardware specs, software versions, kernel boot parameters)
---

# basic-system-info — System Environment Static Information Collection

## Client Connection and Command Execution

Load the remote-execution skill for standardized SSH connection and command execution:

skill:remote-execution

---

## Hardware Specifications

```bash
# CPU model, sockets, cores, threads, cache sizes
lscpu

# NUMA topology
numactl --hardware 2>/dev/null || true

# Memory size and DIMM info
dmidecode -t memory 2>/dev/null | grep -E "Size|Speed|Type|Locator" || true

# Physical memory summary
cat /proc/meminfo | grep -E "MemTotal|SwapTotal|HugePages_Total|HugePages_Free"

# Disk devices and topology (ROTA=1 means rotational/HDD, ROTA=0 means SSD)
lsblk -o NAME,SIZE,TYPE,ROTA,MOUNTPOINT

# SCSI device info
cat /proc/scsi/scsi 2>/dev/null || true

# NIC models
lspci | grep -i eth || true

# NIC driver and firmware versions
for iface in $(ls /sys/class/net/ | grep -v lo); do echo "=== $iface ==="; ethtool -i $iface 2>/dev/null || true; done

# Hardware model
cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true
dmidecode -t system 2>/dev/null | grep -E "Manufacturer|Product Name|Version" || true

# CPU frequency scaling info
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true
cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || true
```

---

## Software Versions

```bash
# OS release
cat /etc/os-release

# Kernel version and build
uname -r && uname -v

# GCC version (affects compiled binary performance)
gcc --version 2>/dev/null | head -1 || true

# glibc version
ldd --version 2>/dev/null | head -1 || true
```

---

## Kernel Boot Parameters

```bash
# Kernel command line (all boot parameters)
cat /proc/cmdline

# Key performance-related sysctl switches (NOT full listing — only knobs with direct performance impact)
sysctl -a 2>/dev/null | grep -E "^vm\.(swappiness|dirty_ratio|dirty_background_ratio|dirty_writeback_centisecs|min_free_kbytes|vfs_cache_pressure|overcommit_memory|overcommit_ratio|nr_hugepages|zone_reclaim_mode|numa_balancing)" || true
sysctl -a 2>/dev/null | grep -E "^net\.(core\.(somaxconn|netdev_max_backlog|netdev_budget|rmem_max|wmem_max)|ipv4\.(tcp_tw_reuse|tcp_max_syn_backlog|tcp_rmem|tcp_wmem|tcp_syncookies|tcp_fin_timeout|tcp_fastopen))" || true
sysctl -a 2>/dev/null | grep -E "^kernel\.(sched_(min_granularity_ns|wakeup_granularity_ns|migration_cost_ns|cfs_bandwidth_slice_us|autogroup_enabled)|numa_balancing|threads-max)" || true
sysctl -a 2>/dev/null | grep -E "^fs\.(file-max|aio-max-nr|nr_open|inotify\.)" || true

# Performance-relevant kernel modules only (NOT full lsmod)
lsmod 2>/dev/null | grep -iE "kvm|nvme|mlx|io_uring|dpdk|vfio|iommu|intel_cstate|intel_uncore|acpi_cpufreq|cpufreq|tuned" || true

# Kernel tickless / nohz / preempt config
cat /boot/config-$(uname -r) 2>/dev/null | grep -E "NO_HZ|HZ_1000|PREEMPT" || true

# Transparent hugepage status
cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true

# I/O scheduler for each block device
for dev in $(ls /sys/block/); do echo "$dev: $(cat /sys/block/$dev/queue/scheduler 2>/dev/null)"; done || true

# IRQ affinity configuration
cat /proc/irq/default_smp_affinity 2>/dev/null || true
```

---

## Usage Notes

- **Static info only**: This reference collects STATIC system facts. Dynamic runtime metrics (CPU utilization, memory pressure, I/O throughput) are collected in Phase 2.
- **Tolerate missing tools**: `dmidecode`, `ethtool`, `numactl` may not be available — use `|| true` to tolerate failures.
- **Root required**: `dmidecode` and some `ethtool` operations require root access.
