# Network Optimization Strategies

## TCP Buffer Tuning

### Description
Adjust TCP buffer sizes to optimize network throughput and latency.

### Applicable Bottlenecks
- Network TCP bottleneck (retransmission > 2%, listen drops > 0)
- High latency connections
- Insufficient buffer capacity for high-throughput scenarios

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-tuning.conf

### Commands

**Check current TCP buffer settings**:
```bash
sysctl net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.ipv4.tcp_mem net.core.rmem_max net.core.wmem_max
```

**Set TCP buffer sizes**:
```bash
# Set TCP read/write buffers (min, default, max)
# Values are in bytes
sysctl net.ipv4.tcp_rmem="4096 87380 16777216"
sysctl net.ipv4.tcp_wmem="4096 65536 16777216"

# Set maximum buffer sizes
sysctl net.core.rmem_max=16777216
sysctl net.core.wmem_max=16777216

# Set TCP memory limits (pages, not bytes)
sysctl net.ipv4.tcp_mem="65536 131072 262144"
```

**Permanent configuration**:
```bash
cat << EOF | sudo tee /etc/sysctl.d/99-tuning.conf
# TCP buffer tuning
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_mem = 65536 131072 262144
EOF

sysctl --system
```

**Recommended values by scenario**:
| Scenario | rmem (min/default/max) | wmem (min/default/max) | rmem_max/wmem_max |
|----------|------------------------|------------------------|-------------------|
| General purpose | 4096/87380/6291456 | 4096/65536/4194304 | 8388608/8388608 |
| High throughput | 4096/87380/16777216 | 4096/65536/16777216 | 16777216/16777216 |
| Low latency | 4096/87380/4194304 | 4096/65536/4194304 | 4194304/4194304 |
| High latency (WAN) | 4096/87380/33554432 | 4096/65536/33554432 | 33554432/33554432 |

### Verification
```bash
# Check settings
sysctl net.ipv4.tcp_rmem net.ipv4.tcp_wmem

# Test with iperf3
iperf3 -c <server_ip> -w 1M -l 64K

# Monitor TCP stats
ss -tin
netstat -s | grep -i tcp
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
10-50% improvement in network throughput, reduced latency

---

## TCP Congestion Control

### Description
Change TCP congestion control algorithm to optimize for network conditions.

### Applicable Bottlenecks
- High latency networks
- High packet loss environments
- Need for fair bandwidth allocation

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-tuning.conf

### Commands

**Check available congestion control algorithms**:
```bash
# List available algorithms
sysctl net.ipv4.tcp_available_congestion_control

# Check current algorithm
sysctl net.ipv4.tcp_congestion_control
```

**Set congestion control algorithm**:
```bash
# Set algorithm
sysctl net.ipv4.tcp_congestion_control=bbr

# Permanent configuration
echo 'net.ipv4.tcp_congestion_control = bbr' | sudo tee -a /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
```

**Congestion control algorithms**:
| Algorithm | Description | Best For |
|-----------|-------------|----------|
| cubic | Default, balanced | General purpose, mixed networks |
| bbr | Bandwidth-based | High-throughput, low-latency, modern networks |
| reno | Classic, conservative | Compatibility, older networks |
| htcp | Hybrid | High-speed networks |
| vegas | Delay-based | Low-latency, low-loss networks |
| illinois | Hybrid, adaptive | High-BDP networks |
| highspeed | Modified Reno | High-speed, high-latency |

**Recommended algorithms**:
| Scenario | Recommended Algorithm |
|----------|---------------------|
| General purpose | cubic |
| High throughput, low loss | bbr |
| High latency, low loss | bbr |
| High packet loss | cubic, htcp |
| Data center | bbr, cubic |
| Internet | bbr |

### Verification
```bash
# Check algorithm
sysctl net.ipv4.tcp_congestion_control

# Test with iperf3
iperf3 -c <server_ip> -t 60

# Monitor TCP congestion
ss -tin
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
10-40% improvement in throughput for appropriate networks

---

## TCP Window Scaling and Timestamps

### Description
Enable TCP window scaling and timestamps for high-throughput connections.

### Applicable Bottlenecks
- High bandwidth-delay product (BDP) networks
- Limited throughput on high-latency connections
- Need for window scaling beyond 64KB

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-tuning.conf

### Commands

**Check current settings**:
```bash
sysctl net.ipv4.tcp_window_scaling net.ipv4.tcp_timestamps
```

**Enable TCP window scaling and timestamps**:
```bash
# Enable window scaling
sysctl net.ipv4.tcp_window_scaling=1

# Enable timestamps
sysctl net.ipv4.tcp_timestamps=1

# Permanent configuration
cat << EOF | sudo tee /etc/sysctl.conf
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
EOF

sysctl -p /etc/sysctl.conf
```

**Explanation**:
- **Window scaling**: Allows TCP window > 64KB for high BDP networks
- **Timestamps**: Helps with round-trip time measurement and PAWS (Protect Against Wrapped Sequences)

### Verification
```bash
# Check settings
sysctl net.ipv4.tcp_window_scaling net.ipv4.tcp_timestamps

# Test with iperf3
iperf3 -c <server_ip> -w 4M -l 64K
```

### Risk Level
Low - Standard features, minimal risk

### Expected Impact
10-50% improvement for high-latency, high-bandwidth networks

---

## TCP Fast Open (TFO)

### Description
Enable TCP Fast Open to reduce connection establishment latency.

### Applicable Bottlenecks
- High connection establishment overhead
- Short-lived connections
- HTTP/HTTPS web servers

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-tuning.conf

### Commands

**Check TFO support**:
```bash
# Check if kernel supports TFO
grep -i tcp_fastopen /proc/sys/net/ipv4/

# Check current TFO status
sysctl net.ipv4.tcp_fastopen
```

**Enable TFO**:
```bash
# Enable TFO (3 = server mode)
sysctl net.ipv4.tcp_fastopen=3

# Enable TFO (0 = disabled, 1 = client only, 2 = server only, 3 = both)
sysctl net.ipv4.tcp_fastopen=3

# Enable TFO queue
sysctl net.ipv4.tcp_fastopenq=1024

# Permanent configuration
cat << EOF | sudo tee /etc/sysctl.conf
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fastopenq = 1024
EOF

sysctl -p /etc/sysctl.conf
```

**TFO modes**:
| Mode | Description |
|------|-------------|
| 0 | Disabled |
| 1 | Client mode (outgoing connections) |
| 2 | Server mode (incoming connections) |
| 3 | Both client and server |

**Application support**:
- Nginx: `fastopen on;`
- Apache: mod_spdy/mod_http2
- HAProxy: `tune.http.fastopen` (2.5+)

### Verification
```bash
# Check TFO status
sysctl net.ipv4.tcp_fastopen

# Check TFO queue
ss -tin

# Monitor TFO
netstat -s | grep -i "fastopen"
```

### Risk Level
Low-Medium - Requires application support

### Expected Impact
10-30% reduction in connection latency for supported applications

---

## TCP SYN Cache and Cookies

### Description
Tune SYN cache and SYN cookies to protect against SYN flood attacks.

### Applicable Bottlenecks
- SYN flood attacks
- Connection backlog exhaustion
- Need for DoS protection

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-tuning.conf

### Commands

**Check current settings**:
```bash
sysctl net.ipv4.tcp_max_syn_backlog net.ipv4.tcp_syncookies net.ipv4.tcp_syn_retries net.ipv4.tcp_synack_retries
```

**Tune SYN cache and cookies**:
```bash
# Increase SYN backlog
sysctl net.ipv4.tcp_max_syn_backlog=8192

# Enable SYN cookies (protection against SYN flood)
sysctl net.ipv4.tcp_syncookies=1

# Tune SYN retries
sysctl net.ipv4.tcp_syn_retries=3
sysctl net.ipv4.tcp_synack_retries=3

# Permanent configuration
cat << EOF | sudo tee /etc/sysctl.conf
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
EOF

sysctl -p /etc/sysctl.conf
```

**Parameters**:
| Parameter | Description | Recommended |
|-----------|-------------|-------------|
| tcp_max_syn_backlog | Max SYN requests in backlog | 8192 (high traffic), 1024 (default) |
| tcp_syncookies | Enable SYN cookies | 1 (enabled), 0 (disabled) |
| tcp_syn_retries | Max SYN retransmits | 3-5 (default: 5) |
| tcp_synack_retries | Max SYN-ACK retransmits | 3-5 (default: 5) |

### Verification
```bash
# Check settings
sysctl net.ipv4.tcp_max_syn_backlog net.ipv4.tcp_syncookies

# Monitor SYN queue
ss -s
netstat -s | grep -i syn
```

### Risk Level
Low - Security improvement, minimal risk

### Expected Impact
Better protection against SYN flood attacks, reduced connection failures

---

## TCP Keepalive Tuning

### Description
Adjust TCP keepalive parameters for better connection management.

### Applicable Bottlenecks
- Stale connections consuming resources
- Connection state issues
- Need for connection health monitoring

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-tuning.conf

### Commands

**Check current keepalive settings**:
```bash
sysctl net.ipv4.tcp_keepalive_time net.ipv4.tcp_keepalive_intvl net.ipv4.tcp_keepalive_probes
```

**Set keepalive parameters**:
```bash
# Time before sending keepalive (seconds)
sysctl net.ipv4.tcp_keepalive_time=7200

# Interval between keepalive probes (seconds)
sysctl net.ipv4.tcp_keepalive_intvl=75

# Number of keepalive probes before dropping connection
sysctl net.ipv4.tcp_keepalive_probes=9

# Permanent configuration
cat << EOF | sudo tee /etc/sysctl.conf
net.ipv4.tcp_keepalive_time = 7200
net.ipv4.tcp_keepalive_intvl = 75
net.ipv4.tcp_keepalive_probes = 9
EOF

sysctl -p /etc/sysctl.conf
```

**Keepalive parameters**:
| Parameter | Description | Default | Recommended |
|-----------|-------------|---------|-------------|
| tcp_keepalive_time | Idle time before keepalive (seconds) | 7200 (2h) | 300-7200 |
| tcp_keepalive_intvl | Interval between probes (seconds) | 75 | 10-75 |
| tcp_keepalive_probes | Max probes before timeout | 9 | 5-9 |

**Recommended values by scenario**:
| Scenario | keepalive_time | keepalive_intvl | keepalive_probes |
|----------|---------------|-----------------|------------------|
| Long-lived connections (DB) | 7200 | 75 | 9 |
| Load balancer | 60 | 10 | 3 |
| WebSocket | 300 | 30 | 5 |
| Proxy server | 600 | 30 | 5 |

### Verification
```bash
# Check settings
sysctl net.ipv4.tcp_keepalive_time net.ipv4.tcp_keepalive_intvl net.ipv4.tcp_keepalive_probes

# Monitor keepalive
ss -tin
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
Better connection management, reduced stale connections

---

## TCP FIN and RST Timeouts

### Description
Adjust TCP FIN and RST timeouts for faster connection cleanup.

### Applicable Bottlenecks
- Slow connection teardown
- Connection state buildup
- Need for faster resource cleanup

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-tuning.conf

### Commands

**Check current timeout settings**:
```bash
sysctl net.ipv4.tcp_fin_timeout net.ipv4.tcp_orphan_retries
```

**Set timeout parameters**:
```bash
# Reduce FIN timeout (seconds)
sysctl net.ipv4.tcp_fin_timeout=30

# Set orphan retries
sysctl net.ipv4.tcp_orphan_retries=0

# Permanent configuration
cat << EOF | sudo tee /etc/sysctl.conf
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_orphan_retries = 0
EOF

sysctl -p /etc/sysctl.conf
```

**Parameters**:
| Parameter | Description | Default | Recommended |
|-----------|-------------|---------|-------------|
| tcp_fin_timeout | Time to wait for FIN ACK (seconds) | 60 | 15-30 |
| tcp_orphan_retries | Retries for orphaned sockets | 8 | 0-2 |

### Verification
```bash
# Check settings
sysctl net.ipv4.tcp_fin_timeout net.ipv4.tcp_orphan_retries

# Monitor connections
ss -tin
netstat -an | grep -E "TIME_WAIT|FIN_WAIT"
```

### Risk Level
Low - Faster connection cleanup

### Expected Impact
Faster connection teardown, reduced connection table usage

---

## Connection Tracking Tuning

### Description
Tune connection tracking (nf_conntrack) for better performance under high connection load.

### Applicable Bottlenecks
- Connection tracking table exhaustion
- High connection rates (load balancers, proxies)
- NAT/conntrack performance issues

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-tuning.conf

### Commands

**Check current conntrack settings**:
```bash
sysctl net.netfilter.nf_conntrack_max net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_expect_max
sysctl net.netfilter.nf_conntrack_buckets
```

**Set conntrack parameters**:
```bash
# Increase conntrack table size
sysctl net.netfilter.nf_conntrack_max=1000000

# Increase conntrack buckets (should be <= max/4)
sysctl net.netfilter.nf_conntrack_buckets=262144

# Increase hash size
sysctl net.netfilter.nf_conntrack_hashsize=262144

# Reduce conntrack timeout (seconds)
sysctl net.netfilter.nf_conntrack_generic_timeout=600

# Permanent configuration
cat << EOF | sudo tee /etc/sysctl.conf
net.netfilter.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_buckets = 262144
net.netfilter.nf_conntrack_hashsize = 262144
net.netfilter.nf_conntrack_generic_timeout = 600
EOF

sysctl -p /etc/sysctl.conf
```

**Parameters**:
| Parameter | Description | Default | Recommended |
|-----------|-------------|---------|-------------|
| nf_conntrack_max | Max conntrack entries | 65536 | 262144-1000000 |
| nf_conntrack_buckets | Hash buckets | 16384 | 65536-262144 |
| nf_conntrack_hashsize | Hash size (boot param) | Auto | 65536-262144 |
| nf_conntrack_generic_timeout | Timeout (seconds) | 600 | 300-600 |

**Calculate conntrack_max**:
```bash
# Formula: conntrack_max = total_memory / 16384 (for 64-bit)
# For 16GB: 16777216 / 16384 = 1024
# For 32GB: 33554432 / 16384 = 2048

# More conservative: conntrack_max = total_memory / 32768
# For 16GB: 16777216 / 32784 = 512
```

### Verification
```bash
# Check conntrack usage
sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max

# Monitor conntrack
watch -n 1 'sysctl net.netfilter.nf_conntrack_count'

# Check conntrack entries
conntrack -L | wc -l
```

### Risk Level
Medium - Increased memory usage

### Expected Impact
Better handling of high connection rates, reduced connection drops

---

## TCP TIME_WAIT Reuse

### Description
Enable TCP TIME_WAIT reuse to reduce connection table pressure.

### Applicable Bottlenecks
- Excessive TIME_WAIT connections
- Port exhaustion under high connection rate
- Connection table saturation

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-tuning.conf

### Commands

**Check current settings**:
```bash
sysctl net.ipv4.tcp_tw_reuse net.ipv4.tcp_tw_recycle
```

**Enable TIME_WAIT reuse**:
```bash
# Enable TIME_WAIT reuse
sysctl net.ipv4.tcp_tw_reuse=1

# Disable TIME_WAIT recycle (deprecated, can cause issues)
sysctl net.ipv4.tcp_tw_recycle=0

# Increase local port range
sysctl net.ipv4.ip_local_port_range="1024 65535"

# Permanent configuration
cat << EOF | sudo tee /etc/sysctl.conf
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.ip_local_port_range = 1024 65535
EOF

sysctl -p /etc/sysctl.conf
```

**Parameters**:
| Parameter | Description | Recommended |
|-----------|-------------|-------------|
| tcp_tw_reuse | Reuse TIME_WAIT sockets | 1 (enabled) |
| tcp_tw_recycle | Recycle TIME_WAIT (deprecated) | 0 (disabled) |
| ip_local_port_range | Local port range | 1024-65535 |

### Verification
```bash
# Check settings
sysctl net.ipv4.tcp_tw_reuse net.ipv4.tcp_tw_recycle

# Monitor TIME_WAIT
ss -tan state time-wait | wc -l
netstat -an | grep TIME_WAIT | wc -l
```

### Risk Level
Low - Standard optimization, minimal risk

### Expected Impact
Reduced TIME_WAIT buildup, better connection handling

---

## UDP Tuning

### Description
Tune UDP parameters for UDP-heavy workloads.

### Applicable Bottlenecks
- High UDP traffic
- DNS servers, video streaming
- Real-time applications

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-tuning.conf

### Commands

**Check current UDP settings**:
```bash
sysctl net.core.rmem_max net.core.wmem_max net.ipv4.udp_rmem_min net.ipv4.udp_wmem_min
```

**Set UDP parameters**:
```bash
# Increase UDP buffers
sysctl net.core.rmem_max=134217728
sysctl net.core.wmem_max=134217728

# Set UDP buffer sizes
sysctl net.ipv4.udp_rmem_min=8192
sysctl net.ipv4.udp_wmem_min=8192

# Permanent configuration
cat << EOF | sudo tee /etc/sysctl.conf
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
EOF

sysctl -p /etc/sysctl.conf
```

**Recommended values by scenario**:
| Scenario | rmem_max | wmem_max | udp_rmem_min | udp_wmem_min |
|----------|----------|----------|--------------|--------------|
| DNS | 8388608 | 8388608 | 4096 | 4096 |
| Video streaming | 67108864 | 67108864 | 8192 | 8192 |
| Real-time | 134217728 | 134217728 | 8192 | 8192 |
| VoIP | 8388608 | 8388608 | 4096 | 4096 |

### Verification
```bash
# Check settings
sysctl net.core.rmem_max net.core.wmem_max

# Monitor UDP traffic
netstat -su | grep -i udp
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
Reduced packet loss for UDP-heavy workloads
