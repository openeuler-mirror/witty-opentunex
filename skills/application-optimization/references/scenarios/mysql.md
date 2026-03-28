---
name: mysql-optimization
description: MySQL/MariaDB performance optimization with InnoDB tuning, query optimization, connection pooling, and configuration management.
---

# MySQL Performance Optimization

This skill provides comprehensive MySQL/MariaDB performance optimization based on system-level bottleneck analysis and application-specific metrics.

---

## Pre-requisites

- MySQL/MariaDB server installed and running
- Sufficient memory for configuration changes
- Backup of current configuration
- Monitoring tools installed (optional): mysqltuner, pt-mysql-summary

---

## Configuration File Detection

**Common MySQL Configuration Paths**:

| Path | Distribution | Notes |
|------|---------------|--------|
| /etc/mysql/my.cnf | Debian/Ubuntu | Main config, includes conf.d |
| /etc/my.cnf | RHEL/CentOS | Main config |
| /usr/local/mysql/my.cnf | Source install | Custom install |
| ~/.my.cnf | User-specific | User-level config |
| /etc/mysql/conf.d/*.cnf | Debian/Ubuntu | Additional configs |

**Detection Commands**:

```bash
# Detect MySQL configuration file
for path in /etc/mysql/my.cnf /etc/my.cnf /usr/local/mysql/my.cnf ~/.my.cnf; do
  if [ -f "$path" ]; then
    echo "Found MySQL config: $path"
  fi
done

# Check for include directories
if [ -d /etc/mysql/conf.d ]; then
  echo "Found MySQL conf.d: /etc/mysql/conf.d/"
  ls -la /etc/mysql/conf.d/
fi

# Check MySQL version and installation type
mysql --version
mysqladmin -u root -p version

# Check MySQL data directory
mysql -e "SHOW VARIABLES LIKE 'datadir';"

# Check running MySQL processes
ps aux | grep mysqld
```

---

## Configuration Backup

```bash
# Backup MySQL configuration
BACKUP_DIR="/opt/optimization-backup/mysql_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup configuration files
cp /etc/mysql/my.cnf $BACKUP_DIR/my.cnf.backup
cp /etc/my.cnf $BACKUP_DIR/my.cnf.backup 2>/dev/null || true
cp -r /etc/mysql/conf.d $BACKUP_DIR/conf.d.backup 2>/dev/null || true

# Backup current configuration
mysql -e "SHOW VARIABLES;" > $BACKUP_DIR/mysql_variables.txt
mysql -e "SHOW GLOBAL VARIABLES;" > $BACKUP_DIR/mysql_global_variables.txt

# Create backup manifest
cat > $BACKUP_DIR/backup_manifest.txt << EOF
MySQL Backup
Date: $(date)
MySQL Version: $(mysql --version)
Configuration Files:
  - my.cnf
  - conf.d/
Variables: mysql_variables.txt, mysql_global_variables.txt
EOF
```

---

## Bottleneck Analysis

Based on system-level bottleneck analysis, identify MySQL-specific bottlenecks:

### InnoDB Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Small buffer pool | High disk I/O, low buffer pool hit ratio | Critical | Increase innodb_buffer_pool_size |
| Frequent checkpoints | High write I/O spikes | High | Increase innodb_log_file_size |
| Lock contention | High lock wait time, deadlocks | High | Reduce transaction size, optimize queries |
| Page flushing issues | High dirty page flushes | Medium | Tune innodb_max_dirty_pages_pct |
| Log buffer too small | High log buffer waits | Medium | Increase innodb_log_buffer_size |

### Query Performance Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Slow queries | High slow query count, long query time | Critical | Optimize queries, add indexes |
| Full table scans | High handler_read_rnd_next | High | Add appropriate indexes |
| Temporary tables | High tmp_table creation | High | Increase tmp_table_size, optimize queries |
| No query cache hit | Low qcache_hits (if enabled) | Medium | Tune query_cache_size or disable |
| Sort buffer issues | High sort_merge_passes | Medium | Increase sort_buffer_size |

### Connection Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Connection exhaustion | Too many connections error | Critical | Increase max_connections |
| Thread creation overhead | High thread creation rate | Medium | Increase thread_cache_size |
| Connection wait time | High wait_timeout usage | Medium | Tune wait_timeout, interactive_timeout |

---

## Optimization Recommendations

### 1. InnoDB Buffer Pool Optimization

**Objective**: Allocate sufficient memory for InnoDB buffer pool to reduce disk I/O.

**Current Value Check**:
```bash
mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
mysql -e "SHOW STATUS LIKE 'Innodb_buffer_pool_reads%';"
```

**Calculation**:
```
Recommended innodb_buffer_pool_size = 70-80% of available RAM
- For dedicated MySQL server: 70-80% of RAM
- For shared server: 40-60% of RAM
- For 16GB RAM server: 11-13GB for buffer pool
```

**Recommended Configuration**:
```ini
[mysqld]
# InnoDB buffer pool (70-80% of RAM for dedicated server)
innodb_buffer_pool_size = 12G

# Multiple buffer pool instances for large servers
innodb_buffer_pool_instances = 4

# Buffer pool chunk size (default 128MB, matches instances)
innodb_buffer_pool_chunk_size = 128M
```

**Verification**:
```bash
# Check buffer pool hit ratio
mysql -e "
  SELECT
    (1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)) * 100 AS hit_ratio
  FROM information_schema.GLOBAL_STATUS;
"

# Target hit ratio: > 99%
```

**Risk**: Medium - Requires sufficient memory, may cause OOM if too large

**Expected Impact**: 30-50% reduction in disk I/O for read-heavy workloads

---

### 2. InnoDB Log File Size Optimization

**Objective**: Optimize log file size to balance checkpoint frequency and recovery time.

**Current Value Check**:
```bash
mysql -e "SHOW VARIABLES LIKE 'innodb_log_file_size';"
mysql -e "SHOW STATUS LIKE 'Innodb_log%';"
```

**Recommended Configuration**:
```ini
[mysqld]
# InnoDB log file size (25-50% of buffer pool size)
innodb_log_file_size = 256M

# Number of log files (default 2)
innodb_log_files_in_group = 2

# Log buffer size (16-64MB)
innodb_log_buffer_size = 64M

# Log flush method
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
```

**Risk**: High - Requires stopping MySQL, removing old log files

**Expected Impact**: 20-40% reduction in write I/O spikes

**Note**: Changing log file size requires:
1. Stop MySQL: `systemctl stop mysql`
2. Remove old log files: `rm /var/lib/mysql/ib_logfile*`
3. Start MySQL: `systemctl start mysql`

---

### 3. InnoDB I/O Optimization

**Objective**: Optimize InnoDB I/O operations for better performance.

**Recommended Configuration**:
```ini
[mysqld]
# I/O concurrency (0 = auto-tune, 2-4 on SSD, 200+ on HDD)
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000

# Dirty page percentage (75-90)
innodb_max_dirty_pages_pct = 75

# Flush method (O_DIRECT for direct I/O, bypassing OS cache)
innodb_flush_method = O_DIRECT

# Flush neighbor pages (1 for SSD, 0 for HDD)
innodb_flush_neighbors = 1

# Purge threads (number of purge threads)
innodb_purge_threads = 4

# Read I/O threads
innodb_read_io_threads = 8

# Write I/O threads
innodb_write_io_threads = 8
```

**Risk**: Low-Medium - Depends on storage type

**Expected Impact**: 10-30% improvement in I/O throughput

---

### 4. Query Cache Optimization

**Objective**: Optimize or disable query cache based on workload.

**Analysis**:
```bash
# Check query cache status
mysql -e "SHOW VARIABLES LIKE 'query_cache%';"
mysql -e "SHOW STATUS LIKE 'Qcache%';"

# Calculate hit ratio
mysql -e "
  SELECT
    Qcache_hits / (Qcache_hits + Qcache_inserts) * 100 AS hit_ratio
  FROM information_schema.GLOBAL_STATUS;
"
```

**Recommendation**:
```ini
[mysqld]
# For InnoDB workloads: Disable query cache
query_cache_type = 0
query_cache_size = 0

# For mixed workloads with many repeated queries:
# query_cache_type = 1
# query_cache_size = 64M
# query_cache_limit = 2M
```

**Risk**: Low

**Expected Impact**: 5-15% improvement for InnoDB workloads

**Note**: Query cache is deprecated in MySQL 8.0 and removed in later versions.

---

### 5. Connection Pool Optimization

**Objective**: Optimize connection handling for better performance.

**Current Value Check**:
```bash
mysql -e "SHOW VARIABLES LIKE 'max_connections';"
mysql -e "SHOW VARIABLES LIKE 'thread_cache_size';"
mysql -e "SHOW VARIABLES LIKE 'wait_timeout';"
```

**Recommended Configuration**:
```ini
[mysqld]
# Maximum connections (500-1000 for high-traffic)
max_connections = 500

# Thread cache size (16-100)
thread_cache_size = 100

# Connection timeout (8-30 seconds)
wait_timeout = 30
interactive_timeout = 30

# Connection backlog (512-2048)
back_log = 512

# Table open cache (4000-10000)
table_open_cache = 8000
table_definition_cache = 2000
```

**Verification**:
```bash
# Check connection usage
mysql -e "SHOW STATUS LIKE 'Threads_connected';"
mysql -e "SHOW STATUS LIKE 'Max_used_connections';"

# Check thread cache efficiency
mysql -e "
  SELECT
    Threads_created,
    Connections,
    (1 - (Threads_created / Connections)) * 100 AS cache_hit_ratio
  FROM information_schema.GLOBAL_STATUS;
"
```

**Risk**: Medium - Increased memory usage per connection

**Expected Impact**: 10-20% improvement in connection handling

---

### 6. Temporary Table Optimization

**Objective**: Optimize temporary table creation for complex queries.

**Current Value Check**:
```bash
mysql -e "SHOW VARIABLES LIKE 'tmp_table_size';"
mysql -e "SHOW VARIABLES LIKE 'max_heap_table_size';"
mysql -e "SHOW STATUS LIKE 'Created_tmp%';"
```

**Recommended Configuration**:
```ini
[mysqld]
# Temporary table size (64-256M)
tmp_table_size = 128M
max_heap_table_size = 128M

# Temporary file path (fast disk if possible)
tmpdir = /dev/shm/mysql

# Enable on-disk temporary tables
internal_tmp_mem_storage_engine = TempTable
```

**Verification**:
```bash
# Check temporary table creation
mysql -e "SHOW STATUS LIKE 'Created_tmp_%';"

# Check disk vs memory temporary tables
mysql -e "
  SELECT
    Created_tmp_disk_tables,
    Created_tmp_tables,
    Created_tmp_disk_tables / Created_tmp_tables * 100 AS disk_percentage
  FROM information_schema.GLOBAL_STATUS;
"
```

**Risk**: Low-Medium - Increased memory usage

**Expected Impact**: 10-30% improvement for complex query workloads

---

### 7. Slow Query Log Optimization

**Objective**: Enable slow query logging for performance analysis.

**Recommended Configuration**:
```ini
[mysqld]
# Slow query log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log

# Long query time (1-10 seconds)
long_query_time = 2

# Log queries without indexes
log_queries_not_using_indexes = 1

# Log slow admin statements
log_slow_admin_statements = 1
```

**Verification**:
```bash
# Check slow query log
tail -f /var/log/mysql/mysql-slow.log

# Analyze slow queries
pt-query-digest /var/log/mysql/mysql-slow.log
```

**Risk**: Low - Slight performance overhead for logging

**Expected Impact**: Enables identification of performance bottlenecks

---

### 8. Character Set and Collation Optimization

**Objective**: Use UTF-8 for international character support.

**Recommended Configuration**:
```ini
[mysqld]
# Character set
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# Connection character set
init_connect = 'SET NAMES utf8mb4'

# Client character set
character-set-client-handshake = FALSE
```

**Risk**: Low - May require application changes

**Expected Impact**: Better international character support

---

## Optimization Procedure

### Step 1: Pre-Optimization Baseline

```bash
# Collect current performance metrics
mysql -e "SHOW GLOBAL STATUS;" > /tmp/mysql_status_before.txt
mysql -e "SHOW GLOBAL VARIABLES;" > /tmp/mysql_variables_before.txt

# Collect InnoDB metrics
mysql -e "SHOW ENGINE INNODB STATUS\G" > /tmp/innodb_status_before.txt

# Record timestamp
date > /tmp/mysql_baseline_timestamp.txt
```

### Step 2: Apply Configuration Changes

```bash
# Create optimized configuration
cat > /etc/mysql/conf.d/99-optimization.cnf << EOF
[mysqld]
# InnoDB optimization
innodb_buffer_pool_size = 12G
innodb_buffer_pool_instances = 4
innodb_log_file_size = 256M
innodb_log_buffer_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000

# Connection optimization
max_connections = 500
thread_cache_size = 100
wait_timeout = 30
interactive_timeout = 30

# Query optimization
query_cache_type = 0
query_cache_size = 0

# Temporary table optimization
tmp_table_size = 128M
max_heap_table_size = 128M

# Slow query log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 2
EOF

# Test configuration
mysqld --defaults-file=/etc/mysql/my.cnf --validate-config

# Restart MySQL
systemctl restart mysql

# Verify MySQL started
systemctl status mysql
mysql -e "SELECT 1"
```

### Step 3: Post-Optimization Verification

```bash
# Collect new performance metrics
mysql -e "SHOW GLOBAL STATUS;" > /tmp/mysql_status_after.txt
mysql -e "SHOW GLOBAL VARIABLES;" > /tmp/mysql_variables_after.txt

# Collect InnoDB metrics
mysql -e "SHOW ENGINE INNODB STATUS\G" > /tmp/innodb_status_after.txt

# Verify configuration applied
mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
mysql -e "SHOW VARIABLES LIKE 'max_connections';"
```

### Step 4: Performance Comparison

```bash
# Compare buffer pool hit ratio
mysql -e "
  SELECT
    (1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)) * 100 AS hit_ratio
  FROM information_schema.GLOBAL_STATUS;
"
# Target: > 99%

# Check connection usage
mysql -e "SHOW STATUS LIKE 'Threads_connected';"
mysql -e "SHOW STATUS LIKE 'Max_used_connections';"

# Check I/O performance
iostat -x 1 5
```

---

## Monitoring and Maintenance

### Key Metrics to Monitor

```bash
# Buffer pool hit ratio
mysql -e "
  SELECT
    (1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)) * 100 AS hit_ratio
  FROM information_schema.GLOBAL_STATUS;
"

# Query performance
mysql -e "SHOW STATUS LIKE 'Slow_queries';"
mysql -e "SHOW STATUS LIKE 'Questions';"

# Connection metrics
mysql -e "SHOW STATUS LIKE 'Threads_connected';"
mysql -e "SHOW STATUS LIKE 'Aborted_clients';"
mysql -e "SHOW STATUS LIKE 'Aborted_connections';"

# InnoDB metrics
mysql -e "SHOW ENGINE INNODB STATUS\G"
```

### Recommended Tools

- **MySQLTuner**: `mysqltuner --user root --pass [password]`
- **pt-mysql-summary**: `pt-mysql-summary --user root --ask-pass`
- **pt-query-digest**: Analyze slow query log
- **Performance Schema**: Built-in performance monitoring

---

## Rollback Procedure

```bash
# Stop MySQL
systemctl stop mysql

# Restore backup configuration
cp /opt/optimization-backup/mysql_*/my.cnf.backup /etc/mysql/my.cnf
cp -r /opt/optimization-backup/mysql_*/conf.d.backup/* /etc/mysql/conf.d/

# If log file size was changed, remove old log files
rm -f /var/lib/mysql/ib_logfile*

# Start MySQL
systemctl start mysql

# Verify MySQL started
systemctl status mysql
mysql -e "SELECT 1"
```

---

## Common Issues and Solutions

### Issue 1: MySQL won't start after configuration change
**Solution**: Check error log: `tail -f /var/log/mysql/error.log`

### Issue 2: Out of memory errors
**Solution**: Reduce `innodb_buffer_pool_size`, ensure swap is available

### Issue 3: High CPU usage
**Solution**: Check for slow queries, optimize indexes, reduce thread cache

### Issue 4: High I/O wait
**Solution**: Increase `innodb_buffer_pool_size`, check disk performance

---

## Additional Resources

- [MySQL Reference Manual](https://dev.mysql.com/doc/refman/8.0/en/)
- [InnoDB Performance Tuning](https://dev.mysql.com/doc/refman/8.0/en/optimizing-innodb.html)
- [MySQLTuner](https://github.com/major/MySQLTuner-perl)
