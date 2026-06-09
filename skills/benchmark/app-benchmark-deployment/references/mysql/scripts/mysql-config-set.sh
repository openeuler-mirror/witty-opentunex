#!/bin/bash
MYSQL_SOCKET="${MYSQL_SOCKET:-/var/lib/mysql/mysql.sock}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-123456}"
[ $# -ne 2 ] && echo "Usage: $0 variable_name value" && exit 1
mysql -S $MYSQL_SOCKET -u $MYSQL_USER -p"$MYSQL_PASS" -e "SET GLOBAL $1 = $2" 2>/dev/null && echo "Set $1=$2" || echo "Failed"