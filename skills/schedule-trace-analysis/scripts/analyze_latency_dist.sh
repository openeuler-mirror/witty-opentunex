#!/bin/bash
# Latency distribution analysis script
# Usage: analyze_latency_dist.sh <TARGET_PID>

TARGET_PID=${1:-}

if [ -z "$TARGET_PID" ]; then
  echo "Usage: $0 <TARGET_PID>"
  echo "Example: $0 1234"
  exit 1
fi

echo "=== Latency Distribution Analysis for PID $TARGET_PID ==="
echo ""

# Get latency percentiles
echo "=== Latency Percentiles (P50, P90, P95, P99) ==="
perf sched timehist | grep " $TARGET_PID " | awk '{print $8}' | sort -n | awk '
BEGIN { count=0 }
{ vals[count++]=$1 }
END {
  if (count > 0) {
    print "P50:", vals[int(count*0.5)]
    print "P90:", vals[int(count*0.9)]
    print "P95:", vals[int(count*0.95)]
    print "P99:", vals[int(count*0.99)]
    print "Total samples:", count
  } else {
    print "No data found"
  }
}'
echo ""

# Analyze latency histogram
echo "=== Latency Histogram (Distribution) ==="
echo "Bucket (ms)     Count"
echo "--------------  ------"
perf sched timehist | grep " $TARGET_PID " | awk '{latency=$8; bucket=int(latency); freq[bucket]++} END {for (b in freq) printf "%4d-%4d ms:    %d\n", b, b+1, freq[b]}' | sort -n -t: -k1 | head -20
echo ""

# Identify high latency events
echo "=== High Latency Events (>10ms) ==="
perf sched timehist | grep " $TARGET_PID " | awk '$8 > 10 {print $0}'
