#!/bin/bash
# Execute commands on remote client
# Usage: execute_remote.sh <user@host> "<command>"

REMOTE_HOST=${1:-}
COMMAND=${2:-}

if [ -z "$REMOTE_HOST" ] || [ -z "$COMMAND" ]; then
  echo "Usage: $0 <user@host> <command>"
  echo "Example: $0 root@192.168.1.100 'uname -r'"
  exit 1
fi

ssh -q -tt "$REMOTE_HOST" "$COMMAND"
