#!/bin/bash
# collect_sched_metrics.sh - Collect and analyze scheduling trace metrics
#
# Usage:
#   bash collect_sched_metrics.sh [--pid <PID>] [--duration <SECONDS>]
#
# Parameters:
#   --pid      — Target process PID (optional, system-wide if not specified)
#   --duration — Collection duration in seconds (default: 5)
#
# Examples:
#   # System-wide collection for 10 seconds:
#   bash collect_sched_metrics.sh --duration 10
#
#   # Target process collection:
#   bash collect_sched_metrics.sh --pid 12345 --duration 10
#
# Save output to file:
#   bash collect_sched_metrics.sh --pid 12345 --duration 10 > sched_result.txt 2>&1

DURATION=5
TARGET_PID=""

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

collect_sched_metrics() {
    PERF_EVENTS="sched:sched_switch,sched:sched_wakeup,sched:sched_wakeup_new,sched:sched_migrate_task"

    echo "=== Prerequisites ==="
    echo "perf_event_paranoid: $(cat /proc/sys/kernel/perf_event_paranoid)"
    echo "sched_schedstats: $(cat /proc/sys/kernel/sched_schedstats 2>/dev/null || echo 'N/A')"
    echo ""

    echo "=== Scheduler Configuration ==="

    sched_latency="N/A"
    if [ -f /proc/sys/kernel/sched_latency_ns ]; then
        sched_latency=$(cat /proc/sys/kernel/sched_latency_ns)
    elif [ -f /sys/kernel/debug/sched/base_slice_ns ]; then
        sched_latency=$(cat /sys/kernel/debug/sched/base_slice_ns)
    fi
    echo "sched_latency_ns (base_slice_ns): $sched_latency"

    if [ -f /proc/sys/kernel/sched_min_granularity_ns ]; then
        echo "sched_min_granularity_ns: $(cat /proc/sys/kernel/sched_min_granularity_ns)"
    else
        echo "sched_min_granularity_ns: N/A (implicit on 6.x, ~0.75 * base_slice_ns)"
    fi

    if [ -f /proc/sys/kernel/sched_wakeup_granularity_ns ]; then
        echo "sched_wakeup_granularity_ns: $(cat /proc/sys/kernel/sched_wakeup_granularity_ns)"
    else
        echo "sched_wakeup_granularity_ns: N/A (implicit on 6.x, ~1.0 * base_slice_ns)"
    fi

    if [ -f /proc/sys/kernel/sched_tunable_scaling ]; then
        echo "sched_tunable_scaling: $(cat /proc/sys/kernel/sched_tunable_scaling)"
    elif [ -f /sys/kernel/debug/sched/tunable_scaling ]; then
        echo "sched_tunable_scaling: $(cat /sys/kernel/debug/sched/tunable_scaling)"
    else
        echo "sched_tunable_scaling: N/A"
    fi

    if [ -f /proc/sys/kernel/sched_migration_cost_ns ]; then
        echo "sched_migration_cost_ns: $(cat /proc/sys/kernel/sched_migration_cost_ns)"
    elif [ -f /sys/kernel/debug/sched/migration_cost_ns ]; then
        echo "sched_migration_cost_ns: $(cat /sys/kernel/debug/sched/migration_cost_ns)"
    fi

    echo "sched_autogroup_enabled: $(cat /proc/sys/kernel/sched_autogroup_enabled 2>/dev/null || echo 'N/A')"
    echo "sched_child_runs_first: $(cat /proc/sys/kernel/sched_child_runs_first 2>/dev/null || echo 'N/A')"
    echo "sched_rt_period_us: $(cat /proc/sys/kernel/sched_rt_period_us 2>/dev/null || echo 'N/A')"
    echo "sched_rt_runtime_us: $(cat /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null || echo 'N/A')"
    echo "isolcpus: $(cat /proc/cmdline | grep -o 'isolcpus=[^ ]*' || echo 'N/A')"
    echo "nohz_full: $(cat /proc/cmdline | grep -o 'nohz_full=[^ ]*' || echo 'N/A')"
    echo ""
    echo "=== Run Queue Status ==="
    vmstat 1 2 | tail -1 | awk '{print "running:", $1, "blocked:", $2}'
    echo ""

    if [ -n "$TARGET_PID" ]; then
        echo "=== Target Process Info ==="
        ps -p $TARGET_PID -o pid,comm,state,pri,ni,nlwp --no-headers || echo "Process not found"
        taskset -pc $TARGET_PID || true
        echo "Scheduler Policy: $(chrt -p $TARGET_PID | grep policy | awk '{print $NF}')"
        echo "RT Priority: $(chrt -p $TARGET_PID | grep priority | awk '{print $NF}')"
        echo ""
    fi

    echo "=== Recording perf sched data (timeout ${DURATION}s) ==="
    timeout $DURATION perf sched record -a -e $PERF_EVENTS

    if [ ! -f "perf.data" ]; then
        echo "Error: perf.data not created"
        exit 1
    fi

    echo "perf.data created: $(du -h perf.data | cut -f1)"
    echo ""

    echo "=== Scheduling Latency (sorted by max/avg delay) ==="
    perf sched latency --sort max,avg | head -30
    echo ""

    echo "=== Scheduling Latency (sorted by runtime) ==="
    perf sched latency | head -30
    echo ""

    echo "=== Time History ==="
    perf sched timehist | head -50
    echo ""

    if [ -n "$TARGET_PID" ]; then
        echo "=== Target Process Schedule Out ==="
        SCHED_SCRIPT=/tmp/perf.sched.script
        perf sched script > $SCHED_SCRIPT 2>&1
        SWITCH_COUNT=$(cat "$SCHED_SCRIPT" | grep "sched_switch: .*:${TARGET_PID} \[.*\] . ==> " | wc -l)
        echo "Schedule Out Events: $SWITCH_COUNT"
        echo "Frequency: $(echo "scale=2; $SWITCH_COUNT / $DURATION" | bc || echo "N/A") events/s"
        echo ""

        echo "=== Preemptors (processes that ran before target, top 10 cnts) ==="
        cat "$SCHED_SCRIPT" | grep "==> .*:${TARGET_PID} \[" | \
            sed 's/.*sched_switch: //' | sed 's/ ==> .*//' | awk '{print $1}' | \
            sort | uniq -c | sort -rn | head -10
        echo ""

        echo "=== Successors (processes that ran after target, top 10 cnts) ==="
        cat "$SCHED_SCRIPT" | grep "sched_switch: .*:${TARGET_PID} \[.*\] . ==> " | \
            sed 's/.*==> //' | awk '{print $1}' | \
            sort | uniq -c | sort -rn | head -10
        echo ""

        echo "=== Time History for Target ==="
        SCHED_TIMEHIST_TARGET=/tmp/perf.sched.timehist.${TARGET_PID}
        perf sched timehist --tid $TARGET_PID > $SCHED_TIMEHIST_TARGET
        cat $SCHED_TIMEHIST_TARGET | head -50

        echo "=== Wakeup Latency for Target ==="
        cat $SCHED_TIMEHIST_TARGET | awk 'NR>3 && NF>=6 {wait+=$4; delay+=$5; if($4>max_w) max_w=$4; if($5>max_d) max_d=$5; n++} END {if(n>0) printf "Avg wait: %.3f ms, sch_delay: %.3f ms, Max wait: %.3f ms, Max delay: %.3f ms (samples: %d)\n", wait/n, delay/n, max_w, max_d, n}'
        echo ""
    fi
    rm -f perf.data 2>/dev/null

    echo "=== Collection Complete ==="
}

parse_param "$@"
collect_sched_metrics
