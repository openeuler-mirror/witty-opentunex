---
name: golang-optimization
description: Go application performance optimization with GOMAXPROCS, GOGC, runtime tuning, and goroutine management.
---

# Go Application Performance Optimization

This skill provides comprehensive Go application performance optimization based on system-level bottleneck analysis and application-specific metrics.

---

## Pre-requisites

- Go application running
- Sufficient memory for configuration changes
- Backup of current configuration
- Monitoring tools installed (optional): pprof, prometheus-Go metrics

---

## Configuration File Detection

**Common Go Application Configuration**:

| Type | Location | Notes |
|------|-----------|--------|
| Environment Variables | shell, systemd service | GOMAXPROCS, GOGC, GODEBUG |
| Application Config | JSON, YAML, TOML | Application-specific settings |
| Docker | Dockerfile, docker-compose.yml | Container settings |

**Detection Commands**:

```bash
# Detect running Go processes
ps aux | grep -E "[^/]go run" | grep -v grep

# Check Go version
go version

# Check Go environment variables
env | grep GO

# Check Go runtime metrics (if exposed)
curl http://localhost:6060/debug/pprof/heap
curl http://localhost:6060/debug/pprof/goroutine
```

---

## Configuration Backup

```bash
# Backup Go application configuration
BACKUP_DIR="/opt/optimization-backup/golang_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup environment variables
env | grep GO > $BACKUP_DIR/go_env.txt

# Backup application config
find /opt/app -name config.json -o -name config.yaml -o -name config.toml | xargs -I {} cp {} $BACKUP_DIR/

# Backup systemd service file
cp /etc/systemd/system/goapp.service $BACKUP_DIR/ 2>/dev/null || true

# Create backup manifest
cat > $BACKUP_DIR/backup_manifest.txt << EOF
Go Application Backup
Date: $(date)
Go Version: $(go version)
Configuration Files:
  - go_env.txt
  - config files
  - systemd service file
EOF
```

---

## Bottleneck Analysis

Based on system-level bottleneck analysis, identify Go-specific bottlenecks:

### Memory Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| High memory usage | Memory leaks, excessive allocation | Critical | Fix leaks, reduce allocation, use sync.Pool |
| Frequent GC | High GC frequency | Critical | Tune GOGC, reduce allocation |
| Long GC pauses | Long GC pause times | High | Reduce heap size, tune GOGC |
| Goroutine leaks | Growing goroutine count | Critical | Fix goroutine leaks, limit goroutines |

### CPU Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| High CPU usage | High CPU utilization | Critical | Optimize code, use caching, reduce allocations |
| CPU bound operations | High CPU in specific operations | High | Optimize algorithms, use native code |
| Excessive syscalls | High syscall rate | Medium | Reduce syscalls, batch operations |
| Context switches | High context switch rate | Medium | Reduce goroutine count, use channels efficiently |

### Goroutine Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Too many goroutines | High goroutine count | Critical | Reduce goroutine count, use worker pools |
| Goroutine leaks | Growing goroutine count | Critical | Fix leaks, use proper goroutine lifecycle |
| Channel blocking | Blocked goroutines | High | Use buffered channels, optimize channel usage |
| Goroutine starvation | Some goroutines never execute | Medium | Tune scheduler, use proper priority |

### I/O Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Slow I/O operations | Long I/O wait time | High | Use buffered I/O, async I/O |
| File descriptor limit | Too many open files error | Critical | Increase ulimit, use connection pooling |
| Network bottleneck | Slow network operations | Medium | Use connection pooling, enable TCP keepalive |
| Database connection pool exhaustion | Connection wait timeout | Critical | Increase pool size, optimize queries |

---

## Optimization Recommendations

### 1. GOMAXPROCS Optimization

**Objective**: Optimize number of OS threads for better CPU utilization.

**Current Value Check**:
```bash
# Check current GOMAXPROCS
echo $GOMAXPROCS

# Check runtime.GOMAXPROCS in application
# In code: runtime.GOMAXPROCS(0)
```

**Recommended Configuration**:

**Option A: CPU Cores**
```bash
# Set GOMAXPROCS to number of CPU cores
export GOMAXPROCS=$(nproc)

# Set to half of CPU cores for I/O-bound workloads
export GOMAXPROCS=$(( $(nproc) / 2 ))
```

**Option B: Systemd Service File**
```ini
# /etc/systemd/system/goapp.service
[Service]
Environment="GOMAXPROCS=4"
```

**Option C: Docker**
```dockerfile
# Dockerfile
ENV GOMAXPROCS=4
```

**Calculation**:
```
GOMAXPROCS = Number of CPU cores (for CPU-bound workloads)
GOMAXPROCS = Number of CPU cores / 2 (for I/O-bound workloads)

Example for 8 cores:
- CPU-bound: GOMAXPROCS = 8
- I/O-bound: GOMAXPROCS = 4
```

**Verification**:
```bash
# Verify GOMAXPROCS
echo $GOMAXPROCS

# Check CPU usage
top -p <pid>
```

**Risk**: Low

**Expected Impact**: 10-20% improvement in CPU utilization

---

### 2. GOGC Optimization

**Objective**: Optimize GC trigger threshold for better performance.

**Current Value Check**:
```bash
# Check current GOGC
echo $GOGC

# Check runtime debug environment
env | grep GODEBUG
```

**Recommended Configuration**:

**Option A: Default GOGC**
```bash
# Default GOGC (trigger GC when heap grows 100% since last GC)
export GOGC=100
```

**Option B: Lower GOGC (more frequent GC, smaller pauses)**
```bash
# Lower GOGC for lower memory footprint
export GOGC=50

# Even lower for memory-constrained environments
export GOGC=20
```

**Option C: Higher GOGC (less frequent GC, larger pauses)**
```bash
# Higher GOGC for better throughput
export GOGC=200
```

**Option D: GODEBUG GC Details**
```bash
# Enable GC debug output
export GODEBUG=gctrace=1

# Print GC info to stderr
# Output: gc # @#s #%: #+#+# ms clock, #+#+# ms cpu, #->#-># ms
```

**Verification**:
```bash
# Verify GOGC
echo $GOGC

# Monitor GC performance
curl http://localhost:6060/debug/pprof/heap

# Check GC stats in application logs
# Look for: "gc # @#s #%" lines
```

**Risk**: Medium - Lower GOGC increases GC frequency, Higher GOGC increases pause time

**Expected Impact**: 10-30% reduction in GC pause time

---

### 3. Goroutine Management Optimization

**Objective**: Optimize goroutine usage for better performance.

**Current Value Check**:
```bash
# Check goroutine count
curl http://localhost:6060/debug/pprof/goroutine?debug=2

# Check goroutine stats in application
# In code: runtime.NumGoroutine()
```

**Recommended Configuration**:

**Use Worker Pool Pattern**:
```go
// Create worker pool with limited goroutines
func workerPool(workers int, tasks <-chan Task) {
    for i := 0; i < workers; i++ {
        go func() {
            for task := range tasks {
                process(task)
            }
        }()
    }
}

// Usage
tasks := make(chan Task, 100)
go workerPool(4, tasks)
```

**Limit Goroutine Creation**:
```go
// Use buffered channels to limit goroutines
func processItems(items []Item) {
    sem := make(chan struct{}, 10) // Limit to 10 concurrent goroutines
    
    var wg sync.WaitGroup
    for _, item := range items {
        wg.Add(1)
        go func(i Item) {
            defer wg.Done()
            sem <- struct{}{}        // Acquire semaphore
            defer func() { <-sem }()  // Release semaphore
            process(i)
        }(item)
    }
    wg.Wait()
}
```

**Use sync.Pool for Object Reuse**:
```go
// Create object pool
var bufferPool = sync.Pool{
    New: func() interface{} {
        return make([]byte, 1024)
    },
}

// Use object pool
func processData(data []byte) {
    buf := bufferPool.Get().([]byte)
    defer bufferPool.Put(buf)
    
    // Process data
    copy(buf, data)
    // ...
}
```

**Verification**:
```bash
# Check goroutine count
curl http://localhost:6060/debug/pprof/goroutine?debug=2

# Monitor goroutine leaks
watch -n 1 'curl -s http://localhost:6060/debug/pprof/goroutine | grep "goroutine profile:" | cut -d: -f2'
```

**Risk**: Medium - Too few goroutines causes backlog, too many causes overhead

**Expected Impact**: 20-40% improvement in goroutine management

---

### 4. Memory Allocation Optimization

**Objective**: Reduce memory allocation for better GC performance.

**Recommended Practices**:

**Reuse Objects**:
```go
// Bad: Allocate new object each time
func process(items []Item) {
    for _, item := range items {
        buf := make([]byte, 1024)  // Allocate new buffer
        processItem(buf, item)
    }
}

// Good: Reuse buffer
func process(items []Item) {
    buf := make([]byte, 1024)  // Allocate once
    for _, item := range items {
        buf = buf[:0]           // Reset buffer
        processItem(buf, item)
    }
}
```

**Use sync.Pool**:
```go
var bufferPool = sync.Pool{
    New: func() interface{} {
        return make([]byte, 1024)
    },
}

func processData(data []byte) {
    buf := bufferPool.Get().([]byte)
    defer bufferPool.Put(buf)
    // Use buf
}
```

**Preallocate Slices**:
```go
// Bad: Append to slice
func process(items []Item) []Result {
    var results []Result
    for _, item := range items {
        results = append(results, processItem(item))  // May cause reallocation
    }
    return results
}

// Good: Preallocate slice
func process(items []Item) []Result {
    results := make([]Result, 0, len(items))  // Preallocate
    for _, item := range items {
        results = append(results, processItem(item))
    }
    return results
}
```

**Avoid String Conversions**:
```go
// Bad: Convert []byte to string repeatedly
func process(data []byte) {
    for i := 0; i < len(data); i++ {
        str := string(data[i:])  // Allocate new string
        processByte(str)
    }
}

// Good: Convert once or use []byte directly
func process(data []byte) {
    for i := 0; i < len(data); i++ {
        processByte(data[i:i+1])
    }
}
```

**Verification**:
```bash
# Check heap profile
curl http://localhost:6060/debug/pprof/heap > /tmp/heap.prof
go tool pprof -http=localhost:8081 /tmp/heap.prof

# Check allocation rate
curl http://localhost:6060/debug/pprof/allocs > /tmp/allocs.prof
go tool pprof -http=localhost:8081 /tmp/allocs.prof
```

**Risk**: Low

**Expected Impact**: 20-40% reduction in allocation rate

---

### 5. I/O Optimization

**Objective**: Optimize I/O operations for better performance.

**Recommended Practices**:

**Use Buffered I/O**:
```go
// Bad: Unbuffered I/O
func readFile(filename string) ([]byte, error) {
    file, err := os.Open(filename)
    if err != nil {
        return nil, err
    }
    defer file.Close()
    
    buf := make([]byte, 1024)
    var data []byte
    for {
        n, err := file.Read(buf)
        if err != nil {
            break
        }
        data = append(data, buf[:n]...)
    }
    return data, nil
}

// Good: Buffered I/O
func readFile(filename string) ([]byte, error) {
    file, err := os.Open(filename)
    if err != nil {
        return nil, err
    }
    defer file.Close()
    
    buf := bufio.NewReader(file)
    data, err := io.ReadAll(buf)
    if err != nil {
        return nil, err
    }
    return data, nil
}
```

**Use Connection Pooling**:
```go
// Create connection pool
type ConnPool struct {
    mu    sync.Mutex
    conns chan *sql.DB
}

func NewConnPool(size int, dsn string) *ConnPool {
    pool := &ConnPool{
        conns: make(chan *sql.DB, size),
    }
    
    for i := 0; i < size; i++ {
        conn, err := sql.Open("mysql", dsn)
        if err != nil {
            continue
        }
        pool.conns <- conn
    }
    
    return pool
}

func (p *ConnPool) Get() *sql.DB {
    return <-p.conns
}

func (p *ConnPool) Put(conn *sql.DB) {
    p.conns <- conn
}
```

**Enable TCP Keepalive**:
```go
// Enable TCP keepalive for connections
dialer := &net.Dialer{
    KeepAlive: 30 * time.Second,
}

conn, err := dialer.Dial("tcp", "localhost:8080")
```

**Verification**:
```bash
# Check I/O profile
curl http://localhost:6060/debug/pprof/block > /tmp/block.prof
go tool pprof -http=localhost:8081 /tmp/block.prof

# Check goroutine blocking
curl http://localhost:6060/debug/pprof/goroutine?debug=2
```

**Risk**: Low

**Expected Impact**: 20-40% improvement in I/O performance

---

### 6. Runtime Tuning Optimization

**Objective**: Tune Go runtime for better performance.

**Recommended Configuration**:

**Runtime Settings in Code**:
```go
func main() {
    // Set GOMAXPROCS
    runtime.GOMAXPROCS(runtime.NumCPU())
    
    // Set memory limit (Go 1.19+)
    // runtime/debug.SetMemoryLimit(4 << 30)  // 4GB
    
    // Set memory profile rate
    // runtime.SetMemProfileRate(1)  // Profile every allocation
    
    // Enable trace
    // trace.Start(os.Stdout)
    // defer trace.Stop()
    
    // Start application
    runApplication()
}
```

**Environment Variables**:
```bash
# GOMEMLIMIT (Go 1.19+)
export GOMEMLIMIT=4GiB

# GOCACHE (Go build cache)
export GOCACHE=/tmp/go-cache

# GOMODCACHE (Go module cache)
export GOMODCACHE=/tmp/go-mod-cache
```

**Verification**:
```bash
# Verify runtime settings
curl http://localhost:6060/debug/pprof/heap
curl http://localhost:6060/debug/pprof/goroutine

# Check memory limit
cat /proc/<pid>/limits | grep Max memory size
```

**Risk**: Low-Medium

**Expected Impact**: Better memory management and performance

---

### 7. Profiling and Monitoring

**Objective**: Enable profiling for performance analysis.

**Recommended Configuration**:

**Enable pprof Server**:
```go
import (
    "net/http"
    _ "net/http/pprof"
)

func main() {
    go func() {
        log.Println(http.ListenAndServe("localhost:6060", nil))
    }()
    
    runApplication()
}
```

**Enable Custom Metrics**:
```go
import (
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    requestsTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "http_requests_total",
            Help: "Total number of HTTP requests",
        },
        []string{"method", "path", "status"},
    )
    
    requestDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name: "http_request_duration_seconds",
            Help: "HTTP request latencies in seconds",
        },
        []string{"method", "path"},
    )
)

func init() {
    prometheus.MustRegister(requestsTotal)
    prometheus.MustRegister(requestDuration)
}

func handler(w http.ResponseWriter, r *http.Request) {
    start := time.Now()
    
    // Process request
    
    duration := time.Since(start).Seconds()
    
    requestsTotal.WithLabelValues(r.Method, r.URL.Path, "200").Inc()
    requestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration)
}

func main() {
    http.Handle("/metrics", promhttp.Handler())
    go func() {
        log.Println(http.ListenAndServe(":9090", nil))
    }()
    
    runApplication()
}
```

**Verification**:
```bash
# Check pprof endpoint
curl http://localhost:6060/debug/pprof/

# Check metrics endpoint
curl http://localhost:9090/metrics

# Capture heap profile
curl http://localhost:6060/debug/pprof/heap > heap.prof
go tool pprof -http=localhost:8081 heap.prof
```

**Risk**: Low - Profiling adds minimal overhead

**Expected Impact**: Enables performance analysis

---

## Optimization Procedure

### Step 1: Pre-Optimization Baseline

```bash
# Collect current performance metrics
curl http://localhost:6060/debug/pprof/goroutine > /tmp/golang_goroutine_before.txt
curl http://localhost:6060/debug/pprof/heap > /tmp/golang_heap_before.txt
top -b -n 1 -p <pid> > /tmp/golang_cpu_before.txt

# Record timestamp
date > /tmp/golang_baseline_timestamp.txt
```

### Step 2: Apply Configuration Changes

```bash
# Create optimized environment
cat > /etc/profile.d/goapp.sh << EOF
# Go runtime optimization
export GOMAXPROCS=$(nproc)
export GOGC=100
export GOMEMLIMIT=4GiB

# Go debug options (for development)
# export GODEBUG=gctrace=1
EOF

# Update systemd service
cat > /etc/systemd/system/goapp.service << EOF
[Unit]
Description=Go Application
After=network.target

[Service]
Type=simple
User=goapp
EnvironmentFile=/etc/profile.d/goapp.sh
WorkingDirectory=/opt/app
ExecStart=/opt/app/goapp
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and restart service
systemctl daemon-reload
systemctl restart goapp

# Verify application started
systemctl status goapp
curl -I http://localhost:8080/
```

### Step 3: Post-Optimization Verification

```bash
# Collect new performance metrics
curl http://localhost:6060/debug/pprof/goroutine > /tmp/golang_goroutine_after.txt
curl http://localhost:6060/debug/pprof/heap > /tmp/golang_heap_after.txt
top -b -n 1 -p <pid> > /tmp/golang_cpu_after.txt

# Verify configuration applied
env | grep GOMAXPROCS
env | grep GOGC
```

### Step 4: Performance Comparison

```bash
# Compare CPU usage
echo "=== Before ==="
cat /tmp/golang_cpu_before.txt | grep -E "PID|USER|%CPU"

echo "=== After ==="
cat /tmp/golang_cpu_after.txt | grep -E "PID|USER|%CPU"

# Compare goroutine count
echo "=== Before ==="
grep "goroutine profile:" /tmp/golang_goroutine_before.txt | cut -d: -f2

echo "=== After ==="
grep "goroutine profile:" /tmp/golang_goroutine_after.txt | cut -d: -f2
```

---

## Monitoring and Maintenance

### Key Metrics to Monitor

```bash
# Goroutine count
curl http://localhost:6060/debug/pprof/goroutine?debug=2

# Heap usage
curl http://localhost:6060/debug/pprof/heap

# GC stats
curl http://localhost:6060/debug/pprof/heap

# Block profile (blocking operations)
curl http://localhost:6060/debug/pprof/block

# Thread creation
curl http://localhost:6060/debug/pprof/threadcreate
```

### Recommended Tools

- **pprof**: Built-in Go profiling
- **Prometheus + Grafana**: Production monitoring
- **trace**: Go execution tracer
- **go-torch**: Flame graph visualization

---

## Rollback Procedure

```bash
# Restore backup configuration
cp /opt/optimization-backup/golang_*/go_env.txt /tmp/go_env_backup.txt

# Remove optimized environment
rm /etc/profile.d/goapp.sh

# Restore original systemd service
cp /opt/optimization-backup/golang_*/goapp.service /etc/systemd/system/goapp.service

# Reload systemd and restart service
systemctl daemon-reload
systemctl restart goapp

# Verify application started
systemctl status goapp
curl -I http://localhost:8080/
```

---

## Common Issues and Solutions

### Issue 1: High memory usage after GOGC increase
**Solution**: Reduce GOGC, fix memory leaks, use sync.Pool

### Issue 2: Goroutine leaks
**Solution**: Fix goroutine leaks, use proper goroutine lifecycle, add timeout

### Issue 3: Too many open files
**Solution**: Increase ulimit, use connection pooling

### Issue 4: High CPU usage
**Solution**: Optimize code, use caching, reduce allocations

---

## Additional Resources

- [Go Runtime Documentation](https://pkg.go.dev/runtime)
- [Go Profiling](https://golang.org/doc/diagnostics/)
- [Go Performance Tips](https://github.com/dgryski/go-perf)

