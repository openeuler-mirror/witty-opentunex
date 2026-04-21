---
name: schedule-trace-analysis
description: Process scheduling trace analysis using perf to analyze target business process scheduling behavior, including scheduling out frequency, scheduling in latency, and preempting tasks identification with global scheduling perspective.
---

# Process Scheduling Trace Analysis

This skill performs comprehensive analysis of process scheduling behavior using Linux perf tools. It helps diagnose scheduling-related performance issues by analyzing:
- **Scheduling out frequency**: How often the target process is being preempted or yields CPU
- **Scheduling in latency**: Time delay from when process becomes runnable to when it actually gets CPU
- **Preempting tasks**: Which tasks are competing for CPU time and causing scheduling interference
- **Global scheduling analysis**: System-wide scheduling perspective to understand overall CPU time distribution

---

## Client Connection and Command Execution

Load the remote-execution skill for standardized SSH connection and command execution:

skill:remote-execution

---

## Phase 1: Environment Preparation

### Step 1.1: Scheduler Tracing Prerequisites

```bash
# Check and enable scheduler tracing prerequisites
cat /proc/sys/kernel/sched_schedstats
cat /proc/sys/kernel/perf_event_paranoid
```

**Enable scheduler stats if needed** (requires root):
```bash
echo 1 > /proc/sys/kernel/sched_schedstats
echo 0 > /proc/sys/kernel/perf_event_paranoid
```


---

## Phase 2: Scheduling Trace Data Collection

### Duration Configuration

Trace duration: 15 seconds by default, or use user-input duration.

### Step 2.1: Target Process Scheduling Attributes

**User Input Required**: Get target process information from context or user, e.g. redis/nginx/mysql.

```bash
# Check process threads
ps -T -p <PID>

# Check process affinity and priority
taskset -pc <PID>
chrt -p <PID>
```

**Output format**:
```markdown
### Target Process Information
| PID | Name | Threads | Priority | Nice | Affinity |
|-----|------|---------|----------|------|----------|
```

### Step 2.2: Perf Sched Recording

**Start perf sched recording**:

```bash
# Record all scheduling events with context (default 15s)
# Local execution:
perf sched record -a -e sched:sched_switch -e sched:sched_wakeup -e sched:sched_wakeup_new -e sched:sched_migrate_task -- sleep ${DURATION:-15}

# Alternative: Record more comprehensive events
perf sched record -a -e sched:* -- sleep ${DURATION:-15}

# For specific process focus
perf sched record -p <PID> -- sleep ${DURATION:-15}
```

**Parameters**:
- `-a`: Record system-wide (recommended for global analysis)
- `-p <PID>`: Record specific process only (use when target is known)
- `-- sleep ${DURATION:-15}`: Collection duration (default 15 seconds)

### Step 2.3: Verify Data Collection

```bash
# Check if perf.data was created
ls -lh perf.data

# Quick preview of events
perf sched script | head -100
```

**Data Size Check**:
```bash
# Check file size (should be reasonable)
du -h perf.data

# Large files (>1GB) may need longer analysis time
```

---

## Phase 3: Scheduling Out Frequency Analysis

### Step 3.1: Global Scheduling Statistics

```bash
# Get overall scheduler statistics
perf sched latency

# Output Example:
#  -------------------------------------------------------------------------------------------------------------------------------------------
#   Task                  |   Runtime ms  | Switches | Avg delay ms    | Max delay ms    | Max delay start           | Max delay end          |
#  -------------------------------------------------------------------------------------------------------------------------------------------
#   kworker/15:1:643040   |      0.102 ms |        1 | avg:   0.066 ms | max:   0.066 ms | max start: 342792.283196 s | max end: 342792.283262 s
#   tokio-runtime-w:(5)   |    183.881 ms |       30 | avg:   0.061 ms | max:   0.582 ms | max start: 342803.433233 s | max end: 342803.433815 s
#   kworker/21:0:643182   |      0.089 ms |        1 | avg:   0.048 ms | max:   0.048 ms | max start: 342812.779246 s | max end: 342812.779294 s

# Get detailed latency breakdown
perf sched latency --sort max,avg,pid

# Output Example:
#  -------------------------------------------------------------------------------------------------------------------------------------------
#   Task                  |   Runtime ms  | Switches | Avg delay ms    | Max delay ms    | Max delay start           | Max delay end          |
#  -------------------------------------------------------------------------------------------------------------------------------------------
#   opencode:(9)          |  10120.616 ms |    26353 | avg:   0.012 ms | max:  17.447 ms | max start: 342783.258915 s | max end: 342783.276362 s
#   HeapHelper:(35)       |   4322.596 ms |   405846 | avg:   0.010 ms | max:   5.163 ms | max start: 342795.776875 s | max end: 342795.782038 s
#   Worker:(5)            |    227.162 ms |     1600 | avg:   0.016 ms | max:   1.423 ms | max start: 342797.255394 s | max end: 342797.256817 s


# Get time-based scheduling history
perf sched timehist

# Output Example:
#            time    cpu  task name                       wait time  sch delay   run time
#                         [tid/pid]                          (msec)     (msec)     (msec)
# --------------- ------  ------------------------------  ---------  ---------  ---------
#   342783.256897 [0000]  perf[642937]                        0.000      0.000      0.000 
#   342783.256922 [0000]  migration/0[13]                     0.000      0.002      0.025 
#   342783.256992 [0001]  perf[642937]                        0.000      0.000      0.000 
#   342783.257011 [0001]  migration/1[16]                     0.000      0.003      0.018 
#   342783.257117 [0002]  perf[642937]                        0.000      0.000      0.000 

#
# Columns:
# - time: Timestamp in seconds when the scheduling event occurred.
# - cpu: CPU core where the event happened.
# - task name: Name of the process/task being scheduled, followed by its thread ID/process ID
# - wait time: Time spent waiting to be scheduled, from when task was last scheduled out to when it was scheduled back in
# - sch delay: Scheduling delay, from woken-up to started running on a CPU, high value indicates CPU resource contention
# - run time: Time the task spent running on the CPU during this scheduling period

# Get time-based scheduling history on certain CPUs or certain tasks
perf sched timehist --cpu <cpu id>
perf sched timehist --tid <tid>
```

**Key metrics to extract**:
```markdown
### Global Scheduling Metrics
| Metric | Value | Normal Range |
|--------|-------|--------------|
| Total Events | 45,678 | - |
| Total Runtime | 28.45s | - |
| Avg Runtime per Task | 2.45ms | 0.5-10ms |
| Max Runtime | 15.2ms | <50ms |
| Context Switches | 45,678 | <10000/s/core |
```

### Step 3.2: Target Process Scheduling Out Analysis

```bash
# Filter events for target process
perf sched script | grep "pid=<PID>"

# Output Example:
#            perf 642937 [000] 342783.256897:       sched:sched_switch: prev_comm=perf prev_pid=642937 prev_prio=120 prev_state=R+ ==> next_comm=migration/0 next_pid=13 next_prio=0
#     migration/0     13 [000] 342783.256922:       sched:sched_switch: prev_comm=migration/0 prev_pid=13 prev_prio=0 prev_state=S ==> next_comm=swapper/0 next_pid=0 next_prio=120
#            perf 642937 [001] 342783.256992:       sched:sched_switch: prev_comm=perf prev_pid=642937 prev_prio=120 prev_state=R+ ==> next_comm=migration/1 next_pid=16 next_prio=0
#     migration/1     16 [001] 342783.257011:       sched:sched_switch: prev_comm=migration/1 prev_pid=16 prev_prio=0 prev_state=S ==> next_comm=swapper/1 next_pid=0 next_prio=120
#            perf 642937 [002] 342783.257117:       sched:sched_switch: prev_comm=perf prev_pid=642937 prev_prio=120 prev_state=R+ ==> next_comm=migration/2 next_pid=21 next_prio=0
#
# Fields explanation:
# - timestamp: seconds.microseconds since epoch
# - prev_comm: task being switched out
# - prev_pid: PID of task being switched out
# - prev_prio: priority of task being switched out
# - prev_state: state of task being switched out (R=Running, R+=Ready, S=Sleeping, D=Uninterruptible)
# - next_comm: task being switched in
# - next_pid: PID of task being switched in
# - next_prio: priority of task being switched in
# Note: Event names have "sched:" prefix (e.g., sched:sched_switch, sched:sched_wakeup)

# Count scheduling out events for target process
perf sched script | grep "sched_switch.*prev_pid=<PID>" | wc -l

# Example output:
# 15234

# Calculate scheduling out frequency (events per second)
# Events count / Collection duration (default 15s)

# Example:
# 15234 events / 15 seconds = 1015.6 events/second

# Analyze scheduling out patterns over time
perf sched script | grep "sched_switch.*prev_pid=<PID>" | awk '{print $1, $3, $4}'

# Output Example:
# 12345.123456 prev_comm=redis-server prev_state=S
# 12345.124123 prev_comm=redis-server prev_state=R
# 12345.125456 prev_comm=redis-server prev_state=R
# 12345.126789 prev_comm=redis-server prev_state=S
```

**Analysis criteria**:
- **Normal range**: Depends on workload type
  - CPU-intensive: 10-100 times/second
  - I/O-intensive: 100-1000 times/second
  - High-frequency: >1000 times/second may indicate issues

**Output format**:
```markdown
### Target Process Scheduling Out Analysis
| Metric | Value | Status |
|--------|-------|--------|
| Total Schedule Out Events | | |
| Schedule Out Frequency (events/sec) | | |
| Collection Duration | | |
| CPU Utilization During Collection | | |
| Normal Range | | |

**Assessment**: [Normal/Elevated/Abnormal]
```

### Step 3.3: Comparison with System Average

```bash
# Calculate average scheduling frequency for all processes
perf sched script | grep "sched_switch" | awk '{for(i=1;i<=NF;i++) if($i ~ /^prev_comm=/) print $i}' | sort | uniq -c | sort -rn | head -20

# Output Example:
#  511396 prev_comm=HeapHelper
#   38634 prev_comm=opencode
#   10871 prev_comm=swapper/9
#    8973 prev_comm=swapper/0
#    7876 prev_comm=node
#    6868 prev_comm=swapper/1
#    4352 prev_comm=swapper/2

# Extract counts for comparison
perf sched script | grep "sched_switch" | awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn | head -10

# Output Example:
#   70908 476466
#   70726 476467
#   69831 476470
#   68715 476469
#   68043 476468
#   66898 476471
#   65693 476472
#   64263 0
#   35681 476464
#    3727 4067

# Compare target process frequency with system average
# Calculate: Target Frequency / System Average

# Example (15s collection):
# Target PID 1234: 1015.6 events/sec (15,234 events / 15s)
# System average (from above): ~75 events/sec
# Ratio: 1015.6 / 75 = 6.77x (elevated)
```

**Output**:
```markdown
### Scheduling Frequency Comparison
| Process | Frequency (events/sec) | Relative to Target |
|---------|------------------------|-------------------|
| Target Process (redis-server) | 1015.6 | 1.0x |
| nginx worker | 296.8 | 0.58x |
| systemd | 189.2 | 0.37x |
| kworker/0:2 | 152.2 | 0.30x |
| postgres | 115.2 | 0.23x |
```

**Analysis**:
- Target process frequency > 2x system average indicates elevated preemption
- Need to investigate preemptors and their CPU consumption

---

## Phase 4: Scheduling In Latency Analysis

### Step 4.1: Extract Scheduling In Latency Data

```bash
# Use perf sched latency to get wait times
perf sched latency -p <PID>

# Output Example:
#  Task ID   Task Name          Prio     Switches    Avg Run    Max Run    Avg Delay   Max Delay
#  --------  -----------------  ------  ----------  ---------  ---------  ----------  ----------
#  1234      redis-server       120      15,234        2.45ms     15.2ms        3.21ms     28.4ms
#
# Analysis:
# - Avg Delay (Avg Sch Delay): 3.21ms - average time from wake-up to schedule-in
# - Max Delay: 28.4ms - worst case scheduling delay
# - This is the "scheduling in latency"

# Alternative: Extract wake-up to run latency
perf sched script | grep -A 1 "sched_wakeup.*pid=<PID>" > wakeup_events.txt

# Output Example:
#   process_name1 642937 [000] 342783.256887: sched:sched_stat_runtime: comm=perf pid=642937 runtime=75410 [ns] vruntime=1229281026892 [ns]
#   process_name2 642937 [000] 342783.256894:       sched:sched_waking: comm=migration/0 pid=13 prio=0 target_cpu=000
#   process_name3 642937 [000] 342783.256897:       sched:sched_switch: prev_comm=perf prev_pid=642937 prev_prio=120 prev_state=R+ ==> next_comm=migration/0 next_pid=13 
#   process_name4 642930 [054] 342783.891895:   sched:sched_wakeup_new: comm=cpuUsage.sh pid=642940 prio=120 target_cpu=055
#
# Note: Event names in openEuler use "sched:sched_wakeup_new" instead of "sched_wakeup"
# Other wake-up events: sched:sched_waking, sched:sched_wakeup
#
# Time calculation:
# - sched_wakeup_new at 342783.891895
# - sched_switch (next) at 342783.892123
# - Latency = 342783.892123 - 342783.891895 = 0.000228s = 0.228ms
#
# This is the actual scheduling delay for this instance

# Parse scheduling latency from sched_switch
perf sched timehist | grep <PID>

# Output Example:
#  time            cpu  task name                     pid  tid  prio    wait time  sch delay  run time
#  1234567890.123    0  redis-server                  1234  1234   120      1.23ms     2.34ms     8.56ms
#  1234567890.131    1  redis-server                  1234  1235   120      0.89ms     1.23ms     3.45ms
#  1234567890.138    0  redis-server                  1234  1234   120      2.12ms     4.56ms     12.3ms
#  1234567890.145    1  redis-server                  1234  1235   120      0.45ms     0.89ms     2.34ms
#  1234567890.152    0  redis-server                  1234  1234   120     15.67ms    28.45ms     8.90ms
#
# Columns explanation:
# - wait time: time spent waiting (not directly scheduling latency)
# - sch delay: scheduling delay (this is the key metric for "scheduling in latency")
# - run time: actual CPU execution time
#
# Analysis:
# - Average sch delay: (2.34+1.23+4.56+0.89+28.45)/5 = 7.49ms
# - Max sch delay: 28.45ms (outlier)
# - Most delays are <5ms, but one is 28.45ms (investigate what happened)
```

**Key latency metrics**:
- **Wait time**: Time from wake-up to first schedule-in
- **Run queue time**: Time spent in run queue
- **Total latency**: Time from task becomes runnable to actually runs
- **sch delay**: Most important metric - time from task becomes runnable to actually gets CPU

### Step 4.2: Latency Distribution Analysis

```bash
# Get latency statistics
perf sched latency --sort max | head -30

# Output Example:
#  Task ID   Task Name          Prio     Switches    Avg Run    Max Run    Avg Delay   Max Delay
#  --------  -----------------  ------  ----------  ---------  ---------  ----------  ----------
#  1234      redis-server       120      15,234        2.45ms     15.2ms        3.21ms     28.4ms
#  5678      nginx worker       120       8,901        1.12ms      8.9ms        4.23ms     45.6ms
#  9012      kworker/3:0         50       12,345        0.23ms      2.1ms        8.45ms     56.7ms

# Calculate latency distribution (P50, P90, P95, P99)
# Use the provided script for automated analysis:
bash scripts/analyze_latency_dist.sh <PID>

# Or calculate manually:
perf sched timehist | grep <PID> | awk '{print $8}' | sort -n | awk '
BEGIN { count=0 }
{ vals[count++]=$1 }
END {
  print "P50:", vals[int(count*0.5)]
  print "P90:", vals[int(count*0.9)]
  print "P95:", vals[int(count*0.95)]
  print "P99:", vals[int(count*0.99)]
}'

# Output Example (manual calculation):
# P50: 0.034ms
# P90: 0.892ms
# P95: 1.234ms
# P99: 5.678ms

# Analyze latency histogram
perf sched timehist | grep <PID> | awk '{latency=$8; bucket=int(latency/1000); freq[bucket]++} END {for (b in freq) print b*1000"-"(b+1)*1000"ms:", freq[b]}'

# Output Example:
# 0-1ms: 4567
# 1-5ms: 8901
# 5-10ms: 2345
# 10-20ms: 567
# 20-30ms: 123
# 30-40ms: 45
# 40-50ms: 12
# 50-60ms: 3
# >60ms: 1

# Interpretation:
# - 4567+8901 = 13468 events (88%) have latency <5ms (good)
# - 2345 events (15%) have latency 5-10ms (acceptable)
# - 567+123+45+12+3+1 = 751 events (5%) have latency >10ms (investigate)
# - 1 event >60ms (outlier, critical to investigate)
```

### Step 4.3: Latency Outlier Analysis

```bash
# Identify high latency events (>10ms, >50ms, >100ms)
perf sched timehist | grep <PID> | awk '$8 > 10000 {print $0}'

# Output Example (latency in column 8, in microseconds):
#  time            cpu  task name                     pid  tid  prio    wait time  sch delay  run time
#  1234567890.152    0  redis-server                  1234  1234   120      15.67ms    28.45ms     8.90ms
#  1234567895.234    1  redis-server                  1234  1235   120      12.34ms    45.67ms     6.78ms
#  1234567898.456    0  redis-server                  1234  1234   120      23.45ms    89.12ms    10.23ms
#
# Note: Column 8 is "sch delay" in ms, column 7 is "wait time" in ms
# For filtering, use appropriate column index

# Analyze what causes high latency
perf sched script | grep -B 5 -A 5 <PID> | grep -E "sched_switch|sched_wakeup"

# Output Example (around a high latency event):
# redis-server 1234 [001] 12345.152000: sched_switch: prev_comm=redis-server prev_pid=1234 prev_prio=120 prev_state=S ==> next_comm=kworker/0:0 next_pid=2345 next_prio=98
# redis-server 1234 [001] 12345.152100: sched_wakeup: comm=redis-server pid=1234 prio=120 target_cpu=001
# redis-server 1234 [001] 12345.154000: sched_switch: prev_comm=kworker/0:0 prev_pid=2345 prev_prio=98 prev_state=R ==> next_comm=kworker/1:1 next_pid=3456 next_prio=98
# redis-server 1234 [001] 12345.156000: sched_switch: prev_comm=kworker/1:1 prev_pid=3456 prev_prio=98 prev_state=R ==> next_comm=systemd-journal next_pid=5678 next_prio=98
# redis-server 1234 [001] 12345.157000: sched_wakeup: comm=ksoftirqd/1 pid=4567 prio=98 target_cpu=001
# redis-server 1234 [001] 12345.158000: sched_switch: prev_comm=systemd-journal prev_pid=5678 prev_prio=98 prev_state=R ==> next_comm=ksoftirqd/1 next_pid=4567 next_prio=98
# redis-server 1234 [001] 12345.159000: sched_switch: prev_comm=ksoftirqd/1 prev_pid=4567 prev_prio=98 prev_state=R ==> next_comm=redis-server next_pid=1234 next_prio=120
#
# Analysis:
# - redis-server woke up at 12345.152100
# - But didn't get scheduled until 12345.159000 (6.9ms later)
# - During this time: kworker/0:0, kworker/1:1, systemd-journal, ksoftirqd/1 ran
# - These are the preemptors causing the delay
```

**Output format**:
```markdown
### Scheduling In Latency Analysis
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Average Latency | 3.21ms | <5ms | ✓ Normal |
| P90 Latency | 8.45ms | <10ms | ✓ Normal |
| P95 Latency | 15.67ms | <20ms | ⚠ Warning |
| P99 Latency | 28.45ms | <50ms | ✓ Normal |
| Max Latency | 89.12ms | <100ms | ⚠ Warning |
| Outliers (>100ms) | 0 | 0 | ✓ Normal |

**Latency Distribution**:
| Latency Range | Count | Percentage |
|---------------|-------|------------|
| 0-1ms | 4567 | 30% |
| 1-5ms | 8901 | 58% |
| 5-10ms | 2345 | 15% |
| 10-50ms | 751 | 5% |
| >50ms | 12 | <1% |

**Assessment**: Normal (few outliers)

### Step 4.4: Latency Cause Analysis

```bash
# Analyze what happens before target process runs
perf sched script | grep <PID> | grep -E "sched_wakeup|sched_switch" | head -50

# Check if target process is in run queue for long time
perf sched timehist | grep <PID> | awk '$3 > 10000 {print $1, $3}'

# Identify blocking tasks (tasks running when target is ready)
perf sched script | grep -B 1 "sched_switch.*next_pid=<PID>" | grep "prev_pid=" | awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn
```

---

## Phase 5: Preempting Tasks Analysis (Global Perspective)

### Step 5.1: Global CPU Time Distribution

**IMPORTANT**: Start with global analysis, not local interference.

```bash
# Get CPU time distribution for all tasks
perf sched latency | awk '/^[0-9]/ {print $1, $2, $6, $7, $8}' | sort -k5 -rn | head -50

# Output Example:
# 1234  redis-server           15,234    28.45ms   8.56ms
# 5678  nginx worker           8,901     12.34ms   5.23ms
# 1     systemd               5,678      3.45ms    1.23ms
# 2345  kworker/0:2           4,567      8.90ms    2.34ms
# 8901  postgres              3,456      12.45ms   3.56ms
# 12    ksoftirqd/0           2,345      5.67ms    1.89ms
# 4567  rsyslogd              1,234      2.34ms    0.89ms
# 6789  sshd                   987       1.23ms    0.56ms
#
# Columns:
# 1. PID
# 2. Task Name
# 3. Switches (context switch count)
# 4. Total Runtime (total CPU time used)
# 5. Avg Runtime (average CPU time per run)
#
# Analysis:
# - redis-server (PID 1234): 28.45ms total runtime, 8.56ms avg runtime
# - nginx worker: 12.34ms total runtime
# - systemd: 3.45ms total runtime
# - kworker/0.2: 8.90ms total runtime
# - postgres: 12.45ms total runtime

# Alternative: Use timehist to get CPU time per task
perf sched timehist | awk '{cpu[$1] += $6} END {for (t in cpu) print t, cpu[t]}' | sort -k2 -rn

# Output Example:
# redis-server 28.45
# nginx worker 12.34
# postgres 12.45
# systemd 3.45
# kworker/0:2 8.90
#
# Values are in milliseconds of CPU time

# Calculate CPU usage percentage
TOTAL_RUNTIME=$(perf sched latency | grep "Total runtime" | awk '{print $3}')

# Example:
# Total runtime: 120.34ms
#
# CPU% calculation:
# redis-server: 28.45 / 120.34 = 23.6%
# nginx worker: 12.34 / 120.34 = 10.3%
# postgres: 12.45 / 120.34 = 10.3%
# kworker/0:2: 8.90 / 120.34 = 7.4%
# systemd: 3.45 / 120.34 = 2.9%
```

**Output format**:
```markdown
### Global CPU Time Distribution (Top 20)
| Rank | PID | Task Name | Runtime | CPU% | Role |
|------|-----|-----------|---------|------|------|
| 1 | 1234 | redis-server | 28.45ms | 23.6% | Target |
| 2 | 5678 | nginx worker | 12.34ms | 10.3% | Application |
| 3 | 8901 | postgres | 12.45ms | 10.3% | Application |
| 4 | 2345 | kworker/0:2 | 8.90ms | 7.4% | Kernel |
| 5 | 1 | systemd | 3.45ms | 2.9% | System |
```

**Output format**:
```markdown
### Global CPU Time Distribution (Top 20)
| Rank | PID | Task Name | Runtime | CPU% | Role |
|------|-----|-----------|---------|------|------|
| 1 | | | | | Target Process |
| 2 | | | | | |
| 3 | | | | | |
```

### Step 5.2: Identify Major Competitors

```bash
# Find tasks that run when target process is ready
# Get all sched_switch events where target becomes runnable
perf sched script | grep "sched_switch.*next_pid=<PID>" | awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn > preemptors.txt

# Output Example (preemptors.txt):
# 4567 12
# 3456 2345
# 2890 5678
# 1234 8901
# 987 1
# 654 3456
# 432 4567
# 321 6789
#
# Columns:
# 1. Count (how many times this task ran immediately before target)
# 2. PID (preemptor's PID)
#
# Interpretation:
# - PID 12 (ksoftirqd/0) ran 4567 times before target (most frequent preemptor)
# - PID 2345 (kworker/0:2) ran 3456 times before target
# - PID 5678 (nginx worker) ran 2890 times before target
# - PID 8901 (postgres) ran 1234 times before target

# Calculate preemptor impact
# For each preemptor: count * average runtime = total stolen time

# Extract detailed preemptor information
for pid in $(head -20 preemptors.txt | awk '{print $2}'); do
  echo "=== PID: $pid ==="
  ps -p $pid -o pid,comm,pcpu,pmem,cmd --no-headers
  # Get this process's global CPU share
  perf sched latency | grep "^ *$pid "
done

# Output Example:
# === PID: 12 ===
# 12 ksoftirqd/0 0.5 0.1 [ksoftirqd/0]
#    12 ksoftirqd/0 4567 5.67ms 1.24ms
#
# === PID: 2345 ===
# 2345 kworker/0:2 1.2 0.2 [kworker/0:2]
#   2345 kworker/0:2 3456 8.90ms 2.58ms
#
# === PID: 5678 ===
# 5678 nginx worker 3.4 0.8 nginx: worker process
#   5678 nginx worker 2890 12.34ms 4.27ms
#
# Analysis:
# - PID 12 (ksoftirqd/0): 4567 preemptions, avg runtime 1.24ms
#   Total stolen time: 4567 * 1.24ms = 5.66s
# - PID 2345 (kworker/0:2): 3456 preemptions, avg runtime 2.58ms
#   Total stolen time: 3456 * 2.58ms = 8.91s
# - PID 5678 (nginx worker): 2890 preemptions, avg runtime 4.27ms
#   Total stolen time: 2890 * 4.27ms = 12.34s
```

**Analysis logic**:
```bash
# Extract detailed preemptor information
for pid in $(head -20 preemptors.txt | awk '{print $2}'); do
  echo "=== PID: $pid ==="
  ps -p $pid -o pid,comm,pcpu,pmem,cmd --no-headers
  # Get this process's global CPU share
  perf sched latency | grep "^ *$pid "
done
```

### Step 5.3: Preemptor Category Analysis

**Categorize preemptors by type**:

```bash
# Kernel threads
perf sched latency | awk '/\[.*\]/ {print $0}'

# Output Example:
# 12 ksoftirqd/0 4567 5.67ms 1.24ms
# 2345 kworker/0:2 3456 8.90ms 2.58ms
# 3456 kworker/1:1 2345 4.56ms 1.94ms
# 4567 migration/0 1234 2.34ms 1.89ms
#
# These are kernel tasks (names in brackets)

# System processes (systemd, sshd, etc.)
ps aux | grep -E "systemd|sshd|cron|rsyslog" | awk '{print $2, $11, $3}'

# Output Example:
# 1 /usr/lib/systemd/systemd 0.1
# 6789 sshd: root@pts/0 0.0
# 5678 /usr/sbin/cron 0.0
# 3456 /usr/sbin/rsyslogd 0.1

# User applications
ps aux | grep -v "\[" | grep -v "systemd\|sshd" | awk '$3 > 1.0 {print $2, $11, $3}' | sort -k3 -rn

# Output Example:
# 8901 /usr/lib/postgresql/12/bin/postgres 3.4
# 5678 nginx: worker process 3.2
# 1234 /usr/bin/redis-server 2.8
#
# These are user-space applications with >1% CPU
```

**Categories**:
1. **Kernel tasks**: `ksoftirqd`, `migration`, `rcu_sched`, etc.
2. **System services**: `systemd`, `rsyslog`, `cron`, etc.
3. **Other applications**: Competing user-space processes
4. **Interrupts/Softirqs**: Network, disk, timer interrupts

### Step 5.4: Preemption Impact Calculation

```bash
# Calculate total time target process lost due to preemption
# For each preemptor: count * average runtime = total stolen time

# Preemptor impact analysis script
# Use the provided script for automated analysis:
bash scripts/analyze_preemptors.sh <PID> [DURATION]

# Output Example:
# === Preemptor Impact Analysis for PID 642937 ===
# Collection Duration: 15s
#
# Target Process Average Runtime: 0.234 ms
#
# === Top Preemptors by Frequency ===
#   1234 476466
#    987 476467
#    856 476468
#
# === Preemptor Impact Analysis ===
# Preemptor analysis (stolen time estimation):
# PID 476466: 1234 preemptions, avg 0.345ms, stolen ~0.43s
# PID 476467: 987 preemptions, avg 0.234ms, stolen ~0.23s
```

**Output format**:
```markdown
### Preemptor Analysis (Global Perspective)
| Rank | PID | Task Name | Category | Preempt Count | Estimated Impact | Global CPU% |
|------|-----|-----------|----------|---------------|------------------|-------------|
| 1 | 12 | ksoftirqd/0 | Kernel | 4567 | 5.66s | 9.4% |
| 2 | 2345 | kworker/0:2 | Kernel | 3456 | 8.92s | 14.9% |
| 3 | 5678 | nginx worker | Application | 2890 | 12.34s | 20.6% |
| 4 | 8901 | postgres | Application | 1234 | 4.39s | 7.3% |
| 5 | 1 | systemd | System | 987 | 1.23s | 2.1% |

**Total Preemption Impact**: 31.31s lost (52.2% of collection time)

### Preemptor Category Breakdown
| Category | Task Count | Total Impact | % of Preemptions |
|----------|------------|--------------|-------------------|
| Kernel Tasks | 2 | 14.58s | 46.5% |
| System Services | 1 | 1.23s | 3.9% |
| Other Applications | 2 | 16.73s | 53.4% |
| Interrupts | 0 | 0s | 0% |

**Analysis**:
- Application-level competition is the primary cause (nginx, postgres)
- Kernel tasks (ksoftirqd, kworker) also significant (46.5%)
- May need to tune priorities or use CPU isolation

### Step 5.5: Context Switch Correlation

```bash
# Analyze context switch pattern
# Is target process being switched out too frequently?
# Is there correlation with specific preemptors?

# Correlation analysis
perf sched script | grep <PID> | grep "sched_switch" | \
  awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | \
  sort | uniq -c | sort -rn | head -10 > top_preemptors.txt

# Check if preemptors are also frequently scheduled out
for pid in $(cat top_preemptors.txt | head -5 | awk '{print $2}'); do
  echo "PID $pid preemptor frequency:"
  perf sched script | grep "sched_switch.*prev_pid=$pid" | wc -l
done
```

---

## Phase 6: Comprehensive Analysis Report

### Step 6.1: Generate Summary Report

```markdown
# Process Scheduling Trace Analysis Report

## Executive Summary
- **Target Process**: PID: [PID], Name: [Name]
- **Analysis Duration**: [Duration] seconds
- **Overall Assessment**: [Normal/Moderate Issues/Severe Issues]

## Key Findings

### 1. Scheduling Out Frequency
- **Frequency**: [X] events/second
- **Status**: [Normal/Elevated/Abnormal]
- **Comparison**: [X]x system average
- **Impact**: [Low/Medium/High]

### 2. Scheduling In Latency
- **Average**: [X] ms (threshold: 5ms)
- **P90**: [X] ms (threshold: 10ms)
- **P99**: [X] ms (threshold: 50ms)
- **Max**: [X] ms
- **Outliers**: [X] events >100ms
- **Status**: [Normal/Elevated/Abnormal]

### 3. Global CPU Time Distribution
- **Target Process**: [X]% CPU time
- **Top Competitor**: [Name] with [X]% CPU
- **Kernel Tasks**: [X]% total
- **User Space**: [X]% total

### 4. Preempting Tasks Analysis
- **Major Preemptors**: [List top 5]
- **Total Preemptions**: [X] times
- **Estimated Time Lost**: [X] ms
- **Primary Category**: [Kernel/System/App/Interrupt]

## Detailed Analysis

### Scheduling Out Analysis
[Detailed analysis from Phase 3]

### Scheduling In Latency Analysis
[Detailed analysis from Phase 4]

### Preemptor Analysis
[Detailed analysis from Phase 5]

## Recommendations

### Immediate Actions
1. [Action 1]
2. [Action 2]

### Optimization Suggestions
1. [Optimization 1]
2. [Optimization 2]

### Further Investigation
1. [Investigation 1]
2. [Investigation 2]

## Appendix
- Data Collection Parameters: [params]
- System Configuration: [config]
- Raw Data Location: [path]
```

### Step 6.2: Generate Visualizations (Optional)

```bash
# Generate flamegraph of scheduling events
perf sched script | ./FlameGraph/stackcollapse-perf.pl | ./FlameGraph/flamegraph.pl > sched_flamegraph.svg

# Generate timeline of target process
perf sched timehist | grep <PID> > target_timeline.txt

# Generate preemptor distribution chart
# (use gnuplot or other tool)
```

---

## Output Template

```markdown
# Process Scheduling Trace Analysis - Final Report

## Target Process Summary
| Attribute | Value |
|-----------|-------|
| PID | [PID] |
| Name | [Name] |
| Priority | [Priority] |
| Nice | [Nice] |
| Affinity | [Affinity] |
| Thread Count | [Count] |

## System Environment
| Attribute | Value |
|-----------|-------|
| CPU Count | [Count] |
| CPU Type | [Type] |
| Kernel Version | [Version] |
| Sched Stats | [Enabled/Disabled] |
| Perf Paranoid | [Level] |

## Scheduling Behavior Metrics

### Scheduling Out Frequency
| Metric | Value | Normal Range | Status |
|--------|-------|--------------|--------|
| Total Events | [X] | - | - |
| Frequency | [X] events/s | [Y-Z] | [Status] |
| System Avg | [X] events/s | - | - |
| Ratio | [X]x | <1.5x | [Status] |

### Scheduling In Latency
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Average | [X] ms | <5ms | [Status] |
| P50 | [X] ms | <5ms | [Status] |
| P90 | [X] ms | <10ms | [Status] |
| P95 | [X] ms | <20ms | [Status] |
| P99 | [X] ms | <50ms | [Status] |
| Max | [X] ms | <100ms | [Status] |
| Outliers >100ms | [X] | 0 | [Status] |

### Latency Distribution
| Latency Range | Count | Percentage |
|---------------|-------|------------|
| 0-1ms | [X] | [X]% |
| 1-5ms | [X] | [X]% |
| 5-10ms | [X] | [X]% |
| 10-50ms | [X] | [X]% |
| >50ms | [X] | [X]% |

## Global CPU Time Distribution (Top 15)
| Rank | PID | Task Name | Category | CPU Time | CPU% | Role |
|------|-----|-----------|----------|----------|------|------|
| 1 | [PID] | [Name] | Target | [Time] | [%] | Target |
| 2 | | | | | | |
| ... | ... | ... | ... | ... | ... | ... |

## Preemptor Analysis

### Top Preemptors by Frequency
| Rank | PID | Task Name | Category | Preempt Count | Est. Impact | Global CPU% |
|------|-----|-----------|----------|---------------|-------------|-------------|
| 1 | | | | | | |
| 2 | | | | | | |
| 3 | | | | | | |

### Preemptor Category Breakdown
| Category | Task Count | Total Impact | % of Preemptions |
|----------|------------|--------------|------------------|
| Kernel Tasks | [X] | [Time] | [%] |
| System Services | [X] | [Time] | [%] |
| Other Applications | [X] | [Time] | [%] |
| Interrupts | [X] | [Time] | [%] |

## Assessment

### Overall Health Score
- [Excellent/Good/Fair/Poor]

### Key Issues Identified
1. **Issue 1**: [Description]
   - Evidence: [Evidence]
   - Severity: [High/Medium/Low]
   - Impact: [Impact]

2. **Issue 2**: [Description]
   - Evidence: [Evidence]
   - Severity: [High/Medium/Low]
   - Impact: [Impact]

## Recommendations

### Immediate Actions (High Priority)
1. [Action 1]
   - Command: [Command]
   - Expected Impact: [Impact]

2. [Action 2]
   - Command: [Command]
   - Expected Impact: [Impact]

### Optimization Suggestions (Medium Priority)
1. [Optimization 1]
   - Rationale: [Rationale]
   - Implementation: [Steps]

2. [Optimization 2]
   - Rationale: [Rationale]
   - Implementation: [Steps]

### Further Investigation (Low Priority)
1. [Investigation 1]
   - Focus: [Focus area]
   - Method: [Method]

2. [Investigation 2]
   - Focus: [Focus area]
   - Method: [Method]

## Appendix

### Data Collection Info
- Collection Command: [Command]
- Duration: [Duration] seconds
- Data Size: [Size]
- Timestamp: [Timestamp]

### System Configuration
- [Full system config]

### Reference Values
- Normal scheduling out frequency: [Range]
- Normal scheduling in latency: [Range]
- Normal preemptor count: [Range]

---

## Example Output: Complete Analysis Report

see [references/analysis_report_example.md] for complete report example.

