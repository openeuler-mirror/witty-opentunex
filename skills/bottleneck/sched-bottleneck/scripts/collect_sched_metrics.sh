#!/bin/bash
# collect_sched_trace_metrics.sh - Collect and analyze scheduling trace metrics
# Usage: collect_sched_trace_metrics.sh [PID] [DURATION]
#   PID: Target process PID (optional, system-wide if not specified)
#   DURATION: Collection duration in seconds (default: 5)

DURATION=${2:-5}
TARGET_PID=${1:-}

PERF_EVENTS="sched:sched_switch,sched:sched_wakeup,sched:sched_wakeup_new,sched:sched_migrate_task"

echo "=== Prerequisites ==="
echo "perf_event_paranoid: $(cat /proc/sys/kernel/perf_event_paranoid)"
echo "sched_schedstats: $(cat /proc/sys/kernel/sched_schedstats 2>/dev/null || echo 'N/A')"
echo ""

echo "=== Scheduler Configuration ==="
echo "sched_latency_ns: $(cat /proc/sys/kernel/sched_latency_ns 2>/dev/null || echo 'N/A')"
echo "sched_min_granularity_ns: $(cat /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null || echo 'N/A')"
echo "sched_wakeup_granularity_ns: $(cat /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null || echo 'N/A')"
echo "sched_tunable_scaling: $(cat /proc/sys/kernel/sched_tunable_scaling 2>/dev/null || echo 'N/A')"
echo "sched_autogroup_enabled: $(cat /proc/sys/kernel/sched_autogroup_enabled 2>/dev/null || echo 'N/A')"
echo "sched_child_runs_first: $(cat /proc/sys/kernel/sched_child_runs_first 2>/dev/null || echo 'N/A')"
echo "sched_rt_period_us: $(cat /proc/sys/kernel/sched_rt_period_us 2>/dev/null || echo 'N/A')"
echo "sched_rt_runtime_us: $(cat /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null || echo 'N/A')"
echo "isolcpus: $(cat /proc/cmdline 2>/dev/null | grep -o 'isolcpus=[^ ]*' || echo 'N/A')"
echo "nohz_full: $(cat /proc/cmdline 2>/dev/null | grep -o 'nohz_full=[^ ]*' || echo 'N/A')"
echo ""
echo "=== Run Queue Status ==="
vmstat 1 2 | tail -1 | awk '{print "running:", $1, "blocked:", $2}'
echo ""

if [ -n "$TARGET_PID" ]; then
    echo "=== Target Process Info ==="
    ps -p $TARGET_PID -o pid,comm,state,pri,ni,threads --no-headers 2>/dev/null || echo "Process not found"
    taskset -pc $TARGET_PID 2>/dev/null || true
    echo "Scheduler Policy: $(chrt -p $TARGET_PID 2>/dev/null | grep policy | awk '{print $NF}')"
    echo "RT Priority: $(chrt -p $TARGET_PID 2>/dev/null | grep priority | awk '{print $NF}')"
    echo ""
fi

echo "=== Recording perf sched data (timeout ${DURATION}s) ==="
timeout $DURATION perf sched record -a -e $PERF_EVENTS --per-socket 2>/dev/null

if [ ! -f "perf.data" ]; then
    echo "Error: perf.data not created"
    exit 1
fi

echo "perf.data created: $(du -h perf.data | cut -f1)"
echo ""

echo "=== Scheduling Latency (sorted by max/avg delay) ==="
perf sched latency --sort max,avg 2>/dev/null | head -30
echo ""

echo "=== Scheduling Latency (sorted by runtime) ==="
perf sched latency 2>/dev/null | head -30
echo ""

echo "=== Time History ==="
perf sched timehist 2>/dev/null | head -50
echo ""

if [ -n "$TARGET_PID" ]; then
    echo "=== Target Process Schedule Out ==="
    SWITCH_COUNT=$(perf sched script 2>/dev/null | grep "sched_switch.*prev_pid=$TARGET_PID" | wc -l)
    echo "Schedule Out Events: $SWITCH_COUNT"
    echo "Frequency: $(echo "scale=2; $SWITCH_COUNT / $DURATION" | bc 2>/dev/null || echo "N/A") events/s"
    echo ""

    echo "=== Preemptors (processes that ran before target) ==="
    perf sched script 2>/dev/null | grep "sched_switch.*next_pid=$TARGET_PID" | \
        awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | \
        sort | uniq -c | sort -rn | head -10
    echo ""

    echo "=== Successors (processes that ran after target) ==="
    perf sched script 2>/dev/null | grep "sched_switch.*prev_pid=$TARGET_PID" | \
        awk -F'next_pid=' '{print $2}' | awk '{print $1}' | \
        sort | uniq -c | sort -rn | head -10
    echo ""

    echo "=== Wakeup Latency for Target ==="
    perf sched timehist --tid $TARGET_PID 2>/dev/null | awk 'NR>3 && NF>=6 {wait+=$4; delay+=$5; if($4>max_w) max_w=$4; if($5>max_d) max_d=$5; n++} END {if(n>0) printf "Avg wait: %.3f ms, sch_delay: %.3f ms, Max wait: %.3f ms, Max delay: %.3f ms (samples: %d)\n", wait/n, delay/n, max_w, max_d, n}'
    echo ""

    echo "=== Time History for Target ==="
    perf sched timehist --tid $TARGET_PID 2>/dev/null | head -50
fi

echo "=== Collection Complete ==="