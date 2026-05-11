# Process Scheduling Trace Analysis Skill

## Overview

This skill provides comprehensive analysis of process scheduling behavior using Linux perf tools. It helps diagnose scheduling-related performance issues by analyzing:

- **Scheduling out frequency**: How often the target process is being preempted or yields CPU
- **Scheduling in latency**: Time delay from when process becomes runnable to when it actually gets CPU
- **Preempting tasks**: Which tasks are competing for CPU time and causing scheduling interference
- **Global scheduling analysis**: System-wide scheduling perspective to understand overall CPU time distribution

## Use Cases

Use this skill when you need to:

1. Investigate why a process is experiencing high latency or poor throughput
2. Identify which tasks are competing with a critical process for CPU time
3. Analyze scheduling patterns to understand system behavior
4. Diagnose scheduling-related performance issues
5. Optimize process priority, affinity, or NUMA placement

## Prerequisites

- Linux system with perf tool installed (kernel >= 3.10 recommended)
- Root access or sufficient permissions to use perf and modify scheduler stats
- Target process PID known (for process-specific analysis)

## Quick Start

### For Process-Specific Analysis

```bash
# Load the skill
skill process-schedule-trace-analysis

# Collect scheduling trace for a specific process (e.g., Redis with PID 1234)
./scripts/collect_sched_trace.sh 1234 -d 60

# Analyze the collected data
./scripts/analyze_sched_trace.sh /tmp/sched_trace_20231201_120000 1234

# View the report
cat /tmp/sched_trace_20231201_120000/analysis/analysis_report.md
```

### For System-Wide Analysis

```bash
# Load the skill
skill process-schedule-trace-analysis

# Collect system-wide scheduling trace
./scripts/collect_sched_trace.sh -d 60

# Analyze all processes
./scripts/analyze_sched_trace.sh /tmp/sched_trace_20231201_120000 all

# View the report
cat /tmp/sched_trace_20231201_120000/analysis/analysis_report.md
```

## Workflow

The skill follows a structured workflow:

### Phase 1: Target Process Identification
- Identify target process by name or PID
- Collect process information (priority, affinity, threads)
- Verify system environment (perf availability, scheduler stats)

### Phase 2: Scheduling Trace Data Collection
- Use `perf sched record` to capture scheduling events
- Configure collection duration based on analysis needs
- Verify data quality and completeness

### Phase 3: Scheduling Out Frequency Analysis
- Count how often target process is scheduled out
- Compare with system average
- Identify abnormal patterns

### Phase 4: Scheduling In Latency Analysis
- Measure time from wake-up to schedule-in
- Calculate latency distribution (P50, P90, P95, P99)
- Identify outliers and causes

### Phase 5: Preempting Tasks Analysis (Global Perspective)
- Analyze global CPU time distribution
- Identify top preemptors and their impact
- Categorize preemptors by type (kernel, system, applications)

### Phase 6: Comprehensive Report Generation
- Generate detailed analysis report
- Provide actionable recommendations
- Document findings and evidence

## Script Reference

### collect_sched_trace.sh

Collects scheduling trace data for analysis.

**Usage:**
```bash
./scripts/collect_sched_trace.sh [PID] [options]
```

**Arguments:**
- `PID`: Target process PID (optional, system-wide if not specified)

**Options:**
- `-d, --duration SECONDS`: Collection duration (default: 60)
- `-o, --output DIR`: Output directory (default: /tmp/sched_trace_<timestamp>)
- `-h, --help`: Show help message

**Examples:**
```bash
# Collect for PID 1234 for 60 seconds
./scripts/collect_sched_trace.sh 1234

# Collect for 120 seconds with custom output
./scripts/collect_sched_trace.sh 1234 -d 120 -o /tmp/mytrace

# Collect system-wide for 30 seconds
./scripts/collect_sched_trace.sh -d 30
```

**Output Files:**
- `perf.data`: Raw scheduling trace data
- `process_info.txt`: Target process information
- `threads.txt`: Thread information
- `lscpu.txt`: CPU topology
- `numa_info.txt`: NUMA configuration
- `sched_latency.txt`: Preliminary latency analysis
- `sched_timehist.txt`: Time history of events
- `sched_map.txt`: Scheduling map
- `sched_script.txt`: Detailed scheduling script
- `summary.txt`: Collection summary

### analyze_sched_trace.sh

Analyzes collected scheduling trace data.

**Usage:**
```bash
./scripts/analyze_sched_trace.sh <input_dir> [PID] [options]
```

**Arguments:**
- `input_dir`: Directory containing collected trace data
- `PID`: Target process PID (optional, 'all' for system-wide)

**Options:**
- `-o, --output DIR`: Output directory for analysis results
- `-d, --duration SECONDS`: Collection duration (for frequency calculation)
- `-h, --help`: Show help message

**Examples:**
```bash
# Analyze specific process
./scripts/analyze_sched_trace.sh /tmp/sched_trace_20231201_120000 1234

# Analyze all processes
./scripts/analyze_sched_trace.sh /tmp/sched_trace_20231201_120000 all

# Analyze with custom output directory
./scripts/analyze_sched_trace.sh /tmp/sched_trace_20231201_120000 1234 -o /tmp/myanalysis
```

**Output Files:**
- `sched_out_target.txt`: Target process scheduling out statistics
- `timehist_target.txt`: Target process latency time history
- `latency_target.txt`: Target process latency analysis
- `cpu_time_distribution.txt`: Global CPU time distribution
- `preemptors_frequency.txt`: Preemptor frequency analysis
- `preemptor_analysis.txt`: Preemptor categorization
- `analysis_report.md`: Comprehensive analysis report

## Understanding the Results

### Scheduling Out Frequency

**Normal Ranges:**
- CPU-intensive workloads: 10-100 events/second
- I/O-intensive workloads: 100-1000 events/second
- System average baseline: varies by workload

**Interpretation:**
- **Low (< normal)**: Process may be getting starved or not running enough
- **Normal**: Expected behavior
- **High (> 2x system average)**: Process is being preempted frequently, investigate preemptors

### Scheduling In Latency

**Normal Ranges:**
- Average: < 5ms
- P90: < 10ms
- P99: < 50ms
- Max: < 100ms
- Outliers (>100ms): Should be 0

**Interpretation:**
- **Low latency**: Good, minimal scheduling delay
- **Elevated latency**: May indicate high CPU load or competition
- **High latency (> thresholds)**: Investigate preemptors and system load
- **Outliers**: May indicate occasional resource contention or priority issues

### Preempting Tasks Analysis

**Key Metrics:**
- **Global CPU%**: Total CPU time consumed by each task
- **Preempt count**: How many times each task runs before target
- **Category**: Kernel, System Service, or Application

**Interpretation:**
- **Kernel tasks**: Essential system tasks (ksoftirqd, migration). Monitor if excessive.
- **System services**: Background services (systemd, sshd). Consider adjusting priority.
- **Applications**: Other user processes. May need to reschedule or optimize.

**Warning Signs:**
- Single preemptor with >20% CPU time
- Single preemptor causing >50% of preemptions
- Kernel tasks consuming excessive CPU (indicates interrupt storm or other issues)

## Common Issues and Solutions

### Issue: High Scheduling Out Frequency

**Possible Causes:**
- Too many runnable processes competing for CPU
- Short time slices
- Real-time tasks preempting normal tasks

**Solutions:**
- Reduce number of competing processes
- Increase time slice (tunable via /proc/sys/kernel/sched_*)
- Adjust task priorities

### Issue: High Scheduling In Latency

**Possible Causes:**
- High CPU load (loadavg > CPU_count)
- Too many runnable processes per CPU
- CPU affinity issues
- Real-time tasks monopolizing CPU

**Solutions:**
- Reduce system load
- Set appropriate CPU affinity
- Adjust task priorities
- Use cgroups for CPU isolation

### Issue: Frequent Preemption by Specific Task

**Possible Causes:**
- Misconfigured task priorities
- Inappropriate real-time priorities
- No CPU isolation for critical workloads

**Solutions:**
- Audit and adjust task priorities
- Use `nice` and `renice` for priority adjustment
- Use `taskset` for CPU affinity
- Configure cgroups for isolation

### Issue: NUMA-Related Issues

**Possible Causes:**
- Poor memory locality
- Process frequently migrating between NUMA nodes
- Insufficient NUMA node resources

**Solutions:**
- Use `numactl` for NUMA binding
- Enable NUMA balancing
- Adjust CPU and memory affinity

## Advanced Usage

### Custom Event Selection

```bash
# Record specific scheduling events
perf sched record -a -e sched:sched_switch -e sched:sched_wakeup -- sleep 60

# Record all sched events (more data)
perf sched record -a -e sched:* -- sleep 60
```

### Interactive Analysis

```bash
# Real-time monitoring
perf sched latency

# View scheduling map
perf sched map

# Trace scheduling events in real-time
perf sched script
```

### Time Window Analysis

```bash
# Analyze specific time window
perf sched script --start 1234567890.000000 --stop 1234567950.000000
```

## References

- `references/bottleneck.md`: Detailed bottleneck analysis guide
- `SKILL.md`: Complete skill documentation and workflow

## Notes

- Collection duration impacts analysis accuracy: longer collections provide better statistics
- System-wide collection uses more disk space and CPU overhead
- Root privileges are required for comprehensive analysis
- Large trace files (>1GB) may require significant memory for analysis

## Support

For issues or questions, refer to:
- SKILL.md for detailed workflow documentation
- references/bottleneck.md for bottleneck analysis guidelines
- perf man pages for detailed tool documentation
