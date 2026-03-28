#!/bin/bash
# collect_io_metrics.sh - Collect I/O metrics for bottleneck analysis
# Usage: collect_io_metrics.sh [duration in seconds]

DURATION=${1:-30}
INTERVAL=1

echo "=== I/O Metrics Collection ==="
echo "Duration: $DURATION seconds"
echo "Interval: $INTERVAL second"
echo ""

# System overview
echo "=== System Overview ==="
uname -r
echo "CPU Count: $(nproc)"
echo "Memory Total: $(free -h | awk '/^Mem:/{print $2}')"
echo ""

# Disk devices
echo "=== Disk Devices ==="
lsblk -d -n -o NAME,SIZE,TYPE | grep -E 'disk|nvme'
echo ""

# Initial vmstat
echo "=== Initial VMStat (1 sample) ==="
vmstat 1 1
echo ""

# iostat baseline
echo "=== IOStat Extended Stats (1 sample) ==="
if command -v iostat &> /dev/null; then
    iostat -x 1 1
else
    echo "iostat not available - installing sysstat..."
    yum install -y sysstat 2>/dev/null || echo "Could not install sysstat"
fi
echo ""

# Start background collection
echo "=== Starting Background Collection (${DURATION}s) ==="

# vmstat collection
vmstat $INTERVAL $DURATION > /tmp/vmstat_output.txt &
VMSTAT_PID=$!

# iostat collection
iostat -x $INTERVAL $DURATION > /tmp/iostat_output.txt 2>&1 &
IOSTAT_PID=$!

# pidstat collection if available
if command -v pidstat &> /dev/null; then
    pidstat -d $INTERVAL $DURATION > /tmp/pidstat_d_output.txt 2>&1 &
    PIDSTAT_PID=$!
fi

# mpstat collection
if command -v mpstat &> /dev/null; then
    mpstat -P ALL $INTERVAL $DURATION > /tmp/mpstat_output.txt 2>&1 &
    MPSTAT_PID=$!
fi

# Wait for collection to complete
wait $VMSTAT_PID $IOSTAT_PID
[ -n "$PIDSTAT_PID" ] && wait $PIDSTAT_PID
[ -n "$MPSTAT_PID" ] && wait $MPSTAT_PID

echo "Collection complete."
echo ""

# Display collected data
echo "=== Collected Data Summary ==="
echo ""
echo "--- VMStat Summary ---"
awk 'NR<=2 || /^[0-9]/' /tmp/vmstat_output.txt | head -15
echo ""

echo "--- I/O Wait Analysis ---"
if [ -f /tmp/mpstat_output.txt ]; then
    awk '$3 ~ /^[0-9]+$/ && $6 > 10 {print "CPU " $3 ": iowait " $6 "%"}' /tmp/mpstat_output.txt | sort -u
fi
echo ""

echo "--- Disk Utilization Summary ---"
if [ -f /tmp/iostat_output.txt ]; then
    awk '/^Device/ {next} /^sd/ || /^vd/ || /^nvme/ {if ($NF != "0.00") print}' /tmp/iostat_output.txt | head -20
fi
echo ""

echo "--- Top I/O Processes ---"
if [ -f /tmp/pidstat_d_output.txt ]; then
    awk 'NR<=3 {next} {print}' /tmp/pidstat_d_output.txt | sort -k7 -rn | head -10
fi
echo ""

echo "Data saved to /tmp/"
ls -la /tmp/vmstat_output.txt /tmp/iostat_output.txt /tmp/pidstat_d_output.txt /tmp/mpstat_output.txt 2>/dev/null
