# Top-Down Bottleneck Analysis - Application Scenarios

This directory contains application-specific workload analysis scenarios for Phase 3 of the top-down-bottleneck skill.

## IMPORTANT:
**Command execution**: all commands for client should be executed via `ssh`, considering the limits of ssh, allow converting commands to bash script and scp to client and execute if needed. ALL DESTRUCTIVE COMMAND SHOULD REQUEST USER'S COMIRMATION.

Each scenario file includes this requirement in its header. Apply this rule consistently across all scenarios.

## Available Scenarios

| Application | Skill File | Description |
|------------|------------|-------------|
| MySQL/MariaDB | [mysql.md](mysql.md) | Database performance: QPS, slow queries, InnoDB metrics, replication lag, lock contention |
| Redis | [redis.md](redis.md) | Cache performance: ops/sec, memory usage, hit rate, eviction, slowlog |
| Kafka | [kafka.md](kafka.md) | Message queue: throughput, latency, consumer lag, broker metrics |
| Nginx | [nginx.md](nginx.md) | Web server: request rate, response time, upstream status, SSL metrics |
| PostgreSQL | [postgres.md](postgres.md) | Database performance: query latency, connection pool, vacuum status, WAL metrics |
| MongoDB | [mongodb.md](mongodb.md) | NoSQL database: opcounters, page faults, connections, index usage |
| Java Application | [java.md](java.md) | JVM analysis: GC pauses, heap usage, thread states, JIT compilation |
| Go Application | [golang.md](golang.md) | Go runtime: goroutines, GC stats, heap allocation, syscalls |

## Usage

1. Detect running application:
```bash
ps aux | grep -E "mysqld|redis-server|kafka|nginx|postgres|mongod|java|go"
ss -tlnp | grep -E "3306|6379|9092|80|5432|27017"
```

2. Load scenario skill:
```bash
Read the scenario skill file from references/scenarios/<app>.md
```

3. Execute metrics collection commands from the scenario file

4. Correlate with system-level data from Phase 2

## Adding New Scenarios

To add a new application scenario:

1. Create a new .md file in this directory
2. Include the following frontmatter:
```yaml
---
name: <app-name>-workload
description: Brief description of the application and analysis scope
---
```

3. Structure the content with:
   - Application Detection section
   - Key Metrics Collection section
   - Bottleneck Identification table
   - Diagnostic Commands section
   - Advanced Tools section
   - Common Bottleneck Patterns section
   - Output Template

4. Update the table above in this README

## Scenario File Structure

Each scenario file should follow this structure:

```markdown
---
name: <app>-workload
description: <description>
---

# <app>-workload — <App> Performance Analysis

**Application Detection**:
<Commands to detect the application>

---

## Key Metrics Collection

<Sections for different metric categories>

---

## Bottleneck Identification

| Category | Key Metrics | Thresholds | Collection |
|----------|-------------|------------|------------|
| ... | ... | ... | ... |

---

## Diagnostic Commands

<Commands for deep-dive analysis>

---

## Advanced Tools

<Optional: Advanced diagnostic tools>

---

## Common Bottleneck Patterns

<List of common performance issues>

---

## Output Template

```markdown
## <App> Workload Analysis

### ... sections ...

### Top Bottlenecks
| Component | Issue | Evidence | Impact |
|-----------|-------|----------|--------|
```
```

## Notes

- All thresholds should be evidence-based and configurable
- Commands should work on both local and remote (OpenTunex) environments
- Include both quick checks and deep-dive diagnostics
- Maintain consistency across scenario files for ease of use
