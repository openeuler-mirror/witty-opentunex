#!/bin/bash
echo "=== Redis Status ==="
pgrep redis-server > /dev/null && echo "RUNNING" || echo "STOPPED"
redis-cli ping 2>/dev/null && echo "PONG" || echo "NO RESPONSE"
redis-cli INFO 2>/dev/null | grep -E "redis_version|connected_clients|used_memory_human"