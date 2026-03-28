# CPU Optimization Strategies

## CPU Affinity Tuning

### Description
Bind specific processes to CPU cores to reduce context switching and improve cache locality.

### Applicable Bottlenecks
- CPU Context Switch (cs/s > 50000)
- High cache miss rates
- NUMA imbalance

### Configuration Files
- None (runtime configuration)

### Commands

**Check current affinity**:
```bash
taskset -c -p <PID>
```

**Set affinity to specific cores**:
```bash
# Bind process to cores 0-3
taskset -cp 0-3 <PID>

# Bind process to cores 0,2,4,6
taskset -cp 0,2,4,6 <PID>
```

**Set affinity at process start**:
```bash
taskset -c 0-3 <command>
```

**NUMA-aware affinity**:
```bash
# Run on NUMA node 0
numactl --cpunodebind=0 --membind=0 <command>

# Run on NUMA node 1
numactl --cpunodebind=1 --membind=1 <command>
```

### Verification
```bash
# Check taskset status
taskset -c -p <PID>

# Check NUMA status
numastat -p <PID>

# Monitor CPU usage per core
mpstat -P ALL 1 5
```

### Risk Level
Medium - Can affect other processes sharing the same cores

### Expected Impact
5-20% improvement for CPU-intensive workloads with good cache locality

---

## CPU Governor Tuning

### Description
Adjust CPU frequency scaling governor to match workload characteristics.

### Applicable Bottlenecks
- CPU utilization spikes
- Latency-sensitive applications
- High-performance computing

### Configuration Files
- /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

### Commands

**Check current governor**:
```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
```

**List available governors**:
```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
```

**Set governor**:
```bash
# Performance mode (always max frequency)
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Powersave mode (always min frequency)
echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# On-demand mode (dynamic scaling)
echo ondemand | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

**Permanent configuration**:
```bash
# Install cpupower (Debian/Ubuntu)
apt-get install linux-cpupower

# Install cpupower (RHEL/CentOS)
yum install kernel-tools

# Set governor permanently
cpupower frequency-set -g performance
```

### Governors
| Governor | Description | Use Case |
|----------|-------------|----------|
| performance | Maximum frequency | HPC, latency-sensitive |
| powersave | Minimum frequency | Power saving, idle systems |
| ondemand | Dynamic scaling based on load | General purpose |
| conservative | Gradual frequency changes | Battery-powered systems |
| schedutil | Scheduler-driven scaling | Modern workloads |

### Verification
```bash
# Check governor status
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Check current frequency
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq

# Monitor frequency changes
watch -n 1 'cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq'
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
3-15% improvement depending on workload

---

## Process Priority Adjustment

### Description
Adjust process priority (nice value) to give CPU preference to critical processes.

### Applicable Bottlenecks
- High-priority workloads starved by lower-priority processes
- Real-time requirements

### Configuration Files
- None (runtime configuration)

### Commands

**Check current priority**:
```bash
ps -eo pid,comm,pri,nice
```

**Change priority (nice)**:
```bash
# Increase priority (decrease nice value, root required)
renice -5 -p <PID>
renice -10 -p <PID>

# Decrease priority (increase nice value)
renice +5 -p <PID>

# Set priority at process start
nice -n -5 <command>
```

**Real-time priority (chrt)**:
```bash
# Check current real-time priority
chrt -p <PID>

# Set real-time priority (FIFO)
chrt -f 50 <command>

# Set real-time priority (RR - Round Robin)
chrt -r 50 <command>

# Set real-time priority for existing process
chrt -f -p 50 <PID>
```

### Priority Levels
| Nice Value | Priority | Description |
|------------|----------|-------------|
| -20 to -1 | Highest | Requires root, use sparingly |
| 0 | Default | Default priority |
| 1 to 19 | Lower | User can decrease priority |

### Real-Time Priority
| Priority | Policy | Description |
|----------|--------|-------------|
| 1-99 | SCHED_FIFO | Real-time FIFO |
| 1-99 | SCHED_RR | Real-time Round Robin |

### Verification
```bash
# Check process priority
ps -eo pid,comm,pri,nice,rtprio,cls

# Monitor scheduling
pidstat -t 1 5
```

### Risk Level
High - Real-time priorities can starve other processes

### Expected Impact
2-10% improvement for high-priority processes

---

## Interrupt Affinity Tuning

### Description
Distribute interrupt handling across CPU cores to balance load and reduce contention.

### Applicable Bottlenecks
- High interrupt rate (in/s > 10000)
- Uneven CPU load due to interrupts
- Network-intensive workloads

### Configuration Files
- /proc/irq/<irq>/smp_affinity

### Commands

**Check interrupt distribution**:
```bash
# Show interrupts per CPU
cat /proc/interrupts

# Show interrupt affinity
cat /proc/irq/24/smp_affinity
```

**Calculate CPU mask**:
```bash
# Convert CPU number to hex mask
# CPU 0 = 0x1
# CPU 1 = 0x2
# CPU 2 = 0x4
# CPU 3 = 0x8
# CPU 0-3 = 0xf
# CPU 4-7 = 0xf0

# Python example
python3 -c "print(hex(1<<3))"  # CPU 3 -> 0x8
```

**Set interrupt affinity**:
```bash
# Bind interrupt 24 to CPU 0-3
echo f | sudo tee /proc/irq/24/smp_affinity

# Bind interrupt 24 to CPU 4-7
echo f0 | sudo tee /proc/irq/24/smp_affinity

# Spread interrupts evenly
# Script to distribute interrupts across cores
for irq in $(cat /proc/interrupts | grep -E "eth|nvme|virtio" | awk '{print $1}' | sed 's/:$//'); do
    echo $(echo $(printf %x $((1<<RANDOM%$(nproc)))) ) > /proc/irq/$irq/smp_affinity
done
```

**Network interrupt optimization**:
```bash
# RPS (Receive Packet Steering)
echo ffff | sudo tee /sys/class/net/eth0/queues/rx-0/rps_cpus

# RFS (Receive Flow Steering)
echo 32768 | sudo tee /proc/sys/net/core/rps_sock_flow_entries

echo 32768 | sudo tee /sys/class/net/eth0/queues/rx-0/rps_flow_cnt
```

### Verification
```bash
# Check interrupt distribution
watch -n 1 'cat /proc/interrupts'

# Monitor CPU load
mpstat -P ALL 1 5

# Check network interrupt load
cat /proc/irq/<irq>/smp_affinity_list
```

### Risk Level
Medium - Can affect network performance if misconfigured

### Expected Impact
5-15% improvement for network-intensive workloads

---

## Transparent Huge Pages (THP) Tuning

### Description
Optimize Transparent Huge Pages for memory-intensive workloads.

### Applicable Bottlenecks
- Memory page table walk overhead
- Large memory workloads
- Database performance

### Configuration Files
- /sys/kernel/mm/transparent_hugepage/enabled
- /sys/kernel/mm/transparent_hugepage/defrag

### Commands

**Check current THP status**:
```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
cat /sys/kernel/mm/transparent_hugepage/defrag
```

**Disable THP**:
```bash
# Disable THP immediately
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Disable THP permanently
echo 'never > /sys/kernel/mm/transparent_hugepage/enabled' | sudo tee -a /etc/rc.local
echo 'never > /sys/kernel/mm/transparent_hugepage/defrag' | sudo tee -a /etc/rc.local
```

**Enable THP**:
```bash
# Enable THP immediately
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Enable THP with madvise
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
```

**THP options**:
| Value | Description |
|-------|-------------|
| always | Always use huge pages |
| never | Never use huge pages |
| madvise | Use huge pages only when explicitly requested |

### Verification
```bash
# Check THP status
cat /sys/kernel/mm/transparent_hugepage/enabled

# Check huge page usage
grep -i huge /proc/meminfo

# Monitor page fault behavior
pidstat -r 1 5
```

### Risk Level
Low-Medium - Can increase memory usage, may cause performance regression for some workloads

### Expected Impact
5-20% improvement for large memory workloads, 5-10% regression for small random access workloads

---

## CPU C-States Tuning

### Description
Adjust CPU C-states (power saving states) to reduce latency at the cost of power efficiency.

### Applicable Bottlenecks
- High wake-up latency
- Latency-sensitive applications
- High-frequency I/O workloads

### Configuration Files
- /sys/module/processor/parameters/idle
- /sys/devices/system/cpu/cpu*/cpuidle/state*/disable

### Commands

**Check available C-states**:
```bash
# List C-states for CPU 0
ls -1 /sys/devices/system/cpu/cpu0/cpuidle/

# Check C-state status
cat /sys/devices/system/cpu/cpu0/cpuidle/state0/disable
cat /sys/devices/system/cpu/cpu0/cpuidle/state1/disable
```

**Disable deep C-states**:
```bash
# Disable C-state 1 and deeper
echo 1 | sudo tee /sys/devices/system/cpu/cpu*/cpuidle/state1/disable
echo 1 | sudo tee /sys/devices/system/cpu/cpu*/cpuidle/state2/disable

# Disable all C-states except C0
for state in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
    echo 1 | sudo tee $state/disable
done
```

**Enable C-states**:
```bash
# Enable all C-states
for state in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
    echo 0 | sudo tee $state/disable
done
```

**Kernel boot parameter**:
```bash
# Add to GRUB cmdline
# intel_idle.max_cstate=1
# processor.max_cstate=1

# Edit /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_idle.max_cstate=1 processor.max_cstate=1"

# Update grub
update-grub
```

### C-States
| C-State | Description | Latency | Power Saving |
|---------|-------------|---------|--------------|
| C0 | Active | 0 | None |
| C1 | Halt | Low | Low |
| C1E | Enhanced Halt | Medium | Medium |
| C3 | Sleep | High | High |
| C6 | Deep Power Down | Very High | Very High |

### Verification
```bash
# Check C-state status
cat /sys/devices/system/cpu/cpu*/cpuidle/state*/disable

# Monitor C-state residency
turbostat --interval 1

# Check wake-up latency
perf stat -e cycles,instructions,sched_wakeup <command>
```

### Risk Level
Medium - Increases power consumption significantly

### Expected Impact
2-10% improvement for latency-sensitive workloads

---

## CPU Hyper-Threading Optimization

### Description
Optimize hyper-threading behavior based on workload characteristics.

### Applicable Bottlenecks
- High cache contention
- Floating-point intensive workloads
- Memory bandwidth saturation

### Configuration Files
- None (runtime configuration via CPU hotplug)

### Commands

**Check hyper-threading status**:
```bash
lscpu | grep -i thread
cat /proc/cpuinfo | grep "siblings"
```

**Disable hyper-threading**:
```bash
# Identify sibling CPUs
lscpu --all --extended | grep -E "^CPU|Thread"

# Disable hyper-threading for CPU cores
# Example: Disable logical cores 2,3 (siblings of 0,1)
echo 0 | sudo tee /sys/devices/system/cpu/cpu2/online
echo 0 | sudo tee /sys/devices/system/cpu/cpu3/online

# Disable all hyper-threads (keep only physical cores)
for cpu in $(seq 0 $(( $(nproc) / 2 - 1 ))); do
    sibling=$((cpu + $(nproc)/2))
    echo 0 | sudo tee /sys/devices/system/cpu/cpu$sibling/online
done
```

**Enable hyper-threading**:
```bash
# Enable all CPUs
for cpu in /sys/devices/system/cpu/cpu*/online; do
    echo 1 | sudo tee $cpu
done
```

**Kernel boot parameter**:
```bash
# Add to /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nosmt"

# Update grub
update-grub
```

### When to Use
| Scenario | Hyper-Threading |
|----------|----------------|
| Floating-point intensive | Disable |
| High cache contention | Disable |
| Memory bandwidth bound | Disable |
| Mixed integer workloads | Enable |
| Thread-level parallelism | Enable |

### Verification
```bash
# Check CPU status
lscpu --all --extended

# Monitor CPU utilization
mpstat -P ALL 1 5

# Check cache sharing
lscpu | grep -i cache
```

### Risk Level
Medium - Reduces core count by half when disabled

### Expected Impact
10-30% improvement for specific workloads, 20-40% regression for general purpose workloads
