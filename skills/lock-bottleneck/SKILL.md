---
name: lock-bottleneck
description: OS-level lock performance bottleneck analysis. Analyzes lock contention, futex wait patterns, spinlock contention, and blocking behavior to identify if target business process suffers from OS lock bottlenecks.
---

# OS Lock Bottleneck Analysis

This skill performs comprehensive analysis of OS-level lock performance bottlenecks. It helps diagnose lock-related performance issues including:
- **Futex contention**: Userspace futex wait/wake patterns causing blocking
- **Spinlock contention**: Kernel spinlock saturation causing CPU spin
- **Blocking behavior**: Process/thread blocking on locks, rwsems, mutexes
- **Context switch impact**: Lock-induced context switches and scheduling
- **Run queue stalls**: Time spent waiting to be scheduled due to lock activity

---

## Scope Limitation

**IMPORTANT - Analysis Scope Constraints**:

1. **OS Components Only**: This skill analyzes only OS-native kernel components (e.g., Linux Kernel, Scheduler, Memory Management, I/O Subsystem). Application internal implementation logic is NOT analyzed.

2. **No Application-Level Analysis**: Application code, application configuration, or application algorithms are NOT analyzed. Examples: Redis internal data structures, database SQL logic, application-level lock implementation.

3. **Results Show OS-Level Bottlenecks Only**: Analysis results can only contain OS-level bottleneck indicators and optimization suggestions, such as:
   - Scheduler configuration issues
   - Kernel parameter tuning
   - CPU/Memory/NUMA configuration
   - Interrupt and softirq configuration
   - System resource limits configuration

4. **Application Issues Only Recorded**: If evidence of application-level issues is found during OS-level analysis (e.g., frequent futex waits, application lock contention), it can only be marked as "may be affected by application logic". No application-level diagnosis or suggestions are allowed.

---

## Client Connection and Command Execution

Load the remote-execution skill for standardized SSH connection and command execution:

skill:remote-execution

---

## Phase 1: Environment Preparation

### Step 1.1: System Environment Check

```bash
# Check kernel version (need >= 2.6.25 for futex, >= 3.14 for better lock stats)
uname -r

# Check perf availability
perf --version

# Check perf_event_paranoid (must be <= 2 for most tracepoints)
cat /proc/sys/kernel/perf_event_paranoid

# Check if lock tracing is available
cat /proc/sys/kernel/lock_stat 2>/dev/null || echo "lock_stat not available"

# Check scheduler stats
cat /proc/sys/kernel/sched_schedstats 2>/dev/null
```

**Enable required stats if needed** (requires root):
```bash
echo 1 > /proc/sys/kernel/sched_schedstats
echo 0 > /proc/sys/kernel/perf_event_paranoid
```

### Step 1.2: CPU Topology Analysis

```bash
# CPU count and topology
lscpu

# NUMA information
numactl --hardware
```

---

## Phase 2: Lock Trace Data Collection

### Step 2.1: Identify Target Process

**System Auto-Discovery**: List top CPU consuming processes for user selection.

```bash
# List top 3 CPU-consuming processes
ps -eo pid,comm,%cpu,%mem,state,wchan:32 | sort -k3 -rn | head -10

# Output Example:
#   PID COMMAND         %CPU  %MEM S WCHAN
# 12345 redis-server    25.3  12.5 S futex_wait_queue_meh
# 12346 redis-server    24.8  12.5 S futex_wait_queue_meh
#  2345 mysqld          15.2   8.1 S schedule_timeout
#  3456 nginx            8.3   2.1 R worker_cond_wait
#  4567 node             5.6   3.2 S ep_poll
#  5678 java             4.2  15.3 S futex_wait
#  6789 python           2.1   1.2 S wait_for_page_io
#  7890 docker           1.8   0.9 S-
#  8901 systemd           0.5   0.1 S ep_poll
#  9012 sshd             0.3   0.1 S-
```

**User Selection Required**: Ask user to confirm target process or specify a different PID.

```bash
# If user confirms PID 12345 (redis-server), get detailed info:
pidstat -p 12345 -u -r -d -w 1 5

# Output Example:
# 09:15:32      PID   %usr %system %guest   %wait   %CPU   CPU  Command
# 09:15:33   12345     20.1    5.2    0.0    3.4   25.3     0  redis-server
# 09:15:33   12345     19.8    5.0    0.0    3.2   24.8     1  redis-server
# 09:15:33   12345     20.5    4.8    0.0    3.5   25.3     2  redis-server

# Check process threads
ps -T -p 12345

# Output Example:
#     PID    TID  CMD
#  12345  12345  redis-server
#  12345  12346  redis-server
#  12345  12347  redis-server
#  ...

# Check process state (look for D state = uninterruptible sleep, S = interruptible sleep)
cat /proc/12345/status | grep -E "State|Threads|VmRSS"

# Output Example:
# State:  S (sleeping)
# Threads:        16
# VmRSS:    245678 kB

# Check what the process is waiting on (wchan)
cat /proc/12345/wchan
# Output: futex_wait_queue_meh

cat /proc/12345/stat | awk '{print $3}'
# Output: S
```

**User Interaction**:
```
Top 3 CPU-consuming processes:
1. PID 12345: redis-server (25.3% CPU, 16 threads, state S - waiting on futex)
2. PID 2345: mysqld (15.2% CPU, 32 threads, state S - schedule_timeout)
3. PID 3456: nginx (8.3% CPU, 8 threads, state R - worker_cond_wait)

Please select target process:
- Enter 1, 2, or 3 to select from above
- Or enter a specific PID to analyze
- Or enter a process name to search (e.g., redis, nginx, mysql)
```

**Output format**:
```markdown
### Target Process Information
| PID | Name | PPID | Threads | State | Wchan | CPU% | VmRSS |
|-----|------|------|---------|-------|-------|------|-------|
| 12345 | redis-server | 1 | 16 | S | futex_wait_queue_meh | 25.3 | 245MB |
```

### Step 2.2: System-Wide Lock Activity Baseline

```bash
# vmstat - Check blocked processes (column 'b' shows blocked processes)
vmstat 1 10

# Output Example:
# procs -----------memory---------- ---swap-- -----io---- -system-- --------cpu--------
#  r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
#  2  0      0 12345678  123456  789012    0    0    12    34  567  890  5  2 90  3  0
#  1  1      0 12345678  123456  789012    0    0    10    28  543  876  4  2 91  3  0
#  0  2      0 12345678  123456  789012    0    0    15    45  598  920  3  2 92  3  0
#
# Key columns:
# - r: runnable processes (should be < CPU count normally)
# - b: blocked processes (THIS IS KEY - high values indicate lock blocking)
# - in: interrupts
# - cs: context switches

# pidstat -w - Check per-process context switches and waiting
pidstat -w 1 10

# Output Example:
# 09:15:32      PID   cswch/s nvcswch/s  Command
# 09:15:33     12345   1523.00      0.00  redis-server
# 09:15:33     12346   1489.00      0.00  redis-server
# 09:15:33        12     45.00      0.00  kworker/3:1H
# 09:15:33         1     12.00      0.00  systemd
#
# cswch/s = voluntary context switches (includes lock waits)
# nvcswch/s = non-voluntary context switches (preemption)
```

### Step 2.3: Futex Activity Analysis

```bash
# Record futex syscalls for target process
# Using perf to trace futex enter/exit
perf record -a -e syscalls:sys_enter_futex -e syscalls:sys_exit_futex -o /tmp/futex.data -- sleep ${DURATION:-30} &

# Alternative: strace futex calls (overhead, use carefully)
strace -c -f -p <PID> 2>&1 | head -50

# Check futex wait queue lengths during peak
cat /proc/<PID>/fd - 2>/dev/null | wc -l
```

**Output Example for futex analysis**:
```markdown
### Futex Wait Patterns
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Futex waits/sec | | | |
| Futex wakes/sec | | | |
| Wait-to-wake ratio | | >2:1 | |
| Avg wait duration | | >100ms | |
```

### Step 2.4: Context Switch and Scheduling Correlation

```bash
# Record scheduling with lock events
perf record -a -e sched:sched_switch -e sched:sched_wakeup -e syscalls:sys_enter_futex -e syscalls:sys_exit_futex -- sleep ${DURATION:-30}

# Check run queue length over time
vmstat 1 30

# mpstat - Check per-CPU utilization
mpstat -P ALL 1 10

# Output Example:
# 10:30:45     CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
# 10:30:46       0    15.23    0.00    5.67    2.34    1.23    8.90    0.00    0.00    0.00   66.63
# 10:30:46       1    45.12    0.00   12.34    0.00    0.56    4.23    0.00    0.00    0.00   37.75
# 10:30:46       2    78.90    0.00   15.67    0.00    0.89    3.45    0.00    0.00    0.00    1.09
# 10:30:46       3    12.34    0.00    3.21    8.90    0.45    2.12    0.00    0.00    0.00   72.98
#
# CPU 2 at 94.57% utilization (usr+sys) - check if lock contention
```

---

## Phase 3: Lock Bottleneck Analysis

### Step 3.1: Blocked Process Analysis

```bash
# Identify processes in blocked state (D = uninterruptible, S = interruptible)
ps -eo pid,comm,state,wchan:32,cmd | grep -E "^[0-9]+.*[DS]"

# Output Example:
#   PID COMMAND         S WCHAN                COMMAND
# 12345 redis-server    S futex_wait_queue_meh [redis-server]
# 12346 redis-server    S futex_wait_queue_meh [redis-server]
#  2345 mysqld          D schedule_timeout      [mysqld]
#
# Key:
# - S = interruptible sleep (waiting on lock, can be interrupted)
# - D = uninterruptible sleep (usually I/O, but can be lock)
# - WCHAN shows what kernel function they're waiting in

# Count blocked processes per wait channel
ps -eo state,wchan:32 | awk '/^[DS]$/ {print $2}' | sort | uniq -c | sort -rn | head -20

# Output Example:
#     45 futex_wait_queue_meh
#     12 schedule_timeout
#      8 wait_for_page_io
#      3 rcu_gp_kthread
```

### Step 3.2: Futex Contention Detection

```bash
# Analyze perf data for futex contention patterns
perf report --stdio --no-children -i /tmp/futex.data 2>/dev/null | head -50

# Check futex wait queue lengths
cat /proc/sys/kernel/futex_wake_mac 2>/dev/null || echo "not available"

# Analyze futex syscall patterns
perf script -i /tmp/futex.data 2>/dev/null | grep -E "futex" | head -100

# Output Example (perf script futex events):
#     redis-server 12345 [000] 342783.256897: sys_exit_futex: 0x7f9c00000000 = 0
#     redis-server 12346 [001] 342783.256922: sys_exit_futex: 0x7f9c00000000 = 0
#     redis-server 12345 [000] 342783.257011: sys_enter_futex: uaddr=0x7f9c00000000, op=0 (FUTEX_WAIT), val=0
#
# Interpretation:
# - High frequency of FUTEX_WAIT followed by quick wake = lock acquisition attempts
# - Long FUTEX_WAIT durations = lock hold time is high
# - Multiple processes waiting on same uaddr = lock contention

# Check target process futex wait time
perf script -i /tmp/futex.data 2>/dev/null | grep -A 2 "enter_futex.*$TARGET_PID" | head -50
```

**Key futex metrics**:
```markdown
### Futex Contention Metrics
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Futex WAIT frequency | | >5000/s suspicious | |
| Avg futex wait duration | | >10ms suspicious | |
| Wait/wake ratio | | >2:1 = contention | |
| Same addr waits | | >10 = contention | |
```

### Step 3.3: Lock-Induced Context Switch Analysis

```bash
# Correlate context switches with lock events
perf sched script | grep -E "sched_switch|futex" | head -200

# Output Example:
#  redis-ser 12345 [001] 342783.256897: sched_switch: prev_comm=redis-server prev_pid=12345 prev_prio=120 prev_state=S ==> next_comm=kworker/0:0 next_pid=2345 next_prio=98
#  redis-ser 12345 [001] 342783.256900: sys_enter_futex: uaddr=0x7f9c00000000, op=0 (FUTEX_WAIT), val=0
#  redis-ser 12346 [002] 342783.256922: sched_switch: prev_comm=redis-server prev_pid=12346 prev_prio=120 prev_state=S ==> next_comm=redis-server next_pid=12345 next_prio=120
#
# Analysis:
# - Process state S (interruptible sleep) before switch out
# - Immediately followed by futex_wait = blocked on lock
# - Next process to run is kworker (preempted by kworker)

# Calculate lock-induced voluntary context switches
perf sched script | grep -B 1 "sys_enter_futex.*$TARGET_PID" | grep "prev_state=S" | wc -l

# Output Example:
# 15234
```

### Step 3.4: Spinlock Contention Detection

```bash
# Check for spinlock-related CPU spinning
# High sys% without high user% = possible spinlock contention
mpstat 1 5

# Output Example:
# 10:30:45     CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle
# Average:      all   25.45    0.00   35.67    1.23    2.34    8.90    0.00    0.00    0.00   26.41
#
# Analysis:
# - sys% (35.67%) is much higher than usr% (25.45%)
# - soft% (8.90%) indicates softirq processing
# - Could indicate kernel lock contention

# Check for excessive softirq time (soft %)
# softirq can indicate lock handling overhead
cat /proc/softirqs

# Output Example:
#                     CPU0       CPU1       CPU2       CPU3
#           HI:          0          0          0          0
#       TIMER:    1023456    1034567    1023567    1034567
#       NET_TX:       234        123        345        234
#       NET_RX:     56789      45678      34567      67890
#       BLOCK:       1234       2345       3456       4567
#   IRQ_POLL:          0          0          0          0
#     TASKLET:      1234       2345       3456       4567
#       SCHED:     345678     234567     456789     345678
#       HRTIMER:      234        345        456        567
#         RCU:     567890     456789     678901     567890
#
# High SCHED softirq = lock activity
```

---

## Phase 4: Lock Bottleneck Identification

### Step 4.1: Lock Wait Time Analysis

```bash
# Estimate time spent waiting on locks
# Using perf sched timehist to see wait times
perf sched timehist 2>/dev/null | head -100

# Output Example:
#             time    cpu  task name                  pid  tid  prio    wait time  sch delay   run time
#                          [tid/pid]                          (msec)     (msec)     (msec)
# --------------- ------  ------------------------------  -----  -----  -----  ---------  ---------  ---------
#   342783.256897 [0000]  redis-server                   12345  12345    120      0.000      0.000      0.000 
#   342783.256900 [0000]  redis-server                   12345  12345    120      0.000      0.002      0.025 
#   342783.257117 [0002]  redis-server                   12346  12346    120      1.234      0.003      0.456 
#   342783.258900 [0001]  redis-server                   12345  12345    120      5.678      0.001      0.123 
#
# Columns:
# - wait time: time spent in blocked state (includes lock waiting)
# - sch delay: time from wakeup to actually running (scheduling latency)
# - run time: actual CPU execution time
#
# High wait time + futex activity = lock contention

# Calculate total wait time for target process
perf sched timehist 2>/dev/null | grep " redis-server" | awk '{sum_wait+=$8; count++} END {print "Total wait:", sum_wait, "ms, Count:", count, "Avg:", sum_wait/count}'
```

### Step 4.2: Lock Bottleneck Categorization

```bash
# Categorize lock issues based on evidence

# Category 1: Futex Userspace Lock Contention
# Evidence: High futex WAIT frequency, multiple processes waiting on same addr
perf script -i /tmp/futex.data 2>/dev/null | grep "enter_futex.*FUTEX_WAIT" | awk '{print $6}' | sort | uniq -c | sort -rn | head -20

# Output Example:
#     1234 uaddr=0x7f9c00000000   <-- same address, high contention
#      567 uaddr=0x7f9c00000010
#      123 uaddr=0x7f9c00000020

# Category 2: Kernel Lock Contention (rwsem, mutex, spinlock)
# Evidence: High sys% CPU, processes in kernel state
ps -eo pid,comm,state,cmd | awk '$3=="R" || $3=="D"' | head -20

# Check kernel locks via /proc/lock_stat if available
cat /proc/lock_stat 2>/dev/null | head -50

# Category 3: File/FLOCK Contention
# Evidence: High flock/posix lock activity
cat /proc/locks | awk '$2=="FLOCK" || $2=="POSIX"' | head -20
```

**Output format**:
```markdown
### Lock Bottleneck Categories
| Category | Evidence Found | Severity | Impact |
|----------|---------------|----------|--------|
| Futex Userspace | | | |
| Kernel Spinlock | | | |
| Kernel Mutex/RWSem | | | |
| File Lock | | | |
| IRQ/Lock Disable | | | |
```

### Step 4.3: Lock Performance Impact Calculation

```bash
# Calculate time lost to lock contention

# From perf sched timehist
TOTAL_WAIT=$(perf sched timehist 2>/dev/null | grep " $TARGET_PID " | awk '{sum+=$8} END {print sum}')
TOTAL_RUNTIME=$(perf sched timehist 2>/dev/null | grep " $TARGET_PID " | awk '{sum+=$10} END {print sum}')
SWITCH_COUNT=$(perf sched timehist 2>/dev/null | grep " $TARGET_PID " | wc -l)

# Calculate lock wait percentage
if [ -n "$TOTAL_RUNTIME" ] && [ "$TOTAL_RUNTIME" != "0" ]; then
    LOCK_WAIT_PCT=$(echo "scale=2; $TOTAL_WAIT / ($TOTAL_WAIT + $TOTAL_RUNTIME) * 100" | bc 2>/dev/null)
    echo "Lock Wait Percentage: ${LOCK_WAIT_PCT}%"
fi

# Output Example:
# Total Wait Time: 1234.56 ms
# Total Run Time: 5678.90 ms
# Lock Wait Percentage: 17.86%
```

---

## Phase 5: Comprehensive Analysis Report

### Step 5.1: Generate Summary Report

```markdown
# OS Lock Bottleneck Analysis Report

## Lock Bottleneck Conclusion

**OS Lock Bottleneck Status**: [EXISTS / DOES NOT EXIST]

### If EXISTS - Lock Bottleneck Details:

## Processes with Lock Bottleneck
| PID | Name | State | Wait Channel | Blocked Time % | CPU% |
|-----|------|-------|-------------|---------------|------|
| [PID1] | [Name] | [S/D/R] | [wchan] | [X]% | [Y]% |
| [PID2] | [Name] | [S/D/R] | [wchan] | [X]% | [Y]% |

## Lock Bottleneck Type
| Type | Severity | Evidence |
|------|----------|----------|
| [Futex/Kernel/File/IRQ] | [High/Medium/Low] | [Evidence summary] |

## Bottleneck Evidence
```bash
# Evidence 1: Process blocking
[ps command output showing blocked processes]

# Evidence 2: Lock contention indicators
[futex/kernel lock metrics]

# Evidence 3: Context switch correlation
[perf sched or pidstat output]
```

## Root Cause Inference
**Primary Cause**: [OS-level root cause inference]
**Supporting Evidence**: [Evidence that supports this inference]
**Affected Components**: [e.g., Scheduler, Memory, I/O, Interrupts]

---

## Key Findings (Supporting Data)

### 1. Blocking Behavior
- **Blocked Time**: [X] ms ([Y]% of total time)
- **Block Frequency**: [X] events/second
- **Primary Wait Channel**: [wchan]
- **Status**: [Normal/Elevated/Critical]

### 2. Lock Contention Intensity
- **Lock Type**: [Futex/Kernel/File]
- **Contention Ratio**: [Wait/Wake ratio]
- **Hottest Lock Address**: [addr]
- **Status**: [Normal/Elevated/Critical]

### 3. Context Switch Impact
- **Voluntary CS**: [X] ([Y]/s)
- **Lock-induced CS**: [X] ([Y]/s)
- **Context Switch Rate**: [X]/s
- **Status**: [Normal/Elevated/Critical]

### 4. CPU Correlation
- **Sys% vs Usr%**: [X]% vs [Y]% 
- **Softirq%**: [X]%
- **Run Queue**: [X] processes
- **Status**: [Normal/Elevated/Critical]

## OS-Level Recommendations Only

**NOTE**: All recommendations are OS-level only. Application-level suggestions are not allowed.

### Immediate Actions (OS-Level)
1. [OS-level action 1]
2. [OS-level action 2]

### Optimization Suggestions (OS-Level)
1. [OS-level suggestion 1]
2. [OS-level suggestion 2]

## Appendix
- Data Collection Parameters: [params]
- System Configuration: [config]
```

---

## Key Commands Summary

| Command | Purpose | Output Example |
|---------|---------|----------------|
| `vmstat 1 10` | System-wide blocked process count | `b: 2` (blocked processes) |
| `pidstat -w 1 5` | Per-process context switches | `cswch/s: 1523` |
| `ps -eo state,wchan` | Processes waiting on locks | `S futex_wait_queue_meh` |
| `perf sched timehist` | Wait time per scheduling event | `wait time: 5.678ms` |
| `perf script -i /tmp/futex.data` | Futex syscall trace | `sys_enter_futex: FUTEX_WAIT` |
| `mpstat 1 5` | Per-CPU utilization | `sys%: 35.67%` |
| `cat /proc/locks` | Current file locks | `FLOCK ADVISORY WRITE` |
| `cat /proc/softirqs` | Softirq frequency | `SCHED: 345678` |

---

## Output Template

```markdown
# OS Lock Bottleneck Analysis - Final Report

## Lock Bottleneck Conclusion

**OS Lock Bottleneck Status**: [EXISTS / DOES NOT EXIST]

---

### If EXISTS - Lock Bottleneck Details:

## Processes with Lock Bottleneck
| PID | Name | State | Wait Channel | Blocked Time % | CPU% |
|-----|------|-------|-------------|---------------|------|
| [PID1] | [Name] | [S/D/R] | [wchan] | [X]% | [Y]% |
| [PID2] | [Name] | [S/D/R] | [wchan] | [X]% | [Y]% |

## Lock Bottleneck Type
| Type | Severity | Evidence |
|------|----------|----------|
| [Futex Userspace] | High | Multiple processes waiting on same futex address |
| [Kernel Spinlock] | Medium | High sys% without corresponding I/O |
| [Kernel Mutex/RWSem] | Medium | Processes blocked in kernel |
| [File Lock (flock)] | Low | Heavy flock activity in /proc/locks |
| [IRQ/Softirq Lock] | Medium | High SCHED softirq |

## Bottleneck Evidence
```bash
# Evidence 1: Process blocking (ps -eo state,wchan)
[ps output showing blocked processes and wait channels]

# Evidence 2: Futex contention (perf script | grep futex)
[futex wait/wake patterns, hot addresses]

# Evidence 3: Context switch correlation (perf sched timehist)
[wait time vs run time analysis]
```

## Root Cause Inference
**Primary Cause**: [OS-level root cause]
**Supporting Evidence**: [Evidence that supports this inference]
**Affected OS Components**: [Scheduler/Memory/I/O/Interrupts/NUMA]
**Inference Confidence**: [High/Medium/Low]

---

## Target Process Summary
| Attribute | Value |
|-----------|-------|
| PID | [PID] |
| Name | [Name] |
| State | [State] |
| Threads | [Count] |
| VmRSS | [MB] |

## System Environment
| Attribute | Value |
|-----------|-------|
| CPU Count | [Count] |
| Kernel Version | [Version] |
| Perf Paranoid | [Level] |
| Lock Stats | [Enabled/Disabled] |

## Lock Bottleneck Metrics

### Blocking Behavior
| Metric | Value | Normal Range | Status |
|--------|-------|--------------|--------|
| Blocked Time % | | <10% | |
| Block Frequency | | <100/s | |
| Avg Block Duration | | <10ms | |
| Max Block Duration | | <100ms | |

### Lock Contention Intensity
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Futex WAIT/s | | <5000/s | |
| Wait/Wake Ratio | | <2:1 | |
| Hottest Lock Addr Waits | | <10 | |
| Lock Wait Time % | | <20% | |

### Context Switch Impact
| Metric | Value | Normal Range | Status |
|--------|-------|--------------|--------|
| Voluntary CS/s | | <10000/s | |
| Lock-induced CS | | | |
| Context Switch Rate | | <50000/s | |

### CPU Correlation
| Metric | Value | Interpretation |
|--------|-------|----------------|
| Sys% vs Usr% | | sys > usr = kernel lock |
| Softirq% | | >10% = high lock activity |
| Run Queue Length | | >CPU count = contention |

## OS-Level Recommendations Only

**NOTE**: All recommendations are OS-level only. No application-level suggestions allowed.

### Immediate Actions (OS-Level)
1. [OS-level action 1]
   - Command: [Command]
   - Expected Impact: [Impact]

### Optimization Suggestions (OS-Level)
1. [OS-level suggestion 1]
   - Rationale: [Rationale]
   - Implementation: [Steps]

## Appendix

### Reference Values
- Normal blocked time %: <10%
- Normal voluntary CS: <10000/s
- Normal futex WAIT: <5000/s
- Normal sys% < usr% (or sys < 30%)

### Key Files Checked
- /proc/locks - File locks
- /proc/softirqs - Soft interrupt statistics
- /proc/schedstat - Scheduler statistics
- /proc/<pid>/wchan - Process wait channel
```

---

## Example Output: Complete Analysis Report

see [references/lock_analysis_report_example.md] for complete report example.
