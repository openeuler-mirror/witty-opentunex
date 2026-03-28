#!/bin/bash
# Check client connection helper script
# Usage: check_client_connection.sh <user@host>

REMOTE_HOST=${1:-}

if [ -z "$REMOTE_HOST" ]; then
  echo "Usage: $0 <user@host>"
  echo "Example: $0 root@192.168.1.100"
  exit 1
fi

echo "Checking connection to $REMOTE_HOST..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_HOST" echo 'OK' 2>/dev/null; then
  echo "Connection successful"
  exit 0
else
  echo "Connection failed - passwordless SSH not configured"
  exit 1
fi
