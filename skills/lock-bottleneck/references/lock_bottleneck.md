# Lock Bottleneck Analysis Guide

This document provides guidelines for identifying and analyzing OS-level lock-related bottlenecks.

## Lock Bottleneck Categories

### 1. Futex Userspace Lock Contention

**Symptoms**:
- High futex WAIT frequency (>5000/s)
- Wait-to-wake ratio > 2:1
- Multiple processes waiting on same futex address
- High voluntary context switches with futex correlation

**Root Causes**:
- Overly coarse-grained locking in application
- Hot lock on shared data structure
- Lock holder doing I/O or sleeping while holding lock
- Thundering herd on lock release

**Analysis Commands**:
```bash
# Record futex events
perf record -a -e syscalls:sys_enter_futex -e syscalls:sys_exit_futex -- sleep 30

# Analyze futex contention
perf script | grep futex | head -100

# Find hot futex addresses
perf script | grep "enter_futex.*FUTEX_WAIT" | awk '{print $6}' | sort | uniq -c | sort -rn | head -10
```

**Thresholds**:
- Normal wait/wake ratio: <2:1
- Warning: 2-5:1 ratio
- Critical: >5:1 ratio
- Normal futex WAIT freq: <5000/s per process

### 2. Kernel Spinlock Contention

**Symptoms**:
- High sys% CPU usage (>30%)
- sys% > usr%
- CPU in kernel mode without I/O
- Softirq (SCHED) elevated

**Root Causes**:
- Lock saturation in kernel
- Excessive interrupts causing lock contention
- Poor NUMA locality
- Running with interrupts disabled too long

**Analysis Commands**:
```bash
# Check per-CPU utilization
mpstat -P ALL 1 10

# Look for high softirq
cat /proc/softirqs

# Check for kernel lock saturation
perf record -a -e lock:lock_acquire -e lock:lock_release -- sleep 30
perf report --stdio | head -50
```

**Thresholds**:
- Normal sys%: <20%
- Warning: 20-40% sys%
- Critical: >40% sys%
- Normal softirq SCHED: varies by CPU count

### 3. Blocking and Wait Time

**Symptoms**:
- High blocked time % in process
- Processes in state 'S' (interruptible) or 'D' (uninterruptible)
- Long wait times in perf sched timehist

**Root Causes**:
- Lock held too long
- I/O blocking while holding lock
- Semaphore/mutex blocking
- Sleep in kernel code

**Analysis Commands**:
```bash
# Check blocked processes
ps -eo pid,comm,state,wchan:32 | grep -E "^[0-9]+.*[DS]"

# System-wide blocked count
vmstat 1 10

# perf wait time analysis
perf sched timehist | head -100
```

**Thresholds**:
- Normal blocked time: <10% of runtime
- Warning: 10-20% blocked
- Critical: >20% blocked
- Normal vmstat 'b': 0 or near 0

### 4. Context Switch Overhead from Locks

**Symptoms**:
- High voluntary context switch rate
- Context switches correlate with lock events
- High cswch/s in pidstat

**Root Causes**:
- Lock-induced sleeps
- Lock spinning then yielding
- scheduler-related preemption

**Analysis Commands**:
```bash
# Per-process context switches
pidstat -w 1 10

# Voluntary vs involuntary
pidstat -w | awk '{print $6}'

# Check context switch correlation
perf sched script | grep -B 2 "prev_state=S" | head -100
```

**Thresholds**:
- Normal voluntary CS: <10,000/s per core
- Warning: 10k-30k/s per core
- Critical: >30k/s per core

### 5. File Lock Contention

**Symptoms**:
- High flock/posix lock activity
- Processes blocked on file locks
- /proc/locks shows many locks

**Root Causes**:
- Multiple processes accessing same file
- Exclusive lock held too long
- Lock convoy (queue behind hot lock)

**Analysis Commands**:
```bash
# Current file locks
cat /proc/locks

# Which processes hold/wait on locks
lslocks

# Trace flock calls
strace -e trace=flock -c -p <PID>
```

## Lock Bottleneck Identification Workflow

### Step 1: System-Wide Baseline

```bash
# System state
vmstat 1 10 > vmstat.log
mpstat -P ALL 1 10 > mpstat.log
pidstat -w 1 10 > pidstat.log

# Blocked processes
ps -eo pid,comm,state,wchan:32 > process_state.log

# Lock state
cat /proc/locks > locks.log
cat /proc/softirqs > softirqs.log
```

### Step 2: Identify Lock Type

```bash
# Check for futex contention
perf record -a -e syscalls:sys_enter_futex -e syscalls:sys_exit_futex -- sleep 30

# Check for kernel locks
perf record -a -e lock:lock_acquire -e lock:lock_release -- sleep 30
```

### Step 3: Analyze Wait Patterns

```bash
# perf sched timehist for wait time
perf sched timehist > timehist.log

# Calculate wait time percentage
grep " <PID> " timehist.log | awk '{wait+=$8; run+=$10} END {print "Wait%:", wait/(wait+run)*100}'
```

### Step 4: Correlate Lock Activity

```bash
# Correlate context switches with lock events
perf sched script | grep -E "futex|prev_state=S" | head -200
```

## Common Lock Bottleneck Patterns

### Pattern 1: The "Futex Stampede"
- **Description**: Many threads competing for same futex
- **Evidence**: Same uaddr with high wait count, high wait/wake ratio
- **Example**: Redis global dict lock, web server connection lock
- **Solution**: Shard locks, use lock-free structures, increase granularity

### Pattern 2: The "Kernel Lock Convoy"
- **Description**: Queue forms behind a hot kernel lock
- **Evidence**: All CPUs have high sys%, similar lock-related kernel time
- **Example**: Filesystem inode lock, block layer plug lock
- **Solution**: Reduce lock hold time, use per-CPU structures, CPU isolation

### Pattern 3: The "Sleeping Lock Holder"
- **Description**: Lock holder blocks (I/O) while others wait
- **Evidence**: Wait channel shows I/O function, lock still held
- **Example**: NFS, database buffer lock
- **Solution**: Avoid blocking while holding lock, use async I/O

### Pattern 4: The "Thundering Herd"
- **Description**: Many processes wake up for same lock
- **Evidence**: Spike in futex wake events, most find lock already taken
- **Example**: Accept() load balancing, eventfd
- **Solution**: Use wake-up optimization (FUTEX_WAKE_OP), reduce waiters

### Pattern 5: The "NUMA Lock Migration"
- **Description**: Lock data structures migrate between NUMA nodes
- **Evidence**: High sched_migrate, remote memory access
- **Example**: Large shared caches, distributed locks
- **Solution**: NUMA-aware allocation, per-node locks

## Mitigation Strategies

### Futex Optimization
```bash
# Use futex with timeout to avoid indefinite blocking
# Consider using FUTEX_WAIT_OP for more efficient wake-ups
# Implement lock-free alternatives where possible
```

### Kernel Lock Reduction
```bash
# Use per-CPU data structures
# Disable preemption carefully
# Reduce interrupt frequency
# Use RCU for read-heavy workloads
```

### Application-Level
```bash
# Reduce critical section size
# Use finer-grained locking
# Implement lock striping
# Consider sharding
```

### CPU Isolation
```bash
# Isolate CPUs for specific workloads
echo 0-7 > /sys/fs/cgroup/cpuset/isolated/tasks

# Set CPU affinity
taskset -pc 8-63 <pid>
```

## Analysis Checklist

- [ ] Identify target process and its lock behavior
- [ ] Check vmstat 'b' column for blocked processes
- [ ] Analyze pidstat voluntary CS for lock-induced switches
- [ ] Trace futex events and identify hot addresses
- [ ] Correlate wait time with lock operations
- [ ] Check sys% vs usr% for kernel lock overhead
- [ ] Analyze /proc/softirqs for lock-related softirq
- [ ] Identify lock bottleneck category
- [ ] Calculate performance impact
- [ ] Generate actionable recommendations

## Normal Ranges Reference

| Metric | Normal | Warning | Critical |
|--------|--------|---------|----------|
| Blocked time % | <10% | 10-20% | >20% |
| Futex wait/wake ratio | <2:1 | 2-5:1 | >5:1 |
| Voluntary CS/s | <10,000 | 10k-30k | >30k |
| sys% vs usr% | sys < usr | sys ~ usr | sys > usr |
| vmstat 'b' | 0 | 1-5 | >5 |
| Softirq SCHED | <1000/s | 1k-5k | >5k |
