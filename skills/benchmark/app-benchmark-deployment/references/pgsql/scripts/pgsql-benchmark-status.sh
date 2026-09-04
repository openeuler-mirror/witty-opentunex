#!/bin/bash
command -v pgbench &>/dev/null && pgbench --version | head -1 || echo "pgbench: NOT INSTALLED"
pgrep postgres > /dev/null && echo "PostgreSQL: RUNNING" || echo "PostgreSQL: STOPPED"