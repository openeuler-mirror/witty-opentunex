#!/bin/bash
if ! pgrep nginx > /dev/null; then echo "Not running"; exit 0; fi
nginx -s stop 2>/dev/null || pkill nginx
for i in {1..10}; do pgrep nginx > /dev/null || { echo "Stopped"; exit 0; }; sleep 1; done
pkill -9 nginx; echo "Force stopped"