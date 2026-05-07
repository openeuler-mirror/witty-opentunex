---
name: postgres-optimization
description: PostgreSQL performance optimization with shared buffers, work memory, autovacuum, and connection pooling.
---

# PostgreSQL Performance Optimization

This skill provides comprehensive PostgreSQL performance optimization based on system-level bottleneck analysis and application-specific metrics.

---

## Pre-requisites

- PostgreSQL server installed and running
- Sufficient memory for configuration changes
- Backup of current configuration
- Monitoring tools installed (optional): pg_stat_statements, pgBadger

---

## Configuration File Detection

**Common PostgreSQL Configuration Paths**:

| Path | Distribution | Notes |
|------|---------------|--------|
| /etc/postgresql/*/main/postgresql.conf | Debian/Ubuntu | Main config |
| /var/lib/pgsql/data/postgresql.conf | RHEL/CentOS | Main config |
| /usr/local/pgsql/data/postgresql.conf | Source install | Custom install |

**Detection Commands**:

```bash
# Detect PostgreSQL configuration file
find /etc/postgresql -name postgresql.conf 2>/dev/null
find /var/lib/pgsql/data -name postgresql.conf 2>/dev/null

# Check PostgreSQL version and installation type
psql --version
psql -c "SELECT version();"

# Check PostgreSQL data directory
psql -c "SHOW data_directory;"

# Check running PostgreSQL processes
ps aux | grep postgres
```

---

## Configuration Backup

```bash
# Backup PostgreSQL configuration
BACKUP_DIR="/opt/optimization-backup/postgres_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Find and backup configuration files
PG_CONF=$(find /etc/postgresql -name postgresql.conf 2>/dev/null | head -1)
if [ -z "$PG_CONF" ]; then
  PG_CONF=$(find /var/lib/pgsql/data -name postgresql.conf 2>/dev/null | head -1)
fi

cp "$PG_CONF" $BACKUP_DIR/postgresql.conf.backup
cp ${PG_CONF%/*}/pg_hba.conf $BACKUP_DIR/pg_hba.conf.backup 2>/dev/null || true
cp ${PG_CONF%/*}/pg_ident.conf $BACKUP_DIR/pg_ident.conf.backup 2>/dev/null || true

# Backup current configuration
psql -c "SHOW ALL;" > $BACKUP_DIR/postgres_settings.txt

# Create backup manifest
cat > $BACKUP_DIR/backup_manifest.txt << EOF
PostgreSQL Backup
Date: $(date)
PostgreSQL Version: $(psql --version)
Configuration Files:
  - postgresql.conf
  - pg_hba.conf
  - pg_ident.conf
Settings: postgres_settings.txt
EOF
```

---

## Bottleneck Analysis

Based on system-level bottleneck analysis, identify PostgreSQL-specific bottlenecks:

### Memory Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Small shared buffers | High disk I/O, low cache hit ratio | Critical | Increase shared_buffers |
| Small work mem | Slow queries, temp file usage | High | Increase work_mem |
| Insufficient effective cache | Low cache hit ratio | Critical | Tune shared_buffers, effective_cache_size |
| Memory exhaustion | OOM errors | Critical | Reduce memory parameters |

### I/O Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| High disk I/O | Slow query performance | High | Increase shared_buffers, use SSD |
| Checkpoint storms | High I/O spikes | High | Tune checkpoint parameters |
| WAL bottleneck | High WAL usage | High | Tune wal_buffers, wal_size |
| Temp file I/O | High temp file usage | Medium | Increase work_mem, maintenance_work_mem |

### CPU Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| High CPU usage | Slow query execution | High | Optimize queries, add indexes |
| Parallel query issues | Inefficient parallel execution | Medium | Tune max_parallel_workers |
| CPU-bound queries | Long-running queries | Critical | Optimize queries, add indexes |

### Autovacuum Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Autovacuum not running | Table bloat, transaction ID wraparound | Critical | Tune autovacuum parameters |
| Slow autovacuum | Performance degradation | High | Increase autovacuum workers |
| Autovacuum conflicts | Lock contention | Medium | Tune autovacuum_cost_delay |

---

## Optimization Recommendations

### 1. Shared Buffers Optimization

**Objective**: Allocate sufficient memory for shared buffers to reduce disk I/O.

**Current Value Check**:
```bash
psql -c "SHOW shared_buffers;"
psql -c "SHOW effective_cache_size;"
psql -c "SELECT SUM(heap_blks_read) AS heap_read, SUM(heap_blks_hit) AS heap_hit, (SUM(heap_blks_hit)::float / NULLIF(SUM(heap_blks_read) + SUM(heap_blks_hit), 0) * 100) AS cache_hit_ratio FROM pg_stat_database;"
```

**Recommended Configuration**:
```ini
# Shared buffers (25-40% of RAM for dedicated database server)
shared_buffers = 4GB

# Effective cache size (50-75% of RAM)
effective_cache_size = 12GB
```

**Calculation**:
```
shared_buffers = 25-40% of RAM (for dedicated server)
effective_cache_size = 50-75% of RAM (includes shared_buffers + OS cache)

Example for 16GB RAM:
- shared_buffers = 4GB (25%)
- effective_cache_size = 12GB (75%)
```

**Verification**:
```bash
# Check cache hit ratio
psql -c "
  SELECT
    SUM(heap_blks_hit) / NULLIF(SUM(heap_blks_read) + SUM(heap_blks_hit), 0) * 100 AS cache_hit_ratio
  FROM pg_stat_database;
"
# Target: > 99%
```

**Risk**: Medium - Requires sufficient memory

**Expected Impact**: 30-50% reduction in disk I/O

---

### 2. Work Memory Optimization

**Objective**: Optimize work memory for sorting and hashing operations.

**Current Value Check**:
```bash
psql -c "SHOW work_mem;"
psql -c "SHOW maintenance_work_mem;"
psql -c "SELECT sum(sort_mem) / sum(sort_time) AS avg_sort_mem FROM (SELECT count(*) AS sort_mem, sum(EXTRACT(EPOCH FROM (query_end - query_start))) AS sort_time FROM pg_stat_statements WHERE sort_count > 0) AS t;"
```

**Recommended Configuration**:
```ini
# Work memory (memory per sort operation)
work_mem = 64MB

# Maintenance work memory (memory for maintenance operations like VACUUM, CREATE INDEX)
maintenance_work_mem = 512MB
```

**Calculation**:
```
work_mem = (RAM - shared_buffers) / (max_connections * 3)
Example: (16GB - 4GB) / (200 * 3) ≈ 20MB → Use 64MB

maintenance_work_mem = work_mem * 8-10
Example: 64MB * 8 = 512MB
```

**Verification**:
```bash
# Check temp file usage
psql -c "SELECT * FROM pg_stat_database WHERE temp_files > 0;"

# Check sort operations
psql -c "SELECT * FROM pg_stat_statements WHERE sort_count > 0 ORDER BY mean_exec_time DESC LIMIT 10;"
```

**Risk**: Medium - Increased memory usage per operation

**Expected Impact**: 20-40% improvement in sorting performance

---

### 3. Checkpoint Optimization

**Objective**: Optimize checkpoint parameters to reduce I/O spikes.

**Current Value Check**:
```bash
psql -c "SHOW checkpoint_completion_target;"
psql -c "SHOW checkpoint_warning;"
psql -c "SHOW wal_buffers;"
```

**Recommended Configuration**:
```ini
# Checkpoint target (0-1, 0.5 = spread over 50% of checkpoint interval)
checkpoint_completion_target = 0.9

# Checkpoint warning (in seconds)
checkpoint_warning = 30s

# WAL buffers (16KB units)
wal_buffers = 16MB

# Minimum WAL size (checkpoint_segments * wal_segment_size in older versions)
min_wal_size = 1GB

# Maximum WAL size
max_wal_size = 4GB
```

**Verification**:
```bash
# Check checkpoint activity
psql -c "SELECT * FROM pg_stat_bgwriter;"

# Check WAL usage
psql -c "SELECT * FROM pg_stat_wal;"
```

**Risk**: Low-Medium

**Expected Impact**: 20-30% reduction in I/O spikes

---

### 4. Autovacuum Optimization

**Objective**: Optimize autovacuum parameters to prevent table bloat.

**Current Value Check**:
```bash
psql -c "SHOW autovacuum;"
psql -c "SHOW autovacuum_analyze_scale_factor;"
psql -c "SHOW autovacuum_vacuum_scale_factor;"
psql -c "SHOW autovacuum_max_workers;"
```

**Recommended Configuration**:
```ini
# Enable autovacuum
autovacuum = on

# Autovacuum workers
autovacuum_max_workers = 4

# Vacuum scale factor (percentage of table size)
autovacuum_vacuum_scale_factor = 0.1

# Analyze scale factor
autovacuum_analyze_scale_factor = 0.05

# Vacuum threshold (number of tuples)
autovacuum_vacuum_threshold = 1000

# Analyze threshold
autovacuum_analyze_threshold = 500

# Vacuum cost delay (milliseconds)
autovacuum_vacuum_cost_delay = 10ms

# Vacuum cost limit
autovacuum_vacuum_cost_limit = 200

# Auto-analyze
autovacuum_analyze = on
```

**Verification**:
```bash
# Check autovacuum activity
psql -c "SELECT * FROM pg_stat_user_tables ORDER BY autovacuum_count DESC LIMIT 10;"

# Check table bloat
psql -c "SELECT schemaname, tablename, n_dead_tup FROM pg_stat_user_tables WHERE n_dead_tup > 1000;"
```

**Risk**: Low-Medium - May cause performance degradation if too aggressive

**Expected Impact**: Prevents table bloat, maintains performance

---

### 5. Connection Pooling Optimization

**Objective**: Optimize connection handling for better performance.

**Current Value Check**:
```bash
psql -c "SHOW max_connections;"
psql -c "SHOW shared_preload_libraries;"
psql -c "SELECT count(*) FROM pg_stat_activity;"
```

**Recommended Configuration**:
```ini
# Maximum connections
max_connections = 200

# Superuser reserved connections
superuser_reserved_connections = 3

# Shared preload libraries (for PgBouncer)
shared_preload_libraries = 'pg_stat_statements'

# Track activity counts (performance impact)
track_activity_query_size = 1024
track_counts = on
track_functions = all
track_io_timing = on
```

**Connection Pooling with PgBouncer**:
```ini
# PgBouncer configuration (in pgbouncer.ini)
[databases]
mydb = host=localhost port=5432 dbname=mydb

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = md5
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
reserve_pool_size = 5
reserve_pool_timeout = 3
max_db_connections = 50
server_idle_timeout = 600
server_lifetime = 3600
```

**Verification**:
```bash
# Check active connections
psql -c "SELECT state, count(*) FROM pg_stat_activity GROUP BY state;"

# Check connection pooling
psql -c "SELECT * FROM pg_stat_activity WHERE application_name = 'pgbouncer';"
```

**Risk**: Medium - Increased memory usage

**Expected Impact**: 30-50% improvement in connection handling

---

### 6. Query Optimization

**Objective**: Enable query performance tracking and optimization.

**Recommended Configuration**:
```ini
# Enable pg_stat_statements
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
pg_stat_statements.max = 10000

# Enable logging
log_min_duration_statement = 1000  # Log queries slower than 1 second
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
```

**Verification**:
```bash
# Check slow queries
psql -c "SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"

# Check query performance
psql -c "SELECT queryid, calls, mean_exec_time, max_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"
```

**Risk**: Low - Slight performance overhead for logging

**Expected Impact**: Enables identification of performance bottlenecks

---

## Optimization Procedure

### Step 1: Pre-Optimization Baseline

```bash
# Collect current performance metrics
psql -c "SELECT * FROM pg_stat_database;" > /tmp/postgres_stats_before.txt
psql -c "SHOW ALL;" > /tmp/postgres_settings_before.txt

# Collect buffer hit ratio
psql -c "SELECT SUM(heap_blks_hit) / NULLIF(SUM(heap_blks_read) + SUM(heap_blks_hit), 0) * 100 AS cache_hit_ratio FROM pg_stat_database;" > /tmp/postgres_cache_hit_before.txt

# Record timestamp
date > /tmp/postgres_baseline_timestamp.txt
```

### Step 2: Apply Configuration Changes

```bash
# Find PostgreSQL configuration file
PG_CONF=$(find /etc/postgresql -name postgresql.conf 2>/dev/null | head -1)
if [ -z "$PG_CONF" ]; then
  PG_CONF=$(find /var/lib/pgsql/data -name postgresql.conf 2>/dev/null | head -1)
fi

# Create optimized configuration
cat >> "$PG_CONF" << EOF

# Performance optimization
shared_buffers = 4GB
effective_cache_size = 12GB
work_mem = 64MB
maintenance_work_mem = 512MB

# Checkpoint optimization
checkpoint_completion_target = 0.9
checkpoint_warning = 30s
wal_buffers = 16MB
min_wal_size = 1GB
max_wal_size = 4GB

# Autovacuum optimization
autovacuum_max_workers = 4
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_scale_factor = 0.05
autovacuum_vacuum_threshold = 1000
autovacuum_analyze_threshold = 500
autovacuum_vacuum_cost_delay = 10ms
autovacuum_vacuum_cost_limit = 200

# Connection optimization
max_connections = 200
superuser_reserved_connections = 3

# Query optimization
log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
EOF

# Reload PostgreSQL
systemctl reload postgresql

# Verify configuration loaded
psql -c "SELECT * FROM pg_settings WHERE pending_restart = true;"
```

### Step 3: Post-Optimization Verification

```bash
# Collect new performance metrics
psql -c "SELECT * FROM pg_stat_database;" > /tmp/postgres_stats_after.txt
psql -c "SHOW ALL;" > /tmp/postgres_settings_after.txt

# Collect buffer hit ratio
psql -c "SELECT SUM(heap_blks_hit) / NULLIF(SUM(heap_blks_read) + SUM(heap_blks_hit), 0) * 100 AS cache_hit_ratio FROM pg_stat_database;" > /tmp/postgres_cache_hit_after.txt

# Verify configuration applied
psql -c "SHOW shared_buffers;"
psql -c "SHOW work_mem;"
```

### Step 4: Performance Comparison

```bash
# Compare cache hit ratio
echo "=== Before ==="
cat /tmp/postgres_cache_hit_before.txt

echo "=== After ==="
cat /tmp/postgres_cache_hit_after.txt
```

---

## Monitoring and Maintenance

### Key Metrics to Monitor

```bash
# Cache hit ratio
psql -c "SELECT SUM(heap_blks_hit) / NULLIF(SUM(heap_blks_read) + SUM(heap_blks_hit), 0) * 100 AS cache_hit_ratio FROM pg_stat_database;"

# Active connections
psql -c "SELECT state, count(*) FROM pg_stat_activity GROUP BY state;"

# Long-running queries
psql -c "SELECT pid, now() - query_start AS duration, query FROM pg_stat_activity WHERE state != 'idle' ORDER BY duration DESC LIMIT 10;"

# Table bloat
psql -c "SELECT schemaname, tablename, n_dead_tup FROM pg_stat_user_tables WHERE n_dead_tup > 1000;"
```

### Recommended Tools

- **pg_stat_statements**: Query performance tracking
- **pgBadger**: Log analyzer
- **pg_stat_kcache**: Cache statistics
- **pgTune**: Configuration tuning tool

---

## Rollback Procedure

```bash
# Restore backup configuration
PG_CONF=$(find /etc/postgresql -name postgresql.conf 2>/dev/null | head -1)
if [ -z "$PG_CONF" ]; then
  PG_CONF=$(find /var/lib/pgsql/data -name postgresql.conf 2>/dev/null | head -1)
fi

cp /opt/optimization-backup/postgres_*/postgresql.conf.backup "$PG_CONF"

# Reload PostgreSQL
systemctl reload postgresql

# Verify PostgreSQL running
systemctl status postgresql
psql -c "SELECT 1"
```

---

## Additional Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Performance Tuning Guide](https://wiki.postgresql.org/wiki/Performance_Optimization)
- [pgTune](https://github.com/zardus/postgresql-tuning)
