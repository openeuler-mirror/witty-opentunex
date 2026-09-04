#!/bin/bash
PGDATA="${PGDATA:-/var/lib/pgsql/data}"
if ! pgrep postgres > /dev/null; then echo "Not running"; exit 0; fi
systemctl stop postgresql 2>/dev/null || su - postgres -c "pg_ctl stop -D $PGDATA"
for i in {1..10}; do pgrep postgres > /dev/null || { echo "Stopped"; exit 0; }; sleep 1; done
pkill postgres; echo "Force stopped"