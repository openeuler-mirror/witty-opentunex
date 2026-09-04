#!/bin/bash
command -v nginx &>/dev/null && nginx -v 2>&1 || echo "nginx: NOT INSTALLED"
pgrep nginx > /dev/null && echo "Nginx: RUNNING" || echo "Nginx: STOPPED"
command -v ab &>/dev/null && echo "ab: AVAILABLE" || echo "ab: NOT AVAILABLE"