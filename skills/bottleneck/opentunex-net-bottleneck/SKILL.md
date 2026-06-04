---
name: opentunex-net-bottleneck
description: OS-level Network bottleneck analysis. Analyzes network subsystem performance including bandwidth, latency, packet loss, connection states, and protocol stack efficiency to identify OS-level network bottlenecks.
---

# OS Network Bottleneck Analysis

This skill performs OS-level network performance bottleneck analysis.

---

## Analysis Command Execution

[1] only if **USER** has specified that remote command execution are allowed, Load the `opentunex-remote-execution` skill for standardized SSH connection and command execution.

[2] otherwise, Keep the following rule for command execution: Always read from user-given data collection files to analyze, command execution results should be saved in these files, if some extra commands are needed for analysis, **prioritize referencing existing scripts under this skill's `scripts/` directory** — provide the script path and usage. Only if no existing script covers the needed commands, generate a new script: output it to **USER** in the conversation, **simultaneously write it to a file in the current working directory** using the naming convention `<skill-name>-collect-step<N>.sh` (increment N each round, starting from 1; replace `<skill-name>` with this skill's short name, e.g., `net-bottleneck`). In all cases, provide usage instructions including: (1) how to execute the script, (2) how to save output (e.g., redirect to a results file), (3) ask user to provide the result file for subsequent analysis. Never execute command automatically.

**Data Collection File Conventions**:
- File path: current working directory
- File naming: `<skill-short-name>-result-<YYYYMMDD-HHMMSS>.txt` (e.g., `net-bottleneck-result-20260604-143000.txt`)
- File format: plain text with `=== Section Name ===` section headers
- For multiple collection rounds, save each round's output separately with incremented timestamps
- When referencing prior data, explicitly state the file name and section header

---

## Phase 1: Data Collection

**Collection Command**: Run `scripts/collect_net_metrics.sh [--pid <PID>] [--duration <SECONDS>]` to collect network metrics (default 10 seconds, PID optional for per-process socket statistics).

**Output**:
- System overview
- Network interface status
- Network sysctl configuration (TCP buffer, congestion control, timeouts)
- Socket memory statistics
- NIC queue and IRQ settings
- NIC driver, ring, coalesce, pause, offload, and IRQ affinity details
- sar DEV/EDEV dynamic metrics (for collection duration)
- Gateway and loopback latency test results
- TCP statistics (netstat -s)
- Socket summary and memory (ss -s, /proc/net/sockstat)
- TCP connection state distribution

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
# OS Network Bottleneck Analysis Report

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

## Error Handling

- **ethtool/perf not available**: Skip NIC detail sections or perf-based latency analysis; document which data is missing and note the limitation in the report.
- **Permission denied**: Some sysctl paths and /proc/net entries require root; if access is denied, report the missing data and suggest running with elevated privileges.
- **Target process exited**: If --pid is specified but the process has exited, fall back to system-wide collection and note the process absence.
- **sar not installed**: Fall back to `cat /proc/net/dev` at interval endpoints; document the reduced granularity in the report.

---

## Operational Notes

- **basic principle**: All analysis must be specific and evidence-based.
- **Iteration**: If evidence is insufficient, narrow focus and deepen analysis.
- **Completion**: All phases must be fully executed before concluding.
- **Scope Constraint — OS Level Only**: This skill analyzes ONLY OS-level information. Do NOT collect or interpret application-layer data.
