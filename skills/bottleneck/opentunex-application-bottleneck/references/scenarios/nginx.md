---
name: nginx-workload
description: Nginx web server workload analysis: request rate, response time, upstream status, SSL metrics. Use for web server performance troubleshooting.
---

# nginx-workload — Nginx Performance Analysis

**Command execution**: all commands for client should be executed via `ssh`, considering the limits of ssh, allow converting commands to bash script and scp to client and execute if needed. ALL DESTRUCTIVE COMMAND SHOULD REQUEST USER'S COMIRMATION.

**Application Detection**:
```bash
ps aux | grep nginx
nginx -v
ss -tlnp | grep -E "nginx"
```

---

## Key Metrics Collection

### Connection and Request Metrics
```bash
# Connection stats
curl http://localhost/nginx_status 2>/dev/null || curl http://localhost/status 2>/dev/null
# Expected output includes:
# Active connections: X
# server accepts handled requests
#   X X X
# Reading: X Writing: X Waiting: X
# Key indicators: active connections > 10000, writing > 5000
# Request rate (calculate from status over time)
# Requests/sec = (current_requests - previous_requests) / time_interval
# Key indicators: declining requests/sec, high rejection rate
```

### Response Time and Latency
```bash
# If custom logging enabled
tail -1000 /var/log/nginx/access.log | awk '{print $(NF-1)}' | sort -n | tail -10
# Calculate percentiles
tail -10000 /var/log/nginx/access.log | awk '{print $(NF-1)}' | sort -n | awk 'BEGIN{c=0} {a[c++]=$1} END{print "p50:", a[int(c*0.5)], "p90:", a[int(c*0.9)], "p99:", a[int(c*0.99)]}'
# Key indicators: p99 > 1s, p90 > 500ms, response time increasing
```

### Upstream Backend Status
```bash
# Check upstream status (if configured)
curl http://localhost/nginx_status 2>/dev/null | grep -i upstream
# Key indicators: upstream errors, slow upstream response, failed connections
# Upstream response time from logs
tail -1000 /var/log/nginx/access.log | grep "upstream_response_time" | awk -F'upstream_response_time=' '{print $2}' | awk '{print $1}' | sort -n | tail -10
# Key indicators: upstream_response_time > 1s, 5xx errors increasing
```

### Worker Processes and Connections
```bash
# Worker process status
ps aux | grep "nginx: worker" | wc -l
# Connections per worker
ps aux | grep "nginx: worker" | awk '{print $2}' | xargs -I {} lsof -p {} | grep TCP | wc -l
# Key indicators: single worker handling > 10000 connections, connection imbalance
```

### SSL/TLS Metrics (if enabled)
```bash
# SSL handshake errors
tail -1000 /var/log/nginx/error.log | grep -i ssl | grep -i error | wc -l
# SSL renegotiation
tail -1000 /var/log/nginx/error.log | grep -i "ssl renegotiate"
# Key indicators: high SSL errors, SSL handshake latency > 100ms
```

---

## Bottleneck Identification

| Category | Key Metrics | Thresholds | Collection |
|----------|-------------|------------|------------|
| Connection Pool | Active connections, Writing state | > 10000, > 5000 | nginx_status |
| Request Rate | requests/sec | declining, unexpected drops | nginx_status |
| Response Time | p50, p90, p99 latency | p90 > 500ms, p99 > 1s | access.log |
| Backend Latency | upstream_response_time | > 1s | access.log |
| Backend Errors | 5xx errors, upstream failures | > 1% of requests | access.log, error.log |
| Worker Saturation | connections per worker | > 10000 | ps, lsof |
| SSL Overhead | SSL handshake errors, latency | errors > 1%, latency > 100ms | error.log |

---

## Diagnostic Commands

```bash
# Nginx status endpoint (if configured)
curl http://localhost/nginx_status
# Error log analysis
tail -100 /var/log/nginx/error.log
tail -1000 /var/log/nginx/error.log | grep -E "crit|error|alert"
# Access log analysis
tail -10000 /var/log/nginx/access.log | awk '{print $9}' | sort | uniq -c | sort -rn
# Slow requests
tail -10000 /var/log/nginx/access.log | awk '$(NF-1) > 1.0' | tail -20
# Worker processes
ps aux | grep nginx
# Network connections
ss -tnp | grep nginx
# Nginx configuration test
nginx -t
# Nginx reload status
kill -HUP $(cat /var/run/nginx.pid)
```

---

## Advanced Tools

```bash
# nginx-amplify (commercial monitoring)
# New Relic (commercial APM)
# Datadog (commercial monitoring)
# Prometheus + Grafana (open source)
# Grafana dashboards for Nginx metrics
# Log analysis with ELK stack
```

---

## Common Bottleneck Patterns

1. **Connection exhaustion**: Active connections near limit, increasing Waiting state, connection reset errors
2. **Backend slow down**: High upstream_response_time, 502/504 errors, backend unresponsive
3. **Disk I/O pressure**: Access log writes slow, disk utilization high, fsync latency
4. **SSL/TLS overhead**: High CPU usage during SSL handshake, SSL errors, TLS 1.3 renegotiation issues
5. **Worker imbalance**: Some workers handling most connections, others idle, connection distribution uneven
6. **Memory pressure**: High RSS for worker processes, OutOfMemory, swap usage

---

## Output Template

```markdown
## Nginx Workload Analysis

### Connection Status
- Active connections: X
- Reading: X, Writing: X, Waiting: X
- Requests/sec: X

### Response Time
- p50 latency: Xms
- p90 latency: Xms
- p99 latency: Xms

### HTTP Status Codes
| Code | Count | Percentage |
|------|-------|------------|
| 2xx | X | X% |
| 3xx | X | X% |
| 4xx | X | X% |
| 5xx | X | X% |

### Upstream Status
- Upstream servers: X
- Average upstream response time: Xms
- Upstream errors: X (X% of requests)

### Worker Processes
- Worker count: X
- Connections per worker: X (avg)
- Worker imbalance: [if any]

### Top Bottlenecks
| Component | Issue | Evidence | Impact |
|-----------|-------|----------|--------|
```
