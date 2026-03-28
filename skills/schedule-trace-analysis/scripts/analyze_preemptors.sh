#!/bin/bash
# Preemptor impact analysis script
# Usage: analyze_preemptors.sh <TARGET_PID> [DURATION]

TARGET_PID=${1:-}
DURATION=${2:-60}

if [ -z "$TARGET_PID" ]; then
  echo "Usage: $0 <TARGET_PID> [DURATION]"
  echo "Example: $0 1234 60"
  exit 1
fi

echo "=== Preemptor Impact Analysis for PID $TARGET_PID ==="
echo "Collection Duration: ${DURATION}s"
echo ""

# Get target process average runtime
TARGET_RUNTIME=$(perf sched timehist | grep " $TARGET_PID " | awk '{sum+=$6; count++} END {if(count>0) print sum/count; else print 0}')

echo "Target Process Average Runtime: ${TARGET_RUNTIME} ms"
echo ""

# Get top preemptors
echo "=== Top Preemptors by Frequency ==="
perf sched script | grep "sched_switch.*next_pid=$TARGET_PID" | \
  awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | \
  sort | uniq -c | sort -rn | head -20
echo ""

# Calculate impact
echo "=== Preemptor Impact Analysis ==="
echo "Preemptor analysis (stolen time estimation):"
perf sched script | grep "sched_switch.*next_pid=$TARGET_PID" | \
  awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | \
  sort | uniq -c | sort -rn | while read count pid; do
    # Get avg runtime for this PID
    avg_runtime=$(perf sched latency | awk -v pid=$pid '$0 ~ " "pid"[: ]" {print $5; exit}' | sed 's/ms//')
    
    if [ -n "$avg_runtime" ] && [ "$avg_runtime" != "" ]; then
      stolen_time=$(echo "scale=2; $count * $avg_runtime / 1000" | bc 2>/dev/null)
      echo "PID $pid: $count preemptions, avg ${avg_runtime}ms, stolen ~${stolen_time}s"
    fi
done
