---
name: mysql-workload
description: MySQL/MariaDB workload analysis: query performance, InnoDB metrics, replication lag, lock contention. Use for database performance troubleshooting and optimization.
---

# mysql-workload — MySQL/MariaDB Performance Analysis

**Command execution**: all commands for client should be executed via `ssh`, considering the limits of ssh, allow converting commands to bash script and scp to client and execute if needed. ALL DESTRUCTIVE COMMAND SHOULD REQUEST USER'S COMIRMATION.

**Application Detection**:
```bash
ps aux | grep -E "mysqld|mariadbd"
ss -tlnp | grep -E "3306"
mysqladmin version 2>/dev/null || mysql --version
```

---

## Key Metrics Collection

### Connection and Thread Status
```bash
# Current connections
mysql -e "SHOW PROCESSLIST"
mysql -e "SHOW STATUS LIKE 'Threads_%'"
mysql -e "SHOW STATUS LIKE 'Max_used_connections'"
mysql -e "SHOW STATUS LIKE 'Connections'"
# Key indicators: Threads_connected > 80% of max_connections, Threads_running > 100
```

### Query Performance
```bash
# QPS and latency
mysql -e "SHOW GLOBAL STATUS LIKE 'Com_%'" | grep -E "Com_select|Com_insert|Com_update|Com_delete"
mysql -e "SHOW GLOBAL STATUS LIKE 'Questions'"
mysql -e "SHOW GLOBAL STATUS LIKE 'Queries'"
mysql -e "SHOW GLOBAL STATUS LIKE 'Uptime'"
# Slow query log
mysql -e "SHOW VARIABLES LIKE 'slow_query_log'"
mysql -e "SHOW VARIABLES LIKE 'long_query_time'"
mysql -e "SHOW VARIABLES LIKE 'slow_query_log_file'"
tail -100 /var/log/mysql/slow-query.log | mysqldumpslow
# Key indicators: QPS declining, slow queries increasing, queries blocked
```

### InnoDB Metrics
```bash
# Buffer pool status
mysql -e "SHOW ENGINE INNODB STATUS\G" | grep -A 20 "BUFFER POOL AND MEMORY"
mysql -e "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_%'"
mysql -e "SHOW GLOBAL STATUS LIKE 'Innodb_page_size'"
# Key indicators: Buffer pool hit rate < 95%, free pages < 10%, flush list > 10000
# Lock waits
mysql -e "SHOW ENGINE INNODB STATUS\G" | grep -A 50 "TRANSACTIONS"
mysql -e "SHOW GLOBAL STATUS LIKE 'Innodb_row_lock_%'"
mysql -e "SHOW GLOBAL STATUS LIKE 'Innodb_deadlocks'"
# Key indicators: lock waits > 100ms, lock wait timeouts > 0, deadlocks > 0
# Redo log and checkpoint
mysql -e "SHOW ENGINE INNODB STATUS\G" | grep -A 10 "LOG"
mysql -e "SHOW GLOBAL STATUS LIKE 'Innodb_os_log_%'"
# Key indicators: log write latency > 10ms, checkpoint age near capacity
```

### Replication Status (if applicable)
```bash
# Master status
mysql -e "SHOW MASTER STATUS"
# Slave status
mysql -e "SHOW SLAVE STATUS\G"
# Key indicators: Seconds_Behind_Master > 10, Slave_IO_Running: No, Slave_SQL_Running: No
```

### Table and Index Analysis
```bash
# Table size and rows
mysql -e "SELECT table_schema, table_name, table_rows, data_length, index_length FROM information_schema.tables WHERE table_schema NOT IN ('information_schema', 'performance_schema', 'mysql') ORDER BY data_length DESC LIMIT 20"
# Fragmentation
mysql -e "SELECT table_schema, table_name, data_free FROM information_schema.tables WHERE data_free > 0 ORDER BY data_free DESC LIMIT 20"
# Unused indexes (use pt-index-usage if available)
pt-index-usage --host localhost /var/log/mysql/mysql-slow.log
```

---

## Bottleneck Identification

| Category | Key Metrics | Thresholds | Collection |
|----------|-------------|------------|------------|
| Connection Pool | Threads_connected, max_connections | > 80% of max | SHOW STATUS LIKE 'Threads_%' |
| CPU Heavy Queries | Com_select, slow queries | QPS drop, slow_qps > 10/s | SHOW STATUS, slow log |
| Lock Contention | Innodb_row_lock_waits, lock_time | avg_wait > 100ms | SHOW ENGINE INNODB STATUS |
| Buffer Pool Pressure | buffer_pool_hit_rate, free_pages | hit_rate < 95%, free < 10% | SHOW STATUS |
| I/O Pressure | Innodb_data_fsyncs, log_writes | fsync_latency > 10ms | SHOW STATUS |
| Replication Lag | Seconds_Behind_Master | > 10s | SHOW SLAVE STATUS |

---

## Diagnostic Commands

```bash
# Full InnoDB status
mysql -e "SHOW ENGINE INNODB STATUS\G" > /tmp/innodb_status.txt
# Check for long-running queries
mysql -e "SELECT id, user, host, db, command, time, state, info FROM information_schema.processlist WHERE time > 5 ORDER BY time DESC"
# Lock wait details
mysql -e "SELECT * FROM sys.innodb_lock_waits"
# Query cache status (if enabled)
mysql -e "SHOW STATUS LIKE 'Qcache_%'"
# Performance schema summary
mysql -e "SELECT * FROM sys.schema_index_statistics ORDER BY rows_inserted DESC LIMIT 20"
```

---

## Advanced Tools

```bash
# pt-summary (Percona Toolkit)
pt-summary --host localhost --port 3306
# pt-mysql-summary
pt-mysql-summary --host localhost
# pt-query-digest (slow query analysis)
pt-query-digest /var/log/mysql/slow-query.log
# Explain query execution plan
mysql -e "EXPLAIN FORMAT=JSON <query>"
```

---

## Common Bottleneck Patterns

1. **Connection exhaustion**: Threads_connected near max_connections, increasing Threads_running
2. **Lock contention**: High Innodb_row_lock_waits, long lock wait times, deadlocks
3. **Buffer pool pressure**: Low hit rate, high free_pages exhaustion, increased page reads
4. **Slow queries**: Long query_time, high full table scans, missing or ineffective indexes
5. **Replication lag**: Seconds_Behind_Master increasing, slave lagging behind master
6. **I/O saturation**: High fsync latency, checkpoint lag, disk I/O bottleneck

---

## Output Template

```markdown
## MySQL Workload Analysis

### Connection Status
- Current connections: X / max_connections (Y%)
- Running threads: X
- Key issues: [if any]

### Query Performance
- QPS: X (selects: X, inserts: X, updates: X, deletes: X)
- Slow query rate: X/s
- Top slow queries: [list]

### InnoDB Health
- Buffer pool hit rate: X%
- Free pages: X (X%)
- Lock wait avg time: Xms, timeouts: X
- Redo log write latency: Xms

### Replication Status (if applicable)
- Slave status: [Running/Stopped]
- Lag: X seconds
- Issues: [if any]

### Top Bottlenecks
| Component | Issue | Evidence | Impact |
|-----------|-------|----------|--------|
```
