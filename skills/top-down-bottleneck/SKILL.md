---
name: top-down-bottleneck
description: Top-down OS-level bottleneck analysis, includes comprehensive system collection(read from user-given data collection files first), and three-level bottleneck analysis (global, process, microarchitecture). Use when diagnosing OS-level performance issues, identifying high-pressure processes, mapping resource dependencies, or analyzing OS-level resource bottlenecks. This skill does NOT analyze application-layer data (e.g., MySQL query plans, Java heap, Redis commands). Supports iterative refinement until sufficient analysis is achieved.
---

# top-down-bottleneck — Top-Down System Bottleneck Analysis

This skill performs a five-phase analysis:
(1) system environment static information analysis;
(2) global resource bottleneck identification and top resource-consuming process identification;
(3) hotspot function and syscall analysis for top processes;
(4) microarchitecture bottleneck analysis using PMU events;
(5) evidence-based bottleneck analysis with severity mapping.
The skill focuses exclusively on OS-level resource bottlenecks. It does NOT collect, analyze, or provide recommendations for application-layer data (database queries, JVM heap, application logs, etc.).
The skill supports iterative refinement until sufficient analysis is achieved.
First try to read from user-given data collection files, if data is not enough, provides script to user to conduct supplementary collection.

---

## Analysis Command Execution

[1] only if **USER** has specified that remote command execution are allowed, Load the `remote-execution` skill for standardized SSH connection and command execution.

[2] otherwise, Keep the following rule for command execution: Always read from user-given data collection files to analyze, command execution results should be saved in these files, if some extra commands are needed for analysis, output command execution script to **USER**, and ask **USER** to provide execution results, never execute command automatically.

---

## Heavyweight Command Constraints (CRITICAL)

**Heavyweight commands** (`perf record`, `perf top`, `perf stat`, `strace`) attach to the target process and alter its runtime behavior. They MUST run sequentially — wait for the previous command to complete before running. Do NOT run concurrently with any other collection or analysis command.

---

## Phase 1: System Environment Static Information Collection

**Objective**: Gather static system environment information — hardware specifications, software versions, and kernel boot parameters. This phase collects **static** facts about the system, not dynamic runtime metrics.

**Collection Command**: Run `scripts/phase1-static-info.sh` to collect static system information.

**Output**: Static system profile: hardware specs (CPU model/core count/NUMA, memory size, disk types, NIC models), software versions (OS, kernel, tools), kernel boot parameters and key sysctl settings.

reference:basic-system-info

---

## Phase 2: Main Workload Identification and Bottleneck Analysis

### Step 2.1: Global Resource Bottleneck Identification

**Collection Command**: Run `scripts/phase2.1-global-bottleneck.sh` to collect global resource bottleneck indicators.

Identify bottleneck characteristics across CPU, memory, I/O, and network. Use specific metrics to pinpoint resource pressure.

**quick diagnosis**: run CPU/MEM/IO/NET analysis in background subtask and in parallel.

**Key Indicators to Analyze**:

| Category | Key Indicators |
|----------|----------------|
| CPU | %user > 80%, %iowait > 20%, %steal > 10%, %soft > 10%, cs/s > 50000, in/s > 10000, loadavg > CPU_count*2, r > CPU_count |
| CPU Thermal | %steal > 10% (may indicate thermal throttling), freq-gov, core_throttle_count |
| Memory | majflt/s > 1000 indicates swap thrashing; Slab > 30% of total memory indicates kernel memory pressure; MemAvailable < 15%; Committed_AS > 100% of total; PSI some > 50% |
| Memory Page | pgscank/s > 1000, pgscand/s > 1000 indicates memory reclaim pressure |
| I/O | %util > 90%, await > 20ms, read_kB/s > 100000, write_kB/s > 50000, avgqu-sz > 16, %vmutil > 30% |
| Network | retransmission rate > 2%, ListenDrops > 0, TIME_WAIT > 5000, established connections > 10000 per port, TCP orphans > 1000 |
| Network Socket | socket memory pressure, ListenOverflows, halfopen connections |
| Network Softirq | softirq% > 30% indicates network processing bottleneck |
| System | file-nr > system limit, inode-nr > system limit, threads-max reached |

**Output**: Identify which resource(s) are under highest pressure with specific evidence (e.g., "CPU bottleneck: %iowait consistently 25-35% across 5 samples").

---

### Step 2.2: Top Resource Process Identification

**Collection Command**: Run `scripts/phase2.2-top-processes.sh` to collect top resource-consuming processes.

From Step 2.1, identify top resource-consuming processes and perform detailed OS-level analysis. **Focus on resource consumption patterns (CPU%, syscalls, context switches, I/O wait) — do NOT analyze application internals (query plans, heap dumps, application logic).**

**Output**: Top processes consuming cpu/mem/io resource.

---

## Phase 3: Hotspot Function and Syscall Analysis

**Execution order**: Step 3.1 → wait for completion → Step 3.2. Do NOT overlap.

### Step 3.1: Hotspot Function Analysis

**Collection Command**: Run `scripts/phase3.1-hotspot-function.sh <PID>` to collect hotspot function data.

**Key Metrics to Analyze**:
- Top hotspot functions by CPU time (perf report)
- Call stack depth and recursive patterns
- User-space vs kernel-space time distribution

**Anomaly Detection**:
- Functions with unexpectedly high CPU time compared to historical baseline
- High context switch rate (cs/s > 50000 for single process)

**Output**: For each top process, record: PID, name, top 5 hot functions, total CPU%, main system calls, identified bottlenecks with evidence.

---

### Step 3.2: Syscall Analysis

**Collection Command**: Run `scripts/phase3.2-syscall-analysis.sh <PID>` to collect syscall data. Must run AFTER Phase 3.1 completes.

**Key Metrics to Analyze**:
- System call patterns and latency (strace output)
- Long-running system calls (block > 100ms)
- Excessive system call frequency (> 10000 syscalls/sec)

**Output**: For each top process, record: PID, name, syscall summary with counts, latency, and errors.

---

## Phase 4: Microarchitecture Bottleneck Analysis

**Collection Command**: Run `scripts/phase4-microarch.sh <PID>` to collect microarchitecture PMU data. Must run AFTER Phase 3 completes.

Use PMU (Performance Monitoring Unit) events to identify cache, branch, and pipeline bottlenecks:

**Key Indicators to Analyze**:

| Category | Key Indicators | Thresholds |
|----------|----------------|------------|
| L1 Cache | L1-dcache-load-misses / L1-dcache-loads | > 10% |
| LLC Cache | LLC-load-misses / LLC-loads | > 20% |
| Branch Prediction | branch-misses / branches | > 5% |
| Frontend Stall | stalled-cycles-frontend / cycles | > 30% |
| Backend Stall | stalled-cycles-backend / cycles | > 20% |
| NUMA Imbalance | remote_loads / local_loads | > 2:1 |

**Output**: Microarchitecture bottleneck report with:

- L1/LLC cache miss rates
- Branch misprediction rate
- Frontend/backend stall percentages
- NUMA locality ratios
- Identified microarchitecture bottlenecks (e.g., "L1 cache miss rate 15% - high memory access density at OS level")

---

## Phase 5: Deep-Dive Analysis via Specialized Skills

Based on the bottleneck categories identified in Phase 5, invoke the corresponding specialized skills for deep-dive analysis.

### Step 5.1: Determine Specialized Skill Mapping

Map identified bottleneck types to specialized skills:

| Identified Bottleneck Type | Specialized Skill to Invoke |
|---------------------------|----------------------------|
| Disk I/O saturation (%util > 90%, await > 20ms) | **io-bottleneck** |
| CPU iowait elevated (%iowait > 20%) | **io-bottleneck** |
| Memory pressure (SwapUsed > 50%, majflt/s > 1000) | **mem-bottleneck** |
| NUMA imbalance (remote/local > 2:1) | **mem-bottleneck** |
| Memory fragmentation (Slab > 30%) | **mem-bottleneck** |
| Network retransmission (Retrans > 2%) | **net-bottleneck** |
| Connection exhaustion (TIME_WAIT > 5000) | **net-bottleneck** |
| High context switches with futex wait | **lock-bottleneck** |
| Processes in D/S state with lock wchan | **lock-bottleneck** |
| Scheduling latency outliers (max delay > 100ms) | **schedule-trace-analysis** |
| CPU contention (preemption > threshold) | **schedule-trace-analysis** |

### Step 5.2: Invoke Specialized Skills

For each identified bottleneck category with **Critical** or **High** severity, invoke the corresponding skill:

**For I/O Bottlenecks:**

```bash
# Invoke io-bottleneck skill
skill:io-bottleneck
# Focus areas:
# - I/O scheduler configuration
# - Blocked process wait channel analysis
# - Page cache pressure
```

**For Memory Bottlenecks:**

```bash
# Invoke mem-bottleneck skill
skill:mem-bottleneck
# Focus areas:
# - PSI memory pressure
# - OOM events and statistics
# - Slab allocator details
# - NUMA hit/miss statistics
# - Vmalloc usage
```

**For Network Bottlenecks:**

```bash
# Invoke net-bottleneck skill
skill:net-bottleneck
# Focus areas:
# - Socket memory usage
# - Loopback latency test
```

**For Lock Contention:**

```bash
# Invoke lock-bottleneck skill
skill:lock-bottleneck
# Focus areas:
# - Futex syscall tracing
# - /proc/PID/wchan analysis
# - Kernel lock statistics
# - File lock status
# - Softirq SCHED activity
```

**For Scheduling Issues:**

```bash
# Invoke schedule-trace-analysis skill
skill:schedule-trace-analysis
# Focus areas:
# - Scheduling latency distribution (P50/P90/P95/P99)
# - Preemptor identification and impact
# - CPU affinity and priority
# - perf sched event analysis
```

---

## Phase 6: Evidence-Based Bottleneck Analysis

**Requirement**: Every bottleneck claim MUST be backed by specific evidence from Phases 1-5. No vague or speculative statements.

**Bottleneck categories and evidence mapping**:

| Category | Key Evidence Metrics | Thresholds | Collection Method |
|----------|---------------------|------------|-------------------|
| CPU Compute | %user, load average, per-CPU utilization | %user > 80%, loadavg > CPU_count*2, r > CPU_count | mpstat, pidstat -u, top |
| CPU I/O Wait | %iowait, vmstat b (blocked processes) | %iowait > 20%, blocked > 10 | mpstat, vmstat |
| CPU Context Switch | cs/s (context switches), in/s (interrupts) | cs/s > 50000, in/s > 10000 | vmstat, pidstat -w |
| CPU Thermal | thermal throttle count, freq | %steal > 10%, throttle > 0 | mpstat, /sys/kernel/thermal |
| Memory Capacity | MemAvailable, Committed_AS, Swap | MemAvailable < 15%, Committed_AS > 100% | free, /proc/meminfo |
| Memory PSI | PSI memory stall % | some > 50% | cat /proc/pressure/mem |
| Memory Pressure | Swap usage, page faults, Slab | SwapUsed > 50%, majflt/s > 1000 | free, pidstat -r, meminfo |
| Memory Reclaim | pgscank/s, pgscand/s | > 1000 | vmstat |
| Memory Fragmentation | Slab, HugePages, Committed_AS | Slab > 30% total, frag > 50% | cat /proc/meminfo |
| Disk I/O | %util, await, queue depth, avgqu-sz | %util > 90%, await > 20ms, avgqu-sz > 16 | iostat -xz |
| Disk I/O per process | read_kB/s, write_kB/s | > 100000 r/s, > 50000 w/s | pidstat -d |
| Network Interface | rxerr/s, txerr/s, collisions | rxerr/s > 10, txerr/s > 10 | sar -n EDEV |
| Network TCP | retransmission rate, drops, orphans | Retrans > 2%, ListenDrops > 0, orphans > 1000 | nstat, ss, /proc/net/sockstat |
| Network Connections | TIME_WAIT, established per port | TIME_WAIT > 5000, conn/port > 10000 | ss |
| Network Socket | socket memory, listen overflows | TCP memory > high, ListenOverflows > 0 | /proc/net/sockstat |
| Network Softirq | softirq% of total CPU | > 30% | mpstat, /proc/softirqs |
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
- [ ] Phase 5 deep-dive analysis via specialized skills (if bottleneck type identified)

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
  - **Phase 5 Completion Requirement**: If any Critical or High severity bottlenecks are identified in Phase 1-4, Phase 5 deep-dive analysis via specialized skills MUST be completed before finalizing the report.
- **Stop when**: All phases are fully executed, all evidence collected, all bottleneck categories mapped, Phase 5 deep-dive completed (if triggered), and the user confirms the report is complete.

---

## Output Template

reference:output-template

---

## Operational Notes

- All phases result should be included in analysis summary.
- All analysis must be specific and evidence-based; maintain rigor and professionalism.
- **Scope Constraint — OS Level Only**: This skill analyzes ONLY OS-level information and bottlenecks. Do NOT collect, interpret, or provide recommendations based on application-layer data (e.g., MySQL query plans, PostgreSQL EXPLAIN output, Java heap/Garbage Collection logs, Redis command traces, application configuration files, application business logic). If application-layer issues are detected (e.g., a process spending excessive time in application code), describe it at the OS level (e.g., "process spending 80% CPU time in user space") without diving into application internals.
