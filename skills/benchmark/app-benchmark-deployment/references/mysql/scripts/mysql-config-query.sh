#!/bin/bash
MYSQL_SOCKET="${MYSQL_SOCKET:-/var/lib/mysql/mysql.sock}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-123456}"
if [ -z "$1" ]; then
  mysql -S $MYSQL_SOCKET -u $MYSQL_USER -p"$MYSQL_PASS" -e "SHOW GLOBAL VARIABLES" 2>/dev/null | column -t
else
  mysql -S $MYSQL_SOCKET -u $MYSQL_USER -p"$MYSQL_PASS" -e "SHOW GLOBAL VARIABLES LIKE '$1'" 2>/dev/null | column -t
fi