#!/bin/bash
MYSQL_SOCKET="${MYSQL_SOCKET:-/var/lib/mysql/mysql.sock}"
if ! pgrep mysqld > /dev/null; then echo "Not running"; exit 0; fi
systemctl stop mysqld 2>/dev/null || mysqladmin -S $MYSQL_SOCKET shutdown 2>/dev/null || pkill mysqld
for i in {1..10}; do pgrep mysqld > /dev/null || { echo "Stopped"; exit 0; }; sleep 1; done
pkill -9 mysqld; echo "Force stopped"