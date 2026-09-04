#!/bin/bash
REDIS_CONF="${REDIS_CONF:-/etc/redis.conf}"
if pgrep redis-server > /dev/null; then echo "Redis running"; exit 0; fi
systemctl start redis 2>/dev/null || redis-server $REDIS_CONF --daemonize yes
for i in {1..10}; do redis-cli ping >/dev/null 2>&1 && echo "Started" && exit 0; sleep 1; done
echo "Start failed"; exit 1