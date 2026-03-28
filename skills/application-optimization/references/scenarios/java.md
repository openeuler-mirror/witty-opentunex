---
name: java-optimization
description: Java application performance optimization with heap tuning, GC configuration, thread pooling, and JVM parameters.
---

# Java Application Performance Optimization

This skill provides comprehensive Java application performance optimization based on system-level bottleneck analysis and application-specific metrics.

---

## Pre-requisites

- Java application running (standalone, Tomcat, Spring Boot, etc.)
- Sufficient memory for configuration changes
- Backup of current configuration
- Monitoring tools installed (optional): JConsole, VisualVM, Prometheus JMX Exporter

---

## Configuration File Detection

**Common Java Application Configuration**:

| Type | Location | Notes |
|------|-----------|--------|
| JVM Args | Environment variables, startup scripts | -Xmx, -Xms, -XX options |
| Tomcat | /etc/tomcat/setenv.sh, CATALINA_OPTS | Tomcat-specific settings |
| Spring Boot | Environment variables, application.properties | Boot-specific settings |
| WildFly | /opt/wildfly/bin/standalone.conf | WildFly-specific settings |
| Docker | Dockerfile, docker-compose.yml | Container settings |

**Detection Commands**:

```bash
# Detect running Java processes
ps aux | grep java | grep -v grep

# Check Java version
java -version

# Check JVM arguments
jps -lvmv 2>/dev/null || ps aux | grep java

# Check heap usage
jstat -gc <pid> 1 5

# Check for JMX monitoring
netstat -an | grep 9999
```

---

## Configuration Backup

```bash
# Backup Java application configuration
BACKUP_DIR="/opt/optimization-backup/java_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup startup scripts
cp /etc/tomcat/setenv.sh $BACKUP_DIR/ 2>/dev/null || true
cp /opt/wildfly/bin/standalone.conf $BACKUP_DIR/ 2>/dev/null || true
cp /etc/default/tomcat* $BACKUP_DIR/ 2>/dev/null || true

# Backup JVM arguments
ps aux | grep java | grep -v grep > $BACKUP_DIR/java_processes.txt

# Backup application properties
find /opt/app -name application.properties -exec cp {} $BACKUP_DIR/ \; 2>/dev/null || true
find /opt/app -name application.yml -exec cp {} $BACKUP_DIR/ \; 2>/dev/null || true

# Create backup manifest
cat > $BACKUP_DIR/backup_manifest.txt << EOF
Java Application Backup
Date: $(date)
Java Version: $(java -version 2>&1 | head -1)
Configuration Files:
  - setenv.sh
  - standalone.conf
  - application.properties
  - application.yml
Processes: java_processes.txt
EOF
```

---

## Bottleneck Analysis

Based on system-level bottleneck analysis, identify Java-specific bottlenecks:

### Memory Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| OutOfMemoryError | OOM errors in logs | Critical | Increase heap size, optimize memory usage |
| Frequent GC | High GC frequency | Critical | Tune GC parameters, increase heap size |
| Long GC pauses | Long GC pause times | High | Use appropriate GC algorithm, tune GC parameters |
| Memory leaks | Continuous memory growth | Critical | Analyze heap dumps, fix leaks |
| Direct buffer memory | OutOfMemoryError: Direct buffer memory | Medium | Increase MaxDirectMemorySize |

### CPU Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| High CPU usage | High CPU utilization | Critical | Optimize code, use caching, tune thread pool |
| Thread contention | High lock wait time | High | Reduce lock contention, use concurrent data structures |
| Excessive context switches | High context switch rate | Medium | Reduce thread count, use async I/O |
| CPU-bound operations | High CPU in specific operations | High | Optimize algorithms, use native code |

### Thread Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Too many threads | High thread count, thread contention | Critical | Reduce thread pool size, use async processing |
| Thread deadlock | Deadlock detected | Critical | Fix deadlock issues |
| Thread starvation | Some threads never execute | Medium | Tune thread pool, use fair scheduling |
| Thread pool exhaustion | Tasks rejected | High | Increase thread pool size |

### I/O Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Slow I/O operations | Long I/O wait time | High | Use NIO, async I/O, buffer I/O |
| File descriptor limit | Too many open files error | Critical | Increase ulimit, use connection pooling |
| Network bottleneck | Slow network operations | Medium | Use connection pooling, enable TCP keepalive |
| Database connection pool exhaustion | Connection wait timeout | Critical | Increase pool size, optimize queries |

---

## Optimization Recommendations

### 1. Heap Size Optimization

**Objective**: Optimize JVM heap size for better memory management.

**Current Value Check**:
```bash
# Check current heap size
jstat -gc <pid> | head -1
jmap -heap <pid> 2>/dev/null | grep -E "Heap Configuration|MaxHeapSize"

# Check heap usage
jstat -gc <pid> 1 5
```

**Recommended Configuration**:

**Option A: Fixed Heap Size**
```bash
# Set fixed heap size
-Xms4g -Xmx4g

# Explanation:
# -Xms: Initial heap size
# -Xmx: Maximum heap size
# Rule: Set Xms = Xmx to avoid runtime resizing
```

**Option B: Container-Aware Heap Size**
```bash
# For Docker containers, use container-aware options
-XX:+UnlockExperimentalVMOptions
-XX:+UseContainerSupport
-XX:MaxRAMPercentage=75.0
-XX:InitialRAMPercentage=75.0

# Alternative: Use cgroup limits
-Xms$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)k
-Xmx$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)k
```

**Calculation**:
```
Heap Size = Total RAM * 0.6-0.8 (for dedicated application)
Heap Size = Total RAM * 0.4-0.6 (for shared server)

Example for 16GB RAM:
- Dedicated: 16GB * 0.75 = 12GB heap
- Shared: 16GB * 0.5 = 8GB heap
```

**Verification**:
```bash
# Verify heap size
jmap -heap <pid> | grep -E "MaxHeapSize|Heap Configuration"

# Monitor heap usage
jstat -gc <pid> 1 10

# Check for OOM errors
tail -f /var/log/application.log | grep OutOfMemoryError
```

**Risk**: Medium - Too large heap causes long GC pauses

**Expected Impact**: 30-50% reduction in GC frequency

---

### 2. Garbage Collection Optimization

**Objective**: Optimize GC algorithm and parameters for better performance.

**Current Value Check**:
```bash
# Check current GC algorithm
jinfo -flags <pid> | grep -i "Use.*GC"

# Check GC statistics
jstat -gc <pid> 1 5
```

**Recommended Configuration**:

**Option A: G1GC (Recommended for large heaps)**
```bash
# Use G1 Garbage Collector (Java 9+)
-XX:+UseG1GC

# G1GC parameters
-XX:MaxGCPauseMillis=200
-XX:G1HeapRegionSize=16m
-XX:InitiatingHeapOccupancyPercent=45
-XX:+ParallelRefProcEnabled
-XX:+StringDeduplication

# Explanation:
# MaxGCPauseMillis: Target max GC pause time (ms)
# G1HeapRegionSize: Size of G1 regions (16m recommended)
# InitiatingHeapOccupancyPercent: Heap occupancy threshold
```

**Option B: ZGC (Java 11+, low latency)**
```bash
# Use Z Garbage Collector (Java 11+)
-XX:+UnlockExperimentalVMOptions
-XX:+UseZGC

# ZGC parameters
-XX:ConcGCThreads=2
-XX:ParallelGCThreads=6
```

**Option C: Shenandoah (Java 12+, low latency)**
```bash
# Use Shenandoah GC (Java 12+)
-XX:+UseShenandoahGC

# Shenandoah parameters
-XX:ShenandoahGCHeuristics=compact
-XX:ShenandoahGCMode=generational
```

**Option D: CMS (Java 8 and earlier, deprecated)**
```bash
# Use CMS Garbage Collector (Java 8)
-XX:+UseConcMarkSweepGC
-XX:+CMSParallelRemarkEnabled
-XX:+CMSScavengeBeforeRemark
-XX:+CMSClassUnloadingEnabled
-XX:+CMSPermGenSweepingEnabled
-XX:CMSInitiatingOccupancyFraction=70
```

**Verification**:
```bash
# Verify GC algorithm
jinfo -flags <pid> | grep -i "Use.*GC"

# Monitor GC performance
jstat -gc <pid> 1 10
# Focus on:
# - YGC (Young GC count)
# - FGC (Full GC count)
# - YGCT (Young GC time)
# - FGCT (Full GC time)
# - GCT (Total GC time)
```

**Risk**: High - GC changes significantly impact performance

**Expected Impact**: 20-40% reduction in GC pause time

---

### 3. Metaspace Optimization

**Objective**: Optimize metaspace size for better class loading.

**Current Value Check**:
```bash
# Check metaspace usage
jstat -gc <pid> | grep -E "M|MC|MU"

# Check class loading
jstat -gc <pid> | grep -E "CCS|CCU"
```

**Recommended Configuration**:
```bash
# Metaspace size (for Java 8+)
-XX:MetaspaceSize=512m
-XX:MaxMetaspaceSize=1g

# Compressed class space size (for Java 8)
-XX:CompressedClassSpaceSize=256m

# Explanation:
# Metaspace: Stores class metadata (grows dynamically)
# MaxMetaspaceSize: Maximum metaspace size
# CompressedClassSpaceSize: Compressed class pointer space
```

**Verification**:
```bash
# Verify metaspace size
jinfo -flags <pid> | grep -E "MetaspaceSize|MaxMetaspaceSize"

# Monitor metaspace usage
jstat -gc <pid> 1 10 | grep -E "M|MC|MU"
```

**Risk**: Low

**Expected Impact**: Prevents OutOfMemoryError: Metaspace

---

### 4. Thread Pool Optimization

**Objective**: Optimize thread pool settings for better performance.

**Current Value Check**:
```bash
# Check thread count
jstack <pid> | grep "java.lang.Thread" | wc -l

# Check thread pool configuration
jinfo -flags <pid> | grep -i "pool|thread"
```

**Recommended Configuration**:

**For Java Thread Pool**:
```java
// Use fixed thread pool for CPU-bound tasks
ExecutorService executor = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors());

// Use cached thread pool for I/O-bound tasks
ExecutorService executor = Executors.newCachedThreadPool();

// Custom thread pool with proper configuration
ThreadPoolExecutor executor = new ThreadPoolExecutor(
    corePoolSize,      // Core pool size
    maxPoolSize,       // Maximum pool size
    keepAliveTime,     // Idle thread keep-alive time
    TimeUnit.SECONDS,
    new LinkedBlockingQueue<>(queueCapacity),
    new ThreadPoolExecutor.CallerRunsPolicy()
);
```

**For Tomcat Thread Pool**:
```xml
<!-- server.xml -->
<Connector port="8080" protocol="HTTP/1.1"
           connectionTimeout="20000"
           redirectPort="8443"
           maxThreads="200"
           acceptCount="100"
           minSpareThreads="10"
           maxSpareThreads="100"
           executor="tomcatThreadPool" />
```

**For Spring Boot Thread Pool**:
```properties
# application.properties
spring.task.execution.pool.core-size=10
spring.task.execution.pool.max-size=50
spring.task.execution.pool.queue-capacity=1000
spring.task.execution.thread-name-prefix=myapp-
```

**Verification**:
```bash
# Check thread count
jstack <pid> | grep "java.lang.Thread" | wc -l

# Monitor thread pool
jinfo -flags <pid> | grep -i "pool|thread"

# Check thread states
jstack <pid> | grep -E "RUNNABLE|BLOCKED|WAITING"
```

**Risk**: Medium - Too many threads cause context switch overhead

**Expected Impact**: 20-30% improvement in thread management

---

### 5. Direct Memory Optimization

**Objective**: Optimize direct memory usage for better I/O performance.

**Current Value Check**:
```bash
# Check direct memory usage
jcmd <pid> VM.native_memory summary
```

**Recommended Configuration**:
```bash
# Direct memory size (for NIO operations)
-XX:MaxDirectMemorySize=2g

# Disable explicit GC for direct memory (for performance)
-XX:+DisableExplicitGC

# Use compressed oops for 64-bit JVMs with < 32GB heap
-XX:+UseCompressedOops
```

**Verification**:
```bash
# Verify direct memory size
jinfo -flags <pid> | grep MaxDirectMemorySize

# Monitor direct memory usage
jcmd <pid> VM.native_memory summary
```

**Risk**: Low-Medium

**Expected Impact**: Improved NIO performance

---

### 6. JMX Monitoring Optimization

**Objective**: Enable JMX monitoring for performance tracking.

**Recommended Configuration**:
```bash
# Enable JMX monitoring
-Dcom.sun.management.jmxremote
-Dcom.sun.management.jmxremote.port=9999
-Dcom.sun.management.jmxremote.authenticate=false
-Dcom.sun.management.jmxremote.ssl=false

# Secure JMX (for production)
-Dcom.sun.management.jmxremote.authenticate=true
-Dcom.sun.management.jmxremote.password.file=/path/to/jmxremote.password
-Dcom.sun.management.jmxremote.access.file=/path/to/jmxremote.access
-Dcom.sun.management.jmxremote.ssl=true
-Djavax.net.ssl.keyStore=/path/to/keystore
-Djavax.net.ssl.keyStorePassword=password
-Djavax.net.ssl.trustStore=/path/to/truststore
-Djavax.net.ssl.trustStorePassword=password
```

**Verification**:
```bash
# Check JMX port
netstat -an | grep 9999

# Test JMX connection
jconsole localhost:9999
jvisualvm
```

**Risk**: Medium - Security risk if not properly secured

**Expected Impact**: Enables performance monitoring

---

## Optimization Procedure

### Step 1: Pre-Optimization Baseline

```bash
# Collect current performance metrics
jstat -gc <pid> 1 10 > /tmp/java_gc_before.txt
jmap -heap <pid> > /tmp/java_heap_before.txt 2>/dev/null || true
jstack <pid> > /tmp/java_threads_before.txt 2>/dev/null || true

# Record timestamp
date > /tmp/java_baseline_timestamp.txt
```

### Step 2: Apply Configuration Changes

```bash
# Create optimized JVM arguments
JAVA_OPTS="-Xms8g -Xmx8g -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:InitiatingHeapOccupancyPercent=45 -XX:MetaspaceSize=512m -XX:MaxMetaspaceSize=1g -XX:MaxDirectMemorySize=2g -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=9999 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"

# Update startup script (example for Tomcat)
cat > /etc/tomcat/setenv.sh << EOF
export JAVA_OPTS="$JAVA_OPTS"
EOF

# Restart application
systemctl restart tomcat

# Verify application started
systemctl status tomcat
curl -I http://localhost:8080/
```

### Step 3: Post-Optimization Verification

```bash
# Collect new performance metrics
jstat -gc <pid> 1 10 > /tmp/java_gc_after.txt
jmap -heap <pid> > /tmp/java_heap_after.txt 2>/dev/null || true
jstack <pid> > /tmp/java_threads_after.txt 2>/dev/null || true

# Verify configuration applied
jinfo -flags <pid> | grep -E "UseG1GC|MaxHeapSize|MaxDirectMemorySize"
```

### Step 4: Performance Comparison

```bash
# Compare GC performance
echo "=== Before ==="
cat /tmp/java_gc_before.txt | tail -10

echo "=== After ==="
cat /tmp/java_gc_after.txt | tail -10

# Compare heap usage
echo "=== Before ==="
grep -E "MaxHeapSize|used" /tmp/java_heap_before.txt | head -5

echo "=== After ==="
grep -E "MaxHeapSize|used" /tmp/java_heap_after.txt | head -5
```

---

## Monitoring and Maintenance

### Key Metrics to Monitor

```bash
# Heap usage
jstat -gc <pid> | awk '{print "Heap Used: " $3 " / " $4 " Capacity: " $5 " / " $6}'

# GC performance
jstat -gc <pid> | awk '{print "Young GC: " $9 " Old GC: " $11 " Total GC Time: " $15}'

# Thread count
jstack <pid> | grep "java.lang.Thread" | wc -l

# Direct memory usage
jcmd <pid> VM.native_memory summary | grep -A 3 "Java Heap"
```

### Recommended Tools

- **JConsole**: Built-in Java monitoring
- **VisualVM**: Java profiling and monitoring
- **JProfiler**: Advanced Java profiling
- **Prometheus JMX Exporter**: Production monitoring
- **YourKit**: Java performance analysis

---

## Rollback Procedure

```bash
# Restore backup configuration
cp /opt/optimization-backup/java_*/setenv.sh /etc/tomcat/setenv.sh 2>/dev/null || true
cp /opt/optimization-backup/java_*/standalone.conf /opt/wildfly/bin/standalone.conf 2>/dev/null || true

# Restart application
systemctl restart tomcat

# Verify application started
systemctl status tomcat
curl -I http://localhost:8080/
```

---

## Common Issues and Solutions

### Issue 1: OutOfMemoryError after heap size increase
**Solution**: Check for memory leaks, reduce heap size, analyze heap dump

### Issue 2: Long GC pauses
**Solution**: Tune GC parameters, use appropriate GC algorithm, reduce heap size

### Issue 3: Thread starvation
**Solution**: Reduce thread count, use async processing, tune thread pool

### Issue 4: Application won't start after JVM args change
**Solution**: Check error log, verify JVM arguments compatibility

---

## Additional Resources

- [JVM Documentation](https://docs.oracle.com/javase/8/docs/technotes/guides/vm/gctuning/)
- [G1GC Tuning](https://docs.oracle.com/javase/9/gctuning/g1-optimizations.html)
- [VisualVM](https://visualvm.github.io/)

