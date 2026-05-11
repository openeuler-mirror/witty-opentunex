---
name: opentunex-os-optimization-enablement
description: OS-level optimization enablement verification skill. Provides configuration backup, performance baseline testing, optimization execution (batch/step-by-step), comprehensive benchmark testing, and rollback support. This skill is invoked after os-performance-optimization identifies bottlenecks and recommendations are approved.
---

# os-optimization-enablement — OS Optimization Enablement and Verification

This skill executes OS-level optimization enablement with the following phases:
1. **Configuration Backup**: Backup current configurations and create comparison baseline
2. **Performance Baseline Testing**: Establish baseline performance metrics before any optimizations
3. **Optimization Execution Mode Selection**: Choose between batch or step-by-step optimization mode
4. **Optimization Execution**: Apply OS-level optimizations using selected mode
5. **Comprehensive Benchmark Testing**: Validate overall system performance improvement
6. **Optimization Summary**: Summarize results, generate rollback scripts, and provide recommendations

**Prerequisite**: Run os-performance-optimization skill Phase 1 and Phase 2 first to identify bottlenecks and get optimization recommendations.

**Note**: This skill focuses on OS-level components only (kernel params, I/O scheduler, CPU, memory, network, filesystem).

---

## Client Connection and Command Execution

Load the remote-execution skill for standardized SSH connection and command execution:

skill:remote-execution

---

## Phase 1: Configuration Backup and Comparison

**Objective**: Before applying any optimization, backup current configurations and create comparison baseline.

### 1.1 Configuration Identification

For each approved optimization, identify all configuration files that will be modified:
```bash
sysctl -a | grep -E "vm.swappiness|vm.dirty_ratio|vm.vfs_cache_pressure"
cat /etc/sysctl.conf
cat /etc/sysctl.d/*.conf
cat /proc/cmdline
cat /proc/sys/vm/*
```

### 1.2 Configuration Backup

Execute the backup script on remote machine via remote-execution:

```bash
ssh ${username}@${ip} "bash -s" < scripts/backup_config.sh
ssh ${username}@${ip} "ls -la /opt/opentunex/backup/"
```

**Backup Script Location**: `scripts/backup_config.sh`

**What the script backs up (all on remote)**:
- sysctl current values
- /etc/sysctl.conf and /etc/sysctl.d/*.conf
- kernel cmdline (/proc/cmdline)
- vm parameters (/proc/sys/vm/*)
- I/O scheduler settings for all block devices
- backup manifest

**Backup Output Directory**: `/opt/opentunex/backup/$(date +%Y%m%d_%H%M%S)`

### 1.3 Configuration Comparison Display

For each optimization, display current vs proposed configuration changes:

```markdown
### Configuration Comparison: [Optimization Title]

**Files to modify**:
- /etc/sysctl.conf
- /etc/sysctl.d/99-optimization.conf

**Current Values**:
| Parameter | Current Value | Recommended Value | Reason |
|-----------|---------------|-------------------|--------|
| vm.swappiness | 60 | 10 | Reduce swapping frequency |
| vm.dirty_ratio | 30 | 15 | Reduce writeback latency |
| vm.vfs_cache_pressure | 100 | 50 | Increase inode/dentry cache |

**Change Impact**: 
- Files modified: 2
- Parameters changed: 3
- Risk level: Medium

**Backup Location**: ${BACKUP_DIR}/
```

**User Confirmation**: Display all configuration changes and ask user to confirm before proceeding.

---

## Phase 2: Performance Baseline Testing

**Objective**: Establish comprehensive baseline performance metrics before any optimizations are applied.

**IMPORTANT**: Run this phase BEFORE any optimization is applied.

### 2.1 Benchmark Method Selection

**Ask user to select baseline benchmark method**:

```markdown
### Baseline Benchmark Method Selection

**Please select baseline benchmark method**:

1. **System-wide stress test**
   - CPU: sysbench cpu --cpu-max-prime=20000 --threads=8 run
   - Memory: sysbench memory --memory-block-size=1K --memory-total-size=100G run
   - Disk: fio --name=randread --rw=randread --bs=4k --numjobs=8 --size=2G
   - Network: iperf3 -c <server_ip> -t 60

2. **Custom benchmark script**
   - Provide script path: _________

3. **User-guided benchmark**
   - You will manually run your benchmark
   - I will wait for your results

[User selects option]
```

### 2.2 Baseline Benchmark Execution

**Execute selected benchmark and collect comprehensive metrics**:

```bash
BASELINE_DIR="/opt/optimization-results/baseline_$(date +%Y%m%d_%H%M%S)"
ssh ${username}@${ip} "mkdir -p ${BASELINE_DIR}"

ssh ${username}@${ip} "sysbench cpu --cpu-max-prime=20000 --threads=8 run" | tee ${BASELINE_DIR}/cpu_baseline.txt
ssh ${username}@${ip} "sysbench memory --memory-block-size=1K --memory-total-size=100G run" | tee ${BASELINE_DIR}/memory_baseline.txt
ssh ${username}@${ip} "fio --name=randread --rw=randread --bs=4k --numjobs=8 --size=2G" | tee ${BASELINE_DIR}/disk_baseline.txt
ssh ${username}@${ip} "iperf3 -c <server_ip> -t 60" | tee ${BASELINE_DIR}/network_baseline.txt

ssh ${username}@${ip} "mpstat -P ALL 1 5" | tee ${BASELINE_DIR}/cpu_stats.txt
ssh ${username}@${ip} "vmstat 1 5" | tee ${BASELINE_DIR}/vm_stats.txt
ssh ${username}@${ip} "iostat -xz 1 5" | tee ${BASELINE_DIR}/io_stats.txt
ssh ${username}@${ip} "sar -n DEV 1 5" | tee ${BASELINE_DIR}/net_stats.txt

cat > ${BASELINE_DIR}/baseline_manifest.txt << EOF
Baseline Performance Test
Date: $(date)
Benchmark Method: [Selected method]
Baseline Directory: ${BASELINE_DIR}
Metrics Collected:
- CPU Performance
- Memory Performance
- Disk I/O Performance
- Network Performance
EOF
```

### 2.3 Baseline Metrics Collection

```markdown
### Baseline Metrics Summary

**System Metrics**:

#### CPU Performance
| Metric | Baseline Value | Unit |
|--------|---------------|-------|
| CPU Utilization | [Value] | % |
| Context Switches/sec | [Value] | cs/s |
| Interrupts/sec | [Value] | in/s |
| Load Average (1min) | [Value] | - |

#### Memory Performance
| Metric | Baseline Value | Unit |
|--------|---------------|-------|
| Total Memory | [Value] | GB |
| Used Memory | [Value] | GB |
| Swap Used | [Value] | GB |
| Page Faults/sec | [Value] | faults/s |

#### Disk I/O Performance
| Metric | Baseline Value | Unit |
|--------|---------------|-------|
| Read Throughput | [Value] | MB/s |
| Write Throughput | [Value] | MB/s |
| Random Read IOPS | [Value] | IOPS |
| Random Write IOPS | [Value] | IOPS |

#### Network Performance
| Metric | Baseline Value | Unit |
|--------|---------------|-------|
| Throughput | [Value] | Mbps |
| Retransmissions/sec | [Value] | retrans/s |
| TCP Connections | [Value] | count |
```

### 2.4 Baseline Result Verification

```markdown
### Baseline Result Verification

**Please verify baseline benchmark results**:

1. Results look correct - proceed
2. Results seem incorrect - re-run benchmark
3. Results incomplete - test with different workload
4. Benchmark failed - check errors

[User selects option]
```

---

## Phase 3: Optimization Execution Mode Selection

**Objective**: Let user choose between two optimization execution modes.

```markdown
### Optimization Execution Mode Selection

**Please select optimization execution mode**:

#### Mode 1: Apply All Optimizations Together
**Description**: Apply all approved OS-level optimizations at once, then run comprehensive benchmark.

**Advantages**: Faster execution, better testing of cumulative effects
**Disadvantages**: Cannot identify individual optimization impact

**Process**:
1. Apply all approved optimizations
2. Run comprehensive benchmark
3. Compare with baseline
4. Rollback entire set if ineffective

#### Mode 2: Apply Optimizations One by One
**Description**: Apply OS-level optimizations individually, testing each change separately.

**Advantages**: Clear visibility of each optimization's impact, easy to rollback
**Disadvantages**: Longer execution time, may miss cumulative effects

**Process**:
1. Pre-optimization benchmark
2. Apply single optimization
3. Post-optimization benchmark
4. Evaluate effectiveness
5. Keep or rollback based on results
6. Repeat for next optimization

**Your Choice**:
1. Mode 1: Apply all optimizations together
2. Mode 2: Apply optimizations one by one

[User selects mode]
```

**Mode Selection Logic**:
- If user selects **Mode 1**: Proceed to Phase 4.1 (Batch Optimization)
- If user selects **Mode 2**: Proceed to Phase 4.2 (Step-by-Step Optimization)

---

## Phase 4: Optimization Execution

**Objective**: Apply selected OS-level optimizations using the chosen execution mode.

### Phase 4.1: Mode 1 - Apply All Optimizations Together

**Use this mode when**: User selected Mode 1 in Phase 3

#### Step 1: Pre-Optimization Benchmark (Global Baseline)

```markdown
### Pre-Optimization Benchmark: Global Baseline

**Benchmark Request**: How would you like to execute performance tests?

Options:
1. Use built-in system stress tests (sysbench, fio, iperf)
2. Run custom benchmark script (provide script path)
3. Skip benchmark (use Phase 2 baseline)

[User selects option]
```

#### Step 2: Apply All Optimizations

**Apply all approved OS-level optimizations in one batch**:

```bash
cat > /tmp/batch_optimization.sh << 'EOF'
#!/bin/bash
echo "Applying OS-level optimizations..."

sysctl vm.swappiness=10
sysctl vm.dirty_ratio=15
sysctl vm.vfs_cache_pressure=50
sysctl net.ipv4.tcp_tw_reuse=1

for dev in /sys/block/sd*; do
    echo mq-deadline | tee $dev/queue/scheduler
done

echo "All OS-level optimizations applied"
EOF

ssh ${username}@${ip} "bash -s" < /tmp/batch_optimization.sh
```

**Permanent configuration**:

```bash
cat << EOF | ssh ${username}@${ip} "cat > /etc/sysctl.d/99-optimization.conf"
vm.swappiness = 10
vm.dirty_ratio = 15
vm.vfs_cache_pressure = 50
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_window_scaling = 1
EOF

ssh ${username}@${ip} "sysctl -p /etc/sysctl.d/99-optimization.conf"
```

#### Step 3: Verify All Optimizations Applied

```markdown
### Post-Optimization Verification: All Optimizations

| Parameter | Previous | Current | Status |
|-----------|----------|---------|--------|
| vm.swappiness | 60 | 10 | ✓ Applied |
| vm.dirty_ratio | 30 | 15 | ✓ Applied |
| vm.vfs_cache_pressure | 100 | 50 | ✓ Applied |
| tcp_tw_reuse | 0 | 1 | ✓ Applied |

**System Check**:
- sysctl values: [Verified]
- I/O scheduler: [Verified]
- Services stable: [Confirmed]
- Kernel log: [No errors]
```

#### Step 4: Post-Optimization Benchmark (Global)

```markdown
### Post-Optimization Benchmark: Global Results

**Benchmark Results**:
- CPU usage: X% (baseline: X% - Change: Y%)
- Memory usage: Y% (baseline: Y% - Change: Z%)
- I/O throughput: Z MB/s (baseline: Z MB/s - Change: +A%)
- Network throughput: W Mbps (baseline: W Mbps - Change: +B%)

**Performance Impact**: 
- Overall improvement: [Summary]
- Most improved metric: [Metric with largest gain]
- Any regressions: [Any negative impacts]
```

#### Step 5: Overall Effect Evaluation

```markdown
### Optimization Effect Summary: Batch Optimization

**Performance Improvement Summary**:
| Metric | Baseline | After | Change | % Change |
|--------|----------|-------|--------|----------|
| CPU Performance | [value] | [value] | [value] | [X%] |
| Memory Performance | [value] | [value] | [value] | [Y%] |
| Disk I/O Read | [value] | [value] | [value] | [Z%] |
| Disk I/O Write | [value] | [value] | [value] | [W%] |
| Network Throughput | [value] | [value] | [value] | [V%] |

**Overall Assessment**: 
- ✓ **KEEP ALL** - Optimizations are effective overall
- ✗ **ROLLBACK ALL** - Optimizations have negative impact
- ○ **INCONCLUSIVE** - Needs more testing

**User Decision**: Keep all or rollback?
1. Keep all optimizations
2. Rollback to original configuration

[User selects option]
```

#### Step 6: Rollback (if needed)

```bash
ssh ${username}@${ip} "cp ${BACKUP_DIR}/sysctl.conf.backup /etc/sysctl.conf"
ssh ${username}@${ip} "rm /etc/sysctl.d/99-optimization.conf"
ssh ${username}@${ip} "sysctl -p /etc/sysctl.conf"

for dev in /sys/block/sd*; do
    ssh ${username}@${ip} "echo deadline > $dev/queue/scheduler"
done
```

---

### Phase 4.2: Mode 2 - Apply Optimizations Step-by-Step

**Use this mode when**: User selected Mode 2 in Phase 3

**Objective**: Apply OS-level optimizations one by one, testing each change individually.

### 4.2.1 Optimization Execution Sequence

For each approved optimization (in priority order):

```markdown
### Pre-Optimization Benchmark: [Optimization Title]

**Benchmark Request**: How would you like to execute performance tests?

Options:
1. Use built-in system stress tests (sysbench, fio, iperf)
2. Run custom benchmark script (provide script path)
3. Skip benchmark for this optimization

[User selects option]
```

**Step 2: Apply Optimization**

**System Parameter Optimization (sysctl)**:
```bash
cat > /tmp/optimization.conf << 'EOF'
vm.swappiness = 10
vm.dirty_ratio = 15
vm.vfs_cache_pressure = 50
EOF

ssh ${username}@${ip} "cat > /etc/sysctl.d/99-optimization.conf" < /tmp/optimization.conf
ssh ${username}@${ip} "sysctl -p /etc/sysctl.d/99-optimization.conf"
ssh ${username}@${ip} "sysctl vm.swappiness vm.dirty_ratio vm.vfs_cache_pressure"
```

**I/O Scheduler Optimization**:
```bash
ssh ${username}@${ip} "cat /sys/block/sda/queue/scheduler"
ssh ${username}@${ip} "echo mq-deadline > /sys/block/sda/queue/scheduler"
ssh ${username}@${ip} "cat /sys/block/sda/queue/scheduler"
```

**CPU Affinity Optimization**:
```bash
ssh ${username}@${ip} "taskset -cp 0-3 <pid>"
ssh ${username}@${ip} "taskset -cp <pid>"
```

**Step 3: Post-Optimization Verification**

```markdown
### Post-Optimization Verification: [Optimization Title]

**Configuration Applied**:
| Parameter | Previous | Current | Status |
|-----------|----------|---------|--------|
| vm.swappiness | 60 | 10 | ✓ Applied |

**System Check**:
- sysctl values: [Verified]
- No errors in kernel log: [Checked]
- Services stable: [Confirmed]
```

**Step 4: Post-Optimization Benchmark**

```markdown
### Post-Optimization Benchmark: [Optimization Title]

**Benchmark Results**:
- CPU usage: X% (baseline: X% - Change: Y%)
- Memory usage: Y% (baseline: Y% - Change: Z%)
- I/O throughput: Z MB/s (baseline: Z MB/s - Change: +A%)
- Network throughput: W Mbps (baseline: W Mbps - Change: +B%)

**Performance Impact**: 
- Positive impact: [Improvements]
- Negative impact: [Any regressions]
- Overall assessment: [Effective/Ineffective/Mixed]
```

**Step 5: Effect Evaluation**

```markdown
### Optimization Effect Summary: [Optimization Title]

**Performance Improvement**:
- [Metric 1]: +X% [Positive/Negative/Neutral]
- [Metric 2]: +Y% [Positive/Negative/Neutral]

**Recommendation**: 
- ✓ **KEEP** - Optimization is effective
- ✗ **ROLLBACK** - Optimization has negative impact
- ○ **INCONCLUSIVE** - Needs more testing

**User Decision**: Keep or rollback?
1. Keep this optimization
2. Rollback to previous configuration
3. Defer decision, test more later

[User selects option]
```

### 4.2.2 Rollback Procedure (if needed)

```bash
ssh ${username}@${ip} "cp ${BACKUP_DIR}/sysctl.conf.backup /etc/sysctl.conf"
ssh ${username}@${ip} "rm /etc/sysctl.d/99-optimization.conf"
ssh ${username}@${ip} "sysctl -p /etc/sysctl.conf"
```

### 4.2.3 Repeat for Each Optimization

Execute Steps 1-5 for each approved optimization.

**Progress Tracking**:
```markdown
### Optimization Progress

| Optimization | Status | Effect | Decision |
|--------------|--------|--------|----------|
| OPT-001: [Title] | Completed | Effective | Kept |
| OPT-002: [Title] | Completed | Ineffective | Rolled back |
| OPT-003: [Title] | In progress | - | - |

**Completed**: [N]/[M] optimizations
**Effective**: [N] optimizations kept
**Rolled back**: [N] optimizations removed
```

---

## Phase 5: Comprehensive Benchmark Testing

**Objective**: After all optimizations are applied, perform comprehensive benchmark.

### 5.1 Benchmark Method Selection

```markdown
### Comprehensive Benchmark Testing

**Please select benchmark approach**:

1. **System-wide stress test**
   - CPU: sysbench cpu --cpu-max-prime=20000 --threads=8 run
   - Memory: sysbench memory --memory-block-size=1K --memory-total-size=100G run
   - Disk: fio --name=randread --rw=randread --bs=4k --numjobs=8 --size=2G
   - Network: iperf3 -c <server_ip> -t 60

2. **Custom benchmark script**
3. **User-guided benchmark**
4. **Skip comprehensive benchmark**

[User selects option]
```

### 5.2 Benchmark Execution

```markdown
### Comprehensive Benchmark Execution

**Benchmark Type**: [Selected type]

**Results**:

#### Pre-Optimization Baseline
| Metric | Value |
|--------|-------|
| CPU Performance | X ops/s |
| Memory Performance | Y MB/s |
| Disk I/O Read | Z MB/s |
| Disk I/O Write | W MB/s |
| Network | V Mbps |

#### Post-Optimization Performance
| Metric | Before | After | Change | % Improvement |
|--------|--------|-------|--------|---------------|
| CPU Performance | X ops/s | A ops/s | +B ops/s | +C% |
| Memory Performance | Y MB/s | D MB/s | +E MB/s | +F% |
| Disk I/O Read | Z MB/s | G MB/s | +H MB/s | +I% |
| Disk I/O Write | W MB/s | J MB/s | +K MB/s | +L% |
| Network | V Mbps | M Mbps | +N Mbps | +O% |

**Overall Assessment**: [Summary of improvements]
```

### 5.3 Benchmark Result Verification

```markdown
### Benchmark Result Verification

**Please verify the benchmark results**:

1. Results look correct - proceed
2. Results seem incorrect - re-run benchmark
3. Results inconclusive - test with different workload
4. Benchmark failed - check errors

[User selects option]
```

---

## Phase 6: Optimization Summary and Finalization

**Objective**: Summarize all OS-level optimizations, their effectiveness, and provide final recommendations.

### 6.1 Optimization Summary Table

```markdown
### Optimization Summary

| Optimization ID | Title | Priority | Applied | Effective | Performance Impact | Decision |
|----------------|-------|----------|---------|-----------|-------------------|----------|
| OPT-001 | Reduce vm.swappiness | High | ✓ Yes | ✓ Yes | +15% I/O throughput | Keep |
| OPT-002 | Tune dirty ratios | Medium | ✓ Yes | ✗ No | -5% I/O throughput | Rolled back |
| OPT-003 | I/O scheduler change | High | ✓ Yes | ✓ Yes | +25% random read | Keep |
| OPT-004 | CPU governor tuning | Medium | ✓ Yes | ✓ Yes | +10% compute | Keep |

**Total Applied**: 4 optimizations
**Total Effective**: 3 optimizations
**Total Rolled Back**: 1 optimization
**Net Performance Improvement**: +XX% overall
```

### 6.2 Final Configuration Display

```markdown
### Final System Configuration

**Active Optimizations**:

**System Parameters** (/etc/sysctl.d/99-optimization.conf):
```
vm.swappiness = 10
vm.dirty_ratio = 15
vm.vfs_cache_pressure = 50
net.ipv4.tcp_tw_reuse = 1
```

**I/O Scheduler**:
```
sda: mq-deadline
sdb: mq-deadline
```

**Backup Location**: ${BACKUP_DIR}/
**Rollback Available**: Yes - Restore with provided script
```

### 6.3 Rollback Script Generation

```bash
ssh ${username}@${ip} "cat > ${BACKUP_DIR}/rollback.sh" << 'EOF'
#!/bin/bash
echo "Rolling back OS-level optimizations..."

cp sysctl.conf.backup /etc/sysctl.conf
rm /etc/sysctl.d/99-optimization.conf 2>/dev/null || true
sysctl -p /etc/sysctl.conf

echo deadline > /sys/block/sda/queue/scheduler
echo deadline > /sys/block/sdb/queue/scheduler

echo "Rollback completed"
EOF

ssh ${username}@${ip} "chmod +x ${BACKUP_DIR}/rollback.sh"
```

### 6.4 Final Recommendations

```markdown
### Final Recommendations

**What worked well**:
- [Optimization 1]: +XX% improvement in [metric]
- [Optimization 2]: +YY% improvement in [metric]

**What didn't work**:
- [Optimization 3]: Caused regression, rolled back

**Future optimization opportunities**:
- Consider application-level optimization with application-optimization skill
- [Other OS-level suggestions]

**Monitoring recommendations**:
- Monitor these metrics: [metrics list]
- Set up alerts for: [alert conditions]

**Documentation**: All optimization details in /opt/optimization-results/
**Backup**: Complete backup at ${BACKUP_DIR}/
**Rollback**: Available at ${BACKUP_DIR}/rollback.sh
```

---

## Operational Notes

**CRITICAL REQUIREMENTS**:
1. **Always backup before modifying**: Never change configuration without backup
2. **Ask user before destructive operations**: Any command that could cause downtime needs explicit confirmation
3. **Benchmark before and after**: Establish baseline for each optimization
4. **Rollback ineffective changes**: Don't keep optimizations that hurt performance
5. **User confirms benchmark results**: Verify accuracy before making decisions
6. **Use ssh for all remote commands**: Follow remote-execution connection protocol

**Benchmark Verification**:
- Always ask user how to execute benchmark
- Allow user to provide custom benchmark scripts
- Confirm benchmark results with user before proceeding

**Configuration Safety**:
- Display current vs proposed values before applying
- Validate configuration syntax before applying
- Test rollback procedures before finalizing

**Rollback Support**:
- Always maintain ability to restore original configuration
- Provide clear rollback instructions
- Document rollback location and procedure

**Communication with User**:
- Present options clearly with trade-offs
- Explain risk levels for each optimization
- Ask for confirmation at critical steps
- Report results concisely with metrics
