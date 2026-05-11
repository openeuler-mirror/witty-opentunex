---
name: nginx-benchmark
description: Nginx/HTTP benchmarking tools reference
---

# Nginx Benchmarking

**Tool**: ab (Apache Bench), wrk, wrk2

**Description**: HTTP server benchmark tools

**Prerequisites**:
- Nginx server running
- Benchmark tool installed

**Installation (Apache Bench)**:
```bash
# Debian/Ubuntu
apt-get install apache2-utils

# RHEL/CentOS
yum install httpd-tools
```

**Installation (wrk)**:
```bash
# Dependencies
apt-get install build-essential libssl-dev libpcre3-dev zlib1g-dev

# Clone and build
git clone https://github.com/wg/wrk.git
cd wrk
make
make install
```

**Installation (wrk2)**:
```bash
# Dependencies
apt-get install build-essential libssl-dev libpcre3-dev zlib1g-dev libnghttp2-dev

# Clone and build
git clone https://github.com/giltene/wrk2.git
cd wrk2
make
make install
```

## Benchmark Commands (ab)

```bash
# Simple benchmark
ab -n 1000 -c 10 http://localhost:8080/

# Keep-alive
ab -k -n 10000 -c 100 http://localhost:8080/

# With timeout
ab -t 60 -c 100 http://localhost:8080/

# With custom headers
ab -H "Authorization: Bearer token" -n 1000 -c 10 http://localhost:8080/

# With POST data
ab -p post_data.txt -T application/json -n 1000 -c 10 http://localhost:8080/api/data

# With content type
ab -T application/x-www-form-urlencoded -p data.txt -n 1000 -c 10 http://localhost:8080/form

# SSL benchmark
ab -n 1000 -c 10 https://localhost:8443/

# Save results to file
ab -n 10000 -c 100 -g -o results.tsv http://localhost:8080/
```

## Benchmark Commands (wrk)

```bash
# Simple benchmark
wrk -t 60 -c 100 http://localhost:8080/

# Multiple threads
wrk -t 60 -c 100 --threads 12 http://localhost:8080/

# With latency histogram
wrk -t 60 -c 100 --latency http://localhost:8080/

# With script
wrk -t 60 -c 100 -s request.lua http://localhost:8080/
```

## Request Script Example (request.lua)

```lua
request = function()
   local path = "/api/users/" .. math.random(1000)
   wrk.method("GET", path, wrk.headers, nil, body)
   
   local body = '{"id": ' .. math.random(1000) .. '}'
   wrk.method("POST", "/api/data", wrk.headers, nil, body)
end
```

## Benchmark Commands (wrk2)

```bash
# Simple benchmark
wrk2 -t 60 -c 100 -R 4 http://localhost:8080/

# With timeout per request
wrk2 -t 60 -c 100 -L 5s http://localhost:8080/

# With header
wrk2 -H "Authorization: Bearer token" -t 60 -c 100 http://localhost:8080/

# With request body
wrk2 -t 60 -c 100 -s post_data.json http://localhost:8080/api/data
```

## Output Metrics

- Requests per second
- Time taken
- Failed requests
- Latency (min, max, avg, p50, p95, p99)
- Throughput (KB/s)
- Connection time

## Example Output (ab)

```
Server Software:        nginx/1.18.0
Server Hostname:        localhost
Server Port:            8080

Document Path:          /
Document Length:        12345 bytes

Concurrency Level:      100
Time taken for tests:   60.123 seconds
Complete requests:      100000
Failed requests:        0
Total transferred:      1234500000 bytes
HTML transferred:       1234500000 bytes
Requests per second:    1663.50 [#/sec] (mean)
Time per request:       60.123 [ms] (mean)
Time per request:       0.601 [ms] (mean, across all concurrent requests)
Transfer rate:          20145.21 [Kbytes/sec] received
                        10066.27 [Kbytes/sec] size
                        20145.21 [Kbytes/sec] speed
```

## Example Output (wrk)

```
Running 60s test @ http://localhost:8080/
  12 threads and 100 connections
  Thread Stats   Avg      Stdev     Max       +/- Stdev
    Latency     10.50ms    2.50ms   50.00ms    8.00ms
    Req/Sec     833.33     50.00    1000.00    50.00
  600000 requests in 60.00s, 10000.00 req/sec

  Latency Distribution
     50%    9.50ms
     75%   10.50ms
     90%   12.00ms
     99%   20.00ms
```

## Output Parsing

Parse ab (Apache Bench) output:

```bash
# Parse ab output
parse_ab_output() {
    local log_file="$1"
    
    grep "^Requests per second" "$log_file" | \
    sed -E 's/.*:\s*([0-9]+\.[0-9]+).*/\1/' > /tmp/ab_rps.txt
    
    grep "^Time per request" "$log_file" | head -1 | \
    sed -E 's/.*:\s*([0-9]+\.[0-9]+).*/\1/' > /tmp/ab_latency.txt
    
    grep "^Failed requests" "$log_file" | \
    sed -E 's/.*:\s*([0-9]+).*/\1/' > /tmp/ab_failed.txt
    
    grep "^Complete requests" "$log_file" | \
    sed -E 's/.*:\s*([0-9]+).*/\1/' > /tmp/ab_complete.txt
    
    grep "^Time taken for tests" "$log_file" | \
    sed -E 's/.*:\s*([0-9]+\.[0-9]+).*/\1/' > /tmp/ab_duration.txt
}

RPS=$(cat /tmp/ab_rps.txt)
LATENCY=$(cat /tmp/ab_latency.txt)
FAILED=$(cat /tmp/ab_failed.txt)
COMPLETE=$(cat /tmp/ab_complete.txt)
DURATION=$(cat /tmp/ab_duration.txt)
```

Parse wrk output:

```bash
# Parse wrk output
parse_wrk_output() {
    local log_file="$1"
    
    grep "requests in" "$log_file" | \
    sed -E 's/.*in.*s,\s*([0-9]+\.[0-9]+).*req\/sec/\1/' > /tmp/wrk_rps.txt
    
    grep "^  Latency" "$log_file" | \
    sed -E 's/.*Avg\s+([0-9]+\.[0-9]+).*/\1/' > /tmp/wrk_latency_avg.txt
    
    grep "^  Latency" "$log_file" | \
    sed -E 's/.*Max\s+([0-9]+\.[0-9]+).*/\1/' > /tmp/wrk_latency_max.txt
    
    grep "Latency Distribution" -A 4 "$log_file" | grep "50%" | \
    sed -E 's/.*50%\s+([0-9]+\.[0-9]+).*/\1/' > /tmp/wrk_latency_p50.txt
    
    grep "Latency Distribution" -A 4 "$log_file" | grep "99%" | \
    sed -E 's/.*99%\s+([0-9]+\.[0-9]+).*/\1/' > /tmp/wrk_latency_p99.txt
}

RPS=$(cat /tmp/wrk_rps.txt)
LATENCY_AVG=$(cat /tmp/wrk_latency_avg.txt)
LATENCY_P50=$(cat /tmp/wrk_latency_p50.txt)
LATENCY_P99=$(cat /tmp/wrk_latency_p99.txt)
```

**Extracted Metrics (ab)**:

| Metric | Variable | Description |
|--------|----------|-------------|
| RPS | `RPS` | Requests per second |
| Latency | `LATENCY` | Time per request (ms) |
| Failed | `FAILED` | Number of failed requests |
| Complete | `COMPLETE` | Number of complete requests |
| Duration | `DURATION` | Test duration (seconds) |

**Extracted Metrics (wrk)**:

| Metric | Variable | Description |
|--------|----------|-------------|
| RPS | `RPS` | Requests per second |
| Latency Avg | `LATENCY_AVG` | Average latency |
| Latency P50 | `LATENCY_P50` | 50th percentile latency |
| Latency P99 | `LATENCY_P99` | 99th percentile latency |

**Example Parsed Output (ab)**:
```markdown
### Nginx Benchmark Results (ab)

| Metric | Value |
|--------|-------|
| RPS | 1663.50 |
| Latency | 60.123ms |
| Failed | 0 |
| Complete | 100000 |
| Duration | 60.123s |
```

**Example Parsed Output (wrk)**:
```markdown
### Nginx Benchmark Results (wrk)

| Metric | Value |
|--------|-------|
| RPS | 10000.00 |
| Latency Avg | 10.50ms |
| Latency P50 | 9.50ms |
| Latency P99 | 20.00ms |
```
