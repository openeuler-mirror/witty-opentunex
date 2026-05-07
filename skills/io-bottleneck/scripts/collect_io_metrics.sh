#!/bin/bash
# collect_io_metrics.sh - Collect I/O metrics for bottleneck analysis
# Usage: collect_io_metrics.sh [duration in seconds]

DURATION=${1:-15}
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

# I/O scheduler and queue settings
echo "=== I/O Scheduler Configuration ==="
for dev in $(lsblk -d -n -o NAME | grep -E '^vd|^sd|^nvme' | head -5); do
    echo "--- /dev/$dev ---"
    echo "scheduler: $(cat /sys/block/$dev/queue/scheduler 2>/dev/null | grep -o '\[.*\]' || echo 'N/A')"
    echo "nr_requests: $(cat /sys/block/$dev/queue/nr_requests 2>/dev/null || echo 'N/A')"
    echo "read_ahead_kb: $(cat /sys/block/$dev/queue/read_ahead_kb 2>/dev/null || echo 'N/A')"
    echo "max_sectors_kb: $(cat /sys/block/$dev/queue/max_sectors_kb 2>/dev/null || echo 'N/A')"
    echo "timeout: $(cat /sys/block/$dev/queue/timeout 2>/dev/null || echo 'N/A')"
    echo "rotational: $(cat /sys/block/$dev/queue/rotational 2>/dev/null || echo 'N/A')"
    echo "add_random: $(cat /sys/block/$dev/queue/add_random 2>/dev/null || echo 'N/A')"
    echo "rq_affinity: $(cat /sys/block/$dev/queue/rq_affinity 2>/dev/null || echo 'N/A')"
    echo "nomerges: $(cat /sys/block/$dev/queue/nomerges 2>/dev/null || echo 'N/A')"
    echo ""
done

# Memory and page cache settings
echo "=== Memory/Page Cache Settings ==="
echo "vfs_cache_pressure: $(cat /proc/sys/vm/vfs_cache_pressure)"
echo "swappiness: $(cat /proc/sys/vm/swappiness)"
echo "dirty_background_ratio: $(cat /proc/sys/vm/dirty_background_ratio)"
echo "dirty_ratio: $(cat /proc/sys/vm/dirty_ratio)"
echo "dirty_writeback_centisecs: $(cat /proc/sys/vm/dirty_writeback_centisecs)"
echo "dirty_expire_centisecs: $(cat /proc/sys/vm/dirty_expire_centisecs)"
echo "min_free_kbytes: $(cat /proc/sys/vm/min_free_kbytes)"
echo "page-cluster: $(cat /proc/sys/vm/page-cluster)"
echo ""

# Filesystem mount options
echo "=== Filesystem Mount Options ==="
mount | grep -E '^/dev|/ext4|/xfs|/btrfs' | head -10
echo ""

# NFS mounts if applicable
echo "=== NFS Mount Options ==="
mount | grep -E 'nfs|cifs' | head -10
echo ""

# Disk IRQ affinity
echo "=== Disk IRQ Affinity (first 5 disks) ==="
for dev in $(lsblk -d -n -o NAME | grep -E '^vd|^sd|^nvme' | head -5); do
    irq=$(grep -l "$dev" /proc/interrupts 2>/dev/null | head -1)
    if [ -n "$irq" ]; then
        echo "/dev/$dev IRQ: $(cat /proc/irq/$(basename $irq)/smp_affinity 2>/dev/null || echo 'N/A')"
    fi
done
echo ""

# LVM if applicable
if command -v lvs &> /dev/null; then
    echo "=== LVM Logical Volumes ==="
    lvs 2>/dev/null
    echo ""
    echo "=== LVM Volume Groups ==="
    vgs 2>/dev/null
    echo ""
fi

# MD RAID if applicable
if [ -f /proc/mdstat ]; then
    echo "=== MD RAID Status ==="
    cat /proc/mdstat 2>/dev/null
    echo ""
fi

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

echo "--- I/O Pattern Analysis (Sequential vs Random) ---"
echo "High rrqm/s+wrqm/s + large avgrq-sz = Sequential"
echo "Low/No merge + small avgrq-sz = Random"
if [ -f /tmp/iostat_output.txt ]; then
    awk '/^Device/ {next} /^sd/ || /^vd/ || /^nvme/ {
        if ($4 > 0 || $5 > 0) {
            ratio = ($4+$5)/($4+$5+$6+$7+0.1)*100
            printf "  %s: merge_rate=%.1f%%, avg_req=%d sectors, pattern=", $1, ratio, $8
            if (ratio > 30 && $8 > 32) print "SEQUENTIAL"
            else if (ratio < 10 && $8 < 16) print "RANDOM"
            else print "MIXED"
        }
    }' /tmp/iostat_output.txt | head -10
fi
echo ""

echo "--- Top I/O Processes ---"
if [ -f /tmp/pidstat_d_output.txt ]; then
    awk 'NR<=3 {next} {print}' /tmp/pidstat_d_output.txt | sort -k7 -rn | head -10
fi
echo ""

echo "Data saved to /tmp/"
ls -la /tmp/vmstat_output.txt /tmp/iostat_output.txt /tmp/pidstat_d_output.txt /tmp/mpstat_output.txt 2>/dev/null
