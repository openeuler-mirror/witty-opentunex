#!/bin/bash
CLIENTS=${1:-10}
TIME=${2:-120}
THREADS=${3:-1}
mkdir -p /opt/opentunex/applications/pgsql/logs

RESULT_DIR="/opt/opentunex/applications/pgsql/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== PostgreSQL pgbench (Sustained ${TIME}s) ==="
echo "Clients: $CLIENTS, Duration: ${TIME}s, Threads: $THREADS"
echo ""

su - postgres -c "pgbench -c $CLIENTS -T $TIME -j $THREADS -r -P 5" pgbench 2>&1 | tee ${RESULT_DIR}/pgbench_${TIMESTAMP}.log

echo "=== Results ==="
tail -20 ${RESULT_DIR}/pgbench_${TIMESTAMP}.log