---
name: opentunex-lock-bottleneck
description: OS-level lock performance bottleneck analysis. Analyzes lock contention, futex wait patterns, spinlock contention, and blocking behavior to identify if target business process suffers from OS lock bottlenecks.
---

# OS Lock Bottleneck Analysis

This skill performs OS-level lock performance bottleneck analysis.

---

## Analysis Command Execution

[1] only if **USER** has specified that remote command execution are allowed, Load the `remote-execution` skill for standardized SSH connection and command execution.

[2] otherwise, Keep the following rule for command execution: Always read from user-given data collection files to analyze, command execution results should be saved in these files, if some extra commands are needed for analysis, output command execution script to **USER**, and ask **USER** to provide execution results, never execute command automatically.

---

## Heavyweight Command Constraints

**perf record** is a heavyweight command that attaches to target processes. It MUST run sequentially and not concurrently with other collection or analysis commands.

---

## Phase 1: Data Collection

**Collection Command**: Run `scripts/collect_lock_trace.sh --pid [PID] [--duration <SECONDS>]` to collect lock metrics (default 15 seconds).

**Output**:
- System lock configuration (lock_stat, sched_schedstats, futex settings)
- Target process info (PID, threads, state, wchan)
- Perf lock trace data (futex, sched_switch, sched_wakeup events)
- System state during collection (vmstat, pidstat, softirqs, /proc/locks)

---

## Phase 2: Key Metrics Analysis

### Key Metrics to Analyze

| Category | Key Metrics | Anomaly Detection |
|----------|-------------|-------------------|
| Blocking Behavior | D-state count, S-state count, wchan patterns | D-state > CPU_count (critical); Same wchan > 10 (lock contention) |
| Futex Activity | futex WAIT/s, Wait/Wake ratio, same addr waits | WAIT/s > 5000 (elevated); Wait/Wake ratio > 2:1 (contention); same addr > 10 (contention) |
| Lock Contention | SCHED softirq rate, lock_stat data, wait time | SCHED softirq > 50000/s (elevated); > 100000/s (critical); wait time > 20% of runtime (lock overhead) |
| Context Switch | cs/s, voluntary cs, lock-induced cs | cs/s > 50000 (elevated); voluntary cs > 10000/s (potential lock issue) |
| Scheduler Tuning | sched_latency_ns, sched_min_granularity_ns, sched_wakeup_granularity_ns, sched_tunable_scaling, sched_autogroup_enabled, sched_child_runs_first | sched_min_granularity too small (high scheduling overhead); sched_child_runs_first=1 (fork lock contention); sched_autogroup_enabled=1 (scheduler grouping affects latency) |
| RCU Configuration | rcu_cpu_stall_suppress, rcu_normal | rcu_cpu_stall_suppress=1 (stall detection disabled); rcu_normal affects read-heavy workload |
| CPU Isolation | isolcpus, nohz_full | isolcpus configured (reduced OS jitter but may cause load imbalance); nohz_full (reduced timer interrupts, lower latency) |
| CPU Correlation | sys% vs usr%, softirq% | sys% > usr% (kernel lock); softirq% > 10% (lock activity) |

### Lock Type Classification

| Lock Type | Indicators | Detection Method |
|-----------|-----------|-----------------|
| Futex Userspace | futex WAIT/WAKE ratio, same addr contention | perf futex syscall tracing |
| Kernel Spinlock | high sys%, lock_stat spinlock data | /proc/lock_stat |
| Kernel Mutex/RWSem | D-state processes, wchan=mutex_lock | ps wchan analysis |
| File Lock (flock) | FLOCK/POSIX in /proc/locks | /proc/locks |
| IRQ/Lock Disable | SCHED softirq high | /proc/softirqs |

---

## Phase 3: Bottleneck Identification

### Output Format

```markdown
# OS Lock Bottleneck Analysis Report

## Lock Bottleneck Conclusion
**OS Lock Bottleneck Status**: [EXISTS / DOES NOT EXIST]

## Processes with Lock Bottleneck
| PID | Name | State | Wait Channel | Blocked Time % | CPU% |
|-----|------|-------|-------------|---------------|------|
| [PID1] | [Name] | [S/D/R] | [wchan] | [X]% | [Y]% |

## Key Evidence
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| D-state processes | X | >CPU_count | [CRITICAL/ELEVATED/NORMAL] |
| Futex WAIT/s | X | >5000/s | [CRITICAL/ELEVATED/NORMAL] |
| SCHED softirq/s | X | >50000/s | [CRITICAL/ELEVATED/NORMAL] |
| Lock Wait Time % | X% | >20% | [CRITICAL/ELEVATED/NORMAL] |

## Bottleneck Type
| Type | Severity | Evidence |
|------|----------|----------|
| [Futex Userspace/Kernel Spinlock/File Lock] | [High/Medium/Low] | [Description] |

## Root Cause Inference
**Primary Cause**: [OS-level root cause]
**Affected Components**: [Scheduler/Memory/I/O/Interrupts]
**Inference Confidence**: [High/Medium/Low]

## OS-Level Recommendations
1. [Recommendation 1]
2. [Recommendation 2]
```

---

## Operational Notes

- **basic principle**: All analysis must be specific and evidence-based.
- **Heavyweight Commands**: perf record MUST run sequentially, not concurrently.
- **Prerequisites**: lock_stat requires root; perf_event_paranoid should be 0 or -1.
- **Iteration**: If evidence is insufficient, narrow focus and deepen analysis.
- **Completion**: All phases must be fully executed before concluding.
- **Scope Constraint — OS Level Only**: This skill analyzes ONLY OS-level information. Do NOT collect or interpret application-layer data.
