#!/bin/bash
# collect_net_metrics.sh - Collect network metrics for bottleneck analysis
# Usage: collect_net_metrics.sh [duration in seconds]

DURATION=${1:-30}
INTERVAL=1

echo "=== Network Metrics Collection ==="
echo "Duration: $DURATION seconds"
echo "Interval: $INTERVAL second"
echo ""

# Check available tools
echo "=== Available Network Tools ==="
for tool in sar netstat ss ip ethtool ping; do
  which $tool 2>/dev/null && echo "$tool: available" || echo "$tool: NOT FOUND"
done
echo ""

# Install sysstat if needed
if ! command -v sar &> /dev/null; then
  echo "Installing sysstat..."
  yum install -y sysstat 2>/dev/null || echo "Could not install sysstat"
fi

# System info
echo "=== System Info ==="
uname -r
echo ""

# Network interfaces
echo "=== Network Interfaces ==="
ip link show
echo ""

# Default gateway
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
echo "Default gateway: $GATEWAY"
echo ""

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

# Latency test
if [ -n "$GATEWAY" ]; then
  echo "--- Latency Test (to gateway) ---"
  ping -c 5 $GATEWAY 2>/dev/null | tail -2
fi

echo ""
echo "Data saved to /tmp/"
ls -la /tmp/sar_*_out.txt /tmp/netstat_s_out.txt /tmp/ss_s_out.txt /tmp/sockstat_out.txt 2>/dev/null
