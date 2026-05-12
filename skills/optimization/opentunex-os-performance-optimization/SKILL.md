---
name: opentunex-os-performance-optimization
description: OS-level performance optimization analysis for Linux kernel, lib libraries, generic services, and process affinity tuning. Uses top-down-bottleneck analysis to identify OS-level bottlenecks and propose optimization strategies. This skill only performs bottleneck analysis and recommendation - use os-optimization-enablement skill to actually apply optimizations. Does NOT optimize application-layer components - use application-optimization skill for that.
---

# os-performance-optimization — Operating System Performance Optimization

This skill performs OS-level performance analysis and optimization recommendation with the following phases:
1. **Bottleneck Analysis**: Use top-down-bottleneck skill to identify OS-level performance issues
2. **Optimization Recommendation**: Propose OS-level optimization strategies based on identified bottlenecks
3. **Proceed to Enablement**: Ask user if they want to apply optimizations via os-optimization-enablement skill

**Note**: This skill focuses exclusively on OS-level components:
- Kernel parameters (sysctl)
- I/O scheduler tuning
- Memory management (hugepages, swappiness, transparent hugepages)
- CPU tuning (governor, affinity, cgroups, NUMA)
- Network stack tuning (TCP parameters, buffers)
- Process scheduling and CPU isolation
- Filesystem mount options and parameters
- Generic system services

**For applying optimizations**, use the `os-optimization-enablement` skill after this analysis.

**For application-level optimizations** (MySQL, Redis, PostgreSQL, Kafka, Nginx, MongoDB, Java, Go), use the `application-optimization` skill instead.

---

## Client Connection and Command Execution

Load the remote-execution skill for standardized SSH connection and command execution:

skill:remote-execution

---

## Phase 1: Bottleneck Analysis

**Objective**: Identify OS-level performance bottlenecks using the top-down-bottleneck skill.

Load and execute the top-down-bottleneck skill to gather comprehensive system data:
```
Load the top-down-bottleneck skill and execute all phases.
```

**Note**: For application-level bottleneck analysis, use the `application-bottleneck` skill instead. This OS-performance-optimization skill does not analyze application internals.

---

**Output**: Complete bottleneck analysis report with identified OS-level issues, severity levels, and evidence.

---

## Phase 2: Optimization Recommendation

**Objective**: Propose specific OS-level optimization strategies based on identified bottlenecks.

For each bottleneck identified in Phase 1, recommend corresponding optimizations from the optimization library in `references/optimizations/`:

### Optimization Categories (OS-Level Only)

| Bottleneck Category | Optimization Strategies | Reference |
|---------------------|------------------------|-----------|
| CPU Compute | CPU affinity tuning, cgroup limits, governor adjustment | [cpu.md](references/optimizations/cpu.md) |
| CPU Context Switch | Process priority adjustment, interrupt handling, tickless kernel | [cpu.md](references/optimizations/cpu.md) |
| Memory Pressure | Swappiness adjustment, vm parameters, transparent hugepages | [memory.md](references/optimizations/memory.md) |
| Memory Fragmentation | Hugepages configuration, slab tuning | [memory.md](references/optimizations/memory.md) |
| Disk I/O | I/O scheduler tuning, elevator selection, readahead | [disk.md](references/optimizations/disk.md) |
| Network | TCP tuning, buffer sizes, connection tracking | [network.md](references/optimizations/network.md) |
| Filesystem | Mount options, filesystem parameters | [disk.md](references/optimizations/disk.md) |

### 2.1 System Environment Check

**CRITICAL**: Before recommending optimizations, perform comprehensive system environment check to ensure all recommended optimizations are applicable and not already enabled.

**Check Objectives**:
- Verify kernel version supports required features
- Check if required tools are installed
- Verify hardware supports optimization features
- Check current configuration status
- Filter out already enabled optimizations
- Filter out incompatible optimizations

**Environment Check Commands**:

```bash
# 1. Kernel version check
uname -r
# Required: >= 3.10 for most optimizations
# Check for specific features: grep -E "CONFIG_[FEATURE]=y" /boot/config-$(uname -r)

# 2. Check available CPU features
lscpu | grep -E "Flags|Model name|CPU(s)"
cat /proc/cpuinfo | grep flags | head -1

# 3. Check memory information
free -h
grep -E "MemTotal|SwapTotal|HugePages|Transparent" /proc/meminfo

# 4. Check disk information
lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINT,MODEL,ROTA
cat /sys/block/sda/queue/scheduler
cat /sys/block/sda/queue/rotational
cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null || echo "No NVMe device"

# 5. Check filesystem information
df -Th
mount | grep -E "^/dev"
tune2fs -l /dev/sda1 2>/dev/null | grep -i "Filesystem features" || xfs_info /dev/sda1 2>/dev/null || btrfs filesystem df / 2>/dev/null || echo "Other filesystem"

# 6. Check network information
ethtool eth0 2>/dev/null || ip link show
sysctl net.ipv4.tcp_available_congestion_control
cat /proc/sys/net/ipv4/tcp_congestion_control

# 7. Check current system parameters
sysctl -a | grep -E "vm.swappiness|vm.dirty|vm.vfs_cache_pressure|net.ipv4.tcp|net.core.rmem|net.core.wmem"

# 8. Check installed tools
which sysbench fio iperf3 perf bc 2>/dev/null || echo "Some benchmark tools not installed"
```

**Optimization Enablement Check for Each Category**:

#### CPU Optimizations Check

```bash
# CPU Governor check
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null && echo "CPU governor available" || echo "CPU governor not available (may be fixed-frequency CPU)"

# Available governors check
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null || echo "Governor control not available"

# C-states check
ls -1 /sys/devices/system/cpu/cpu0/cpuidle/ | grep state | wc -l
# If > 0, C-states are available

# Hyper-threading check
lscpu | grep -i "thread(s) per core"
# If > 1, hyper-threading is available and enabled

# NUMA check
numactl --hardware 2>/dev/null && echo "NUMA available" || echo "NUMA not available"

# Transparent Huge Pages check
cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null && echo "THP available" || echo "THP not available"
```

#### Memory Optimizations Check

```bash
# Swappiness check
cat /proc/sys/vm/swappiness
# Current value (if already at recommended, skip recommendation)

# Huge Pages check
cat /proc/sys/vm/nr_hugepages
grep -i "HugePages" /proc/meminfo
# Check if huge pages are already configured

# Transparent Huge Pages check
cat /sys/kernel/mm/transparent_hugepage/enabled
# Check current THP setting

# Memory overcommit check
cat /proc/sys/vm/overcommit_memory
# Check current overcommit mode
```

#### Disk I/O Optimizations Check

```bash
# I/O scheduler check
for dev in /sys/block/*/queue/scheduler; do
    echo "$dev: $(cat $dev)"
done
# Check available schedulers for each device

# Read-ahead check
for dev in /sys/block/*/queue/read_ahead_kb; do
    echo "$dev: $(cat $dev)"
done

# Filesystem mount options check
mount | grep -E "^/dev"
# Check current mount options

# Disk type check (SSD vs HDD)
for dev in /sys/block/*/queue/rotational; do
    if [ "$(cat $dev)" = "0" ]; then
        echo "${dev%/*}: SSD (non-rotational)"
    else
        echo "${dev%/*}: HDD (rotational)"
    fi
done
```

#### Network Optimizations Check

```bash
# Available congestion control algorithms
sysctl net.ipv4.tcp_available_congestion_control
# Check which algorithms are available

# Current congestion control
sysctl net.ipv4.tcp_congestion_control
# Check if already using recommended algorithm

# TCP window scaling check
sysctl net.ipv4.tcp_window_scaling
# Check if already enabled

# TCP Fast Open check
cat /proc/sys/net/ipv4/tcp_fastopen
# Check current TFO setting

# Connection tracking check
ls /proc/sys/net/netfilter/nf_conntrack_* 2>/dev/null && echo "Connection tracking available" || echo "Connection tracking not available (firewall may be disabled)"
```

### 2.2 Optimization Filtering

**Filtering Logic**:

For each optimization identified from bottleneck analysis:

1. **Check Enablement**:
   - Is the feature supported by the kernel?
   - Is the required hardware available?
   - Are the required tools installed?

2. **Check Current Status**:
   - Is the optimization already enabled?
   - Is the current value already at the recommended value?

3. **Filter Out**:
   - Optimizations that cannot be enabled on this system
   - Optimizations that are already enabled
   - Optimizations where current value matches recommended value

**Filtering Example**:

```bash
# Example: Swappiness optimization
CURRENT_SWAPPINESS=$(cat /proc/sys/vm/swappiness)
RECOMMENDED_SWAPPINESS=10

if [ "$CURRENT_SWAPPINESS" = "$RECOMMENDED_SWAPPINESS" ]; then
    echo "SKIP: vm.swappiness already at recommended value ($RECOMMENDED_SWAPPINESS)"
else
    echo "KEEP: vm.swappiness optimization needed (current: $CURRENT_SWAPPINESS, recommended: $RECOMMENDED_SWAPPINESS)"
fi

# Example: I/O scheduler optimization
DEVICE=/dev/sda
CURRENT_SCHEDULER=$(cat /sys/block/sda/queue/scheduler | awk '{print $1}')
RECOMMENDED_SCHEDULER="mq-deadline"

if echo "$CURRENT_SCHEDULER" | grep -q "$RECOMMENDED_SCHEDULER"; then
    echo "SKIP: I/O scheduler already set to $RECOMMENDED_SCHEDULER"
else
    echo "KEEP: I/O scheduler optimization needed (current: $CURRENT_SCHEDULER, recommended: $RECOMMENDED_SCHEDULER)"
fi

# Example: TCP congestion control
AVAILABLE_ALGOS=$(sysctl -n net.ipv4.tcp_available_congestion_control)
CURRENT_ALGO=$(sysctl -n net.ipv4.tcp_congestion_control)
RECOMMENDED_ALGO="bbr"

if ! echo "$AVAILABLE_ALGOS" | grep -q "$RECOMMENDED_ALGO"; then
    echo "SKIP: $RECOMMENDED_ALGO not available on this system"
    echo "Available algorithms: $AVAILABLE_ALGOS"
elif [ "$CURRENT_ALGO" = "$RECOMMENDED_ALGO" ]; then
    echo "SKIP: TCP congestion control already set to $RECOMMENDED_ALGO"
else
    echo "KEEP: TCP congestion control optimization needed (current: $CURRENT_ALGO, recommended: $RECOMMENDED_ALGO)"
fi
```

### 2.3 Filtered Recommendation Format

After filtering, present only applicable optimizations:

```markdown
### Phase 2: Optimization Recommendation

**System Environment Check**: [Summary of system capabilities]

**Optimization Filtering Results**:
- Total potential optimizations: [N]
- Optimizations filtered out (not applicable): [N]
- Optimizations filtered out (already enabled): [N]
- OS-level optimizations recommended: [N]

---

### Applicable Optimizations (OS-Level Only)

#### Optimization [ID]: [Title]
**Target Bottleneck**: [Bottleneck from Phase 1]
**Priority**: [Critical/High/Medium/Low]
**Risk Level**: [Low/Medium/High]
**Estimated Impact**: [High/Medium/Low]
**Configuration Files**: 
  - [File 1]: [Path]
  - [File 2]: [Path]
**Current Value**: [Current configuration value]
**Recommended Value**: [Recommended value]
**Change Required**: [Yes/No]
**Reason for Recommendation**: [Why this optimization is needed]
**Pre-conditions**: [Verified: Met/Not Met]
**Post-verification**: [How to verify it worked]
```

**Filtered Out Optimizations** (for transparency):

```markdown
### Optimizations Not Recommended

#### Already Enabled
| Optimization | Current Value | Recommended Value | Reason |
|-------------|---------------|-------------------|---------|
| vm.swappiness | 10 | 10 | Already at recommended value |
| tcp_tw_reuse | 1 | 1 | Already enabled |

#### Not Applicable to Current System
| Optimization | Reason |
|-------------|---------|
| BBR congestion control | BBR not available in this kernel |
| NUMA tuning | System is not NUMA-aware |

#### Application-Specific (Not in Scope)
| Optimization | Reason |
|-------------|---------|
| MySQL tuning | Use application-optimization skill |
| Redis tuning | Use application-optimization skill |
```

### Recommendation Format

For each recommended optimization (after filtering):
```markdown
### Optimization [ID]: [Title]
**Target Bottleneck**: [Bottleneck from Phase 1]
**Priority**: [Critical/High/Medium/Low]
**Risk Level**: [Low/Medium/High]
**Estimated Impact**: [High/Medium/Low]
**Configuration Files**: 
  - [File 1]: [Path]
  - [File 2]: [Path]
**Description**: [What this optimization does]
**Pre-conditions**: [Any requirements]
**Post-verification**: [How to verify it worked]
```

**User Confirmation**: Present all recommendations to user and ask which optimizations to apply. Allow user to select specific optimizations or approve all.

---

## Phase 3: Proceed to Optimization Enablement

**Objective**: After reviewing optimization recommendations, ask user if they want to proceed with applying optimizations.

```markdown
### Optimization Recommendation Summary

**System Environment Check**: [Summary of system capabilities from Phase 2.1]

**Optimization Filtering Results**:
- Total potential optimizations: [N]
- Optimizations filtered out (not applicable): [N]
- Optimizations filtered out (already enabled): [N]
- OS-level optimizations recommended: [N]

**Approved Optimizations for Application**:
| Optimization ID | Title | Priority | Risk Level |
|----------------|-------|----------|------------|
| OPT-001 | [Title] | High | Low |
| OPT-002 | [Title] | Medium | Medium |
| OPT-003 | [Title] | High | Low |

---

### Proceed to Optimization Enablement?

**You have completed the analysis phase. Would you like to proceed with applying the optimizations?**

**Option 1**: Proceed with optimization enablement
- Load the `os-optimization-enablement` skill
- This will backup current configuration
- Establish performance baseline
- Apply optimizations (batch or step-by-step mode)
- Run comprehensive benchmark testing
- Generate rollback scripts

**Option 2**: Skip optimization for now
- Keep the analysis results
- No changes will be made to the system
- You can re-run this analysis later

**Option 3**: Modify optimization list
- Go back and adjust which optimizations to apply
- Re-run filtering with different parameters

[User selects option]
```

**If user selects Option 1**:
```
Load the os-optimization-enablement skill with the approved optimizations list from Phase 2.
```

**If user selects Option 2**:
```
End the optimization session. All analysis results are documented.
```

**If user selects Option 3**:
```
Return to Phase 2.2 and adjust optimization filtering criteria.
```

---

## Scope Clarification

**This skill (os-performance-optimization) focuses on OS-level analysis and recommendation ONLY:**

| Included (OS-Level) | Excluded (Application-Level) |
|---------------------|------------------------------|
| Kernel parameters (sysctl) | MySQL configuration |
| I/O scheduler tuning | Redis configuration |
| Memory management (hugepages, THP) | PostgreSQL configuration |
| CPU governor and affinity | Nginx configuration |
| Network stack tuning | Kafka configuration |
| Filesystem mount options | MongoDB configuration |
| Process scheduling | Java/JVM tuning |
| cgroups and namespaces | Go runtime tuning |
| NUMA placement | Application-specific queries |

**For applying optimizations, use `os-optimization-enablement` skill.**

**For application-level optimizations, use `application-optimization` skill.**

---

## Operational Notes

**CRITICAL REQUIREMENTS**:
1. **Always check system environment first**: Verify all recommended optimizations are applicable to the current system before proposing them
2. **Filter out incompatible optimizations**: Never recommend optimizations that cannot work on the current hardware/kernel
3. **Filter out already-enabled optimizations**: Avoid wasting time on configurations that are already optimal
4. **Present options clearly**: User chooses whether to proceed with enablement
5. **Use ssh for all remote commands**: Follow remote-execution connection protocol

**Environment Check and Filtering**:
- **Always perform system environment check** before recommending optimizations
- **Check kernel version** to ensure required features are supported
- **Verify hardware capabilities** (CPU flags, NUMA, SSD/HDD, etc.)
- **Check current configuration values** to avoid redundant optimizations
- **Filter out incompatible optimizations** that cannot work on current system
- **Filter out already-enabled optimizations** to save time
- **Provide transparency** by showing what was filtered out and why
- **Document system capabilities** for future reference

**Communication with User**:
- Present options clearly with trade-offs
- Explain risk levels for each optimization
- Ask for confirmation at critical steps
- Report results concisely with metrics
- Allow user to skip or defer optimizations
