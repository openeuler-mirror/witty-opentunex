# Top-Down Bottleneck Analysis Report

## System Environment Static Information

**Hardware Specifications**:
- CPU: [model, sockets, cores/socket, threads/core, cache sizes]
- NUMA: [node count, CPU list per node, memory per node]
- Memory: [total size, DIMM count, speed, type]
- Disk: [device list with type (SSD/HDD), size, scheduler]
- NIC: [interface list with model, driver, firmware]

**Software Versions**:
- OS: [distribution, version]
- Kernel: [version, build config summary]
- Key Tools: [sysstat, perf, gcc, glibc versions]

**Kernel Boot Parameters**:
- Command line: [/proc/cmdline content]
- Key sysctl: [vm.*, net.*, kernel.sched*, kernel.numa*, fs.* settings]
- Kernel modules: [top loaded modules]
- THP: [always/madvise/never]
- I/O schedulers: [per-device scheduler setting]

## Analysis Scenario

[e.g. mysql database + sysbench random read N threads concurrency]

## Bottleneck Analysis Summary

### Primary Bottleneck: [Resource/Component]

**Severity**: [Critical/High/Medium/Low]
**Affected Processes**: [All PIDs affected]
**Bottleneck Chain**:
[%iowait > 30%, disk %util > 90%] → Global I/O saturation observed
 ↓
[proc XYZ read=50MB/s] → Process XYZ identified as major I/O consumer
 ↓
[60% time in ext4_readpage, syscall read() blocked] → Hotspot function identified
 ↓
[LLC miss rate 45%] → Memory access pattern issue confirmed
 ↓
[io-bottleneck deep-dive] → I/O scheduler and page cache pressure confirmed
**Evidence Mapping**:
| Bottleneck points | Key Finding | Related Process | Evidence Source |
|------------|------------------|---------------------|---------------------|
| [sub-Bottleneck 1] | [metric=value] | [PID] | [Phase_xxx.txt/Phase name/Skill name], ... |
| [sub-Bottleneck 2] | [metric=value] | [PID] | [Phase_xxx.txt/Phase name/Skill name], ... |
| ... | ... | ... | ... |
**Root Cause**: [Single-sentence OS-level root cause， e.g. I/O bound process with LLC thrashing, excessive page cache pressure]

### Secondary Bottleneck(s)**: [repeat of bottlenecks]

## OS-Level Tuning Recommendations

**CPU Bottleneck Tuning Recommendations**:
| Bottleneck Type | Tuning Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| High %user (>80%) | Check `nice`/`renice` priority; consider CPU affinity pinning via `taskset`; if latency-sensitive workload, enable tickless kernel (`nohz_full`) via `nohz_full=<cpu-list>` kernel cmdline | Reduce scheduling contention | Verify no other critical processes are affected by affinity changes |
| High %iowait (>20%) | See Disk I/O section below; also check `vm.dirty_ratio` and `vm.dirty_background_ratio` | Reduce CPU blocked on I/O | Monitor disk latency after changes |
| High %soft (>10%) | Review kernel softirq configuration; check `net.core.netdev_budget`; enable/configure `irqbalance` service | Reduce softirq CPU overhead | Monitor network throughput after changes |
| High %steal (>10%) | (VM) Not directly tunable inside guest; consider VM host-level CPU quota or CPU pinning adjustment | N/A | N/A |
| High context switches (>50k/s) | Identify syscall-heavy processes via `strace`; reduce system call frequency at OS level (e.g., check unnecessary `fsync`, `sync_file_range` calls); use compiler-level optimization (`-fno-stack-protector` if stack checks overhead is high) to reduce per-call overhead | Lower scheduler pressure | Monitor scheduling latency after changes |
| CPU-bound workload with high IPC | Compiler-level: rebuild with `-O3 -march=native -mtune=native` for CPU-specific optimizations; check `-fprofile-use` for PGO | Improve instruction-level parallelism and reduce instruction overhead | PGO requires representative training workload; test in staging |

**Memory Bottleneck Tuning Recommendations**:
| Bottleneck Type | Tuning Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| Swap used > 50% | Reduce `vm.swappiness` (e.g., to 10 or lower for SSD-backed swap); increase `vm.min_free_kbytes` to retain more free memory | Reduce page-in/page-out thrashing | Lower swappiness may cause OOM in some configs |
| majflt/s > 1000 | Increase `vm.min_free_kbytes`; check `vm.vfs_cache_pressure` | Reduce major page faults | Monitor memory pressure after changes |
| Slab > 30% total | Check `/proc/slabinfo` for high-use slabs; tune `vm.memory_balloon` (if enabled) | Free kernel memory for user processes | Monitor kernel stability |
| NUMA imbalance (remote/local > 2:1) | Enable NUMA balancing via `numactl --interleave=all` or tune `numa_balancing` via `/proc/sys/kernel/numa_balancing` | Reduce remote memory access latency | Not all workloads benefit from interleave |
| Excessive malloc/free fragmentation | Replace system malloc with jemalloc via `LD_PRELOAD=/usr/lib64/libjemalloc.so.2` or via `/etc/ld.so.preload`; alternatively configure `MALLOC_ARENA_MAX` env var | Reduce memory allocator fragmentation and improve multi-threaded memory performance | Verify jemalloc is compatible with the application; test in staging |

**Disk I/O Bottleneck Tuning Recommendations**:
| Bottleneck Type | Tuning Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| %util > 90%, await > 20ms | Change I/O scheduler to `mq-deadline` or `none` (for SSD/NVMe): `echo mq-deadline > /sys/block/<device>/queue/scheduler` | Reduce I/O queue latency | Test in staging first |
| High write latency | Reduce `vm.dirty_background_ratio` (e.g., to 5) and `vm.dirty_ratio` (e.g., to 20); enable `vm.dirty_writeback_centisecs=500` | Batch disk writes more aggressively | May increase RAM usage |
| High read latency | Increase `vm.pagecache` or use `readahead` tuning; check `blkdiscard` for SSD TRIM | Improve read-ahead effectiveness | Verify filesystem supports readahead changes |
| Queue depth saturation | Increase `nr_requests` via `/sys/block/<device>/queue/nr_requests` (e.g., to 1024) | Allow more in-flight I/O | May increase latency for individual ops |
| High disk I/O across multiple devices | Enable and tune `irqbalance` service to distribute storage interrupts across CPU cores | Reduce interrupt contention on single core | Verify storage device supports multi-queue IRQ routing |
| Transparent hugepage fragmentation | Enable transparent hugepages (`always`): `echo always > /sys/kernel/mm/transparent_hugepage/enabled`; tune `khugepaged` via `/sys/kernel/mm/transparent_hugepage/khugepaged/` | Reduce memory fragmentation for large workloads | May cause latency spikes in some applications; monitor |
| I/O priority contention | Use `ionice` to set CFQ/bfq scheduler for latency-sensitive processes; combine with `nice` for CPU/IO priority separation | Isolate latency-sensitive I/O from bulk I/O | Verify CFQ/bfq is available on the system |

**Network Bottleneck Tuning Recommendations**:
| Bottleneck Type | Tuning Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| High retransmission (>2%) | Tune `tcp_rmem`/`tcp_wmem`; enable `tcp_tw_reuse=1`; increase `tcp_max_syn_backlog` | Reduce retransmissions and TIME_WAIT buildup | Monitor connection stability |
| ListenOverflows/Drops > 0 | Increase `net.core.somaxconn` and `net.ipv4.tcp_max_syn_backlog` | Accept more incoming connections | Verify socket backlog capacity at OS level is sufficient |
| High TIME_WAIT (>5000) | Enable `tcp_tw_reuse=1`; reduce `net.netfilter.nf_conntrack_tcp_timeout_time_wait` | Free socket buffer memory | Not safe if NAT/conntrack is in use |
| High socket memory | Increase `net.core.rmem_max`/`wmem_max`; tune `net.ipv4.tcp_rmem`/`tcp_wmem` | Prevent socket buffer exhaustion | Monitor network throughput |
| High softirq CPU from network | Enable/configure `irqbalance` service to distribute NIC IRQ across cores; increase `net.core.netdev_budget` (e.g., to 600) and `net.core.netdev_cost` (e.g., to 1000) | Reduce softirq CPU bottleneck on single core | Monitor network throughput and latency after changes |

**Microarchitecture Bottleneck Tuning Recommendations**:
| Bottleneck Type | Tuning Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| L1/LLC cache miss high | Enable transparent hugepages (`always`): `echo always > /sys/kernel/mm/transparent_hugepage/enabled`; or use explicit hugepages via `vm.nr_hugepages` | Reduce memory footprint per access | May cause latency spikes in some workloads; monitor |
| Branch misprediction high | Compiler-level: rebuild application with `-fbranch-probabilities` and `-fprofile-use` for profile-guided optimization; OS-level: reduce thread count to improve instruction cache | Reduce branch misprediction | Profile-guided optimization requires training workload; test in staging |
| Frontend stalls high | Reduce number of active processes/threads; tune `kernel.sched_migration_cost_ns` | Reduce instruction fetch stalls | Monitor scheduling latency |
| Backend stalls high | Memory bandwidth issue: increase `vm.zone_reclaim_mode` (for NUMA); tune `kernel.percpu_cpu_distance` | Reduce memory access latency | May increase local vs remote tradeoffs |

**Scheduler Tuning Recommendations**:
| Bottleneck Type | Tuning Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| cs/s > 50000 | Use `perf sched` to identify scheduling latency; reduce `kernel.sched_cfs_bandwidth_slice_us` (to 5ms); consider `kernel.sched_autogroup_enabled=0` to disable autogroup scheduling | Reduce scheduling overhead | Monitor for throttling side effects |
| in/s > 10000 | Check IRQ affinity via `/proc/irq/*/smp_affinity`; enable/configure `irqbalance` service to automatically balance interrupts across cores | Distribute interrupts across cores | Verify IRQ pinning doesn't break latency-sensitive apps |
| Scheduling latency spikes | Use `tuned` service with a latency-performance profile: `tuned-adm profile latency-performance`; or manually set `kernel.sched_migration_cost_ns=500000` to reduce unnecessary process migrations | Reduce scheduling migration overhead | Monitor workload throughput after changes |

## Detailed workload and bottleneck analysis

### Global Resource Bottleneck Identification

| Resource | Key Metrics | Status | Severity |
|----------|-------------|--------|----------|
| CPU | %user=%x, %iowait=%x, loadavg=%x | [Normal/Pressured/Saturated] | [Low/Medium/High/Critical] |
| Memory | used=%x, swap=%x, majflt/s=%x | [Normal/Pressured/Saturated] | [Low/Medium/High/Critical] |
| Disk I/O | %util=%x, await=%xms | [Normal/Pressured/Saturated] | [Low/Medium/High/Critical] |
| Network | rxerr/s=%x, txerr/s=%x, retrans=%x% | [Normal/Pressured/Saturated] | [Low/Medium/High/Critical] |

**Global Bottleneck Summary**: [Identify the primary bottleneck resource with specific evidence. All four resources must be assessed.]

### Top Resource Process Identification

| PID | Name | CPU% | Mem% | IO% | OS Role |
|-----|------|------|------|-----|---------|

### Hotspot Function Analysis

**Top 5 Hot Functions per Process** (from `perf record` / `perf top`):
| PID | Function | CPU% | Category | Evidence Source |
|-----|----------|------|----------|------------------|
| [PID] | [function_name] | [x%] | [user/kernel] | perf record -p [PID] -g -- sleep [DURATION] |
| [PID] | [function_name] | [x%] | [user/kernel] | perf record -p [PID] -g -- sleep [DURATION] |

### Syscall Analysis

**System Call Analysis** (from `strace -c -p [PID]` and `strace -T -p [PID]`):
| PID | Syscall | Count/s | Avg Latency | Pattern | Notes |
|-----|---------|---------|-------------|---------|-------|
| [PID] | [syscall_name] | [n] | [x]ms | [frequent/slow/anomalous] | [specific observation] |
| [PID] | [syscall_name] | [n] | [x]ms | [frequent/slow/anomalous] | [specific observation] |

**Top System Calls by Frequency** (from `strace -c -p [PID]`):
| PID | Syscall | Total Count | % of Total | Status |
|-----|---------|-------------|------------|--------|
| [PID] | [name] | [n] | [x]% | [normal/elevated/critical] |
| [PID] | [name] | [n] | [x]% | [normal/elevated/critical] |

**Long-Running System Calls** (from `strace -T -p [PID]`):
| PID | Syscall | Duration | Frequency | Root Cause Hypothesis |
|-----|---------|----------|----------|----------------------|
| [PID] | [name] | [x]ms | [n] occurrences | [blocking on I/O/lock/network/...] |
| [PID] | [name] | [x]ms | [n] occurrences | [blocking on I/O/lock/network/...] |

### Microarchitecture Bottleneck Analysis

| Component | Metric | Value | Threshold | Status |
|-----------|--------|-------|-----------|--------|
| L1 Cache | L1-dcache-load-misses / L1-dcache-loads | [x]% | >10% | [Normal/Elevated/Critical] |
| LLC Cache | LLC-load-misses / LLC-loads | [x]% | >20% | [Normal/Elevated/Critical] |
| Branch Prediction | branch-misses / branches | [x]% | >5% | [Normal/Elevated/Critical] |
| Frontend Stall | stalled-cycles-frontend / cycles | [x]% | >30% | [Normal/Elevated/Critical] |
| Backend Stall | stalled-cycles-backend / cycles | [x]% | >20% | [Normal/Elevated/Critical] |
| NUMA Locality | remote_loads / local_loads | [x]:1 | >2:1 | [Normal/Imbalanced] |

### Deep-Dive Analysis

#### [Skill Name] Analysis Results (e.g. io-bottleneck)

**Target Process**: [PID/Name]
**Analysis Status**: [COMPLETED / SKIPPED]

**Key Metrics**:
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| [Metric 1] | [Value] | [Threshold] | [Normal/Elevated/Critical] |
| [Metric 2] | [Value] | [Threshold] | [Normal/Elevated/Critical] |
| ... | ... | ... | ... |

**Findings**:
1. [Finding 1 with specific evidence]
2. [Finding 2 with specific evidence]
3. ...

**Evidence**:
```
[Relevant command output from specialized skill/XXX_metrics_analysis.txt]
```

#### [Skill Name] Results (e.g., lock-bottleneck)

[Repeat the same structure for each invoked specialized skill]

---
