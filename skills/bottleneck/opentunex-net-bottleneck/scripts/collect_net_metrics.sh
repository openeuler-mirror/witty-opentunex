#!/bin/bash
# collect_net_metrics.sh - Collect network metrics for bottleneck analysis
#
# Usage:
#   bash collect_net_metrics.sh [--pid <PID>] [--duration <SECONDS>]
#
# Parameters:
#   --pid      — Target process PID for per-process socket statistics (optional)
#   --duration — Collection duration in seconds (default: 10)
#
# Examples:
#   # Default 10-second collection:
#   bash collect_net_metrics.sh
#
#   # 30-second collection:
#   bash collect_net_metrics.sh --duration 30
#
#   # Target process collection:
#   bash collect_net_metrics.sh --pid 12345 --duration 30
#
# Save output to file:
#   bash collect_net_metrics.sh --pid 12345 --duration 30 > net_result.txt 2>&1

DURATION=10
TARGET_PID=""
INTERVAL=1

parse_param() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pid)
                TARGET_PID="$2"
                shift 2
                ;;
            --duration)
                DURATION="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Usage: bash $0 [--pid <PID>] [--duration <SECONDS>]" >&2
                exit 1
                ;;
        esac
    done

    if [ -n "$TARGET_PID" ]; then
        if ! [[ "$TARGET_PID" =~ ^[0-9]+$ ]]; then
            echo "Error: --pid must be a numeric value, got: $TARGET_PID" >&2
            exit 1
        fi

        if [ ! -d "/proc/$TARGET_PID" ]; then
            echo "Error: Process with PID $TARGET_PID does not exist" >&2
            exit 1
        fi
    fi
}

collect_net_metrics() {
    echo "=== Network Metrics Collection ==="
    echo "Duration: $DURATION seconds"
    if [ -n "$TARGET_PID" ]; then
        echo "Target PID: $TARGET_PID"
    fi
    echo ""

    echo "=== Network Interfaces ==="
    ip -br link show
    echo ""

    echo "=== Network Sysctl Configuration ==="
    echo "tcp_tw_reuse: $(cat /proc/sys/net/ipv4/tcp_tw_reuse 2>/dev/null || echo 'N/A')"
    echo "tcp_timestamps: $(cat /proc/sys/net/ipv4/tcp_timestamps 2>/dev/null || echo 'N/A')"
    echo "tcp_sack: $(cat /proc/sys/net/ipv4/tcp_sack 2>/dev/null || echo 'N/A')"
    echo "tcp_window_scaling: $(cat /proc/sys/net/ipv4/tcp_window_scaling 2>/dev/null || echo 'N/A')"
    echo "tcp_congestion_control: $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo 'N/A')"
    echo "tcp_rmem: $(cat /proc/sys/net/ipv4/tcp_rmem 2>/dev/null || echo 'N/A')"
    echo "tcp_wmem: $(cat /proc/sys/net/ipv4/tcp_wmem 2>/dev/null || echo 'N/A')"
    echo "tcp_mem: $(cat /proc/sys/net/ipv4/tcp_mem 2>/dev/null || echo 'N/A')"
    echo "tcp_max_syn_backlog: $(cat /proc/sys/net/ipv4/tcp_max_syn_backlog 2>/dev/null || echo 'N/A')"
    echo "tcp_fin_timeout: $(cat /proc/sys/net/ipv4/tcp_fin_timeout 2>/dev/null || echo 'N/A')"
    echo "ip_local_port_range: $(cat /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null || echo 'N/A')"
    echo "netdev_max_backlog: $(cat /proc/sys/net/core/netdev_max_backlog 2>/dev/null || echo 'N/A')"
    echo "netdev_budget: $(cat /proc/sys/net/core/netdev_budget 2>/dev/null || echo 'N/A')"
    echo "somaxconn: $(cat /proc/sys/net/core/somaxconn 2>/dev/null || echo 'N/A')"
    echo "rmem_default: $(cat /proc/sys/net/core/rmem_default 2>/dev/null || echo 'N/A')"
    echo "rmem_max: $(cat /proc/sys/net/core/rmem_max 2>/dev/null || echo 'N/A')"
    echo "wmem_default: $(cat /proc/sys/net/core/wmem_default 2>/dev/null || echo 'N/A')"
    echo "wmem_max: $(cat /proc/sys/net/core/wmem_max 2>/dev/null || echo 'N/A')"
    echo ""

    echo "=== NIC Configuration ==="
    for iface in $(ip -br link show | awk '$2=="UP" {print $1}' | grep -v lo | head -3); do
        echo "--- $iface ---"
        echo "Link: $(ethtool $iface 2>/dev/null | grep -E 'Speed|Duplex|Link detected|Auto-negotiation' | sed 's/^\t*//')"
        echo "Driver: $(ethtool -i $iface 2>/dev/null | grep -E 'driver|version|firmware|bus-info' | sed 's/^[^:]*: //' | paste -sd, -)"
        echo ""
        echo "[Queue/Channel]"
        ethtool -l $iface 2>/dev/null
        echo ""
        echo "[Ring]"
        ethtool -g $iface 2>/dev/null
        echo ""
        echo "[Coalesce]"
        ethtool -c $iface 2>/dev/null
        echo ""
        echo "[Pause]"
        ethtool -a $iface 2>/dev/null
        echo ""
        echo "[Offload]"
        ethtool -k $iface 2>/dev/null
        echo ""
        BUS_INFO=$(ethtool -i $iface 2>/dev/null | grep 'bus-info' | awk '{print $2}')
        if [ -n "$BUS_INFO" ]; then
            echo "--- IRQ Affinity ---"
            grep "$BUS_INFO" /proc/interrupts 2>/dev/null | while read -r line; do
                IRQ=$(echo "$line" | awk '{print $1}' | tr -d ':')
                AFFINITY=$(cat /proc/irq/$IRQ/smp_affinity 2>/dev/null || echo 'N/A')
                DESC=$(echo "$line" | awk '{for(i=131;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
                echo "IRQ $IRQ: $AFFINITY  ($DESC)"
            done
        fi
        echo ""
    done

    ACTIVE_IFACES=$(ip -br link show | awk '$2=="UP" && $1!="lo" {print $1}' | paste -sd,)
    sar -n DEV $INTERVAL $DURATION --iface=$ACTIVE_IFACES > /tmp/sar_dev_out.txt 2>&1 &
    SAR_DEV_PID=$!
    sar -n EDEV $INTERVAL $DURATION --iface=$ACTIVE_IFACES > /tmp/sar_edeve_out.txt 2>&1 &
    SAR_EDEV_PID=$!

    GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
    ping -c 5 $GATEWAY 2>/dev/null > /tmp/ping_gw_out.txt &
    PING_GW_PID=$!
    ping -c 5 127.0.0.1 2>/dev/null > /tmp/ping_lo_out.txt &
    PING_LO_PID=$!

    wait $SAR_DEV_PID $SAR_EDEV_PID $PING_GW_PID $PING_LO_PID 2>/dev/null

    echo "--- Network Device Stats (sar -n DEV) ---"
    tail -n +4 /tmp/sar_dev_out.txt
    echo ""
    echo "--- Network Error Stats (sar -n EDEV) ---"
    tail -n +4 /tmp/sar_edeve_out.txt
    echo ""
    echo "--- Latency Test (to gateway) ---"
    echo "Default gateway: $GATEWAY"
    [ -s /tmp/ping_gw_out.txt ] && tail -2 /tmp/ping_gw_out.txt || echo "No gateway found"
    echo ""
    echo "--- Loopback Latency Test ---"
    tail -2 /tmp/ping_lo_out.txt
    echo ""

    echo "--- TCP Statistics ---"
    netstat -s 2>/dev/null | sed -n '/^Tcp:/,/^$/p' | head -50
    echo ""

    echo "--- Socket Summary ---"
    ss -s 2>/dev/null
    echo ""

    echo "--- Socket Memory ---"
    cat /proc/net/sockstat
    echo ""

    echo "--- TCP Connection States ---"
    ss -tan 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -10
    echo ""

    if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
        echo "=== Target Process Socket Statistics ==="
        echo "Process: $(cat /proc/$TARGET_PID/comm 2>/dev/null || echo 'unknown')"
        echo "--- Open Sockets ---"
        ss -tanp 2>/dev/null | grep "pid=$TARGET_PID" | head -30
        echo ""
        echo "--- Socket State Summary ---"
        ss -tanp 2>/dev/null | grep "pid=$TARGET_PID" | awk '{print $1}' | sort | uniq -c | sort -rn
        echo ""
        echo "--- Socket Memory for PID $TARGET_PID ---"
        ss -tmp 2>/dev/null | grep "pid=$TARGET_PID" | head -20
        echo ""
        echo "--- Process Network Connections Count ---"
        TOTAL_CONN=$(ss -tanp 2>/dev/null | grep -c "pid=$TARGET_PID" || echo 0)
        echo "Total TCP connections: $TOTAL_CONN"
        echo ""
    fi

    echo "=== Collection Complete ==="
}

parse_param "$@"
collect_net_metrics
