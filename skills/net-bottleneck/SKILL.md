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

### Step 1: Quick Environment Check

Execute on remote host via `ssh -q -tt root@<IP>`:

```bash
uname -r && echo "---" && ss -s && echo "---" && cat /proc/net/sockstat
```

### Step 2: Connection State Analysis

```bash
echo "=== TCP Connection States ==="
ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn | head -10

echo "=== Socket Memory ==="
cat /proc/net/sockstat
```

### Step 3: TCP Stats

```bash
echo "=== TCP Retrans & Reset Stats ==="
netstat -s | grep -E "retransmitted|resets sent|Timeouts" | head -10
```

### Step 4: Latency Test

```bash
echo "=== Loopback Latency ==="
ping -c 5 127.0.0.1 2>/dev/null | tail -2
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
| TIME_WAIT connections | X | >5000 | [CRITICAL/ELEVATED/NORMAL] |
| FIN-WAIT-2 connections | X | >1000 | [CRITICAL/ELEVATED/NORMAL] |
| TCP retrans segments | X | >100 | [CRITICAL/ELEVATED/NORMAL] |
| Loopback latency | Xms | >30ms | [CRITICAL/ELEVATED/NORMAL] |

## Bottleneck Type
| Type | Severity | Evidence |
|------|----------|----------|
| [Connection Exhaustion/Latency/Retrans/Error] | [High/Medium/Low] | [Description] |

## Root Cause Inference
**Primary Cause**: [OS-level root cause]
**Affected Components**: [Network Stack/NIC/Timers]
**Inference Confidence**: [High/Medium/Low]

## OS-Level Recommendations (Only)
1. [Recommendation 1 - OS level only]
2. [Recommendation 2 - OS level only]
```

---

## Key Thresholds

| Indicator | Critical | Elevated | Normal |
|-----------|----------|----------|--------|
| TIME_WAIT conns | >10000 | 5000-10000 | <5000 |
| FIN-WAIT-2 conns | >5000 | 1000-5000 | <1000 |
| TCP retrans | >1000/s | 100-1000/s | <100/s |
| Loopback latency | >100ms | 30-100ms | <30ms |

---

## Reference

see [references/net_analysis_report_example.md] for complete report example.
