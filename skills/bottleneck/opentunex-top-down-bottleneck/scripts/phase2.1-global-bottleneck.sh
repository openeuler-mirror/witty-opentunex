#!/bin/bash
# =============================================================================
# phase2.1-global-bottleneck.sh — Phase 2.1: Global Resource Bottleneck
# =============================================================================
# Usage: bash phase2.1-global-bottleneck.sh
# No parameters required. All commands are lightweight and safe to serialize.
# Total runtime: ~30 seconds (5s sampling × 4 resource categories, sequential).
# =============================================================================


collect_global_bottleneck() {
    echo "============================================================"
    echo "Phase 2.1: Global Resource Bottleneck Identification"
    echo "============================================================"
    echo ""

    echo "========== CPU Bottleneck Indicators =========="

    echo "--- CPU Utilization Per Core (5s sample, skip 100% idle) ---"
    mpstat -P ALL 1 5 | grep 'Average' | awk 'NR==1 || $3=="all" || $NF != "100.00"'

    echo ""
    echo "--- Load Average vs CPU Count ---"
    cat /proc/loadavg

    echo ""
    echo "--- Context Switches and Interrupts (5s interval) ---"
    vmstat 5 2 | awk 'NR<=2{print; next} NR==3{next} {print; exit}'

    echo ""
    echo "--- Top 30 Context Switch Tasks (by cswch/s) ---"
    { echo "      UID       PID   cswch/s nvcswch/s  Command"; pidstat -w 1 5 | grep 'Average' | grep -v "UID" | sort -k4 -rn | head -30; }

    echo ""

    echo "========== Memory Bottleneck Indicators =========="

    echo "--- Swap Usage and Pressure ---"
    free -h

    echo ""
    echo "--- Key Swap Metrics ---"
    cat /proc/meminfo | grep -E "SwapTotal|SwapFree|SwapCached|CommitLimit|Committed_AS"

    echo ""
    echo "--- Page Faults - Top 20 by majflt/s ---"
    { echo "      UID       PID  minflt/s  majflt/s     VSZ     RSS   %MEM  Command"; pidstat -r 1 5 | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20; }

    echo ""
    echo "--- Slab Memory Usage ---"
    cat /proc/meminfo | grep -E "Slab|SReclaimable|SUnreclaim"

    echo ""

    echo "========== I/O Bottleneck Indicators =========="

    echo "--- Disk Utilization (5s sample, skip 0% util) ---"
    iostat -xz 5 2 | awk '/^avg-cpu/{report++; if(report==2) print; next} /^Device/{if(report==2) print; next} /^$/{next} /Linux/{next} report==2 {if(/^[[:space:]]*[0-9]/){print; next} if(/^[a-z]/ && $NF+0>0){print; next}}'

    echo ""
    echo "--- Queue Depth (inflight_IO, instantaneous) ---"
    echo "major minor device inflight_IO" && cat /proc/diskstats | awk '{print $1, $2, $3, $12}'

    echo ""
    echo "--- Top 20 I/O Processes by kB_wr/s ---"
    { echo "      UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command"; pidstat -d 1 5 | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20; }

    echo ""

    echo "========== Network Bottleneck Indicators =========="

    echo "--- Network Interface Stats (5s sample, skip idle) ---"
    sar -n DEV 1 5 | grep 'Average' | awk 'NR==1 || $5+0>0 || $6+0>0'

    echo ""
    echo "--- Network Error Stats (skip all-zero errors) ---"
    sar -n EDEV 1 5 | grep 'Average' | awk 'NR==1{print; next} {for(i=3;i<=NF;i++) if($i+0>0){print; next}}'

    echo ""
    echo "--- TCP Retransmissions and Drops (5s two-snapshot delta) ---"
    nstat -az | grep -E "^(TcpOutSegs|TcpRetransSegs|TcpExtTCPLostRetransmit|TcpExtListenOverflows|TcpExtListenDrops)" | awk '{print $1,$2}' > /tmp/nstat_before.txt
    sleep 5
    nstat -az | grep -E "^(TcpOutSegs|TcpRetransSegs|TcpExtTCPLostRetransmit|TcpExtListenOverflows|TcpExtListenDrops)" | awk '{print $1,$2}' > /tmp/nstat_after.txt
    echo "counter delta rate/s"
    join /tmp/nstat_before.txt /tmp/nstat_after.txt | awk -v s=5 '{printf "%-40s %8d %8.1f\n", $1, $3-$2, ($3-$2)/s}'
    rm -f /tmp/nstat_before.txt /tmp/nstat_after.txt

    echo ""
    echo "--- Connection Backlog ---"
    echo "TIME_WAIT connections:" && ss -tan state time-wait | wc -l

    echo ""
    echo "--- Top 10 Ports by Established Connections ---"
    { echo "count port"; ss -tn state established | awk '{print $4}' | awk -F: '{print $NF}' | sort | uniq -c | sort -rn | head -10; }

    echo ""
    echo "============================================================"
    echo "Phase 2.1: Global Resource Bottleneck Identification Complete"
    echo "============================================================"
}

parse_param "$@"
collect_global_bottleneck
