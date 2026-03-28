#!/bin/bash
# Scheduling frequency analysis script
# Usage: analyze_sched_freq.sh <TARGET_PID> [DURATION]

TARGET_PID=${1:-}
DURATION=${2:-60}

if [ -z "$TARGET_PID" ]; then
  echo "Usage: $0 <TARGET_PID> [DURATION]"
  echo "Example: $0 1234 60"
  exit 1
fi

echo "=== Scheduling Frequency Analysis for PID $TARGET_PID ==="
echo "Collection Duration: ${DURATION}s"
echo ""

# Count scheduling out events
echo "=== Scheduling Out Analysis ==="
SWITCH_COUNT=$(perf sched script | grep "sched_switch.*prev_pid=$TARGET_PID" | wc -l)
echo "Total Schedule Out Events: $SWITCH_COUNT"

# Calculate frequency
if [ "$DURATION" -gt 0 ]; then
  FREQ=$(echo "scale=2; $SWITCH_COUNT / $DURATION" | bc)
  echo "Schedule Out Frequency: ${FREQ} events/second"
fi

# Analyze scheduling out patterns
echo ""
echo "=== Scheduling Out Pattern (Sample 10 events) ==="
perf sched script | grep "sched_switch.*prev_pid=$TARGET_PID" | head -10 | awk '{print $1, $2}' | sed 's/sched:sched_switch://g'
echo ""

# Compare with system average
echo "=== System Comparison ==="
echo "Top 10 tasks by switch count:"
perf sched script | grep "sched_switch" | awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | while read count pid; do
  if [ "$pid" == "$TARGET_PID" ]; then
    echo ">>> PID $pid: $count switches (TARGET) <<<"
  else
    comm=$(ps -p $pid -o comm= 2>/dev/null || echo "unknown")
    echo "    PID $pid ($comm): $count switches"
  fi
done
