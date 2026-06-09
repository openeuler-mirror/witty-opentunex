#!/bin/bash
su - postgres -c "psql -c 'DROP TABLE IF EXISTS pgbench_accounts, pgbench_branches, pgbench_history, pgbench_tellers'" pgbench 2>&1