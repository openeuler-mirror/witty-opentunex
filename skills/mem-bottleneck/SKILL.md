---
name: mem-bottleneck
description: OS-level Memory bottleneck analysis. Analyzes memory utilization, swap activity, page faults, memory bandwidth, NUMA/Cluster access patterns to identify OS-level Memory bottlenecks including memory-access-intensive scenarios.
---

# OS Memory Bottleneck Analysis

This skill analyzes OS-level memory performance bottlenecks, including memory-access-intensive scenarios where memory usage is low but memory bandwidth or NUMA access patterns cause performance issues.

---

## Scope Limitation

1. **OS Components Only**: Analyzes only OS-native kernel components (Memory Management, Slab Allocator, NUMA, Virtual Memory, Page Cache, Memory Controller)
2. **No Application-Level Analysis**: Results show only OS-level bottlenecks
3. **Results**: Contain only OS-level bottleneck indicators and optimization suggestions

---

## Client Connection

skill:remote-execution

---

## Analysis Steps

### Step 1: PSI Memory Pressure Analysis

```bash
echo "=== Memory Pressure Level (PSI) ===" && if [ -f /proc/pressure/mem ]; then cat /proc/pressure/mem; else echo "pressure not available"; fi
```

### Step 2: OOM Event Analysis

```bash
echo "=== VM OOM Stats ===" && cat /proc/vmstat | grep -E 'oom|pgmajfault'
```

```bash
echo "=== Recent OOM Events ===" && dmesg -T 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10 || journalctl -k 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10
```

### Step 3: Swap Configuration Analysis

```bash
echo "=== Swap Configuration ===" && swapon -s 2>/dev/null || cat /proc/swaps
```

### Step 4: Slab and Vmalloc Analysis

```bash
echo "=== Slab Memory Detail ===" && cat /proc/slabinfo 2>/dev/null | head -30
```

```bash
echo "=== Vmalloc Region ===" && cat /proc/meminfo | grep -E "VmallocTotal|VmallocUsed"
```

### Step 5: NUMA Statistics Analysis

```bash
echo "=== NUMA Hit/Miss Stats ===" && cat /proc/vmstat | grep -E "numa_hit|numa_miss|numa_foreign|numa_local|numa_other" | head -20
```

```bash
echo "=== NUMA Policy ===" && if command -v numactl &>/dev/null; then numactl --policy; else echo "numactl not installed"; fi
```

```bash
echo "=== Memory Binding ===" && cat /proc/self/status | grep -E "Mems_allowed|Mems_allowed_node"
```

### Step 6: Per-Process NUMA Hints

```bash
echo "=== Per-Process NUMA Info ===" && if [ -f /proc/self/sched ]; then cat /proc/self/sched 2>/dev/null | head -10; else echo "per-process NUMA info not available"; fi
```

---

## Output Format

Based on collected data, determine:

```markdown
# OS Memory Bottleneck Analysis Report

## Memory Bottleneck Conclusion

**OS Memory Bottleneck Status**: [EXISTS / DOES NOT EXIST]
**Bottleneck Subtype**: [Memory Capacity/Memory Access Intensity/NUMA Access Pattern/Cluster Access Pattern]

## Key Evidence

### Memory Capacity Metrics
| Metric | Observed Value | Threshold | Status |
|--------|---------------|-----------|--------|
| Memory Used % | X% | >90% | [CRITICAL/ELEVATED/NORMAL] |
| MemAvailable % | X% | <15% | [CRITICAL/ELEVATED/NORMAL] |
| Swap Used | X GB | >0 | [CRITICAL/ELEVATED/NORMAL] |
| Committed_AS % | X% | >100% | [CRITICAL/ELEVATED/NORMAL] |

### Memory Access Intensity Metrics
| Metric | Observed Value | Threshold | Status |
|--------|---------------|-----------|--------|
| CPU Sys % | X% | >30% | [CRITICAL/ELEVATED/NORMAL] |
| Context Switches/s | X | >10000 | [CRITICAL/ELEVATED/NORMAL] |
| Interrupts/s | X | >10000 | [CRITICAL/ELEVATED/NORMAL] |
| Page Faults/s | X | >5000 | [CRITICAL/ELEVATED/NORMAL] |

### NUMA/Cluster Access Metrics
| Metric | Observed Value | Threshold | Status |
|--------|---------------|-----------|--------|
| NUMA Miss % | X% | >20% | [CRITICAL/ELEVATED/NORMAL] |
| Cross-NUMA Access | X | High | [CRITICAL/ELEVATED/NORMAL] |

## Bottleneck Type
| Type | Severity | Evidence |
|------|----------|----------|
| [Memory Saturation/Memory Access Intensity/NUMA Access/Cluster Access] | [High/Medium/Low] | [Description] |

## Root Cause Inference
**Primary Cause**: [OS-level root cause]
**Affected Components**: [e.g., Memory Management, NUMA Subsystem, Memory Controller]
**Inference Confidence**: [High/Medium/Low]

## OS-Level Recommendations
1. [Recommendation 1]
2. [Recommendation 2]
```

---

## Key Thresholds

### Memory Capacity
| Indicator | Critical | Elevated | Normal |
|-----------|----------|----------|--------|
| Memory Used % | >95% | 85-95% | <85% |
| MemAvailable % | <5% | 5-15% | >15% |
| Swap Used | >1GB | 100MB-1GB | ~0 |
| Committed_AS % | >100% | 95-100% | <95% |

### Memory Access Intensity
| Indicator | Critical | Elevated | Normal |
|-----------|----------|----------|--------|
| CPU Sys % | >40% | 20-40% | <20% |
| Context Switches/s | >15000 | 8000-15000 | <8000 |
| Interrupts/s | >15000 | 8000-15000 | <8000 |
| majflt/s | >100 | 20-100 | <20 |
| CPU wa (iowait) % | >30% | 10-30% | <10% |

### NUMA/Cluster Access
| Indicator | Critical | Elevated | Normal |
|-----------|----------|----------|--------|
| NUMA Miss % | >30% | 10-30% | <10% |
| Cross-NUMA Access | >30% of memory ops | 10-30% | <10% |

---

## Reference

see [references/mem_analysis_report_example.md] for complete report example.
