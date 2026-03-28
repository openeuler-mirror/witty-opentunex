#!/bin/bash
# Analyze lock contention from collected perf data
# Usage: analyze_lock_contention.sh [perf_data_path]

set -e

PERF_DATA=${1:-perf.data}
DURATION=${2:-30}

echo "=== Lock Contention Analysis ==="
echo "Perf data: $PERF_DATA"
echo ""

# Check if perf.data exists
if [ ! -f "$PERF_DATA" ]; then
  echo "Error: $PERF_DATA not found"
  echo "Please run perf record first or provide correct path"
  exit 1
fi

# 1. Analyze scheduling latency (wait time = lock blocking indicator)
echo "[1/6] Analyzing scheduling latency (wait time = lock blocking indicator)..."
perf sched timehist 2>/dev/null | head -50
echo ""

# Calculate total wait time for top processes
echo "--- Top processes by wait time ---"
perf sched timehist 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | head -10 | while read count name; do
    wait_sum=$(perf sched timehist 2>/dev/null | grep " $name " | awk '{sum+=$8} END {print sum}')
    echo "  $name: wait=${wait_sum}ms count=$count"
done
echo ""

# 2. Analyze futex activity
echo "[2/6] Analyzing futex activity..."
perf script -i "$PERF_DATA" 2>/dev/null | grep -E "futex" | head -100
echo ""

# Futex wait address contention
echo "--- Futex wait address contention (hot locks) ---"
perf script -i "$PERF_DATA" 2>/dev/null | grep "enter_futex.*FUTEX_WAIT" | awk '{print $6}' | sort | uniq -c | sort -rn | head -10
echo ""

# 3. Analyze context switches
echo "[3/6] Analyzing context switches..."
echo "--- Top processes by voluntary context switches ---"
perf sched script -i "$PERF_DATA" 2>/dev/null | grep "prev_state=S" | awk '{print $4}' | sort | uniq -c | sort -rn | head -10
echo ""

# 4. Analyze blocked processes
echo "[4/6] Analyzing blocked processes..."
if [ -f "process_state.log" ]; then
    echo "--- Processes in blocked state (D=uninterruptible, S=interruptible) ---"
    awk '/^[0-9]+.*[DS]/' process_state.log | head -20
    echo ""
    
    echo "--- Wait channel breakdown ---"
    awk '/^[0-9]+.*[DS]/ {print $4}' process_state.log | sort | uniq -c | sort -rn | head -10
    echo ""
fi

# 5. Analyze system metrics
echo "[5/6] Analyzing system metrics..."
if [ -f "vmstat.log" ]; then
    echo "--- Blocked processes (b column) ---"
    awk 'NR>2 {print "blocked:", $16}' vmstat.log | sort -rn | head -10
    echo ""
fi

if [ -f "softirqs.log" ]; then
    echo "--- Softirq breakdown ---"
    cat softirqs.log
    echo ""
fi

# 6. Generate summary
echo "[6/6] Generating summary..."
echo ""
echo "=== Lock Bottleneck Summary ==="
echo ""
echo "Key indicators to look for:"
echo "  1. High wait time in perf sched timehist = lock blocking"
echo "  2. Multiple processes waiting on same futex address = contention"
echo "  3. High voluntary context switches (prev_state=S) = lock-induced blocking"
echo "  4. Blocked processes in vmstat (b > 0) = system-wide lock contention"
echo "  5. Futex wait/wake ratio > 2:1 = userspace lock contention"
echo ""
echo "Interpretation:"
echo "  - Wait time > 20% of runtime = significant lock overhead"
echo "  - Futex addr with >10 waits = contested lock"
echo "  - vmstat b column > CPU count = severe lock contention"
echo ""
