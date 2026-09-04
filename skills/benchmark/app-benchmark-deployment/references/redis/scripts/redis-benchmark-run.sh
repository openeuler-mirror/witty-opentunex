#!/bin/bash
CLIENTS=${1:-50}
DURATION=${2:-120}
KEYS=${3:-10000}
mkdir -p /opt/opentunex/applications/redis/logs

RESULT_DIR="/opt/opentunex/applications/redis/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== Redis Benchmark (Sustained ${DURATION}s) ==="
echo "Clients: $CLIENTS, Duration: ${DURATION}s"
echo ""

START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))

while [ $(date +%s) -lt $END_TIME ]; do
  CURRENT=$(( $(date +%s) - START_TIME ))
  redis-benchmark -c $CLIENTS -n 10000 -t get,set -d 100 -P 16 --notimestamp 2>&1 | \
    sed "s/^/[${CURRENT}s] /"
done 2>&1 | tee ${RESULT_DIR}/redis_benchmark_${TIMESTAMP}.log

echo "=== Results ==="
echo "Duration: ${DURATION}s"
grep -E "^(====|Requests|Latency|RPS)" ${RESULT_DIR}/redis_benchmark_${TIMESTAMP}.log | head -20