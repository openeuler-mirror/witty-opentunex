---
name: top-down-bottleneck
description: Top-down OS-level bottleneck analysis, includes comprehensive system collection, and three-level bottleneck analysis (global, process, microarchitecture). Use when diagnosing OS-level performance issues, identifying high-pressure processes, mapping resource dependencies, or analyzing OS-level resource bottlenecks. This skill does NOT analyze application-layer data (e.g., MySQL query plans, Java heap, Redis commands). Supports iterative refinement until sufficient analysis is achieved.
---

# top-down-bottleneck — Top-Down System Bottleneck Analysis

This skill performs a five-phase analysis:
(1) system environment static information collection (hardware specs, software versions, kernel boot parameters);
(2) global resource bottleneck identification and top resource-consuming process identification;
(3) hotspot function and syscall analysis for top processes;
(4) microarchitecture bottleneck analysis using PMU events;
(5) evidence-based bottleneck analysis with severity mapping.
The skill focuses exclusively on OS-level resource bottlenecks. It does NOT collect, analyze, or provide recommendations for application-layer data (database queries, JVM heap, application logs, etc.).
The skill supports iterative refinement until sufficient analysis is achieved.

---

## Client Connection and Command Execution

[1] if current <agent> is not opentunex-assistant, Load the `remote-execution` skill for standardized SSH connection and command execution.

[2] if current <agent> is opentunex-assistant, Keep the following rule for command execution:  **IMPORTANT** Always output commands which need execution to the **USER**, and ask **USER** for execution results, never execute command automatically by <agent> yourself.

---

## Phase 1: System Environment Static Information Collection

**Objective**: Gather static system environment information — hardware specifications, software versions, and kernel boot parameters. This phase collects **static** facts about the system, not dynamic runtime metrics.

reference:basic-system-info

**Output**: Static system profile: hardware specs (CPU model/core count/NUMA, memory size, disk types, NIC models), software versions (OS, kernel, tools), kernel boot parameters and key sysctl settings.

---

## Phase 2: Main Workload Identification and Bottleneck Analysis

### Step 2.1: Global Resource Bottleneck Identification

Identify bottleneck characteristics across CPU, memory, I/O, and network. Use specific metrics to pinpoint resource pressure.

**quick diagnosis**: run CPU/MEM/IO/NET analysis in background subtask and in parallel.

**CPU Bottleneck Indicators**:
```bash
# CPU utilization per core (skip 100% idle cores, keep header + all + active)
mpstat -P ALL 1 5 | grep 'Average' | awk 'NR==1 || $3=="all" || $NF != "100.00"'

# Load average vs CPU count
cat /proc/loadavg

# Context switches and interrupts (skip since-boot sample, keep 5-second interval)
vmstat 5 2 | awk 'NR<=2{print; next} NR==3{next} {print; exit}'

# Top 30 context switch tasks (Sorted by cswch/s - header + top 30)
{ echo "      UID       PID   cswch/s nvcswch/s  Command"; pidstat -w 1 5 | grep 'Average' | grep -v "UID" | sort -k4 -rn | head -30; }

# Key indicators: %user > 80%, %iowait > 20%, %steal > 10%, %soft > 10%, cs/s > 50000, in/s > 10000
```

**Memory Bottleneck Indicators**:
```bash
# Swap usage and pressure
free -h

# Key swap metrics only
cat /proc/meminfo | grep -E "SwapTotal|SwapFree|SwapCached|CommitLimit|Committed_AS"

# Page faults - Top 20 by majflt/s (Sorted - header + top 20)
{ echo "      UID       PID  minflt/s  majflt/s     VSZ     RSS   %MEM  Command"; pidstat -r 1 5 | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20; }

# Key indicators: majflt/s > 1000 indicates swap thrashing
# Slab memory usage
cat /proc/meminfo | grep -E "Slab|SReclaimable|SUnreclaim"

# Key indicators: Slab > 30% of total memory indicates kernel memory pressure
```

**I/O Bottleneck Indicators**:
```bash
# Disk utilization (skip since-boot, keep 5s interval sample, skip 0% util devices)
iostat -xz 5 2 | awk '/^avg-cpu/{report++; if(report==2) print; next} /^Device/{if(report==2) print; next} /^$/{next} /Linux/{next} report==2 {if(/^[[:space:]]*[0-9]/){print; next} if(/^[a-z]/ && $NF+0>0){print; next}}'

# Queue depth (inflight_IO is instantaneous, not cumulative)
echo "major minor device inflight_IO" && cat /proc/diskstats | awk '{print $1, $2, $3, $12}'

# Top 20 I/O processes by kB_wr/s (Sorted - header + top 20)
{ echo "      UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command"; pidstat -d 1 5 | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20; }

# Key indicators: %util > 90%, await > 20ms, read_kB/s > 100000, write_kB/s > 50000
```

**Network Bottleneck Indicators**:
```bash
# Network interface stats (skip idle interfaces with zero rx/tx kB/s)
sar -n DEV 1 5 | grep 'Average' | awk 'NR==1 || $5+0>0 || $6+0>0'

# Network error stats (skip interfaces with all-zero errors)
sar -n EDEV 1 5 | grep 'Average' | awk 'NR==1{print; next} {for(i=3;i<=NF;i++) if($i+0>0){print; next}}'

# TCP retransmissions and drops (5-second two-snapshot delta, excludes since-boot accumulation)
nstat -az | grep -E "^(TcpOutSegs|TcpRetransSegs|TcpExtTCPLostRetransmit|TcpExtListenOverflows|TcpExtListenDrops)" | awk '{print $1,$2}' > /tmp/nstat_before.txt && sleep 5 && nstat -az | grep -E "^(TcpOutSegs|TcpRetransSegs|TcpExtTCPLostRetransmit|TcpExtListenOverflows|TcpExtListenDrops)" | awk '{print $1,$2}' > /tmp/nstat_after.txt && echo "counter delta rate/s" && join /tmp/nstat_before.txt /tmp/nstat_after.txt | awk -v s=5 '{printf "%-40s %8d %8.1f\n", $1, $3-$2, ($3-$2)/s}'
# Key indicators: retransmission rate > 2%, ListenDrops > 0

# Connection backlog
echo "TIME_WAIT connections:" && ss -tan state time-wait | wc -l

# Top 10 ports by established connections (Sorted - header + top 10)
{ echo "count port"; ss -tn state established | awk '{print $4}' | awk -F: '{print $NF}' | sort | uniq -c | sort -rn | head -10; }

# Key indicators: TIME_WAIT > 5000, established connections > 10000 per port
```

**Output**: Identify which resource(s) are under highest pressure with specific evidence (e.g., "CPU bottleneck: %iowait consistently 25-35% across 5 samples").

---

### Step 2.2: Top Resource Process Identification

From Step 2.1, identify top resource-consuming processes and perform detailed OS-level analysis. **Focus on resource consumption patterns (CPU%, syscalls, context switches, I/O wait) — do NOT analyze application internals (query plans, heap dumps, application logic).**

**Process Identification**:
```bash
# Top 20 CPU processes (Sorted - header preserved by ps)
ps aux --sort=-%cpu | head -20

# Top 20 memory processes (Sorted - header preserved by ps)
ps aux --sort=-%mem | head -20

# Top 20 I/O processes by iotop (requires root, 5-second sampling)
{ echo "    PID  PRIO  USER     DISK READ  DISK WRITE  SWAPIN      IO    COMMAND"; iotop -oP -b -n 5 -d 1 | grep -E "^\s*[0-9]" | head -20; } || true

# Top 20 I/O processes by pidstat (Sorted by kB_wr/s col 5 - header + top 20)
{ echo "      UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command"; pidstat -d 1 5 | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20; }
```

---

## Phase 3: Hotspot Function and Syscall Analysis

### Step 3.1: Hotspot Function Analysis

**Important**: use `remote-execution` skill for remote perf command.

```bash
# Record performance data for target process (30 seconds)
perf record -p <PID> -g -- sleep 30
# Analyze recorded data
perf report
# Real-time sampling
perf top -p <PID>
# Generate flamegraph (requires flamegraph tools, tolerate if not installed)
perf record -F 99 -p <PID> -g -- sleep 30 && perf script | stackcollapse-perf.pl | flamegraph.pl > flamegraph.svg || true
```

### Step 3.2: Syscall Analysis

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

**Output**: For each top process, record: PID, name, top 5 hot functions, total CPU%, main system calls, identified bottlenecks with evidence. **Both Hot Function Analysis and System Call Analysis results MUST be included in the Phase 3 summary — they are not optional.**

---

## Phase 4: Microarchitecture Bottleneck Analysis

Use PMU (Performance Monitoring Unit) events to identify cache, branch, and pipeline bottlenecks:

**CPU Cache Analysis**:
```bash
# Cache miss rates (portable across x86/ARM)
perf stat -e cache-references,cache-misses,L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses -p <PID> -- sleep 30
# Key indicators: L1 miss rate > 10%, LLC miss rate > 20%
# TLB miss statistics (may not be available on all platforms, tolerate errors)
perf stat -e dTLB-load-misses,iTLB-load-misses -p <PID> -- sleep 30 || true
```

**Branch Prediction and Pipeline Analysis**:
```bash
# Branch misprediction rate (branches may not be supported on all platforms)
perf stat -e branches,branch-misses -p <PID> -- sleep 30 || true
# Pipeline stall analysis
perf stat -e stalled-cycles-frontend,stalled-cycles-backend,cycles,instructions -p <PID> -- sleep 30
# Key indicators: branch miss rate > 5%, frontend stalls > 30% cycles, backend stalls > 20% cycles
```

**Top-Down Microarchitecture Analysis**:
```bash
# Portable pipeline metrics (cycles, instructions available everywhere)
perf stat -e cycles,instructions -p <PID> -- sleep 30
# Intel-only uops metrics (tolerate error on non-Intel platforms)
perf stat -e uops_executed,uops_retired -p <PID> -- sleep 30 || true
# Intel pmu-tools Top-Down analysis (Intel-only, tolerate if not installed)
toplev -p <PID> --sleep 30 || true
```

**Memory Bandwidth and NUMA**:
```bash
# NUMA-related metrics (may not exist on non-NUMA platforms, tolerate errors)
perf stat -e node_loads,node_stores,local_loads,remote_loads -p <PID> -- sleep 30 || true
# Key indicators: remote/local > 2:1 indicates NUMA imbalance
```

**Output**: Microarchitecture bottleneck report with:
- L1/LLC cache miss rates
- Branch misprediction rate
- Frontend/backend stall percentages
- NUMA locality ratios
- Identified microarchitecture bottlenecks (e.g., "L1 cache miss rate 15% - high memory access density at OS level")

---

## Phase 5: Evidence-Based Bottleneck Analysis

**Requirement**: Every bottleneck claim MUST be backed by specific evidence from Phases 1-4. No vague or speculative statements.

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
- [ ] Phase 1 system environment static info (hardware specs, software versions, kernel boot parameters)
- [ ] Phase 2.1 global bottleneck identification (mpstat, iostat, pidstat, sar)
- [ ] Phase 2.2 top process identification (ps, iotop, pidstat)
- [ ] Phase 3 hotspot function and syscall analysis (perf, strace)
- [ ] Phase 4 microarchitecture PMU events (perf stat)

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
- **Important — Complete All Phases Before Concluding**: Do NOT stop analysis early once an initial bottleneck is found. All phases (Phase 1 through Phase 5) must be fully executed and reported before concluding. Early termination prevents discovering secondary bottlenecks that may be equally or more impactful. The final report is only complete when every section of the Output Template has been filled with actual data.
- **Stop when**: All phases are fully executed, all evidence collected, all bottleneck categories mapped, and the user confirms the report is complete.

---

## Output Template

reference:output-template

---

## Operational Notes

- All analysis must be specific and evidence-based; maintain rigor and professionalism.
- When using perf for microarchitecture analysis, ensure appropriate sampling intervals (15-30 seconds) to avoid skewing metrics.
- **Scope Constraint — OS Level Only**: This skill analyzes ONLY OS-level information and bottlenecks. Do NOT collect, interpret, or provide recommendations based on application-layer data (e.g., MySQL query plans, PostgreSQL EXPLAIN output, Java heap/Garbage Collection logs, Redis command traces, application configuration files, application business logic). If application-layer issues are detected (e.g., a process spending excessive time in application code), describe it at the OS level (e.g., "process spending 80% CPU time in user space") without diving into application internals.
