#!/bin/bash
[ $# -ne 2 ] && echo "Usage: $0 parameter value" && exit 1
su - postgres -c "psql -c \"ALTER SYSTEM SET $1 = $2;\"" 2>/dev/null && echo "Set $1=$2" || echo "Failed"