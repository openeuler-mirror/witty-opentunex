#!/bin/bash
# collect_net_metrics.sh - Collect network metrics for bottleneck analysis
# Usage: collect_net_metrics.sh [duration in seconds]

DURATION=${1:-15}
INTERVAL=1

echo "=== Network Metrics Collection ==="
echo "Duration: $DURATION seconds"
echo "Interval: $INTERVAL second"
echo ""

# System info
echo "=== System Overview ==="
uname -r
echo "CPU Count: $(nproc)"
echo ""

# Network interfaces
echo "=== Network Interfaces ==="
ip -br link show
echo ""

# Network sysctl configuration
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

# Socket memory
echo "=== Socket Memory ==="
cat /proc/net/sockstat
echo ""

# Default gateway and latency
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
echo "Default gateway: $GATEWAY"
echo ""

# NIC queue, ring and offload settings
echo "=== NIC Configuration ($iface) ==="
for iface in $(ip -br link show | awk '{print $1}' | grep -v lo | head -5); do
    echo "--- $iface ---"
    ethtool -l $iface 2>/dev/null | grep -E "Current|pre-set"
    ethtool -g $iface 2>/dev/null | grep -E "Current|pre-set"
    echo "speed: $(ethtool $iface 2>/dev/null | grep Speed | awk '{print $2}')"
    echo "mtu: $(ip link show $iface 2>/dev/null | grep -o 'mtu [0-9]*' | awk '{print $2}')"
    echo "rx-checksumming: $(ethtool -k $iface 2>/dev/null | grep 'rx-checksumming' | awk '{print $2}')"
    echo "tx-checksumming: $(ethtool -k $iface 2>/dev/null | grep 'tx-checksumming' | awk '{print $2}')"
    echo "tcp-segmentation-offload: $(ethtool -k $iface 2>/dev/null | grep 'tcp-segmentation-offload' | awk '{print $2}')"
    echo "generic-segmentation-offload: $(ethtool -k $iface 2>/dev/null | grep 'generic-segmentation-offload' | awk '{print $2}')"
    echo "generic-receive-offload: $(ethtool -k $iface 2>/dev/null | grep 'generic-receive-offload' | awk '{print $2}')"
    echo "large-receive-offload: $(ethtool -k $iface 2>/dev/null | grep 'large-receive-offload' | awk '{print $2}')"
    echo "adaptive-rx: $(ethtool -C $iface 2>/dev/null | grep 'adaptive-rx' | awk '{print $2}')"
    echo "irq coalesce: $(ethtool -c $iface 2>/dev/null | grep 'rx-frames' | head -1)"
    for irq in $(grep -l "$iface" /proc/interrupts 2>/dev/null | head -3); do
        echo "IRQ $(basename $irq): $(cat /proc/irq/$(basename $irq)/smp_affinity 2>/dev/null || echo 'N/A')"
    done
    echo ""
done

# Start background collection
echo "=== Starting Background Collection (${DURATION}s) ==="

# sar for network stats
sar -n DEV $INTERVAL $DURATION > /tmp/sar_dev_out.txt 2>&1 &
SAR_DEV_PID=$!

sar -n EDEV $INTERVAL $DURATION > /tmp/sar_edeve_out.txt 2>&1 &
SAR_EDEV_PID=$!

# netstat
netstat -s > /tmp/netstat_s_out.txt 2>&1 &

# ss summary
ss -s > /tmp/ss_s_out.txt 2>&1 &

# sockstat
cat /proc/net/sockstat > /tmp/sockstat_out.txt 2>&1 &

# Wait for collection
wait $SAR_DEV_PID $SAR_EDEV_PID 2>/dev/null

echo "Collection complete."
echo ""

# Display collected data
echo "=== Collected Data Summary ==="
echo ""

echo "--- Network Device Stats (sar -n DEV) ---"
grep -E "IFACE|Average|^$" /tmp/sar_dev_out.txt | head -30
echo ""

echo "--- Network Error Stats (sar -n EDEV) ---"
grep -E "IFACE|Average|^$" /tmp/sar_edeve_out.txt | head -20
echo ""

echo "--- TCP Statistics ---"
grep -E "Tcp:|TcpExt:" /tmp/netstat_s_out.txt | head -30
echo ""

echo "--- Socket Summary ---"
cat /tmp/ss_s_out.txt
echo ""

echo "--- Socket Memory ---"
cat /tmp/sockstat_out.txt
echo ""

echo "--- TCP Connection States ---"
ss -tan 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -10
echo ""

echo "--- TCP Retransmits ---"
grep -i retrans /tmp/netstat_s_out.txt | head -10
echo ""

# Latency test
echo "--- Latency Test (to gateway) ---"
if [ -n "$GATEWAY" ]; then
    ping -c 5 $GATEWAY 2>/dev/null | tail -2
else
    echo "No gateway found"
fi
echo ""

echo "--- Loopback Latency Test ---"
ping -c 5 127.0.0.1 2>/dev/null | tail -2
echo ""

echo "Data saved to /tmp/"
ls -la /tmp/sar_*_out.txt /tmp/netstat_s_out.txt /tmp/ss_s_out.txt /tmp/sockstat_out.txt 2>/dev/null
