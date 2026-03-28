---
name: java-benchmark
description: Java application benchmarking tools reference
---

# Java Application Benchmarking

**Tool**: JMeter, Gatling

**Description**: Java application performance testing tools

**Prerequisites**:
- Java application running
- JMeter or Gatling installed

**JMeter Installation**:
```bash
# Download JMeter
wget https://downloads.apache.org//jmeter/binaries/apache-jmeter-5.5.tgz
tar -xzf apache-jmeter-5.5.tgz

# Run JMeter
cd apache-jmeter-5.5/bin
./jmeter
```

**Gatling Installation**:
```bash
# Download Gatling
wget https://repo1.maven.org/maven2/io/gatling/gatling-bundle/3.9.3/gatling-bundle-3.9.3-bundle.zip
unzip gatling-bundle-3.9.3-bundle.zip

# Run Gatling
cd gatling-bundle-3.9.3
./bin/gatling.sh
```

## JMeter Test Plan

```xml
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0" jmeter="5.5">
  <hashTree>
    <TestPlan guiclass="TestPlanController" testclass="TestPlan" testname="My Test Plan">
      <elementProp name="TestPlan.comments">My API Performance Test</elementProp>
      <elementProp name="TestPlan.user_define_classname">org.apache.jmeter.control.gui.TestPlanGui</elementProp>
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <boolProp name="TestPlan.serialize_threadgroups">false</boolProp>
      <elementProp name="TestPlan.user_defined_variables">
        <collectionProp name="Arguments.arguments" elementType="Arguments">
          <collectionProp name="Arguments.user_defined_variables">
            <elementProp name="Variable" elementType="Variable" testname="BASE_URL">
              <stringProp name="Argument.name">BASE_URL</stringProp>
              <stringProp name="Argument.value">http://localhost:8080</stringProp>
            </elementProp>
          </collectionProp>
        </collectionProp>
      </elementProp>
      
      <ThreadGroup guiclass="ThreadGroup" testclass="ThreadGroup" testname="Thread Group">
        <intProp name="ThreadGroup.num_threads">100</intProp>
        <intProp name="ThreadGroup.ramp_time">0</intProp>
        <boolProp name="ThreadGroup.scheduler">true</boolProp>
        <stringProp name="ThreadGroup.duration">60</stringProp>
        <stringProp name="ThreadGroup.delay">0</stringProp>
        <boolProp name="ThreadGroup.same_user_on_next_iteration">true</boolProp>
        
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="HTTP Request">
          <stringProp name="HTTPSampler.domain">localhost</stringProp>
          <intProp name="HTTPSampler.port">8080</intProp>
          <stringProp name="HTTPSampler.path">/api/data</stringProp>
          <stringProp name="HTTPSampler.method">GET</stringProp>
          <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
          <stringProp name="HTTPSampler.embedded_url_re">http://${BASE_URL}/api/data</stringProp>
        </HTTPSamplerProxy>
      </ThreadGroup>
    </TestPlan>
  </hashTree>
</jmeterTestPlan>
```

## Gatling Simulation

```scala
import io.gatling.core.Predef._
import io.gatling.http.Predef._

class BasicSimulation extends Simulation {
  val httpProtocol = http
    .baseUrl("http://localhost:8080")
    .acceptHeader("application/json")

  val scn = scenario("Basic Simulation")
    .exec(http("request_1")
      .get("/api/data")
    )

  setUp(
    scn.inject(atOnceUsers(100))
  ).protocols(httpProtocol)
}
```

## Run JMeter

```bash
# Non-GUI mode
./jmeter -n -t test_plan.jmx -l results.jtl

# With report generation
./jmeter -n -t test_plan.jmx -l results.jtl -e -o report_output

# With properties
./jmeter -JBASE_URL=http://localhost:8080 -n -t test_plan.jmx -l results.jtl
```

## Run Gatling

```bash
# Run simulation
./bin/gatling.sh -s BasicSimulation

# With custom config
./bin/gatling.sh -s BasicSimulation -rf reports

# Headless mode
./bin/gatling.sh -s BasicSimulation -m
```

## Output Metrics

- Requests per second
- Response time (min, max, avg, p50, p95, p99)
- Success rate
- Error rate
- Throughput

## Output Parsing

Parse JMeter results (from CSV):

```bash
# Parse JMeter CSV results
parse_jmeter_output() {
    local csv_file="$1"
    
    # Calculate requests per second
    TOTAL_REQUESTS=$(tail -n +2 "$csv_file" | wc -l)
    DURATION=$(awk -F',' 'NR>1 {if($1>max) max=$1} END {print max/1000}' "$csv_file")
    RPS=$(echo "scale=2; $TOTAL_REQUESTS / $DURATION" | bc)
    
    # Calculate response time percentiles
    RESP_TIMES=$(awk -F',' 'NR>1 {print $1}' "$csv_file" | sort -n)
    P50=$(echo "$RESP_TIMES" | awk 'NR==(10/100 * NR)+1 {print $1/1000}')
    P95=$(echo "$RESP_TIMES" | awk 'NR==(95/100 * NR)+1 {print $1/1000}')
    P99=$(echo "$RESP_TIMES" | awk 'NR==(99/100 * NR)+1 {print $1/1000}')
    
    # Calculate success rate
    FAILED=$(grep -c "false" "$csv_file" || echo "0")
    SUCCESS=$(echo "$TOTAL_REQUESTS - $FAILED" | bc)
    SUCCESS_RATE=$(echo "scale=2; $SUCCESS * 100 / $TOTAL_REQUESTS" | bc)
}

RPS=$(cat /tmp/jmeter_rps.txt)
P50=$(cat /tmp/jmeter_p50.txt)
P95=$(cat /tmp/jmeter_p95.txt)
SUCCESS_RATE=$(cat /tmp/jmeter_success_rate.txt)
```

Parse Gatling results (from JSON report):

```bash
# Parse Gatling JSON report
parse_gatling_output() {
    local json_file="$1"
    
    RPS=$(grep -E "\"requestsPerSecond\"" "$json_file" | sed -E 's/.*:\s*([0-9]+\.[0-9]+).*/\1/')
    MEAN=$(grep -E "\"mean\"" "$json_file" | head -1 | sed -E 's/.*:\s*([0-9]+\.[0-9]+).*/\1/')
    P95=$(grep -E "\"percentile95\"" "$json_file" | sed -E 's/.*:\s*([0-9]+\.[0-9]+).*/\1/')
    P99=$(grep -E "\"percentile99\"" "$json_file" | sed -E 's/.*:\s*([0-9]+\.[0-9]+).*/\1/')
    ERROR_RATE=$(grep -E "\"errors\"" "$json_file" | sed -E 's/.*:\s*([0-9]+\.[0-9]+).*/\1/')
}

RPS=$(cat /tmp/gatling_rps.txt)
MEAN=$(cat /tmp/gatling_mean.txt)
P95=$(cat /tmp/gatling_p95.txt)
ERROR_RATE=$(cat /tmp/gatling_error_rate.txt)
```

**Extracted Metrics (JMeter)**:

| Metric | Variable | Description |
|--------|----------|-------------|
| RPS | `RPS` | Requests per second |
| P50 Latency | `P50` | 50th percentile response time (ms) |
| P95 Latency | `P95` | 95th percentile response time (ms) |
| Success Rate | `SUCCESS_RATE` | Percentage of successful requests |

**Extracted Metrics (Gatling)**:

| Metric | Variable | Description |
|--------|----------|-------------|
| RPS | `RPS` | Requests per second |
| Mean Latency | `MEAN` | Mean response time (ms) |
| P95 Latency | `P95` | 95th percentile response time (ms) |
| Error Rate | `ERROR_RATE` | Percentage of failed requests |

**Example Parsed Output**:
```markdown
### Java Application Benchmark Results

| Metric | Value |
|--------|-------|
| RPS | 5000.00 |
| Mean Latency | 15.5ms |
| P95 Latency | 45.2ms |
| Error Rate | 0.05% |
```
