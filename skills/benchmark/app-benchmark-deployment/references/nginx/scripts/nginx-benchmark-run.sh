#!/bin/bash
CLIENTS=${1:-100}
DURATION=${2:-120}
INTERVAL=${3:-10}
mkdir -p /opt/opentunex/applications/nginx/logs

RESULT_DIR="/opt/opentunex/applications/nginx/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if ! pgrep nginx > /dev/null; then 
  nginx
  sleep 3
fi

if ! command -v ab &>/dev/null; then
  echo "ab not available"
  exit 1
fi

echo "=== Nginx Benchmark (Sustained ${DURATION}s) ==="
echo "Clients: $CLIENTS, Duration: ${DURATION}s, Interval: ${INTERVAL}s"
echo ""

START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))
ITER=1

while [ $(date +%s) -lt $END_TIME ]; do
  CURRENT=$(( $(date +%s) - START_TIME ))
  echo "--- [${CURRENT}s] Iteration $ITER ---"
  ab -n 5000 -c $CLIENTS http://localhost:80/ 2>&1 | grep -E "(Requests per second|Time per request|Transfer rate)" | \
    sed "s/^/  /"
  ITER=$((ITER + 1))
done 2>&1 | tee ${RESULT_DIR}/nginx_benchmark_${TIMESTAMP}.log

echo "=== Summary ($ITER iterations) ==="
grep "Requests per second" ${RESULT_DIR}/nginx_benchmark_${TIMESTAMP}.log