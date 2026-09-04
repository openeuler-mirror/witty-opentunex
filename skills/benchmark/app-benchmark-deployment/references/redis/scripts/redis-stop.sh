#!/bin/bash
if ! pgrep redis-server > /dev/null; then echo "Not running"; exit 0; fi
systemctl stop redis 2>/dev/null || redis-cli shutdown 2>/dev/null || pkill redis-server
for i in {1..10}; do pgrep redis-server > /dev/null || { echo "Stopped"; exit 0; }; sleep 1; done
pkill -9 redis-server; echo "Force stopped"