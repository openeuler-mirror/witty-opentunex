#!/bin/bash
# collect_lock_trace.sh - Collect lock trace data for bottleneck analysis
# Usage: collect_lock_trace.sh [duration] [PID]

DURATION=${1:-15}
TARGET_PID=${2:-}

echo "=== Lock Trace Collection ==="
echo "Duration: $DURATION seconds"
if [ -n "$TARGET_PID" ]; then
    echo "Target PID: $TARGET_PID"
fi
echo ""

# Lock tracing prerequisites
echo "=== Lock Tracing Prerequisites ==="
echo "perf_event_paranoid: $(cat /proc/sys/kernel/perf_event_paranoid)"
echo "lock_stat: $(cat /proc/sys/kernel/lock_stat 2>/dev/null || echo 'N/A')"
echo "sched_schedstats: $(cat /proc/sys/kernel/sched_schedstats 2>/dev/null || echo 'N/A')"
echo ""

# System lock configuration
echo "=== System Lock Configuration ==="
echo "futex_wake_mac: $(cat /proc/sys/kernel/futex_wake_mac 2>/dev/null || echo 'N/A')"
echo "futex_ping_latency: $(cat /proc/sys/kernel/futex_ping_latency 2>/dev/null || echo 'N/A')"
echo "sched_autogroup_enabled: $(cat /proc/sys/kernel/sched_autogroup_enabled 2>/dev/null || echo 'N/A')"
echo "sched_child_runs_first: $(cat /proc/sys/kernel/sched_child_runs_first 2>/dev/null || echo 'N/A')"
echo "sched_latency_ns: $(cat /proc/sys/kernel/sched_latency_ns 2>/dev/null || echo 'N/A')"
echo "sched_min_granularity_ns: $(cat /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null || echo 'N/A')"
echo "sched_wakeup_granularity_ns: $(cat /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null || echo 'N/A')"
echo "sched_tunable_scaling: $(cat /proc/sys/kernel/sched_tunable_scaling 2>/dev/null || echo 'N/A')"
echo ""

# RCU configuration
echo "=== RCU Configuration ==="
echo "rcu_cpu_stall_suppress: $(cat /proc/sys/kernel/rcu_cpu_stall_suppress 2>/dev/null || echo 'N/A')"
echo "rcu_normal: $(cat /proc/sys/kernel/rcu_normal 2>/dev/null || echo 'N/A')"
echo ""

# Lockup detection
echo "=== Lockup Detection ==="
echo "softlockup_panic: $(cat /proc/sys/kernel/softlockup_panic 2>/dev/null || echo 'N/A')"
echo "nmi_watchdog: $(cat /proc/sys/kernel/nmi_watchdog 2>/dev/null || echo 'N/A')"
echo ""

# CPU isolation
echo "=== CPU Isolation ==="
echo "isolcpus: $(cat /proc/cmdline 2>/dev/null | grep -o 'isolcpus=[^ ]*' || echo 'N/A')"
echo "nohz_full: $(cat /proc/cmdline 2>/dev/null | grep -o 'nohz_full=[^ ]*' || echo 'N/A')"
echo ""

# Kernel lock statistics
echo "=== Kernel Lock Statistics ==="
cat /proc/lock_stat 2>/dev/null | head -50 || echo "lock_stat: not available (requires root)"
echo ""

# File locks
echo "=== File Locks ==="
cat /proc/locks 2>/dev/null | head -30 || echo "locks: not available"
echo ""

# Softirq activity
echo "=== Softirq Activity ==="
cat /proc/softirqs 2>/dev/null | head -20
echo ""

# Target process info
if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
    echo "=== Target Process Info (PID: $TARGET_PID) ==="
    ps -T -p $TARGET_PID 2>/dev/null || echo "Process not found"
    cat /proc/$TARGET_PID/status 2>/dev/null | grep -E "State|Threads|VmRSS" || echo "Cannot read process"
    echo "wchan: $(cat /proc/$TARGET_PID/wchan 2>/dev/null || echo 'N/A')"
    cat /proc/$TARGET_PID/stack 2>/dev/null | head -20 || echo "Cannot read stack"
    echo ""
fi

# Blocked processes
echo "=== Blocked Processes (D=uninterruptible, S=interruptible) ==="
ps -eo state,wchan:32,pid,comm | awk '/^[DS]/ {print}' | sort | uniq -c | sort -rn | head -20
echo ""

echo "=== Wait Channel Breakdown ==="
ps -eo state,wchan:32 | awk '/^[DS]$/ {print $2}' | sort | uniq -c | sort -rn | head -20
echo ""

echo "=== Collection Complete ==="
