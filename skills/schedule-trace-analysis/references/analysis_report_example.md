## Example Output: Complete Analysis Report

Below is a complete example of an actual analysis report for a Redis process (PID 1234) experiencing scheduling issues:

```markdown
# Process Scheduling Trace Analysis - Final Report

## Executive Summary
- **Target Process**: PID: 1234, Name: redis-server
- **Analysis Duration**: 15 seconds
- **Overall Assessment**: Fair - Some performance issues detected

**Key Findings**:
1. Excessive preemption frequency (1015.6 events/s vs normal 10-100)
2. 57.4% of potential runtime lost to preemption
3. Kernel tasks dominate interference (51.4% of preemptions)
4. Application competition significant (nginx: 20.6%, postgres: 7.3% CPU)

## Key Findings

### 1. Scheduling Out Frequency
- **Frequency**: 1015.6 events/second
- **Status**: Elevated
- **Comparison**: 6.77x system average
- **Impact**: High - Process loses majority of potential runtime

### 2. Scheduling In Latency
- **Average**: 3.21 ms (threshold: 5ms)
- **P90**: 8.45 ms (threshold: 10ms)
- **P99**: 28.45 ms (threshold: 50ms)
- **Max**: 89.12 ms
- **Outliers**: 0 events >100ms
- **Status**: Normal (few outliers)

### 3. Global CPU Time Distribution
- **Target Process**: 23.6% CPU time (28.45ms total)
- **Top Competitor**: nginx worker with 20.6% CPU
- **Kernel Tasks**: 7.4% + 6.3% + 4.7% = 18.4% total
- **User Space**: 81.6% total

### 4. Preempting Tasks Analysis
- **Major Preemptors**: ksoftirqd/0, kworker/0:2, nginx worker, postgres
- **Total Preemptions**: 13,234 times
- **Estimated Time Lost**: 17.22s
- **Primary Category**: Kernel Tasks (51.4%) and Applications (48.6%)

## Detailed Analysis

### Scheduling Out Analysis

Target process was scheduled out 15,234 times during the 15-second collection, resulting in a frequency of 1015.6 events/second. This is 6.77x higher than the system average of 75 events/second, indicating significant CPU competition.

**Comparison with System**:
- Target PID 1234 (redis-server): 1015.6 events/s
- PID 5678 (nginx worker): 296.8 events/s (0.58x target)
- PID 8901 (postgres): 115.2 events/s (0.23x target)
- PID 2345 (kworker/0:2): 152.2 events/s (0.30x target)

The elevated frequency is consistent with the high preemption count from competitors, particularly kernel tasks and nginx.

### Scheduling In Latency Analysis

Most scheduling latencies are within acceptable ranges:
- 30.0% of events (4,567) have latency <1ms
- 58.4% of events (8,901) have latency 1-5ms
- 8.1% of events (1,234) have latency 5-10ms
- 3.4% of events (512) have latency 10-50ms
- 0.1% of events (20) have latency >50ms

However, the maximum latency of 89.12ms warrants investigation. Analysis of outliers shows they correlate with periods of high ksoftirqd activity and nginx worker execution, suggesting interrupt storms or bursty application load.

### Preemptor Analysis

**Global CPU Time Distribution (Top 8)**:
1. redis-server (PID 1234): 28.45ms (23.6%) - Target
2. nginx worker (PID 5678): 12.34ms (10.3%) - Application
3. postgres (PID 8901): 12.45ms (10.3%) - Application
4. kworker/0:2 (PID 2345): 8.90ms (7.4%) - Kernel
5. kworker/1:1 (PID 3456): 7.56ms (6.3%) - Kernel
6. ksoftirqd/0 (PID 12): 5.67ms (4.7%) - Kernel
7. systemd (PID 1): 3.45ms (2.9%) - System
8. rsyslogd (PID 4567): 2.34ms (1.9%) - System

**Top Preemptors by Frequency**:
1. ksoftirqd/0 (PID 12): 4,567 preemptions, stolen 5.66s, global CPU 9.4%
2. kworker/0:2 (PID 2345): 3,456 preemptions, stolen 8.92s, global CPU 14.9%
3. nginx worker (PID 5678): 2,890 preemptions, stolen 12.34s, global CPU 20.6%
4. postgres (PID 8901): 1,234 preemptions, stolen 4.39s, global CPU 7.3%
5. kworker/1:1 (PID 3456): 987 preemptions, stolen 3.12s, global CPU 5.2%

**Preemptor Category Breakdown**:
- Kernel Tasks: 3 tasks, 17.70s stolen (51.4% of preemptions)
- System Services: 0 tasks, 0s stolen (0% of preemptions)
- Other Applications: 2 tasks, 16.73s stolen (48.6% of preemptions)
- Interrupts: 0 tasks, 0s stolen (0% of preemptions)

The analysis reveals that kernel tasks (ksoftirqd, kworkers) are the primary source of interference, causing over half of all preemptions. Application-level competition from nginx and postgres is also significant, accounting for nearly half of preemptions.

## Assessment

### Overall Health Score
**Fair** - The target process is experiencing significant scheduling interference, but latencies remain mostly acceptable. The primary issue is excessive preemption frequency leading to lost runtime.

### Key Issues Identified

1. **Issue 1**: Excessive preemption frequency (1015.6 events/s)
    - Evidence: 6.77x higher than system average, 15,234 events in 15s
    - Severity: High
    - Impact: Target process loses 57.4% (17.22s) of potential runtime
    - Root Cause: High competition from kernel tasks (51.4%) and applications (48.6%)

2. **Issue 2**: Kernel task interference (ksoftirqd, kworkers)
   - Evidence: ksoftirqd alone causes 9.4% CPU and 4,567 preemptions
   - Severity: Medium
   - Impact: 17.70s lost to kernel preemptions (51.4% of total)
   - Root Cause: Likely interrupt storm or high kernel workload

3. **Issue 3**: Application-level competition
   - Evidence: nginx (20.6% CPU) and postgres (10.3% CPU) compete for CPU
   - Severity: Medium
   - Impact: 16.73s lost to application preemptions (48.6% of total)
   - Root Cause: Co-located applications on same CPU resources

## Recommendations

### Immediate Actions (High Priority)

1. **Adjust task priorities for critical process**
   - Command: `renice -n -5 -p 1234` (increase redis priority)
   - Command: `renice -n 5 -p 5678` (decrease nginx priority)
   - Expected Impact: Reduce preemption frequency by ~30%, improve latency

2. **Investigate and resolve interrupt storm**
   - Command: `cat /proc/interrupts | sort -k2 -rn | head -20`
   - Command: `watch -n 1 'cat /proc/interrupts | sort -k2 -rn | head -10'`
   - Expected Impact: Identify high interrupt devices, reduce ksoftirqd CPU usage

3. **Apply CPU isolation for critical workload**
   - Command: `echo 0-1 > /sys/devices/system/cpu/isolated`
   - Command: `taskset -pc 0-1 1234`
   - Command: `systemctl set-property redis-server.service CPUAffinity=0-1`
   - Expected Impact: Eliminate most preemptions, guarantee CPU access

### Optimization Suggestions (Medium Priority)

1. **Use cgroups for CPU resource control**
   - Implementation:
     ```bash
     # Create cgroup for redis
     mkdir -p /sys/fs/cgroup/cpu,cpuacct/redis
     echo 1234 > /sys/fs/cgroup/cpu,cpuacct/redis/cgroup.procs
     echo 2048 > /sys/fs/cgroup/cpu,cpuacct/redis/cpu.shares  # Higher priority
     echo 50000000 > /sys/fs/cgroup/cpu,cpuacct/redis/cpu.cfs_quota_us  # 50ms per 100ms
     echo 100000 > /sys/fs/cgroup/cpu,cpuacct/redis/cpu.cfs_period_us
     ```
   - Expected Impact: More predictable CPU allocation, reduce competition

2. **Tune interrupt affinity**
   - Implementation:
     ```bash
     # Move network interrupts to CPU 2-3
     for irq in /proc/irq/*; do
       if grep -q "eth0" $irq/name 2>/dev/null; then
         echo 4-7 > $irq/smp_affinity
       fi
     done
     # Verify
     cat /proc/interrupts | grep -E "eth0|:"
     ```
   - Expected Impact: Reduce kernel interrupts on target CPU, improve latency

3. **Reschedule competing applications**
   - Implementation: Move nginx and postgres to different server or use CPU affinity to separate them
   - Command: `taskset -pc 2-3 5678` (nginx to CPU 2-3)
   - Command: `taskset -pc 2-3 8901` (postgres to CPU 2-3)
   - Expected Impact: Eliminate application competition on target CPU

4. **Enable NUMA balancing if applicable**
   - Implementation: `echo 1 > /proc/sys/kernel/numa_balancing`
   - Command: `numactl --preferred=0 redis-server` (bind to NUMA node 0)
   - Expected Impact: Improve memory locality, reduce migrations

## Appendix

### Data Collection Info
- Collection Command: `perf sched record -a -e sched:sched_switch,sched:sched_wakeup,sched:sched_wakeup_new,sched:sched_migrate_task -- sleep 15`
- Duration: 15 seconds
- Data Size: 128MB
- Timestamp: 2024-03-19 12:00:00 UTC
- System Load: 2.34, 2.12, 2.01 (1min, 5min, 15min averages)

### System Configuration
```
Architecture: aarch64
CPU op-mode(s): 64-bit
Byte Order: Little Endian
CPU(s): 8
On-line CPU(s) list: 0-7
Thread(s) per core: 1
Core(s) per socket: 8
Socket(s): 1
NUMA node(s): 1
Vendor ID: ARM
Model name: ARM Neoverse N1
CPU max MHz: 2400.0000
CPU min MHz: 600.0000
BogoMIPS: 50.00
Virtualization: -
L1d cache: 64 KiB
L1i cache: 64 KiB
L2 cache: 1024 KiB
NUMA node0 CPU(s): 0-7
```

### Reference Values
- Normal scheduling out frequency:
  - CPU-intensive workloads: 10-100 events/second
  - I/O-intensive workloads: 100-1000 events/second
  - Target should be <2x system average
- Normal scheduling in latency:
  - Average: <5ms
  - P90: <10ms
  - P99: <50ms
  - Max: <100ms
  - Outliers (>100ms): Should be 0
- Normal preemptor count:
  - System average varies by workload
  - Target process should be <2x system average
- Normal preemptor distribution:
  - Kernel Tasks: <30%
  - Applications: <50%
  - System Services: <20%

### Files Generated
- perf.data: Raw scheduling trace data (128MB)
- process_info.txt: Target process information
- threads.txt: Thread information (4 threads)
- lscpu.txt: CPU topology
- numa_info.txt: NUMA configuration (single node)
- sched_latency.txt: Scheduling latency analysis
- sched_timehist.txt: Time history of scheduling events
- sched_map.txt: Scheduling map visualization
- sched_script.txt: Detailed scheduling script (45,678 events)
- summary.txt: Collection summary
- analysis/analysis_report.md: This report

---

**Report Generated**: 2024-03-19 12:05:00 UTC
**Analysis Tool**: process-schedule-trace-analysis skill v1.0
**Analyst**: Automated Analysis
```

This example demonstrates:
1. How to interpret perf sched output formats
2. How to calculate and present scheduling metrics
3. How to identify and categorize preemptors
4. How to correlate findings with system behavior
5. How to provide actionable recommendations
6. How to structure a comprehensive analysis report

Key takeaways from the example:
- Target process had 3.38x higher scheduling frequency than average
- 57.4% of potential runtime was lost to preemption
- Kernel tasks were the primary interference source (51.4%)
- Application competition was also significant (48.6%)
- Recommendations include priority adjustment, CPU isolation, and cgroup configuration
