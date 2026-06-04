---
name: opentunex-mem-bottleneck
description: OS-level Memory bottleneck analysis. Analyzes memory utilization, swap activity, page faults, memory bandwidth, NUMA/Cluster access patterns to identify OS-level Memory bottlenecks including memory-access-intensive scenarios.
---

# OS Memory Bottleneck Analysis

This skill performs OS-level memory performance bottleneck analysis, including memory-access-intensive scenarios where memory usage is low but memory bandwidth or NUMA access patterns cause performance issues.

---

## Analysis Command Execution

[1] only if **USER** has specified that remote command execution are allowed, Load the `opentunex-remote-execution` skill for standardized SSH connection and command execution.

[2] otherwise, Keep the following rule for command execution: Always read from user-given data collection files to analyze, command execution results should be saved in these files, if some extra commands are needed for analysis, **prioritize referencing existing scripts under this skill's `scripts/` directory** — provide the script path and usage. Only if no existing script covers the needed commands, generate a new script: output it to **USER** in the conversation, **simultaneously write it to a file in the current working directory** using the naming convention `<skill-name>-collect-step<N>.sh` (increment N each round, starting from 1; replace `<skill-name>` with this skill's short name, e.g., `mem-bottleneck`). In all cases, provide usage instructions including: (1) how to execute the script, (2) how to save output (e.g., redirect to a results file), (3) ask user to provide the result file for subsequent analysis. Never execute command automatically.

**Data Collection File Conventions**:
- File path: current working directory
- File naming: `<skill-short-name>-result-<YYYYMMDD-HHMMSS>.txt` (e.g., `mem-bottleneck-result-20260604-143000.txt`)
- File format: plain text with `=== Section Name ===` section headers
- For multiple collection rounds, save each round's output separately with incremented timestamps
- When referencing prior data, explicitly state the file name and section header

---

## Phase 1: Data Collection

**Collection Command**: Run `scripts/collect_mem_metrics.sh --pid [PID]` to collect memory metrics (PID optional).

**Output**:
- System overview (kernel version, CPU count, total memory)
- Memory Pressure (PSI: some avg10/avg60/avg300, full avg10/avg60/avg300)
- Memory usage (free -h output)
- VM OOM stats (oom_kill, pgmajfault counters)
- Swap configuration (swapon -s)
- Slab info (top 30 entries from /proc/slabinfo)
- Vmalloc region (VmallocTotal, VmallocUsed)
- Memory allocation/reclaim stats (pgfault, pgmajflt, pgalloc, pgfree, pgscank, pgscand, pgsteal, pgrotated)
- Memory details (Active, Inactive, SReclaimable, SUnreclaim, Shmem, VmallocUsed, Committed_AS)
- HugePages configuration (nr_hugepages, HugePages_Total/Free/Rsvd, Hugepagesize, transparent_hugepage)
- OOM configuration (oom_kill_allocating_task, oom_dump_tasks)
- KSM configuration (ksm.run, pages_shared, pages_sharing)
- NUMA balancing setting
- Memory CGroup limits (limit_in_bytes, soft_limit, usage)
- Memory watermarks (watermark_scale_factor, watermark_boost_factor)
- Memory zone info per NUMA node
- jemalloc configuration (MALLOC_ARENA_MAX, MALLOC_CONF, detection in target process)
- NUMA statistics (system-wide numa_hit/miss/foreign/local/other)
- Process NUMA memory distribution and cross-NUMA warning — if PID specified
- NUMA node layout (numactl --hardware, numactl --show)
- Recent OOM events (dmesg/journalctl)

---

## Phase 2: Key Metrics Analysis

### Key Metrics to Analyze

| Category | Key Metrics | Anomaly Detection |
|----------|-------------|-------------------|
| Memory Capacity | Memory Used%, MemAvailable%, Swap Used, Committed_AS% | Memory Used > 85% (elevated); > 95% (critical); MemAvailable < 15% (elevated); < 5% (critical); Swap Used > 0 (elevated); Committed_AS > 100% (overcommit risk) |
| Memory PSI | memory stall % (some avg10, full avg10) | some avg10 > 30% (elevated); > 50% (critical); full avg10 > 50% (sustained pressure) |
| Page Faults | majflt/s, pgscank/s, pgscand/s | majflt/s > 100 (elevated); > 1000 (critical swap thrashing); pgscank/s > 1000 (kswapd aggressive); pgscand/s > 1000 (direct reclaim storm) |
| Memory Allocation/Reclaim | pgalloc, pgfree, pgfault, pgsteal; Active/Inactive ratio | pgfault > 10000/s (allocation pressure); Active/Inactive < 1 (memory pressure); pgsteal > 5000 (reclaim overhead) |
| Slab Allocator | Slab%, SUnreclaim%, slabinfo top consumers | Slab > 30% (elevated); > 50% (critical); SUnreclaim > 70% of Slab (kernel memory fragmentation) |
| HugePages | nr_hugepages, HugePages_Free vs Total, Hugepagesize, transparent_hugepage | HugePages_Free = Total (never used, wasted); Free > 50% of Total (over-provisioned); transparent_hugepage=always (performance variance) |
| OOM | oom_kill_allocating_task, oom_dump_tasks | oom_kill_allocating_task=1 (kill cause, not victim) |
| KSM (Kernel Samepage Merging) | ksm.run, pages_shared, pages_sharing | pages_sharing >> pages_shared (effective deduplication) |
| NUMA Balancing | numa_balancing enabled | numa_balancing=1 (auto NUMA awareness); =0 (disable) |
| Memory CGroup | memory.limit_in_bytes, soft_limit vs usage | usage close to limit (cgroup pressure) |
| Memory Watermarks | watermark_scale_factor | >10 (aggressive reclaim); <3 (latency-sensitive) |
| jemalloc | MALLOC_ARENA_MAX, arena count vs CPU count | arena > 4x CPU count (jemalloc fragmentation); jemalloc dirty not released |
| NUMA Access | numa_hit, numa_miss, numa_foreign, cross-NUMA ratio, node distances | numa_miss > 20% (elevated); > 30% (critical); cross-NUMA ratio > 30% (elevated); > 50% (critical); node distance > 30 (remote access penalty) |

---

## Phase 3: Bottleneck Identification

### Output Format

```markdown
# OS Memory Bottleneck Analysis Report

## Memory Bottleneck Conclusion
**OS Memory Bottleneck Status**: [EXISTS / DOES NOT EXIST]
**Bottleneck Subtype**: [Memory Capacity/Memory Access Intensity/NUMA Access Pattern]

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
| majflt/s | X | >100 | [CRITICAL/ELEVATED/NORMAL] |
| pgscank/s | X | >1000 | [CRITICAL/ELEVATED/NORMAL] |
| pgscand/s | X | >1000 | [CRITICAL/ELEVATED/NORMAL] |

### NUMA Access Metrics
| Metric | Observed Value | Threshold | Status |
|--------|---------------|-----------|--------|
| NUMA Miss % | X% | >20% | [CRITICAL/ELEVATED/NORMAL] |
| Cross-NUMA Access | X | >30% | [CRITICAL/ELEVATED/NORMAL] |

## Bottleneck Type
| Type | Severity | Evidence |
|------|----------|----------|
| [Memory Saturation/NUMA Access/Slab Pressure] | [High/Medium/Low] | [Description] |

## Root Cause Inference
**Primary Cause**: [OS-level root cause]
**Affected Components**: [e.g., Memory Management, NUMA Subsystem]
**Inference Confidence**: [High/Medium/Low]

## OS-Level Recommendations
1. [Recommendation 1]
2. [Recommendation 2]
```

---

## Error Handling

- **/proc/slabinfo not readable**: Requires root; if access is denied, fall back to Slab/SReclaimable/SUnreclaim from /proc/meminfo and note the limitation.
- **numactl/numastat not available**: Skip per-NUMA-node analysis; document missing data and suggest installing numactl package.
- **Target process exited**: If --pid is specified but the process has exited, fall back to system-wide memory analysis and note the process absence.
- **PSI not available**: If /proc/pressure/mem is missing, fall back to vmstat (si/so) and /proc/vmstat counters for memory pressure indication.

---

## Operational Notes

- **basic principle**: All analysis must be specific and evidence-based.
- **Iteration**: If evidence is insufficient, narrow focus and deepen analysis.
- **Completion**: All phases must be fully executed before concluding.
- **Scope Constraint — OS Level Only**: This skill analyzes ONLY OS-level information. Do NOT collect or interpret application-layer data.
