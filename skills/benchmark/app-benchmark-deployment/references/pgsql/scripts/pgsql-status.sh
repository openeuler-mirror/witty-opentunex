#!/bin/bash
echo "=== PostgreSQL Status ==="
pgrep postgres > /dev/null && echo "Status: RUNNING" || echo "Status: STOPPED"
su - postgres -c "psql -c 'SELECT version()'" 2>/dev/null | head -3
su - postgres -c "psql -l" 2>/dev/null | head -10