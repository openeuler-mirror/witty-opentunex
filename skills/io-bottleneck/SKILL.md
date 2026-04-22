---
name: io-bottleneck
description: OS-level I/O bottleneck analysis. Analyzes disk utilization, I/O wait, queue depth, and memory压力 to identify OS-level I/O bottlenecks. Use when diagnosing disk I/O performance issues.
---

# OS I/O Bottleneck Analysis

This skill analyzes OS-level I/O performance bottlenecks.

---

## Scope Limitation

1. **OS Components Only**: Analyzes only OS-native kernel components (I/O Scheduler, Block Layer, Memory Management, Filesystem)
2. **No Application-Level Analysis**: Results show only OS-level bottlenecks
3. **Results**: Contain only OS-level bottleneck indicators and optimization suggestions

---

## Client Connection

skill:remote-execution

---

## Analysis Steps

### Step 1: Environment Check

Execute on remote host via `ssh -q -tt root@<IP>`:

```bash
lsblk -d -n -o NAME,SIZE,TYPE | grep -E 'disk|nvme' && echo "---" && cat /sys/block/vda/queue/scheduler 2>/dev/null | grep -o '\[.*\]'
```

### Step 2: Collect I/O Metrics (30 seconds)

Collect data in background:

```bash
(
  vmstat 1 30 > /tmp/vmstat_out.txt &
  iostat -xz 1 30 > /tmp/iostat_out.txt &
  mpstat -P ALL 1 30 > /tmp/mpstat_out.txt &
  wait
) 2>/dev/null
```

Then analyze the collected data:

```bash
echo "=== vmstat (key columns: r=runnable, b=blocked, wa=iowait) ==="
awk 'NR<=2 || /^[0-9]/' /tmp/vmstat_out.txt | head -15

echo "=== iostat (key: %util>90%, await>20ms indicates bottleneck) ==="
awk '/^Device/ || /^dm-|^vd|^sd/ {print}' /tmp/iostat_out.txt | head -30

echo "=== mpstat iowait per CPU ==="
awk '$3 ~ /^[0-9]+$/ && $6 > 5 {print "CPU " $3 ": iowait=" $6 "%"}' /tmp/mpstat_out.txt | sort -u
```

### Step 3: Blocked Process Analysis

```bash
echo "=== Blocked Processes (state D=uninterruptible I/O wait, S=interruptible) ==="
ps -eo pid,comm,state,wchan:32 | awk '$3 ~ /^[DS]$/ {print}' | head -20
```

### Step 4: Page Cache Pressure Analysis

```bash
echo "=== Page Cache Pressure ==="
cat /proc/sys/vm/vfs_cache_pressure
```

---

## Output Format

Based on collected data, determine:

```markdown
# OS I/O Bottleneck Analysis Report

## I/O Bottleneck Conclusion

**OS I/O Bottleneck Status**: [EXISTS / DOES NOT EXIST]

## Key Evidence

| Metric | Observed Value | Threshold | Status |
|--------|---------------|-----------|--------|
| CPU iowait % | X% | >20% | [CRITICAL/ELEVATED/NORMAL] |
| Disk %util | X% | >90% | [CRITICAL/ELEVATED/NORMAL] |
| Blocked processes | X | >CPU_count | [CRITICAL/ELEVATED/NORMAL] |
| IO await (ms) | Xms | >20ms | [CRITICAL/ELEVATED/NORMAL] |

## Bottleneck Type
| Type | Severity | Evidence |
|------|----------|----------|
| [Disk Saturation/CPU iowait/Memory/Swap] | [High/Medium/Low] | [Description] |

## Root Cause Inference
**Primary Cause**: [OS-level root cause]
**Affected Components**: [e.g., Block Layer, Memory Management]
**Inference Confidence**: [High/Medium/Low]

## OS-Level Recommendations
1. [Recommendation 1]
2. [Recommendation 2]
```

---

## Key Thresholds

| Indicator | Critical | Elevated | Normal |
|-----------|----------|----------|--------|
| CPU iowait % | >30% | 10-30% | <10% |
| Disk %util | >90% | 70-90% | <70% |
| Blocked processes | >CPU count | CPU_count/2 to CPU_count | <CPU_count/2 |
| IO await (ms) | >100ms | 20-100ms | <20ms |
| Queue size (aqu-sz) | >16 | 4-16 | <4 |

---

## Reference

see [references/io_analysis_report_example.md] for complete report example.
