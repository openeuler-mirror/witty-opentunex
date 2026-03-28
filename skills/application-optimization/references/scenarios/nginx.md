---
name: nginx-optimization
description: Nginx performance optimization with worker processes, caching, SSL, keepalive, and configuration management.
---

# Nginx Performance Optimization

This skill provides comprehensive Nginx performance optimization based on system-level bottleneck analysis and application-specific metrics.

---

## Pre-requisites

- Nginx installed and running
- Sufficient memory for configuration changes
- Backup of current configuration
- Monitoring tools installed (optional): nginx-amplify, prometheus-nginx-exporter

---

## Configuration File Detection

**Common Nginx Configuration Paths**:

| Path | Distribution | Notes |
|------|---------------|--------|
| /etc/nginx/nginx.conf | Debian/Ubuntu | Main config, includes conf.d |
| /etc/nginx/conf.d/*.conf | Debian/Ubuntu | Additional configs |
| /usr/local/nginx/conf/nginx.conf | Source install | Custom install |
| /etc/nginx/sites-enabled/*.conf | Debian/Ubuntu | Site-specific configs |
| /etc/nginx/sites-available/*.conf | Debian/Ubuntu | Available site configs |

**Detection Commands**:

```bash
# Detect Nginx configuration file
for path in /etc/nginx/nginx.conf /usr/local/nginx/conf/nginx.conf; do
  if [ -f "$path" ]; then
    echo "Found Nginx config: $path"
  fi
done

# Check Nginx version and installation type
nginx -v
nginx -V

# Check Nginx configuration syntax
nginx -t

# Check running Nginx processes
ps aux | grep nginx
```

---

## Configuration Backup

```bash
# Backup Nginx configuration
BACKUP_DIR="/opt/optimization-backup/nginx_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup configuration files
cp /etc/nginx/nginx.conf $BACKUP_DIR/nginx.conf.backup
cp -r /etc/nginx/conf.d $BACKUP_DIR/conf.d.backup 2>/dev/null || true
cp -r /etc/nginx/sites-enabled $BACKUP_DIR/sites-enabled.backup 2>/dev/null || true
cp -r /etc/nginx/sites-available $BACKUP_DIR/sites-available.backup 2>/dev/null || true

# Create backup manifest
cat > $BACKUP_DIR/backup_manifest.txt << EOF
Nginx Backup
Date: $(date)
Nginx Version: $(nginx -v 2>&1)
Configuration Files:
  - nginx.conf
  - conf.d/
  - sites-enabled/
  - sites-available/
EOF
```

---

## Bottleneck Analysis

Based on system-level bottleneck analysis, identify Nginx-specific bottlenecks:

### Worker Process Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Insufficient workers | High worker load, connection drops | Critical | Increase worker_processes |
| Worker exhaustion | All workers busy, backlog | High | Increase worker_connections |
| CPU saturation | High CPU usage per worker | Medium | Tune worker_processes, use caching |

### Connection Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Connection limit reached | Too many connections error | Critical | Increase worker_connections, backlog |
| Slow connections | High keepalive timeout | Medium | Tune keepalive_timeout |
| Connection reuse | Low connection reuse rate | Medium | Enable keepalive |

### I/O Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Disk I/O bottleneck | High disk usage, slow file serving | High | Enable sendfile, aio, use SSD |
| Buffer bloat | High buffer usage | Medium | Tune send buffers |
| File descriptor limit | Too many open files error | Critical | Increase worker_rlimit_nofile |

### Network Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| TCP backlog overflow | High SYN queue drops | High | Increase backlog, enable tcp_fastopen |
| Slow SSL handshake | High SSL handshake time | High | Enable SSL session cache, HTTP/2 |
| Network latency | High response time | Medium | Enable tcp_nodelay, tcp_nopush |

### Caching Bottlenecks

| Bottleneck | Evidence | Severity | Optimization |
|------------|-----------|-----------|----------------|
| Cache miss rate | High cache miss ratio | High | Increase cache size, tune cache keys |
| Cache eviction | High cache eviction rate | Medium | Increase cache size, tune cache manager |
| Cache hit ratio | Low cache hit ratio | Medium | Tune cache parameters |

---

## Optimization Recommendations

### 1. Worker Process Optimization

**Objective**: Optimize worker processes for better CPU utilization.

**Current Value Check**:
```bash
grep -E "worker_processes|worker_connections|worker_rlimit_nofile" /etc/nginx/nginx.conf
```

**Recommended Configuration**:
```nginx
# Worker processes (auto = number of CPU cores)
worker_processes auto;

# Worker connections per worker (1024-4096)
worker_connections 4096;

# Maximum open file descriptors
worker_rlimit_nofile 65535;

# Worker priority (-20 to 20, higher is lower priority)
worker_priority -5;
```

**Calculation**:
```
worker_processes = number of CPU cores (or auto)
worker_connections = 1024-4096 (depends on memory)
max_connections = worker_processes * worker_connections

Example: 4 cores * 4096 = 16384 connections
```

**Verification**:
```bash
# Check worker processes
ps aux | grep nginx | grep worker | wc -l

# Check active connections
nginx -s status 2>/dev/null || echo "Need stub_status module"

# Check open file descriptors
ls -la /proc/<pid>/fd | wc -l
```

**Risk**: Low-Medium - Increased memory usage per worker

**Expected Impact**: 20-40% improvement in connection handling

---

### 2. Event Processing Optimization

**Objective**: Optimize event processing model for better performance.

**Current Value Check**:
```bash
grep -E "use|multi_accept|accept_mutex" /etc/nginx/nginx.conf
```

**Recommended Configuration**:
```nginx
# Event model (epoll for Linux)
use epoll;

# Accept multiple connections at once
multi_accept on;

# Accept mutex (off for better performance, on for stability)
accept_mutex off;

# Connection processing method (kqueue for BSD, epoll for Linux)
# use epoll; # (already set above)
```

**Verification**:
```bash
# Check event processing
nginx -V 2>&1 | grep -E "epoll|kqueue|eventport"

# Check connection rate
ab -n 1000 -c 100 http://localhost/
```

**Risk**: Low

**Expected Impact**: 10-20% improvement in connection handling

---

### 3. File I/O Optimization

**Objective**: Optimize file I/O operations for better performance.

**Current Value Check**:
```bash
grep -E "sendfile|tcp_nopush|tcp_nodelay|aio|directio" /etc/nginx/nginx.conf
```

**Recommended Configuration**:
```nginx
# Enable sendfile (zero-copy file transfer)
sendfile on;

# TCP options
tcp_nopush on;   # Send headers and data in one packet
tcp_nodelay on;   # Disable Nagle's algorithm for faster data transfer

# Asynchronous I/O (Linux with AIO support)
aio on;
directio 4m;    # Direct I/O for files > 4MB

# Output buffer size
output_buffers 1 64k;
```

**Verification**:
```bash
# Check file transfer speed
dd if=/dev/zero of=/var/www/html/testfile bs=1M count=100
ab -n 1000 -c 10 http://localhost/testfile

# Check I/O usage
iostat -x 1 5
```

**Risk**: Low

**Expected Impact**: 15-30% improvement in file serving performance

---

### 4. Keepalive Optimization

**Objective**: Optimize HTTP keepalive for better connection reuse.

**Current Value Check**:
```bash
grep -E "keepalive_timeout|keepalive_requests" /etc/nginx/nginx.conf
```

**Recommended Configuration**:
```nginx
# Keepalive timeout (seconds)
keepalive_timeout 65;

# Keepalive requests per connection
keepalive_requests 1000;

# Enable HTTP keepalive
http {
    keepalive on;
    keepalive_timeout 65;
    keepalive_requests 1000;
}

# Upstream keepalive
upstream backend {
    server backend1.example.com;
    server backend2.example.com;
    keepalive 32;
    keepalive_timeout 60s;
    keepalive_requests 1000;
}
```

**Verification**:
```bash
# Check active connections
curl -I http://localhost/

# Check keepalive reuse rate
# Use nginx stub_status module
# curl http://localhost/nginx_status
```

**Risk**: Low

**Expected Impact**: 10-25% reduction in connection overhead

---

### 5. Buffer Optimization

**Objective**: Optimize buffers for better memory management.

**Current Value Check**:
```bash
grep -E "client_body_buffer_size|client_header_buffer_size|large_client_header_buffers" /etc/nginx/nginx.conf
```

**Recommended Configuration**:
```nginx
http {
    # Client body buffer size
    client_body_buffer_size 128k;

    # Client header buffer size
    client_header_buffer_size 1k;

    # Large client header buffers (number size)
    large_client_header_buffers 4 16k;

    # Output buffer size
    output_buffers 1 64k;

    # Client body timeout
    client_body_timeout 12;

    # Client header timeout
    client_header_timeout 12;

    # Send timeout
    send_timeout 10;

    # Keepalive timeout
    keepalive_timeout 65;

    # Client max body size
    client_max_body_size 10m;
}
```

**Verification**:
```bash
# Check buffer usage
nginx -s status 2>/dev/null | grep -E "reading|writing|waiting"

# Check buffer overflow
grep -i "upstream sent too big header" /var/log/nginx/error.log
```

**Risk**: Medium - Increased memory usage

**Expected Impact**: 10-20% improvement in buffer handling

---

### 6. Gzip Compression Optimization

**Objective**: Enable gzip compression for better bandwidth usage.

**Current Value Check**:
```bash
grep -E "gzip|gzip_types|gzip_comp_level" /etc/nginx/nginx.conf
```

**Recommended Configuration**:
```nginx
http {
    # Enable gzip compression
    gzip on;

    # Compression level (1-9, 1 is fastest, 9 is best compression)
    gzip_comp_level 6;

    # Minimum file size to compress (in bytes)
    gzip_min_length 1024;

    # HTTP version
    gzip_http_version 1.1;

    # Buffer size
    gzip_buffers 16 8k;

    # MIME types to compress
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/x-javascript
        application/xml
        application/xml+rss
        application/xhtml+xml
        image/svg+xml;

    # Disable gzip for IE6
    gzip_disable "msie6";

    # Proxied requests
    gzip_proxied any;
}
```

**Verification**:
```bash
# Check if gzip is enabled
curl -I -H "Accept-Encoding: gzip" http://localhost/

# Check compression ratio
for file in /var/www/html/*.{html,css,js}; do
  original_size=$(stat -c%s "$file")
  compressed_size=$(curl -s -H "Accept-Encoding: gzip" http://localhost/$(basename "$file") | wc -c)
  ratio=$(echo "scale=2; (1 - $compressed_size/$original_size) * 100" | bc)
  echo "$file: $ratio% compression"
done
```

**Risk**: Low - Slight CPU overhead for compression

**Expected Impact**: 30-60% reduction in bandwidth usage

---

### 7. Caching Optimization

**Objective**: Enable caching for better performance.

**Current Value Check**:
```bash
grep -E "proxy_cache|fastcgi_cache|open_file_cache" /etc/nginx/nginx.conf
```

**Recommended Configuration**:

**Proxy Cache**:
```nginx
http {
    # Proxy cache path and size
    proxy_cache_path /var/cache/nginx/proxy levels=1:2 keys_zone=proxy_cache:100m max_size=1g inactive=60m use_temp_path=off;

    # Proxy cache settings
    proxy_cache proxy_cache;
    proxy_cache_valid 200 302 10m;
    proxy_cache_valid 404 1m;
    proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;

    # Proxy cache bypass
    proxy_cache_bypass $http_pragma $http_authorization;

    # Proxy cache key
    proxy_cache_key "$scheme$request_method$host$request_uri";

    # Don't cache POST requests
    proxy_no_cache $request_method = POST;
}

server {
    location / {
        proxy_pass http://backend;
        proxy_cache proxy_cache;
        add_header X-Cache-Status $upstream_cache_status;
    }
}
```

**FastCGI Cache**:
```nginx
http {
    # FastCGI cache path and size
    fastcgi_cache_path /var/cache/nginx/fastcgi levels=1:2 keys_zone=fastcgi_cache:100m max_size=1g inactive=60m;

    # FastCGI cache settings
    fastcgi_cache fastcgi_cache;
    fastcgi_cache_valid 200 302 10m;
    fastcgi_cache_valid 404 1m;
    fastcgi_cache_use_stale error timeout updating;

    # FastCGI cache bypass
    fastcgi_cache_bypass $request_method = POST;

    # FastCGI cache key
    fastcgi_cache_key "$scheme$request_method$host$request_uri";
}

server {
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm.sock;
        fastcgi_cache fastcgi_cache;
        add_header X-Cache-Status $upstream_cache_status;
    }
}
```

**Open File Cache**:
```nginx
http {
    # Open file cache
    open_file_cache max=200000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;

    # Sendfile cache
    sendfile on;
    tcp_nopush on;
}
```

**Verification**:
```bash
# Check cache status
ls -lh /var/cache/nginx/proxy/
ls -lh /var/cache/nginx/fastcgi/

# Check cache hit rate
grep "X-Cache-Status: HIT" /var/log/nginx/access.log | wc -l
grep "X-Cache-Status: MISS" /var/log/nginx/access.log | wc -l
```

**Risk**: Medium - Increased memory and disk usage

**Expected Impact**: 30-70% reduction in backend load

---

### 8. SSL/TLS Optimization

**Objective**: Optimize SSL/TLS for better security and performance.

**Current Value Check**:
```bash
grep -E "ssl_certificate|ssl_protocols|ssl_ciphers|ssl_session_cache" /etc/nginx/nginx.conf
```

**Recommended Configuration**:
```nginx
server {
    listen 443 ssl http2;

    # SSL certificates
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    # SSL protocols (disable SSLv2 and SSLv3)
    ssl_protocols TLSv1.2 TLSv1.3;

    # SSL ciphers (strong ciphers only)
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;

    # SSL session cache
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # SSL session tickets
    ssl_session_tickets off;

    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/nginx/ssl/chain.pem;

    # SSL buffer size
    ssl_buffer_size 4k;

    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
}
```

**Verification**:
```bash
# Check SSL configuration
openssl s_client -connect localhost:443 -tls1_2
openssl s_client -connect localhost:443 -tls1_3

# Test SSL performance
ab -n 1000 -c 10 -H "Accept-Encoding: gzip" https://localhost/

# Check SSL session cache
openssl s_client -connect localhost:443 -reconnect 2>&1 | grep "Session-ID"
```

**Risk**: Low-Medium - Slight performance overhead for SSL

**Expected Impact**: 10-20% improvement in SSL handshake time

---

### 9. Logging Optimization

**Objective**: Optimize logging for better performance and disk usage.

**Current Value Check**:
```bash
grep -E "access_log|error_log|log_format" /etc/nginx/nginx.conf
```

**Recommended Configuration**:
```nginx
http {
    # Custom log format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

    # Access log with buffer
    access_log /var/log/nginx/access.log main buffer=32k flush=5s;

    # Error log
    error_log /var/log/nginx/error.log warn;

    # Disable access log for specific locations
    location = /favicon.ico {
        access_log off;
        log_not_found off;
    }

    location = /robots.txt {
        access_log off;
        log_not_found off;
    }
}
```

**Verification**:
```bash
# Check log file size
ls -lh /var/log/nginx/access.log
ls -lh /var/log/nginx/error.log

# Check log rate
tail -f /var/log/nginx/access.log
```

**Risk**: Low

**Expected Impact**: 10-20% reduction in disk I/O for logging

---

### 10. Rate Limiting Optimization

**Objective**: Enable rate limiting for better DDoS protection.

**Recommended Configuration**:
```nginx
http {
    # Rate limiting zone
    limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;

    # Connection limiting zone
    limit_conn_zone $binary_remote_addr zone=addr:10m;

    server {
        # Rate limit
        limit_req zone=one burst=20 nodelay;

        # Connection limit
        limit_conn addr 10;

        # Rate limit status
        limit_req_status 429;
        limit_conn_status 429;
    }
}
```

**Verification**:
```bash
# Test rate limiting
ab -n 1000 -c 20 http://localhost/

# Check for 429 responses
grep "429" /var/log/nginx/access.log
```

**Risk**: Low - May block legitimate requests

**Expected Impact**: Better DDoS protection

---

## Optimization Procedure

### Step 1: Pre-Optimization Baseline

```bash
# Collect current performance metrics
ab -n 1000 -c 10 http://localhost/ > /tmp/nginx_baseline_before.txt

# Check current configuration
nginx -t

# Check active connections
curl http://localhost/nginx_status 2>/dev/null || echo "Need stub_status"

# Record timestamp
date > /tmp/nginx_baseline_timestamp.txt
```

### Step 2: Apply Configuration Changes

```bash
# Create optimized configuration
cat > /etc/nginx/nginx.conf << EOF
user nginx;
worker_processes auto;
worker_rlimit_nofile 65535;

error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
    accept_mutex off;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time';

    access_log /var/log/nginx/access.log main buffer=32k flush=5s;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;

    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;
    client_max_body_size 10m;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss;

    # Add your server blocks here
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

# Test configuration
nginx -t

# Reload Nginx
systemctl reload nginx

# Verify Nginx running
systemctl status nginx
curl -I http://localhost/
```

### Step 3: Post-Optimization Verification

```bash
# Collect new performance metrics
ab -n 1000 -c 10 http://localhost/ > /tmp/nginx_baseline_after.txt

# Compare results
echo "=== Before ==="
grep "Requests per second" /tmp/nginx_baseline_before.txt
grep "Time per request" /tmp/nginx_baseline_before.txt

echo "=== After ==="
grep "Requests per second" /tmp/nginx_baseline_after.txt
grep "Time per request" /tmp/nginx_baseline_after.txt

# Check configuration
nginx -t
```

### Step 4: Performance Comparison

```bash
# Compare requests per second
before=$(grep "Requests per second" /tmp/nginx_baseline_before.txt | awk '{print $4}')
after=$(grep "Requests per second" /tmp/nginx_baseline_after.txt | awk '{print $4}')
improvement=$(echo "scale=2; (($after - $before) / $before) * 100" | bc)
echo "Improvement: $improvement%"

# Compare response time
before_time=$(grep "Time per request" /tmp/nginx_baseline_before.txt | awk '{print $4}')
after_time=$(grep "Time per request" /tmp/nginx_baseline_after.txt | awk '{print $4}')
improvement_time=$(echo "scale=2; (($before_time - $after_time) / $before_time) * 100" | bc)
echo "Response time improvement: $improvement_time%"
```

---

## Monitoring and Maintenance

### Key Metrics to Monitor

```bash
# Check active connections
curl http://localhost/nginx_status 2>/dev/null | grep "Active connections"

# Check request rate
curl http://localhost/nginx_status 2>/dev/null | grep "accepts"

# Check worker status
ps aux | grep nginx | grep worker

# Check SSL handshake time
openssl s_client -connect localhost:443 -tls1_2 -connect-timeout 5

# Check cache hit rate
grep "X-Cache-Status: HIT" /var/log/nginx/access.log | wc -l
grep "X-Cache-Status: MISS" /var/log/nginx/access.log | wc -l
```

### Recommended Tools

- **nginx-amplify**: Nginx monitoring and analytics
- **prometheus-nginx-exporter**: Prometheus metrics exporter
- **nginx-vts-exporter**: Virtual host traffic status exporter
- **goaccess**: Real-time web log analyzer

---

## Rollback Procedure

```bash
# Restore backup configuration
cp /opt/optimization-backup/nginx_*/nginx.conf.backup /etc/nginx/nginx.conf
cp -r /opt/optimization-backup/nginx_*/conf.d.backup/* /etc/nginx/conf.d/
cp -r /opt/optimization-backup/nginx_*/sites-enabled.backup/* /etc/nginx/sites-enabled/

# Test configuration
nginx -t

# Reload Nginx
systemctl reload nginx

# Verify Nginx running
systemctl status nginx
curl -I http://localhost/
```

---

## Common Issues and Solutions

### Issue 1: Nginx won't start after configuration change
**Solution**: Check error log: `tail -f /var/log/nginx/error.log`

### Issue 2: 502 Bad Gateway errors
**Solution**: Check upstream server, increase proxy timeouts

### Issue 3: High CPU usage
**Solution**: Reduce worker_processes, enable caching, check for slow queries

### Issue 4: Connection timeout
**Solution**: Increase keepalive_timeout, check network connectivity

### Issue 5: SSL handshake failures
**Solution**: Check SSL certificates, verify cipher suite compatibility

---

## Additional Resources

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Nginx Performance Tuning](https://www.nginx.com/blog/tuning-nginx/)
- [Nginx Wiki](https://www.nginx.com/resources/wiki/)
