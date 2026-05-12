---
name: mysql-benchmark
description: MySQL benchmarking tool reference
---

# MySQL Benchmarking

**Tool**: mysqlslap

**Description**: MySQL load emulator and client

**Prerequisites**:
- MySQL server running
- mysqlslap tool installed (part of mysql-client package)
- Test database and queries available

**Installation**:
```bash
# Debian/Ubuntu
apt-get install mysql-client

# RHEL/CentOS
yum install mysql

# From source
wget https://dev.mysql.com/get/Downloads/MySQL-Cluster/mysql-cluster-7.5.7.tar
tar -xzf mysql-cluster-7.5.7.tar
cd mysql-cluster-7.5.7
mkdir build && cd build
cmake ..
make
make install
```

## Benchmark Commands

```bash
# Simple read benchmark
mysqlslap \
  --host=localhost \
  --user=root \
  --password=pass \
  --number-of-queries=1000 \
  --query="SELECT * FROM test_table WHERE id = %s"

# Mixed read/write benchmark
mysqlslap \
  --host=localhost \
  --user=root \
  --password=pass \
  --concurrency=50 \
  --iterations=100 \
  --query=test_query.sql

# Auto-generate SQL (schema)
mysqlslap \
  --host=localhost \
  --user=root \
  --password=pass \
  --concurrency=100 \
  --iterations=10 \
  --auto-generate-sql \
  --auto-generate-sql-execute-number=10000

# Read-only from schema
mysqlslap \
  --host=localhost \
  --user=root \
  --password=pass \
  --concurrency=50 \
  --iterations=100 \
  --only-print \
  --create-schema=testdb
```

## Output Metrics

- Average number of queries per second (QPS)
- Average latency
- Min/Max latency
- Standard deviation
- Total time
- Number of clients

## Example Output

```
Benchmark
  Running for engine mysql
  Average number of seconds to run all queries: 15.123 seconds
  Average number of queries per second: 66.123
  Min: 0.05 seconds
  Max: 0.25 seconds
  Standard deviation: 0.05 seconds
```

## Example Query File (test_query.sql)

```sql
SELECT * FROM users WHERE id = %s;
SELECT * FROM orders WHERE user_id = %s;
SELECT COUNT(*) FROM products WHERE category_id = %s;
```

## Output Parsing

Parse mysqlslap output to extract performance metrics:

```bash
# Parse mysqlslap output
parse_mysqlslap_output() {
    local log_file="$1"
    
    grep -E "Average number of queries per second|Average number of seconds|Min:|Max:|Standard deviation" "$log_file" | \
    sed -E 's/.*queries per second:\s*(.*)/\1/' > /tmp/mysql_qps.txt
    
    grep "Average number of seconds to run" "$log_file" | \
    sed -E 's/.*seconds to run all queries:\s*(.*) seconds/\1/' > /tmp/mysql_avg_time.txt
    
    grep "^  Min:" "$log_file" | sed -E 's/.*Min:\s*(.*) seconds/\1/' > /tmp/mysql_min_latency.txt
    grep "^  Max:" "$log_file" | sed -E 's/.*Max:\s*(.*) seconds/\1/' > /tmp/mysql_max_latency.txt
}

# Extract metrics into variables
QPS=$(grep -E "[0-9]+\.[0-9]+" /tmp/mysql_qps.txt | head -1)
AVG_TIME=$(cat /tmp/mysql_avg_time.txt)
MIN_LATENCY=$(cat /tmp/mysql_min_latency.txt)
MAX_LATENCY=$(cat /tmp/mysql_max_latency.txt)
```

**Extracted Metrics**:

| Metric | Variable | Description |
|--------|----------|-------------|
| QPS | `QPS` | Queries per second |
| Avg Time | `AVG_TIME` | Average execution time (seconds) |
| Min Latency | `MIN_LATENCY` | Minimum query latency (seconds) |
| Max Latency | `MAX_LATENCY` | Maximum query latency (seconds) |

**Example Parsed Output**:
```markdown
### MySQL Benchmark Results

| Metric | Value |
|--------|-------|
| QPS | 66.123 |
| Avg Time | 15.123s |
| Min Latency | 0.05s |
| Max Latency | 0.25s |
```
