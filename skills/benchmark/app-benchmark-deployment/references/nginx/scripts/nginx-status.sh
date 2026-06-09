#!/bin/bash
echo "=== Nginx Status ==="
pgrep nginx > /dev/null && echo "RUNNING" || echo "STOPPED"
nginx -v 2>&1
nginx -t 2>&1 || true
curl -s -o /dev/null -w "HTTP: %{http_code}\n" http://localhost:80 2>/dev/null || echo "No response"