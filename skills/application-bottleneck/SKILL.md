---
name: application-bottleneck
description: Application-specific workload data collection and bottleneck analysis. Provides deep-dive analysis for MySQL, Redis, PostgreSQL, Kafka, Nginx, MongoDB, Java, and Go applications. Use after system-level bottleneck analysis (Phase 2) when root cause is unclear or application-level optimization is required.
---

# application-bottleneck — Application-Specific Workload Analysis

This skill provides application-specific performance data collection and bottleneck analysis. It should be used after system-level bottleneck analysis identifies that application internals need deeper investigation.

**Prerequisite**: Run top-down-bottleneck skill Phase 1 and Phase 2 first to identify resource pressure points and determine which applications require deep-dive analysis.

---

## Client Connection and Command Execution

Load the remote-execution skill for standardized SSH connection and command execution:

skill:remote-execution

---

## Application Scenario Skills

Load dedicated scenario skill based on detected application type. Available scenarios in `references/scenarios/`:

| Application | Scenario Skill | Key Metrics |
|-------------|----------------|-------------|
| MySQL | [scenarios/mysql.md](references/scenarios/mysql.md) | QPS, slow queries, InnoDB buffer pool, replication lag, lock waits |
| Redis | [scenarios/redis.md](references/scenarios/redis.md) | ops/sec, memory usage, hit rate, eviction rate, slowlog |
| Kafka | [scenarios/kafka.md](references/scenarios/kafka.md) | message rate, lag, request latency, consumer group lag |
| Nginx | [scenarios/nginx.md](references/scenarios/nginx.md) | requests/sec, response time, upstream status, SSL metrics |
| PostgreSQL | [scenarios/postgres.md](references/scenarios/postgres.md) | connections, query latency, WAL size, vacuum status |
| MongoDB | [scenarios/mongodb.md](references/scenarios/mongodb.md) | opcounters, page faults, connections, index usage |
| Java App | [scenarios/java.md](references/scenarios/java.md) | GC pauses, heap usage, thread states, JIT compilation |
| Go App | [scenarios/golang.md](references/scenarios/golang.md) | goroutines, GC stats, heap allocation, syscalls |

**Detection method**:
```bash
# Identify running applications
ps aux | grep -E "mysqld|redis-server|kafka|nginx|postgres|mongod|java|go"
# Check listening ports for service identification
ss -tlnp | grep -E "3306|6379|9092|80|5432|27017"
```

---

## When to Invoke Application Analysis

- System-level bottlenecks (Phase 2) identified but root cause unclear
- Need deep dive into application internals
- User specifically requests application-level analysis
- Application-specific optimization is required

---

## Execution Pattern

For each detected application:

1. **Load scenario skill**:
   ```bash
   Read the scenario skill file from references/scenarios/<app>.md
   ```

2. **Collect application metrics**:
   ```bash
   # Example: MySQL
   mysql -e "SHOW ENGINE INNODB STATUS\G"
   mysql -e "SHOW PROCESSLIST"
   mysql -e "SHOW GLOBAL STATUS LIKE 'Com_%'"
   # Use pt-summary if available
   pt-summary --host localhost --port 3306
   ```

3. **Correlate with system-level data**:
   - Map application metrics to Phase 2 findings
   - Identify if application is causing system bottlenecks
   - Determine if system constraints limit application performance

4. **Application-specific bottleneck analysis**:
   - Database: lock contention, slow queries, buffer pool pressure
   - Cache: hit ratio degradation, memory fragmentation
   - Message queue: consumer lag, producer backpressure
   - Web server: connection pool exhaustion, slow upstreams

---

## Output Template

```markdown
## Application Workload Analysis

### Detected Applications
| Application | PID | Port | Version |
|-------------|-----|------|---------|

### Application Performance Metrics
[Metric tables/charts from scenario skills]

### Application-System Correlation
[Mapping between application behavior and system resource usage]

### Application-Specific Bottlenecks
| Component | Bottleneck Type | Evidence | Impact |
|-----------|----------------|----------|--------|
```

---

## Output Template

```markdown
## Application Workload Analysis

### Detected Applications
| Application | PID | Port | Version |
|-------------|-----|------|---------|

### Application Performance Metrics
[Metric tables/charts from scenario skills]

### Application-System Correlation
[Mapping between application behavior and system resource usage]

### Application-Specific Bottlenecks
| Component | Bottleneck Type | Evidence | Impact |
|-----------|----------------|----------|--------|

## Next Steps
(Concrete actions: e.g., query optimization, connection pool tuning, cache configuration, application-level tuning)
```

---

## Operational Notes

- Execute application analysis after Phase 2 to deep-dive into detected applications
- All analysis must be specific and evidence-based; maintain rigor and professionalism
- Application scenario skills must be loaded from `references/scenarios/` directory before collecting application-specific metrics
- When delegating to sys-sniffer (Phase 1), the subagent should ALSO execute command in client via `ssh`.

(End of file - total 150 lines)
