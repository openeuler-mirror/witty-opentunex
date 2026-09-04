#!/bin/bash
command -v redis-benchmark &>/dev/null && redis-benchmark --version || echo "redis-benchmark: NOT INSTALLED"
pgrep redis-server > /dev/null && echo "Redis: RUNNING" || echo "Redis: STOPPED"