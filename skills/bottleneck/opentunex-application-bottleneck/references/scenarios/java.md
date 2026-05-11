---
name: java-workload
description: Java application workload analysis- GC pauses, heap usage, thread states, JIT compilation. Use for JVM performance troubleshooting.
---

# java-workload — Java Application Performance Analysis

**Command execution**: all commands for client should be executed via `ssh`, considering the limits of ssh, allow converting commands to bash script and scp to client and execute if needed. ALL DESTRUCTIVE COMMAND SHOULD REQUEST USER'S COMIRMATION.

**Application Detection**:
```bash
ps aux | grep -E "java|org.apache"
jps -l
jinfo -flags <pid>
java -version
```

---

## Key Metrics Collection

### JVM Heap and Memory
```bash
# Get process ID
JAVA_PID=$(jps -l | grep <main-class> | awk '{print $1}')
# Heap usage
jstat -gc $JAVA_PID 1s 5
# Key indicators: heap usage > 80%, increasing old generation
# Metaspace usage
jstat -gc $JAVA_PID 1s 5 | grep -E "OU|MU|CCS"
# Key indicators: Metaspace approaching MetaspaceSize limit, Full GC
# Direct memory (if using Netty, NIO, etc.)
jstat -gc $JAVA_PID | awk '{print "Direct: "}'  # Need to use jcmd for details
```

### Garbage Collection
```bash
# GC statistics
jstat -gcutil $JAVA_PID 1s 5
# Key indicators: FGCT > 1s, frequent Full GC, YGCT increasing
# GC pause time details
jstat -gc $JAVA_PID 1s 10
jstat -gccapacity $JAVA_PID
# GC cause and duration
jcmd $JAVA_PID GC.heap_info
jcmd $JAVA_PID GC.run_finalization
# Key indicators: long GC pauses (> 1s), high GC frequency (> 1/sec)
```

### Thread Analysis
```bash
# Thread count and state
jstack $JAVA_PID | grep "java.lang.Thread.State" | sort | uniq -c
# Deadlock detection
jstack $JAVA_PID | grep -A 10 "Found one Java-level deadlock"
# Thread dump
jstack $JAVA_PID > /tmp/jstack_$JAVA_PID.txt
# Key indicators: high thread count (> 1000), blocked threads, deadlocks
# CPU usage by thread
top -H -p $JAVA_PID
# Map thread to Java thread
printf "0x%x\n" <thread-id>  # Convert to hex, then search in jstack output
```

### Class Loading and JIT
```bash
# Class loading stats
jstat -class $JAVA_PID 1s 5
# Key indicators: excessive class loading (> 1000/sec)
# JIT compilation
jstat -compiler $JAVA_PID
# Key indicators: low compilation rate, high compilation time
# JIT compiled methods
jcmd $JAVA_PID VM.cds
```

---

## Bottleneck Identification

| Category | Key Metrics | Thresholds | Collection |
|----------|-------------|------------|------------|
| Memory Pressure | heap usage, old gen % | > 80%, old gen > 70% | jstat -gcutil |
| GC Pauses | FGCT, YGCT, FGC count | FGCT > 1s, FGC > 1/min | jstat -gc |
| Memory Leak | heap growth rate, metaspace | Continuous growth > 1MB/min | jstat -gc |
| Thread Contention | blocked threads, deadlocks | > 100 blocked, any deadlock | jstack |
| CPU Hotspots | Thread CPU time, hot methods | Single thread > 50% CPU | top -H, jstack |
| Class Loading | loaded classes, unload rate | > 1000 load/sec | jstat -class |
| Compilation | JIT compilation time | High compilation overhead | jstat -compiler |

---

## Diagnostic Commands

```bash
# Full JVM statistics
jstat -gc -gcutil -gccapacity -gcnew -gcold $JAVA_PID > /tmp/jstat_$JAVA_PID.txt
# Thread dump for deadlock detection
jstack -l $JAVA_PID > /tmp/jstack_$JAVA_PID.txt
# Heap dump (use with caution, large file)
jcmd $JAVA_PID GC.heap_dump /tmp/heap_$JAVA_PID.hprof
# JVM flags
jinfo -flags $JAVA_PID
jcmd $JAVA_PID VM.flags
# System properties
jcmd $JAVA_PID VM.system_properties
# VM summary
jcmd $JAVA_PID VM.version
jcmd $JAVA_PID VM.summary
```

---

## Advanced Tools

```bash
# JConsole (GUI)
jconsole $JAVA_PID
# JVisualVM (GUI, includes heap analyzer)
jvisualvm
# Java Flight Recorder (JFR)
jcmd $JAVA_PID JFR.start name=recording duration=60s filename=/tmp/recording.jfr
# Arthas (Alibaba's Java diagnostic tool)
./arthas-boot.sh
# YourKit (commercial)
# JProfiler (commercial)
```

---

## Common Bottleneck Patterns

1. **Memory leak**: Continuous heap growth, frequent Full GC, OutOfMemoryError
2. **Long GC pauses**: FGCT > 1s, system unresponsive during GC, stop-the-world events
3. **Thread deadlock**: Threads in BLOCKED state indefinitely, application hangs
4. **CPU hotspots**: Single thread consuming 100% CPU, inefficient algorithm, hotspot method
5. **Class loading overhead**: Excessive class loading, high memory usage in metaspace, PermGen/Perm space issues
6. **I/O bottlenecks**: Threads blocked on I/O, slow database/network calls, thread pool exhaustion

---

## Output Template

```markdown
## Java Application Workload Analysis

### JVM Status
- Java version: X
- Heap size: X MB (max: X MB)
- Heap usage: X%
- Thread count: X

### Garbage Collection
- Young Gen collections: X (avg time: Xms)
- Full GC collections: X (avg time: Xms)
- Total GC time: Xms (X% of uptime)

### Memory Regions
| Region | Capacity | Used | Utilization |
|--------|----------|------|-------------|
| Young Gen | X MB | X MB | X% |
| Old Gen | X MB | X MB | X% |
| Metaspace | X MB | X MB | X% |

### Thread State
| State | Count |
|-------|-------|
| RUNNABLE | X |
| WAITING | X |
| BLOCKED | X |
| TIMED_WAITING | X |

### Top Bottlenecks
| Component | Issue | Evidence | Impact |
|-----------|-------|----------|--------|
```

