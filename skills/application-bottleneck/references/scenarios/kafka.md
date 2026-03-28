---
name: kafka-workload
description: Kafka workload analysis- message throughput, latency, consumer lag, broker metrics. Use for message queue performance troubleshooting.
---

# kafka-workload — Kafka Performance Analysis
**Command execution**: all commands for client should be executed via `ssh`, considering the limits of ssh, allow converting commands to bash script and scp to client and execute if needed. ALL DESTRUCTIVE COMMAND SHOULD REQUEST USER'S COMIRMATION.

**Application Detection**:
```bash
ps aux | grep kafka
jps | grep -i kafka
kafka-topics.sh --list --bootstrap-server localhost:9092 2>/dev/null
kafka-broker-api-versions.sh --bootstrap-server localhost:9092 2>/dev/null
```

---

## Key Metrics Collection

### Broker Metrics (via JMX)
```bash
# Request throughput
kafka-run-class.sh kafka.tools.JmxTool --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9999/jmxrmi --object-name kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec --attributes OneMinuteRate
kafka-run-class.sh kafka.tools.JmxTool --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9999/jmxrmi --object-name kafka.server:type=BrokerTopicMetrics,name=BytesInPerSec --attributes OneMinuteRate
# Key indicators: declining throughput, message rate dropping
# Request latency
kafka-run-class.sh kafka.tools.JmxTool --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9999/jmxrmi --object-name kafka.network:type=RequestMetrics,name=RequestLatencyMs,request=Produce --attributes 99thPercentile
kafka-run-class.sh kafka.tools.JmxTool --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9999/jmxrmi --object-name kafka.network:type=RequestMetrics,name=RequestLatencyMs,request=Fetch --attributes 99thPercentile
# Key indicators: p99 latency > 100ms for Produce, > 500ms for Fetch
```

### Consumer Group Lag
```bash
# Consumer group overview
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group <group-name>
# Key indicators: LAG > 10000 messages, consumer not assigned
# Lag by topic/partition
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group <group-name> --verbose
```

### Topic and Partition Metrics
```bash
# Topic list and details
kafka-topics.sh --bootstrap-server localhost:9092 --describe
# Partition distribution
kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic <topic-name>
# Under-replicated partitions
kafka-run-class.sh kafka.tools.JmxTool --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9999/jmxrmi --object-name kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions --attributes Value
# Key indicators: UnderReplicatedPartitions > 0
```

### Log Segment and I/O Metrics
```bash
# Log flush rate
kafka-run-class.sh kafka.tools.JmxTool --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9999/jmxrmi --object-name kafka.log:type=LogFlushStats,name=LogFlushRateAndTimeMs --attributes Count
# I/O wait time
kafka-run-class.sh kafka.tools.JmxTool --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9999/jmxrmi --object-name kafka.server:type=ReplicaManager,name=IsrShrinksPerSec --attributes Count
# Key indicators: Log flush latency > 100ms, I/O saturation
```

---

## Bottleneck Identification

| Category | Key Metrics | Thresholds | Collection |
|----------|-------------|------------|------------|
| Producer Latency | RequestLatencyMs (Produce p99) | > 100ms | JMX RequestMetrics |
| Consumer Lag | LAG per consumer group | > 10000 messages | kafka-consumer-groups |
| Network I/O | BytesIn/OutPerSec, network threads | Saturation | JMX BrokerTopicMetrics |
| Disk I/O | Log flush latency, disk utilization | > 100ms, > 80% | JMX LogFlushStats |
| Replication | UnderReplicatedPartitions | > 0 | JMX ReplicaManager |
| Memory | JVM heap usage, GC pause time | > 80%, > 1000ms | JMX Memory, GC |
| Thread Pool | Network/Request thread queue | > 1000 pending | JMX ThreadPool |

---

## Diagnostic Commands

```bash
# Full JMX metrics dump
kafka-run-class.sh kafka.tools.JmxTool --jmx-url service:jmx:rmi:///jndi/rmi://localhost:9999/jmxrmi --object-name kafka.server:* --attributes OneMinuteRate,Count,Mean,99thPercentile > /tmp/kafka_jmx.txt
# Consumer group details
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --all-groups
# Topic configuration
kafka-configs.sh --bootstrap-server localhost:9092 --entity-type topics --describe
# Broker configuration
kafka-configs.sh --bootstrap-server localhost:9092 --entity-type brokers --describe
# Log segment analysis
kafka-run-class.sh kafka.tools.DumpLogSegments --files /var/kafka/data/<topic>-0/00000000000000000000.log --print-data-log
```

---

## Advanced Tools

```bash
# kafka-topics-ui (web UI)
# Kafka Manager (web UI)
# Burrow (consumer lag monitoring)
# Confluent Control Center (commercial)
# JMX console tools
jconsole
jvisualvm
```

---

## Common Bottleneck Patterns

1. **Producer backpressure**: High RequestLatencyMs, network thread queue full, BytesInPerSec declining
2. **Consumer lag**: High LAG in consumer groups, slow consumers, rebalancing issues
3. **Disk I/O saturation**: High LogFlushStats latency, disk utilization > 90%, fsync delays
4. **Replication lag**: UnderReplicatedPartitions > 0, ISR shrinking, broker network issues
5. **Memory pressure**: JVM heap usage > 85%, frequent GC, OutOfMemory errors
6. **Thread exhaustion**: Network/Request thread pool exhausted, queued requests > 1000

---

## Output Template

```markdown
## Kafka Workload Analysis

### Broker Status
- Active brokers: X
- Under-replicated partitions: X
- Controller: broker X

### Message Throughput
- Messages/sec: X
- Bytes in/sec: X MB
- Bytes out/sec: X MB

### Latency
- Producer p99 latency: Xms
- Fetch p99 latency: Xms

### Consumer Groups
| Group | Topic | Partition | Lag | Consumer |
|-------|-------|-----------|-----|----------|

### Resource Utilization
- Disk utilization: X%
- I/O wait: X%
- Network bandwidth: X Mbps
- JVM heap: X%

### Top Bottlenecks
| Component | Issue | Evidence | Impact |
|-----------|-------|----------|--------|
```

