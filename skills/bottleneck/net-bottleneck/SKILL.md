---
name: net-bottleneck
description: OS-level Network bottleneck analysis. Analyzes network subsystem performance including bandwidth, latency, packet loss, connection states, and protocol stack efficiency to identify OS-level network bottlenecks.
---

# OS Network Bottleneck Analysis

This skill performs OS-level network performance bottleneck analysis.

---

## Analysis Command Execution

[1] only if **USER** has specified that remote command execution are allowed, Load the `remote-execution` skill for standardized SSH connection and command execution.

[2] otherwise, Keep the following rule for command execution: Always read from user-given data collection files to analyze, command execution results should be saved in these files, if some extra commands are needed for analysis, output command execution script to **USER**, and ask **USER** to provide execution results, never execute command automatically.

---

## Phase 1: Data Collection

**Collection Command**: Run `scripts/collect_net_metrics.sh` to collect network metrics (15 seconds).

**Output**:
- System overview
- Network interface status
- Network sysctl configuration (TCP buffer, congestion control, timeouts)
- Socket memory statistics
- NIC queue and IRQ settings
- 15-second sar (DEV, EDEV), netstat, ss dynamic metrics

---

## Phase 2: Key Metrics Analysis

### Key Metrics to Analyze

| Category | Key Metrics | Anomaly Detection |
|----------|-------------|-------------------|
| TCP Socket Memory | TCP mem (used/high/thresh), orphans | orphans > 1000 (critical); TCP mem > high_thresh (pressure) |
| TCP Connection States | ListenDrops, ListenOverflows, TIME_WAIT, established, synrecv | ListenDrops > 0 (critical); TIME_WAIT > 5000 (elevated); established > 10000 (connection leak); synrecv > 100 (syn queue buildup) |
| TCP Retransmission | RetransSegs, OutSegs, Retrans rate | Retrans rate > 2% (network issue); > 10% (critical) |
| TCP Errors | EstabResets, EmbryonicRST, PruneCalled | EstabResets > 100/s (connection issues); PruneCalled > 0 (memory pressure) |
| Network Throughput | rxkB/s, txkB/s per interface | rxkB/s or txkB/s near line rate (bottleneck) |
| Network Packet Rate | rxpck/s, txpck/s per interface | rxpck/s > 100000 (interrupt storm) |
| Network Errors | rxerr/s, txerr/s, drop/s, fifer/s | rxerr/s > 0 (hardware issue); drop/s > 0 (buffer overflow) |
| Network Softirq | softirq% of total CPU, NET_RX/TX rates | softirq% > 30% (elevated); > 50% (critical) |
| TCP Latency | RTT (ping), tcp_tw_reuse, tcp_timestamps | RTT > 30ms (elevated); > 100ms (critical) |
| Socket Backlog | tcp_max_syn_backlog, somaxconn | tcp_max_syn_backlog reached (connection drops) |
| Buffer Tuning | tcp_rmem, tcp_wmem, rmem_max, wmem_max | current buffer vs max buffer ratio < 50% (underutilized) |

### Network I/O Pattern Detection

| Pattern | Indicators | Detection |
|---------|-----------|-----------|
| High Throughput | rxkB/s + txkB/s near line rate | Bandwidth saturation |
| Connection Flood | synrecv > 100, ListenDrops > 0 | SYN flood or connection storm |
| Memory Pressure | PruneCalled > 0, TCP mem > high | Socket buffer exhaustion |
| Latency Issue | Retrans > 2%, RTT elevated | Network quality problem |

---

## Phase 3: Bottleneck Identification

### Output Format

```markdown
# OS Network Bottottleneck Analysis Report

## Network Bottleneck Conclusion
**OS Network Bottleneck Status**: [EXISTS / DOES NOT EXIST]

## Key Evidence
| Metric | Observed | Threshold | Status |
|--------|----------|-----------|--------|
| Socket orphans | X | >1000 | [CRITICAL/ELEVATED/NORMAL] |
| TCP memory | X | >high_thresh | [CRITICAL/ELEVATED/NORMAL] |
| TIME_WAIT | X | >5000 | [CRITICAL/ELEVATED/NORMAL] |
| Retrans rate | X% | >2% | [CRITICAL/ELEVATED/NORMAL] |
| RTT latency | Xms | >30ms | [CRITICAL/ELEVATED/NORMAL] |

## Bottleneck Type
| Type | Severity | Evidence |
|------|----------|----------|
| [Socket Memory/TCP Retrans/Connection Exhaustion/Bandwidth Saturation] | [High/Medium/Low] | [Description] |

## Root Cause Inference
**Primary Cause**: [OS-level root cause]
**Affected Components**: [Network Stack/Protocol Timers/NIC]
**Inference Confidence**: [High/Medium/Low]

## OS-Level Recommendations
1. [Recommendation 1]
2. [Recommendation 2]
```

---

## Operational Notes

- **basic principle**: All analysis must be specific and evidence-based.
- **Iteration**: If evidence is insufficient, narrow focus and deepen analysis.
- **Completion**: All phases must be fully executed before concluding.
- **Scope Constraint — OS Level Only**: This skill analyzes ONLY OS-level information. Do NOT collect or interpret application-layer data.
