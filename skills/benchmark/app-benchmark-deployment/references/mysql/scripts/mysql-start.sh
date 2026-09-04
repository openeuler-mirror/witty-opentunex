#!/bin/bash
MYSQL_SOCKET="${MYSQL_SOCKET:-/var/lib/mysql/mysql.sock}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-123456}"
if pgrep mysqld > /dev/null; then echo "MySQL running: $(pgrep mysqld)"; exit 0; fi
mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld 2>/dev/null
systemctl start mysqld 2>/dev/null || su - mysql -s /bin/bash -c "nohup mysqld --socket=$MYSQL_SOCKET --user=mysql > /opt/opentunex/applications/mysql/logs/mysql.log 2>&1 &"
for i in {1..30}; do mysqladmin -S $MYSQL_SOCKET ping 2>/dev/null && echo "Started" && exit 0; sleep 1; done
echo "Start failed"; exit 1