#!/bin/bash
PGDATA="${PGDATA:-/var/lib/pgsql/data}"
if pgrep postgres > /dev/null; then echo "PostgreSQL running: $(pgrep postgres)"; exit 0; fi
systemctl start postgresql 2>/dev/null || su - postgres -c "pg_ctl start -D $PGDATA"
for i in {1..30}; do su - postgres -c "psql -c 'SELECT 1'" >/dev/null 2>&1 && echo "Started" && exit 0; sleep 1; done
echo "Start failed"; exit 1