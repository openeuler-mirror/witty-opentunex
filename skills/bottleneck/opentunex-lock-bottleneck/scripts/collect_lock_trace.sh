#!/bin/bash
# collect_lock_trace.sh - Collect lock trace data for bottleneck analysis
#
# Usage:
#   bash collect_lock_trace.sh [--pid <PID>] [--duration <SECONDS>]
#
# Parameters:
#   --pid      — Target process PID (optional)
#   --duration — Collection duration in seconds (default: 15)
#
# Examples:
#   # System-wide collection for 20 seconds:
#   bash collect_lock_trace.sh --duration 20
#
#   # Target process collection:
#   bash collect_lock_trace.sh --pid 12345 --duration 20
#
# Save output to file:
#   bash collect_lock_trace.sh --pid 12345 --duration 20 > lock_result.txt 2>&1

DURATION=15
TARGET_PID=""

parse_param() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pid)
                if [ -z "$2" ] || [[ "$2" == --* ]]; then
                    echo "Error: --pid requires a value" >&2
                    echo "Usage: bash $0 [--pid <PID>] [--duration <SECONDS>]" >&2
                    exit 1
                fi
                TARGET_PID="$2"
                shift 2
                ;;
            --duration)
                if [ -z "$2" ] || [[ "$2" == --* ]]; then
                    echo "Error: --duration requires a value" >&2
                    echo "Usage: bash $0 [--pid <PID>] [--duration <SECONDS>]" >&2
                    exit 1
                fi
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

    if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -le 0 ]; then
        echo "Error: --duration must be a positive integer, got: $DURATION" >&2
        exit 1
    fi
}

collect_lock_trace() {
    echo "=== Lock Trace Collection ==="
    echo "Duration: $DURATION seconds"
    if [ -n "$TARGET_PID" ]; then
        echo "Target PID: $TARGET_PID"
    fi
    echo ""

    echo "=== Lock Tracing Prerequisites ==="
    echo "perf_event_paranoid: $(cat /proc/sys/kernel/perf_event_paranoid)"
    echo "lock_stat: $(cat /proc/sys/kernel/lock_stat 2>/dev/null || echo 'N/A')"
    echo "sched_schedstats: $(cat /proc/sys/kernel/sched_schedstats 2>/dev/null || echo 'N/A')"
    echo ""

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

    echo "=== RCU Configuration ==="
    echo "rcu_cpu_stall_suppress: $(cat /proc/sys/kernel/rcu_cpu_stall_suppress 2>/dev/null || echo 'N/A')"
    echo "rcu_normal: $(cat /proc/sys/kernel/rcu_normal 2>/dev/null || echo 'N/A')"
    echo ""

    echo "=== Lockup Detection ==="
    echo "softlockup_panic: $(cat /proc/sys/kernel/softlockup_panic 2>/dev/null || echo 'N/A')"
    echo "nmi_watchdog: $(cat /proc/sys/kernel/nmi_watchdog 2>/dev/null || echo 'N/A')"
    echo ""

    echo "=== CPU Isolation ==="
    echo "isolcpus: $(cat /proc/cmdline 2>/dev/null | grep -o 'isolcpus=[^ ]*' || echo 'N/A')"
    echo "nohz_full: $(cat /proc/cmdline 2>/dev/null | grep -o 'nohz_full=[^ ]*' || echo 'N/A')"
    echo ""

    echo "=== Kernel Lock Statistics ==="
    LOCK_STAT=$(cat /proc/lock_stat 2>/dev/null)
    if [ -n "$LOCK_STAT" ]; then
        echo "$LOCK_STAT" | head -50
    else
        echo "lock_stat: not available (enable via: echo 1 > /proc/sys/kernel/lock_stat)"
    fi
    echo ""

    echo "=== File Locks ==="
    cat /proc/locks 2>/dev/null | head -50 || echo "locks: not available"
    echo ""

    echo "=== Softirq Activity ==="
    cat /proc/softirqs 2>/dev/null | head -50
    echo ""

    if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
        echo "=== Target Process Info (PID: $TARGET_PID) ==="
        ps -T -p "$TARGET_PID" 2>/dev/null || echo "Process not found"
        cat "/proc/$TARGET_PID/status" 2>/dev/null | grep -E "State|Threads|VmRSS" || echo "Cannot read process"
        echo "wchan: $(cat "/proc/$TARGET_PID/wchan" 2>/dev/null || echo 'N/A')"
        cat "/proc/$TARGET_PID/stack" 2>/dev/null | head -20 || echo "Cannot read stack"
        echo ""
    fi

    echo "=== Blocked Processes (D=uninterruptible, S=interruptible) ==="
    ps -eo state,wchan:32,pid,comm | awk '/^[DS]/ {print}' | sort | uniq -c | sort -rn | head -20
    echo ""

    echo "=== Wait Channel Breakdown ==="
    ps -eo state,wchan:32 | awk '/^[DS]/ {print $2}' | sort | uniq -c | sort -rn | head -20
    echo ""

    echo "=== Collection Complete ==="
}

parse_param "$@"
collect_lock_trace
