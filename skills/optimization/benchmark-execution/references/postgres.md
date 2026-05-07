---
name: postgres-benchmark
description: PostgreSQL benchmarking tool reference
---

# PostgreSQL Benchmarking

**Tool**: pgbench

**Description**: PostgreSQL benchmark tool

**Prerequisites**:
- PostgreSQL server running
- pgbench tool installed (part of postgresql-contrib package)

**Installation**:
```bash
# Debian/Ubuntu
apt-get install postgresql-contrib

# RHEL/CentOS
yum install postgresql-contrib
```

## Benchmark Commands

```bash
# Initialize benchmark database
pgbench -h localhost -U postgres -d benchdb -i 5 -s 100000

# Simple benchmark
pgbench -h localhost -U postgres -d benchdb -c 10 -t 60

# Multiple clients
pgbench -h localhost -U postgres -d benchdb -c 50 -T 300

# With custom script
cat > my_bench.sql << 'EOF'
\set nbranches :random(1, 10000) * :scale;
\set naccounts :random(1, 100000) * :scale;
\set aid :random(1, 100000 * :scale);
SELECT abalance FROM pg_accounts WHERE aid = :aid;
EOF

pgbench -h localhost -U postgres -d benchdb -f my_bench.sql -c 10 -t 60 -j 2

# TPC-B like workload
pgbench -h localhost -U postgres -d benchdb -c 32 -j 32 -T 600

# Report only (no output to stdout)
pgbench -h localhost -U postgres -d benchdb -c 10 -T 60 -o summary
```

## Output Metrics

- Transactions per second (TPS)
- Latency (average, min, max, p50, p95, p99)
- Connections used
- Total transactions
- Failed transactions
- SQL latency

## Example Output

```
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 10
number of threads: 1
duration: 60 s
number of transactions actually processed: 850000
latency average = 0.705 ms
latency stddev = 0.603 ms
tps = 1416.666667 (including connections establishing)
tps = 1421.223924 (excluding connections establishing)
```

## Output Parsing

Parse pgbench output to extract performance metrics:

```bash
# Parse pgbench output
parse_pgbench_output() {
    local log_file="$1"
    
    grep "^latency average" "$log_file" | \
    sed -E 's/.*=\s*([0-9]+\.[0-9]+).*/\1/' > /tmp/pg_latency_avg.txt
    
    grep "^latency stddev" "$log_file" | \
    sed -E 's/.*=\s*([0-9]+\.[0-9]+).*/\1/' > /tmp/pg_latency_stddev.txt
    
    grep "^tps =" "$log_file" | head -1 | \
    sed -E 's/tps = ([0-9]+\.[0-9]+).*/\1/' > /tmp/pg_tps.txt
    
    grep "number of transactions actually processed" "$log_file" | \
    sed -E 's/.*:\s*([0-9]+).*/\1/' > /tmp/pg_total_tx.txt
    
    grep "number of clients" "$log_file" | head -1 | \
    sed -E 's/.*:\s*([0-9]+).*/\1/' > /tmp/pg_clients.txt
    
    grep "^duration" "$log_file" | \
    sed -E 's/duration:\s*([0-9]+).*/\1/' > /tmp/pg_duration.txt
}

# Extract metrics into variables
LATENCY_AVG=$(cat /tmp/pg_latency_avg.txt)
LATENCY_STDDEV=$(cat /tmp/pg_latency_stddev.txt)
TPS=$(cat /tmp/pg_tps.txt)
TOTAL_TX=$(cat /tmp/pg_total_tx.txt)
CLIENTS=$(cat /tmp/pg_clients.txt)
DURATION=$(cat /tmp/pg_duration.txt)
```

**Extracted Metrics**:

| Metric | Variable | Description |
|--------|----------|-------------|
| TPS | `TPS` | Transactions per second |
| Latency Avg | `LATENCY_AVG` | Average transaction latency (ms) |
| Latency Stddev | `LATENCY_STDDEV` | Latency standard deviation (ms) |
| Total Tx | `TOTAL_TX` | Total transactions processed |
| Clients | `CLIENTS` | Number of concurrent clients |
| Duration | `DURATION` | Test duration (seconds) |

**Example Parsed Output**:
```markdown
### PostgreSQL Benchmark Results

| Metric | Value |
|--------|-------|
| TPS | 1416.67 |
| Latency Avg | 0.705ms |
| Latency Stddev | 0.603ms |
| Total Transactions | 850000 |
| Clients | 10 |
| Duration | 60s |
```
