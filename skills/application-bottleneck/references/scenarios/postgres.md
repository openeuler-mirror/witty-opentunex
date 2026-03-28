---
name: postgres-workload
description: PostgreSQL workload analysis: query performance, connection pool, vacuum status, WAL metrics. Use for PostgreSQL database performance troubleshooting.
---

# postgres-workload — PostgreSQL Performance Analysis

**Command execution**: all commands for client should be executed via `ssh`, considering the limits of ssh, allow converting commands to bash script and scp to client and execute if needed. ALL DESTRUCTIVE COMMAND SHOULD REQUEST USER'S COMIRMATION.

**Application Detection**:
```bash
ps aux | grep -E "postgres|postmaster"
psql --version
ss -tlnp | grep -E "5432"
```

---

## Key Metrics Collection

### Connection and Session Status
```bash
# Connection statistics
psql -c "SELECT count(*) FROM pg_stat_activity;"
psql -c "SELECT state, count(*) FROM pg_stat_activity GROUP BY state;"
# Key indicators: active connections > 80% of max_connections, idle_in_transaction > 10
# Long-running queries
psql -c "SELECT pid, now() - query_start as duration, query FROM pg_stat_activity WHERE (now() - query_start) > interval '5 minutes' ORDER BY duration DESC LIMIT 20;"
# Key indicators: queries running > 5 minutes, blocking queries
```

### Query Performance
```bash
# QPS and query statistics
psql -c "SELECT sum(xact_commit) + sum(xact_rollback) as transactions, sum(blks_read) as reads, sum(blks_hit) as hits FROM pg_stat_database;"
# Calculate hit rate: hits / (reads + hits)
# Key indicators: cache hit rate < 95%, declining transaction rate
# Slow queries
psql -c "SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 20;"
# Key indicators: mean_exec_time > 100ms, total_exec_time increasing
```

### Vacuum and Autovacuum Status
```bash
# Vacuum statistics
psql -c "SELECT relname, n_dead_tup, n_live_tup, autovacuum_count, last_autovacuum FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 20;"
# Key indicators: high n_dead_tup ratio, stale autovacuum
# Transaction wraparound risk
psql -c "SELECT datname, age(datfrozenxid) FROM pg_database;"
# Key indicators: age > 1000000000 indicates risk
```

### WAL and Replication Metrics
```bash
# WAL activity
psql -c "SELECT * FROM pg_stat_wal;"
# Key indicators: high wal_bytes, wal_sync_latency > 10ms
# Replication lag (if standby)
psql -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"
# Key indicators: replay_lag > 5s, state != streaming
```

### Locks and Blocking
```bash
# Current locks
psql -c "SELECT * FROM pg_locks WHERE granted = false;"
# Blocking queries
psql -c "SELECT blocked_locks.pid AS blocked_pid, blocked_activity.usename AS blocked_user, blocking_locks.pid AS blocking_pid, blocking_activity.usename AS blocking_user, blocked_activity.query AS blocked_statement, blocking_activity.query AS current_statement_in_blocking_process FROM pg_catalog.pg_locks blocked_locks JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid AND blocking_locks.pid != blocked_locks.pid JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid WHERE NOT blocked_locks.granted;"
# Key indicators: blocking locks > 0, long wait times
```

---

## Bottleneck Identification

| Category | Key Metrics | Thresholds | Collection |
|----------|-------------|------------|------------|
| Connection Pool | active/max connections | > 80% | pg_stat_activity |
| Query Performance | cache hit rate, slow queries | hit rate < 95%, mean_time > 100ms | pg_stat_database, pg_stat_statements |
| Lock Contention | blocked locks, blocking queries | > 0 blocked, wait > 1s | pg_locks |
| Vacuum Lag | dead tuples, autovacuum | n_dead_tup > 10% of n_live_tup | pg_stat_user_tables |
| WAL I/O | wal_sync_latency | > 10ms | pg_stat_wal |
| Replication Lag | replay_lag | > 5s | pg_stat_replication |

---

## Diagnostic Commands

```bash
# Full statistics
psql -c "SELECT * FROM pg_stat_database;"
psql -c "SELECT * FROM pg_stat_user_tables;"
psql -c "SELECT * FROM pg_stat_user_indexes;"
# EXPLAIN ANALYZE for specific queries
psql -c "EXPLAIN (ANALYZE, BUFFERS, VERBOSE) <query>"
# Check configuration
psql -c "SHOW ALL;"
# View current connections
psql -c "SELECT * FROM pg_stat_activity;"
```

---

## Advanced Tools

```bash
# pgAdmin (GUI)
# pgBadger (log analyzer)
pgbadger /var/log/postgresql/postgresql-*.log
# pg_stat_statements (extension)
psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
# pgbench (benchmark)
pgbench -h localhost -p 5432 -U postgres testdb
```

---

## Common Bottleneck Patterns

1. **Connection exhaustion**: Active connections near max_connections, idle_in_transaction > 10, connection refused errors
2. **Slow queries**: High mean_exec_time, cache hit rate < 90%, full table scans
3. **Lock contention**: Blocked locks, blocking queries, wait time > 1s
4. **Vacuum lag**: High dead tuple ratio, table bloat, autovacuum not running
5. **WAL I/O saturation**: High wal_sync_latency, disk I/O bottleneck, replication lag
6. **Replication lag**: replay_lag increasing, standby not keeping up

---

## Output Template

```markdown
## PostgreSQL Workload Analysis

### Connection Status
- Active connections: X / max_connections (Y%)
- Idle in transaction: X
- Long-running queries: X

### Query Performance
- Cache hit rate: X%
- QPS: X (transactions/sec)
- Top slow queries: [list]

### Vacuum Status
- Tables requiring vacuum: X
- Dead tuple ratio: X%
- Autovacuum active: yes/no

### WAL and Replication
- WAL sync latency: Xms
- Replication lag: Xs (if applicable)
- WAL archive status: [status]

### Lock Status
- Blocked locks: X
- Blocking queries: X
- Lock wait time avg: Xms

### Top Bottlenecks
| Component | Issue | Evidence | Impact |
|-----------|-------|----------|--------|
```
