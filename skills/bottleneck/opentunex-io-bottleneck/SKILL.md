---
name: opentunex-io-bottleneck
description: OS-level I/O bottleneck analysis. Analyzes disk utilization, I/O wait, queue depth, and memory pressure to identify OS-level I/O bottlenecks. Use when diagnosing disk I/O performance issues.
---

# OS I/O Bottleneck Analysis

This skill performs OS-level I/O performance bottleneck analysis.

---

## Analysis Command Execution

[1] only if **USER** has specified that remote command execution are allowed, Load the `opentunex-remote-execution` skill for standardized SSH connection and command execution.

[2] otherwise, Keep the following rule for command execution: Always read from user-given data collection files to analyze, command execution results should be saved in these files, if some extra commands are needed for analysis, **prioritize referencing existing scripts under this skill's `scripts/` directory** — provide the script path and usage. Only if no existing script covers the needed commands, generate a new script: output it to **USER** in the conversation, **simultaneously write it to a file in the current working directory** using the naming convention `<skill-name>-collect-step<N>.sh` (increment N each round, starting from 1; replace `<skill-name>` with this skill's short name, e.g., `io-bottleneck`). In all cases, provide usage instructions including: (1) how to execute the script, (2) how to save output (e.g., redirect to a results file), (3) ask user to provide the result file for subsequent analysis. Never execute command automatically.

**Data Collection File Conventions**:
- File path: current working directory
- File naming: `<skill-short-name>-result-<YYYYMMDD-HHMMSS>.txt` (e.g., `io-bottleneck-result-20260604-143000.txt`)
- File format: plain text with `=== Section Name ===` section headers
- For multiple collection rounds, save each round's output separately with incremented timestamps
- When referencing prior data, explicitly state the file name and section header

---

## Phase 1: Data Collection

**Collection Command**: Run `scripts/collect_io_metrics.sh --pid [PID] [--duration <SECONDS>]` to collect I/O metrics (default 15 seconds).

**Output**:
- System overview (CPU, memory, disk devices)
- I/O scheduler and queue configuration (scheduler, nr_requests, rotational, etc.)
- blk-mq configuration (hw_queue_depth, numa_node)
- Extended disk stats (/proc/diskstats)
- Memory/page cache settings (vfs_cache_pressure, swappiness, dirty parameters, overcommit)
- Target process IO priority (ionice, if PID provided)
- cgroup IO weight (blkio.weight, io.io_weight)
- Filesystem mount options and journal config (ext4)
- LVM/MD RAID status (if applicable)
- Disk IRQ affinity and cgroup IO throttling
- 15-second vmstat, iostat, pidstat, mpstat dynamic metrics

---

## Phase 2: Key Metrics Analysis

### Key Metrics to Analyze

| Category | Key Metrics | Anomaly Detection |
|----------|-------------|-------------------|
| CPU I/O Wait | %iowait, %user, r (runnable), b (blocked) | %iowait > 20% (elevated); > 30% (critical); r > CPU_count*4 (severe queueing) |
| Disk Utilization | %util, await, avgqu-sz, r/s, w/s, rkB/s, wkB/s | %util > 70% (elevated); > 90% (critical); await > 20ms (elevated); > 100ms (critical); avgqu-sz > 4 (elevated); > 16 (critical) |
| Disk Saturation | aqu-sz, w_await, r_await | aqu-sz > 4 (elevated); > 16 (critical); w_await/r_await > 50ms (high latency) |
| I/O Pattern | rrqm/s+wrqm/s merge rate, avgrq-sz, inferred pattern | Sequential: merge>30% + avgrq>32; Random: merge<10% + avgrq<16; MIXED: otherwise |
| Readahead Match | read_ahead_kb vs observed avgrq-sz | read_ahead_kb >> avgrq-sz (wasted prefetch); read_ahead_kb << avgrq-sz (insufficient prefetch); optimal: read_ahead_kb ≈ avgrq-sz * 2 |
| Swap Activity | si, so, swpd; driven by memory PSI pressure | si > 0 (swap in); so > 0 (swap out); swpd > 50% of memory (heavy swap); competes with application IO |
| Memory PSI | memory stall % (some avg10, full avg10); PSI = Pressure Stall Information (some=partial stall, full=complete stall); indicates memory pressure causing indirect IO (swap, page cache churn, direct reclaim blocking) | some avg10 > 30% (elevated); > 50% (critical); full avg10 > 50% (sustained pressure) |
| Memory Overcommit | overcommit_memory, overcommit_ratio | overcommit_memory=2 (never) is safest; overcommit_ratio > 50 (risky) |
| Blocked Processes | D-state count, S-state count, wchan patterns | D-state > CPU_count (critical); same wchan > 10 (contention) |
| Page Cache Pressure | pgscank/s, pgscand/s, pgfree/s | pgscank/s > 1000 (kswapd aggressive); pgscand/s > 1000 (direct reclaim storm) |
| Process I/O | iodelay, %wa per process (pidstat), ionice class, blkio.weight | iodelay > 10ms (elevated); %wa > 30% (process I/O bound); ionice=idle (throttled); blkio.weight=100 (low priority) |
| IO Throttling | cgroup blkio.throttle, io.latency, cgroup IO weight | throttled processes showing high wait time; io.weight indicates cgroup priority |
| Filesystem Journal | ext4 journal size, commit interval | journal > 1GB (excessive); commit interval > 15s (high latency risk) |
| NFS/Network Storage | retrans rate, sync/async mount | Retrans > 2% (network issue); sync mount (high latency) |

---

## Phase 3: Bottleneck Identification

### Output Format

```markdown
# OS I/O Bottleneck Analysis Report

## I/O Bottleneck Conclusion
**OS I/O Bottleneck Status**: [EXISTS / DOES NOT EXIST]

## Key Evidence
| Metric | Observed Value | Threshold | Status |
|--------|---------------|-----------|--------|
| CPU iowait % | X% | >20% | [CRITICAL/ELEVATED/NORMAL] |
| Disk %util | X% | >90% | [CRITICAL/ELEVATED/NORMAL] |
| Blocked processes | X | >CPU_count | [CRITICAL/ELEVATED/NORMAL] |
| IO await (ms) | Xms | >20ms | [CRITICAL/ELEVATED/NORMAL] |

## Bottleneck Type
| Type | Severity | Evidence |
|------|----------|----------|
| [Disk Saturation/CPU iowait/Page Cache] | [High/Medium/Low] | [Description] |

## Root Cause Inference
**Primary Cause**: [OS-level root cause]
**Affected Components**: [e.g., Block Layer, Memory Management]
**Inference Confidence**: [High/Medium/Low]

## OS-Level Recommendations
1. [Recommendation 1]
2. [Recommendation 2]
```

---

## Error Handling

- **iostat/sar not installed**: Fall back to reading /proc/diskstats and /proc/vmstat directly; document reduced granularity in the report.
- **perf_event_paranoid restriction**: If perf_event_paranoid > 0, suggest `echo 0 > /proc/sys/kernel/perf_event_paranoid` or running as root; fall back to /proc and sysfs-based analysis.
- **Target process exited**: If --pid is specified but the process has exited, fall back to system-wide I/O analysis and note the process absence.
- **Block device path not found**: If the target device is a virtual device (LVM, MD), resolve to physical devices via /sys/block or dmsetup; document the mapping.

---

## Operational Notes

- **basic principle**: All analysis must be specific and evidence-based.
- **Iteration**: If evidence is insufficient, narrow focus and deepen analysis.
- **Completion**: All phases must be fully executed before concluding.
- **Scope Constraint — OS Level Only**: This skill analyzes ONLY OS-level information. Do NOT collect or interpret application-layer data.
