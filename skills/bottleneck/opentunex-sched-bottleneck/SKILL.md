---
name: opentunex-sched-bottleneck
description: OS-level scheduling bottleneck analysis. Analyzes scheduling latency, preemption patterns, wakeup latency, and run queue contention using perf sched tools.
---

# OS Scheduling Bottleneck Analysis

This skill performs scheduling trace analysis using perf tools.

---

## Analysis Command Execution

[1] only if **USER** has specified that remote command execution are allowed, Load the `opentunex-remote-execution` skill for standardized SSH connection and command execution.

[2] otherwise, Keep the following rule for command execution: Always read from user-given data collection files to analyze, command execution results should be saved in these files, if some extra commands are needed for analysis, **prioritize referencing existing scripts under this skill's `scripts/` directory** — provide the script path and usage. Only if no existing script covers the needed commands, generate a new script: output it to **USER** in the conversation, **simultaneously write it to a file in the current working directory** using the naming convention `<skill-name>-collect-step<N>.sh` (increment N each round, starting from 1; replace `<skill-name>` with this skill's short name, e.g., `sched-bottleneck`). In all cases, provide usage instructions including: (1) how to execute the script, (2) how to save output (e.g., redirect to a results file), (3) ask user to provide the result file for subsequent analysis. Never execute command automatically.

**Data Collection File Conventions**:
- File path: current working directory
- File naming: `<skill-short-name>-result-<YYYYMMDD-HHMMSS>.txt` (e.g., `sched-bottleneck-result-20260604-143000.txt`)
- File format: plain text with `=== Section Name ===` section headers
- For multiple collection rounds, save each round's output separately with incremented timestamps
- When referencing prior data, explicitly state the file name and section header

---

## Heavyweight Command Constraints (CRITICAL)

**perf sched record** is a heavyweight command that attaches to target processes and alters runtime behavior. It MUST run sequentially and not concurrently with any other collection or analysis command.

---

## Phase 1: Data Collection

**Collection Command**: Run `scripts/collect_sched_metrics.sh --pid [PID] [--duration <SECONDS>]` to collect and analyze scheduling trace data (default 10 seconds, PID optional).

**Output**:
- Prerequisites check (perf_event_paranoid, sched_schedstats)
- Scheduler configuration (sched_latency_ns, sched_min_granularity_ns, sched_wakeup_granularity_ns, sched_tunable_scaling, sched_migration_cost_ns, sched_autogroup_enabled, sched_child_runs_first, sched_rt_period_us, sched_rt_runtime_us, isolcpus, nohz_full)
- Run queue status (running, blocked counts)
- Target process info (PID, name, state, priority, nice, threads, CPU affinity, scheduler policy, RT priority) — if PID specified
- perf sched latency report (sorted by max/avg delay and by runtime)
- perf sched timehist output
- Schedule-out frequency, preemptors, and successors for target process — if PID specified
- Wakeup latency statistics (avg wait, avg sch_delay, max wait, max delay) — if PID specified

---

## Phase 2: Key Metrics Analysis

### Key Metrics to Analyze

| Category | Key Metrics | Anomaly Detection |
|----------|-------------|-------------------|
| Scheduling Latency | avg delay, max delay | avg delay > 5ms (elevated); > 10ms (critical); max delay > 100ms (critical) |
| Scheduling Out Frequency | switches/s | freq > 1000/s (elevated); > 5000/s (critical) |
| Preemption | preempt count, preemptors, successors | preempt > 2x system avg (elevated); > 5x (critical) |
| Wakeup Latency | wait time, sch delay | sch delay > 10ms (elevated); > 50ms (critical) |
| CPU Time Distribution | runtime % | target < expected share (competition) |
| Scheduler Configuration | sched_latency_ns, sched_rt_runtime_us, sched_rt_period_us | sched_rt_runtime_us/sched_rt_period_us < 0.5 (RT starvation risk); sched_rt_runtime_us=-1 (dangerous) |
| Scheduling Policy | SCHED_FIFO/RR vs SCHED_OTHER | RT process without isolcpus (latency jitter); RT with -1 runtime (system freeze risk) |

---

## Phase 3: Bottleneck Identification

### Output Format

```markdown
# Process Scheduling Trace Analysis Report

## Scheduling Bottleneck Conclusion
**OS Scheduling Bottleneck Status**: [EXISTS / DOES NOT EXIST]

## Target Process Summary (if PID specified)
| Attribute | Value |
|-----------|-------|
| PID | [PID] |
| Name | [Name] |
| State | [State] |
| Priority/Nice | [pri]/[ni] |
| Threads | [threads] |
| Affinity | [cpus] |
| Scheduler Policy | [SCHED_OTHER/FIFO/RR] |
| RT Priority | [rtprio] |

## Key Evidence

### Scheduler Configuration Check
| Config | Value | Status |
|--------|-------|--------|
| sched_rt_runtime_us/sched_rt_period_us | X% | [OK/WARNING/CRITICAL] (<50% RT starvation risk; =-1 dangerous) |
| sched_latency_ns | Xms | [OK/ABNORMAL] |
| sched_min_granularity_ns | Xms | [OK/ABNORMAL] |

### Run Queue Status
| Metric | Value | Status |
|--------|-------|--------|
| Running | X | >CPU_count (contention) |
| Blocked | X | - |

### Scheduling Latency (top 30 by delay)
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Avg Delay (top task) | Xms | >5ms | [CRITICAL/ELEVATED/NORMAL] |
| Max Delay (top task) | Xms | >100ms | [CRITICAL/ELEVATED/NORMAL] |

### Wakeup Latency (if PID specified)
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Avg wait_time | Xms | - | |
| Avg sch_delay | Xms | >10ms | [CRITICAL/ELEVATED/NORMAL] |
| Max wait_time | Xms | - | |
| Max sch_delay | Xms | >50ms | [CRITICAL/ELEVATED/NORMAL] |

### Schedule Out Frequency (if PID specified)
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Frequency | X/s | >1000/s | [CRITICAL/ELEVATED/NORMAL] |

### Preemptors/Successors (if PID specified)
| Role | Top Process | Count | Description |
|------|-------------|-------|-------------|
| Preemptor | [PID/Name] | X | Ran before target |
| Successor | [PID/Name] | X | Ran after target |

## Bottleneck Type
| Type | Severity | Evidence |
|------|----------|----------|
| [Scheduling Latency/Preemption/Run Queue Contention/RT Config] | [High/Medium/Low] | [Description] |

## Root Cause Inference
**Primary Cause**: [OS-level root cause]
**Affected Components**: [Scheduler]
**Inference Confidence**: [High/Medium/Low]

## OS-Level Recommendations
1. [Recommendation 1]
2. [Recommendation 2]
```

---

## Error Handling

- **perf_event_paranoid restriction**: If perf_event_paranoid > 0, suggest `echo 0 > /proc/sys/kernel/perf_event_paranoid` or running as root; fall back to /proc/sched_debug and vmstat-based analysis if perf is unavailable.
- **Target process exited**: If --pid is specified but the process has exited, fall back to system-wide scheduling analysis and note the process absence.
- **perf.data not created**: If perf sched record fails, check disk space and permissions; document the failure and use alternative data sources (top, pidstat, /proc).
- **sched_schedstats disabled**: Note that scheduler statistics may be incomplete; suggest enabling with `echo 1 > /proc/sys/kernel/sched_schedstats`.

---

## Operational Notes

- **basic principle**: All analysis must be specific and evidence-based.
- **Iteration**: If evidence is insufficient, narrow focus and deepen analysis.
- **Completion**: All phases must be fully executed before concluding.
- **Scope Constraint — OS Level Only**: This skill analyzes ONLY OS-level information. Do NOT collect or interpret application-layer data.
