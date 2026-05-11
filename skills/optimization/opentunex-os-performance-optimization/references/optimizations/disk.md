# Disk I/O Optimization Strategies

## I/O Scheduler Tuning

### Description
Change the I/O scheduler to optimize for specific workload characteristics.

### Applicable Bottlenecks
- Disk I/O bottleneck (%util > 90%, await > 20ms)
- High I/O latency
- Sequential vs random I/O mismatch

### Configuration Files
- /sys/block/<device>/queue/scheduler
- /etc/udev/rules.d/60-schedulers.rules

### Commands

**Check current scheduler**:
```bash
# Check all devices
cat /sys/block/*/queue/scheduler

# Check specific device
cat /sys/block/sda/queue/scheduler

# Check available schedulers
cat /sys/block/sda/queue/scheduler
```

**Set I/O scheduler**:
```bash
# Set scheduler (temporary)
echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler
echo none | sudo tee /sys/block/nvme0n1/queue/scheduler

# Set scheduler for all block devices
for dev in /sys/block/sd*; do
    echo mq-deadline | sudo tee $dev/queue/scheduler
done
```

**Permanent scheduler configuration** (udev rules):
```bash
# Create udev rule
cat << EOF | sudo tee /etc/udev/rules.d/60-schedulers.rules
# Set deadline scheduler for HDD
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="deadline"

# Set none scheduler for NVMe SSD
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"

# Set mq-deadline for non-rotational (SATA SSD)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
EOF

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

**I/O schedulers**:
| Scheduler | Description | Best For |
|-----------|-------------|-----------|
| none | No scheduler (kernel bypass) | NVMe SSDs, high-end SSDs |
| mq-deadline | Multi-queue deadline | SATA SSDs, mixed workloads |
| deadline | Deadline scheduler | HDDs, mixed workloads |
| cfq | Completely Fair Queueing | Default, general purpose |
| bfq | Budget Fair Queueing | Desktop, interactive workloads |
| kyber | Multi-queue low latency | Flash storage |

### Verification
```bash
# Check scheduler
cat /sys/block/sda/queue/scheduler

# Monitor I/O performance
iostat -x 1 5

# Test with fio
fio --name=randread --rw=randread --bs=4k --numjobs=1 --size=1G --iodepth=32
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
10-30% improvement in I/O performance for appropriate workloads

---

## Read-Ahead Tuning

### Description
Adjust read-ahead size to optimize sequential read performance.

### Applicable Bottlenecks
- Sequential read workload
- High read latency
- Insufficient read-ahead

### Configuration Files
- /sys/block/<device>/queue/read_ahead_kb

### Commands

**Check current read-ahead**:
```bash
# Check all block devices
cat /sys/block/*/queue/read_ahead_kb

# Check specific device
cat /sys/block/sda/queue/read_ahead_kb
```

**Set read-ahead size**:
```bash
# Set read-ahead to 128KB
echo 128 | sudo tee /sys/block/sda/queue/read_ahead_kb

# Set read-ahead to 512KB (for large sequential reads)
echo 512 | sudo tee /sys/block/sda/queue/read_ahead_kb

# Set read-ahead to 0 (disable for random I/O)
echo 0 | sudo tee /sys/block/sda/queue/read_ahead_kb
```

**Permanent configuration** (systemd tmpfile):
```bash
cat << EOF | sudo tee /etc/tmpfiles.d/readahead.conf
# Set read-ahead for sda
w /sys/block/sda/queue/read_ahead_kb - - - - 128
EOF
```

**Recommended values**:
| Workload | Read-ahead (KB) |
|----------|-----------------|
| Database (OLTP) | 8-16 |
| Database (OLAP) | 256-512 |
| File server | 128-256 |
| Desktop | 64-128 |
| SSD (general) | 32-64 |
| HDD (sequential) | 256-512 |
| Random I/O | 0-8 |

### Verification
```bash
# Check read-ahead
cat /sys/block/sda/queue/read_ahead_kb

# Monitor read performance
iostat -x 1 5

# Test with hdparm
hdparm -tT /dev/sda
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
5-20% improvement for sequential read workloads

---

## I/O Queue Depth Tuning

### Description
Adjust I/O queue depth to optimize throughput and latency.

### Applicable Bottlenecks
- High I/O throughput requirements
- Latency vs throughput trade-offs
- NVMe/SAS storage optimization

### Configuration Files
- /sys/block/<device>/queue/nr_requests
- /sys/block/<device>/queue/iosched/fifo_batch (for deadline)
- /sys/block/<device>/queue/iosched/quantum (for cfq)

### Commands

**Check current queue depth**:
```bash
# Check queue depth
cat /sys/block/sda/queue/nr_requests

# Check device maximum queue depth
cat /sys/block/sda/queue/max_hw_sectors_kb
```

**Set queue depth**:
```bash
# Set queue depth (nr_requests)
echo 128 | sudo tee /sys/block/sda/queue/nr_requests
echo 256 | sudo tee /sys/block/sda/queue/nr_requests
echo 512 | sudo tee /sys/block/sda/queue/nr_requests
```

**Scheduler-specific tuning**:
```bash
# For deadline scheduler
cat /sys/block/sda/queue/iosched/fifo_batch
echo 16 | sudo tee /sys/block/sda/queue/iosched/fifo_batch

# For cfq scheduler
cat /sys/block/sda/queue/iosched/quantum
echo 8 | sudo tee /sys/block/sda/queue/iosched/quantum
```

**Permanent configuration** (systemd tmpfile):
```bash
cat << EOF | sudo tee /etc/tmpfiles.d/queue_depth.conf
# Set queue depth for sda
w /sys/block/sda/queue/nr_requests - - - - 256
EOF
```

**Recommended values**:
| Device Type | nr_requests |
|-------------|-------------|
| HDD | 128-256 |
| SATA SSD | 256-512 |
| NVMe SSD | 512-1024 |
| SAS SSD | 256-512 |

### Verification
```bash
# Check queue depth
cat /sys/block/sda/queue/nr_requests

# Monitor I/O queue depth
iostat -x 1 5

# Check in-flight I/O
cat /proc/diskstats | awk '{print $1, $12}'
```

### Risk Level
Low-Medium - Can increase latency if too high

### Expected Impact
5-15% improvement in I/O throughput

---

## Filesystem Mount Options

### Description
Optimize filesystem mount options for specific workloads.

### Applicable Bottlenecks
- Filesystem performance bottleneck
- High metadata operations
- Data integrity vs performance trade-offs

### Configuration Files
- /etc/fstab

### Commands

**Check current mount options**:
```bash
# Check all mounts
mount

# Check specific mount
mount | grep /home
findmnt /home
```

**Remount with new options**:
```bash
# Remount with noatime (disable access time updates)
mount -o remount,noatime /home

# Remount with nodiratime (disable directory access time)
mount -o remount,noatime,nodiratime /home

# Remount with data=writeback (ext4)
mount -o remount,data=writeback /home

# Remount with commit=30 (ext4 - commit interval)
mount -o remount,commit=30 /home
```

**Permanent configuration** (edit /etc/fstab):
```bash
# Backup fstab
cp /etc/fstab /etc/fstab.backup

# Edit fstab
# Example: /dev/sda1 /home ext4 defaults,noatime,nodiratime,commit=30 0 2
```

**Common mount options**:
| Option | Description | Use Case |
|--------|-------------|----------|
| noatime | Disable access time updates | Most workloads |
| nodiratime | Disable directory access time | High metadata workloads |
| data=writeback | Async metadata writes (ext4) | Performance-critical |
| data=ordered | Sync metadata before data (ext4) | Default, safer |
| journal_async_commit | Async journal commit (ext4) | Performance |
| commit=30 | Commit every 30s (ext4) | Reduced I/O |
| nobarrier | Disable write barriers | SSDs with battery backup |
| discard | Enable TRIM | SSDs |
| nodelalloc | Disable delayed allocation | Database workloads |

**Filesystem-specific tuning**:

**Ext4**:
```bash
# Check current options
tune2fs -l /dev/sda1 | grep -i options

# Set mount options
tune2fs -o journal_async_commit /dev/sda1
```

**XFS**:
```bash
# Check current options
xfs_info /dev/sda1

# Mount options for XFS
mount -o noatime,allocsize=4M,inode64 /dev/sda1 /mnt
```

**Btrfs**:
```bash
# Mount options for Btrfs
mount -o noatime,compress=lzo,ssd /dev/sda1 /mnt
```

### Verification
```bash
# Check mount options
mount | grep /home
findmnt /home

# Monitor filesystem performance
iostat -x 1 5
df -h /home
```

### Risk Level
Medium - data=writeback can risk data loss on power failure

### Expected Impact
10-40% improvement for file-intensive workloads

---

## Filesystem Alignment Tuning

### Description
Ensure filesystem alignment with physical sectors for optimal performance.

### Applicable Bottlenecks
- Suboptimal I/O performance
- Misaligned partitions
- Advanced Format (4K sector) drives

### Configuration Files
- /etc/fstab

### Commands

**Check disk sector size**:
```bash
# Check logical sector size
cat /sys/block/sda/queue/logical_block_size

# Check physical sector size
cat /sys/block/sda/queue/physical_block_size

# Check partition alignment
fdisk -l /dev/sda
```

**Check filesystem alignment**:
```bash
# Check ext4 alignment
tune2fs -l /dev/sda1 | grep -i block

# Check XFS alignment
xfs_db -c "sb" -c "print" /dev/sda1 | grep -i blocksize
```

**Create aligned filesystem**:
```bash
# Create ext4 with 4K alignment
mkfs.ext4 -b 4096 -E stride=128,stripe-width=256 /dev/sda1

# Create XFS with 4K alignment
mkfs.xfs -d su=128k,sw=2 -b size=4096 /dev/sda1
```

**RAID alignment**:
```bash
# For RAID 5 with 128K stripe
mkfs.ext4 -b 4096 -E stride=32,stripe-width=64 /dev/md0
# stride = chunk_size / block_size = 128K / 4K = 32
# stripe_width = stride * (n_disks - 1) = 32 * 2 = 64

# For RAID 10 with 128K stripe
mkfs.ext4 -b 4096 -E stride=32,stripe-width=128 /dev/md0
# stripe_width = stride * n_disks = 32 * 4 = 128
```

### Verification
```bash
# Check filesystem alignment
tune2fs -l /dev/sda1 | grep -i block

# Test with fio
fio --name=align_test --rw=randread --bs=4k --numjobs=1 --size=1G --iodepth=32
```

### Risk Level
Low - Requires filesystem recreation for existing systems

### Expected Impact
5-15% improvement for RAID systems with misaligned partitions

---

## I/O Throttling (cgroup)

### Description
Use cgroups to limit I/O bandwidth for specific processes.

### Applicable Bottlenecks
- I/O contention between processes
- Need to prioritize critical workloads
- Limit background I/O impact

### Configuration Files
- /sys/fs/cgroup/blkio/...
- /etc/systemd/system/*.service

### Commands

**Check cgroup version**:
```bash
mount | grep cgroup
```

**cgroup v1 (blkio)**:
```bash
# Create cgroup
mkdir /sys/fs/cgroup/blkio/limited_io

# Set I/O limits (read: 10MB/s)
echo "8:0 10485760" | sudo tee /sys/fs/cgroup/blkio/limited_io/blkio.throttle.read_bps_device

# Set I/O limits (write: 5MB/s)
echo "8:0 5242880" | sudo tee /sys/fs/cgroup/blkio/limited_io/blkio.throttle.write_bps_device

# Set IOPS limits (read: 1000 IOPS)
echo "8:0 1000" | sudo tee /sys/fs/cgroup/blkio/limited_io/blkio.throttle.read_iops_device

# Add process to cgroup
echo <PID> | sudo tee /sys/fs/cgroup/blkio/limited_io/cgroup.procs
```

**cgroup v2 (io)**:
```bash
# Create cgroup
mkdir /sys/fs/cgroup/limited_io

# Set I/O limits
echo "8:0 rbps=10485760 wbps=5242880" | sudo tee /sys/fs/cgroup/limited_io/io.max

# Add process to cgroup
echo <PID> | sudo tee /sys/fs/cgroup/limited_io/cgroup.procs
```

**systemd service limits**:
```bash
# Create/modify service file
cat << EOF | sudo tee /etc/systemd/system/myapp.service
[Unit]
Description=My Application

[Service]
ExecStart=/usr/bin/myapp
IOReadBandwidthMax=/dev/sda 10M
IOWriteBandwidthMax=/dev/sda 5M
IOReadIOPSMax=/dev/sda 1000
IOWriteIOPSMax=/dev/sda 500

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload
systemctl enable myapp
```

### Verification
```bash
# Check cgroup limits
cat /sys/fs/cgroup/blkio/limited_io/blkio.throttle.read_bps_device
cat /sys/fs/cgroup/limited_io/io.max

# Monitor I/O
iostat -x 1 5
pidstat -d 1 5
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
Better I/O isolation, predictable performance

---

## Swap Device Configuration

### Description
Optimize swap device configuration for better performance.

### Applicable Bottlenecks
- High swap usage causing performance degradation
- Poor swap device placement
- Need for emergency swap

### Configuration Files
- /etc/fstab

### Commands

**Check swap configuration**:
```bash
# Check swap devices
cat /proc/swaps
swapon --show

# Check swap usage
free -h
swapon --summary
```

**Check swap priority**:
```bash
cat /proc/swaps
# Priority column shows swap priority (higher = preferred)
```

**Set swap priority**:
```bash
# Disable swap
swapoff /dev/sdb1

# Re-enable with priority
swapon -p 100 /dev/sdb1
```

**Create swap file**:
```bash
# Create 4GB swap file
dd if=/dev/zero of=/swapfile bs=1G count=4
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Set priority
swapon -p 50 /swapfile

# Permanent configuration
echo "/swapfile none swap sw,pri=50 0 0" | sudo tee -a /etc/fstab
```

**Optimize swappiness**:
```bash
# Reduce swappiness (see memory.md)
sysctl vm.swappiness=10
echo 'vm.swappiness = 10' | sudo tee -a /etc/sysctl.conf
```

**Swap recommendations**:
| Scenario | Swap Size | Priority |
|----------|-----------|----------|
| Desktop | 2-4GB | Medium |
| Server (no hibernate) | 1-2GB | Low |
| Database server | 0-1GB | Lowest |
| Swap on SSD | Minimal | Low |
| Swap on HDD | 2-4GB | Medium |

### Verification
```bash
# Check swap
cat /proc/swaps
free -h

# Monitor swap usage
watch -n 1 'cat /proc/swaps; free -h'
```

### Risk Level
Low - Reversible, minimal risk

### Expected Impact
Reduced performance impact when swap is used

---

## Disk Scheduling with ionice

### Description
Use ionice to set I/O scheduling priority for processes.

### Applicable Bottlenecks
- I/O contention between processes
- Need to prioritize critical I/O
- Background I/O interference

### Configuration Files
- None (runtime configuration)

### Commands

**Check ionice priority**:
```bash
# Check process I/O priority
ionice -p <PID>

# Check all processes
ionice -c 1 -p <PID>  # Real-time
ionice -c 2 -n 0 -p <PID>  # Best effort, highest priority
ionice -c 2 -n 7 -p <PID>  # Best effort, lowest priority
ionice -c 3 -p <PID>  # Idle
```

**Set ionice priority**:
```bash
# Set I/O priority (requires root)
ionice -c 2 -n 0 -p <PID>

# Run command with I/O priority
ionice -c 2 -n 0 <command>

# Real-time I/O priority (use carefully)
ionice -c 1 -n 0 <command>

# Idle I/O priority
ionice -c 3 <command>
```

**I/O priority classes**:
| Class | Description | Use Case |
|-------|-------------|----------|
| 1: Real-time | Highest priority, can starve others | Critical database I/O |
| 2: Best-effort | Default scheduling (0-7 priority levels) | General purpose |
| 3: Idle | Only runs when no other I/O | Background tasks |

**systemd integration**:
```bash
# Create/modify service file
cat << EOF | sudo tee /etc/systemd/system/myapp.service
[Unit]
Description=My Application

[Service]
ExecStart=/usr/bin/myapp
IOSchedulingClass=2
IOSchedulingPriority=0

[Install]
WantedBy=multi-user.target
EOF
```

### Verification
```bash
# Check I/O priority
ionice -p <PID>

# Monitor I/O
iostat -x 1 5
pidstat -d 1 5
```

### Risk Level
Medium - Real-time priority can starve other processes

### Expected Impact
Better I/O isolation, predictable performance for critical processes
