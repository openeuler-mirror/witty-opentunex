---
name: opentunex-top-down-bottleneck
description: Top-down OS-level bottleneck analysis, includes comprehensive system collection(read from user-given data collection files first), and three-level bottleneck analysis (global, process, microarchitecture). This skill should be triggered FIRST for any performance optimization tasks, serving as the prerequisite for specialized bottleneck skills (sched-bottleneck, lock-bottleneck, io-bottleneck, mem-bottleneck, net-bottleneck). Use when diagnosing OS-level performance issues, identifying high-pressure processes, mapping resource dependencies, or analyzing OS-level resource bottlenecks. This skill does NOT analyze application-layer data (e.g., MySQL query plans, Java heap, Redis commands).
---

# top-down-bottleneck — Top-Down System Bottleneck Analysis

This skill performs a seven-phase analysis:
(1) system environment static information analysis;
(2) global resource bottleneck identification and top resource-consuming process identification;
(3) hotspot function and syscall analysis for top processes;
(4) microarchitecture bottleneck analysis using PMU events;
(5) deep-dive analysis via specialized skills;
(6) evidence-based bottleneck mapping;
(7) output bottleneck analysis report.

**IMPORTANT**: This skill must be triggered FIRST for performance optimization. Phase 5 specialized skills (sched-bottleneck, lock-bottleneck, io-bottleneck, mem-bottleneck, net-bottleneck) should only be invoked based on top-down findings, not independently.

The skill focuses exclusively on OS-level resource bottlenecks. It does NOT collect, analyze, or provide recommendations for application-layer data (database queries, JVM heap, application logs, etc.).
The skill supports iterative refinement until sufficient analysis is achieved.
First try to read from user-given data collection files, if data is not enough, **prioritize referencing existing scripts under this skill's `scripts/` directory** — provide the script path and usage. Only if no existing script covers the needed commands, generate a new script and **simultaneously write it to a file in the current working directory** (following the naming convention in the Analysis Command Execution rule below), along with usage instructions, to conduct supplementary collection.

---

## Analysis Command Execution

[1] only if **USER** has specified that remote command execution are allowed, Load the `opentunex-remote-execution` skill for standardized SSH connection and command execution.

[2] otherwise, Keep the following rule for command execution: Always read from user-given data collection files to analyze, command execution results should be saved in these files, if some extra commands are needed for analysis, **prioritize referencing existing scripts under this skill's `scripts/` directory** — provide the script path and usage. Only if no existing script covers the needed commands, generate a new script: output it to **USER** in the conversation, **simultaneously write it to a file in the current working directory** using the naming convention `<skill-name>-collect-step<N>.sh` (increment N each round, starting from 1; replace `<skill-name>` with this skill's short name, e.g., `topdown-bottleneck`). In all cases, provide usage instructions including: (1) how to execute the script, (2) how to save output (e.g., redirect to a results file), (3) ask user to provide the result file for subsequent analysis. Never execute command automatically.

**Data Collection File Conventions**:
- File path: current working directory
- File naming: `<skill-short-name>-result-<YYYYMMDD-HHMMSS>.txt` (e.g., `topdown-bottleneck-result-20260604-143000.txt`)
- File format: plain text with `=== Section Name ===` section headers
- For multiple collection rounds, save each round's output separately with incremented timestamps
- When referencing prior data, explicitly state the file name and section header
- **Inter-phase data passing**: When Phase 2.2 identifies top resource-consuming processes, extract the PID(s) from the output and pass them explicitly via `--pid <PID>` to Phase 3.1, 3.2, and 4 collection scripts. If multiple processes are significant, run each phase per-PID sequentially.

---

## Heavyweight Command Constraints (CRITICAL)

**Heavyweight commands** (`perf record`, `perf top`, `perf stat`, `strace`) attach to the target process and alter its runtime behavior. They MUST run sequentially — wait for the previous command to complete before running. Do NOT run concurrently with any other collection or analysis command.

---

## Phase 1: System Environment Static Information Collection

**Objective**: Gather static system environment information — hardware specifications, software versions, and kernel boot parameters. This phase collects **static** facts about the system, not dynamic runtime metrics.

**Collection Command**: Run `scripts/phase1-static-info.sh` to collect static system information.

**Output**: Static system profile: hardware specs (CPU model/core count/NUMA, memory size, disk types, NIC models), software versions (OS, kernel, tools), kernel boot parameters and key sysctl settings.

---

## Phase 2: Main Workload Identification and Bottleneck Analysis

### Step 2.1: Global Resource Bottleneck Identification

**Collection Command**: Run `scripts/phase2.1-global-bottleneck.sh` to collect global resource bottleneck indicators.

Identify bottleneck characteristics across CPU, memory, I/O, and network. Use specific metrics to pinpoint resource pressure.

**Key Indicators to Analyze**:

| Category | Key Indicators | Anomaly Detection |
|----------|----------------|---------------------------|
| CPU | %user, %iowait, %steal, %soft, cs/s, in/s, loadavg, r (runnable) | %user > 80% (compute bound); %iowait > 20% (I/O wait); %steal > 10% (hypervisor contention); loadavg > CPU_count*2 (CPU saturation); r > CPU_count*4 (severe queueing) |
| CPU Thermal | core_throttle_count, freq-gov, thermal zone temp | throttle > 0 (thermal throttling active); freq < nominal (performance degradation) |
| Memory | majflt/s, Slab%, MemAvailable, Committed_AS | majflt/s > 1000 (swap thrashing); Slab > 30% (kernel memory pressure); MemAvailable < 15% (low memory); Committed_AS > 100% (overcommit risk) |
| Memory PSI | memory stall % (some avg10, full avg10) | some avg10 > 50% (acute pressure); full avg10 > 50% (sustained pressure, critical) |
| Memory Page Reclaim | pgscank/s, pgscand/s | pgscank/s > 1000 (kswapd aggressive scanning); pgscand/s > 1000 (direct reclaim storm) |
| I/O | %util, await, read_kB/s, write_kB/s, avgqu-sz, %vmutil | %util > 90% (disk saturation); await > 20ms (I/O latency); avgqu-sz > 16 (queue backlog); %vmutil > 30% (memory pressure from I/O) |
| Network TCP | retrans rate, ListenDrops, TIME_WAIT, established, orphans | Retrans > 2% (network quality issue); ListenDrops > 0 (listen queue overflow); TIME_WAIT > 5000 (connection cleanup backlog); orphans > 1000 (socket memory leak) |
| Network Socket | TCP mem, ListenOverflows, halfopen | TCP mem > high_thresh (socket memory pressure); ListenOverflows > 0 (connection refused risk); halfopen > 1000 (SYN flood indicator) |
| Network Softirq | softirq% of total CPU, NET_RX/TX rates | softirq% > 30% (network processing bottleneck); NET_RX spike (interrupt storm) |
| System | file-nr, inode-nr, threads-max, proc-pid-max | file-nr > max (FD exhaustion); threads-max reached (thread creation blocked) |

**Output**: Identify which resource(s) are under highest pressure with specific evidence (e.g., "CPU bottleneck: %iowait consistently 25-35% across 5 samples").

---

### Step 2.2: Top Resource Process Identification

**Collection Command**: Run `scripts/phase2.2-top-processes.sh` to collect top resource-consuming processes.

From Step 2.1, identify top resource-consuming processes and perform detailed OS-level analysis. **Focus on resource consumption patterns (CPU%, syscalls, context switches, I/O wait) — do NOT analyze application internals (query plans, heap dumps, application logic).**

**Output**: Top processes consuming cpu/mem/io resource.

Top processes should be consistent with benchmark target application. And in following phases, `PID` refers to the PID of Top process detected in this phase.

---

## Phase 3: Hotspot Function and Syscall Analysis

**Execution order**: Step 3.1 → wait for completion → Step 3.2. Do NOT overlap.

### Step 3.1: Hotspot Function Analysis

**Collection Command**: Run `scripts/phase3.1-hotspot-function.sh --pid <PID>` to collect hotspot function data.

**Key Metrics to Analyze**:

| Category | Key Metrics | Anomaly Detection |
|----------|-------------|-------------------|
| Hotspot Functions | top functions by CPU time, function name, module | function CPU% > 50% (optimization target); function not in expected module (unexpected load) |
| Call Stack | stack depth, recursive patterns | depth > 20 (deep recursion); recursive call detected (stack overflow risk) |
| Time Distribution | user-space %, kernel-space % | kernel% > 80% (syscall/I/O overhead); user% < 20% with high CPU (app issue) |
| Context Switch | cs/s per process | cs/s > 50000 for single process (excessive switching) |

**Output**: For each top process, record: PID, name, top 5 hot functions, total CPU%, main system calls, identified bottlenecks with evidence.

---

### Step 3.2: Syscall Analysis

**Collection Command**: Run `scripts/phase3.2-syscall-analysis.sh --pid <PID>` to collect syscall data. Must run AFTER Phase 3.1 completes.

**Key Metrics to Analyze**:

| Category | Key Metrics | Anomaly Detection |
|----------|-------------|-------------------|
| Syscall Latency | block time per syscall, slow syscall count | block > 100ms (slow syscall, I/O or lock wait); block > 1000ms (severe delay) |
| Syscall Frequency | syscalls/sec, syscall pattern | freq > 10000/s (excessive overhead); unusual syscall mix (unexpected behavior) |
| Syscall Errors | error rate, error types | error rate > 1% (app/permission issues); ENOSPC/EMFILE (resource exhaustion) |
| Specific Syscalls | getpid/getuid calls, epoll_wait/select | getpid > 1000/s (unnecessary overhead); epoll_wait > 5000/s with low events (idle polling) |

**Output**: For each top process, record: PID, name, syscall summary with counts, latency, and errors.

---

## Phase 4: Microarchitecture Bottleneck Analysis

**Collection Command**: Run `scripts/phase4-microarch.sh --pid <PID>` to collect microarchitecture PMU data. Must run AFTER Phase 3 completes.

Use PMU (Performance Monitoring Unit) events to identify cache, branch, and pipeline bottlenecks:

**Key Metrics to Analyze**:

| Category | Key Metrics | Anomaly Detection |
|----------|-------------|-------------------|
| L1 Cache | L1-dcache-loads, L1-dcache-load-misses, miss rate | miss rate > 10% (L1 cache pressure); > 15% (severe) |
| LLC Cache | LLC-loads, LLC-load-misses, miss rate | miss rate > 20% (LLC pressure); > 30% (severe memory footprint) |
| TLB | dTLB-loads, dTLB-load-misses, iTLB-loads, iTLB-load-misses, miss rate | miss rate > 5% (TLB pressure); > 10% (severe, memory access overhead) |
| Branch Prediction | branches, branch-misses, miss rate | miss rate > 5% (prediction errors); > 10% (high mispredict penalty) |
| CPU Efficiency | cycles, instructions, CPI = cycles/instructions | CPI > 2 (memory bound); CPI > 3 (severe memory bottleneck) |
| Frontend Stall | stalled-cycles-frontend, cycles, stall % | stall% > 30% (frontend bound); > 50% (severe fetch bottleneck) |
| Backend Stall | stalled-cycles-backend, cycles, stall % | stall% > 20% (backend bound); > 40% (memory latency issue) |
| NUMA (SCCL) | remote_access, ll_cache; cross-SCCL ratio = remote_access / (remote_access + ll_cache) | cross-SCCL ratio > 30% (NUMA imbalance); > 50% (critical, severe cross-SCCL access) |

**Output**: Microarchitecture bottleneck report with:

- L1/LLC cache miss rates and thresholds exceeded
- TLB miss rates and impact
- Branch misprediction rate and impact
- Frontend/backend stall percentages and severity
- Cross-SCCL NUMA ratio and impact (ARM only)
- Identified microarchitecture bottlenecks with severity mapping

---

## Phase 5: Deep-Dive Analysis via Specialized Skills

**Prerequisite**: Phase 5 specialized skills MUST only be invoked AFTER top-down analysis (Phase 1-4) identifies specific bottleneck types. Do NOT invoke specialized skills independently without top-down findings.

### Step 5.1: Determine Specialized Skill Mapping

Map identified bottleneck types to specialized skills (invoked in order based on findings):

| Identified Bottleneck Type | Severity | Specialized Skill to Invoke |
|---------------------------|----------|----------------------------|
| Scheduling latency outliers (max delay > 100ms) | High/Critical | **sched-bottleneck** (phase5.1) |
| CPU contention (preemption > threshold) | High/Critical | **sched-bottleneck** (phase5.1) |
| High context switches with futex wait | High/Critical | **lock-bottleneck** (phase5.2) |
| Processes in D/S state with lock wchan | High/Critical | **lock-bottleneck** (phase5.2) |
| Disk I/O saturation (%util > 90%, await > 20ms) | High/Critical | **io-bottleneck** (phase5.3) |
| CPU iowait elevated (%iowait > 20%) | High/Critical | **io-bottleneck** (phase5.3) |
| Memory pressure (SwapUsed > 50%, majflt/s > 1000) | High/Critical | **mem-bottleneck** (phase5.4) |
| NUMA imbalance (remote/local > 2:1) | High/Critical | **mem-bottleneck** (phase5.4) |
| Memory fragmentation (Slab > 30%) | Medium/High | **mem-bottleneck** (phase5.4) |
| Network retransmission (Retrans > 2%) | High/Critical | **net-bottleneck** (phase5.5) |
| Connection exhaustion (TIME_WAIT > 5000) | Medium/High | **net-bottleneck** (phase5.5) |

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
# Invoke sched-bottleneck skill
skill:sched-bottleneck
# Focus areas:
# - Scheduling latency distribution (P50/P90/P95/P99)
# - Preemptor identification and impact
# - CPU affinity and priority
# - perf sched event analysis
```

Each specified skill invoked should analyze the key process `PID` found in previous phases.

---

## Phase 6: Evidence-Based Bottleneck Mapping

**Requirement**: Every bottleneck claim MUST be backed by specific evidence from Phases 1-5. No vague or speculative statements.

**Evidence chain**: Link findings across phases to form a complete causal chain:

```
Phase 1 (Static) → Phase 2.1 (Global) → Phase 2.2 (Process) → Phase 3 (Hotspot) → Phase 4 (Microarch) → Phase 5 (Specialized)

Example evidence chain:
1. Phase 2.1: %iowait > 30%, disk %util > 90% (global I/O saturation)
2. Phase 2.2: process XYZ reads 50MB/s, major culprit
3. Phase 3: perf shows 60% time in ext4_readpage, syscall read() blocked
4. Phase 4: LLC miss rate 45% (critical), memory bound
5. Conclusion: I/O bound process with LLC thrashing, recommend I/O scheduler tuning
```

**Example evidence mapping** (values from Phase 1-5 outputs):

| Bottleneck | Phase 2.1 Finding | Phase 2.2/3 Finding | Phase 4 Finding | Inferred Root Cause |
|------------|------------------|---------------------|-----------------|---------------------|
| CPU I/O Wait | %iowait=35%, disk %util=95% | proc XYZ read=50MB/s | - | Disk saturation causing I/O wait |
| Memory Pressure | majflt/s=1500, SwapUsed=60% | proc ABC VmRSS=8GB | CPI=2.8 (memory bound) | Swap thrashing, insufficient RAM |
| Cache Bound | - | - | LLC miss rate=45%, CPI=3.2 | Memory access pattern issue |
| Lock Contention | cs/s=65000, softirq%=25% | futex wait=80% | - | Userspace lock contention |
| NUMA Imbalance | - | - | cross-SCCL=55% | Process bound to remote SCCL |

**Evidence requirements**:
- Each bottleneck claim MUST cite evidence from at least Phase 2.1 or 2.2
- Critical/High severity requires Phase 3 or 4 supporting evidence
- Root cause inference must connect observed metrics to system behavior

**Bottleneck prioritization**:

1. **Critical**: Resource saturation (CPU 100%, Disk 100%, Swap in use)
2. **High**: Excessive latency (I/O await > 100ms, network retrans > 10%, scheduling max delay > 100ms)
3. **Medium**: Performance degradation (cache miss > 30%, branch miss > 10%, Slab > 30%)
4. **Low**: Suboptimal but not blocking (context switches elevated but acceptable)

---

## Phase 7: Output Bottleneck Analysis Report

Summarize all other phases findings, and output analysis report, also save as `opentunex-bottleneck-analysis-report-<APP>-<BENCHMARK>-<DATE>.md` in current working directory.

Read `references/bottleneck-analysis-report-template.md` (located under this skill's directory) for report template.

---

## Error Handling

- **Script execution failure**: If any phase script fails, document the failure, skip the affected analysis, and continue with remaining phases. Note the data gap in the final report.
- **perf_event_paranoid restriction**: If perf_event_paranoid > 0, suggest `echo 0 > /proc/sys/kernel/perf_event_paranoid` or running as root; fall back to /proc and sysfs-based analysis for affected phases.
- **Target process exited mid-analysis**: If the target PID becomes unavailable, fall back to system-wide analysis for remaining phases and note the process absence.
- **Insufficient permissions**: For scripts requiring root (e.g., /proc/slabinfo, lock_stat, some perf events), document missing data and suggest elevated privileges; proceed with available data.
- **Tool not installed**: If perf, sar, or other required tools are missing, document the limitation and use alternative data sources where possible (e.g., /proc, /sys).

---

## Operational Notes

- **basic principle**: All analysis must be specific and evidence-based; maintain rigor and professionalism.
- **Iteration**: If evidence is insufficient, narrow focus (e.g., container/port/device) and deepen analysis; reuse existing data if system state unchanged; Phase 5 deep-dive is required for Critical/High severity.
- **Completion**: All phases must be fully executed before bottleneck analysis report output; Evidence-Based bottleneck analysis should only stop when evidence is complete and not guessing. All phases result should be included in final report.
- **Scope Constraint**: This skill analyzes **ONLY OS-LEVEL** bottlenecks(kernel/system config, compiler flags, runtime linker). Do NOT collect, interpret, or provide recommendations based on application-layer data (e.g., MySQL query plans, PostgreSQL EXPLAIN output, Java heap/Garbage Collection logs, Redis command traces, application configuration files, application business logic). If application-layer issues are detected (e.g., a process spending excessive time in application code), describe it at the OS level (e.g., "process spending 80% CPU time in user space") without diving into application internals.
- **Operation Constraint**: This skill only do analysis operations with no side effect for target machine, changing system configuration or covering application data are **NOT ALLOWED**.
