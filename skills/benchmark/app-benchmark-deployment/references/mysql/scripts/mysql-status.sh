#!/bin/bash
MYSQL_SOCKET="${MYSQL_SOCKET:-/var/lib/mysql/mysql.sock}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-123456}"
echo "=== MySQL Status ==="
pgrep mysqld > /dev/null && echo "Status: RUNNING (PID: $(pgrep mysqld))" || echo "Status: STOPPED"
mysqladmin -S $MYSQL_SOCKET ping 2>/dev/null && echo "MySQL: RESPONDING" || echo "MySQL: NOT RESPONDING"
mysql -S $MYSQL_SOCKET -u $MYSQL_USER -p"$MYSQL_PASS" -e "SELECT @@version, ROUND(@@uptime/3600,2) as Uptime_h, @@max_connections as MaxConn" 2>/dev/null
mysql -S $MYSQL_SOCKET -u $MYSQL_USER -p"$MYSQL_PASS" -e "SELECT table_schema as DB, ROUND(SUM(data_length+index_length)/1024/1024,2) as MB FROM information_schema.tables WHERE table_schema NOT IN ('information_schema','performance_schema','mysql') GROUP BY table_schema" 2>/dev/null