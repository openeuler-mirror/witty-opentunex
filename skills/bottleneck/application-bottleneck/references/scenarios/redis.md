---
name: redis-workload
description: Redis workload analysis: operations/sec, memory usage, hit rate, eviction, slowlog. Use for cache performance troubleshooting.
---

# redis-workload — Redis Performance Analysis

**Command execution**: all commands for client should be executed via `ssh`, considering the limits of ssh, allow converting commands to bash script and scp to client and execute if needed. ALL DESTRUCTIVE COMMAND SHOULD REQUEST USER'S COMIRMATION.

**Application Detection**:
```bash
ps aux | grep redis-server
ss -tlnp | grep -E "6379"
redis-cli --version
redis-cli INFO server
```

---

## Key Metrics Collection

### Connection and Operations
```bash
# Connection stats
redis-cli INFO clients | grep -E "connected_clients|blocked_clients|rejected_connections"
# Operation rate
redis-cli INFO stats | grep -E "total_connections_received|total_commands_processed|instantaneous_ops_per_sec"
# Key indicators: ops/sec declining, rejected_connections > 0, blocked_clients > 0
```

### Memory Usage
```bash
# Memory overview
redis-cli INFO memory | grep -E "used_memory|used_memory_peak|used_memory_dataset|used_memory_perc"
# Memory fragmentation
redis-cli INFO memory | grep -E "mem_fragmentation_ratio"
# Key indicators: used_memory > maxmemory * 0.8, fragmentation_ratio > 1.5
# Eviction status
redis-cli INFO stats | grep -E "evicted_keys|expired_keys"
# Key indicators: evicted_keys > 1000/min indicates memory pressure
```

### Cache Performance
```bash
# Hit rate
redis-cli INFO stats | grep -E "keyspace_hits|keyspace_misses"
# Calculate hit rate: hits / (hits + misses)
# Key indicators: hit rate < 80% indicates cache ineffective
# Key statistics
redis-cli INFO stats | grep -E "total_keys|expires"
redis-cli INFO keyspace
# Key indicators: high key count approaching maxmemory-policy limit
```

### Slow Operations
```bash
# Slowlog
redis-cli SLOWLOG GET 50
redis-cli SLOWLOG LEN
redis-cli CONFIG GET slowlog-log-slower-than
# Key indicators: slowlog entries > 10, command latency > 10ms
# Latency monitoring
redis-cli LATENCY LATEST
redis-cli LATENCY HISTORY
# Key indicators: latency spikes > 100ms
```

### Persistence and Replication
```bash
# RDB status
redis-cli INFO persistence | grep -E "rdb_last_cow_size|rdb_changes_since_last_save|rdb_last_bgsave_time_sec"
# AOF status
redis-cli INFO persistence | grep -E "aof_enabled|aof_rewrite_in_progress|aof_last_cow_size"
# Replication status
redis-cli INFO replication | grep -E "role|connected_slaves|master_link_status|master_last_io_seconds_ago"
# Key indicators: replication lag > 5s, master_link_status: down, bgsave failure
```

---

## Bottleneck Identification

| Category | Key Metrics | Thresholds | Collection |
|----------|-------------|------------|------------|
| Memory Pressure | used_memory/maxmemory, evicted_keys | > 80%, > 1000/min | INFO memory, stats |
| Cache Ineffectiveness | Hit rate | < 80% | INFO stats |
| Slow Operations | Slowlog count/latency | > 10 entries, > 10ms | SLOWLOG |
| Connection Issues | rejected_connections, blocked_clients | > 0 | INFO clients |
| Persistence I/O | rdb_last_bgsave_time, cow_size | > 30s, growing | INFO persistence |
| Network Latency | master_link_status, last_io | down, > 5s | INFO replication |

---

## Diagnostic Commands

```bash
# Full INFO output
redis-cli INFO > /tmp/redis_info.txt
# Memory breakdown by key pattern
redis-cli --bigkeys
redis-cli --memkeys
# Monitor commands (use with caution in production)
redis-cli MONITOR | head -100
# Client list
redis-cli CLIENT LIST
# Latency spike analysis
redis-cli LATENCY DOCTOR
# Check specific key info
redis-cli OBJECT encoding <key>
redis-cli TTL <key>
```

---

## Advanced Tools

```bash
# redis-cli advanced analysis
redis-cli --latency-history 30
redis-cli --stat
redis-cli --scan --pattern "*" --count 1000
# Check cluster status (if in cluster mode)
redis-cli --cluster info
redis-cli --cluster nodes
```

---

## Common Bottleneck Patterns

1. **Memory exhaustion**: used_memory approaching maxmemory, high evicted_keys, fragmentation_ratio > 2.0
2. **Cache miss storm**: Low hit rate, high miss count, high ops/sec on cache misses
3. **Slow operations**: Slowlog populated with large operations (O(N), DEL large key, FLUSH*)
4. **Persistence I/O**: High rdb_last_bgsave_time_sec, large cow_size, AOF rewrite lag
5. **Connection pressure**: rejected_connections increasing, high blocked_clients
6. **Network latency**: replication lag, master_link_status issues

---

## Output Template

```markdown
## Redis Workload Analysis

### Connection Status
- Connected clients: X
- Blocked clients: X
- Rejected connections: X

### Operations
- Ops/sec: X (avg over last minute)
- Total commands: X since startup
- Instantaneous ops/sec: X

### Memory
- Used memory: X bytes (X% of maxmemory)
- Memory fragmentation ratio: X
- Evicted keys: X (X/min)
- Expired keys: X (X/min)

### Cache Performance
- Hit rate: X% (hits: X, misses: X)
- Total keys: X
- Keys with TTL: X

### Slow Operations
- Slowlog entries: X
- Average slow query latency: Xms
- Top slow operations: [list]

### Replication/Persistence
- RDB last save: X seconds ago
- AOF enabled: yes/no
- Replication status: [if applicable]

### Top Bottlenecks
| Component | Issue | Evidence | Impact |
|-----------|-------|----------|--------|
```
