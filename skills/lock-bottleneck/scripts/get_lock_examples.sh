#!/bin/bash
# Get actual output examples from local system for OS lock bottleneck analysis
# This script demonstrates the actual output of lock analysis commands

echo "=== OS Lock Bottleneck Analysis - Command Output Examples ==="
echo ""
echo "NOTE: These are real outputs from this system. Actual values will vary by environment."
echo ""

# 1. vmstat output
echo "[1/10] vmstat 1 5 - System-wide blocked process count"
echo "---"
vmstat 1 5
echo ""

# 2. pidstat context switch output
echo "[2/10] pidstat -w 1 5 - Per-process context switches"
echo "---"
pidstat -w 1 5 2>/dev/null || echo "pidstat not available"
echo ""

# 3. Process state and wait channel
echo "[3/10] ps -eo pid,comm,state,wchan:32 - Processes with wait channels"
echo "---"
ps -eo pid,comm,state,wchan:32 2>/dev/null | head -30
echo ""

# 4. Current file locks
echo "[4/10] cat /proc/locks - Current file locks"
echo "---"
cat /proc/locks 2>/dev/null | head -20 || echo "not available"
echo ""

# 5. Softirqs
echo "[5/10] cat /proc/softirqs - Soft interrupt statistics"
echo "---"
cat /proc/softirqs 2>/dev/null || echo "not available"
echo ""

# 6. mpstat
echo "[6/10] mpstat 1 5 - Per-CPU utilization"
echo "---"
mpstat 1 5 2>/dev/null || echo "mpstat not available"
echo ""

# 7. Process status with state
echo "[7/10] cat /proc/self/status | grep -E 'State|Threads' - Process state example"
echo "---"
cat /proc/self/status 2>/dev/null | grep -E "State|Threads" || echo "not available"
echo ""

# 8. Example of a process wchan
echo "[8/10] Example: cat /proc/1/wchan - Init process wait channel"
echo "---"
cat /proc/1/wchan 2>/dev/null || echo "not available"
echo ""

# 9. perf schedstat
echo "[9/10] perf schedlatency (from recent perf.data if exists)"
echo "---"
if [ -f "perf.data" ]; then
    perf sched latency 2>/dev/null | head -30 || echo "perf sched latency failed"
else
    echo "No perf.data found - run 'perf sched record -a -- sleep 10' first"
fi
echo ""

# 10. Check schedstat
echo "[10/10] cat /proc/schedstat - Scheduler statistics (first 3 lines)"
echo "---"
cat /proc/schedstat 2>/dev/null | head -3 || echo "not available"
echo ""

echo "=== Example Complete ==="
echo ""
echo "Use these outputs as reference when analyzing lock bottlenecks:"
echo "  - vmstat 'b' column: blocked processes (>0 = lock blocking)"
echo "  - pidstat 'cswch/s': voluntary context switches (includes lock waits)"
echo "  - ps state 'S': interruptible sleep (waiting on lock)"
echo "  - ps state 'D': uninterruptible sleep (usually I/O)")
echo "  - wchan: kernel function process is waiting in"
