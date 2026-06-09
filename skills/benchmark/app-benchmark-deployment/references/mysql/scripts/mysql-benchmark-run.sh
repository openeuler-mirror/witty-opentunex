#!/bin/bash
THREADS=${1:-8}
TIME=${2:-120}
TEST_TYPE=${3:-read_write}
MYSQL_SOCKET="${MYSQL_SOCKET:-/var/lib/mysql/mysql.sock}"
DB_NAME="${DB_NAME:-sbtest}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-123456}"
RESULT_DIR="/opt/opentunex/applications/mysql/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p $RESULT_DIR

SCRIPT="/usr/share/sysbench/oltp_read_write.lua"
[ "$TEST_TYPE" = "read_only" ] && SCRIPT="/usr/share/sysbench/oltp_read_only.lua"
[ "$TEST_TYPE" = "write_only" ] && SCRIPT="/usr/share/sysbench/oltp_write_only.lua"

echo "=== MySQL sysbench (Sustained ${TIME}s) ==="
echo "Threads: $THREADS, Duration: ${TIME}s, Type: $TEST_TYPE"
echo ""

sysbench $SCRIPT \
  --db-driver=mysql \
  --mysql-socket=$MYSQL_SOCKET \
  --mysql-db=$DB_NAME \
  --mysql-user=$DB_USER \
  --mysql-password=$DB_PASS \
  --threads=$THREADS \
  --time=$TIME \
  --report-interval=10 \
  --db-ps-mode=disable \
  run 2>&1 | tee ${RESULT_DIR}/sysbench_${TEST_TYPE}_${TIMESTAMP}.log

echo "=== Results ==="
grep -E "^(    avg:|    95th percentile:|    99th percentile:|    transactions:|    queries:)" ${RESULT_DIR}/sysbench_${TEST_TYPE}_${TIMESTAMP}.log