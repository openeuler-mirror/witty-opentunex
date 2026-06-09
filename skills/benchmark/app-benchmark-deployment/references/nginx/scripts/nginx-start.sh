#!/bin/bash
NGINX_CONF="${NGINX_CONF:-/etc/nginx/nginx.conf}"
if pgrep nginx > /dev/null; then echo "Nginx running: $(pgrep nginx)"; exit 0; fi
nginx -c $NGINX_CONF 2>/dev/null || nginx
for i in {1..10}; do pgrep nginx > /dev/null && echo "Started" && exit 0; sleep 1; done
echo "Start failed"; exit 1