---
name: redis-optimization
description: Redis performance optimization with memory management, persistence tuning, clustering, and configuration management.
---

# Redis Performance Optimization

This skill provides comprehensive Redis performance optimization based on system-level bottleneck analysis and application-specific metrics.

---

## Pre-requisites

- Redis server installed and running
- Sufficient memory for configuration changes
- Backup of current configuration
- Monitoring tools installed (optional): redis-cli, redis-benchmark

---

## Configuration File Detection

**Common Redis Configuration Paths**:

| Path | Distribution | Notes |
|------|---------------|--------|
| /etc/redis/redis.conf | Debian/Ubuntu | Standard location |
| /etc/redis.conf | RHEL/CentOS | Standard location |
| /usr/local/etc/redis.conf | Source install | Custom install |
| /etc/redis/redis-*.conf | Docker | Container-based |

**Detection Commands**:

```bash
# Detect Redis configuration file
for path in /etc/redis/redis.conf /etc/redis.conf /usr/local/etc/redis.conf; do
  if [ -f "$path" ]; then
    echo "Found Redis config: $path"
  fi
done

# Check Redis version and installation type
redis-server --version
redis-cli --version

# Check Redis data directory
redis-cli CONFIG GET dir

# Check running Redis processes
ps aux | grep redis-server
```

---

## Configuration Backup

```bash
# Backup Redis configuration
BACKUP_DIR="/opt/optimization-backup/redis_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup configuration files
cp /etc/redis/redis.conf $BACKUP_DIR/redis.conf.backup
cp /etc/redis.conf $BACKUP_DIR/redis.conf.backup 2>/dev/null || true

# Backup current configuration
redis-cli CONFIG GET * > $BACKUP_DIR/redis_config.txt

# Create backup manifest
cat > $BACKUP_DIR/backup_manifest.txt << EOF
Redis Backup
Date: $(date)
Redis Version: $(redis-server --version)
Configuration Files:
  - redis.conf
Variables: redis_config.txt
EOF
```

---

## Bottleneck Analysis

Based on system-level bottleneck analysis, identify Redis-specific bottlenecks:

### Memory Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Eviction active | High eviction rate, expired keys | Critical | Adjust maxmemory, eviction policy |
| Memory fragmentation | High fragmentation ratio | High | Enable active defrag, tune hash-max-ziplist |
| Memory exhaustion | OOM errors, out of memory | Critical | Increase maxmemory, add replicas |
| Large key values | High memory per key | Medium | Use data structures efficiently |

### Persistence Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Slow RDB saves | Long save duration, fork blocking | High | Tune save parameters, use AOF |
| AOF rewrite issues | Long rewrite time, large AOF file | High | Tune auto-aof-rewrite, use fsync policy |
| Fork blocking | Fork blocks operations | High | Reduce dataset size, disable THP |
| Disk I/O bottleneck | High disk usage during save | High | Use SSD, tune appendonly |

### Network Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Connection exhaustion | Max clients reached | High | Increase maxclients |
| High latency | Network round-trip time | Medium | Use pipelining, connection pool |
| Bandwidth saturation | High network throughput | Medium | Use replicas for reads |

### CPU Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| High CPU usage | Redis CPU > 80% | High | Optimize commands, use data structures efficiently |
| Expensive operations | Slow commands, long execution | High | Avoid O(N) operations, use SCAN |
| Thread contention | High context switches | Medium | Adjust thread settings |

---

## Optimization Recommendations

### 1. Memory Management Optimization

**Objective**: Optimize Redis memory usage and eviction policy.

**Current Value Check**:
```bash
redis-cli CONFIG GET maxmemory
redis-cli CONFIG GET maxmemory-policy
redis-cli INFO memory | grep used_memory
redis-cli INFO memory | grep used_memory_peak
redis-cli INFO stats | grep evicted_keys
```

**Recommended Configuration**:
```ini
# Maximum memory (50-80% of available RAM)
maxmemory 12gb

# Eviction policy (allkeys-lru, volatile-lru, volatile-ttl, etc.)
# allkeys-lru: Evict least recently used keys
# volatile-lru: Evict least recently used keys with TTL
# allkeys-random: Evict random keys
maxmemory-policy allkeys-lru

# Sample frequency for eviction (10-100)
# Higher = more accurate eviction, more CPU
hz 10

# Active defragmentation (Redis 4.0+)
activedefrag yes
active-defrag-cycle-min 1
active-defrag-cycle-max 25
active-defrag-threshold-lower 10
active-defrag-threshold-upper 100
```

**Verification**:
```bash
# Check memory usage
redis-cli INFO memory | grep used_memory_human

# Check memory fragmentation ratio
redis-cli INFO memory | grep mem_fragmentation_ratio
# Target: < 1.5

# Check eviction rate
redis-cli INFO stats | grep evicted_keys
```

**Risk**: Medium - May cause key eviction if too aggressive

**Expected Impact**: 20-40% reduction in memory usage, improved hit ratio

---

### 2. Persistence Optimization

**Objective**: Optimize Redis persistence for performance and durability.

**Current Value Check**:
```bash
redis-cli CONFIG GET save
redis-cli CONFIG GET appendonly
redis-cli CONFIG GET appendfsync
redis-cli CONFIG GET no-appendfsync-on-rewrite
redis-cli INFO persistence
```

**Recommended Configuration**:

**Option A: RDB + AOF (Recommended for production)**
```ini
# RDB persistence (snapshots)
# Format: save <seconds> <changes>
save 900 1    # Save after 15 min if 1+ key changes
save 300 10   # Save after 5 min if 10+ key changes
save 60 10000  # Save after 1 min if 10000+ key changes

# RDB compression (yes/no)
rdbcompression yes

# RDB checksum (yes/no)
rdbchecksum yes

# AOF persistence (append-only log)
appendonly yes
appendfilename "appendonly.aof"

# AOF fsync policy
# always: Sync on every write (safest, slowest)
# everysec: Sync every second (good balance)
# no: Let OS sync (fastest, least safe)
appendfsync everysec

# AOF rewrite policy
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Don't fsync during AOF rewrite
no-appendfsync-on-rewrite yes

# AOF load truncated file
aof-load-truncated yes
```

**Option B: RDB only (Faster, less durable)**
```ini
# RDB persistence only
save 900 1
save 300 10
save 60 10000

# Disable AOF
appendonly no
```

**Option C: AOF only (Most durable)**
```ini
# Disable RDB
save ""

# Enable AOF
appendonly yes
appendfsync everysec

# AOF rewrite every 1 hour or 100% size increase
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
```

**Verification**:
```bash
# Check persistence status
redis-cli INFO persistence

# Check last save time
redis-cli INFO persistence | grep rdb_last_save_time

# Check AOF size
ls -lh /var/lib/redis/appendonly.aof
```

**Risk**: High - AOF rewrite can cause blocking

**Expected Impact**: 30-50% reduction in save blocking, improved durability

---

### 3. Network Optimization

**Objective**: Optimize Redis network settings for better performance.

**Current Value Check**:
```bash
redis-cli CONFIG GET bind
redis-cli CONFIG GET port
redis-cli CONFIG GET maxclients
redis-cli CONFIG GET timeout
redis-cli CONFIG GET tcp-keepalive
redis-cli INFO clients | grep connected_clients
```

**Recommended Configuration**:
```ini
# Network binding
# bind 127.0.0.1  # Local only
bind 0.0.0.0  # All interfaces

# Network port
port 6379

# Maximum clients (10000 for high traffic)
maxclients 10000

# Client timeout (0 = no timeout)
timeout 0

# TCP keepalive (300 seconds)
tcp-keepalive 300

# TCP backlog (511-1024)
tcp-backlog 511

# TCP listen backlog (somaxconn)
# Linux kernel: /proc/sys/net/core/somaxconn
# Redis: redis.conf tcp-backlog
```

**Verification**:
```bash
# Check connected clients
redis-cli INFO clients | grep connected_clients

# Check rejected connections
redis-cli INFO stats | grep rejected_connections

# Check network latency
redis-cli --latency
redis-cli --latency-history
```

**Risk**: Low-Medium - Increased memory usage per connection

**Expected Impact**: 10-20% improvement in network performance

---

### 4. Data Structure Optimization

**Objective**: Optimize Redis data structures for memory efficiency.

**Current Value Check**:
```bash
redis-cli CONFIG GET hash-max-ziplist-entries
redis-cli CONFIG GET hash-max-ziplist-value
redis-cli CONFIG GET list-max-ziplist-size
redis-cli CONFIG GET set-max-intset-entries
redis-cli CONFIG GET zset-max-ziplist-entries
redis-cli CONFIG GET zset-max-ziplist-value
redis-cli INFO memory | grep used_memory_dataset
```

**Recommended Configuration**:
```ini
# Hash optimization (use ziplist for small hashes)
hash-max-ziplist-entries 512
hash-max-ziplist-value 64

# List optimization (use ziplist for small lists)
list-max-ziplist-size -2
# -2: 8KB, -1: 4KB, 0: Disabled

# Set optimization (use intset for small integer sets)
set-max-intset-entries 512

# Sorted set optimization (use ziplist for small sorted sets)
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
```

**Verification**:
```bash
# Check memory usage
redis-cli INFO memory | grep used_memory_dataset

# Check data structure efficiency
redis-cli MEMORY USAGE <key>
```

**Risk**: Low

**Expected Impact**: 20-30% reduction in memory usage for small data structures

---

### 5. Replication Optimization

**Objective**: Optimize Redis replication for better performance.

**Current Value Check**:
```bash
redis-cli CONFIG GET repl-diskless-sync
redis-cli CONFIG GET repl-backlog-size
redis-cli CONFIG GET repl-timeout
redis-cli INFO replication
```

**Recommended Configuration**:
```ini
# Diskless replication (replicate in RAM without saving to disk)
repl-diskless-sync yes

# Replication backlog size (for partial resync)
repl-backlog-size 256mb

# Replication timeout (seconds)
repl-timeout 60

# Disable TCP_NODELAY for replication
repl-disable-tcp-nodelay no

# Replication backlog TTL (seconds)
repl-backlog-ttl 3600

# Priority for replication (0-100, lower is higher priority)
replica-priority 100

# Replication read-only
replica-read-only yes
```

**Verification**:
```bash
# Check replication status
redis-cli INFO replication

# Check replication lag
redis-cli INFO replication | grep master_link_down_since_seconds
```

**Risk**: Medium

**Expected Impact**: 20-40% reduction in replication lag

---

### 6. Cluster Optimization

**Objective**: Optimize Redis Cluster for better performance and reliability.

**Current Value Check**:
```bash
redis-cli CONFIG GET cluster-enabled
redis-cli CONFIG GET cluster-node-timeout
redis-cli INFO cluster
```

**Recommended Configuration**:
```ini
# Enable Redis Cluster
cluster-enabled yes

# Cluster configuration file
cluster-config-file nodes.conf

# Cluster node timeout (milliseconds)
cluster-node-timeout 15000

# Cluster migration barrier (1 = enabled)
cluster-migration-barrier 1

# Cluster replica validity factor
cluster-replica-validity-factor 10

# Cluster minimum replicas
cluster-migration-barrier 1

# Cluster require full coverage
cluster-require-full-coverage yes
```

**Verification**:
```bash
# Check cluster status
redis-cli CLUSTER INFO

# Check cluster nodes
redis-cli CLUSTER NODES
```

**Risk**: High - Requires careful cluster planning

**Expected Impact**: Improved scalability and reliability

---

### 7. Slow Log Optimization

**Objective**: Enable slow log for performance analysis.

**Recommended Configuration**:
```ini
# Slow log
slowlog-log-slower-than 10000  # Log commands slower than 10ms
slowlog-max-len 128  # Keep last 128 slow commands
```

**Verification**:
```bash
# Check slow log
redis-cli SLOWLOG GET 10

# Check slow log length
redis-cli SLOWLOG LEN
```

**Risk**: Low - Slight memory overhead for slow log

**Expected Impact**: Enables identification of performance bottlenecks

---

### 8. Lua Script Optimization

**Objective**: Optimize Lua script execution for better performance.

**Recommended Configuration**:
```ini
# Lua script time limit (milliseconds)
lua-time-limit 5000

# Lua script replication (yes/no)
lua-replicate-commands yes
```

**Verification**:
```bash
# Test Lua script
redis-cli EVAL "return redis.call('KEYS')" 0

# Check Lua script performance
redis-cli INFO stats | grep total_commands_processed
```

**Risk**: Medium - Long-running scripts can block Redis

**Expected Impact**: Better control over script execution

---

## Optimization Procedure

### Step 1: Pre-Optimization Baseline

```bash
# Collect current performance metrics
redis-cli INFO > /tmp/redis_info_before.txt
redis-cli CONFIG GET * > /tmp/redis_config_before.txt

# Collect memory statistics
redis-cli INFO memory > /tmp/redis_memory_before.txt

# Collect replication statistics
redis-cli INFO replication > /tmp/redis_replication_before.txt

# Record timestamp
date > /tmp/redis_baseline_timestamp.txt
```

### Step 2: Apply Configuration Changes

```bash
# Create optimized configuration
cat > /etc/redis/redis.conf << EOF
# Network
bind 0.0.0.0
port 6379
maxclients 10000
timeout 0
tcp-keepalive 300
tcp-backlog 511

# Memory
maxmemory 12gb
maxmemory-policy allkeys-lru
hz 10

# Persistence
save 900 1
save 300 10
save 60 10000
appendonly yes
appendfsync everysec
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Data structures
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64

# Slow log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Active defrag (Redis 4.0+)
activedefrag yes
active-defrag-cycle-min 1
active-defrag-cycle-max 25
active-defrag-threshold-lower 10
active-defrag-threshold-upper 100
EOF

# Test configuration
redis-server /etc/redis/redis.conf --test-memory 1024

# Restart Redis
systemctl restart redis

# Verify Redis started
systemctl status redis
redis-cli PING
```

### Step 3: Post-Optimization Verification

```bash
# Collect new performance metrics
redis-cli INFO > /tmp/redis_info_after.txt
redis-cli CONFIG GET * > /tmp/redis_config_after.txt

# Collect memory statistics
redis-cli INFO memory > /tmp/redis_memory_after.txt

# Collect replication statistics
redis-cli INFO replication > /tmp/redis_replication_after.txt

# Verify configuration applied
redis-cli CONFIG GET maxmemory
redis-cli CONFIG GET maxmemory-policy
```

### Step 4: Performance Comparison

```bash
# Compare memory usage
redis-cli INFO memory | grep used_memory_human

# Check memory fragmentation ratio
redis-cli INFO memory | grep mem_fragmentation_ratio

# Check eviction rate
redis-cli INFO stats | grep evicted_keys

# Check hit ratio
redis-cli INFO stats | grep keyspace_hits
redis-cli INFO stats | grep keyspace_misses
redis-cli -e "INFO stats" | awk -F: '/keyspace_hits/{hits=$2} /keyspace_misses/{misses=$2} END {print "Hit ratio: " (hits/(hits+misses))*100 "%"}"
```

---

## Monitoring and Maintenance

### Key Metrics to Monitor

```bash
# Memory usage
redis-cli INFO memory | grep used_memory_human

# Memory fragmentation
redis-cli INFO memory | grep mem_fragmentation_ratio

# Eviction rate
redis-cli INFO stats | grep evicted_keys

# Hit ratio
redis-cli INFO stats | grep keyspace_hits
redis-cli INFO stats | grep keyspace_misses

# Connections
redis-cli INFO clients | grep connected_clients

# Commands per second
redis-cli INFO stats | grep instantaneous_ops_per_sec

# Slow log
redis-cli SLOWLOG LEN
redis-cli SLOWLOG GET 10
```

### Recommended Tools

- **redis-cli**: Built-in Redis CLI
- **redis-benchmark**: Performance testing
- **RedisInsight**: Redis GUI and monitoring
- **Prometheus + Grafana**: Production monitoring

---

## Rollback Procedure

```bash
# Stop Redis
systemctl stop redis

# Restore backup configuration
cp /opt/optimization-backup/redis_*/redis.conf.backup /etc/redis/redis.conf

# Restore AOF file if needed
cp /opt/optimization-backup/redis_*/appendonly.aof.backup /var/lib/redis/appendonly.aof

# Start Redis
systemctl start redis

# Verify Redis started
systemctl status redis
redis-cli PING
```

---

## Common Issues and Solutions

### Issue 1: Redis won't start after configuration change
**Solution**: Check error log: `tail -f /var/log/redis/redis-server.log`

### Issue 2: Out of memory errors
**Solution**: Reduce `maxmemory`, enable `maxmemory-policy`, check system memory

### Issue 3: High CPU usage
**Solution**: Check for slow commands, avoid O(N) operations, optimize data structures

### Issue 4: High eviction rate
**Solution**: Increase `maxmemory`, change `maxmemory-policy`, add replicas

### Issue 5: Replication lag
**Solution**: Enable `repl-diskless-sync`, increase `repl-backlog-size`

---

## Additional Resources

- [Redis Documentation](https://redis.io/documentation)
- [Redis Best Practices](https://redis.io/topics/best-practices)
- [Redis Performance Tuning](https://redis.io/topics/admin)
