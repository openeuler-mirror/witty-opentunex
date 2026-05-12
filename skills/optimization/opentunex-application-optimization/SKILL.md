---
name: opentunex-application-optimization
description: Application-specific performance optimization for MySQL, Redis, PostgreSQL, Kafka, Nginx, MongoDB, Java, and Go applications. Uses application-bottleneck analysis to identify app-level bottlenecks, optimize configurations, and validate improvements. Use after os-performance-optimization or when application-level tuning is required.
---

# application-optimization — Application-Specific Performance Optimization

This skill performs systematic application-level performance optimization with the following phases:
1. **Application Detection**: Identify running applications and their scenarios
2. **Application Bottleneck Analysis**: Use application-bottleneck skill for deep-dive analysis
3. **Configuration Backup**: Backup current application configurations
4. **Optimization Recommendation**: Propose application-specific optimization strategies
5. **Optimization Execution**: Apply application-level optimizations
6. **Performance Testing**: Validate improvements with application benchmarks
7. **Optimization Summary**: Summarize results and provide recommendations

**Note**: This skill focuses exclusively on application-level components:
- MySQL/MariaDB configuration tuning
- Redis/Memcached configuration tuning
- PostgreSQL configuration tuning
- Nginx/Apache configuration tuning
- Kafka broker/producer/consumer tuning
- MongoDB configuration tuning
- Java/JVM application tuning
- Go application tuning

**For OS-level optimizations** (kernel params, I/O scheduler, CPU governor, memory management, network stack), use the `os-performance-optimization` skill instead.

---

## Client Connection and Command Execution

Load the remote-execution skill for standardized SSH connection and command execution:

skill:remote-execution

---

## Phase 1: Application Scenario Detection

**Objective**: Detect running applications and determine which scenario skills to load.

**IMPORTANT**: This skill optimizes application-layer components based on:
- Applications detected in running processes
- Listening ports indicating active services
- Bottleneck analysis from application-bottleneck skill

### 1.1 Detect Running Applications

**Detect running applications and their scenarios**:

```bash
# 1. Detect running applications
ssh ${username}@${ip} "ps aux | grep -E 'mysqld|redis-server|kafka|nginx|postgres|mongod|java|go' | grep -v grep"

# 2. Check listening ports
ssh ${username}@${ip} "ss -tlnp | grep -E '3306|6379|9092|80|5432|27017|8080|3000'"

# 3. Check service status
ssh ${username}@${ip} "systemctl list-units --type=service --state=running | grep -E 'mysql|redis|kafka|nginx|postgres|mongodb'"
```

### 1.2 Available Application Scenarios

**Available Application Scenario Skills**:

| Application | Scenario Skill | Key Metrics | Optimization Focus |
|-------------|----------------|-------------|-------------------|
| MySQL | [scenarios/mysql.md](references/scenarios/mysql.md) | QPS, slow queries, buffer pool, lock waits | InnoDB tuning, query optimization, connection pooling |
| Redis | [scenarios/redis.md](references/scenarios/redis.md) | ops/sec, memory, hit rate, eviction | Memory management, persistence, clustering |
| Kafka | [scenarios/kafka.md](references/scenarios/kafka.md) | Message rate, lag, latency, consumer lag | Producer/consumer tuning, broker optimization |
| Nginx | [scenarios/nginx.md](references/scenarios/nginx.md) | requests/sec, response time, upstream | Worker processes, caching, SSL, keepalive |
| PostgreSQL | [scenarios/postgres.md](references/scenarios/postgres.md) | Connections, query latency, WAL, vacuum | Shared buffers, work mem, autovacuum |
| MongoDB | [scenarios/mongodb.md](references/scenarios/mongodb.md) | Opcounters, page faults, connections | WiredTiger cache, journaling, sharding |
| Java App | [scenarios/java.md](references/scenarios/java.md) | GC pauses, heap, threads, JIT | Heap size, GC tuning, thread pool |
| Go App | [scenarios/golang.md](references/scenarios/golang.md) | Goroutines, GC stats, heap | GOMAXPROCS, GOGC, runtime tuning |

---

## Phase 2: Application Bottleneck Analysis

**Objective**: Perform deep-dive analysis into application-specific bottlenecks using the application-bottleneck skill.

**IMPORTANT**: Run the application-bottleneck skill first to identify which application internals need optimization.

Load and execute the application-bottleneck skill:
```
Load the application-bottleneck skill and execute all phases.
```

The application-bottleneck skill provides:
- Application scenario skills for MySQL, Redis, PostgreSQL, Kafka, Nginx, MongoDB, Java, and Go
- Deep-dive metrics collection commands
- Application-system correlation analysis
- Application-specific bottleneck identification

---

**Output**: Complete application bottleneck analysis report with identified issues, severity levels, and evidence.

---

## Phase 3: Configuration Backup

**Objective**: Before applying any application optimization, backup current configurations.

### 3.1 Configuration Path Detection

**For each selected application, detect configuration file locations**:

```bash
# MySQL configuration paths
MYSQL_PATHS=(
  "/etc/mysql/my.cnf"
  "/etc/my.cnf"
  "/usr/local/mysql/my.cnf"
  "~/.my.cnf"
  "/etc/mysql/conf.d/*.cnf"
)

for path in "${MYSQL_PATHS[@]}"; do
  if ssh ${username}@${ip} "test -f $path"; then
    echo "Found MySQL config: $path"
  fi
done

# Redis configuration paths
REDIS_PATHS=(
  "/etc/redis/redis.conf"
  "/etc/redis.conf"
  "/usr/local/etc/redis.conf"
)

for path in "${REDIS_PATHS[@]}"; do
  if ssh ${username}@${ip} "test -f $path"; then
    echo "Found Redis config: $path"
  fi
done

# Nginx configuration paths
NGINX_PATHS=(
  "/etc/nginx/nginx.conf"
  "/usr/local/nginx/conf/nginx.conf"
  "/etc/nginx/conf.d/*.conf"
)

for path in "${NGINX_PATHS[@]}"; do
  if ssh ${username}@${ip} "test -f $path"; then
    echo "Found Nginx config: $path"
  fi
done

# PostgreSQL configuration paths
POSTGRES_PATHS=(
  "/etc/postgresql/*/main/postgresql.conf"
  "/var/lib/pgsql/data/postgresql.conf"
  "/usr/local/pgsql/data/postgresql.conf"
)

for path in "${POSTGRES_PATHS[@]}"; do
  if ssh ${username}@${ip} "test -f $path"; then
    echo "Found PostgreSQL config: $path"
  fi
done

# MongoDB configuration paths
MONGO_PATHS=(
  "/etc/mongod.conf"
  "/etc/mongodb.conf"
  "/usr/local/etc/mongod.conf"
)

for path in "${MONGO_PATHS[@]}"; do
  if ssh ${username}@${ip} "test -f $path"; then
    echo "Found MongoDB config: $path"
  fi
done

# Kafka configuration paths
KAFKA_PATHS=(
  "/etc/kafka/server.properties"
  "/usr/local/kafka/config/server.properties"
  "/opt/kafka/config/server.properties"
)

for path in "${KAFKA_PATHS[@]}"; do
  if ssh ${username}@${ip} "test -f $path"; then
    echo "Found Kafka config: $path"
  fi
done
```

**Confirm configuration paths with user**:

```markdown
### Configuration Path Confirmation

**Application**: [Application Name]

**Detected Configuration Paths**:
- [Path 1]: ✓ Found
- [Path 2]: ✗ Not found
- [Path 3]: ✓ Found

**Please confirm the configuration file to use**:

Options:
1. Use detected path: [Path 1]
2. Use detected path: [Path 3]
3. Specify custom path: _________
4. Skip this application

[User selects option]
```

### 3.2 Configuration Backup

**Backup application configuration before modification**:

```bash
# Create application backup directory
APP_BACKUP_DIR="${BACKUP_DIR}/app_backups/$(date +%Y%m%d_%H%M%S)"
ssh ${username}@${ip} "mkdir -p ${APP_BACKUP_DIR}"

# Backup application configuration
scp ${username}@${ip}:/path/to/app.conf ${APP_BACKUP_DIR}/app.conf.backup

# Backup application data directory (if applicable)
# scp -r ${username}@${ip}:/path/to/app/data ${APP_BACKUP_DIR}/data_backup

# Record backup manifest
cat > ${APP_BACKUP_DIR}/backup_manifest.txt << EOF
Application: [App Name]
Backup Date: $(date)
Config Files:
  - /path/to/app.conf
Data Directories:
  - /path/to/app/data
EOF
```

---

## Phase 4: Optimization Recommendation

**Objective**: Propose application-specific optimization strategies based on bottleneck analysis.

Load scenario-specific optimization recommendations from `references/scenarios/<app>.md`.

### 4.1 Application-Specific Bottleneck Analysis

**Based on Phase 2 (application-bottleneck) analysis, identify application-specific bottlenecks**:

```markdown
### Application Bottleneck Analysis: [Application Name]

**System-Level Bottlenecks (from os-performance-optimization)**:
- [Bottleneck 1]: [Description], [Severity]
- [Bottleneck 2]: [Description], [Severity]

**Application-Specific Metrics (from Phase 2)**:
| Metric | Current Value | Threshold | Status |
|--------|---------------|-----------|--------|
| [Metric 1] | [Value] | [Threshold] | [Status] |
| [Metric 2] | [Value] | [Threshold] | [Status] |
| [Metric 3] | [Value] | [Threshold] | [Status] |

**Identified Application Bottlenecks**:
- [Bottleneck 1]: [Description], [Evidence], [Severity]
- [Bottleneck 2]: [Description], [Evidence], [Severity]

**Optimization Recommendations**:
[Load scenario-specific optimization recommendations from references/scenarios/<app>.md]
```

### 4.2 Scenario Skill Selection

**Ask user to select application scenario to optimize**:

```markdown
### Application Scenario Selection

**Detected Applications**:
| Application | Status | Port | Version | Scenario Available |
|-------------|--------|-------|----------|-------------------|
| [App 1] | Running | [Port] | [Version] | ✓ Yes |
| [App 2] | Running | [Port] | [Version] | ✓ Yes |
| [App 3] | Not Running | - | - | ✗ Not available |

**Please select application scenario to optimize**:

1. MySQL optimization
2. Redis optimization
3. Kafka optimization
4. Nginx optimization
5. PostgreSQL optimization
6. MongoDB optimization
7. Java application optimization
8. Go application optimization
9. Skip application optimization
10. Optimize all detected applications

[User selects option]
```

### 4.3 Application Configuration Optimization

**Apply application-specific optimizations based on scenario skill**.

#### Example for MySQL:

```markdown
### MySQL Configuration Optimization

**Recommended Optimizations** (from scenarios/mysql.md):

#### Optimization 1: InnoDB Buffer Pool
**Current Value**: innodb_buffer_pool_size = 128M
**Recommended Value**: innodb_buffer_pool_size = 4G
**Reason**: Buffer pool too small for workload, causing excessive disk I/O
**Evidence**: High disk I/O, high buffer pool read misses

#### Optimization 2: InnoDB Log File Size
**Current Value**: innodb_log_file_size = 48M
**Recommended Value**: innodb_log_file_size = 256M
**Reason**: Small log files cause frequent checkpoints
**Evidence**: High checkpoint activity, write I/O spikes

#### Optimization 3: Connection Pool
**Current Value**: max_connections = 151
**Recommended Value**: max_connections = 500
**Reason**: Connection exhaustion under peak load
**Evidence**: High connection wait time, connection errors
```

**Apply configuration changes**:

```bash
# 1. Read current configuration
scp ${username}@${ip}:/etc/mysql/my.cnf /tmp/my.cnf.current

# 2. Create optimized configuration
cat > /tmp/my.cnf.optimized << 'EOF'
[mysqld]
# InnoDB optimization
innodb_buffer_pool_size = 4G
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT

# Connection optimization
max_connections = 500
thread_cache_size = 100

# Query cache (disable for InnoDB)
query_cache_type = 0
query_cache_size = 0
EOF

# 3. Backup current configuration
scp /tmp/my.cnf.current ${APP_BACKUP_DIR}/my.cnf.backup

# 4. Apply optimized configuration
scp /tmp/my.cnf.optimized ${username}@${ip}:/tmp/my.cnf.new
ssh ${username}@${ip} "cp /tmp/my.cnf.new /etc/mysql/my.cnf"

# 5. Restart application
ssh ${username}@${ip} "systemctl restart mysql"

# 6. Verify application started
ssh ${username}@${ip} "systemctl status mysql"
ssh ${username}@${ip} "mysql -e 'SELECT 1'"
```

#### Example for Redis:

```bash
# 1. Read current configuration
scp ${username}@${ip}:/etc/redis/redis.conf /tmp/redis.conf.current

# 2. Create optimized configuration
cat > /tmp/redis.conf.optimized << 'EOF'
# Memory optimization
maxmemory 2gb
maxmemory-policy allkeys-lru

# Persistence optimization
save 900 1
save 300 10
save 60 10000
appendonly yes
appendfsync everysec

# Network optimization
tcp-backlog 511
timeout 0
tcp-keepalive 300
EOF

# 3. Backup current configuration
scp /tmp/redis.conf.current ${APP_BACKUP_DIR}/redis.conf.backup

# 4. Apply optimized configuration
scp /tmp/redis.conf.optimized ${username}@${ip}:/tmp/redis.conf.new
ssh ${username}@${ip} "cp /tmp/redis.conf.new /etc/redis/redis.conf"

# 5. Restart application
ssh ${username}@${ip} "systemctl restart redis"

# 6. Verify application
ssh ${username}@${ip} "systemctl status redis"
ssh ${username}@${ip} "redis-cli PING"
```

#### Example for Nginx:

```bash
# 1. Read current configuration
scp ${username}@${ip}:/etc/nginx/nginx.conf /tmp/nginx.conf.current

# 2. Create optimized configuration
cat > /tmp/nginx.conf.optimized << 'EOF'
worker_processes auto;
worker_connections 1024;
multi_accept on;

# Keepalive optimization
keepalive_timeout 65;
keepalive_requests 100;

# Buffer optimization
client_body_buffer_size 10k;
client_header_buffer_size 1k;
client_max_body_size 8m;
large_client_header_buffers 4 32k;

# Gzip compression
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml application/json application/javascript;
EOF

# 3. Backup current configuration
scp /tmp/nginx.conf.current ${APP_BACKUP_DIR}/nginx.conf.backup

# 4. Apply optimized configuration
scp /tmp/nginx.conf.optimized ${username}@${ip}:/tmp/nginx.conf.new
ssh ${username}@${ip} "cp /tmp/nginx.conf.new /etc/nginx/nginx.conf"

# 5. Test and reload
ssh ${username}@${ip} "nginx -t"
ssh ${username}@${ip} "nginx -s reload"
```

---

## Phase 5: Optimization Execution

**Objective**: Apply selected application optimizations.

### 5.1 Apply Optimizations

**For each application optimization**:

```bash
# Apply application configuration changes
# [Application-specific commands as shown above]
```

### 5.2 Post-Optimization Verification

**Verify application optimizations are applied correctly**:

```markdown
### Post-Optimization Verification: [Application Name]

**Configuration Applied**:
| Parameter | Previous | Current | Status |
|-----------|----------|---------|--------|
| [Param 1] | [Old Value] | [New Value] | ✓ Applied |
| [Param 2] | [Old Value] | [New Value] | ✓ Applied |

**Application Status**:
- Service: ✓ Running
- Configuration: ✓ Loaded
- Connections: ✓ Active
- Errors: ✗ None

**Application Metrics (Post-Optimization)**:
| Metric | Before | After | Change | % Change |
|--------|--------|-------|--------|----------|
| [Metric 1] | [Value] | [Value] | [Value] | [X%] |
| [Metric 2] | [Value] | [Value] | [Value] | [Y%] |
| [Metric 3] | [Value] | [Value] | [Value] | [Z%] |

**Verification Commands**:
```bash
# MySQL verification
mysql -e "SHOW VARIABLES LIKE 'innodb_%';"
mysql -e "SHOW STATUS LIKE 'Innodb_%';"

# Redis verification
redis-cli INFO
redis-cli CONFIG GET maxmemory

# Nginx verification
nginx -t
nginx -s reload
```
```

---

## Phase 6: Performance Testing

**Objective**: Run application-specific benchmarks to validate improvements.

### 6.1 Application Performance Testing

**Run application-specific benchmarks to validate improvements**:

```markdown
### Application Performance Testing: [Application Name]

**Benchmark Request**: How would you like to test application performance?

Options:
1. Use built-in application benchmark (mysqlslap, redis-benchmark, etc.)
2. Run custom benchmark script (provide script path)
3. Load test with production workload
4. Skip benchmark (rely on metrics monitoring)

[User selects option]

**Executing Benchmark**: [Command details]

**Benchmark Results**:
| Metric | Pre-Optimization | Post-Optimization | Improvement |
|--------|------------------|-------------------|-------------|
| [Metric 1] | [Value] | [Value] | [+X%] |
| [Metric 2] | [Value] | [Value] | [+Y%] |
| [Metric 3] | [Value] | [Value] | [+Z%] |

**Overall Assessment**:
- ✓ Significant improvement: [+XX%] overall
- Optimal configuration achieved: Yes/No
- Recommendations for further tuning: [Suggestions]
```

---

## Phase 7: Rollback and Summary

### 7.1 Rollback Application Optimization

**If application optimization causes issues, rollback to previous configuration**:

```bash
# Restore application configuration
scp ${APP_BACKUP_DIR}/app.conf.backup ${username}@${ip}:/path/to/app.conf

# Restart application
ssh ${username}@${ip} "systemctl restart <app>"

# Verify application
ssh ${username}@${ip} "systemctl status <app>"

# Test application
[Run application-specific test]
```

### 7.2 Application Optimization Summary

**Document all application optimizations and their effectiveness**:

```markdown
### Application Optimization Summary

**Optimized Applications**:

| Application | Optimizations Applied | Performance Impact | Status |
|-------------|----------------------|-------------------|--------|
| MySQL | 3 optimizations | +40% QPS | ✓ Effective |
| Redis | 2 optimizations | +25% throughput | ✓ Effective |
| Nginx | 1 optimization | +15% response time | ✓ Effective |

**Total Applications Optimized**: [N]
**Total Application Optimizations**: [N]
**Effective Optimizations**: [N]
**Rolled Back Optimizations**: [N]

**Application Configuration Changes**:
- [App 1]: [Summary of changes]
- [App 2]: [Summary of changes]

**Application Performance Improvements**:
- [App 1]: [Summary of improvements]
- [App 2]: [Summary of improvements]

**Application Backup Locations**: ${APP_BACKUP_DIR}/
**Rollback Available**: Yes - Per-application rollback scripts
```

---

## Scope Clarification

**This skill (application-optimization) focuses on application-level optimizations ONLY:**

| Included (Application-Level) | Excluded (OS-Level) |
|-----------------------------|---------------------|
| MySQL/MariaDB configuration | Kernel parameters |
| Redis/Memcached configuration | I/O scheduler tuning |
| PostgreSQL configuration | CPU governor |
| Nginx/Apache configuration | Memory management (hugepages) |
| Kafka broker tuning | Network stack tuning |
| MongoDB configuration | Filesystem mount options |
| Java/JVM tuning | Process scheduling |
| Go runtime tuning | cgroups/namespaces |

**For OS-level optimizations, use the `os-performance-optimization` skill instead.**

---

## Operational Notes

**CRITICAL REQUIREMENTS**:
1. **Always backup before modifying**: Never change application configuration without backup
2. **Test configuration syntax**: Validate config before restarting service
3. **Graceful restart**: Prefer reload over restart when possible
4. **Monitor after changes**: Watch application logs and metrics
5. **Rollback if issues**: Don't hesitate to rollback problematic changes
6. **Benchmark before/after**: Establish baseline for each optimization
7. **Ask user confirmation**: Any service restart needs explicit confirmation

**Application Detection**:
- Always detect running applications first
- Check both processes and listening ports
- Verify application version for compatibility

**Configuration Safety**:
- Display current vs proposed values before applying
- Validate configuration syntax before applying
- Test rollback procedures before finalizing
- Keep backup of working configuration

**Communication with User**:
- Present options clearly with trade-offs
- Explain risk levels for each optimization
- Ask for confirmation at critical steps (service restart)
- Report results concisely with metrics

**Rollback Support**:
- Always maintain ability to restore original configuration
- Provide clear rollback instructions
- Test rollback after each optimization (if selected)
- Document rollback location and procedure
