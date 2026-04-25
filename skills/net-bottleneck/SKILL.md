---
name: net-bottleneck
description: OS-level Network bottleneck analysis. Analyzes network subsystem performance including bandwidth, latency, packet loss, connection states, and protocol stack efficiency to identify OS-level network bottlenecks.
---

# OS Network Bottleneck Analysis

This skill analyzes OS-level network performance bottlenecks.

---

## Scope Limitation

1. **OS Components Only**: Analyzes only OS-native kernel components (Network Stack, Protocol Timers, Interrupt Handling, NIC Driver)
2. **No Application-Level Analysis**: Results show only OS-level bottlenecks
3. **Results**: Contain only OS-level bottleneck indicators and optimization suggestions

---

## Client Connection

skill:remote-execution

---

## Analysis Steps

### Step 1: Socket Memory Analysis

```bash
echo "=== Socket Memory ===" && cat /proc/net/sockstat
```

### Step 2: Loopback Latency Test

```bash
echo "=== Loopback Latency ===" && ping -c 5 127.0.0.1 2>/dev/null | tail -2
```

---

## Output Format

```markdown
# OS Network Bottleneck Analysis Report

## Network Bottleneck Conclusion

**OS Network Bottleneck Status**: [EXISTS / DOES NOT EXIST]

## Key Evidence

| Metric | Observed | Threshold | Status |
|--------|----------|-----------|--------|
| Socket memory (used/orphaned) | X | >threshold | [CRITICAL/ELEVATED/NORMAL] |
| Loopback latency | Xms | >30ms | [CRITICAL/ELEVATED/NORMAL] |

## Bottleneck Type
| Type | Severity | Evidence |
|------|----------|----------|
| [Socket Memory/Protocol Latency] | [High/Medium/Low] | [Description] |

## Root Cause Inference
**Primary Cause**: [OS-level root cause]
**Affected Components**: [Network Stack/Protocol Timers]
**Inference Confidence**: [High/Medium/Low]

## OS-Level Recommendations (Only)
1. [Recommendation 1 - OS level only]
2. [Recommendation 2 - OS level only]
```

---

## Key Thresholds

| Indicator | Critical | Elevated | Normal |
|-----------|----------|----------|--------|
| Socket orphans | >1000 | 500-1000 | <500 |
| TCP memory used | >high threshold | medium | <low |
| Loopback latency | >100ms | 30-100ms | <30ms |

---

## Reference

see [references/net_analysis_report_example.md] for complete report example.
