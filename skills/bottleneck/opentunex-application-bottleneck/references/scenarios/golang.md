---
name: golang-workload
description: Go (Golang) application workload analysis: goroutines, GC stats, heap allocation, syscalls. Use for Go program performance troubleshooting.
---

# golang-workload — Go Application Performance Analysis

**Command execution**: all commands for client should be executed via `ssh`, considering the limits of ssh, allow converting commands to bash script and scp to client and execute if needed. ALL DESTRUCTIVE COMMAND SHOULD REQUEST USER'S COMIRMATION.

**Application Detection**:
```bash
ps aux | grep -E "go-build|go run|<go-binary-name>"
# Check if Go runtime is present
# Look for Go applications using pprof endpoint or SIGQUIT
```

---

## Key Metrics Collection

### Goroutines and Threads
```bash
# Send SIGQUIT to get goroutine dump
kill -QUIT <PID>
# Output goroutine dump to stderr
# Check goroutine count
curl http://localhost:<pprof-port>/debug/pprof/goroutine?debug=1
# Key indicators: goroutine count > 10000, goroutine leaks
# Thread stats
curl http://localhost:<pprof-port>/debug/pprof/threadcreate?debug=1
# Key indicators: excessive thread creation, thread exhaustion
```

### Memory and Heap
```bash
# Heap profile
curl http://localhost:<pprof-port>/debug/pprof/heap > /tmp/heap.prof
# Analyze with go tool
go tool pprof -top /tmp/heap.prof
# Key indicators: high heap allocation (> 1GB), heap growth rate > 10MB/min
# Allocation rate
curl http://localhost:<pprof-port>/debug/pprof/allocs?debug=1
# Key indicators: excessive allocation rate > 1GB/sec
# Live objects
curl http://localhost:<pprof-port>/debug/pprof/heap?debug=2
# Key indicators: large object count, memory leaks
```

### Garbage Collection
```bash
# GC stats
curl http://localhost:<pprof-port>/debug/pprof/gc?debug=1
# Key indicators: GC pause > 100ms, frequent GC (> 10/sec)
# GC cycles
curl http://localhost:<pprof-port>/debug/pprof/gc?debug=2
# Key indicators: increasing GC cycles, long GC pauses
```

### CPU and Performance
```bash
# CPU profile (30 seconds)
curl http://localhost:<pprof-port>/debug/pprof/profile?seconds=30 > /tmp/cpu.prof
# Analyze top functions
go tool pprof -top /tmp/cpu.prof
# Key indicators: single function > 20% CPU, hot loops
# Real-time goroutine dump
curl http://localhost:<pprof-port>/debug/pprof/goroutine?debug=1 | head -100
# Key indicators: blocked goroutines, waiting goroutines
```

### System Calls and Blocking
```bash
# Block profile
curl http://localhost:<pprof-port>/debug/pprof/block?debug=1
# Key indicators: blocking I/O, channel contention, mutex contention
# Mutex profile (if enabled)
curl http://localhost:<pprof-port>/debug/pprof/mutex?debug=1
# Key indicators: lock contention, mutex wait time > 100ms
# Syscall trace (if enabled)
curl http://localhost:<pprof-port>/debug/pprof/syscall?debug=1
# Key indicators: excessive syscalls, slow syscalls
```

---

## Bottleneck Identification

| Category | Key Metrics | Thresholds | Collection |
|----------|-------------|------------|------------|
| Goroutine Leak | goroutine count, growth rate | > 10000, > 100/min | pprof goroutine |
| Memory Leak | heap size, allocation rate | > 1GB, > 1GB/sec | pprof heap, allocs |
| GC Pressure | GC pause time, GC frequency | > 100ms, > 10/sec | pprof gc |
| CPU Hotspot | top CPU functions | > 20% total CPU | pprof profile |
| Block Contention | blocking time, wait count | > 10s total, > 1000 waits | pprof block |
| Lock Contention | mutex wait time, contention | wait > 100ms, > 100 contends | pprof mutex |
| Syscall Overhead | syscall count, latency | > 10000/sec, > 10ms avg | pprof syscall |

---

## Diagnostic Commands

```bash
# Full pprof analysis
go tool pprof http://localhost:<pprof-port>/debug/pprof/heap
go tool pprof http://localhost:<pprof-port>/debug/pprof/profile?seconds=30
go tool pprof http://localhost:<pprof-port>/debug/pprof/goroutine
# Generate flamegraph
go tool pprof -http=:8080 http://localhost:<pprof-port>/debug/pprof/profile?seconds=30
# List all pprof endpoints
curl http://localhost:<pprof-port>/debug/pprof/
# Runtime metrics
curl http://localhost:<pprof-port>/debug/vars
```

---

## Advanced Tools

```bash
# pprof (built-in Go profiler)
go tool pprof
# Graphviz (visualization)
dot -Tsvg profile.dot > profile.svg
# go-torch (flamegraph)
go-torch -u http://localhost:<pprof-port> -t 30
# delve (Go debugger)
dlv attach <PID>
dlv debug <program>
```

---

## Common Bottleneck Patterns

1. **Goroutine leak**: Continuously increasing goroutine count, blocked goroutines, channel deadlock
2. **Memory leak**: Continuous heap growth, unreleased objects, allocation rate > 1GB/sec
3. **GC pressure**: Long GC pauses, frequent GC cycles, high heap allocation
4. **CPU hotspots**: Single function consuming > 20% CPU, inefficient algorithms
5. **Blocking I/O**: Goroutines blocked on I/O, slow network calls, synchronous operations
6. **Lock contention**: Mutex contention, high wait times, sequential access to shared resources

---

## Output Template

```markdown
## Go Application Workload Analysis

### Goroutine Status
- Total goroutines: X
- Goroutine growth rate: X/min
- Top goroutine stacks: [list]

### Memory Status
- Heap size: X MB
- Allocation rate: X MB/sec
- Live objects: X
- Top memory allocators: [list]

### GC Status
- GC pause avg: Xms
- GC pause max: Xms
- GC frequency: X/sec
- GC cycles: X

### CPU Performance
- Top CPU consumers: [list]
- CPU utilization by function: [table]

### Blocking and Locking
- Blocking operations: X
- Mutex contention: X
- Block time avg: Xms

### Syscall Activity
- Syscall rate: X/sec
- Slow syscalls: [list]

### Top Bottlenecks
| Component | Issue | Evidence | Impact |
|-----------|-------|----------|--------|
```

