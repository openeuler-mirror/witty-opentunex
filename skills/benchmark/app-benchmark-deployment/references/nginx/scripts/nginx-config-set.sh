#!/bin/bash
[ $# -ne 2 ] && echo "Usage: $0 directive value" && exit 1
echo "Set $1 = $2 (manual edit required, then reload)"
nginx -s reload