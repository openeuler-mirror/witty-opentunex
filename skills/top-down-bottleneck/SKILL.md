---
name: top-down-bottleneck
description: Top-down OS-level bottleneck analysis, includes comprehensive system collection, and three-level bottleneck analysis (global, process, microarchitecture). Use when diagnosing OS-level performance issues, identifying high-pressure processes, mapping resource dependencies, or analyzing OS-level resource bottlenecks. This skill does NOT analyze application-layer data (e.g., MySQL query plans, Java heap, Redis commands). Supports iterative refinement until sufficient analysis is achieved.
---

# top-down-bottleneck — Top-Down System Bottleneck Analysis

This skill performs a two-phase analysis:
(1) fast, background system-wide information collection;
(2) rigorous main-workload identification with evidence-based bottleneck analysis at multiple levels (global, process, microarchitecture).
The skill focuses exclusively on OS-level resource bottlenecks. It does NOT collect, analyze, or provide recommendations for application-layer data (database queries, JVM heap, application logs, etc.).
The skill supports iterative refinement until sufficient analysis is achieved.

---

## Client Connection and Command Execution

[1] if current <agent> is not opentunex-assistant, Load the `remote-execution` skill for standardized SSH connection and command execution.

[2] if current <agent> is opentunex-assistant, Keep the following rule for command execution:  **IMPORTANT** Always output commands which need execution to the **USER**, and ask **USER** for execution results, never execute command automatically by <agent> yourself.

---

## Phase 1: System-Wide Information Collection

**Objective**: Gather comprehensive raw system data.

```
task(subagent_type="sys-sniffer", load_skills=["basic-system-info"], description="Gather basic system info", prompt="Collect CPU, memory, disk, network, kernel, hardware.")
```

**Output**: Raw data. Scope: CPU, memory, disk, network, kernel.

---

## Phase 2: Main Workload Identification and Bottleneck Analysis

### Step 2.1: Global Resource Bottleneck Identification

Identify bottleneck characteristics across CPU, memory, I/O, and network. Use specific metrics to pinpoint resource pressure.

**quick diagnosis**: run CPU/MEM/IO/NET analysis in background subtask and in parallel.

**CPU Bottleneck Indicators**:
```bash
# CPU utilization breakdown
mpstat -P ALL 1 5 | grep 'Average'
# Key indicators: %user > 80%, %iowait > 20%, %steal > 10%, %soft > 10%
# Load average vs CPU count
cat /proc/loadavg
# Context switches and interrupts
vmstat 1 5 | awk 'NR>1 {print $12, $13}'
# top 50 context switch tasks
pidstat -w 1 5 | awk '/Average/ && !/UID/ && NF>=6 {total=$4+$5; print total, $0}' | sort -k1 -rn | head -50 | cut -d' ' -f2-
# Key indicators: cs/s > 50000, in/s > 10000 indicate scheduling pressure
```

**Memory Bottleneck Indicators**:
```bash
# Swap usage and pressure
free -h
cat /proc/meminfo | grep -E "SwapTotal|SwapFree|SwapCached|CommitLimit|Committed_AS"
# Page faults
pidstat -r 1 5 | grep 'Average'
# Key indicators: majflt/s > 1000 indicates swap thrashing
# Slab memory usage
cat /proc/meminfo | grep -E "Slab|SReclaimable|SUnreclaim"
# Key indicators: Slab > 30% of total memory indicates kernel memory pressure
```

**I/O Bottleneck Indicators**:
```bash
# Disk utilization and wait time
iostat -xz 1 5
# Key indicators: %util > 90%, await > 20ms, svctm > 10ms
# Queue depth
cat /proc/diskstats | awk '{print $1, $12}'
# IO pressure per process
pidstat -d 1 5
# Key indicators: read_kB/s > 100000, write_kB/s > 50000, %util > 80%
```

**Network Bottleneck Indicators**:
```bash
# Network interface stats
sar -n DEV 1 5 | grep 'Average'
sar -n EDEV 1 5 | grep 'Average'
# Key indicators: rxerr/s > 10, txerr/s > 10, collisions/s > 5
# TCP retransmissions and drops
nstat -az | grep -E "TcpOutSegs|TcpRetransSegs|TcpExtTCPLostRetransmit|TcpExtListenOverflows|TcpExtListenDrops"
# Key indicators: high retransmission rate, listen drops indicate connection pressure
# Connection backlog
ss -tan state time-wait | wc -l
ss -tn state established | awk '{print $4}' | awk -F: '{print $NF}' | sort | uniq -c | sort -rn | head -10
# Key indicators: TIME_WAIT > 5000, established connections > 10000 per port
```

**Output**: Identify which resource(s) are under highest pressure with specific evidence (e.g., "CPU bottleneck: %iowait consistently 25-35% across 5 samples").

---

### Step 2.2: Top Resource Process Identification

From Step 2.1, identify top resource-consuming processes and perform detailed OS-level analysis. **Focus on resource consumption patterns (CPU%, syscalls, context switches, I/O wait) — do NOT analyze application internals (query plans, heap dumps, application logic).**

**Process Identification**:
```bash
# Top CPU processes
ps aux --sort=-%cpu | head -20
# Top memory processes
ps aux --sort=-%mem | head -20
# Top I/O processes
iotop -oP -b -n 5 -d 1
pidstat -d 1 5 | awk 'NR<=3 || $6>1000 || $7>1000'
```

### Step 2.3: Hotspot Function Analysis and syscall analysis

**Important**: use `remote-execution` skill for remote perf command.

```bash
# Record performance data for target process (30 seconds)
perf record -p <PID> -g -- sleep 30
# Analyze recorded data
perf report
# Real-time sampling
perf top -p <PID>
# Generate flamegraph (if flamegraph tools available)
perf record -F 99 -p <PID> -g -- sleep 30
perf script | stackcollapse-perf.pl | flamegraph.pl > flamegraph.svg
```

### Step 2.4: Hotspot Function Analysis and syscall analysis

**Important**: use `remote-execution` skill for remote perf command.

**syscall analysis**:
```bash
# Trace system calls
strace -p <PID> -c -f -o strace.out
# Trace with timestamps
strace -p <PID> -T -tt -f -o strace_timestamps.out
# System call latency histogram
perf trace -p <PID>
```

**Key Metrics to Analyze**:
- Top hotspot functions by CPU time (perf report)
- System call patterns and latency (strace output)
- Call stack depth and recursive patterns
- User-space vs kernel-space time distribution

**Anomaly Detection**:
- Functions with unexpectedly high CPU time compared to historical baseline
- Long-running system calls (block > 100ms)
- High context switch rate (cs/s > 50000 for single process)
- Excessive system call frequency (> 10000 syscalls/sec)

**Output**: For each top process, record: PID, name, top 5 hot functions, total CPU%, main system calls, identified bottlenecks with evidence. **Both Hot Function Analysis and System Call Analysis results MUST be included in the Phase 2 summary — they are not optional.**

---

### Step 2.3: Microarchitecture Bottleneck Analysis

Use PMU (Performance Monitoring Unit) events to identify cache, branch, and pipeline bottlenecks:

**CPU Cache Analysis**:
```bash
# Collect cache miss rates
perf stat -e cache-references,cache-misses,L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses -p <PID> -- sleep 30
# Key indicators: L1 miss rate > 10%, LLC miss rate > 20%
# Detailed cache statistics
perf stat -e cache-misses,cache-references,dTLB-load-misses,iTLB-load-misses -p <PID> -- sleep 30
```

**Branch Prediction Analysis**:
```bash
# Branch misprediction rate
perf stat -e branches,branch-misses -p <PID> -- sleep 30
# Key indicators: branch miss rate > 5% indicates poor branch prediction
# Pipeline stall analysis
perf stat -e stalled-cycles-frontend,stalled-cycles-backend,cycles,instructions -p <PID> -- sleep 30
# Key indicators: frontend stalls > 30% cycles, backend stalls > 20% cycles
```

**Top-Down Microarchitecture Analysis**:
```bash
# Intel Top-Down Microarchitecture Analysis
perf stat -e cycles,instructions,uops_executed,uops_retired -p <PID> -- sleep 30
# Retiring metric (good)
# Bad speculation metric
# Frontend bound metric
# Backend bound metric
# Use pmu-tools if available
toplev -p <PID> --sleep 30
```

**Memory Bandwidth and Latency**:
```bash
# Memory bandwidth utilization
perf stat -e mem_loads,mem_stores,mem_load_retired.l3_miss -p <PID> -- sleep 30
# NUMA-related metrics
perf stat -e node_loads,node_stores,local_loads,remote_loads -p <PID> -- sleep 30
# Key indicators: remote/local > 2:1 indicates NUMA imbalance
```

**Output**: Microarchitecture bottleneck report with:
- L1/LLC cache miss rates
- Branch misprediction rate
- Frontend/backend stall percentages
- NUMA locality ratios
- Identified microarchitecture bottlenecks (e.g., "L1 cache miss rate 15% - high memory access density at OS level")

---

### Step 2.4: Evidence-Based Bottleneck Analysis

**Requirement**: Every bottleneck claim MUST be backed by specific evidence from Steps 2.1-2.3. No vague or speculative statements.

**Bottleneck categories and evidence mapping**:

| Category | Key Evidence Metrics | Thresholds | Collection Method |
|----------|---------------------|------------|-------------------|
| CPU Compute | %user, load average, per-CPU utilization | %user > 80%, loadavg > CPU_count*2 | mpstat, pidstat -u, top |
| CPU I/O Wait | %iowait, vmstat b (blocked processes) | %iowait > 20%, blocked > 10 | mpstat, vmstat |
| CPU Context Switch | cs/s (context switches), in/s (interrupts) | cs/s > 50000, in/s > 10000 | vmstat, pidstat -w |
| Memory Pressure | Swap usage, page faults, Slab | SwapUsed > 50%, majflt/s > 1000 | free, pidstat -r, meminfo |
| Memory Fragmentation | Slab, HugePages, Committed_AS | Slab > 30% total, frag > 50% | cat /proc/meminfo |
| Disk I/O | %util, await, queue depth | %util > 90%, await > 20ms | iostat -xz |
| Disk I/O per process | read_kB/s, write_kB/s | > 100000 r/s, > 50000 w/s | pidstat -d |
| Network Interface | rxerr/s, txerr/s, collisions | rxerr/s > 10, txerr/s > 10 | sar -n EDEV |
| Network TCP | retransmission rate, drops | Retrans > 2%, ListenDrops > 0 | nstat, ss |
| Network Connections | TIME_WAIT, established per port | TIME_WAIT > 5000, conn/port > 10000 | ss |
| L1 Cache | L1-dcache-load-misses / L1-dcache-loads | > 10% | perf stat |
| LLC Cache | LLC-load-misses / LLC-loads | > 20% | perf stat |
| Branch Prediction | branch-misses / branches | > 5% | perf stat |
| Frontend Stall | stalled-cycles-frontend / cycles | > 30% | perf stat |
| Backend Stall | stalled-cycles-backend / cycles | > 20% | perf stat |
| NUMA Imbalance | remote_loads / local_loads | > 2:1 | perf stat |

**Bottleneck prioritization**:
1. **Critical**: Resource saturation (CPU 100%, Disk 100%, Swap in use)
2. **High**: Excessive latency (I/O await > 100ms, network retrans > 10%)
3. **Medium**: Performance degradation (cache miss > 30%, branch miss > 10%)
4. **Low**: Suboptimal but not blocking (context switches elevated but acceptable)

**Evidence collection checklist**:
- [ ] Phase 1 system metrics (mpstat, iostat, pidstat)
- [ ] Phase 2.1 global bottleneck identification
- [ ] Phase 2.2 top process hot functions and call chains
- [ ] Phase 2.3 microarchitecture PMU events

**Output format for each bottleneck**:
```
Bottleneck: [Resource/Component]
Severity: [Critical/High/Medium/Low]
Evidence:
  - Metric 1: value (threshold, severity)
  - Metric 2: value (threshold, severity)
  - ...
Root cause: [Specific cause based on analysis]
Affected processes: [PID, name, role]
Impact: [Description of user-visible impact]
```

---

## Iteration Loop

The skill allows repeated cycles to narrow the analysis scope:

- **When to iterate**: Bottleneck(s) not yet identified with sufficient evidence, or next steps are unclear.
- **How to iterate**: Each cycle narrows focus (e.g., specific container, port, device). Re-run Phase 1 if system state may have changed; otherwise reuse existing data and deepen analysis.
- **Important — Complete All Phases Before Concluding**: Do NOT stop analysis early once an initial bottleneck is found. All phases (Phase 1 + all Step 2.x subsections) must be fully executed and reported before concluding. Early termination prevents discovering secondary bottlenecks that may be equally or more impactful. The final report is only complete when every section of the Output Template has been filled with actual data.
- **Stop when**: All phases are fully executed, all evidence collected, all bottleneck categories mapped, and the user confirms the report is complete.

---

## Output Template

```markdown
## Phase 0: Benchmark Status
- Benchmark Running: [Yes/No — if Yes, record PID and duration]
- Workload During Collection: [Existing production workload / Synthetic benchmark]

## Phase 1: System Collection Summary

**Collected Raw Data Summary**:
- CPU: [avg %user, %sys, %iowait, %idle across all cores; load average; context switch rate]
- Memory: [total, used, free, available, swap used; major/minor page faults]
- Disk I/O: [device(s) with highest %util, avg await, read/write KB/s per device]
- Network: [interface(s) with highest rx/tx KB/s, error/drop rates, TCP retrans rate]
- Kernel: [uptime, slab info, file descriptors, process count]
- Hardware: [CPU model, core count, NUMA nodes, memory size]

## Phase 2: Main Workload and Bottleneck Analysis

### 2.1 Global Resource Bottleneck Identification

| Resource | Key Metrics | Status | Severity |
|----------|-------------|--------|----------|
| CPU | %user=%x, %iowait=%x, loadavg=%x | [Normal/Pressured/Saturated] | [Low/Medium/High/Critical] |
| Memory | used=%x, swap=%x, majflt/s=%x | [Normal/Pressured/Saturated] | [Low/Medium/High/Critical] |
| Disk I/O | %util=%x, await=%xms | [Normal/Pressured/Saturated] | [Low/Medium/High/Critical] |
| Network | rxerr/s=%x, txerr/s=%x, retrans=%x% | [Normal/Pressured/Saturated] | [Low/Medium/High/Critical] |

**Global Bottleneck Summary**: [Identify the primary bottleneck resource with specific evidence. All four resources must be assessed.]

### 2.2 Top Resource Process Identification

| PID | Name | CPU% | Mem% | IO% | OS Role |
|-----|------|------|------|-----|---------|

**Top 5 Hot Functions per Process** (from `perf record` / `perf top`):
| PID | Function | CPU% | Category | Evidence Source |
|-----|----------|------|----------|------------------|
| [PID] | [function_name] | [x%] | [user/kernel] | perf record -p [PID] -g -- sleep 60 |
| [PID] | [function_name] | [x%] | [user/kernel] | perf record -p [PID] -g -- sleep 60 |
| [PID] | [function_name] | [x%] | [user/kernel] | perf record -p [PID] -g -- sleep 60 |
| [PID] | [function_name] | [x%] | [user/kernel] | perf record -p [PID] -g -- sleep 60 |
| [PID] | [function_name] | [x%] | [user/kernel] | perf record -p [PID] -g -- sleep 60 |

**System Call Analysis** (from `strace -c -p [PID]` and `strace -T -p [PID]`):
| PID | Syscall | Count/s | Avg Latency | Pattern | Notes |
|-----|---------|---------|-------------|---------|-------|
| [PID] | [syscall_name] | [n] | [x]ms | [frequent/slow/anomalous] | [specific observation] |
| [PID] | [syscall_name] | [n] | [x]ms | [frequent/slow/anomalous] | [specific observation] |
| [PID] | [syscall_name] | [n] | [x]ms | [frequent/slow/anomalous] | [specific observation] |
| [PID] | [syscall_name] | [n] | [x]ms | [frequent/slow/anomalous] | [specific observation] |
| [PID] | [syscall_name] | [n] | [x]ms | [frequent/slow/anomalous] | [specific observation] |

**Top System Calls by Frequency** (from `strace -c -p [PID]`):
| PID | Syscall | Total Count | % of Total | Status |
|-----|---------|-------------|------------|--------|
| [PID] | [name] | [n] | [x]% | [normal/elevated/critical] |
| [PID] | [name] | [n] | [x]% | [normal/elevated/critical] |
| [PID] | [name] | [n] | [x]% | [normal/elevated/critical] |

**Long-Running System Calls** (from `strace -T -p [PID]`):
| PID | Syscall | Duration | Frequency | Root Cause Hypothesis |
|-----|---------|----------|----------|----------------------|
| [PID] | [name] | [x]ms | [n] occurrences | [blocking on I/O/lock/network/...] |
| [PID] | [name] | [x]ms | [n] occurrences | [blocking on I/O/lock/network/...] |

### 2.3 Microarchitecture Bottleneck Analysis

| Component | Metric | Value | Threshold | Status |
|-----------|--------|-------|-----------|--------|
| L1 Cache | L1-dcache-load-misses / L1-dcache-loads | [x]% | >10% | [Normal/Elevated/Critical] |
| LLC Cache | LLC-load-misses / LLC-loads | [x]% | >20% | [Normal/Elevated/Critical] |
| Branch Prediction | branch-misses / branches | [x]% | >5% | [Normal/Elevated/Critical] |
| Frontend Stall | stalled-cycles-frontend / cycles | [x]% | >30% | [Normal/Elevated/Critical] |
| Backend Stall | stalled-cycles-backend / cycles | [x]% | >20% | [Normal/Elevated/Critical] |
| NUMA Locality | remote_loads / local_loads | [x]:1 | >2:1 | [Normal/Imbalanced] |

### 2.4 Topology Analysis

**Process Dependency Topology**:
- [List all key processes and their relationships: parent → child, I/O wait chains]
- [Identify which processes are causing cascading resource pressure]

**Resource Dependency Graph**:
- [Map resource → process → OS component: e.g., Disk sda → mysqld → jbd2/dm-0-8]

### 2.5 Evidence-Based Bottleneck Mapping

| PID | TID | Name | OS Role | Main Bottleneck | Severity | Evidence |
|-----|-----|------|---------|-----------------|----------|----------|
| [PID] | [TID] | [name] | [kernel/daemon/user] | [bottleneck type] | [Critical/High/Medium/Low] | [metric=value, threshold=..., status=...] |
| [PID] | [TID] | [name] | [kernel/daemon/user] | [bottleneck type] | [Critical/High/Medium/Low] | [metric=value, threshold=..., status=...] |
| [PID] | [TID] | [name] | [kernel/daemon/user] | [bottleneck type] | [Critical/High/Medium/Low] | [metric=value, threshold=..., status=...] |

### 2.6 Final Bottleneck Summary

**Primary Bottleneck**: [Resource/Component]
- Severity: [Critical/High/Medium/Low]
- Evidence: [All supporting metrics from Steps 2.1-2.5]
- Affected Processes: [All PIDs affected]

**Secondary Bottleneck(s)**: [List all other identified bottlenecks in order of severity]

**Bottleneck Chain**: [If multiple bottlenecks are causally linked, describe the chain: e.g., mysqld → high write I/O → jbd2 → disk saturation → CPU iowait]

**OS-Level Root Cause Hypothesis**: [Single-sentence hypothesis of the OS-level root cause]

### 2.7 OS-Level Preliminary Optimization Recommendations

Based on the bottleneck analysis above, the following OS-level kernel/subsystem tuning actions are recommended. **Only OS-level tunables (`sysctl`, `/proc`, `/sys`) are in scope — do NOT include application-layer configuration changes (e.g., database parameters, JVM flags, application config files).** Apply only after confirming the current kernel parameters and that changes are safe for the running workload.

**CPU Bottleneck Recommendations**:
| Bottleneck Type | OS-Level Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| High %user (>80%) | Check `nice`/`renice` priority; consider CPU affinity pinning via `taskset`; if latency-sensitive workload, enable tickless kernel (`nohz_full`) via `nohz_full=<cpu-list>` kernel cmdline | Reduce scheduling contention | Verify no other critical processes are affected by affinity changes |
| High %iowait (>20%) | See Disk I/O section below; also check `vm.dirty_ratio` and `vm.dirty_background_ratio` | Reduce CPU blocked on I/O | Monitor disk latency after changes |
| High %soft (>10%) | Review kernel softirq configuration; check `net.core.netdev_budget`; enable/configure `irqbalance` service | Reduce softirq CPU overhead | Monitor network throughput after changes |
| High %steal (>10%) | (VM) Not directly tunable inside guest; consider VM host-level CPU quota or CPU pinning adjustment | N/A | N/A |
| High context switches (>50k/s) | Identify syscall-heavy processes via `strace`; reduce system call frequency at OS level (e.g., check unnecessary `fsync`, `sync_file_range` calls); use compiler-level optimization (`-fno-stack-protector` if stack checks overhead is high) to reduce per-call overhead | Lower scheduler pressure | Monitor scheduling latency after changes |
| CPU-bound workload with high IPC | Compiler-level: rebuild with `-O3 -march=native -mtune=native` for CPU-specific optimizations; check `-fprofile-use` for PGO | Improve instruction-level parallelism and reduce instruction overhead | PGO requires representative training workload; test in staging |

**Memory Bottleneck Recommendations**:
| Bottleneck Type | OS-Level Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| Swap used > 50% | Reduce `vm.swappiness` (e.g., to 10 or lower for SSD-backed swap); increase `vm.min_free_kbytes` to retain more free memory | Reduce page-in/page-out thrashing | Lower swappiness may cause OOM in some configs |
| majflt/s > 1000 | Increase `vm.min_free_kbytes`; check `vm.vfs_cache_pressure` | Reduce major page faults | Monitor memory pressure after changes |
| Slab > 30% total | Check `/proc/slabinfo` for high-use slabs; tune `vm.memory_balloon` (if enabled) | Free kernel memory for user processes | Monitor kernel stability |
| NUMA imbalance (remote/local > 2:1) | Enable NUMA balancing via `numactl --interleave=all` or tune `numa_balancing` via `/proc/sys/kernel/numa_balancing` | Reduce remote memory access latency | Not all workloads benefit from interleave |
| Excessive malloc/free fragmentation | Replace system malloc with jemalloc via `LD_PRELOAD=/usr/lib64/libjemalloc.so.2` or via `/etc/ld.so.preload`; alternatively configure `MALLOC_ARENA_MAX` env var | Reduce memory allocator fragmentation and improve multi-threaded memory performance | Verify jemalloc is compatible with the application; test in staging |

**Disk I/O Bottleneck Recommendations**:
| Bottleneck Type | OS-Level Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| %util > 90%, await > 20ms | Change I/O scheduler to `mq-deadline` or `none` (for SSD/NVMe): `echo mq-deadline > /sys/block/<device>/queue/scheduler` | Reduce I/O queue latency | Test in staging first |
| High write latency | Reduce `vm.dirty_background_ratio` (e.g., to 5) and `vm.dirty_ratio` (e.g., to 20); enable `vm.dirty_writeback_centisecs=500` | Batch disk writes more aggressively | May increase RAM usage |
| High read latency | Increase `vm.pagecache` or use `readahead` tuning; check `blkdiscard` for SSD TRIM | Improve read-ahead effectiveness | Verify filesystem supports readahead changes |
| Queue depth saturation | Increase `nr_requests` via `/sys/block/<device>/queue/nr_requests` (e.g., to 1024) | Allow more in-flight I/O | May increase latency for individual ops |
| High disk I/O across multiple devices | Enable and tune `irqbalance` service to distribute storage interrupts across CPU cores | Reduce interrupt contention on single core | Verify storage device supports multi-queue IRQ routing |
| Transparent hugepage fragmentation | Enable transparent hugepages (`always`): `echo always > /sys/kernel/mm/transparent_hugepage/enabled`; tune `khugepaged` via `/sys/kernel/mm/transparent_hugepage/khugepaged/` | Reduce memory fragmentation for large workloads | May cause latency spikes in some applications; monitor |
| I/O priority contention | Use `ionice` to set CFQ/bfq scheduler for latency-sensitive processes; combine with `nice` for CPU/IO priority separation | Isolate latency-sensitive I/O from bulk I/O | Verify CFQ/bfq is available on the system |

**Network Bottleneck Recommendations**:
| Bottleneck Type | OS-Level Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| High retransmission (>2%) | Tune `tcp_rmem`/`tcp_wmem`; enable `tcp_tw_reuse=1`; increase `tcp_max_syn_backlog` | Reduce retransmissions and TIME_WAIT buildup | Monitor connection stability |
| ListenOverflows/Drops > 0 | Increase `net.core.somaxconn` and `net.ipv4.tcp_max_syn_backlog` | Accept more incoming connections | Verify socket backlog capacity at OS level is sufficient |
| High TIME_WAIT (>5000) | Enable `tcp_tw_reuse=1`; reduce `net.netfilter.nf_conntrack_tcp_timeout_time_wait` | Free socket buffer memory | Not safe if NAT/conntrack is in use |
| High socket memory | Increase `net.core.rmem_max`/`wmem_max`; tune `net.ipv4.tcp_rmem`/`tcp_wmem` | Prevent socket buffer exhaustion | Monitor network throughput |
| High softirq CPU from network | Enable/configure `irqbalance` service to distribute NIC IRQ across cores; increase `net.core.netdev_budget` (e.g., to 600) and `net.core.netdev_cost` (e.g., to 1000) | Reduce softirq CPU bottleneck on single core | Monitor network throughput and latency after changes |

**Microarchitecture Bottleneck Recommendations**:
| Bottleneck Type | OS-Level Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| L1/LLC cache miss high | Enable transparent hugepages (`always`): `echo always > /sys/kernel/mm/transparent_hugepage/enabled`; or use explicit hugepages via `vm.nr_hugepages` | Reduce memory footprint per access | May cause latency spikes in some workloads; monitor |
| Branch misprediction high | Compiler-level: rebuild application with `-fbranch-probabilities` and `-fprofile-use` for profile-guided optimization; OS-level: reduce thread count to improve instruction cache | Reduce branch misprediction | Profile-guided optimization requires training workload; test in staging |
| Frontend stalls high | Reduce number of active processes/threads; tune `kernel.sched_migration_cost_ns` | Reduce instruction fetch stalls | Monitor scheduling latency |
| Backend stalls high | Memory bandwidth issue: increase `vm.zone_reclaim_mode` (for NUMA); tune `kernel.percpu_cpu_distance` | Reduce memory access latency | May increase local vs remote tradeoffs |

**Context Switch / Scheduler Recommendations**:
| Bottleneck Type | OS-Level Recommendation | Expected Effect | Safety Note |
|-----------------|------------------------|-----------------|-------------|
| cs/s > 50000 | Use `perf sched` to identify scheduling latency; reduce `kernel.sched_cfs_bandwidth_slice_us` (to 5ms); consider `kernel.sched_autogroup_enabled=0` to disable autogroup scheduling | Reduce scheduling overhead | Monitor for throttling side effects |
| in/s > 10000 | Check IRQ affinity via `/proc/irq/*/smp_affinity`; enable/configure `irqbalance` service to automatically balance interrupts across cores | Distribute interrupts across cores | Verify IRQ pinning doesn't break latency-sensitive apps |
| Scheduling latency spikes | Use `tuned` service with a latency-performance profile: `tuned-adm profile latency-performance`; or manually set `kernel.sched_migration_cost_ns=500000` to reduce unnecessary process migrations | Reduce scheduling migration overhead | Monitor workload throughput after changes |

**Priority Order of OS-Level Actions**:
1. **Highest priority**: Actions addressing Critical-severity bottlenecks
2. **Second priority**: Actions addressing bottleneck chains (root cause first)
3. **Third priority**: Actions addressing High-severity bottlenecks
4. **Low priority**: Actions for Medium/Low improvements

**Scope of Allowed OS-Level Recommendations**:
OS-level optimizations include, but are not limited to:
- **Kernel/subsystem tunables**: `sysctl` variables (e.g., `vm.swappiness`), `/proc` paths, `/sys` paths
- **Compiler-level optimizations**: compiler flags that affect binary performance (e.g., `-O3`, `-march=native`, `-fbranch-probabilities`) — these optimize how the application binary runs without changing application source code
- **OS-level library replacements**: swapping OS-level libraries that affect process behavior (e.g., replacing glibc `malloc` with `jemalloc` via `LD_PRELOAD` or system-wide linker config — this changes memory allocator behavior at the OS level, not the application level)
- **OS basic service tuning**: tuning OS-level services that affect system performance (e.g., `irqbalance` service, `ksmd`/`khugepaged` for transparent hugepages, `tuned`/`sysctl` for profile-based tuning)
- **OS resource management**: cgroups, namespaces, CPU affinity, process priority (`nice`/`renice`), NUMA policy (`numactl`)

**NOT Allowed — Application-Layer Changes**:
- Application source code or logic changes
- Application configuration files or parameters (e.g., MySQL `innodb_buffer_pool_size`, PostgreSQL `shared_buffers`, JVM `-Xmx`, Redis `maxmemory`, application business logic)

**Constraints on Recommendations**:
- Every recommendation must reference a specific **OS-level tunable**: a `sysctl` variable, a `/proc` or `/sys` path, a compiler/linker flag, an OS service or library replacement, or an OS resource management mechanism. If no OS-level mechanism exists, state "No direct OS-level tunable — investigate OS-level workarounds (e.g., process priority, IRQ affinity)"
- For each recommendation, include a **safety note** — OS-level changes can have unintended side effects
- Always recommend **monitoring the effect** after applying a change
- If unsure of a safe value range, recommend testing in a non-production environment first
- If a bottleneck appears to require application-level fixes, only describe it in OS terms (e.g., "process spending 95% CPU in user space issuing 20k write syscalls/s") and do not suggest application configuration changes

---

**Report Completeness Checklist**:
- [x] Phase 0: Benchmark status recorded (or existing workload confirmed)
- [x] Phase 1: All system metrics collected and summarized (CPU, Memory, Disk, Network, Kernel)
- [x] Step 2.1: All four global resources assessed with severity ratings
- [x] Step 2.2: Hot function analysis completed for top processes
- [x] Step 2.2: System call analysis completed for top processes
- [x] Step 2.2: Frequency and latency analysis completed for top processes
- [x] Step 2.3: All microarchitecture metrics collected and assessed
- [x] Step 2.4: Process and resource topology mapped
- [x] Step 2.5: All bottlenecks mapped with evidence and severity
- [x] Step 2.6: Final bottleneck summary written — no bottleneck left unmapped
- [x] Step 2.7: OS-level preliminary optimization recommendations provided for all identified bottlenecks

**Analysis is complete only when ALL items above are checked.**
```

---

## Operational Notes

- All analysis must be specific and evidence-based; maintain rigor and professionalism.
- When using perf for microarchitecture analysis, ensure appropriate sampling intervals (15-30 seconds) to avoid skewing metrics.
- **Scope Constraint — OS Level Only**: This skill analyzes ONLY OS-level information and bottlenecks. Do NOT collect, interpret, or provide recommendations based on application-layer data (e.g., MySQL query plans, PostgreSQL EXPLAIN output, Java heap/Garbage Collection logs, Redis command traces, application configuration files, application business logic). If application-layer issues are detected (e.g., a process spending excessive time in application code), describe it at the OS level (e.g., "process spending 80% CPU time in user space") without diving into application internals.
