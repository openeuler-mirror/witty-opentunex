---
name: go-benchmark
description: Go application benchmarking tools reference
---

# Go Application Benchmarking

**Tool**: Go test with pprof, wrk (for HTTP)

**Description**: Go application performance testing

**Prerequisites**:
- Go application running
- Go tools installed

## Built-in Go Benchmarking

```go
// Create benchmark file: benchmark_test.go
package main

import (
    "testing"
    "math/rand"
)

func BenchmarkMyFunction(b *testing.B) {
    for i := 0; i < b.N; i++ {
        MyFunction(rand.Intn(1000))
    }
}

func main() {
    // Run specific benchmark
    testing.Benchmark(func(b *testing.B) {
        BenchmarkMyFunction(b)
    })
}
```

## Run Go Benchmarks

```bash
# Run all benchmarks
go test -bench=. -benchmem

# Run specific benchmark
go test -bench=MyFunction -benchmem

# Run with CPU profiling
go test -cpuprofile=cpu.prof -bench=.

# Run with memory profiling
go test -memprofile=mem.prof -bench=.
```

## Profiling with pprof

```go
import (
    _ "net/http/pprof"
    "os"
    "runtime/pprof"
)

func main() {
    // Enable pprof HTTP server
    go func() {
        http.ListenAndServe("localhost:6060", nil)
    }()
    
    // Run application
    RunApplication()
}
```

## Profiling Commands

```bash
# CPU profiling
go tool pprof -http=:8081 http://localhost:6060/debug/pprof/profile?seconds=30

# Heap profiling
go tool pprof -http=:8081 http://localhost:6060/debug/pprof/heap

# Goroutine profiling
go tool pprof -http=:8081 http://localhost:6060/debug/pprof/goroutine

# Block profiling
go tool pprof -http=:8081 http://localhost:6060/debug/pprof/block
```

## HTTP Benchmarking with wrk

```bash
# Same as Nginx benchmarking
wrk -t 60 -c 100 http://localhost:8080/
```

## Go Benchmark Output

```
BenchmarkMyFunction-8    1234567    1234 ns/op    1024 B/op    10 allocs/op
```

## Output Parsing

Parse go test benchmark output:

```bash
# Parse go test output
parse_go_output() {
    local log_file="$1"
    
    # Extract operations per second (inverse of ns/op)
    grep "ns/op" "$log_file" | \
    sed -E 's/Benchmark.*-?[0-9]+\s+([0-9]+)\s+ns\/op.*/\1/' > /tmp/go_ns_per_op.txt
    
    # Extract bytes per operation
    grep "B/op" "$log_file" | \
    sed -E 's/.*\s+([0-9]+)\s+B\/op/\1/' > /tmp/go_bytes_per_op.txt
    
    # Extract allocations per operation
    grep "allocs/op" "$log_file" | \
    sed -E 's/.*\s+([0-9]+)\s+allocs\/op/\1/' > /tmp/go_allocs_per_op.txt
    
    # Calculate ops/sec from ns/op
    NS_PER_OP=$(cat /tmp/go_ns_per_op.txt)
    if [ -n "$NS_PER_OP" ] && [ "$NS_PER_OP" -gt 0 ]; then
        OPS_PER_SEC=$(echo "scale=2; 1000000000 / $NS_PER_OP" | bc)
        echo "$OPS_PER_SEC" > /tmp/go_ops_per_sec.txt
    fi
}

NS_PER_OP=$(cat /tmp/go_ns_per_op.txt)
BYTES_PER_OP=$(cat /tmp/go_bytes_per_op.txt)
ALLOCS_PER_OP=$(cat /tmp/go_allocs_per_op.txt)
OPS_PER_SEC=$(cat /tmp/go_ops_per_sec.txt)
```

Parse pprof CPU profile:

```bash
# Parse pprof text output
parse_pprof_output() {
    local pprof_file="$1"
    local top_n="${2:-10}"
    
    # Extract top CPU consumers
    head -n $(echo "$top_n + 7" | bc) "$pprof_file" | tail -n "$top_n" > /tmp/pprof_top.txt
    
    # Extract total CPU percentage
    grep "^Total:" "$pprof_file" | \
    sed -E 's/.*:\s*([0-9]+\.[0-9]+).*/\1/' > /tmp/pprof_total.txt
}

TOP_FUNCTIONS=$(cat /tmp/pprof_top.txt)
TOTAL_CPU=$(cat /tmp/pprof_total.txt)
```

**Extracted Metrics**:

| Metric | Variable | Description |
|--------|----------|-------------|
| Ops/sec | `OPS_PER_SEC` | Operations per second |
| ns/op | `NS_PER_OP` | Nanoseconds per operation |
| Bytes/op | `BYTES_PER_OP` | Bytes allocated per operation |
| Allocs/op | `ALLOCS_PER_OP` | Allocations per operation |
| Total CPU | `TOTAL_CPU` | Total CPU percentage (pprof) |

**Example Parsed Output (go test)**:
```markdown
### Go Benchmark Results

| Metric | Value |
|--------|-------|
| Ops/sec | 810372.00 |
| ns/op | 1234 |
| Bytes/op | 1024 |
| Allocs/op | 10 |
```

**Example Parsed Output (pprof)**:
```markdown
### Go CPU Profile Results

| Function | CPU % |
|----------|-------|
| runtime.scanobject | 15.2% |
| runtime.mallocgc | 12.8% |
| myapp.processItem | 8.5% |

Total CPU: 45.3%
```
