# Bottleneck Analysis Guidelines
---

## Bottleneck Categories

### Topology Misalignment
- Operator dispatch threads not on NUMA nodes affiliated with their NPU
- Evidence: Slow dispatch, high memory latency

### L3 Cache Contention
- Dispatch thread shares NUMA with cache-heavy thread
- Evidence: High LLC misses, increased memory access latency

### Communication Distance
- High inter-process/thread communication between entities with large physical/NUMA distance
- Evidence: Elevated latency in communication paths

### CPU Affinity Over-concentration
- Too many threads pinned to same CPUs
- Evidence: High resource occupancy, scheduling conflicts

### Memory Pressure
- Excessive memory on single NUMA node
- Evidence: Frequent page-ins/outs, degraded memory performance

### Context Switch Anomalies

| Type | Indicator | Cause |
|------|-----------|-------|
| High voluntary | Frequent CPU yields | I/O waits, synchronization bottlenecks, locking |
| High involuntary | Thread preemption | CPU saturation, inefficient scheduling, overutilized cores |

---

## Analysis Procedure

1. Identify hot processes from topology data (high CPU%, memory usage, context switches)
2. For each hot process, identify key threads (main thread, dispatch threads, worker threads)
3. Map each to potential bottleneck category
4. Record evidence from topology data

---

## Output Template

```markdown
## Bottleneck Summary
(Summary of: topology affinity issues, cache contention, communication distance, CPU distribution, memory pressure, context switch anomalies)

Note: Mark "Not Bottleneck" for threads with no identified issues.

## Hot Process/Thread & Bottleneck Mapping
| PID | TID | Name | Role | Key Function | Main Bottleneck/Evidence |
|-----|-----|------|------|--------------|--------------------------|
| 1234 | 1234 | worker_main | Main | Process coordinator | NUMA misalignment: on NUMA 0, NPU on NUMA 1 |
| 1234 | 1235 | dispatch | Dispatch | Operator dispatch | LLC contention: shares NUMA with cache-heavy thread 5678 |
| 1234 | 1236 | compute | Worker | Computation | Not Bottleneck |
| 2345 | 2345 | worker_2 | Main | Process coordinator | High involuntary ctx switches: CPU cores overutilized |
```
