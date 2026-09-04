#!/bin/bash
TABLES=${1:-10}
ROWS=${2:-100000}
MYSQL_SOCKET="${MYSQL_SOCKET:-/var/lib/mysql/mysql.sock}"
DB_NAME="${DB_NAME:-sbtest}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-123456}"
echo "=== Prepare: $TABLES tables, $ROWS rows ==="
sysbench /usr/share/sysbench/oltp_common.lua --db-driver=mysql --mysql-socket=$MYSQL_SOCKET --mysql-db=$DB_NAME --mysql-user=$DB_USER --mysql-password=$DB_PASS --tables=$TABLES --table-size=$ROWS prepare 2>&1