#!/bin/bash
# Script to collect perf sched command output examples

echo "=== 1. perf sched latency (default) ==="
perf sched latency | head -15
echo ""

echo "=== 2. perf sched latency --sort max,avg,pid ==="
perf sched latency --sort max,avg,pid | head -15
echo ""

echo "=== 3. perf sched timehist (header + 6 lines) ==="
perf sched timehist | head -8
echo ""

echo "=== 4. perf sched map (header + 15 lines) ==="
perf sched map | head -15
echo ""

echo "=== 5. perf sched script (header + 6 lines) ==="
perf sched script | head -6
echo ""

echo "=== 6. perf sched script | grep sched_switch (6 lines) ==="
perf sched script | grep "sched_switch" | head -6
echo ""

echo "=== 7. perf sched script | grep sched_wakeup (6 lines) ==="
perf sched script | grep "sched_wakeup" | head -6
echo ""
