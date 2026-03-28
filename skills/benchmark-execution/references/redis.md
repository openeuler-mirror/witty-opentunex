---
name: redis-benchmark
description: Redis benchmarking tool reference
---

# Redis Benchmarking

**Tool**: redis-benchmark

**Description**: Redis benchmark tool for performance testing

**Prerequisites**:
- Redis server running
- redis-benchmark tool installed (part of redis-tools package)

**Installation**:
```bash
# Debian/Ubuntu
apt-get install redis-tools

# RHEL/CentOS
yum install redis

# From source
wget http://download.redis.io/releases/redis-7.0.5.tar.gz
tar -xzf redis-7.0.5.tar.gz
cd redis-7.0.5
make
make install
```

## Benchmark Commands

```bash
# SET benchmark
redis-benchmark -h localhost -p 6379 -t set -n 1000000

# GET benchmark
redis-benchmark -h localhost -p 6379 -t get -n 1000000

# Mixed SET/GET
redis-benchmark -h localhost -p 6379 -t set,get -n 1000000

# INCR benchmark
redis-benchmark -h localhost -p 6379 -t incr -n 1000000

# LPUSH/LPOP benchmark
redis-benchmark -h localhost -p 6379 -t lpush -n 1000000

# Multiple data types
redis-benchmark -h localhost -p 6379 -t set,get,lpush,lpop,incr -n 100000

# Pipeline testing
redis-benchmark -h localhost -p 6379 -P 16 -t set -n 100000

# Multiple threads/clients
redis-benchmark -h localhost -p 6379 -c 50 -t set -n 1000000

# Random data size
redis-benchmark -h localhost -p 6379 -d 100 -t set -n 1000000

# Connection keep-alive
redis-benchmark -h localhost -p 6379 -k 1 -t set -n 1000000
```

## Output Metrics

- Requests per second
- Latency (average, min, max, p50, p95, p99)
- Bytes transferred per second
- Connect time
- Connection errors

## Example Output

```
====== SET ======
  1000000 requests completed in 5.23 seconds
  50 parallel clients
  3 bytes payload
  keep alive: 1
  99.80% <= 1 milliseconds
  97.56% <= 2 milliseconds
  191234.00 requests per second

====== GET ======
  1000000 requests completed in 4.89 seconds
  50 parallel clients
  3 bytes payload
  keep alive: 1
  96.50% <= 1 milliseconds
  194567.00 requests per second
```

## Output Parsing

Parse redis-benchmark output to extract performance metrics:

```bash
# Parse redis-benchmark output
parse_redis_output() {
    local log_file="$1"
    local operation="${2:-SET}"
    
    # Extract requests per second for specific operation
    awk "/====== $operation ======/,/======.*======/" "$log_file" | \
    grep "requests per second" | \
    sed -E 's/.*:\s*([0-9]+\.[0-9]+).*/\1/' > /tmp/redis_rps.txt
    
    # Extract latency percentiles
    awk "/====== $operation ======/,/======.*======/" "$log_file" | \
    grep "% <=" | head -5 > /tmp/redis_latency.txt
    
    # Extract duration
    awk "/====== $operation ======/,/======.*======/" "$log_file" | \
    grep "completed in" | \
    sed -E 's/.*completed in\s*([0-9]+\.[0-9]+).*/\1/' > /tmp/redis_duration.txt
}

# Extract metrics into variables
RPS=$(cat /tmp/redis_rps.txt)
DURATION=$(cat /tmp/redis_duration.txt)
P50=$(grep -E "50%" /tmp/redis_latency.txt | sed -E 's/.*<=\s*([0-9]+\.[0-9]+).*/\1/')
P99=$(grep -E "99%" /tmp/redis_latency.txt | sed -E 's/.*<=\s*([0-9]+\.[0-9]+).*/\1/')
```

**Extracted Metrics**:

| Metric | Variable | Description |
|--------|----------|-------------|
| RPS | `RPS` | Requests per second |
| Duration | `DURATION` | Total test duration (seconds) |
| P50 Latency | `P50` | 50th percentile latency (ms) |
| P99 Latency | `P99` | 99th percentile latency (ms) |

**Example Parsed Output**:
```markdown
### Redis Benchmark Results (SET)

| Metric | Value |
|--------|-------|
| RPS | 191234.00 |
| Duration | 5.23s |
| P50 Latency | 1ms |
| P99 Latency | 2ms |
```
