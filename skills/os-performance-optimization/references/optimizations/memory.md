# Memory Optimization Strategies

## Swappiness Tuning

### Description
Adjust the kernel's tendency to swap (vm.swappiness) to balance memory pressure vs swap usage.

### Applicable Bottlenecks
- Memory Pressure (SwapUsed > 50%, majflt/s > 1000)
- Excessive page swapping
- Poor response time due to swap thrashing

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-optimization.conf

### Commands

**Check current swappiness**:
```bash
cat /proc/sys/vm/swappiness
sysctl vm.swappiness
```

**Set swappiness**:
```bash
# Immediate change
sysctl vm.swappiness=10

# Permanent change
echo 'vm.swappiness = 10' | sudo tee -a /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
```

**Swappiness values**:
| Value | Behavior | Use Case |
|-------|----------|----------|
| 0-10 | Aggressively avoid swap | Database servers, low-latency apps |
| 10-30 | Low swap preference | General servers, workstations |
| 60 | Default (Ubuntu) | Default Ubuntu configuration |
| 100 | Aggressively use swap | Desktop systems with limited RAM |

### Verification
```bash
# Check swappiness
cat /proc/sys/vm/swappiness

# Monitor swap usage
watch -n 1 'free -h; cat /proc/vmstat | grep pswpin | head -1; cat /proc/vmstat | grep pswpout | head -1'

# Check page fault rate
pidstat -r 1 5
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
5-20% improvement for memory-bound workloads, reduced swap thrashing

---

## Dirty Page Tuning

### Description
Adjust dirty page parameters (vm.dirty_ratio, vm.dirty_background_ratio) to optimize write performance.

### Applicable Bottlenecks
- Disk I/O bottleneck with high write traffic
- Inconsistent write latency
- I/O spikes during background writeback

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-optimization.conf

### Commands

**Check current dirty page settings**:
```bash
sysctl vm.dirty_ratio vm.dirty_background_ratio vm.dirty_background_bytes vm.dirty_bytes vm.dirty_expire_centisecs vm.dirty_writeback_centisecs
```

**Set dirty page parameters**:
```bash
# Immediate changes
sysctl vm.dirty_ratio=15
sysctl vm.dirty_background_ratio=5
sysctl vm.dirty_expire_centisecs=3000
sysctl vm.dirty_writeback_centisecs=500

# Permanent changes
cat << EOF | sudo tee -a /etc/sysctl.conf
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
EOF

sysctl -p /etc/sysctl.conf
```

**Parameters**:
| Parameter | Description | Default | Recommended |
|-----------|-------------|---------|-------------|
| vm.dirty_ratio | % of RAM when processes start writing themselves | 30 | 10-15 |
| vm.dirty_background_ratio | % of RAM when background writeback starts | 10 | 3-5 |
| vm.dirty_expire_centisecs | How long dirty data can stay in memory | 3000 (30s) | 3000-6000 |
| vm.dirty_writeback_centisecs | How often background writeback runs | 500 (5s) | 500-1000 |

### Verification
```bash
# Check parameters
sysctl vm.dirty_ratio vm.dirty_background_ratio

# Monitor dirty pages
grep -A 5 Dirty /proc/meminfo
watch -n 1 'grep Dirty /proc/meminfo'

# Monitor writeback
iostat -x 1 5
```

### Risk Level
Low-Medium - Can affect write performance and durability

### Expected Impact
10-30% improvement in write throughput, more consistent latency

---

## VFS Cache Pressure Tuning

### Description
Adjust vm.vfs_cache_pressure to control the kernel's tendency to reclaim inode and dentry cache.

### Applicable Bottlenecks
- High file system metadata operations
- Inconsistent file access performance
- Excessive cache thrashing

### Configuration Files
- /etc/sysctl.conf
- /etc/sysctl.d/99-optimization.conf

### Commands

**Check current vfs cache pressure**:
```bash
cat /proc/sys/vm/vfs_cache_pressure
sysctl vm.vfs_cache_pressure
```

**Set vfs cache pressure**:
```bash
# Immediate change
sysctl vm.vfs_cache_pressure=50

# Permanent change
echo 'vm.vfs_cache_pressure = 50' | sudo tee -a /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
```

**vfs_cache_pressure values**:
| Value | Behavior | Use Case |
|-------|----------|----------|
| 1-50 | Keep more inode/dentry cache | File servers, NFS servers |
| 100 | Default | Default behavior |
| >100 | More aggressive reclaim | Memory-constrained systems |

### Verification
```bash
# Check vfs cache pressure
cat /proc/sys/vm/vfs_cache_pressure

# Monitor cache usage
grep -E "dentry|inode" /proc/meminfo
watch -n 1 'grep -E "dentry|inode" /proc/meminfo'

# Monitor slab cache
slabtop
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
5-15% improvement for file-intensive workloads

---

## Transparent Huge Pages (THP) Tuning

### Description
Optimize Transparent Huge Pages for memory-intensive workloads.

### Applicable Bottlenecks
- Memory page table walk overhead
- Large memory workloads
- Database performance

### Configuration Files
- /sys/kernel/mm/transparent_hugepage/enabled
- /sys/kernel/mm/transparent_hugepage/defrag

### Commands

**Check current THP status**:
```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
cat /sys/kernel/mm/transparent_hugepage/defrag
```

**Disable THP**:
```bash
# Disable THP immediately
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Disable THP permanently
echo 'never > /sys/kernel/mm/transparent_hugepage/enabled' | sudo tee -a /etc/rc.local
echo 'never > /sys/kernel/mm/transparent_hugepage/defrag' | sudo tee -a /etc/rc.local
```

**Enable THP**:
```bash
# Enable THP immediately
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Enable THP with madvise
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
```

**THP options**:
| Value | Description |
|-------|-------------|
| always | Always use huge pages |
| never | Never use huge pages |
| madvise | Use huge pages only when explicitly requested |

### Verification
```bash
# Check THP status
cat /sys/kernel/mm/transparent_hugepage/enabled

# Check huge page usage
grep -i huge /proc/meminfo

# Monitor page fault behavior
pidstat -r 1 5
```

### Risk Level
Low-Medium - Can increase memory usage, may cause performance regression for some workloads

### Expected Impact
5-20% improvement for large memory workloads, 5-10% regression for small random access workloads

---

## Huge Pages Configuration

### Description
Configure static huge pages for memory-intensive applications like databases.

### Applicable Bottlenecks
- Large memory workloads with high page table overhead
- Database performance (Oracle, PostgreSQL, MySQL)
- Virtualization performance

### Configuration Files
- /etc/sysctl.conf
- /proc/sys/vm/nr_hugepages
- /proc/meminfo

### Commands

**Check current huge pages**:
```bash
cat /proc/sys/vm/nr_hugepages
grep -i huge /proc/meminfo
```

**Calculate required huge pages**:
```bash
# For 2MB huge pages
# Required huge pages = Total memory needed / 2MB
# Example: 8GB database = 8192MB / 2MB = 4096 huge pages

# Calculate based on SGA size (Oracle)
# Huge pages = SGA size / huge page size
```

**Set huge pages**:
```bash
# Set number of huge pages (requires root)
echo 4096 | sudo tee /proc/sys/vm/nr_hugepages

# Permanent configuration
echo 'vm.nr_hugepages = 4096' | sudo tee -a /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
```

**Configure user limit**:
```bash
# Add to /etc/security/limits.conf
* soft memlock 8589934592
* hard memlock 8589934592

# For specific user
oracle soft memlock 8589934592
oracle hard memlock 8589934592
```

**Oracle specific configuration**:
```bash
# Set MEMORY_TARGET/SGA_TARGET to use huge pages
# Add to /etc/sysctl.conf
vm.nr_hugepages = 4096
vm.hugetlb_shm_group = 1001

# Add to /etc/security/limits.conf
oracle soft memlock 8589934592
oracle hard memlock 8589934592

# Set shmmax and shmall
echo 'kernel.shmmax = 8589934592' | sudo tee -a /etc/sysctl.conf
echo 'kernel.shmall = 2097152' | sudo tee -a /etc/sysctl.conf
```

**MySQL specific configuration**:
```bash
# Add to my.cnf
[mysqld]
large_pages
innodb_buffer_pool_size = 4G

# Preallocate huge pages
numactl --interleave=all /usr/sbin/mysqld --user=mysql
```

### Verification
```bash
# Check huge page usage
grep -i huge /proc/meminfo

# Check process huge page usage
cat /proc/<PID>/smaps | grep -i huge

# Monitor huge page allocation
watch -n 1 'grep -i huge /proc/meminfo'
```

### Risk Level
Medium - Can cause memory allocation issues if not properly configured

### Expected Impact
10-30% improvement for database workloads

---

## Memory Overcommit Tuning

### Description
Adjust memory overcommit behavior to balance memory allocation vs out-of-memory (OOM) risk.

### Applicable Bottlenecks
- OOM kills under memory pressure
- Memory allocation failures
- Over-allocation by applications

### Configuration Files
- /proc/sys/vm/overcommit_memory
- /proc/sys/vm/overcommit_ratio
- /etc/sysctl.conf

### Commands

**Check current overcommit settings**:
```bash
cat /proc/sys/vm/overcommit_memory
cat /proc/sys/vm/overcommit_ratio
sysctl vm.overcommit_memory vm.overcommit_ratio
```

**Set overcommit behavior**:
```bash
# Disable overcommit (heuristic)
echo 0 | sudo tee /proc/sys/vm/overcommit_memory

# Enable overcommit (always allow)
echo 1 | sudo tee /proc/sys/vm/overcommit_memory

# Enable overcommit with ratio
echo 2 | sudo tee /proc/sys/vm/overcommit_memory
echo 80 | sudo tee /proc/sys/vm/overcommit_ratio

# Permanent configuration
cat << EOF | sudo tee -a /etc/sysctl.conf
vm.overcommit_memory = 2
vm.overcommit_ratio = 80
EOF

sysctl -p /etc/sysctl.conf
```

**Overcommit modes**:
| Mode | Description | Use Case |
|------|-------------|----------|
| 0 | Heuristic overcommit (default) | General purpose |
| 1 | Always overcommit | Development, testing |
| 2 | Strict accounting, no overcommit | Production, critical systems |

**Calculate overcommit ratio**:
```bash
# Recommended ratio = (Total RAM + Swap) * percentage / 100
# Example: 16GB RAM + 4GB Swap = 20GB
# Ratio 80 = 16GB allocatable (RAM + 0% Swap)

# Formula: ratio = (RAM + Swap * 0) / Total RAM * 100
```

### Verification
```bash
# Check overcommit settings
cat /proc/sys/vm/overcommit_memory
cat /proc/sys/vm/overcommit_ratio

# Check commit ratio
cat /proc/meminfo | grep -i commit

# Monitor OOM events
dmesg | grep -i "out of memory"
journalctl | grep -i "out of memory"
```

### Risk Level
Medium - Can cause application failures if too restrictive

### Expected Impact
Reduced OOM kills, more predictable memory behavior

---

## Page Cache Tuning

### Description
Adjust page cache limits to balance caching vs memory availability.

### Applicable Bottlenecks
- Memory pressure due to excessive page cache
- Inconsistent cache performance
- Cache thrashing

### Configuration Files
- /proc/sys/vm/pagecache_limit
- /proc/sys/vm/min_free_kbytes
- /etc/sysctl.conf

### Commands

**Check current page cache settings**:
```bash
cat /proc/sys/vm/pagecache_limit 2>/dev/null || echo "Not available"
cat /proc/sys/vm/min_free_kbytes
sysctl vm.min_free_kbytes
```

**Set minimum free memory**:
```bash
# Calculate min_free_kbytes (1-5% of RAM)
# For 16GB RAM: 16GB * 0.01 = 16384KB (16MB)
# For 16GB RAM: 16GB * 0.05 = 81920KB (80MB)

# Set min_free_kbytes
echo 65536 | sudo tee /proc/sys/vm/min_free_kbytes

# Permanent configuration
echo 'vm.min_free_kbytes = 65536' | sudo tee -a /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
```

**Clear page cache** (temporary):
```bash
# Clear page cache
sync
echo 1 | sudo tee /proc/sys/vm/drop_caches

# Clear dentries and inodes
sync
echo 2 | sudo tee /proc/sys/vm/drop_caches

# Clear page cache, dentries, and inodes
sync
echo 3 | sudo tee /proc/sys/vm/drop_caches
```

**Recommendations for min_free_kbytes**:
| RAM Size | min_free_kbytes |
|-----------|-----------------|
| 4GB | 65536 (64MB) |
| 8GB | 131072 (128MB) |
| 16GB | 262144 (256MB) |
| 32GB | 524288 (512MB) |
| 64GB | 1048576 (1GB) |

### Verification
```bash
# Check min_free_kbytes
cat /proc/sys/vm/min_free_kbytes

# Check free memory
free -h
grep -E "MemFree|MemAvailable|Cached" /proc/meminfo

# Monitor page cache
watch -n 1 'grep -E "Cached|Buffers" /proc/meminfo'
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
More stable memory availability, reduced OOM risk

---

## NUMA Memory Allocation Tuning

### Description
Optimize NUMA memory allocation for better locality and performance.

### Applicable Bottlenecks
- NUMA imbalance (remote/local > 2:1)
- High memory latency
- Cross-node memory access

### Configuration Files
- /sys/kernel/mm/transparent_hugepage/defrag
- /proc/sys/vm/zone_reclaim_mode
- /etc/sysctl.conf

### Commands

**Check NUMA topology**:
```bash
numactl --hardware
lscpu | grep -i numa
```

**Check current NUMA policy**:
```bash
numastat
numastat -p <PID>
```

**Set NUMA policy for processes**:
```bash
# Run on specific node with local memory
numactl --cpunodebind=0 --membind=0 <command>

# Run on specific node with interleaved memory
numactl --interleave=all <command>

# Run with preferred node
numactl --preferred=0 <command>
```

**Enable zone reclaim mode**:
```bash
# Enable zone reclaim (local memory priority)
echo 1 | sudo tee /proc/sys/vm/zone_reclaim_mode

# Permanent configuration
echo 'vm.zone_reclaim_mode = 1' | sudo tee -a /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
```

**Zone reclaim modes**:
| Mode | Description |
|------|-------------|
| 0 | Disable (default) |
| 1 | Enable reclaim from local zone only |
| 2 | Enable reclaim and compaction |

**NUMA balancing**:
```bash
# Enable NUMA balancing
echo 1 | sudo tee /proc/sys/kernel/numa_balancing

# Check NUMA balancing status
cat /proc/sys/kernel/numa_balancing
```

### Verification
```bash
# Check NUMA statistics
numastat -p <PID>

# Monitor NUMA page migrations
watch -n 1 'numastat -p <PID>'

# Check memory locality
perf stat -e mem_loads,mem_stores,local_loads,remote_loads -p <PID> -- sleep 30
```

### Risk Level
Medium - Can affect performance on non-NUMA systems

### Expected Impact
10-40% improvement for NUMA-aware workloads
