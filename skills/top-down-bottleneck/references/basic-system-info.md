---
name: basic-system-info
description: Collect basic system information (CPU, memory, disk, network)
---

# basic-system-info — System Information Collection

**Delegation**: When delegating to sys-sniffer, use **ONE** task call: 
\`task(subagent_type="sys-sniffer", run_in_background=true, load_skills=["basic-system-info"], description="Gather system info", prompt="Collect CPU, memory, disk, network, kernel, process, security, hardware. Output raw data in <collected> format.")\`. 
Do NOT spawn multiple tasks (e.g. one per CPU/memory/disk) — each task requires \`subagent_type\` or \`category\`, and splitting causes "Unknown Task" failures.

## Client Connection and Command Execution

Load the remote-execution skill for standardized SSH connection and command execution:

skill:remote-execution

---

## Ensure Tool is available
```
mpstat -V
iostat -V
pidstat -V
perf --version
```

---

## CPU Diagnostics

```bash
# Per-CPU usage
mpstat -P ALL 1 5
# High CPU processes
pidstat -u 1 5
pidstat -u 1 5 | awk 'NR<=3 || $8>10'
# Thread-level CPU details
pidstat -u -t -p <PID> 1 5
# Context switch statistics
vmstat 1 | awk '{print $12, $13}'
pidstat -w 1 5
# history cpu stat
cat /proc/stat | grep cpu
```

---

## Memory Diagnostics

```bash
# Overview
free -h
# Detailed meminfo
cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Slab|SReclaimable|SUnreclaim|Dirty|Writeback|AnonPages|Mapped|Shmem|HugePages"
# Slab analysis
slabtop -o | head -20
# Process PSS (if smem installed)
smem -rkt -s pss | head -20
# Process memory mapping
pmap -x <PID> | tail -1
cat /proc/<PID>/status | grep -E "VmSize|VmRSS|VmSwap|Threads"
cat /proc/<PID>/smaps_rollup
# OOM Killer events
dmesg | grep -i "oom\|out of memory" | tail -20
dmesg | grep "Killed process"
```

---

## Disk I/O Diagnostics

```bash
# Disk IO stats
iostat -xz 1 5
# IO-heavy processes (batch mode)
iotop -oP -b -n 5 -d 1
# Process-level IO
pidstat -d 1 5
pidstat -d -p <PID> 1 5
# Filesystem space / inode summary
df -hT
df -i
du -sh /* 2>/dev/null | sort -rh | head -10
lsof +L1   # Deleted but still open files
```

---

## Network Diagnostics

```bash
# Connection overview
ss -s
ss -tan state time-wait | wc -l
ss -tn state established | awk '{print $4}' | awk -F: '{print $NF}' | sort | uniq -c | sort -rn | head -10
ss -tlnp
# NIC traffic (if sar available)
sar -n DEV 1 5
sar -n EDEV 1 5
sar -n TCP,ETCP 1 5
# Protocol stack counters
nstat -az | grep -i tcp
nstat -az | grep -E "TcpRetransSegs|TcpExtTCPLostRetransmit|TcpExtListenOverflows|TcpExtListenDrops|TcpExtTCPAbortOnMemory"
# NIC errors / drops
ethtool -S eth0 | grep -i error
ethtool -S eth0 | grep -i drop
ethtool -g eth0
cat /proc/net/softnet_stat
```

---

## Usage Notes

- **stat tools**: Recommend sampling with `interval 1 count 5` (e.g., `1 5`)
