---
name: opentunex-benchmark-execution
description: Application performance benchmark execution framework. Provides benchmark control, configuration, monitoring, and result storage for MySQL, Redis, PostgreSQL, Nginx, Java, and Go applications. Use with references/<app>.md for detailed tool usage.
---

# Benchmark Execution Framework

This skill provides application performance benchmark execution framework to ensure workload is running during system data collection.

## Application Benchmark References

Load specific benchmark tool documentation from `references/` directory:

| Application | Reference | Key Metrics |
|-------------|-----------|--------------|
| MySQL | [references/mysql.md](references/mysql.md) | QPS, latency, throughput |
| Redis | [references/redis.md](references/redis.md) | ops/sec, latency, hit rate |
| PostgreSQL | [references/postgres.md](references/postgres.md) | TPS, latency, connections |
| Nginx | [references/nginx.md](references/nginx.md) | req/sec, latency, throughput |
| Java | [references/java.md](references/java.md) | req/sec, response time, error rate |
| Go | [references/go.md](references/go.md) | ops/sec, memory, goroutines |

---

## Client Connection and Command Execution

Load the remote-execution skill for standardized SSH connection and command execution:

skill:remote-execution

---

## Benchmark Execution Flow

### Phase 0: Benchmark Configuration

**Ask user to configure benchmark**:

```markdown
### Benchmark Configuration

**IMPORTANT**: Please configure the performance benchmark that will run during system data collection.

**Step 1: Select Application to Benchmark**

1. MySQL
2. Redis
3. PostgreSQL
4. Nginx/Web Server
5. Java Application
6. Go Application
7. Skip benchmark (use existing workload)

[User selects option]

**Step 2: Select Benchmark Type**

1. Built-in benchmark (use default settings)
2. Custom benchmark script (provide script path)
3. Production workload simulation
4. Skip benchmark

[User selects option]

**Step 3: Configure Benchmark Duration**

1. 30 seconds (quick data collection)
2. 60 seconds (standard data collection)
3. 120 seconds (comprehensive data collection)
4. Custom duration: _______ seconds

[User selects option]

**Step 4: Configure Benchmark Load**

1. Low load (minimal impact)
2. Medium load (typical production)
3. High load (stress test)
4. Custom configuration

[User selects option]
```

**Benchmark Configuration Summary**:
- Application: [Selected Application]
- Benchmark Type: [Selected Type]
- Duration: [Selected Duration] seconds
- Load Level: [Selected Load]

---

### Phase 1: Start Benchmark in Background

**Start benchmark and let it run while collecting system data**:

```markdown
### Starting Performance Benchmark

**Starting benchmark with configuration**:
- Application: [Application]
- Benchmark Type: [Type]
- Duration: [Duration] seconds
- Load Level: [Load]

**Starting benchmark in background...**

Benchmark process started with PID: [PID]
Benchmark will run for [Duration] seconds
System data collection will start shortly

**Status**: Benchmark is running ✓

**Next Steps**:
1. System-Wide Information Collection will start
2. Benchmark will continue running during data collection
3. After data collection, benchmark will be stopped
```

**Start benchmark command**:
```bash
# Start benchmark in background
benchmark_command &
BENCHMARK_PID=$!

echo "Benchmark started with PID: $BENCHMARK_PID"
echo "Benchmark will run for specified duration"
```

---

### Phase 2: Benchmark Monitoring

**Monitor benchmark during system data collection**:

```bash
# Monitor benchmark process
BENCHMARK_PID=[benchmark_pid]

# Check if benchmark is still running
ps -p $BENCHMARK_PID

# Check benchmark output
tail -f /tmp/benchmark_output.log &

# Monitor application connections
netstat -an | grep ESTABLISHED | wc -l

# Monitor system load
top -b -n 1 | grep [application_name]
```

---

### Phase 3: Stop Benchmark

**Stop benchmark after system data collection is complete**:

```markdown
### Stopping Performance Benchmark

**Stopping benchmark process...**

Benchmark stopped
Benchmark duration: [actual duration]
Benchmark results saved to: /opt/benchmark-results/[timestamp]/

**Status**: Benchmark stopped ✓
```

**Stop benchmark command**:
```bash
# Stop benchmark process
kill $BENCHMARK_PID

# Wait for process to stop
wait $BENCHMARK_PID 2>/dev/null

# Verify benchmark stopped
ps -p $BENCHMARK_PID || echo "Benchmark stopped successfully"

# Collect benchmark results
cat /tmp/benchmark_output.log > /opt/benchmark-results/benchmark_output.txt
```

---

### Phase 4: Benchmark Status Check

**Check if benchmark is running before starting data collection**:

```markdown
### Benchmark Status Check

**Checking benchmark status...**

Current Status:
- Benchmark PID: [PID]
- Benchmark Running: [Yes/No]
- Time Elapsed: [elapsed time]

**Action**:
- If benchmark is running: ✓ Proceed to system data collection
- If benchmark stopped: Restart benchmark or skip
- If benchmark failed: Check logs and restart
```

**Verification command**:
```bash
# Check if benchmark process exists and is running
if ps -p $BENCHMARK_PID > /dev/null; then
    echo "Benchmark is running"
    exit 0
else
    echo "Benchmark is NOT running"
    exit 1
fi
```

---

## Benchmark Result Storage

```bash
# Create benchmark results directory
BENCHMARK_DIR="/opt/benchmark-results/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BENCHMARK_DIR

# Save benchmark output
echo "Benchmark completed" > $BENCHMARK_DIR/benchmark_summary.txt
echo "Application: [App Name]" >> $BENCHMARK_DIR/benchmark_summary.txt
echo "Tool: [Tool Name]" >> $BENCHMARK_DIR/benchmark_summary.txt
echo "Duration: [Duration]" >> $BENCHMARK_DIR/benchmark_summary.txt

# Save benchmark output
cp benchmark_output.txt $BENCHMARK_DIR/

# Create benchmark manifest
cat > $BENCHMARK_DIR/benchmark_manifest.txt << 'EOF'
Benchmark Execution
Date: $(date)
Application: [App Name]
Benchmark Type: [Type]
Tool: [Tool Name]
Duration: [Duration seconds]
Output Files:
  - benchmark_output.txt
  - benchmark_summary.txt
EOF
```

---

## Benchmark Output Parsing

After benchmark execution, parse the output log file to extract performance metrics.

**For each application**, load the corresponding reference file to get the parsing commands:

| Application | Output Parsing Reference |
|-------------|-------------------------|
| MySQL | [references/mysql.md#output-parsing](references/mysql.md#output-parsing) |
| Redis | [references/redis.md#output-parsing](references/redis.md#output-parsing) |
| PostgreSQL | [references/postgres.md#output-parsing](references/postgres.md#output-parsing) |
| Nginx | [references/nginx.md#output-parsing](references/nginx.md#output-parsing) |
| Java | [references/java.md#output-parsing](references/java.md#output-parsing) |
| Go | [references/go.md#output-parsing](references/go.md#output-parsing) |

### Output Parsing Flow

```bash
# Step 1: Save benchmark output to file
ssh ${username}@${ip} "cat /tmp/benchmark_output.log" > /tmp/benchmark_output.txt

# Step 2: Copy output file to results directory
cp /tmp/benchmark_output.txt $BENCHMARK_DIR/

# Step 3: Parse based on application type
case "$APP_TYPE" in
    mysql)
        parse_mysqlslap_output /tmp/benchmark_output.txt
        ;;
    redis)
        parse_redis_output /tmp/benchmark_output.txt "SET"
        ;;
    postgres)
        parse_pgbench_output /tmp/benchmark_output.txt
        ;;
    nginx)
        parse_ab_output /tmp/benchmark_output.txt
        ;;
    java)
        parse_jmeter_output /tmp/jmeter_results.csv
        ;;
    go)
        parse_go_output /tmp/go_benchmark.txt
        ;;
esac

# Step 4: Display parsed metrics
echo "=== Benchmark Performance Metrics ==="
cat $BENCHMARK_DIR/parsed_metrics.txt
```

### Parsed Metrics Output Format

Present parsed metrics to user in structured markdown format:

```markdown
### Benchmark Performance Metrics

**Application**: [App Name]
**Tool**: [Benchmark Tool]
**Duration**: [X seconds]

| Metric | Value | Unit |
|--------|-------|------|
| [Metric 1] | [Value] | [Unit] |
| [Metric 2] | [Value] | [Unit] |
| [Metric 3] | [Value] | [Unit] |

**Raw Output**: Saved to `$BENCHMARK_DIR/benchmark_output.txt`
**Parsed Metrics**: Saved to `$BENCHMARK_DIR/parsed_metrics.txt`
```

---

## Common Issues and Solutions

### Issue 1: Connection refused
**Solution**: Check if application is running, verify port, check firewall

### Issue 2: Authentication failed
**Solution**: Verify credentials, check user permissions

### Issue 3: Out of memory during benchmark
**Solution**: Reduce concurrent clients, reduce data size, increase heap size

### Issue 4: CPU saturation at 100%
**Solution**: Reduce load, use fewer clients, check for infinite loops

---

## Additional Resources

- [MySQL Benchmarking](https://dev.mysql.com/doc/refman/8.0/en/mysqlslap.html)
- [Redis Benchmarking](https://redis.io/topics/benchmarks)
- [PostgreSQL Benchmarking](https://www.postgresql.org/docs/current/pgbench.html)
- [Apache Bench](https://httpd.apache.org/docs/2.4/programs/ab.html)
- [wrk](https://github.com/wg/wrk)
- [Gatling](https://gatling.io/docs/current/)
- [JMeter](https://jmeter.apache.org/usermanual/index.html)
- [Go Benchmarking](https://golang.org/pkg/testing/)
