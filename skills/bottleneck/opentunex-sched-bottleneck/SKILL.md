---
name: opentunex-sched-bottleneck
description: OS-level scheduling bottleneck analysis. Analyzes scheduling latency, preemption patterns, wakeup latency, and run queue contention using perf sched tools.
---

# OS Scheduling Bottleneck Analysis

This skill performs scheduling trace analysis using perf tools.

---

## Analysis Command Execution

[1] only if **USER** has specified that remote command execution are allowed, Load the `remote-execution` skill for standardized SSH connection and command execution.

[2] otherwise, Keep the following rule for command execution: Always read from user-given data collection files to analyze, command execution results should be saved in these files, if some extra commands are needed for analysis, output command execution script to **USER**, and ask **USER** to provide execution results, never execute command automatically.

---

## Phase 1: Data Collection

**Collection Command**: (Execute only if `sched_metrics_analysis.txt` e.g. does not exist) Run `scripts/collect_sched_metrics.sh --pid [PID] [--duration <SECONDS>]` to collect and analyze scheduling trace data (default 5 seconds, PID optional).

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

## Phase 4: output report to disk

After the analysis is completed, write Phase 3 bottleneck analysis report into file in current working directory.

**Saved File**: `sched_bottleneck_report.md`
**Report Content**: Includes all the fields in the Phase 3 Output Format (bottleneck conclusion, key evidence, bottleneck type, root cause inference, OS-level recommendations)

---

## Operational Notes

- **basic principle**: All analysis must be specific and evidence-based.
- **Iteration**: If evidence is insufficient, narrow focus and deepen analysis.
- **Completion**: All phases must be fully executed before concluding.
- **Scope Constraint — OS Level Only**: This skill analyzes ONLY OS-level information. Do NOT collect or interpret application-layer data.
