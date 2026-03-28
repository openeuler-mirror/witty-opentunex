# Scheduling Bottleneck Analysis Guide

This document provides guidelines for identifying and analyzing scheduling-related bottlenecks in process performance.

## Scheduling Bottleneck Categories

### 1. Excessive Context Switching
**Symptoms**:
- High scheduling out frequency (>1000 events/second for CPU-intensive workloads)
- Elevated context switch rate (>50000 cs/s system-wide)
- CPU time spent in kernel mode for scheduling overhead

**Root Causes**:
- Too many runnable processes competing for limited CPUs
- Short time slices (quantum) causing frequent preemption
- Real-time priority tasks preempting normal tasks
- Inefficient thread synchronization causing unnecessary wake-ups

**Analysis Commands**:
```bash
# System-wide context switch rate
vmstat 1 5

# Per-process context switches
pidstat -w 1 5

# Context switch timeline
perf sched map | head -100
```

**Thresholds**:
- Warning: >10000 cs/s per core
- Critical: >50000 cs/s per core
- Target Process: >1000 sched_out/sec for CPU-intensive, >5000 sched_out/sec for I/O-intensive

### 2. High Scheduling In Latency
**Symptoms**:
- Long wait time from wake-up to schedule-in (>10ms P90)
- Many outliers (>50ms, >100ms)
- Target process spends significant time in run queue

**Root Causes**:
- High CPU load (loadavg > CPU_count)
- Too many runnable processes per CPU
- CPU affinity issues (process stuck on busy CPU)
- Priority inversion or starvation
- Real-time tasks monopolizing CPU

**Analysis Commands**:
```bash
# Check load average
cat /proc/loadavg

# Run queue length
vmstat 1 5

# Per-CPU load
mpstat -P ALL 1 5

# Load per CPU
cat /proc/stat
```

**Thresholds**:
- Warning: P90 > 10ms, P99 > 50ms
- Critical: P90 > 20ms, P99 > 100ms
- Outliers: >0 events >100ms is abnormal

### 3. Preemption by Competing Tasks
**Symptoms**:
- Target process frequently preempted by specific tasks
- Competing tasks consume significant CPU time
- Scheduling correlation with specific preemptors

**Root Causes**:
- Misconfigured task priorities
- Inappropriate real-time priorities
- No CPU isolation for critical workloads
- Kernel tasks consuming excessive CPU (ksoftirqd, migration)
- System services running at wrong priority

**Analysis Commands**:
```bash
# Task priorities and scheduling policies
ps -eo pid,comm,pri,ni,cls,rtprio

# Real-time tasks
ps -eo pid,comm,pri,rtprio | grep -v "0"

# CPU affinity of preemptors
taskset -pc <PID>

# Kernel task CPU usage
ps -L -p $(pgrep ksoftirqd) -o pid,tid,psr,pcpu
```

**Thresholds**:
- Warning: Single preemptor >10% CPU, causes >20% of preemptions
- Critical: Single preemptor >20% CPU, causes >50% of preemptions

### 4. Starvation and Priority Inversion
**Symptoms**:
- Target process consistently denied CPU time
- Lower priority process runs while high priority waits
- Long periods (>1s) without schedule-in

**Root Causes**:
- Real-time tasks with infinite runtime
- Priority inversion (low-priority holds resource needed by high-priority)
- CPU affinity conflicts (all CPUs busy with other tasks)
- CFS group scheduling misconfiguration

**Analysis Commands**:
```bash
# Check for starvation (long gaps in schedule-in events)
perf sched timehist | grep <PID> | awk '{gap=$1-prev; if(gap>1000) print "Gap:", gap, "ms at", $1; prev=$1}'

# Check CFS group weights
cat /sys/kernel/sched_autogroup_enabled
cat /proc/<PID>/cgroup

# Check real-time tasks
ps -eo pid,comm,pri,rtprio,cls | grep "FF\|RR"
```

**Thresholds**:
- Warning: Gaps >100ms (>0.1s)
- Critical: Gaps >1000ms (>1s)

### 5. NUMA-Related Scheduling Issues
**Symptoms**:
- Process migrated frequently between NUMA nodes
- High remote memory access
- Performance degradation over time

**Root Causes**:
- Automatic NUMA balancing disabled
- Poor memory locality
- NUMA imbalance causing migrations
- Insufficient NUMA node resources

**Analysis Commands**:
```bash
# NUMA statistics
numastat

# Process memory distribution
numactl -p

# NUMA migrations
perf sched script | grep "sched_migrate"

# Remote vs local memory access
perf stat -e node_loads,node_stores,local_loads,remote_loads -p <PID> -- sleep 10
```

## Bottleneck Identification Workflow

### Step 1: Collect Baseline Metrics
```bash
# System-wide baseline
vmstat 1 10 > baseline_vmstat.txt
mpstat -P ALL 1 10 > baseline_mpstat.txt
pidstat -u -r -d -w 1 10 > baseline_pidstat.txt

# Process-specific baseline
cat /proc/<PID>/schedstat
cat /proc/<PID>/stat
```

### Step 2: Identify Anomalous Patterns
```bash
# Compare with normal ranges
# - Context switch rate
# - Load average
# - Scheduling latency
# - Preemptor frequency
```

### Step 3: Correlate with Root Causes
```bash
# For each anomaly:
# 1. Check system load
# 2. Check task priorities
# 3. Check CPU affinity
# 4. Check NUMA placement
# 5. Check for specific preemptors
```

### Step 4: Verify Bottleneck Impact
```bash
# Measure performance impact
# - Compare latency with/without bottleneck
# - Calculate CPU time lost
# - Estimate throughput impact
```

## Common Bottleneck Patterns

### Pattern 1: The "Bursty Competitor"
- **Description**: Background task periodically consumes high CPU, causing scheduling spikes
- **Evidence**: Preemptor with high CPU% but low average, causing clustered preemptions
- **Example**: Cron jobs, log rotation, backup processes
- **Solution**: Adjust task priority, reschedule to off-peak hours, use nice/ionice

### Pattern 2: The "Real-Time Hog"
- **Description**: Real-time task monopolizing CPU
- **Evidence**: RT policy task with high CPU%, causing sustained latency for other tasks
- **Example**: Audio/Video processing, custom RT daemon
- **Solution**: Audit RT policies, set appropriate limits, use cgroups

### Pattern 3: The "Kernel Task Storm"
- **Description**: Kernel tasks consuming excessive CPU
- **Evidence**: ksoftirqd, migration, rcu_sched with high CPU%
- **Example**: Network interrupt storm, timer flood
- **Solution**: Tune interrupt handling, check for IRQ affinity, reduce interrupt rate

### Pattern 4: The "NUMA Migrator"
- **Description**: Process frequently migrating between NUMA nodes
- **Evidence**: High sched_migrate events, remote/local memory ratio > 2:1
- **Example**: Poor memory locality, insufficient node resources
- **Solution**: Tune NUMA balancing, set CPU/memory affinity, use numactl

### Pattern 5: The "Priority Inverter"
- **Description**: Low-priority task holding resource needed by high-priority task
- **Evidence**: Low-priority task running while high-priority waits
- **Example**: Contended lock, priority inheritance not enabled
- **Solution**: Use priority inheritance, avoid contended locks, separate workloads

## Mitigation Strategies

### Priority Management
```bash
# Adjust nice value (lower = higher priority)
renice -n -5 -p <PID>

# Set real-time priority
chrt -f -p 50 <PID>

# Use ionice for I/O priority
ionice -c 1 -n 4 -p <PID>
```

### CPU Affinity
```bash
# Pin to specific CPU
taskset -pc 2 <PID>

# Pin to CPU set
taskset -pc 0-3 <PID>

# Automatic CPU affinity using cgroups
echo <PID> > /sys/fs/cgroup/cpuset/mycpuset/tasks
```

### NUMA Optimization
```bash
# Run on specific NUMA node
numactl --cpunodebind=0 --membind=0 <command>

# Interleave memory across nodes
numactl --interleave=all <command>

# Prefer local memory
numactl --prefer=0 <command>
```

### Cgroups and Systemd
```bash
# Create cgroup for CPU isolation
systemd-run --scope -p CPUAffinity=0-3 <command>

# Set CPU quota
systemctl set-property <service>.service CPUQuota=200%

# Set priority
systemctl set-property <service>.service CPUSchedulingPriority=50
```

### Kernel Tuning
```bash
# Adjust scheduler granularity (microseconds)
echo 1000000 > /proc/sys/kernel/sched_granularity_ns

# Adjust scheduler latency (microseconds)
echo 20000000 > /proc/sys/kernel/sched_latency_ns

# Enable NUMA balancing
echo 1 > /proc/sys/kernel/numa_balancing

# Adjust migration cost
echo 500000 > /proc/sys/kernel/sched_migration_cost_ns
```

## Analysis Checklist

- [ ] Identify target process PID and characteristics
- [ ] Collect baseline system metrics
- [ ] Record scheduling trace with perf sched record
- [ ] Analyze scheduling out frequency vs normal range
- [ ] Analyze scheduling in latency distribution
- [ ] Identify top preemptors and their impact
- [ ] Analyze global CPU time distribution
- [ ] Check for priority-related issues
- [ ] Verify CPU affinity and NUMA placement
- [ ] Calculate performance impact (time lost, latency added)
- [ ] Generate actionable recommendations
- [ ] Verify recommendations with targeted testing

## Normal Ranges Reference

| Metric | Normal | Warning | Critical |
|--------|--------|---------|----------|
| Scheduling Out Frequency (CPU-intensive) | 10-100 /s | 100-500 /s | >500 /s |
| Scheduling Out Frequency (I/O-intensive) | 100-1000 /s | 1000-5000 /s | >5000 /s |
| Avg Scheduling In Latency | <5 ms | 5-10 ms | >10 ms |
| P90 Scheduling In Latency | <10 ms | 10-20 ms | >20 ms |
| P99 Scheduling In Latency | <50 ms | 50-100 ms | >100 ms |
| Outliers (>100ms) | 0 | 1-10 | >10 |
| System Context Switch Rate | <10000 /s/core | 10k-50k /s/core | >50k /s/core |
| Load Average | <CPU_count | CPU_count-2*CPU_count | >2*CPU_count |
| Single Preemptor CPU% | <10% | 10-20% | >20% |
| Preemption Share by Single Task | <20% | 20-50% | >50% |
