#!/bin/bash
command -v sysbench &>/dev/null && sysbench --version || echo "sysbench: NOT INSTALLED"
pgrep mysqld > /dev/null && echo "MySQL: RUNNING" || echo "MySQL: STOPPED"
mysql -S /var/lib/mysql/mysql.sock -u root -p"123456" -e "SELECT COUNT(*) as tables FROM information_schema.tables WHERE table_schema='sbtest'" 2>/dev/null